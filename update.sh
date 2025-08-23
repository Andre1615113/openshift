set -euo pipefail

NAMESPACE="${NAMESPACE:-alunoX}"
APP_NAME="${APP_NAME:-web}"

echo ">> Selecionando projeto..."
oc project "$NAMESPACE" >/dev/null

echo ">> Injetando variável e atualizando (simula novo release)..."
oc set env deploy/"$APP_NAME" RELEASE_TAG="$(date +%s)"
oc rollout status deploy/"$APP_NAME"

echo ">> Verificando pods..."
oc get pods -l app="$APP_NAME" -o wide
