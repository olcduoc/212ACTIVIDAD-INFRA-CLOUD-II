#!/bin/bash
# =============================================================
# cleanup_prerequisites.sh
# Elimina los prerrequisitos manuales de tienda-tech-EC2
# S3, DynamoDB, ECR, AMI, Snapshots RDS
# =============================================================

set -e

ACCOUNT_ID="975050244181"
REGION="us-east-1"
PROJECT="tienda-tech"
BUCKET="tienda-tech-tfstate-${ACCOUNT_ID}"

echo ""
echo "======================================================="
echo "  CLEANUP — Prerrequisitos tienda-tech-EC2"
echo "  Cuenta: ${ACCOUNT_ID} | Región: ${REGION}"
echo "======================================================="
echo ""
echo "⚠️  ADVERTENCIA: Esta acción es IRREVERSIBLE."
echo "   Se eliminarán: S3, DynamoDB, ECR, AMIs, Snapshots RDS"
echo ""
read -p "¿Confirmas? Escribe ELIMINAR para continuar: " CONFIRM

if [ "$CONFIRM" != "ELIMINAR" ]; then
  echo "Operación cancelada."
  exit 0
fi

echo ""
echo "─── [1/5] Vaciando y eliminando bucket S3 ───────────────"
# Eliminar todas las versiones del bucket (versionado activo)
aws s3api list-object-versions \
  --bucket "${BUCKET}" \
  --query "Versions[*].{Key:Key,VersionId:VersionId}" \
  --output json 2>/dev/null | \
  jq -r '.[] | "--delete Objects=[{Key=\(.Key),VersionId=\(.VersionId)}]"' | \
  while read ARGS; do
    aws s3api delete-objects --bucket "${BUCKET}" ${ARGS} --region "${REGION}" 2>/dev/null || true
  done

# Eliminar marcadores de eliminación
aws s3api list-object-versions \
  --bucket "${BUCKET}" \
  --query "DeleteMarkers[*].{Key:Key,VersionId:VersionId}" \
  --output json 2>/dev/null | \
  jq -r '.[] | "--delete Objects=[{Key=\(.Key),VersionId=\(.VersionId)}]"' | \
  while read ARGS; do
    aws s3api delete-objects --bucket "${BUCKET}" ${ARGS} --region "${REGION}" 2>/dev/null || true
  done

aws s3 rb s3://${BUCKET} --force --region "${REGION}" 2>/dev/null && \
  echo "✅ Bucket ${BUCKET} eliminado" || \
  echo "⚠️  Bucket no encontrado o ya eliminado"

echo ""
echo "─── [2/5] Eliminando tabla DynamoDB ─────────────────────"
aws dynamodb delete-table \
  --table-name tienda-tech-tf-lock \
  --region "${REGION}" 2>/dev/null && \
  echo "✅ Tabla tienda-tech-tf-lock eliminada" || \
  echo "⚠️  Tabla no encontrada o ya eliminada"

echo ""
echo "─── [3/5] Eliminando imágenes y repositorios ECR ────────"
for REPO in tienda-tech-frontend tienda-tech-backend; do
  # Eliminar todas las imágenes del repo
  IMAGES=$(aws ecr list-images \
    --repository-name "${REPO}" \
    --region "${REGION}" \
    --query "imageIds[*]" \
    --output json 2>/dev/null)

  if [ "$IMAGES" != "[]" ] && [ -n "$IMAGES" ]; then
    aws ecr batch-delete-image \
      --repository-name "${REPO}" \
      --image-ids "${IMAGES}" \
      --region "${REGION}" 2>/dev/null && \
      echo "  🗑  Imágenes de ${REPO} eliminadas"
  fi

  aws ecr delete-repository \
    --repository-name "${REPO}" \
    --force \
    --region "${REGION}" 2>/dev/null && \
    echo "✅ Repositorio ${REPO} eliminado" || \
    echo "⚠️  Repositorio ${REPO} no encontrado"
done

echo ""
echo "─── [4/5] Deregistrando AMIs del proyecto ───────────────"
AMIS=$(aws ec2 describe-images \
  --owners self \
  --filters "Name=name,Values=${PROJECT}*" \
  --query "Images[*].ImageId" \
  --region "${REGION}" \
  --output text 2>/dev/null)

if [ -n "$AMIS" ]; then
  for AMI in $AMIS; do
    # Obtener snapshots asociados antes de deregistrar
    SNAPSHOTS=$(aws ec2 describe-images \
      --image-ids "${AMI}" \
      --query "Images[0].BlockDeviceMappings[*].Ebs.SnapshotId" \
      --region "${REGION}" \
      --output text 2>/dev/null)

    aws ec2 deregister-image --image-id "${AMI}" --region "${REGION}" 2>/dev/null && \
      echo "✅ AMI ${AMI} deregistrada"

    # Eliminar snapshots de la AMI
    for SNAP in $SNAPSHOTS; do
      aws ec2 delete-snapshot --snapshot-id "${SNAP}" --region "${REGION}" 2>/dev/null && \
        echo "  🗑  Snapshot ${SNAP} eliminado"
    done
  done
else
  echo "⚠️  No se encontraron AMIs del proyecto"
fi

echo ""
echo "─── [5/5] Eliminando snapshots RDS del proyecto ─────────"
RDS_SNAPS=$(aws rds describe-db-snapshots \
  --snapshot-type manual \
  --query "DBSnapshots[?contains(DBSnapshotIdentifier,'${PROJECT}')].DBSnapshotIdentifier" \
  --region "${REGION}" \
  --output text 2>/dev/null)

if [ -n "$RDS_SNAPS" ]; then
  for SNAP in $RDS_SNAPS; do
    aws rds delete-db-snapshot \
      --db-snapshot-identifier "${SNAP}" \
      --region "${REGION}" 2>/dev/null && \
      echo "✅ Snapshot RDS ${SNAP} eliminado" || \
      echo "⚠️  Snapshot ${SNAP} no encontrado"
  done
else
  echo "⚠️  No se encontraron snapshots RDS del proyecto"
fi

echo ""
echo "======================================================="
echo "  ✅ Cleanup completado"
echo "======================================================="
echo ""
