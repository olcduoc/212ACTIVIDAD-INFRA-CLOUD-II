#!/bin/bash
# =============================================================
# setup_prerequisites.sh
# Crea todos los prerrequisitos para tienda-tech-EC2
# S3, DynamoDB, ECR, build y push de imágenes Docker
# =============================================================

set -e

# ─── CONFIGURACIÓN ───────────────────────────────────────────
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
PROJECT="tienda-tech"
BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}"
DYNAMO_TABLE="${PROJECT}-tf-lock"
APP_DIR="/home/oleivac/Documents/LabInfraCloud-II-Act2.1/tienda-tech-EC2"

echo ""
echo "======================================================="
echo "  SETUP — Prerrequisitos tienda-tech-EC2"
echo "  Cuenta : ${ACCOUNT_ID}"
echo "  Región : ${REGION}"
echo "  Bucket : ${BUCKET}"
echo "======================================================="
echo ""

# ─── [1/4] S3 BACKEND ────────────────────────────────────────
echo "─── [1/4] Creando bucket S3 para Terraform state ────────"

if aws s3api head-bucket --bucket "${BUCKET}" --region "${REGION}" 2>/dev/null; then
  echo "⚠️  Bucket ${BUCKET} ya existe — omitiendo creación"
else
  aws s3api create-bucket \
    --bucket "${BUCKET}" \
    --region "${REGION}"
  echo "✅ Bucket ${BUCKET} creado"
fi

# Habilitar versionado
aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled
echo "✅ Versionado habilitado en ${BUCKET}"

# Bloquear acceso público
aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo "✅ Acceso público bloqueado"

# ─── [2/4] DYNAMODB LOCKING ──────────────────────────────────
echo ""
echo "─── [2/4] Creando tabla DynamoDB para locking ───────────"

if aws dynamodb describe-table --table-name "${DYNAMO_TABLE}" --region "${REGION}" 2>/dev/null; then
  echo "⚠️  Tabla ${DYNAMO_TABLE} ya existe — omitiendo creación"
else
  aws dynamodb create-table \
    --table-name "${DYNAMO_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"

  echo "⏳ Esperando que la tabla esté activa..."
  aws dynamodb wait table-exists \
    --table-name "${DYNAMO_TABLE}" \
    --region "${REGION}"
  echo "✅ Tabla ${DYNAMO_TABLE} creada y activa"
fi

# ─── [3/4] ECR REPOSITORIOS ──────────────────────────────────
echo ""
echo "─── [3/4] Creando repositorios ECR ─────────────────────"

for REPO in tienda-tech-frontend tienda-tech-backend; do
  if aws ecr describe-repositories --repository-names "${REPO}" --region "${REGION}" 2>/dev/null; then
    echo "⚠️  Repositorio ${REPO} ya existe — omitiendo creación"
  else
    aws ecr create-repository \
      --repository-name "${REPO}" \
      --region "${REGION}"
    echo "✅ Repositorio ${REPO} creado"
  fi
done

# ─── [4/4] BUILD Y PUSH DE IMÁGENES ──────────────────────────
echo ""
echo "─── [4/4] Build y push de imágenes Docker ───────────────"

# Verificar que Docker está corriendo
if ! docker info > /dev/null 2>&1; then
  echo "❌ Docker no está corriendo. Inícialo y vuelve a ejecutar el script."
  exit 1
fi

# Verificar que existe el directorio de la app
if [ ! -d "${APP_DIR}" ]; then
  echo "❌ No se encontró el directorio ${APP_DIR}"
  echo "   Ajusta la variable APP_DIR al path de tu proyecto."
  exit 1
fi

# Login a ECR
echo "⏳ Login a ECR..."
aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS \
  --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
echo "✅ Login ECR exitoso"

# Build y push frontend
echo ""
echo "⏳ Build frontend..."
cd "${APP_DIR}/tienda-tech-frontend"
docker build -t tienda-tech-frontend . --quiet
docker tag tienda-tech-frontend:latest \
  "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/tienda-tech-frontend:latest"
docker push \
  "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/tienda-tech-frontend:latest"
echo "✅ Frontend pushed a ECR"

# Build y push backend
echo ""
echo "⏳ Build backend..."
cd "${APP_DIR}/tienda-tech-backend"
docker build -t tienda-tech-backend . --quiet
docker tag tienda-tech-backend:latest \
  "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/tienda-tech-backend:latest"
docker push \
  "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/tienda-tech-backend:latest"
echo "✅ Backend pushed a ECR"

# ─── RESUMEN FINAL ───────────────────────────────────────────
echo ""
echo "======================================================="
echo "  ✅ Setup completado"
echo "======================================================="
echo ""
echo "  S3 Bucket  : ${BUCKET}"
echo "  DynamoDB   : ${DYNAMO_TABLE}"
echo "  ECR Frontend: ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/tienda-tech-frontend:latest"
echo "  ECR Backend : ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/tienda-tech-backend:latest"
echo ""
echo "  Actualiza backend.tf con:"
echo "  bucket = \"${BUCKET}\""
echo ""
echo "  Luego ejecuta:"
echo "  terraform init && terraform validate"
echo "======================================================="
echo ""
