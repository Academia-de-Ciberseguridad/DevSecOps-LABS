#!/usr/bin/env python3
"""
App de ejemplo VULNERABLE para prácticas DevSecOps.
Contiene vulnerabilidades intencionales que los alumnos deben detectar
con las herramientas del pipeline (SonarQube, Trivy, Gitleaks, ZAP).

⚠️ NO USAR EN PRODUCCIÓN - Solo para laboratorio educativo.
"""

from flask import Flask, request, render_template_string, redirect
import sqlite3
import os
import hashlib
import subprocess

app = Flask(__name__)

# ============================================================
# VULNERABILIDAD 1: Secretos hardcodeados (Gitleaks los detecta)
# ============================================================
DATABASE_PASSWORD = "SuperSecret123!"
API_KEY = "sk-proj-FAKE-abcdef123456789-not-real-key"
AWS_SECRET = "AKIAIOSFODNN7FAKEFAKE"

# ============================================================
# VULNERABILIDAD 2: SQL Injection (SonarQube/ZAP lo detectan)
# ============================================================
def get_user(username):
    conn = sqlite3.connect('users.db')
    cursor = conn.cursor()
    # VULNERABLE: concatenación directa en query SQL
    query = f"SELECT * FROM users WHERE username = '{username}'"
    cursor.execute(query)
    result = cursor.fetchone()
    conn.close()
    return result

# ============================================================
# VULNERABILIDAD 3: XSS Reflejado (ZAP lo detecta)
# ============================================================
@app.route('/')
def index():
    name = request.args.get('name', 'Visitante')
    # VULNERABLE: input del usuario directamente en HTML
    return render_template_string(f'''
        <html>
        <head><title>DevSecOps Lab App</title></head>
        <body>
            <h1>Bienvenido, {name}!</h1>
            <form action="/search">
                <input name="q" placeholder="Buscar...">
                <button>Buscar</button>
            </form>
            <a href="/login">Login</a> | <a href="/admin">Admin</a>
        </body>
        </html>
    ''')

# ============================================================
# VULNERABILIDAD 4: Command Injection (SonarQube lo detecta)
# ============================================================
@app.route('/ping')
def ping():
    host = request.args.get('host', '127.0.0.1')
    # VULNERABLE: input del usuario en comando del sistema
    result = subprocess.run(f"ping -c 1 {host}", shell=True, capture_output=True, text=True)
    return f"<pre>{result.stdout}\n{result.stderr}</pre>"

# ============================================================
# VULNERABILIDAD 5: Hash débil (SonarQube lo detecta)
# ============================================================
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        password = request.form.get('password', '')
        # VULNERABLE: MD5 no es seguro para contraseñas
        hashed = hashlib.md5(password.encode()).hexdigest()
        if hashed == "5f4dcc3b5aa765d61d8327deb882cf99":  # "password"
            return "Login exitoso"
        return "Credenciales incorrectas"

    return render_template_string('''
        <html><body>
        <h2>Login</h2>
        <form method="POST">
            <input name="username" placeholder="Usuario"><br><br>
            <input name="password" type="password" placeholder="Password"><br><br>
            <button>Entrar</button>
        </form>
        </body></html>
    ''')

# ============================================================
# VULNERABILIDAD 6: IDOR / Broken Access Control
# ============================================================
@app.route('/user/<int:user_id>')
def user_profile(user_id):
    # VULNERABLE: no verifica si el usuario tiene permiso
    return f"<h2>Perfil del usuario {user_id}</h2><p>Email: user{user_id}@example.com</p>"

# ============================================================
# VULNERABILIDAD 7: Directory Traversal
# ============================================================
@app.route('/download')
def download():
    filename = request.args.get('file', 'readme.txt')
    # VULNERABLE: path traversal sin sanitización
    filepath = os.path.join('/app/files', filename)
    try:
        with open(filepath, 'r') as f:
            return f"<pre>{f.read()}</pre>"
    except:
        return "Archivo no encontrado", 404

# ============================================================
# VULNERABILIDAD 8: Debug habilitado / Info Disclosure
# ============================================================
@app.route('/admin')
def admin():
    # VULNERABLE: información de debug expuesta
    return render_template_string(f'''
        <html><body>
        <h2>Panel Admin (sin autenticación)</h2>
        <pre>
        Server: {os.uname()}
        Python: {os.sys.version}
        CWD: {os.getcwd()}
        DB Password: {DATABASE_PASSWORD}
        ENV: {dict(os.environ)}
        </pre>
        </body></html>
    ''')


def init_db():
    conn = sqlite3.connect('users.db')
    c = conn.cursor()
    c.execute('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT, password TEXT, email TEXT)')
    c.execute("INSERT OR IGNORE INTO users VALUES (1, 'admin', 'admin123', 'admin@lab.com')")
    c.execute("INSERT OR IGNORE INTO users VALUES (2, 'user1', 'password', 'user1@lab.com')")
    conn.commit()
    conn.close()


if __name__ == '__main__':
    init_db()
    # VULNERABLE: debug=True en producción
    app.run(host='0.0.0.0', port=5000, debug=True)
