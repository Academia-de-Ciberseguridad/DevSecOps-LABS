#!/usr/bin/env bash
###############################################################################
#  push-jenkinsfile.sh
#
#  Sube el `Jenkinsfile` al repositorio 'devsecops-sample' de GitLab, para que
#  los alumnos puedan usar la opción "Pipeline script from SCM" (Nivel 3).
#
#  Es un atajo: hace lo mismo que clonar, copiar el fichero, commit y push,
#  pero reutilizando el PAT que ya generó ./scripts/register-runner.sh.
#
#  ⚠️ El push a 'main' DISPARA también el pipeline de GitLab CI. Es inofensivo
#     (y hasta útil: así hay hallazgos frescos en DefectDojo para la clase).
#
#  Uso:  ./scripts/push-jenkinsfile.sh
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
# shellcheck disable=SC1091
source "$LAB_DIR/.lab-credentials" 2>/dev/null || true

GITLAB_PORT="${GITLAB_PORT_HTTP:-8929}"
REPO="http://root:${GITLAB_PAT:-}@localhost:${GITLAB_PORT}/root/devsecops-sample.git"

if [ -z "${GITLAB_PAT:-}" ]; then
  err "No hay GITLAB_PAT en .lab-credentials. Ejecuta antes: ./scripts/register-runner.sh"; exit 1
fi
if [ ! -f "$LAB_DIR/sample-project/Jenkinsfile" ]; then
  err "No existe sample-project/Jenkinsfile"; exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

info "Clonando devsecops-sample..."
if ! git clone -q "$REPO" "$TMP/repo" 2>/dev/null; then
  err "No se pudo clonar. ¿Existe el proyecto? Ejecuta ./scripts/bootstrap-integrations.sh"; exit 1
fi

cp -f "$LAB_DIR/sample-project/Jenkinsfile" "$TMP/repo/Jenkinsfile"

cd "$TMP/repo"
if git diff --quiet -- Jenkinsfile && git ls-files --error-unmatch Jenkinsfile >/dev/null 2>&1; then
  ok "El Jenkinsfile del repositorio ya está actualizado. Nada que hacer."
  exit 0
fi

git add Jenkinsfile
git -c user.email="lab@devsecops.local" -c user.name="DevSecOps Lab" \
    commit -qm "Añade el pipeline DevSecOps para Jenkins"
if git push -q origin HEAD:main; then
  ok "Jenkinsfile subido a devsecops-sample (rama main)."
  echo "   Compruébalo en: http://localhost:${GITLAB_PORT}/root/devsecops-sample"
  echo "   Los alumnos ya pueden usar 'Pipeline script from SCM' con Script Path = Jenkinsfile"
else
  err "El push falló. ¿'main' está protegida y el PAT no tiene write_repository?"
  exit 1
fi
