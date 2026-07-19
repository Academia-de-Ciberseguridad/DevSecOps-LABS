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
- **Jenkins / Prometheus / Grafana** están definidos en el compose pero no se arrancan (el pipeline no los usa). Para levantarlos: `docker compose up -d jenkins prometheus grafana`.
