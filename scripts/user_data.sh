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

# ─── ECR Login con retry ─────────────────────────────────────────────────
for i in 1 2 3 4 5; do
  aws ecr get-login-password --region ${aws_region} | \
    docker login --username AWS \
    --password-stdin ${account_id}.dkr.ecr.${aws_region}.amazonaws.com && break
  echo "ECR login intento $i fallido, esperando 10s..."
  sleep 10
done

# ─── Docker Compose App ──────────────────────────────────────────────────
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
    restart: unless-stopped

  backend:
    image: ${account_id}.dkr.ecr.${aws_region}.amazonaws.com/tienda-tech-backend:latest
    container_name: tienda-tech-backend
    env_file:
      - .env
    ports:
      - "3001:3001"
    restart: unless-stopped
COMPOSE

cat > /opt/app/.env << ENVFILE
DB_HOST=${db_host}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
DB_NAME=${db_name}
DB_PORT=3306
ENVFILE

# Copiar a home de ec2-user para debug manual
cp /opt/app/docker-compose.yml /home/ec2-user/docker-compose.yml
cp /opt/app/.env /home/ec2-user/.env
chown ec2-user:ec2-user /home/ec2-user/docker-compose.yml /home/ec2-user/.env

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

# ─── Esperar que backend esté listo ──────────────────────────────────────
echo "=== Esperando que backend inicie... ==="
for i in $(seq 1 30); do
  if curl -sf http://localhost:3001/api/productos > /dev/null 2>&1; then
    echo "Backend listo en intento $i"
    break
  fi
  echo "Backend no listo, intento $i/30, esperando 10s..."
  sleep 10
done

# ─── Auto-init DB schema (idempotente) ───────────────────────────────────
echo "=== Inicializando schema DB... ==="
mysql -h ${db_host} -u ${db_user} -p${db_password} << 'SQLEOF'
CREATE DATABASE IF NOT EXISTS ${db_name};
USE ${db_name};

CREATE TABLE IF NOT EXISTS productos (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(255) NOT NULL,
  descripcion TEXT,
  precio DECIMAL(10,2) NOT NULL,
  stock INT NOT NULL
);
SQLEOF

# ─── Auto-carga de productos (solo si tabla vacía) ───────────────────────
echo "=== Verificando productos... ==="
PRODUCT_COUNT=$(mysql -h ${db_host} -u ${db_user} -p${db_password} -N -e \
  "SELECT COUNT(*) FROM ${db_name}.productos;" 2>/dev/null || echo "0")

if [ "$PRODUCT_COUNT" = "0" ]; then
  echo "=== Tabla vacía, cargando productos de prueba... ==="
  
  # Esperar que backend responda
  sleep 5
  
  curl -s -X POST http://localhost:3001/api/productos \
    -H "Content-Type: application/json" \
    -d '{"nombre":"Laptop Dell XPS 15","descripcion":"Intel Core i7-13700H 16GB RAM DDR5 512GB SSD NVMe","precio":1299990,"stock":8}'
  
  curl -s -X POST http://localhost:3001/api/productos \
    -H "Content-Type: application/json" \
    -d '{"nombre":"iPhone 15 Pro Max","descripcion":"256GB Titanio Azul Chip A17 Pro USB-C","precio":1499990,"stock":5}'
  
  curl -s -X POST http://localhost:3001/api/productos \
    -H "Content-Type: application/json" \
    -d '{"nombre":"Samsung Galaxy S24 Ultra","descripcion":"512GB Negro Titanio Snapdragon 8 Gen 3 S Pen","precio":1199990,"stock":12}'
  
  curl -s -X POST http://localhost:3001/api/productos \
    -H "Content-Type: application/json" \
    -d '{"nombre":"MacBook Pro M3 Pro","descripcion":"14 pulgadas Chip M3 Pro 18GB RAM 1TB SSD","precio":2199990,"stock":3}'
  
  curl -s -X POST http://localhost:3001/api/productos \
    -H "Content-Type: application/json" \
    -d '{"nombre":"Sony WH-1000XM5","descripcion":"Audifonos Bluetooth Noise Cancelling 30h bateria","precio":349990,"stock":20}'
  
  curl -s -X POST http://localhost:3001/api/productos \
    -H "Content-Type: application/json" \
    -d '{"nombre":"iPad Air M2","descripcion":"11 pulgadas 128GB WiFi Chip M2 Azul Cielo","precio":749990,"stock":7}'
  
  echo "=== Productos cargados: $(date) ==="
else
  echo "=== Tabla ya tiene $PRODUCT_COUNT productos, no se cargan duplicados ==="
fi

# ─── CloudWatch Agent ────────────────────────────────────────────────────
yum install -y amazon-cloudwatch-agent

mkdir -p /opt/aws/amazon-cloudwatch-agent/etc/

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWA_CONFIG'
{
  "metrics": {
    "append_dimensions": {
      "InstanceId": "$${aws:InstanceId}",
      "AutoScalingGroupName": "$${aws:AutoScalingGroupName}"
    },
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/"],
        "metrics_collection_interval": 60
      }
    }
  }
}
CWA_CONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo "=== CloudWatch Agent iniciado: $(date) ==="

# ─── Instance Info HTTP Server ───────────────────────────────────────────
cat > /usr/local/bin/instance-info-server.py << 'PYSERVER'
#!/usr/bin/env python3
import http.server
import socketserver
import urllib.request
import socket
from datetime import datetime

PORT = 8080

def get_metadata(path):
    try:
        req = urllib.request.Request(
            "http://169.254.169.254/latest/api/token",
            method='PUT',
            headers={'X-aws-ec2-metadata-token-ttl-seconds': '21600'}
        )
        token = urllib.request.urlopen(req, timeout=2).read().decode()
        req = urllib.request.Request(
            f"http://169.254.169.254/latest/meta-data/{path}",
            headers={'X-aws-ec2-metadata-token': token}
        )
        return urllib.request.urlopen(req, timeout=2).read().decode()
    except Exception as e:
        return f"ERR: {e}"

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        instance_id = get_metadata('instance-id')
        local_ip = get_metadata('local-ipv4')
        public_ip = get_metadata('public-ipv4')
        az = get_metadata('placement/availability-zone')
        instance_type = get_metadata('instance-type')
        hostname = socket.gethostname()
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        html = f"""<!DOCTYPE html>
<html><head><title>Tienda Tech - EC2 Instance Info</title><meta charset="utf-8">
<style>
body {{ font-family: 'Courier New', monospace; background: #0a0e27; color: #00ff41; padding: 40px; margin: 0; }}
.container {{ max-width: 800px; margin: 0 auto; background: rgba(0,0,0,0.6); padding: 30px; border: 1px solid #00ff41; border-radius: 5px; }}
h1 {{ color: #00ff41; border-bottom: 2px solid #00ff41; padding-bottom: 10px; }}
table {{ font-size: 1.1em; width: 100%; }}
td {{ padding: 8px 0; }}
td:first-child {{ padding-right: 30px; color: #66ffaa; }}
.value {{ color: #ffeb3b; font-weight: bold; }}
.footer {{ margin-top: 30px; font-size: 0.9em; color: #888; text-align: center; }}
</style></head>
<body><div class="container">
<h1>EC2 Instance Serving Your Request</h1>
<table>
<tr><td>Instance ID:</td><td class="value">{instance_id}</td></tr>
<tr><td>Private IP:</td><td class="value">{local_ip}</td></tr>
<tr><td>Public IP:</td><td class="value">{public_ip}</td></tr>
<tr><td>Availability Zone:</td><td class="value">{az}</td></tr>
<tr><td>Instance Type:</td><td class="value">{instance_type}</td></tr>
<tr><td>Hostname:</td><td class="value">{hostname}</td></tr>
<tr><td>Request Time:</td><td>{now}</td></tr>
</table>
<div class="footer">Refresh (F5) para probar balanceo de carga del ALB</div>
</div></body></html>"""

        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.end_headers()
        self.wfile.write(html.encode())

    def log_message(self, *args):
        pass

if __name__ == '__main__':
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        httpd.serve_forever()
PYSERVER
chmod +x /usr/local/bin/instance-info-server.py

cat > /etc/systemd/system/instance-info.service << 'SVCEOF'
[Unit]
Description=Instance Info HTTP Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/instance-info-server.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable instance-info.service
systemctl start instance-info.service
echo "=== Instance Info service iniciado: $(date) ==="

echo "=== user_data completado: $(date) ==="
