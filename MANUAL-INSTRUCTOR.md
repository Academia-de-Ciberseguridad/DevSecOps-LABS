# Manual del Instructor — POC DevSecOps (Shift-Left Security)

Guía detallada para montar y **demostrar en vivo** el flujo completo:
un desarrollador hace `git push` y, sin intervención manual, se ejecutan
todas las validaciones de seguridad y los hallazgos se consolidan en un
gestor de vulnerabilidades.

---

## 1. Objetivo pedagógico

Que el alumno vea, en una sola cadena automática, las capas de seguridad
del ciclo CI/CD (el principio **shift-left**: detectar temprano):

```
  git push ─▶ GitLab CI (Runner) ─▶ pipeline de 7 etapas
     │
     ├─ 1. SECRETS    Gitleaks        ¿hay credenciales hardcodeadas?
     ├─ 2. SAST       SonarQube       análisis estático del código
     ├─ 3. SCA        Trivy (fs)      CVEs en las dependencias
     ├─ 4. BUILD      Docker          construye la imagen
     ├─ 5. CONTAINER  Trivy (image)   CVEs del sistema operativo/imagen
     ├─ 6. DAST       OWASP ZAP       ataca la app en ejecución
     └─ 7. REPORT     DefectDojo      consolida TODOS los hallazgos
```

**Aplicación de práctica:** una app Flask *intencionalmente vulnerable*
(`sample-project/app.py`) con 8 vulnerabilidades plantadas (SQLi, XSS,
command injection, MD5, IDOR, path traversal, secretos, debug on).

---

## 2. Requisitos de la máquina

- **16 GB de RAM** recomendados (GitLab pide holgura; ver §7).
- Docker + Docker Compose v2, `git`, `curl`, `python3`.
- ~25 GB de disco libre.

---

## 3. Puesta en marcha (hazlo ~30 min ANTES de la clase)

> GitLab tarda ~5 min en arrancar la primera vez. No lo dejes para el
> último momento.

### Paso 1 — Levantar los servicios (escalonado, para no saturar)
```bash
cd /home/kali/DevSecOps-LABS

# GitLab (el más pesado) + los ligeros
docker compose up -d gitlab juiceshop defectdojo-db defectdojo-redis

# …esperar a que GitLab responda (http://localhost:8929) ~4-5 min…
# comprobar:  curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8929/users/sign_in   → 200

# El resto (DefectDojo se auto-migra vía el contenedor 'initializer';
# defectdojo-nginx sirve el UI con estilos y hace de proxy al uwsgi)
docker compose up -d sonarqube defectdojo defectdojo-nginx defectdojo-celeryworker gitlab-runner
```

### Paso 2 — Registrar el GitLab Runner
```bash
./scripts/register-runner.sh
```
Qué hace (explícalo a los alumnos): genera un token de acceso (PAT) de
root, crea un *runner de instancia* por API y lo registra con executor
**Docker**. Sin runner, el pipeline se queda en "pending" para siempre.

### Paso 3 — Conectar herramientas y disparar el primer pipeline
```bash
./scripts/bootstrap-integrations.sh
```
Qué hace: cambia la clave inicial de SonarQube y genera su **token**;
obtiene la **API key** de DefectDojo; crea el proyecto `devsecops-sample`
en GitLab; inyecta las **variables CI/CD** (tokens/URLs) a nivel de
proyecto y de instancia; y hace el **push** que dispara el pipeline.

Verifica que quedó verde antes de clase:
`http://localhost:8929/root/devsecops-sample/-/pipelines`

---

## 4. Guion de la demostración en vivo (~20-25 min)

### 4.1 Mostrar el punto de partida
1. Abre **DefectDojo** (http://localhost:8080) → producto *"DevSecOps Lab"*.
   Muestra que ya hay hallazgos del arranque (o vacíalo, ver §7, para
   crearlos en vivo).
2. Abre **SonarQube** (http://localhost:9000) → proyecto `devsecops-sample`.

### 4.2 El disparo automático (el "wow")
Simula que un desarrollador sube un cambio:
```bash
git clone http://root:<PAT>@localhost:8929/root/devsecops-sample.git demo
cd demo
# edita app.py: añade una vuln nueva, o cambia un texto
echo "# cambio en clase" >> app.py
git commit -am "cambio del alumno" && git push origin main
```
(El `<PAT>` está en `.lab-credentials`, variable `GITLAB_PAT`.)

Inmediatamente ve a **CI/CD ▸ Pipelines** en GitLab y muestra cómo, solo
por el push, arrancan las 7 etapas en cadena. **Nadie ejecutó las
herramientas a mano: esa es la idea del DevSecOps.**

### 4.3 Recorrer las etapas mientras corren
- **secrets (Gitleaks)** — abre el job: detecta el token AWS de `app.py`.
  Sale "naranja" (exit 1) porque *encontrar* secretos es un fallo. Punto
  de enseñanza: `allow_failure: true` deja ver todo sin bloquear.
- **sast (SonarQube)** — al terminar, en el UI de SonarQube salen SQLi,
  command injection, MD5, etc.
- **sca (Trivy fs)** — CVEs de `requirements.txt` (libs viejas a propósito).
- **build / container (Trivy image)** — CVEs del SO base de la imagen.
- **dast (ZAP)** — ataca Juice Shop en ejecución (headers faltantes, etc.).
- **report (DefectDojo)** — importa TODO por la API.

### 4.4 El resultado consolidado
Vuelve a **DefectDojo**: el producto *"DevSecOps Lab"* ahora tiene los
hallazgos de todas las herramientas clasificados por severidad
(Critical/High/Medium/Low/Info) y por tipo de escaneo. **Un solo panel
para gobernar la vulnerabilidad del proyecto.**

---

## 5. Conceptos clave a transmitir

| Sigla | Qué es | Herramienta | Encuentra… |
|-------|--------|-------------|------------|
| Secret Scanning | Buscar credenciales en el código/historial | Gitleaks | API keys, tokens, passwords |
| **SAST** | Análisis estático (sin ejecutar) | SonarQube | SQLi, XSS, hashes débiles, code smells |
| **SCA** | Análisis de dependencias | Trivy fs | CVEs de librerías |
| Container Scanning | Escaneo de la imagen | Trivy image | CVEs del SO/paquetes |
| **DAST** | Análisis dinámico (app corriendo) | OWASP ZAP | XSS reflejado, headers, config |
| Vuln Management | Consolidación y gestión | DefectDojo | (agrega todo lo anterior) |

Idea central: **shift-left** = mover la seguridad lo más temprano posible
en el ciclo (en el `push`, no en producción). Cada herramienta cubre una
capa distinta; ninguna sola es suficiente.

---

## 6. Ejercicios para los alumnos

1. **Quality Gate bloqueante:** en `.gitlab-ci.yml`, cambiar
   `allow_failure: true` por `false` en `secret_scanning` y volver a
   pushear. Observar cómo ahora el pipeline se pone ROJO y (con Merge
   Requests) impediría el merge.
2. **Corregir una vulnerabilidad:** quitar los secretos hardcodeados de
   `app.py` o parametrizar la query SQL, pushear, y ver cómo desaparecen
   hallazgos en la siguiente corrida.
3. **Subir de severidad Trivy:** añadir `--exit-code 1` a Trivy para que
   falle si hay CVEs CRITICAL.
4. **Triage en DefectDojo:** marcar un hallazgo como falso positivo /
   aceptado y discutir el flujo de gestión de riesgo.

---

## 7. Accesos, credenciales y reseteo

**Accesos** (todo con contraseña `DevSecOps2024!`):

| Servicio    | URL                     | Usuario |
|-------------|-------------------------|---------|
| GitLab      | http://localhost:8929   | root    |
| SonarQube   | http://localhost:9000   | admin   |
| DefectDojo  | http://localhost:8080   | admin   |
| Juice Shop  | http://localhost:3000   | (objetivo del DAST) |

Tokens generados automáticamente en `.lab-credentials` (NO se commitea).

**Vaciar DefectDojo para demostrar la carga en vivo:** en el UI, producto
*"DevSecOps Lab"* ▸ borrar engagements; o simplemente pushear de nuevo y
mostrar el engagement nuevo por pipeline.

**Apagar / encender entre clases:**
```bash
docker compose stop        # apaga sin borrar datos
docker compose start       # vuelve a encender (rápido)
```

**Reset total (borra TODO y empieza limpio):**
```bash
docker compose down -v     # borra volúmenes; luego repetir §3 pasos 1-3
```

---

## 8. Troubleshooting (fallos ya resueltos, por si reaparecen)

- **DefectDojo da 500 / no da API key** → faltan contenedores. Deben estar
  arriba `defectdojo-redis`, `defectdojo-db`, y el `defectdojo-initializer`
  debe haber salido con código 0 (`docker logs devsecops-dojo-initializer`).
- **GitLab da 502 / el runner no se registra** → GitLab se satura si su
  límite de RAM es bajo. Debe ser **6G** (ya está en `docker-compose.yml`).
- **El pipeline queda "pending"** → no hay runner. Re-ejecuta
  `./scripts/register-runner.sh` y comprueba
  `http://localhost:8929/admin/runners` (debe salir online).
- **El job `report` importa 0 findings** → el import necesita
  `product_type_name` (ya incluido en `.gitlab-ci.yml`).
- **ZAP no genera reporte** → el job crea `/zap/wrk` antes de escanear
  (ya incluido).
- **Push rechazado a `main`** → `main` está protegida; usa push normal, no
  `git push -f`.

---

> Referencia rápida de comandos: ver `RUNBOOK.md`.
