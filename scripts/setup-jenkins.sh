#!/usr/bin/env bash
###############################################################################
#  setup-jenkins.sh
#
#  Deja Jenkins LISTO para la clase. Ejecútalo ~30 min ANTES (el build de la
#  imagen y el pre-pull de herramientas tardan varios minutos la primera vez).
#
#  Qué hace, paso a paso:
#    1. Comprueba Docker y la RAM disponible.
#    2. Crea /var/jenkins_home en el HOST (bind mount con ruta idéntica: es lo
#       que hace que `docker run -v "$WORKSPACE":/src` funcione desde el pipeline).
#    3. Crea el volumen 'trivy-cache' (caché compartida de CVEs entre alumnos).
#    4. Construye la imagen devsecops-jenkins:lts (Jenkins + docker CLI + plugins).
#    5. Arranca Jenkins y espera a que responda.
#    6. PRE-DESCARGA las imágenes de las herramientas y calienta la BD de Trivy,
#       para que en clase los pipelines no se queden bajando gigas.
#    7. Verifica que Jenkins ve el demonio Docker y alcanza al resto del lab.
#    8. Imprime la contraseña inicial de desbloqueo.
#
#  Uso:
#    ./scripts/setup-jenkins.sh            # instalación completa
#    ./scripts/setup-jenkins.sh --check    # solo verificaciones (smoke test)
#    ./scripts/setup-jenkins.sh --password # volver a mostrar la contraseña inicial
#    ./scripts/setup-jenkins.sh --reset    # BORRA Jenkins y empieza de cero
#
#  ⚠️ Ejecútalo desde el MISMO directorio desde el que levantaste el resto del
#     laboratorio. Docker Compose deriva el nombre del proyecto del directorio:
#     si lanzas unos servicios desde /opt/devsecops-lab y otros desde aquí,
#     `docker compose ps/stop` no verá los del otro stack.
###############################################################################
set -uo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
info(){ echo -e "${CYAN}▸ $*${NC}"; }
ok(){   echo -e "${GREEN}✅ $*${NC}"; }
warn(){ echo -e "${YELLOW}⚠️  $*${NC}"; }
err(){  echo -e "${RED}❌ $*${NC}"; }
step(){ echo ""; echo -e "${BOLD}════════ $* ════════${NC}"; }

LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$LAB_DIR"
# shellcheck disable=SC1091
source .env 2>/dev/null || true

JENKINS_PORT="${JENKINS_PORT:-8180}"
JENKINS_CONTAINER="devsecops-jenkins"
JENKINS_HOME_HOST="/var/jenkins_home"
JENKINS_URL="http://localhost:${JENKINS_PORT}"

# Imágenes que usan las etapas del pipeline. Se pre-descargan para que el
# primer pipeline de la clase no tarde 10 minutos bajando capas.
TOOL_IMAGES=(
  "alpine:latest"                      # canario del workspace + utilidades
  "ghcr.io/gitleaks/gitleaks:v8.18.4"
  "aquasec/trivy:latest"
  "sonarsource/sonar-scanner-cli:latest"
  "ghcr.io/zaproxy/zaproxy:stable"
  "python:3.9-slim"
)

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

###############################################################################
# Funciones de verificación (reutilizadas por --check)
###############################################################################
check_all() {
  local fails=0

  step "Verificación (smoke test)"

  info "1) ¿Está el contenedor de Jenkins arriba?"
  if docker ps --format '{{.Names}}' | grep -qx "$JENKINS_CONTAINER"; then
    ok "$JENKINS_CONTAINER está corriendo"
  else
    err "$JENKINS_CONTAINER NO está corriendo  →  docker compose up -d jenkins"; fails=$((fails+1))
  fi

  info "2) ¿Responde el UI de Jenkins en ${JENKINS_URL}?"
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "${JENKINS_URL}/login" 2>/dev/null || echo 000)
  if echo "$CODE" | grep -qE '200|403'; then ok "Jenkins responde (HTTP $CODE)"
  else err "Jenkins no responde (HTTP $CODE)  →  docker logs $JENKINS_CONTAINER"; fails=$((fails+1)); fi

  info "3) ¿Tiene Jenkins el cliente docker y ve el demonio del host?"
  if docker exec "$JENKINS_CONTAINER" docker version --format '{{.Server.Version}}' >/dev/null 2>&1; then
    ok "docker CLI operativo dentro de Jenkins (servidor $(docker exec "$JENKINS_CONTAINER" docker version --format '{{.Server.Version}}' 2>/dev/null))"
  else
    err "Jenkins NO puede hablar con el demonio Docker (¿falta el socket o el CLI?)"; fails=$((fails+1))
  fi

  info "4) ¿Coincide la ruta de JENKINS_HOME dentro y fuera? (el fallo clásico)"
  docker exec "$JENKINS_CONTAINER" sh -c 'mkdir -p /var/jenkins_home/_smoke && echo lab > /var/jenkins_home/_smoke/probe.txt' 2>/dev/null
  if docker run --rm -v /var/jenkins_home/_smoke:/probe alpine:latest cat /probe/probe.txt 2>/dev/null | grep -q lab; then
    ok "El host y Jenkins comparten la MISMA ruta: 'docker run -v \$WORKSPACE:/src' funcionará"
  else
    err "Rutas distintas: los escáneres montarían un directorio VACÍO."
    err "   Revisa que docker-compose.yml tenga:  - /var/jenkins_home:/var/jenkins_home"; fails=$((fails+1))
  fi
  docker exec "$JENKINS_CONTAINER" rm -rf /var/jenkins_home/_smoke 2>/dev/null || true

  info "5) ¿Alcanza Jenkins al resto del laboratorio por nombre de contenedor?"
  for target in "devsecops-sonarqube:9000" "devsecops-defectdojo:8081" "devsecops-juiceshop:3000" "devsecops-gitlab:${GITLAB_PORT_HTTP:-8929}"; do
    if docker exec "$JENKINS_CONTAINER" curl -s -o /dev/null -m 8 "http://${target}" 2>/dev/null; then
      ok "   $target alcanzable"
    else
      warn "   $target NO responde (¿ese servicio está apagado? no siempre es un error)"
    fi
  done

  info "6) ¿Están las imágenes de las herramientas descargadas?"
  for img in "${TOOL_IMAGES[@]}"; do
    if docker image inspect "$img" >/dev/null 2>&1; then ok "   $img"
    else warn "   $img NO descargada (el primer pipeline irá lento)"; fi
  done

  info "7) ¿Existe la caché de Trivy?"
  if docker volume inspect trivy-cache >/dev/null 2>&1; then ok "   volumen trivy-cache creado"
  else warn "   falta el volumen trivy-cache  →  docker volume create trivy-cache"; fi

  echo ""
  if [ "$fails" -eq 0 ]; then
    ok "Todo correcto. Jenkins está listo para la clase."
  else
    err "$fails comprobación(es) crítica(s) han fallado. Revísalas antes de clase."
  fi
  return "$fails"
}

show_password() {
  step "Contraseña inicial de Jenkins"
  PASS=$(docker exec "$JENKINS_CONTAINER" cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null)
  if [ -n "${PASS:-}" ]; then
    echo -e "   URL      : ${BOLD}${JENKINS_URL}${NC}"
    echo -e "   Password : ${BOLD}${PASS}${NC}"
    echo ""
    echo "   (Si el fichero ya no existe, es que el asistente de instalación"
    echo "    ya se completó: entra con el usuario que creaste entonces.)"
  else
    warn "No hay contraseña inicial: el asistente ya se completó."
    echo "   Entra en ${JENKINS_URL} con el usuario administrador que creaste."
  fi
}

###############################################################################
# Modos alternativos
###############################################################################
reset_jenkins() {
  step "RESET de Jenkins"
  warn "Esto BORRA todos los jobs, credenciales y usuarios de Jenkins."
  warn "El resto del laboratorio (GitLab, SonarQube, DefectDojo…) NO se toca."
  printf "   ¿Continuar? escribe 'si' y pulsa Enter: "
  read -r ANSWER
  [ "$ANSWER" = "si" ] || { info "Cancelado."; exit 0; }

  # OJO: 'docker compose down -v' NO borra un bind mount. Hay que borrarlo a mano.
  docker compose rm -sf jenkins >/dev/null 2>&1 || true
  $SUDO rm -rf "$JENKINS_HOME_HOST"
  $SUDO mkdir -p "$JENKINS_HOME_HOST"
  $SUDO chown 0:0 "$JENKINS_HOME_HOST"
  ok "Jenkins borrado. Ejecuta ahora: ./scripts/setup-jenkins.sh"
}

case "${1:-}" in
  --check)    check_all; exit $?;;
  --password) show_password; exit 0;;
  --reset)    reset_jenkins; exit 0;;
esac

###############################################################################
# 1) Requisitos
###############################################################################
step "1/7  Requisitos"
if ! command -v docker >/dev/null 2>&1; then
  err "Docker no está instalado en esta máquina. Ejecuta primero ./install.sh"; exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  err "Falta el plugin 'docker compose' (v2)."; exit 1
fi
ok "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?') disponible"

FREE_MB=$(free -m | awk '/^Mem:/{print $7}')
info "RAM disponible: ${FREE_MB} MB"
if [ "${FREE_MB:-0}" -lt 1800 ]; then
  warn "Queda poca RAM libre. Para la clase de Jenkins puedes liberar memoria con:"
  echo "     docker compose stop gitlab-runner prometheus grafana"
  echo "   (y si vas MUY justo, también 'sonarqube': la etapa SAST es opcional)"
fi

###############################################################################
# 2) JENKINS_HOME en el host (ruta idéntica dentro/fuera)
###############################################################################
step "2/7  JENKINS_HOME en el host"
if [ ! -d "$JENKINS_HOME_HOST" ]; then
  info "Creando $JENKINS_HOME_HOST (necesita permisos de root)..."
  $SUDO mkdir -p "$JENKINS_HOME_HOST"
fi
$SUDO chown -R 0:0 "$JENKINS_HOME_HOST" 2>/dev/null || true
ok "$JENKINS_HOME_HOST listo"
echo "   Motivo: el pipeline hace 'docker run -v \$WORKSPACE:/src' y esa ruta la"
echo "   resuelve el demonio Docker DEL HOST. Si la ruta no existiera fuera,"
echo "   los escáneres analizarían un directorio vacío."

###############################################################################
# 3) Caché compartida de Trivy
###############################################################################
step "3/7  Caché de Trivy"
docker volume create trivy-cache >/dev/null 2>&1 && ok "volumen trivy-cache listo" || ok "volumen trivy-cache ya existía"

###############################################################################
# 4) Construir la imagen de Jenkins
###############################################################################
step "4/7  Construyendo la imagen de Jenkins (Jenkins + docker CLI + plugins)"
info "Esto tarda 3-6 minutos la primera vez..."
if docker compose build jenkins; then
  ok "Imagen devsecops-jenkins:lts construida"
else
  err "Falló el build. Revisa la salida de arriba (¿hay salida a internet?)."; exit 1
fi

###############################################################################
# 5) Arrancar Jenkins
###############################################################################
step "5/7  Arrancando Jenkins"
docker compose up -d jenkins
info "Esperando a que Jenkins responda en ${JENKINS_URL}..."
for i in $(seq 1 40); do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "${JENKINS_URL}/login" 2>/dev/null || echo 000)
  if echo "$CODE" | grep -qE '200|403'; then ok "Jenkins operativo (HTTP $CODE)"; break; fi
  printf "   intento %s/40 (HTTP %s)\r" "$i" "$CODE"; sleep 5
  if [ "$i" = "40" ]; then err "Jenkins no arrancó. Revisa: docker logs $JENKINS_CONTAINER"; exit 1; fi
done

###############################################################################
# 6) Pre-descarga de herramientas + calentar la BD de Trivy
###############################################################################
step "6/7  Pre-descargando las imágenes de las herramientas"
info "Sin esto, el primer pipeline de cada alumno tardaría muchísimo."
for img in "${TOOL_IMAGES[@]}"; do
  printf "   %-45s " "$img"
  if docker pull -q "$img" >/dev/null 2>&1; then echo -e "${GREEN}OK${NC}"; else echo -e "${YELLOW}FALLÓ (se descargará en el pipeline)${NC}"; fi
done

info "Descargando la base de datos de vulnerabilidades de Trivy a la caché compartida..."
docker run --rm -v trivy-cache:/root/.cache/trivy aquasec/trivy:latest \
  image --download-db-only --no-progress >/dev/null 2>&1 \
  && ok "BD de Trivy en caché" \
  || warn "No se pudo precargar la BD de Trivy (se bajará en el primer job)"

###############################################################################
# 7) Verificación + contraseña
###############################################################################
check_all || true
show_password

step "Siguiente paso"
cat <<EOF
   1. Abre ${JENKINS_URL} y pega la contraseña de arriba.
   2. En "Customize Jenkins":
      ⚠️  NO pulses el botón grande "Install suggested plugins".
      Elige  ▸ Select plugins to install ▸ botón "None" ▸ Install
      Los plugins YA vienen dentro de la imagen. "Install suggested plugins"
      se pondría a descargar ~19 plugins de internet y tarda varios minutos.
   3. Crea el usuario administrador del laboratorio.
   4. (Opcional, si varios alumnos comparten este Jenkins)
      Manage Jenkins ▸ Nodes ▸ Built-In Node ▸ Configure ▸ Number of executors = 4
   5. Sigue el manual: docs/jenkins/Practica-Jenkins-Alumno.pdf
EOF
