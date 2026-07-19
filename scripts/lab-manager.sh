#!/bin/bash
###############################################################################
#  DevSecOps Lab Manager - Script de gestión rápida
#
#  Uso: ./scripts/lab-manager.sh [comando]
#
#  Comandos:
#    status     - Ver estado de todos los servicios
#    start      - Iniciar todos los servicios
#    stop       - Detener todos los servicios
#    restart    - Reiniciar todos los servicios
#    logs       - Ver logs en tiempo real
#    urls       - Mostrar URLs de acceso
#    scan-app   - Ejecutar escaneo completo de la app de ejemplo
#    health     - Verificar salud de todos los servicios
#    ram        - Ver uso de memoria por contenedor
#    cleanup    - Limpiar imágenes y volúmenes sin usar
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

LAB_DIR="/opt/devsecops-lab"
cd "$LAB_DIR" 2>/dev/null || cd "$(dirname "$0")/.." || { echo "No se encontró el directorio del lab"; exit 1; }

source .env 2>/dev/null || true
SERVER_IP=$(hostname -I | awk '{print $1}')

case "${1:-help}" in

  status)
    echo -e "${BOLD}Estado de los servicios DevSecOps:${NC}\n"
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    ;;

  start)
    echo -e "${CYAN}Iniciando servicios...${NC}"
    docker compose up -d
    echo -e "${GREEN}✅ Servicios iniciados${NC}"
    ;;

  stop)
    echo -e "${YELLOW}Deteniendo servicios...${NC}"
    docker compose down
    echo -e "${GREEN}✅ Servicios detenidos${NC}"
    ;;

  restart)
    echo -e "${YELLOW}Reiniciando servicios...${NC}"
    docker compose restart
    echo -e "${GREEN}✅ Servicios reiniciados${NC}"
    ;;

  logs)
    SERVICE="${2:-}"
    if [ -n "$SERVICE" ]; then
      docker compose logs -f "$SERVICE"
    else
      docker compose logs -f --tail=50
    fi
    ;;

  urls)
    echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║       DevSecOps Lab - URLs de Acceso             ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC} ${CYAN}GitLab${NC}       http://${SERVER_IP}:${GITLAB_PORT_HTTP:-8929}  ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}              root / ${GITLAB_ROOT_PASSWORD:-DevSecOps2024!}         ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC} ${CYAN}SonarQube${NC}    http://${SERVER_IP}:${SONAR_PORT:-9000}       ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}              admin / admin                      ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC} ${CYAN}OWASP ZAP${NC}    http://${SERVER_IP}:${ZAP_PORT:-8090}       ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC} ${CYAN}DefectDojo${NC}   http://${SERVER_IP}:${DEFECTDOJO_PORT:-8080}  ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}              admin / ${DD_ADMIN_PASSWORD:-DevSecOps2024!}         ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC} ${CYAN}Juice Shop${NC}   http://${SERVER_IP}:${JUICESHOP_PORT:-3000}  ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC} ${CYAN}Grafana${NC}      http://${SERVER_IP}:${GRAFANA_PORT:-3001}    ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}              admin / ${GF_SECURITY_ADMIN_PASSWORD:-DevSecOps2024!}         ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC} ${CYAN}Prometheus${NC}   http://${SERVER_IP}:${PROMETHEUS_PORT:-9090}  ${BOLD}║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
    ;;

  scan-app)
    echo -e "${BOLD}Ejecutando escaneo completo del proyecto de ejemplo...${NC}\n"
    APP_DIR="$LAB_DIR/sample-project"

    echo -e "${CYAN}[1/4] Gitleaks - Secret Scanning${NC}"
    if command -v gitleaks &>/dev/null; then
      gitleaks detect --source "$APP_DIR" --verbose 2>&1 || true
    else
      echo "  Gitleaks no instalado, usando Docker..."
      docker run --rm -v "$APP_DIR":/scan zricethezav/gitleaks:latest detect --source /scan --verbose 2>&1 || true
    fi

    echo -e "\n${CYAN}[2/4] Trivy - SCA (Dependencias)${NC}"
    if command -v trivy &>/dev/null; then
      trivy fs --severity HIGH,CRITICAL "$APP_DIR"
    else
      docker run --rm -v "$APP_DIR":/scan aquasec/trivy:latest fs --severity HIGH,CRITICAL /scan
    fi

    echo -e "\n${CYAN}[3/4] Trivy - Container Scan${NC}"
    if [ -f "$APP_DIR/Dockerfile" ]; then
      cd "$APP_DIR"
      docker build -t devsecops-sample-app:test . -q
      if command -v trivy &>/dev/null; then
        trivy image --severity HIGH,CRITICAL devsecops-sample-app:test
      else
        docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL devsecops-sample-app:test
      fi
      cd "$LAB_DIR"
    fi

    echo -e "\n${CYAN}[4/4] OWASP ZAP - DAST (contra Juice Shop)${NC}"
    ZAP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${ZAP_PORT:-8090}/JSON/core/view/version/" 2>/dev/null || echo "000")
    if [ "$ZAP_STATUS" = "200" ]; then
      echo "  Iniciando escaneo spider contra Juice Shop..."
      curl -s "http://localhost:${ZAP_PORT:-8090}/JSON/spider/action/scan/?url=http://devsecops-juiceshop:3000&maxChildren=5" | python3 -m json.tool 2>/dev/null || true
      echo "  Spider iniciado. Ver progreso en http://${SERVER_IP}:${ZAP_PORT:-8090}"
    else
      echo "  ⚠️  ZAP no disponible en puerto ${ZAP_PORT:-8090}"
    fi

    echo -e "\n${GREEN}✅ Escaneo completo finalizado${NC}"
    ;;

  health)
    echo -e "${BOLD}Verificación de salud de servicios:${NC}\n"

    check_service() {
      local name=$1 url=$2
      STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$url" --connect-timeout 5 2>/dev/null || echo "000")
      if [ "$STATUS" = "200" ] || [ "$STATUS" = "302" ]; then
        echo -e "  ${GREEN}✅ $name${NC} ($url) - HTTP $STATUS"
      else
        echo -e "  ${RED}❌ $name${NC} ($url) - HTTP $STATUS"
      fi
    }

    check_service "GitLab"     "http://localhost:${GITLAB_PORT_HTTP:-8929}/-/health"
    check_service "SonarQube"  "http://localhost:${SONAR_PORT:-9000}/api/system/status"
    check_service "OWASP ZAP"  "http://localhost:${ZAP_PORT:-8090}/JSON/core/view/version/"
    check_service "DefectDojo" "http://localhost:${DEFECTDOJO_PORT:-8080}"
    check_service "Juice Shop" "http://localhost:${JUICESHOP_PORT:-3000}"
    check_service "Grafana"    "http://localhost:${GRAFANA_PORT:-3001}"
    check_service "Prometheus" "http://localhost:${PROMETHEUS_PORT:-9090}/-/healthy"
    echo ""
    ;;

  ram)
    echo -e "${BOLD}Uso de memoria por contenedor:${NC}\n"
    docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}" | grep devsecops
    echo ""
    echo -e "RAM total del sistema:"
    free -h | head -2
    ;;

  cleanup)
    echo -e "${YELLOW}Limpiando recursos Docker no utilizados...${NC}"
    docker system prune -f
    echo -e "${GREEN}✅ Limpieza completada${NC}"
    ;;

  *)
    echo -e "${BOLD}DevSecOps Lab Manager${NC}"
    echo ""
    echo "Uso: $0 [comando]"
    echo ""
    echo "Comandos disponibles:"
    echo "  status     Ver estado de los servicios"
    echo "  start      Iniciar todos los servicios"
    echo "  stop       Detener todos los servicios"
    echo "  restart    Reiniciar servicios"
    echo "  logs       Ver logs (logs [servicio] para uno específico)"
    echo "  urls       Mostrar URLs y credenciales"
    echo "  scan-app   Ejecutar escaneo de seguridad completo"
    echo "  health     Verificar salud de todos los servicios"
    echo "  ram        Ver uso de memoria"
    echo "  cleanup    Limpiar recursos Docker sin usar"
    ;;
esac
