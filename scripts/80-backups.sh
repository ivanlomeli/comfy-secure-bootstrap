#!/usr/bin/env bash
# Fase 2 — Backups automatizados.
#
# Dos capas:
#   A) AWS Backup: snapshot diario del EBS (si estamos en EC2).
#   B) restic: backup incremental cifrado de /etc, /opt/comfyui/{workflows,output,custom_nodes}
#      a un bucket S3 con MFA-delete (si RESTIC_REPOSITORY set).
#
# Sin variables de entorno, solo configura la parte A si detecta EC2.
set -euo pipefail

# ============================================================
# A) EBS snapshots vía AWS Backup (requiere IAM role)
# ============================================================
if curl -s --max-time 2 -H "X-aws-ec2-metadata-token: $(curl -sX PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' 2>/dev/null)" http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
  INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $(curl -sX PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" http://169.254.169.254/latest/meta-data/instance-id)
  echo "[80-backups] EC2 detectado: $INSTANCE_ID"
  echo "  Configura AWS Backup en la consola:"
  echo "    aws backup create-backup-plan --backup-plan file://backup-plan.json"
  echo "  O crea un tag y usa una selección por tag."
  echo
  echo "  Ejemplo backup-plan.json:"
  cat <<EOF
  {
    "BackupPlan": {
      "BackupPlanName": "comfyui-daily",
      "Rules": [{
        "RuleName": "daily",
        "TargetBackupVaultName": "Default",
        "ScheduleExpression": "cron(0 5 * * ? *)",
        "StartWindowMinutes": 60,
        "CompletionWindowMinutes": 240,
        "Lifecycle": {"DeleteAfterDays": 30, "MoveToColdStorageAfterDays": 7}
      }]
    }
  }
EOF
fi

# ============================================================
# B) restic → S3 (cifrado con passphrase local)
# ============================================================
if [ -n "${RESTIC_REPOSITORY:-}" ] && [ -n "${RESTIC_PASSWORD_FILE:-}" ]; then
  apt-get install -y restic
  export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE

  # Inicializar repo si no existe
  restic snapshots >/dev/null 2>&1 || restic init

  # Systemd timer diario
  cat >/etc/systemd/system/restic-backup.service <<EOF
[Unit]
Description=Restic backup
[Service]
Type=oneshot
Environment=RESTIC_REPOSITORY=${RESTIC_REPOSITORY}
Environment=RESTIC_PASSWORD_FILE=${RESTIC_PASSWORD_FILE}
ExecStart=/usr/bin/restic backup /etc /home /opt/comfyui/workflows /opt/comfyui/output /opt/comfyui/custom_nodes /var/lib/aide/aide.db --exclude-caches --tag daily
ExecStartPost=/usr/bin/restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune
EOF

  cat >/etc/systemd/system/restic-backup.timer <<'EOF'
[Unit]
Description=Daily restic backup at 03:00
[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=1h
Persistent=true
[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now restic-backup.timer
  echo "[80-backups] restic timer diario habilitado hacia $RESTIC_REPOSITORY"
else
  echo "[80-backups] restic NO configurado. Para habilitar:"
  echo "  echo 'unaPasswordFuerteAqui' > /root/.restic-pass && chmod 600 /root/.restic-pass"
  echo "  export RESTIC_REPOSITORY=s3:s3.amazonaws.com/mi-bucket-backups/comfyui"
  echo "  export RESTIC_PASSWORD_FILE=/root/.restic-pass"
  echo "  export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=..."
  echo "  sudo -E ./80-backups.sh"
fi
