# DevSecOps Lab - Entorno Completo de Seguridad en CI/CD

Laboratorio automatizado que despliega un stack DevSecOps completo sobre Ubuntu Server con Docker.
Incluye todas las herramientas necesarias para implementar seguridad en cada fase del pipeline CI/CD.

---

## Herramientas incluidas

| Herramienta | Tipo | Puerto | Función |
|-------------|------|--------|---------|
| **GitLab CE** | SCM + CI/CD | 8929 | Control de versiones y pipeline de integración continua |
| **SonarQube** | SAST | 9000 | Análisis estático de código fuente |
| **OWASP ZAP** | DAST | 8090 | Análisis dinámico de aplicaciones en ejecución |
| **Trivy** | SCA + Container | CLI | Escaneo de dependencias y contenedores |
| **Gitleaks** | Secret Scanning | CLI | Detección de secretos en código fuente |
| **DefectDojo** | Vuln Management | 8080 | Gestión centralizada de vulnerabilidades |
| **Juice Shop** | Target App | 3000 | Aplicación vulnerable para prácticas DAST |
| **Grafana** | Monitoring | 3001 | Dashboards y visualización de métricas |
| **Prometheus** | Metrics | 9090 | Recolección de métricas del sistema |

---

## Requisitos mínimos

- **SO**: Ubuntu 20.04 / 22.04 / 24.04 LTS (Server o Desktop)
- **RAM**: 8 GB mínimo (16 GB recomendado)
- **Disco**: 30 GB libres mínimo (50 GB recomendado)
- **CPU**: 4 cores mínimo
- **Red**: Conexión a internet para descargar imágenes Docker

---

## Instalación

```bash
# 1. Clonar o copiar la carpeta DevSecOps-Lab al servidor Ubuntu
scp -r DevSecOps-Lab/ usuario@servidor:~/

# 2. Conectar al servidor
ssh usuario@servidor

# 3. Ejecutar el script de instalación
cd ~/DevSecOps-Lab
chmod +x install.sh
sudo ./install.sh
```

El script automáticamente:
1. Actualiza el sistema e instala dependencias
2. Instala Docker + Docker Compose
3. Configura swap de 4GB (necesario para 8GB RAM)
4. Optimiza parámetros del kernel
5. Instala Trivy y Gitleaks como CLI
6. Levanta todos los servicios Docker
7. Muestra URLs y credenciales de acceso

---

## Acceso a los servicios

Después de la instalación, los servicios estarán disponibles en:

| Servicio | URL | Usuario | Contraseña | Notas |
|----------|-----|---------|------------|-------|
| **GitLab CE** | `http://<IP>:8929` | `root` | `DevSecOps2024!` | SSH disponible en puerto `2224` |
| **SonarQube** | `http://<IP>:9000` | `admin` | `admin` | Pide cambio de contraseña en el primer login |
| **OWASP ZAP** | `http://<IP>:8090` | -- | -- | API sin autenticación (`api.disablekey=true`) |
| **DefectDojo** | `http://<IP>:8080` | `admin` | `DevSecOps2024!` | Backend PostgreSQL |
| **Juice Shop** | `http://<IP>:3000` | -- | -- | App vulnerable, no requiere login inicial |
| **Grafana** | `http://<IP>:3001` | `admin` | `DevSecOps2024!` | Datasource Prometheus preconfigurado |
| **Prometheus** | `http://<IP>:9090` | -- | -- | Sin autenticación |

> **Nota**: GitLab CE tarda ~5 minutos en arrancar completamente. Puedes verificar su estado con:
> ```bash
> curl -s http://localhost:8929/-/readiness
> ```

### Credenciales por defecto

Todas las contraseñas por defecto están definidas en el archivo `.env` en la raíz del proyecto.
Puedes modificarlas **antes** de ejecutar `install.sh` o `docker compose up -d`:

```bash
# .env - Variables principales de credenciales
GITLAB_ROOT_PASSWORD=DevSecOps2024!    # root password de GitLab
DD_ADMIN_PASSWORD=DevSecOps2024!       # admin password de DefectDojo
GF_SECURITY_ADMIN_PASSWORD=DevSecOps2024!  # admin password de Grafana
SONAR_JDBC_USERNAME=sonar              # usuario BD interna de SonarQube
SONAR_JDBC_PASSWORD=sonar              # password BD interna de SonarQube
```

> **Importante**: SonarQube usa credenciales internas `admin/admin` que no se configuran desde `.env`. Cambia la contraseña en el primer acceso desde la interfaz web.

### Puertos utilizados

| Puerto | Servicio | Protocolo |
|--------|----------|-----------|
| `8929` | GitLab CE (HTTP) | HTTP |
| `2224` | GitLab CE (SSH) | SSH |
| `9000` | SonarQube | HTTP |
| `8090` | OWASP ZAP (API) | HTTP/REST |
| `8080` | DefectDojo | HTTP |
| `3000` | Juice Shop | HTTP |
| `3001` | Grafana | HTTP |
| `9090` | Prometheus | HTTP |

Todos los puertos son configurables desde el archivo `.env`.

---

## Gestión del laboratorio

Usar el script de gestión:

```bash
chmod +x scripts/lab-manager.sh

# Ver estado de los servicios
./scripts/lab-manager.sh status

# Ver URLs y credenciales
./scripts/lab-manager.sh urls

# Verificar salud de servicios
./scripts/lab-manager.sh health

# Ver uso de RAM por contenedor
./scripts/lab-manager.sh ram

# Ejecutar escaneo completo de la app de ejemplo
./scripts/lab-manager.sh scan-app

# Ver logs
./scripts/lab-manager.sh logs
./scripts/lab-manager.sh logs gitlab    # logs de un servicio específico

# Iniciar / Detener / Reiniciar
./scripts/lab-manager.sh start
./scripts/lab-manager.sh stop
./scripts/lab-manager.sh restart
```

---

## Guía de práctica: Pipeline DevSecOps

### Paso 1: Crear proyecto en GitLab

1. Accede a GitLab (`http://<IP>:8929`)
2. Crea un nuevo proyecto: "devsecops-sample"
3. Sube el contenido de `sample-project/`:
   ```bash
   cd sample-project
   git init
   git remote add origin http://<IP>:8929/root/devsecops-sample.git
   git add .
   git commit -m "Initial commit - vulnerable app"
   git push -u origin main
   ```

### Paso 2: Ejecutar escaneos manuales

```bash
# Secret Scanning
gitleaks detect --source ./sample-project --verbose

# SCA - Escanear dependencias
trivy fs --severity HIGH,CRITICAL ./sample-project

# Container Scanning
cd sample-project && docker build -t sample-app:test .
trivy image --severity HIGH,CRITICAL sample-app:test

# DAST - Escanear Juice Shop con ZAP
curl "http://localhost:8090/JSON/spider/action/scan/?url=http://devsecops-juiceshop:3000"
curl "http://localhost:8090/JSON/ascan/action/scan/?url=http://devsecops-juiceshop:3000"
```

### Paso 3: Configurar SonarQube

1. Accede a SonarQube (`http://<IP>:9000`)
2. Cambia la contraseña por defecto (admin/admin)
3. Crea un token: User > My Account > Security > Generate Token
4. Escanea el proyecto:
   ```bash
   docker run --rm \
     --network devsecops-lab_devsecops-net \
     -v "$(pwd)/sample-project:/usr/src" \
     sonarsource/sonar-scanner-cli \
     -Dsonar.projectKey=devsecops-sample \
     -Dsonar.sources=/usr/src \
     -Dsonar.host.url=http://devsecops-sonarqube:9000 \
     -Dsonar.login=<TU_TOKEN>
   ```

### Paso 4: Ejecutar DAST con ZAP

```bash
# Escaneo rápido (baseline) contra Juice Shop
docker exec devsecops-zap zap-baseline.py \
  -t http://devsecops-juiceshop:3000 \
  -r /zap/wrk/zap-report.html

# Copiar reporte
docker cp devsecops-zap:/zap/wrk/zap-report.html ./zap-report.html
```

### Paso 5: Importar resultados en DefectDojo

1. Accede a DefectDojo (`http://<IP>:8080`)
2. Crea un producto: "DevSecOps Lab"
3. Crea un engagement: "CI/CD Pipeline"
4. Importa los reportes (Trivy JSON, ZAP JSON, Gitleaks JSON)
5. Revisa las vulnerabilidades consolidadas

---

## Mapeo con DSOMM (DevSecOps Maturity Model)

| Nivel DSOMM | Herramientas del Lab | Práctica |
|-------------|---------------------|----------|
| **Nivel 1** - Básico | Gitleaks, Trivy CLI | Escaneo manual de secretos y dependencias |
| **Nivel 2** - Gestionado | SonarQube, ZAP | SAST y DAST integrados al desarrollo |
| **Nivel 3** - Definido | GitLab CI + Pipeline | Automatización de seguridad en CI/CD |
| **Nivel 4** - Cuantitativo | DefectDojo, Grafana | Métricas y gestión centralizada de vulnerabilidades |

---

## Estructura del proyecto

```
DevSecOps-Lab/
├── install.sh                 # Script de instalación automatizada
├── docker-compose.yml         # Definición de todos los servicios
├── .env                       # Variables de configuración
├── README.md                  # Este archivo
├── config/
│   ├── prometheus/
│   │   └── prometheus.yml     # Configuración de Prometheus
│   └── grafana/
│       └── provisioning/
│           └── datasources/
│               └── prometheus.yml  # Datasource auto-configurado
├── scripts/
│   └── lab-manager.sh         # Script de gestión del lab
└── sample-project/
    ├── .gitlab-ci.yml         # Pipeline CI/CD DevSecOps completo
    ├── app.py                 # App vulnerable (educativa)
    ├── requirements.txt       # Dependencias con CVEs conocidos
    ├── Dockerfile             # Dockerfile de la app
    └── sonar-project.properties  # Config para SonarQube
```

---

## Solución de problemas

```bash
# GitLab no arranca (necesita más tiempo)
docker compose logs -f gitlab
# Esperar hasta ver: "gitlab Reconfigured!"

# SonarQube falla con error de memoria
sudo sysctl -w vm.max_map_count=524288

# Ver qué consume más RAM
docker stats --no-stream | sort -k4 -h -r

# Reiniciar un servicio específico
docker compose restart sonarqube

# Reconstruir todo desde cero
docker compose down -v
sudo ./install.sh
```
