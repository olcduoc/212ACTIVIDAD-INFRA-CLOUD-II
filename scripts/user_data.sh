#!/bin/bash
exec > /var/log/user-data.log 2>&1
set -x

yum update -y
yum install -y docker git telnet mariadb105

systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/bin/docker-compose

aws ecr get-login-password --region ${aws_region} | \
  docker login --username AWS \
  --password-stdin ${account_id}.dkr.ecr.${aws_region}.amazonaws.com

mkdir -p /opt/app

cat > /opt/app/docker-compose.yml << 'COMPOSE'
services:
  frontend:
    image: ${account_id}.dkr.ecr.${aws_region}.amazonaws.com/tienda-tech-frontend:latest
    container_name: tienda-tech-frontend
    ports:
      - "80:80"
    depends_on:
      - backend

  backend:
    image: ${account_id}.dkr.ecr.${aws_region}.amazonaws.com/tienda-tech-backend:latest
    container_name: tienda-tech-backend
    env_file:
      - .env
    ports:
      - "3001:3001"
COMPOSE

cat > /opt/app/.env << ENVFILE
DB_HOST=${db_host}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
DB_NAME=${db_name}
DB_PORT=3306
ENVFILE

cat > /etc/systemd/system/app-compose.service << 'SERVICE'
[Unit]
Description=Tienda Tech App Docker Compose
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/app
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable app-compose.service
systemctl start app-compose.service

echo "=== user_data completado: $(date) ==="
