#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Uso: $0 users.txt [--random] [--password <senha_unica>] [--delete]"
  exit 1
fi

USERS_FILE="$1"; shift || true
RANDOM_PASS=false
DELETE_MODE=false
COMMON_PASS="Senha@123"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --random) RANDOM_PASS=true; shift;;
    --password) COMMON_PASS="${2:-Senha@123}"; shift 2;;
    --delete) DELETE_MODE=true; shift;;
    *) echo "Parâmetro desconhecido: $1"; exit 1;;
  esac
done

OUT_DIR="./oak-prep"
HTPASSWD_FILE="$OUT_DIR/users.htpasswd"
CSV_FILE="$OUT_DIR/users_passwords.csv"

if $DELETE_MODE; then
  echo "⚠️  Modo REMOÇÃO ativado"
  echo " - Apagando projetos dos usuários de $USERS_FILE"
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    user="$(echo "$raw" | sed 's/[[:space:]]//g')"
    [[ -z "$user" || "$user" =~ ^# ]] && continue
    ns="$user"
    if oc get ns "$ns" >/dev/null 2>&1; then
      oc delete project "$ns" --wait=false || true
      echo " - Projeto $ns removido"
    fi
  done < "$USERS_FILE"

  echo " - Removendo Secret htpasswd-secret"
  oc -n openshift-config delete secret htpasswd-secret --ignore-not-found

  echo " - Removendo provider HTPasswd do OAuth (se existir)"
  PATCH_REMOVE=$(cat <<'EOF'
{
  "spec": {
    "identityProviders": []
  }
}
EOF
)
  oc patch oauth cluster --type=merge -p "$PATCH_REMOVE" || true

  echo "✅ Remoção concluída."
  exit 0
fi

# =============== MODO CRIAÇÃO ===============
mkdir -p "$OUT_DIR"
: > "$CSV_FILE"

FIRST_CREATED=false
if [[ ! -s "$HTPASSWD_FILE" ]]; then
  FIRST_CREATED=true
fi

add_user() {
  local user="$1" pass="$2"
  if [[ "$FIRST_CREATED" == true ]]; then
    htpasswd -c -B -b "$HTPASSWD_FILE" "$user" "$pass" >/dev/null
    FIRST_CREATED=false
  else
    if grep -qE "^${user}:" "$HTPASSWD_FILE"; then
      htpasswd -B -b "$HTPASSWD_FILE" "$user" "$pass" >/dev/null
    else
      htpasswd -B -b "$HTPASSWD_FILE" "$user" "$pass" >/dev/null
    fi
  fi
}

echo "username,password" > "$CSV_FILE"

while IFS= read -r raw || [[ -n "$raw" ]]; do
  user="$(echo "$raw" | sed 's/[[:space:]]//g')"
  [[ -z "$user" || "$user" =~ ^# ]] && continue

  if $RANDOM_PASS; then
    pass="$(LC_ALL=C tr -dc 'A-Za-z0-9@#%+=' </dev/urandom | head -c 12)"
  else
    pass="$COMMON_PASS"
  fi

  add_user "$user" "$pass"
  echo "$user,$pass" >> "$CSV_FILE"
done < "$USERS_FILE"

echo "[1/4] htpasswd gerado em $HTPASSWD_FILE"
echo "[2/4] CSV de senhas em $CSV_FILE"

oc -n openshift-config delete secret htpasswd-secret --ignore-not-found
oc -n openshift-config create secret generic htpasswd-secret --from-file=htpasswd="$HTPASSWD_FILE"

PATCH=$(cat <<'EOF'
{
  "spec": {
    "identityProviders": [
      {
        "name": "local_htpasswd",
        "mappingMethod": "claim",
        "type": "HTPasswd",
        "htpasswd": { "fileData": { "name": "htpasswd-secret" } }
      }
    ]
  }
}
EOF
)
oc patch oauth cluster --type=merge -p "$PATCH"

echo "[3/4] OAuth patch aplicado (provider: local_htpasswd)"

while IFS= read -r raw || [[ -n "$raw" ]]; do
  user="$(echo "$raw" | sed 's/[[:space:]]//g')"
  [[ -z "$user" || "$user" =~ ^# ]] && continue

  ns="$user"
  if ! oc get ns "$ns" >/dev/null 2>&1; then
    oc new-project "$ns" --display-name="Projeto de $user" >/dev/null
    echo " - Projeto criado: $ns"
  else
    echo " - Projeto já existe: $ns"
  fi

  oc adm policy add-role-to-user admin "$user" -n "$ns" >/dev/null || true
done < "$USERS_FILE"

echo "[4/4] Projetos e RBAC prontos."
echo "✅ Preparação concluída."
echo "Arquivos úteis:"
echo " - $HTPASSWD_FILE"
echo " - $CSV_FILE  (entregue de forma segura aos alunos)"

