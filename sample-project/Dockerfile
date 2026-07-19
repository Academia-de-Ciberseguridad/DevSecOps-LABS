# NOTA: python:3.9-slim a propósito. requirements.txt fija versiones ANTIGUAS
# y vulnerables (para que Trivy/SonarQube las detecten). Esas versiones tienen
# wheels precompilados para 3.9, así que el build NO falla; en 3.11 pyyaml==5.4
# y otras rompen la compilación (Cython) y tumbaban el pipeline.
FROM python:3.9-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

EXPOSE 5000
CMD ["python", "app.py"]
