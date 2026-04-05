#!/bin/bash
###############################################################################
#  DevSecOps Lab - Script de Instalación Automatizada para Ubuntu
#
#  Instala y configura un entorno completo DevSecOps con:
#    - Docker + Docker Compose
#    - GitLab CE (SCM + CI/CD)
#    - SonarQube (SAST)
#    - OWASP ZAP (DAST)
#    - Trivy (SCA + Container Scanning)
#    - Gitleaks (Secret Scanning)
#    - DefectDojo (Gestión de Vulnerabilidades)
#    - OWASP Juice Shop (App Vulnerable para prácticas)
#    - Grafana + Prometheus (Monitoreo)
#
#  Uso:
#    chmod +x install.sh
#    sudo ./install.sh
#
#  Optimizado para servidores con 8 GB de RAM
###############################################################################

set -euo pipefail

# ============================================================
# Colores y funciones de utilidad
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════${NC}"; echo -e "${CYAN}${BOLD}  $1${NC}"; echo -e "${CYAN}${BOLD}═══════════════════════════════════════════${NC}\n"; }

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVSECOPS_HOME="/opt/devsecops-lab"

# ============================================================
# Verificaciones previas
# ============================================================
log_section "VERIFICACIONES PREVIAS"

if [[ $EUID -ne 0 ]]; then
    log_error "Este script debe ejecutarse como root (sudo ./install.sh)"
    exit 1
fi

# Detectar SO
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
    log_info "Sistema detectado: $PRETTY_NAME"
else
    log_error "No se pudo detectar el sistema operativo"
    exit 1
fi

# Verificar RAM
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
log_info "RAM total: ${TOTAL_RAM_GB} GB"

if [ "$TOTAL_RAM_GB" -lt 6 ]; then
    log_error "Se requieren mínimo 6 GB de RAM. Tienes ${TOTAL_RAM_GB} GB."
    exit 1
elif [ "$TOTAL_RAM_GB" -lt 8 ]; then
    log_warn "RAM limitada (${TOTAL_RAM_GB} GB). Se aplicarán optimizaciones agresivas."
fi

# Verificar espacio en disco
FREE_DISK_GB=$(df / | tail -1 | awk '{print int($4/1024/1024)}')
log_info "Espacio libre en disco: ${FREE_DISK_GB} GB"

if [ "$FREE_DISK_GB" -lt 20 ]; then
    log_error "Se requieren mínimo 20 GB libres. Tienes ${FREE_DISK_GB} GB."
    exit 1
fi

log_success "Verificaciones completadas"

# ============================================================
# 1. Actualizar sistema e instalar dependencias base
# ============================================================
log_section "1/7 - ACTUALIZANDO SISTEMA"

apt-get update -qq
apt-get install -y -qq \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    git \
    wget \
    unzip \
    jq \
    net-tools \
    htop \
    python3 \
    python3-pip \
    > /dev/null 2>&1

log_success "Dependencias base instaladas"

# ============================================================
# 2. Instalar Docker + Docker Compose
# ============================================================
log_section "2/7 - INSTALANDO DOCKER"

if command -v docker &> /dev/null; then
    log_info "Docker ya está instalado: $(docker --version)"
else
    # Agregar repo oficial de Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1

    systemctl enable docker
    systemctl start docker

    log_success "Docker instalado: $(docker --version)"
fi

# Agregar usuario actual al grupo docker
if [ -n "${SUDO_USER:-}" ]; then
    usermod -aG docker "$SUDO_USER" 2>/dev/null || true
    log_info "Usuario $SUDO_USER agregado al grupo docker"
fi

# Verificar Docker Compose
if docker compose version &> /dev/null; then
    log_success "Docker Compose: $(docker compose version --short)"
else
    log_error "Docker Compose no disponible"
    exit 1
fi

# ============================================================
# 3. Configurar SWAP (crítico para 8GB RAM)
# ============================================================
log_section "3/7 - CONFIGURANDO SWAP Y KERNEL"

SWAP_SIZE="4G"
if [ ! -f /swapfile ]; then
    log_info "Creando swap de ${SWAP_SIZE}..."
    fallocate -l $SWAP_SIZE /swapfile
    chmod 600 /swapfile
    mkswap /swapfile > /dev/null
    swapon /swapfile

    # Persistir en fstab
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    log_success "Swap de ${SWAP_SIZE} activado"
else
    swapon /swapfile 2>/dev/null || true
    log_info "Swap ya existe"
fi

# Optimizar kernel para contenedores
cat > /etc/sysctl.d/99-devsecops-lab.conf << 'SYSCTL'
# Optimizaciones para DevSecOps Lab
vm.swappiness=10
vm.max_map_count=524288
net.core.somaxconn=65535
net.ipv4.ip_forward=1
fs.file-max=65536
SYSCTL
sysctl --system > /dev/null 2>&1

log_success "Swap y kernel optimizados"

# ============================================================
# 4. Instalar herramientas CLI (Trivy + Gitleaks)
# ============================================================
log_section "4/7 - INSTALANDO HERRAMIENTAS CLI"

# --- Trivy ---
if command -v trivy &> /dev/null; then
    log_info "Trivy ya instalado: $(trivy --version 2>/dev/null | head -1)"
else
    log_info "Instalando Trivy (SCA + Container Scanning)..."
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin > /dev/null 2>&1
    if command -v trivy &> /dev/null; then
        log_success "Trivy instalado: $(trivy --version 2>/dev/null | head -1)"
    else
        log_warn "Trivy: instalación via script falló, intentando con apt..."
        wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /etc/apt/keyrings/trivy.gpg 2>/dev/null
        echo "deb [signed-by=/etc/apt/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" > /etc/apt/sources.list.d/trivy.list
        apt-get update -qq && apt-get install -y -qq trivy > /dev/null 2>&1
        log_success "Trivy instalado via apt"
    fi
fi

# --- Gitleaks ---
if command -v gitleaks &> /dev/null; then
    log_info "Gitleaks ya instalado: $(gitleaks version 2>/dev/null)"
else
    log_info "Instalando Gitleaks (Secret Scanning)..."
    GITLEAKS_VERSION=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | jq -r '.tag_name' | tr -d 'v' 2>/dev/null || echo "8.18.4")
    ARCH=$(dpkg --print-architecture)
    if [ "$ARCH" = "amd64" ]; then ARCH="x64"; fi
    wget -q "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${ARCH}.tar.gz" -O /tmp/gitleaks.tar.gz 2>/dev/null || \
    wget -q "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" -O /tmp/gitleaks.tar.gz 2>/dev/null
    if [ -f /tmp/gitleaks.tar.gz ]; then
        tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks 2>/dev/null || true
        rm -f /tmp/gitleaks.tar.gz
        chmod +x /usr/local/bin/gitleaks 2>/dev/null || true
    fi
    if command -v gitleaks &> /dev/null; then
        log_success "Gitleaks instalado: $(gitleaks version 2>/dev/null)"
    else
        log_warn "Gitleaks: se instalará como contenedor Docker como alternativa"
    fi
fi

log_success "Herramientas CLI instaladas"

# ============================================================
# 5. Preparar directorio del laboratorio
# ============================================================
log_section "5/7 - PREPARANDO LABORATORIO"

mkdir -p "$DEVSECOPS_HOME"
cp -r "$INSTALL_DIR"/* "$DEVSECOPS_HOME"/ 2>/dev/null || true

# Crear directorios de datos persistentes
mkdir -p "$DEVSECOPS_HOME/data"/{gitlab/{config,logs,data},sonarqube/{data,logs,extensions},defectdojo,prometheus,grafana,juiceshop}

# Permisos para SonarQube (necesita usuario específico)
chown -R 1000:1000 "$DEVSECOPS_HOME/data/sonarqube" 2>/dev/null || true

# Permisos para Grafana
chown -R 472:472 "$DEVSECOPS_HOME/data/grafana" 2>/dev/null || true

log_success "Directorio del laboratorio: $DEVSECOPS_HOME"

# ============================================================
# 6. Copiar configuraciones y levantar servicios
# ============================================================
log_section "6/7 - LEVANTANDO SERVICIOS DOCKER"

cd "$DEVSECOPS_HOME"

# Crear archivo .env si no existe
if [ ! -f .env ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
    cat > .env << ENV
# ============================================================
# DevSecOps Lab - Variables de Entorno
# ============================================================

# IP del servidor (detectada automáticamente)
SERVER_IP=${SERVER_IP}

# GitLab
GITLAB_HOME=${DEVSECOPS_HOME}/data/gitlab
GITLAB_ROOT_PASSWORD=DevSecOps2024!
GITLAB_PORT_HTTP=8929
GITLAB_PORT_SSH=2224

# SonarQube
SONAR_PORT=9000
SONAR_JDBC_USERNAME=sonar
SONAR_JDBC_PASSWORD=sonar

# OWASP ZAP
ZAP_PORT=8090

# DefectDojo
DEFECTDOJO_PORT=8080
DD_ADMIN_PASSWORD=DevSecOps2024!

# Juice Shop
JUICESHOP_PORT=3000

# Grafana
GRAFANA_PORT=3001
GF_SECURITY_ADMIN_PASSWORD=DevSecOps2024!

# Prometheus
PROMETHEUS_PORT=9090
ENV
    log_info "Archivo .env creado con configuración por defecto"
fi

source .env

# Levantar servicios en orden (para 8GB RAM)
log_info "Levantando servicios (esto puede tomar varios minutos)..."

# Primero GitLab (el más pesado)
log_info "[1/5] Iniciando GitLab CE..."
docker compose up -d gitlab 2>&1 | tail -3
log_info "  GitLab necesita ~3-5 min para iniciar completamente"

# SonarQube + PostgreSQL
log_info "[2/5] Iniciando SonarQube..."
docker compose up -d sonarqube-db sonarqube 2>&1 | tail -3

# DefectDojo
log_info "[3/5] Iniciando DefectDojo..."
docker compose up -d defectdojo-db defectdojo 2>&1 | tail -3

# Servicios ligeros
log_info "[4/5] Iniciando Juice Shop + ZAP..."
docker compose up -d juiceshop zap 2>&1 | tail -3

# Monitoreo
log_info "[5/5] Iniciando Grafana + Prometheus..."
docker compose up -d prometheus grafana 2>&1 | tail -3

log_success "Todos los servicios están iniciando"

# ============================================================
# 7. Verificación y resumen final
# ============================================================
log_section "7/7 - VERIFICACIÓN FINAL"

# Esperar a que los servicios arranquen
log_info "Esperando 30s para que los servicios arranquen..."
sleep 30

echo ""
echo -e "${BOLD}Estado de los contenedores:${NC}"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || docker compose ps

echo ""
log_section "INSTALACIÓN COMPLETADA"

SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║          DevSecOps Lab - Servicios Disponibles              ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}║${NC}                                                              ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}  ${CYAN}GitLab CE${NC}        http://${SERVER_IP}:8929               ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                   User: root / Pass: DevSecOps2024!          ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                                                              ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}  ${CYAN}SonarQube${NC}        http://${SERVER_IP}:9000               ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                   User: admin / Pass: admin                  ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                                                              ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}  ${CYAN}OWASP ZAP${NC}        http://${SERVER_IP}:8090               ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                   API: http://${SERVER_IP}:8090/JSON/          ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                                                              ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}  ${CYAN}DefectDojo${NC}       http://${SERVER_IP}:8080               ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                   User: admin / Pass: DevSecOps2024!         ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                                                              ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}  ${CYAN}Juice Shop${NC}       http://${SERVER_IP}:3000               ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                   (App vulnerable para prácticas)            ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                                                              ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}  ${CYAN}Grafana${NC}          http://${SERVER_IP}:3001               ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                   User: admin / Pass: DevSecOps2024!         ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                                                              ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}  ${CYAN}Prometheus${NC}       http://${SERVER_IP}:9090               ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                                                              ${BOLD}║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}║${NC}  ${GREEN}Herramientas CLI instaladas:${NC}                               ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}    trivy image <imagen>      (escanear contenedores)         ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}    trivy fs .                (escanear código fuente)         ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}    gitleaks detect .          (buscar secretos en código)     ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}                                                              ${BOLD}║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}║${NC}  ${YELLOW}NOTA:${NC} GitLab tarda ~5 min en arrancar completamente.       ${BOLD}║${NC}"
echo -e "${BOLD}║${NC}  Verifica con: docker compose logs -f gitlab                 ${BOLD}║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}${BOLD}Lab DevSecOps instalado exitosamente.${NC}"
echo -e "Directorio: ${DEVSECOPS_HOME}"
echo -e "Para gestionar: cd ${DEVSECOPS_HOME} && docker compose [up -d|down|logs|ps]"
echo ""
