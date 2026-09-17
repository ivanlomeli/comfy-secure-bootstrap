# Bootstrap en AWS EC2 con user-data

## AMI recomendada

**Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 24.04)** — release ≥ `20260612`.

Ya trae:
- Driver NVIDIA 595.71.05 (compatible con L40S SM 8.9)
- CUDA 12.8, 12.9, 13.0, 13.2 (default 13.2)
- Python 3.12
- Kernel 6.17-aws
- NVIDIA container toolkit + EFA + DCGM

Buscar con:
```
aws ec2 describe-images --owners amazon \
  --filters 'Name=name,Values=Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 24.04)*' \
  --query 'sort_by(Images,&CreationDate)[-1].[ImageId,Name]' --output text
```

Alternativa Ubuntu Server 24.04 LTS vainilla si prefieres kernel/driver diferente: el script `40-gpu-nvidia.sh` instalará el driver automáticamente (requiere reboot posterior).

## Security Group inicial

```
aws ec2 create-security-group --group-name comfyui-bootstrap \
  --description "Comfy bootstrap: SSH 2222 temp + WireGuard"

aws ec2 authorize-security-group-ingress --group-name comfyui-bootstrap \
  --protocol tcp --port 2222 --cidr <TU_IP>/32

aws ec2 authorize-security-group-ingress --group-name comfyui-bootstrap \
  --protocol udp --port 51820 --cidr 0.0.0.0/0
```

## Lanzar la instancia con user-data

```
cat > user-data.sh <<'USERDATA'
#!/bin/bash
set -eux
export ADMIN_USER=ubuntu
export ADMIN_SSH_PUBKEY="ssh-ed25519 AAAAC3Nz... tu-llave"
curl -fsSL https://raw.githubusercontent.com/ivanlomeli/comfy-secure-bootstrap/main/bootstrap.sh | sudo -E bash
USERDATA

aws ec2 run-instances \
  --region us-west-2 \
  --image-id ami-XXXXXXXXXXXXXX \
  --instance-type g6e.xlarge \
  --key-name <tu-keypair> \
  --security-group-ids sg-XXXXXXXX \
  --iam-instance-profile Name=SSMInstanceCore \
  --metadata-options 'HttpTokens=required,HttpPutResponseHopLimit=1,HttpEndpoint=enabled' \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":500,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=comfyui-l40s},{Key=Bootstrap,Value=comfy-secure}]' \
  --user-data file://user-data.sh
```

Notas clave:

- `HttpTokens=required` fuerza IMDSv2 (mitiga SSRF → robo de credenciales IAM).
- `HttpPutResponseHopLimit=1` impide que containers accedan al IMDS.
- IAM instance profile `SSMInstanceCore` con la policy `AmazonSSMManagedInstanceCore` para tener escape hatch vía Session Manager.
- 500 GB gp3 para modelos (Wan 2.2 y Sonic pesan decenas de GB).

## IAM role para SSM

```
aws iam create-role --role-name SSMInstanceCore \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

aws iam attach-role-policy --role-name SSMInstanceCore \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile --instance-profile-name SSMInstanceCore
aws iam add-role-to-instance-profile --instance-profile-name SSMInstanceCore \
  --role-name SSMInstanceCore
```

## Monitorear el arranque

```
aws ec2 get-console-output --instance-id i-XXXXX --output text | tail -100
```

O vía SSM:
```
aws ssm start-session --target i-XXXXX
sudo tail -f /var/log/cloud-init-output.log
```

## Cuando termine

1. Espera a ver `[bootstrap] Fase 1 completa` en el log.
2. Conéctate por 2222 la primera vez:
   ```
   ssh -p 2222 ubuntu@<ip-publica>
   sudo /opt/bootstrap/add-peer.sh mi-mac
   ```
3. Configura WG en tu cliente, conéctate, verifica `ssh ubuntu@10.7.0.1`.
4. Corre `sudo /opt/bootstrap/scripts/90-lock-down.sh`.
5. Revoca 2222 del SG:
   ```
   aws ec2 revoke-security-group-ingress --group-name comfyui-bootstrap \
     --protocol tcp --port 2222 --cidr <TU_IP>/32
   ```

## Costos aproximados

- **g6e.xlarge** (1× L40S 48 GB, 4 vCPU): $1.86/hr on-demand en us-west-2.
- **EBS gp3 500 GB**: ~$40/mes (~$0.055/hr).
- **Data transfer out**: primeros 100 GB/mes gratis; después ~$0.09/GB.

Total para 4 horas de uso: ~$7.60 + fracción de disco.
