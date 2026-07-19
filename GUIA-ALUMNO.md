# Guía del Alumno — Construye tu pipeline DevSecOps paso a paso

En esta práctica **tú** montas todo el flujo a mano: creas tu repositorio
en GitLab, generas los tokens/API keys de cada herramienta, configuras las
variables del pipeline y disparas el análisis con un `git push`. Al terminar
entenderás **cada pieza** que normalmente un script automatiza.

> Los servicios (GitLab, SonarQube, DefectDojo, Juice Shop) ya están
> levantados por el instructor. Tú trabajas sobre ellos.

**Accesos** (usuario / contraseña `DevSecOps2024!`):

| Herramienta | URL (navegador)         | Usuario |
|-------------|-------------------------|---------|
| GitLab      | http://localhost:8929   | root    |
| SonarQube   | http://localhost:9000   | admin   |
| DefectDojo  | http://localhost:8080   | admin   |
| Juice Shop  | http://localhost:3000   | (objetivo del DAST) |

> ⚠️ **URLs internas vs. del navegador.** Tú abres las herramientas en
> `localhost:<puerto>`. Pero los *jobs* del pipeline corren dentro de
> contenedores y se hablan entre ellos por **nombre de contenedor**. Por eso
> en las variables usarás `http://devsecops-sonarqube:9000`,
> `http://devsecops-defectdojo:8081`, `http://devsecops-juiceshop:3000`.

---

## Módulo 1 — Prepara el código de la aplicación

Usarás una app Flask *intencionalmente vulnerable*. Crea una carpeta y los
archivos (o cópialos de `sample-project/`):

```bash
mkdir mi-app-devsecops && cd mi-app-devsecops
```

Necesitas al menos estos archivos (mira `sample-project/` como referencia):
- `app.py` — la app con vulnerabilidades plantadas.
- `requirements.txt` — dependencias con CVEs conocidos.
- `Dockerfile` — para construir la imagen (`FROM python:3.9-slim`).
- `sonar-project.properties` — configuración de SonarQube.
- `.gitlab-ci.yml` — el pipeline (lo montamos en el Módulo 6).

---

## Módulo 2 — Crea tu proyecto en GitLab y sube el código

### 2.1 Crear el proyecto (interfaz web)
1. Entra a **http://localhost:8929** (root / `DevSecOps2024!`).
2. Arriba a la derecha: **➕ ▸ New project/repository ▸ Create blank project**.
3. Nombre: `mi-app-<tu-nombre>`. Visibility: **Private**. **Desmarca**
   "Initialize repository with a README". ▸ **Create project**.
4. Copia la URL HTTP del repo (algo como
   `http://localhost:8929/root/mi-app-tunombre.git`).

### 2.2 Generar un token para poder hacer push (PAT)
El push por HTTPS necesita un token, no tu contraseña:
1. Arriba a la derecha: **avatar ▸ Edit profile ▸ Access Tokens**.
2. **Add new token**. Nombre: `push-token`. Scopes: marca **`write_repository`**
   (y `read_repository`). ▸ **Create**. **Copia el token** (`glpat-...`), no
   se vuelve a mostrar.

### 2.3 Subir tu código
```bash
cd mi-app-devsecops
git init -b main
git add .
git config user.email "alumno@lab.local"
git config user.name  "Alumno"
git commit -m "App vulnerable inicial"
# usa tu token en la URL:
git remote add origin http://root:<TU-PAT>@localhost:8929/root/mi-app-tunombre.git
git push -u origin main
```
Refresca el proyecto en GitLab: ya está tu código. *(Todavía no corre nada:
falta configurar el pipeline y sus credenciales.)*

---

## Módulo 3 — El GitLab Runner (quién ejecuta el pipeline)

El pipeline no se ejecuta solo: lo corre un **GitLab Runner**. El instructor
ya registró uno de instancia (compartido) con executor **Docker**.

Verifícalo: **Admin Area (icono llave inglesa) ▸ CI/CD ▸ Runners**. Debe
aparecer uno **online** (verde). Si no hay runner, el pipeline se queda en
`pending` para siempre.

> **Concepto:** el runner tiene montado el socket de Docker y está en la red
> `devsecops-net`, por eso puede *construir imágenes* y *alcanzar* a
> SonarQube/DefectDojo/Juice Shop por su nombre de contenedor.

---

## Módulo 4 — Genera el token de análisis de SonarQube (SAST)

1. Entra a **http://localhost:9000** (admin / `DevSecOps2024!`).
2. Arriba a la derecha: **avatar (A) ▸ My Account ▸ Security**.
3. En **Generate Tokens**: Name = `token-ci`, Type = **User Token** ▸
   **Generate**. **Copia el token** (`squ_...`).

> Este token permite que el job de SonarQube publique el análisis en el
> servidor. Guárdalo, lo usarás en el Módulo 6.

---

## Módulo 5 — Obtén la API key de DefectDojo (gestión de vulnerabilidades)

**Opción A (interfaz):**
1. Entra a **http://localhost:8080** (admin / `DevSecOps2024!`).
2. Menú superior: **avatar ▸ ⚙ (o "API v2 Key")** → verás tu **API Key**.
   Cópiala (40 caracteres hex).

**Opción B (por API, para practicar):**
```bash
curl -s -X POST http://localhost:8080/api/v2/api-token-auth/ \
  --data-urlencode "username=admin" \
  --data-urlencode "password=DevSecOps2024!"
# -> {"token":"xxxxxxxx..."}   copia ese valor
```

> Con esta key, el último job del pipeline importará TODOS los reportes a
> DefectDojo por su API.

---

## Módulo 6 — Configura las variables CI/CD en tu proyecto

Aquí conectas todo. En tu proyecto de GitLab:
**Settings ▸ CI/CD ▸ Variables ▸ Expand ▸ Add variable** (una por una):

| Key                  | Value                                   | Notas |
|----------------------|-----------------------------------------|-------|
| `SONAR_HOST_URL`     | `http://devsecops-sonarqube:9000`       | URL interna |
| `SONAR_TOKEN`        | *(el `squ_...` del Módulo 4)*           | Mask ✔ |
| `DEFECTDOJO_URL`     | `http://devsecops-defectdojo:8081`      | URL interna (puerto 8081) |
| `DEFECTDOJO_API_KEY` | *(la key del Módulo 5)*                 | Mask ✔ |
| `DAST_TARGET`        | `http://devsecops-juiceshop:3000`       | objetivo del DAST |

Para cada una: **Add variable**, pega Key y Value, deja **Protected**
desmarcado (tu rama `main` no es protegida en esta práctica), marca **Masked**
en las dos que son secretos, ▸ **Add variable**.

> **Concepto:** el pipeline lee estas variables como `${SONAR_TOKEN}`, etc.
> Nunca escribas tokens dentro del `.gitlab-ci.yml`: van aquí.

---

## Módulo 7 — Crea el pipeline (`.gitlab-ci.yml`)

Añade a la raíz de tu repo un archivo `.gitlab-ci.yml`. Usa como base el de
`sample-project/.gitlab-ci.yml`. Entiende cada etapa:

```yaml
stages: [secrets, sast, sca, build, container, dast, report]
```
- **secrets** → Gitleaks busca credenciales hardcodeadas.
- **sast** → SonarQube analiza el código y publica en el servidor.
- **sca** → Trivy escanea `requirements.txt` (CVEs de librerías).
- **build** → construye la imagen Docker.
- **container** → Trivy escanea la imagen construida (CVEs del SO).
- **dast** → OWASP ZAP ataca la app en ejecución (`DAST_TARGET`).
- **report** → importa todos los reportes a DefectDojo por su API.

Detalles que DEBEN estar (si no, falla en silencio):
- El job de ZAP hace `mkdir -p /zap/wrk` antes de escanear.
- El import a DefectDojo manda `product_type_name` (para autocrear el producto).

---

## Módulo 8 — Dispara el pipeline

```bash
git add .gitlab-ci.yml
git commit -m "Añade pipeline DevSecOps"
git push
```
Ve a tu proyecto ▸ **Build ▸ Pipelines**. Verás las 7 etapas correr en
cadena, **solo por haber hecho push**. Entra a cada job y lee su log.

> Nota: `secret_scanning` saldrá "naranja" — es correcto: *encontrar*
> secretos hace que el job salga con error, pero `allow_failure: true` deja
> continuar para ver TODOS los hallazgos.

---

## Módulo 9 — Interpreta los resultados

1. **SonarQube** (http://localhost:9000) ▸ tu proyecto: vulnerabilidades y
   "code smells" (SQLi, MD5, command injection…).
2. **DefectDojo** (http://localhost:8080) ▸ producto **"DevSecOps Lab"**:
   TODOS los hallazgos (Gitleaks + Trivy + ZAP) clasificados por severidad.
3. Compara: ¿qué encontró cada herramienta? ¿Qué capa cubre cada una
   (secretos / código / dependencias / imagen / app en ejecución)?

---

## Módulo 10 — Reto: convierte una etapa en *Quality Gate* bloqueante

1. En `.gitlab-ci.yml`, en el job `secret_scanning`, cambia
   `allow_failure: true` por `false`.
2. `git commit -am "quality gate: bloquear si hay secretos" && git push`.
3. Observa cómo ahora el pipeline se pone **ROJO** y, con Merge Requests,
   impediría el merge. **Eso es un control de seguridad que bloquea, no solo
   avisa.**

Extra: corrige una vulnerabilidad real (quita los secretos de `app.py` o
parametriza la query SQL), vuelve a pushear y verifica que desaparece el
hallazgo.

---

## Apéndice — Referencia de URLs internas (para las variables)

| Variable          | Valor interno                        | Por qué |
|-------------------|--------------------------------------|---------|
| SONAR_HOST_URL    | http://devsecops-sonarqube:9000      | job → SonarQube |
| DEFECTDOJO_URL    | http://devsecops-defectdojo:8081     | job → DefectDojo (API) |
| DAST_TARGET       | http://devsecops-juiceshop:3000      | ZAP → app objetivo |

*(Todo corre en la red Docker `devsecops-net`; por eso se usan nombres de
contenedor y no `localhost`.)*
