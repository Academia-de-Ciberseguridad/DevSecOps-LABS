#!/usr/bin/env bash
###############################################################################
#  register-runner.sh
#
#  Registra AUTOMÁTICAMENTE el GitLab Runner contra tu GitLab local.
#  Sin este paso, GitLab CI no puede ejecutar el pipeline.
#
#  Qué hace, paso a paso (para explicar a los alumnos):
#    1. Espera a que GitLab esté "healthy".
#    2. Genera un token de acceso personal (PAT) de root vía gitlab-rails.
#    3. Crea un runner de instancia por API y obtiene su token (glrt-...).
#    4. Registra el runner con executor Docker, montando el socket de Docker
#       y conectándolo a la red devsecops-net (para alcanzar sonarqube, zap,
#       defectdojo y juiceshop por nombre).
#    5. Reinicia el runner para aplicar la configuración.
#
#  Uso:  ./scripts/register-runner.sh
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

GITLAB_PORT="${GITLAB_PORT_HTTP:-8929}"
GITLAB_HOST_URL="http://localhost:${GITLAB_PORT}"      # acceso desde el host
GITLAB_INT_URL="http://devsecops-gitlab:${GITLAB_PORT}" # acceso entre contenedores
GL_CONTAINER="devsecops-gitlab"
RUNNER_CONTAINER="devsecops-gitlab-runner"
CRED_FILE="$LAB_DIR/.lab-credentials"

# ---------------------------------------------------------------------------
# 1) Esperar a que GitLab responda
# ---------------------------------------------------------------------------
info "Esperando a que GitLab esté disponible en ${GITLAB_HOST_URL} (puede tardar ~5 min)..."
for i in $(seq 1 60); do
  # /users/sign_in es fiable desde el host (/-/health da 404 por la whitelist de IPs)
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "${GITLAB_HOST_URL}/users/sign_in" 2>/dev/null || echo 000)
  if [ "$CODE" = "200" ]; then ok "GitLab está listo (HTTP 200)"; break; fi
  printf "   intento %s/60 (HTTP %s)\r" "$i" "$CODE"; sleep 10
  if [ "$i" = "60" ]; then err "GitLab no respondió a tiempo. Revisa: docker compose logs -f gitlab"; exit 1; fi
done

# ---------------------------------------------------------------------------
# 2) Generar PAT de root vía gitlab-rails
# ---------------------------------------------------------------------------
info "Generando token de acceso (PAT) de root..."
PAT=$(docker exec "$GL_CONTAINER" gitlab-rails runner "
u = User.find_by_username('root')
u.personal_access_tokens.where(name: 'lab-automation').find_each(&:revoke!)
t = u.personal_access_tokens.create!(scopes: ['api','read_repository','write_repository'], name: 'lab-automation', expires_at: 365.days.from_now)
puts t.token
" 2>/dev/null | grep -oE 'glpat-[A-Za-z0-9_-]+' | head -1)

if [ -z "${PAT:-}" ]; then
  err "No se pudo generar el PAT. ¿GitLab terminó de arrancar? (docker compose logs gitlab)"; exit 1
fi
ok "PAT generado: ${PAT:0:12}...(oculto)"

# ---------------------------------------------------------------------------
# 3) Crear runner de instancia por API y obtener su token
# ---------------------------------------------------------------------------
info "Creando runner de instancia vía API..."
RESP=$(curl -s -X POST "${GITLAB_HOST_URL}/api/v4/user/runners" \
  -H "PRIVATE-TOKEN: ${PAT}" \
  --data "runner_type=instance_type" \
  --data "description=devsecops-lab-runner" \
  --data "tag_list=devsecops,docker" \
  --data "run_untagged=true" \
  --data "locked=false")
RUNNER_TOKEN=$(echo "$RESP" | grep -oE '"token":"[^"]+"' | head -1 | cut -d'"' -f4)

if [ -z "${RUNNER_TOKEN:-}" ]; then
  err "No se obtuvo el token del runner. Respuesta de la API:"; echo "$RESP"; exit 1
fi
ok "Runner creado, token: ${RUNNER_TOKEN:0:12}...(oculto)"

# ---------------------------------------------------------------------------
# 4) Registrar el runner (executor docker + socket + red devsecops-net)
# ---------------------------------------------------------------------------
info "Registrando el runner con executor Docker..."
docker exec "$RUNNER_CONTAINER" gitlab-runner register \
  --non-interactive \
  --url "${GITLAB_INT_URL}" \
  --token "${RUNNER_TOKEN}" \
  --executor "docker" \
  --docker-image "alpine:latest" \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --docker-network-mode "devsecops-net" \
  --docker-pull-policy "if-not-present" \
  --clone-url "${GITLAB_INT_URL}" >/dev/null

# ---------------------------------------------------------------------------
# 5) Reiniciar el runner para aplicar la config
# ---------------------------------------------------------------------------
docker restart "$RUNNER_CONTAINER" >/dev/null
ok "Runner registrado y reiniciado."

# Guardar el PAT para que bootstrap-integrations.sh lo reutilice
touch "$CRED_FILE"; chmod 600 "$CRED_FILE"
grep -v '^GITLAB_PAT=' "$CRED_FILE" > "$CRED_FILE.tmp" 2>/dev/null || true
mv "$CRED_FILE.tmp" "$CRED_FILE" 2>/dev/null || true
echo "GITLAB_PAT=${PAT}" >> "$CRED_FILE"

echo ""
ok "Runner operativo. Verifícalo en: ${GITLAB_HOST_URL}/admin/runners"
echo -e "   (PAT guardado en ${CRED_FILE})"
