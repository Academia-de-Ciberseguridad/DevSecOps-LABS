#!/usr/bin/env bash
###############################################################################
#  bootstrap-integrations.sh
#
#  Conecta AUTOMÁTICAMENTE todas las herramientas del pipeline:
#    1. SonarQube  -> cambia la contraseña inicial y genera un token de análisis.
#    2. DefectDojo -> obtiene la API key de admin.
#    3. GitLab     -> crea el proyecto 'devsecops-sample', inyecta las variables
#                     CI/CD (tokens/URLs) y sube el código + el .gitlab-ci.yml.
#
#  El push final DISPARA el pipeline por sí solo: esa es la demostración del
#  flujo automatizado (push -> validación completa -> DefectDojo).
#
#  Requisito previo: haber ejecutado ./scripts/register-runner.sh
#  Uso:  ./scripts/bootstrap-integrations.sh
###############################################################################
set -uo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info(){ echo -e "${CYAN}▸ $*${NC}"; }
ok(){   echo -e "${GREEN}✅ $*${NC}"; }
warn(){ echo -e "${YELLOW}⚠️  $*${NC}"; }
err(){  echo -e "${RED}❌ $*${NC}"; }

LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$LAB_DIR"
# shellcheck disable=SC1091
source .env 2>/dev/null || true
CRED_FILE="$LAB_DIR/.lab-credentials"
# shellcheck disable=SC1090
source "$CRED_FILE" 2>/dev/null || true

# ---- URLs de acceso desde el HOST (localhost + puerto publicado) ----
GITLAB_PORT="${GITLAB_PORT_HTTP:-8929}"
GITLAB_HOST="http://localhost:${GITLAB_PORT}"
SONAR_HOST="http://localhost:${SONAR_PORT:-9000}"
DOJO_HOST="http://localhost:${DEFECTDOJO_PORT:-8080}"

# ---- URLs INTERNAS (contenedor -> contenedor) que usará el pipeline ----
SONAR_INT="http://devsecops-sonarqube:9000"
DOJO_INT="http://devsecops-defectdojo:8081"
DAST_TARGET_INT="http://devsecops-juiceshop:3000"

SONAR_ADMIN_PASS="${SONAR_ADMIN_PASS:-DevSecOps2024!}"
DD_ADMIN_PASSWORD="${DD_ADMIN_PASSWORD:-DevSecOps2024!}"

wait_http(){ # $1=url  $2=nombre  $3=match_code(regex)
  local url="$1" name="$2" match="${3:-200}"
  info "Esperando a $name ($url)..."
  for i in $(seq 1 60); do
    local c; c=$(curl -s -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 000)
    if echo "$c" | grep -qE "$match"; then ok "$name listo (HTTP $c)"; return 0; fi
    printf "   intento %s/60 (HTTP %s)\r" "$i" "$c"; sleep 10
  done
  err "$name no respondió a tiempo"; return 1
}

save_cred(){ # $1=KEY $2=VALUE
  touch "$CRED_FILE"; chmod 600 "$CRED_FILE"
  grep -v "^$1=" "$CRED_FILE" > "$CRED_FILE.tmp" 2>/dev/null || true
  mv "$CRED_FILE.tmp" "$CRED_FILE" 2>/dev/null || true
  echo "$1=$2" >> "$CRED_FILE"
}

###############################################################################
# 1) SONARQUBE  -> contraseña + token
###############################################################################
echo ""; echo "════════ 1/3  SonarQube (SAST) ════════"
wait_http "${SONAR_HOST}/api/system/status" "SonarQube" "200" || exit 1
# Asegurar que el estado sea UP (no solo STARTING)
for i in $(seq 1 30); do
  ST=$(curl -s "${SONAR_HOST}/api/system/status" | grep -oE '"status":"[^"]+"' | cut -d'"' -f4)
  [ "$ST" = "UP" ] && break
  printf "   SonarQube status: %s (%s/30)\r" "$ST" "$i"; sleep 10
done

info "Cambiando contraseña inicial de admin (si sigue en admin/admin)..."
CODE=$(curl -s -o /dev/null -w '%{http_code}' -u "admin:admin" -X POST \
  "${SONAR_HOST}/api/users/change_password" \
  --data-urlencode "login=admin" \
  --data-urlencode "previousPassword=admin" \
  --data-urlencode "password=${SONAR_ADMIN_PASS}")
if [ "$CODE" = "204" ]; then ok "Contraseña de SonarQube cambiada a la del lab"; else warn "No se cambió (HTTP $CODE) — probablemente ya estaba cambiada"; fi

info "Generando token de análisis en SonarQube..."
curl -s -u "admin:${SONAR_ADMIN_PASS}" -X POST "${SONAR_HOST}/api/user_tokens/revoke" --data-urlencode "name=ci-lab" >/dev/null 2>&1 || true
SONAR_TOKEN=$(curl -s -u "admin:${SONAR_ADMIN_PASS}" -X POST "${SONAR_HOST}/api/user_tokens/generate" \
  --data-urlencode "name=ci-lab" | grep -oE '"token":"[^"]+"' | cut -d'"' -f4)
if [ -z "${SONAR_TOKEN:-}" ]; then err "No se pudo generar el token de SonarQube"; exit 1; fi
ok "Token SonarQube: ${SONAR_TOKEN:0:10}...(oculto)"
save_cred "SONAR_TOKEN" "$SONAR_TOKEN"
save_cred "SONAR_ADMIN_PASS" "$SONAR_ADMIN_PASS"

###############################################################################
# 2) DEFECTDOJO  -> API key
###############################################################################
echo ""; echo "════════ 2/3  DefectDojo (Vuln Mgmt) ════════"
wait_http "${DOJO_HOST}/login" "DefectDojo" "200|302" || exit 1
info "Obteniendo API key de DefectDojo..."
DD_API_KEY=""
for i in $(seq 1 12); do
  DD_API_KEY=$(curl -s -X POST "${DOJO_HOST}/api/v2/api-token-auth/" \
    --data-urlencode "username=admin" \
    --data-urlencode "password=${DD_ADMIN_PASSWORD}" | grep -oE '"token":"[^"]+"' | cut -d'"' -f4)
  [ -n "$DD_API_KEY" ] && break
  printf "   reintentando (%s/12)...\r" "$i"; sleep 10
done
if [ -z "${DD_API_KEY:-}" ]; then err "No se pudo obtener la API key de DefectDojo (¿migraciones aún en curso?)"; exit 1; fi
ok "API key DefectDojo: ${DD_API_KEY:0:10}...(oculto)"
save_cred "DD_API_KEY" "$DD_API_KEY"

###############################################################################
# 3) GITLAB  -> proyecto + variables CI/CD + push (dispara el pipeline)
###############################################################################
echo ""; echo "════════ 3/3  GitLab (proyecto + variables + push) ════════"
if [ -z "${GITLAB_PAT:-}" ]; then
  err "No hay GITLAB_PAT. Ejecuta primero: ./scripts/register-runner.sh"; exit 1
fi
wait_http "${GITLAB_HOST}/users/sign_in" "GitLab" "200" || exit 1

info "Creando (o localizando) el proyecto 'devsecops-sample'..."
PID=$(curl -s -H "PRIVATE-TOKEN: ${GITLAB_PAT}" \
  "${GITLAB_HOST}/api/v4/projects?search=devsecops-sample&membership=true" \
  | grep -oE '"id":[0-9]+' | head -1 | cut -d: -f2)
if [ -z "${PID:-}" ]; then
  PID=$(curl -s -H "PRIVATE-TOKEN: ${GITLAB_PAT}" -X POST "${GITLAB_HOST}/api/v4/projects" \
    --data-urlencode "name=devsecops-sample" \
    --data-urlencode "visibility=private" \
    --data "initialize_with_readme=false" | grep -oE '"id":[0-9]+' | head -1 | cut -d: -f2)
fi
if [ -z "${PID:-}" ]; then err "No se pudo crear/localizar el proyecto"; exit 1; fi
ok "Proyecto listo (ID=$PID)"

set_var(){ # $1=key $2=value $3=masked(true/false)
  curl -s -o /dev/null -H "PRIVATE-TOKEN: ${GITLAB_PAT}" -X DELETE \
    "${GITLAB_HOST}/api/v4/projects/${PID}/variables/$1" 2>/dev/null || true
  curl -s -o /dev/null -H "PRIVATE-TOKEN: ${GITLAB_PAT}" -X POST \
    "${GITLAB_HOST}/api/v4/projects/${PID}/variables" \
    --data-urlencode "key=$1" \
    --data-urlencode "value=$2" \
    --data "masked=$3" --data "protected=false"
}
info "Inyectando variables CI/CD en el proyecto..."
set_var "SONAR_HOST_URL"     "$SONAR_INT"        "false"
set_var "SONAR_TOKEN"        "$SONAR_TOKEN"      "true"
set_var "DEFECTDOJO_URL"     "$DOJO_INT"         "false"
set_var "DEFECTDOJO_API_KEY" "$DD_API_KEY"       "true"
set_var "DAST_TARGET"        "$DAST_TARGET_INT"  "false"
ok "Variables CI/CD inyectadas en el proyecto (SONAR_TOKEN y DEFECTDOJO_API_KEY enmascaradas)"

# --- Variables a NIVEL DE INSTANCIA -------------------------------------------
# Así CUALQUIER proyecto nuevo del lab hereda los tokens: al alumno le basta con
# incluir un .gitlab-ci.yml en su repo para que el análisis corra solo.
set_instance_var(){ # $1=key $2=value $3=masked(true/false)
  curl -s -o /dev/null -H "PRIVATE-TOKEN: ${GITLAB_PAT}" -X DELETE \
    "${GITLAB_HOST}/api/v4/admin/ci/variables/$1" 2>/dev/null || true
  curl -s -o /dev/null -H "PRIVATE-TOKEN: ${GITLAB_PAT}" -X POST \
    "${GITLAB_HOST}/api/v4/admin/ci/variables" \
    --data-urlencode "key=$1" \
    --data-urlencode "value=$2" \
    --data "masked=$3" --data "protected=false"
}
info "Inyectando las mismas variables a NIVEL DE INSTANCIA (para todos los repos)..."
set_instance_var "SONAR_HOST_URL"     "$SONAR_INT"        "false"
set_instance_var "SONAR_TOKEN"        "$SONAR_TOKEN"      "true"
set_instance_var "DEFECTDOJO_URL"     "$DOJO_INT"         "false"
set_instance_var "DEFECTDOJO_API_KEY" "$DD_API_KEY"       "true"
set_instance_var "DAST_TARGET"        "$DAST_TARGET_INT"  "false"
ok "Variables de instancia listas: cualquier repo con un .gitlab-ci.yml correrá el análisis"

info "Subiendo el código de sample-project (esto DISPARA el pipeline)..."
TMP=$(mktemp -d)
cp -a "$LAB_DIR/sample-project/." "$TMP/"
rm -rf "$TMP/__pycache__"
( cd "$TMP"
  git init -q
  git checkout -q -B main
  git add -A
  git -c user.email="lab@devsecops.local" -c user.name="DevSecOps Lab" commit -qm "App vulnerable + pipeline DevSecOps" >/dev/null
  git push -q -f "http://root:${GITLAB_PAT}@localhost:${GITLAB_PORT}/root/devsecops-sample.git" main
) && ok "Código subido — el pipeline debería estar arrancando" || { err "Falló el push"; }
rm -rf "$TMP"

echo ""
echo "═════════════════════════════════════════════════════════════"
ok "Integraciones completadas."
echo -e "   Pipeline:   ${GITLAB_HOST}/root/devsecops-sample/-/pipelines"
echo -e "   SonarQube:  ${SONAR_HOST}  (admin / ${SONAR_ADMIN_PASS})"
echo -e "   DefectDojo: ${DOJO_HOST}   (producto 'DevSecOps Lab')"
echo -e "   Credenciales/tokens guardados en: ${CRED_FILE}"
echo "═════════════════════════════════════════════════════════════"
