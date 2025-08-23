#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG DO ALUNO ======
NAMESPACE="${NAMESPACE:-alunoX}"   # export NAMESPACE=aluno7 antes de rodar, ou edite aqui
APP_NAME="${APP_NAME:-web}"
IMAGE="${IMAGE:-quay.io/openshift/origin-hello-openshift}"
# =============================

echo ">> Verificando login e projeto..."
oc whoami >/dev/null
oc project "$NAMESPACE" >/dev/null

echo ">> Criando app ($APP_NAME) com imagem $IMAGE..."
if oc get deploy/"$APP_NAME" >/dev/null 2>&1; then
  echo "   - Deployment já existe. Pulando criação."
else
  oc new-app --name="$APP_NAME" "$IMAGE"
fi

echo ">> Expondo o serviço via Route..."
oc get route "$APP_NAME" >/dev/null 2>&1 || oc expose svc/"$APP_NAME"

echo ">> Aguardando rollout..."
oc rollout status deploy/"$APP_NAME"

ROUTE=$(oc get route "$APP_NAME" -o jsonpath='{.spec.host}')
echo "✅ Pronto! Acesse: http://$ROUTE"
