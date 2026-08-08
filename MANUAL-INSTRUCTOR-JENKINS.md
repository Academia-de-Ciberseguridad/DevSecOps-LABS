# Manual del Instructor — Sesión 2: Jenkins

Guía para impartir la clase de **90 minutos** sobre Jenkins, partiendo de lo que
los alumnos ya montaron con GitLab CI en la sesión anterior.

---

## 0. Estado actual del laboratorio (ya validado end-to-end)

Todo esto **ya está hecho y probado** en esta máquina:

| Elemento | Estado |
|----------|--------|
| Docker | 28.5.2 + Compose 2.40.3, servicio activo, usuario `kali` en el grupo `docker` |
| Imagen `devsecops-jenkins:lts` | construida (Jenkins LTS jdk21 + docker CLI 29.7.2 + 83 plugins) |
| Jenkins | `http://localhost:8180` — **asistente ya completado**, `admin` / `DevSecOps2024!`, 4 executors |
| Credenciales en Jenkins | `gitlab-cred`, `sonar-token`, `defectdojo-api-key` ya creadas |
| Job `demo-instructor` | Pipeline from SCM, con 4 builds de referencia (ver abajo) |
| GitLab / DefectDojo / Juice Shop | arriba, integrados, con datos |
| **SonarQube** | **APAGADO a propósito** para liberar RAM — ver §0-bis |
| Rama `fix-secretos` en `devsecops-sample` | creada para el reto final |

**Builds de referencia ya ejecutados** (útiles para enseñar sin esperar):

| Build | Parámetros | Resultado | Duración real |
|-------|-----------|-----------|---------------|
| #1 | SAST on, DAST off | 🟡 UNSTABLE | **41 s** |
| #2 | SAST on, **DAST on** | 🟡 UNSTABLE | **81 s** |
| #3 | quality gate ON | 🔴 FAILURE | **4 s** |
| #4 | quality gate ON, rama `fix-secretos` | 🔴 FAILURE | **4 s** |

Con las cachés calientes el pipeline completo son **~40-80 segundos**, no minutos.
Ese es el escenario de un alumno; con 15 en paralelo y 4 executors, cuenta con colas.

> Si solo vas a repasar antes de clase: `./scripts/setup-jenkins.sh --check` y
> abre `http://localhost:8180/job/demo-instructor/`.

### §0-bis — SonarQube está apagado: plan para la clase

La máquina tiene 9,5 GB y con todo encendido quedaban **1,7 GB libres**. Con 15 alumnos
lanzando pipelines eso se agota. Apagar SonarQube libera **1,3 GB** (quedan 3,0 GB).

**El pipeline lo detecta solo.** La etapa SAST hace un `curl` a SonarQube antes de
escanear: si no responde, imprime un aviso, **se salta en VERDE** y el resto del pipeline
sigue. Verificado en el build #5: 19 s, 6 etapas OK, 3 informes en DefectDojo, ninguna
etapa roja. El alumno no ve un error, ve una explicación.

**Plan recomendado para los 90 minutos:**

| Momento | Acción |
|---------|--------|
| Toda la práctica (0:40 – 1:15) | SonarQube **apagado**. Máxima RAM para los alumnos. |
| ~1:10 (mientras siguen trabajando) | `docker compose start sonarqube-db sonarqube` — tarda 1-2 min en levantar |
| 1:20 (cierre) | Ya está arriba: enseñas los **Security Hotspots** y la lección de "0 Vulnerabilities" con el proyecto `jenkins-demo-instructor` que ya tiene datos del build #1 |

```bash
# encender antes del cierre
docker compose start sonarqube-db sonarqube
# comprobar que está UP (1-2 min)
curl -s http://localhost:9000/api/system/status

# volver a apagarlo
docker compose stop sonarqube sonarqube-db
```

> Los datos del análisis del build #1 **siguen guardados** en SonarQube: al encenderlo
> vuelve a aparecer el proyecto con sus 6 hotspots. No hace falta relanzar nada.
>
> Si prefieres SonarQube encendido toda la clase, hazlo — pero entonces pide a los alumnos
> que **no** marquen `RUN_DAST`, que es lo que más memoria consume.

**Materiales de la sesión**

| Fichero | Para quién | Qué es |
|---------|------------|--------|
| `docs/jenkins/Presentacion-Jenkins-DevSecOps.pdf` | proyectar / alumnos | 33 diapositivas 16:9 |
| `docs/jenkins/Practica-Jenkins-Alumno.pdf` | alumnos | Guía paso a paso autocontenida (18 pág.) |
| `sample-project/Jenkinsfile` | el lab | El pipeline completo, comentado línea a línea |
| `config/jenkins/Dockerfile` + `plugins.txt` | el lab | Imagen de Jenkins con docker CLI y plugins |
| `scripts/setup-jenkins.sh` | tú | Deja Jenkins listo y verifica que todo funciona |
| `scripts/push-jenkinsfile.sh` | tú | Sube el `Jenkinsfile` al repo de GitLab |

> Los HTML fuente están junto a los PDF. Para regenerarlos:
> `weasyprint docs/jenkins/presentacion-jenkins.html docs/jenkins/Presentacion-Jenkins-DevSecOps.pdf`

---

## 1. Preparación (haz esto ~40 minutos ANTES de clase)

### Paso 1 — Levantar el laboratorio base

```bash
cd /home/kali/DevSecOps-LABS

# Si el lab está apagado desde la clase anterior:
docker compose start          # rápido, conserva los datos

# Si empiezas de cero, sigue el RUNBOOK.md (GitLab tarda ~5 min)
```

> ⚠️ **Ejecuta todos los `docker compose` desde el MISMO directorio.** Compose deriva
> el nombre del proyecto del nombre de la carpeta. Si levantaste el laboratorio desde
> `/opt/devsecops-lab` y ejecutas `setup-jenkins.sh` desde el checkout de git, tendrás
> **dos stacks separados**: `docker compose ps` no verá los servicios del otro y los
> `docker compose stop` no apagarán lo que crees.

Para la clase de Jenkins **necesitas arriba**: `gitlab`, `sonarqube`,
`defectdojo` (+ `defectdojo-db`, `-redis`, `-nginx`, `-celeryworker`), `juiceshop`.
**Puedes apagar** para liberar RAM: `gitlab-runner`, `prometheus`, `grafana`.

```bash
docker compose stop gitlab-runner prometheus grafana
```

### Paso 2 — Construir y arrancar Jenkins

```bash
./scripts/setup-jenkins.sh
```

Tarda **5-10 minutos** la primera vez. Hace, en este orden:

1. Crea `/var/jenkins_home` en el host (bind mount con ruta idéntica dentro/fuera).
2. Crea el volumen `trivy-cache` (caché de CVEs compartida entre alumnos).
3. Construye `devsecops-jenkins:lts` = Jenkins LTS + **cliente Docker** + plugins.
4. Arranca Jenkins y espera a que responda en `http://localhost:8180`.
5. **Pre-descarga** las imágenes de las herramientas y la BD de Trivy.
6. Ejecuta un smoke test de 7 comprobaciones.
7. Imprime la contraseña inicial de desbloqueo.

### Paso 3 — Completar el asistente de Jenkins (2 min, en el navegador)

> **Ya está hecho** en esta máquina (`admin` / `DevSecOps2024!`). Este paso solo aplica
> si reinstalas desde cero (`./scripts/setup-jenkins.sh --reset`).

1. `http://localhost:8180` → pega la contraseña que imprimió el script.
2. **"Customize Jenkins"** → **Select plugins to install** → botón **None** → **Install**.
   *(Los plugins ya están dentro de la imagen: no hay que descargar nada.)*
3. Crea el usuario admin del laboratorio. Sugerencia: `admin` / `DevSecOps2024!`.
4. **Instance Configuration**: deja `http://localhost:8180/` → **Save and Finish**.

### Paso 4 — Ajustes para clase compartida

- **Executors**: *Manage Jenkins ▸ Nodes ▸ Built-In Node ▸ Configure ▸
  Number of executors = **4*** (con 4 vCPU, más solo genera contención).
- **Usuario para alumnos** (si no quieres darles el admin):
  *Manage Jenkins ▸ Users ▸ Create User* → `alumno` / `DevSecOps2024!`.
  Con la estrategia de autorización por defecto tendrá permisos suficientes.
- **Credenciales globales compartidas** — créalas tú una vez, así los alumnos
  no se bloquean si no llegan a generarlas
  (*Manage Jenkins ▸ Credentials ▸ System ▸ Global credentials ▸ Add Credentials*):

  | Kind | ID | Valor |
  |------|----|-------|
  | Secret text | `sonar-token` | `SONAR_TOKEN` de `.lab-credentials` |
  | Secret text | `defectdojo-api-key` | `DD_API_KEY` de `.lab-credentials` |
  | Username with password | `gitlab-cred` | `root` / `GITLAB_PAT` de `.lab-credentials` |

  ```bash
  cat .lab-credentials     # aquí están los tres valores
  ```

### Paso 5 — Subir el Jenkinsfile al repositorio

```bash
./scripts/push-jenkinsfile.sh
```

Sin esto, el **Nivel 3** ("Pipeline script from SCM") no encuentra el fichero.
Compruébalo en `http://localhost:8929/root/devsecops-sample` — debe verse `Jenkinsfile`.

### Paso 6 — Ensayo (IMPRESCINDIBLE)

Crea un job `demo-instructor` (Pipeline script from SCM) y **lánzalo entero una vez**,
con `RUN_SAST` y `RUN_DAST` marcados. Objetivos:

- Confirmar que las 7 etapas pasan.
- **Calentar las cachés**: capas de Docker, BD de Trivy, sesión de Sonar. El primer
  pipeline de la clase será entonces mucho más rápido.
- Tener un build de referencia que enseñar si algo se tuerce en vivo.

### Checklist final (T-5 min)

```bash
./scripts/setup-jenkins.sh --check     # 7 comprobaciones, ~20 segundos
docker stats --no-stream               # ¿queda RAM libre?
```

- [ ] Jenkins responde y tú puedes hacer login
- [ ] `docker version` funciona dentro del contenedor de Jenkins
- [ ] Las rutas de `JENKINS_HOME` coinciden dentro y fuera
- [ ] Las 3 credenciales globales existen
- [ ] El repo `devsecops-sample` tiene el `Jenkinsfile`
- [ ] El job `demo-instructor` tiene al menos un build correcto
- [ ] PDF de la práctica repartido o accesible para los alumnos

---

## 2. Guion de los 90 minutos

| Tiempo | Diapositivas | Bloque | Notas para ti |
|--------|--------------|--------|---------------|
| **0:00 – 0:10** | 1-5 | De dónde venimos | Recupera el pipeline de la sesión anterior. Lanza la pregunta: *"¿quién ejecutaba todo eso?"* |
| **0:10 – 0:30** | 6-16 | Qué es Jenkins | Teoría útil: arquitectura, tipos de job, plugins, credenciales, Jenkinsfile, semáforo, disparadores |
| **0:30 – 0:40** | 17-21 | Jenkins + Docker + demo | Aquí proyectas Jenkins en vivo (§3) |
| **0:40 – 1:20** | 22-27 | **PRÁCTICA** | Ellos trabajan; tú circulas. Diapositivas como referencia visual |
| **1:20 – 1:30** | 28-33 | Resultados y cierre | DefectDojo con engagements de los dos orquestadores; comparativa; seguridad del CI |

### Tres resultados que TE VAN A PREGUNTAR (verificados en ejecución real)

Estos tres los ha comprobado el laboratorio de verdad. No son teoría, y son los
mejores momentos didácticos de la sesión: **apóyate en ellos, no los esquives.**

**1. «SonarQube dice 0 Vulnerabilities. ¿Está roto?»**
No. Es la **edición Community**. La detección de inyecciones (SQLi, command injection)
necesita *taint analysis*, que es de pago (Developer Edition+). Community da
**6 Security Hotspots**: contraseña hardcodeada, CSRF desactivado, hash MD5, imagen
como root. Mensaje: *el SAST gratuito cubre una parte; ninguna herramienta sola basta.*

**2. «Gitleaks solo encuentra 1 secreto y en `app.py` hay tres.»**
Correcto: encuentra el token de AWS (`aws-access-token`, línea 23) porque tiene un
**patrón reconocible**. `DATABASE_PASSWORD = "SuperSecret123!"` no encaja con ninguna
regla → **falso negativo**. Y el remate: **SonarQube SÍ marca esa contraseña** y en cambio
no ve el token de AWS. *Cada herramienta tapa el agujero de la otra.*

**3. «He quitado el secreto y el build SIGUE en rojo.»**
El mejor momento de la clase. Gitleaks analiza **todo el historial de git**, y el commit
viejo sigue ahí. Demuéstralo en vivo con el mismo código:

```bash
cd /ruta/al/repo
# solo el código actual  -> "no leaks found", exit 0
docker run --rm -v "$PWD":/src ghcr.io/gitleaks/gitleaks:v8.18.4 detect --source /src --no-git --redact
# código + historial      -> "3 commits scanned … leaks found: 1", exit 1
docker run --rm -v "$PWD":/src ghcr.io/gitleaks/gitleaks:v8.18.4 detect --source /src --redact
```

Conclusión: **un secreto commiteado está quemado.** Borrarlo del fichero no lo borra de
la historia, ni de los forks, ni de los backups. Lo único que sirve es **rotar la credencial**.
La rama `fix-secretos` ya está creada en `devsecops-sample` para enseñarlo sin escribir código:
lanza el job con `GIT_BRANCH=fix-secretos` y `BLOQUEAR_SI_HAY_SECRETOS` marcado.

### Los cinco mensajes que deben salir de clase

1. **Jenkins no analiza nada: orquesta.** Las herramientas son las mismas de la sesión anterior.
2. **Pipeline as Code**: la automatización es código versionado y revisable.
3. **Los secretos van en Credentials**, nunca en el fichero.
4. **Verde/amarillo/rojo es una decisión de seguridad**, no un color.
5. **El CI es un activo crítico**: quien lo controla, controla lo que llega a producción.

---

## 3. Demo en vivo (10 minutos, minuto 0:30)

Proyecta Jenkins y haz esto delante de ellos, narrando:

1. **Dashboard** — "esta lista son jobs; la bola de color es el último resultado".
2. **New Item ▸ Pipeline** — crea `demo-clase`, y pega:
   ```groovy
   pipeline {
     agent any
     stages {
       stage('Saludo') { steps { sh 'date; whoami; pwd' } }
       stage('¿Docker?') { steps { sh 'docker version --format "{{.Server.Version}}"' } }
     }
   }
   ```
3. **Build Now** → abre **Console Output** en directo.
   - Señala `whoami → root` y `pwd → /var/jenkins_home/workspace/demo-clase`.
   - **Momento clave:** "acabamos de comprobar que Jenkins puede lanzar contenedores.
     Ese es el motor de todo lo que viene."
4. **Rompe algo**: cambia `date` por `fecha`, relanza, enseña el rojo y el `exit code 127`.
   - "Regla: código de salida ≠ 0 → falla la etapa → se para el pipeline. **Recordad esto**,
     porque en un rato lo vamos a usar a propósito para bloquear despliegues inseguros."
5. Abre el job `demo-instructor` (el del ensayo) y enseña un **build completo ya hecho**:
   Stage View con las 7 etapas, artefactos, y —si lo ejecutaste con DAST— la pestaña
   **Informe OWASP ZAP**. Así ven el destino antes de empezar el viaje.

---

## 4. Durante la práctica: dónde se atascan

| Minuto aprox. | Atasco típico | Qué decir / hacer |
|---------------|---------------|-------------------|
| 0:45 | No encuentran **Pipeline** en New Item | Está debajo de "Freestyle project"; hay que bajar |
| 0:50 | Copian el script con comillas "curvas" del PDF | Que lo escriban a mano o usen el HTML; las comillas tipográficas rompen Groovy |
| 0:55 | `Could not find credentials entry with ID` | El ID debe ser **idéntico**. Enséñales la lista de credenciales |
| 1:00 | Usan `localhost` en la URL del repo | Diapositiva 23: dentro del pipeline se usan **nombres de contenedor** |
| 1:05 | Builds en cola | Normal: 4 executors, 15 alumnos. Que aprovechen para leer el log del anterior |
| 1:10 | Marcan `RUN_DAST` todos a la vez | Pídeles que **no** lo marquen; que lo pruebe uno solo y se proyecte |
| 1:15 | "Me sale amarillo, ¿está mal?" | **Amarillo es el resultado correcto.** La app es vulnerable a propósito |
| 1:15 | "SonarQube dice 0 vulnerabilidades" | Ver §4-bis punto 1: es Community, mira **Security Hotspots** |
| 1:18 | "Arreglé el secreto y sigue rojo" | Ver §4-bis punto 3: Gitleaks lee **el historial**. Es la lección, no un fallo |

**Regla de oro que debes repetir**: *"antes de preguntar, abre el Console Output
y busca la primera línea en rojo"*. Es la habilidad que de verdad se llevan.

---

## 5. Cierre (minuto 1:20)

1. Abre **DefectDojo** → producto **"DevSecOps Lab"** → lista de engagements.
   Ahí conviven `Pipeline #N` (GitLab CI) y `Jenkins #N (pipeline-alumno)`.
   > *"Dos orquestadores distintos, un único panel de riesgo. A la empresa no le
   > importa qué CI usó cada equipo: le importa cuántas críticas tiene abiertas."*
2. Abre **SonarQube** y enseña varios proyectos `jenkins-pipeline-<nombre>`: cada
   alumno tiene el suyo.
3. Diapositiva 30 (comparativa) y 31 (seguridad del propio Jenkins). Insiste en que
   **este laboratorio incumple varias buenas prácticas a propósito** — Jenkins como
   root, socket de Docker montado, todos administradores — y en que deben saberlo.
4. Diapositiva 32: las 8 ideas.

---

## 6. Decisiones de diseño del laboratorio (por si preguntan)

- **Imagen de Jenkins propia.** La oficial `jenkins/jenkins:lts-jdk17` **no trae el
  cliente `docker`**; montar el socket sin él no sirve de nada. Además pre-instalamos
  los plugins para no depender de internet en clase.
- **`/var/jenkins_home` como bind mount con la misma ruta dentro y fuera.** Es el
  fallo clásico: en `docker run -v "$WORKSPACE":/src`, esa ruta la resuelve el
  **demonio del host**. Con un volumen con nombre, Docker montaría un directorio
  **vacío** y los escáneres dirían "0 hallazgos" — un falso verde.
- **`docker run` explícito en vez de `agent { docker { … } }`.** Es más verboso,
  pero se ve exactamente qué imagen se usa y qué se monta. Para una primera clase
  la transparencia gana a la elegancia.
- **Caché `trivy-cache` compartida.** Sin ella cada alumno se baja ~50 MB de CVEs
  y se agotan los límites de descarga de ghcr.io.
- **DAST opcional (`RUN_DAST`, por defecto `false`).** Un baseline de ZAP son 3-5
  minutos; 15 en paralelo tumban el laboratorio.
- **`catchError` en casi todas las etapas.** Que un fallo de SonarQube no impida
  que el alumno vea los resultados de Trivy y de DefectDojo.

---

## 7. Troubleshooting del instructor

| Síntoma | Causa | Solución |
|---------|-------|----------|
| `docker compose build jenkins` falla bajando `docker-ce-cli` | Sin salida a internet o repo de Docker caído | Alternativa: en `config/jenkins/Dockerfile`, sustituye el bloque del repo oficial por `apt-get install -y docker.io` (más pesado, pero funciona con los repos de Debian) |
| Jenkins arranca pero `docker: not found` en los jobs | Se levantó la imagen oficial, no la construida | `docker compose build jenkins && docker compose up -d --force-recreate jenkins` |
| Los escáneres no encuentran nada, con el código presente | Rutas de workspace distintas | `./scripts/setup-jenkins.sh --check` (comprobación 4). Revisa el bind mount de `/var/jenkins_home` |
| `permission denied /var/run/docker.sock` | El contenedor no corre como root | El `docker-compose.yml` debe tener `user: root` en el servicio `jenkins` |
| Builds eternos en cola | Pocos executors | Súbelos a 4-6 en *Built-In Node ▸ Configure* |
| Jenkins se reinicia solo / OOM | Límite de memoria justo | Sube `memory: 1536M` y `-Xmx768m`; o apaga `sonarqube` durante la práctica y desmarca `RUN_SAST` |
| ZAP no genera informe | Permisos de escritura en `/zap/wrk` | El Jenkinsfile ya crea `zapout` con `chmod 777`. Verifica que la etapa lo hizo |
| DefectDojo devuelve 400 al importar | Falta `product_type_name` o API key inválida | Ya va incluido; regenera la API key y actualiza la credencial |
| El alumno no ve **Build with Parameters** | Jenkins registra los parámetros al primer build | Lanzar una vez con **Build Now** |
| Perdiste la contraseña inicial | — | `./scripts/setup-jenkins.sh --password` |

### Reset entre clases

```bash
# Apagar sin perder nada
docker compose stop

# Borrar SOLO Jenkins y empezar limpio (conserva el resto del laboratorio)
./scripts/setup-jenkins.sh --reset   # pide confirmación
./scripts/setup-jenkins.sh           # vuelve a crear todo y da la contraseña nueva

# Limpiar las imágenes que construyeron los alumnos
docker image prune -f
```

> ⚠️ **`docker compose down -v` NO borra Jenkins.** `JENKINS_HOME` es un *bind mount*
> del host, no un volumen con nombre: `down -v` lo deja intacto. Si lo intentas y
> luego te extraña que el asistente de instalación no reaparezca, es por esto.
> Usa `--reset`.

### Portabilidad a otras distribuciones

El laboratorio está probado sobre Debian/Ubuntu/Kali, donde el perfil `docker-default`
de AppArmor no restringe los *bind mounts*. **Si lo replicas en RHEL/Fedora/CentOS con
SELinux en `enforcing`**, los contenedores hermanos recibirán *permission denied* al
leer el workspace: hay que añadir el sufijo `:z` a cada montaje del Jenkinsfile
(`-v "$WORKSPACE":/src:z`).

### Deuda técnica conocida (no tocar la víspera de la clase)

- `sonarqube:lts-community` quedó congelado en la rama 9.9.x, ya fuera de soporte.
  La migración a `sonarqube:2025-lta-community` implica migración de base de datos:
  hazla **entre clases**, con tiempo y con backup, nunca el día antes.
- Las imágenes de herramientas usan `:latest` / `:stable` (salvo Gitleaks, fijado a
  `v8.18.4`). Para reproducibilidad estricta, fija versiones tras validarlas.

---

## 8. Requisitos de máquina

| Recurso | Mínimo | Comentario |
|---------|--------|------------|
| RAM | 12 GB | Con 8-10 GB: apaga `prometheus`, `grafana`, `gitlab-runner` y desmarca `RUN_SAST` |
| CPU | 4 vCPU | Determina cuántos executors puedes dar (4) |
| Disco | +8 GB libres | Imágenes de herramientas, capas de build y caché de Trivy |
| Red | Salida a internet | Solo para la **preparación**. Durante la clase ya está todo descargado |

Consumo aproximado en reposo: GitLab ~3,5 GB · SonarQube ~1,5 GB ·
DefectDojo (5 contenedores) ~1 GB · Jenkins ~0,5 GB · Juice Shop ~0,2 GB.
