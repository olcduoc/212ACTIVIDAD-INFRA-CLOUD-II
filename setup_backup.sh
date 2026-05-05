#!/bin/bash
# =============================================================
# setup_backup.sh
# Configura AWS Backup para tienda-tech-EC2
# Ejecutar DESPUÉS que el pipeline haya desplegado EC2 y RDS
# =============================================================
set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
PROJECT="tienda-tech"
VAULT_NAME="vault-${PROJECT}"
PLAN_NAME="Plan-Continuidad-Negocio-Diario"
RULE_NAME="regla-diaria"

echo ""
echo "======================================================="
echo "  SETUP — AWS Backup para ${PROJECT}"
echo "======================================================="

# ─── 1. OBTENER IDs DE RECURSOS ────────────────────────────
echo ""
echo "[1/5] Obteniendo IDs de recursos..."

EC2_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${PROJECT}-EC2" \
            "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text)

RDS_ARN=$(aws rds describe-db-instances \
  --query "DBInstances[?contains(DBInstanceIdentifier, '${PROJECT}') && DBInstanceStatus=='available'].DBInstanceArn" \
  --output text | awk '{print $1}')

if [ "$EC2_ID" == "None" ] || [ -z "$EC2_ID" ]; then
  echo "❌ No se encontró instancia EC2 corriendo con tag ${PROJECT}-EC2"
  echo "   Asegúrate que el pipeline terminó exitosamente."
  exit 1
fi

if [ -z "$RDS_ARN" ]; then
  echo "❌ No se encontró instancia RDS disponible con nombre ${PROJECT}"
  echo "   Asegúrate que el RDS está en estado available."
  exit 1
fi

EC2_ARN="arn:aws:ec2:${REGION}:${ACCOUNT_ID}:instance/${EC2_ID}"
echo "   EC2: ${EC2_ID}"
echo "   RDS: ${RDS_ARN}"

# ─── 2. TAGEAR RECURSOS ────────────────────────────────────
echo ""
echo "[2/5] Aplicando tags backup:activo..."

aws ec2 create-tags \
  --resources "$EC2_ID" \
  --tags Key=backup,Value=activo

aws rds add-tags-to-resource \
  --resource-name "$RDS_ARN" \
  --tags Key=backup,Value=activo

echo "   ✅ Tags aplicados"

# ─── 3. CREAR BACKUP VAULT ────────────────────────────────
echo ""
echo "[3/5] Creando Backup Vault..."

VAULT_EXISTS=$(aws backup list-backup-vaults \
  --query "BackupVaultList[?BackupVaultName=='${VAULT_NAME}'].BackupVaultName" \
  --output text)

if [ -z "$VAULT_EXISTS" ]; then
  aws backup create-backup-vault \
    --backup-vault-name "$VAULT_NAME" \
    --region "$REGION"
  echo "   ✅ Vault creado: ${VAULT_NAME}"
else
  echo "   ℹ️  Vault ya existe: ${VAULT_NAME}"
fi

# ─── 4. CREAR BACKUP PLAN ─────────────────────────────────
echo ""
echo "[4/5] Creando Backup Plan..."

PLAN_ID=$(aws backup list-backup-plans \
  --query "BackupPlansList[?BackupPlanName=='${PLAN_NAME}'].BackupPlanId" \
  --output text)

if [ -z "$PLAN_ID" ]; then
  PLAN_ID=$(aws backup create-backup-plan \
    --backup-plan "{
      \"BackupPlanName\": \"${PLAN_NAME}\",
      \"Rules\": [{
        \"RuleName\": \"${RULE_NAME}\",
        \"TargetBackupVaultName\": \"${VAULT_NAME}\",
        \"ScheduleExpression\": \"cron(0 5 * * ? *)\",
        \"StartWindowMinutes\": 60,
        \"CompletionWindowMinutes\": 120,
        \"Lifecycle\": {
          \"DeleteAfterDays\": 7
        }
      }]
    }" \
    --query "BackupPlanId" \
    --output text)
  echo "   ✅ Plan creado: ${PLAN_NAME} (ID: ${PLAN_ID})"
else
  echo "   ℹ️  Plan ya existe: ${PLAN_NAME} (ID: ${PLAN_ID})"
fi

# ─── 5. ASOCIAR RECURSOS AL PLAN ──────────────────────────
echo ""
echo "[5/5] Asociando recursos al plan..."

aws backup create-backup-selection \
  --backup-plan-id "$PLAN_ID" \
  --backup-selection "{
    \"SelectionName\": \"seleccion-${PROJECT}\",
    \"IamRoleArn\": \"arn:aws:iam::${ACCOUNT_ID}:role/LabRole\",
    \"ListOfTags\": [{
      \"ConditionType\": \"STRINGEQUALS\",
      \"ConditionKey\": \"backup\",
      \"ConditionValue\": \"activo\"
    }]
  }" 2>/dev/null && echo "   ✅ Recursos asociados" || echo "   ℹ️  Selección ya existe"

# ─── BACKUP MANUAL INMEDIATO ──────────────────────────────
echo ""
echo ">>> Iniciando backup manual de EC2..."
aws backup start-backup-job \
  --backup-vault-name "$VAULT_NAME" \
  --resource-arn "$EC2_ARN" \
  --iam-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/LabRole" \
  --start-window-minutes 60 \
  --query "BackupJobId" \
  --output text | xargs -I{} echo "   EC2 Backup Job: {}"

echo ""
echo ">>> Iniciando backup manual de RDS..."
aws backup start-backup-job \
  --backup-vault-name "$VAULT_NAME" \
  --resource-arn "$RDS_ARN" \
  --iam-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/LabRole" \
  --start-window-minutes 60 \
  --query "BackupJobId" \
  --output text | xargs -I{} echo "   RDS Backup Job: {}"

echo ""
echo "======================================================="
echo "  ✅ Setup Backup completado"
echo ""
echo "  Vault : ${VAULT_NAME}"
echo "  Plan  : ${PLAN_NAME}"
echo "  EC2   : ${EC2_ID} → tagged backup:activo"
echo "  RDS   : ${RDS_ARN}"
echo ""
echo "  Los backups manuales están corriendo."
echo "  Verifica en AWS Backup → Jobs → Backup jobs"
echo "======================================================="
