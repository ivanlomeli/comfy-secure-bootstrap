#!/usr/bin/env bash
# Fase 2 — Log forwarding a un destino remoto (para que un atacante que borre
# /var/log no pueda cubrir sus huellas).
#
# Opciones:
#   A) CloudWatch Logs (si CLOUDWATCH_LOG_GROUP set)
#   B) Loki push (si LOKI_URL set)
#   C) Remote syslog (si REMOTE_SYSLOG set, formato: udp://host:port)
#
# Sin ninguna variable de entorno, sale sin cambios.
set -euo pipefail

CONFIGURED=0

# ============================================================
# A) CloudWatch Logs — requiere IAM role con logs:PutLogEvents
# ============================================================
if [ -n "${CLOUDWATCH_LOG_GROUP:-}" ]; then
  echo "[78-logs] configurando CloudWatch agent → grupo $CLOUDWATCH_LOG_GROUP"
  # Instalar CloudWatch agent
  cd /tmp
  curl -fsSL https://s3.us-west-2.amazonaws.com/amazoncloudwatch-agent-us-west-2/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o cw.deb
  dpkg -i cw.deb || apt-get -y -f install

  # Config: enviar auditd, ssh, ufw, journal, aide, kern
  cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
  "agent": {"metrics_collection_interval": 60, "run_as_user": "cwagent"},
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {"file_path": "/var/log/auth.log", "log_group_name": "${CLOUDWATCH_LOG_GROUP}", "log_stream_name": "{instance_id}/auth"},
          {"file_path": "/var/log/audit/audit.log", "log_group_name": "${CLOUDWATCH_LOG_GROUP}", "log_stream_name": "{instance_id}/audit"},
          {"file_path": "/var/log/syslog", "log_group_name": "${CLOUDWATCH_LOG_GROUP}", "log_stream_name": "{instance_id}/syslog"},
          {"file_path": "/var/log/kern.log", "log_group_name": "${CLOUDWATCH_LOG_GROUP}", "log_stream_name": "{instance_id}/kernel"},
          {"file_path": "/var/log/ufw.log", "log_group_name": "${CLOUDWATCH_LOG_GROUP}", "log_stream_name": "{instance_id}/ufw"},
          {"file_path": "/var/log/aide/*.log", "log_group_name": "${CLOUDWATCH_LOG_GROUP}", "log_stream_name": "{instance_id}/aide"},
          {"file_path": "/var/log/fail2ban.log", "log_group_name": "${CLOUDWATCH_LOG_GROUP}", "log_stream_name": "{instance_id}/fail2ban"}
        ]
      }
    }
  }
}
EOF
  systemctl enable --now amazon-cloudwatch-agent
  CONFIGURED=1
fi

# ============================================================
# B) Loki (Grafana)
# ============================================================
if [ -n "${LOKI_URL:-}" ]; then
  echo "[78-logs] configurando promtail → $LOKI_URL"
  wget -qO /usr/local/bin/promtail.zip \
    "https://github.com/grafana/loki/releases/latest/download/promtail-linux-amd64.zip"
  unzip -qo /usr/local/bin/promtail.zip -d /usr/local/bin/
  mv /usr/local/bin/promtail-linux-amd64 /usr/local/bin/promtail
  chmod +x /usr/local/bin/promtail

  cat >/etc/promtail.yaml <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0
positions:
  filename: /var/lib/promtail-positions.yaml
clients:
  - url: ${LOKI_URL}/loki/api/v1/push
scrape_configs:
  - job_name: system
    static_configs:
      - targets: [localhost]
        labels:
          job: varlogs
          host: $(hostname)
          __path__: /var/log/{auth,syslog,kern,ufw,fail2ban}*.log
  - job_name: audit
    static_configs:
      - targets: [localhost]
        labels:
          job: auditd
          host: $(hostname)
          __path__: /var/log/audit/*.log
EOF

  cat >/etc/systemd/system/promtail.service <<'EOF'
[Unit]
Description=Promtail log shipper
After=network.target
[Service]
ExecStart=/usr/local/bin/promtail --config.file=/etc/promtail.yaml
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now promtail
  CONFIGURED=1
fi

# ============================================================
# C) Remote syslog
# ============================================================
if [ -n "${REMOTE_SYSLOG:-}" ]; then
  echo "[78-logs] configurando rsyslog forward → $REMOTE_SYSLOG"
  proto=$(echo "$REMOTE_SYSLOG" | cut -d: -f1)  # udp o tcp
  hostport=$(echo "$REMOTE_SYSLOG" | sed 's|.*://||')
  sym='@'
  [ "$proto" = "tcp" ] && sym='@@'
  cat >/etc/rsyslog.d/99-remote.conf <<EOF
*.*  ${sym}${hostport}
EOF
  systemctl restart rsyslog
  CONFIGURED=1
fi

if [ "$CONFIGURED" -eq 0 ]; then
  echo "[78-logs] SKIP: no hay destino configurado."
  echo "  export CLOUDWATCH_LOG_GROUP=/comfyui/secure-bootstrap  # y IAM role con logs:PutLogEvents"
  echo "  export LOKI_URL=https://loki.example.com"
  echo "  export REMOTE_SYSLOG=udp://logserver.example.com:514"
fi
