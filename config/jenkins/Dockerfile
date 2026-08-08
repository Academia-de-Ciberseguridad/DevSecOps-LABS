# =============================================================================
#  Jenkins para el laboratorio DevSecOps
#
#  ¿Por qué una imagen propia y no `jenkins/jenkins:lts` a secas?
#
#  1) La imagen oficial NO trae el cliente `docker`. Montar el socket
#     (/var/run/docker.sock) no sirve de nada si dentro no hay binario que
#     hable con él. Aquí instalamos SOLO el CLI (docker-ce-cli): el demonio
#     sigue siendo el del host. Es el patrón "Docker-out-of-Docker" (DooD):
#     el pipeline lanza contenedores HERMANOS, no anidados.
#
#  2) Pre-instalamos los plugins. El día de la clase nadie espera a que
#     Jenkins se los descargue de internet.
#
#  3) `curl` y `jq` para hablar con la API de DefectDojo directamente desde
#     el contenedor de Jenkins (está en la red devsecops-net).
# =============================================================================
#  ⚠️ NO usar `lts-jdk17`: esa etiqueta quedó congelada en marzo de 2026 (Jenkins
#     2.541.3) cuando el proyecto retiró el soporte de Java 17, y arrastra CVEs de
#     core sin parchear. La línea LTS viva publica jdk21/jdk25. Dar una clase de
#     seguridad sobre un controlador desactualizado sería contradictorio.
#     Para reproducibilidad estricta, fija la versión: jenkins/jenkins:2.568.2-lts-jdk21
FROM jenkins/jenkins:lts-jdk21

USER root

# --- Cliente de Docker (NO el demonio) + utilidades del pipeline ------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg jq git; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://download.docker.com/linux/debian/gpg \
        -o /etc/apt/keyrings/docker.asc; \
    chmod a+r /etc/apt/keyrings/docker.asc; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin; \
    rm -rf /var/lib/apt/lists/*; \
    docker --version

# --- Plugins pre-instalados -------------------------------------------------
# Sin --latest: jenkins-plugin-cli resuelve contra el update center de ESTA
# versión del core. Forzar "la última de internet" es lo que hace que un build
# que funcionaba ayer falle hoy con "plugin requires a newer Jenkins version".
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# El contenedor se ejecuta como root (definido en docker-compose.yml) para poder
# usar /var/run/docker.sock sin pelearnos con el GID del grupo `docker` del host,
# que cambia de una máquina a otra. Es un laboratorio, no producción.
USER root
