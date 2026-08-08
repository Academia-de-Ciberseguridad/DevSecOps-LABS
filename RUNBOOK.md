# DevSecOps Lab — Runbook (orden correcto)

Pipeline completo: `git push` → GitLab CI ejecuta **Gitleaks** (secrets) → **SonarQube** (SAST) → **Trivy** (SCA) → **build** → **Trivy image** (container) → **ZAP** (DAST) → **DefectDojo** (consolida todo).

> Requiere ~16 GB de RAM. GitLab tarda ~5 min en arrancar la primera vez.

## Puesta en marcha (3 pasos, EN ESTE ORDEN)

```bash
cd /home/kali/DevSecOps-LABS

# 1) Levantar servicios (GitLab primero; el resto se escalona solo por depends_on)
docker compose up -d gitlab juiceshop defectdojo-db defectdojo-redis
#    …esperar ~4-5 min a que GitLab responda en http://localhost:8929 …
docker compose up -d sonarqube defectdojo defectdojo-nginx defectdojo-celeryworker gitlab-runner

# 2) Registrar el GitLab Runner (genera el PAT de root y lo registra con executor Docker)
./scripts/register-runner.sh

# 3) Conectar herramientas y disparar el pipeline
#    (token Sonar + API key Dojo + crea proyecto + inyecta variables CI/CD + push)
./scripts/bootstrap-integrations.sh
```

Ver el pipeline: **http://localhost:8929/root/devsecops-sample/-/pipelines**

## Accesos (todo con contraseña `DevSecOps2024!`)

| Servicio    | URL                        | Usuario |
|-------------|----------------------------|---------|
| GitLab      | http://localhost:8929      | root    |
| SonarQube   | http://localhost:9000      | admin   |
| DefectDojo  | http://localhost:8080      | admin   |
| Juice Shop  | http://localhost:3000      | (target DAST) |

Los hallazgos quedan en DefectDojo, producto **"DevSecOps Lab"**.

## Re-disparar el pipeline (demo del "alumno que sube código")

`main` es rama protegida → usar push normal, **no** `git push -f`:

```bash
git clone http://root:<PAT>@localhost:8929/root/devsecops-sample.git
cd devsecops-sample
# …editar algo…
git commit -am "cambio" && git push origin main   # dispara un pipeline nuevo
```
(El PAT está en `.lab-credentials`, variable `GITLAB_PAT`.)

## Notas / gotchas resueltos

- **DefectDojo** necesita 5 contenedores (redis + db + initializer + uwsgi + celeryworker). El initializer corre las migraciones y crea el admin; sin él, `/login` da 500 y no hay API key.
- **GitLab** debe tener límite de RAM ≥ 6G. Con 3G se satura al generar el PAT (`gitlab-rails runner`) y da 502.
- El **PAT** de GitLab usa formato "routable" con puntos (`glpat-xxx.01.yyy`); al extraerlo por regex hay que incluir `.`.
- El endpoint `/api/v4/user/runners` exige el scope **`create_runner`** en el PAT.
- El **build** de la app usa `python:3.9-slim` a propósito (las libs viejas vulnerables tienen wheels en 3.9; en 3.11 rompen la compilación).
- El import a **DefectDojo** requiere `product_type_name` para poder autocrear el producto (si no, HTTP 400 silencioso).
- **ZAP** (`zap-baseline.py`) exige que exista `/zap/wrk`; el job hace `mkdir -p /zap/wrk` antes de escanear.
- **Prometheus / Grafana** están definidos en el compose pero no se arrancan (el pipeline no los usa). Para levantarlos: `docker compose up -d prometheus grafana`.

## Jenkins (sesión 2 — orquestador alternativo)

```bash
# Puesta en marcha completa (build + arranque + pre-pull + verificación)
./scripts/setup-jenkins.sh          # ~5-10 min la primera vez

# Subir el Jenkinsfile al repo de GitLab (necesario para "Pipeline from SCM")
./scripts/push-jenkinsfile.sh

# Comprobaciones rápidas
./scripts/setup-jenkins.sh --check      # 7 comprobaciones (~20 s)
./scripts/setup-jenkins.sh --password   # contraseña inicial de desbloqueo
```

Jenkins queda en **http://localhost:8180**. Documentación de la sesión:
`MANUAL-INSTRUCTOR-JENKINS.md` y `docs/jenkins/`.

Notas propias de Jenkins:

- La imagen se **construye** (`config/jenkins/Dockerfile`): la oficial no trae el cliente `docker`, y sin él montar el socket no sirve de nada.
- `JENKINS_HOME` va como **bind mount con la misma ruta dentro y fuera** (`/var/jenkins_home`). Con un volumen con nombre, `docker run -v "$WORKSPACE":/src` montaría un directorio **vacío** y los escáneres dirían "0 hallazgos".
- Los jobs comparten el volumen `trivy-cache` para no re-descargar la BD de CVEs por alumno.
- Credenciales que espera el `Jenkinsfile`: `gitlab-cred` (user+PAT), `sonar-token` y `defectdojo-api-key` (secret text). Sus valores están en `.lab-credentials`.
