#!/bin/bash
# ═══════════════════════════════════════════════════════
# Script de generación de carga para métricas CloudWatch
# Ejecutar desde máquina local
# ═══════════════════════════════════════════════════════

ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null)
if [ -z "$ALB_DNS" ]; then
  echo "ERROR: No se pudo obtener ALB DNS. Ejecuta desde el directorio del repo."
  exit 1
fi

EC2_IDS=$(aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].InstanceId' --output text)

echo "═══════════════════════════════════════════"
echo "  Generador de carga — Tienda Tech"
echo "═══════════════════════════════════════════"
echo "ALB: $ALB_DNS"
echo "EC2: $EC2_IDS"
echo ""

# ─── PASO 1: Verificar/Iniciar CloudWatch Agent ─────
echo ">>> [1/4] Verificando CloudWatch Agent en EC2s..."
for ID in $EC2_IDS; do
  echo "  Iniciando agent en $ID..."
  aws ssm send-command \
    --instance-ids "$ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json 2>/dev/null && echo OK || echo FAIL"]' \
    --query 'Command.CommandId' --output text 2>/dev/null && echo "    Enviado" || echo "    SSM no disponible - iniciar manualmente"
done

# ─── PASO 2: Instalar stress y generar carga CPU+MEM ─
echo ""
echo ">>> [2/4] Generando carga CPU+Memoria en EC2s..."
for ID in $EC2_IDS; do
  echo "  Stress en $ID (10 min)..."
  aws ssm send-command \
    --instance-ids "$ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["sudo yum install -y stress-ng > /dev/null 2>&1; stress-ng --cpu 0 --vm 2 --vm-bytes 75% --timeout 600s > /dev/null 2>&1 &; echo STRESS_STARTED"]' \
    --query 'Command.CommandId' --output text 2>/dev/null && echo "    Enviado" || echo "    SSM no disponible - ejecutar manualmente"
done

# ─── PASO 3: Bombardeo HTTP ──────────────────────────
echo ""
echo ">>> [3/4] Bombardeando ALB (5 minutos)..."
END_TIME=$((SECONDS + 300))
COUNT=0
while [ $SECONDS -lt $END_TIME ]; do
  for i in $(seq 1 20); do
    curl -s -o /dev/null http://$ALB_DNS:3001/api/productos &
    curl -s -o /dev/null http://$ALB_DNS/ &
  done
  wait
  COUNT=$((COUNT + 40))
  echo "  $(date +%H:%M:%S) — $COUNT requests acumulados"
  sleep 3
done

# ─── PASO 4: Verificar métricas ──────────────────────
echo ""
echo ">>> [4/4] Verificando métricas..."
echo ""
echo "=== CWAgent ==="
aws cloudwatch list-metrics --namespace CWAgent \
  --query 'Metrics[*].MetricName' --output text | tr '\t' '\n' | sort -u

echo ""
echo "=== RDS ==="
aws cloudwatch list-metrics --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value=tienda-tech-mysql \
  --query 'Metrics[*].MetricName' --output text | tr '\t' '\n' | sort -u | head -10

echo ""
echo "═══════════════════════════════════════════"
echo "  Carga completada. Verifica:"
echo "  Dashboard: CloudWatch → tienda-tech-dashboard (rango 1h)"
echo "  Alarmas: CloudWatch → Alarms"
echo "  Email: Revisa correo para alertas SNS"
echo "═══════════════════════════════════════════"
