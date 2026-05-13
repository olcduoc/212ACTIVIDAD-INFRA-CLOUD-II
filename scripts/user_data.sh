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

# ─── CloudWatch Agent ────────────────────────────────────────────────────
yum install -y amazon-cloudwatch-agent


# ─── CloudWatch Agent ──────────────────────────────────────────────────────
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

# ─── Instance Info HTTP Server ─────────────────────────────────────────────
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
