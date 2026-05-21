from flask import Flask, request, render_template_string
import re
import subprocess

app = Flask(__name__)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Kundenportal - ServerCheck (Gehärtet)</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #f0f2f5; margin: 0; padding: 0; }
        .header { background: #2e7d32; color: white; padding: 20px 40px; }
        .header h1 { margin: 0; font-size: 24px; }
        .badge { background: #43a047; padding: 4px 12px; border-radius: 12px; font-size: 12px; margin-left: 10px; }
        .container { max-width: 800px; margin: 40px auto; padding: 0 20px; }
        .card { background: white; border-radius: 8px; padding: 30px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .card h2 { color: #2e7d32; margin-top: 0; }
        input[type="text"] { width: 100%; padding: 12px; border: 1px solid #ddd; border-radius: 4px; font-size: 16px; box-sizing: border-box; }
        button { background: #2e7d32; color: white; border: none; padding: 12px 30px; border-radius: 4px; font-size: 16px; cursor: pointer; margin-top: 10px; }
        pre { background: #263238; color: #aed581; padding: 20px; border-radius: 4px; overflow-x: auto; white-space: pre-wrap; }
        .error { color: #d32f2f; font-weight: bold; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🏢 Kundenportal - Netzwerk-Diagnose <span class="badge">GEHÄRTET</span></h1>
    </div>
    <div class="container">
        <div class="card">
            <h2>Server-Erreichbarkeit prüfen</h2>
            <p>Geben Sie eine IP-Adresse oder einen Hostnamen ein.</p>
            <form method="POST" action="/ping">
                <input type="text" name="host" placeholder="z.B. 8.8.8.8 oder google.com" value="{{ host_value }}">
                <button type="submit">Ping ausführen</button>
            </form>
        </div>
        {% if error %}
        <div class="card">
            <p class="error">{{ error }}</p>
        </div>
        {% endif %}
        {% if output %}
        <div class="card">
            <h2>Ergebnis</h2>
            <pre>{{ output }}</pre>
        </div>
        {% endif %}
    </div>
</body>
</html>
"""

def is_valid_host(host):
    """HÄRTUNG: Strikte Input-Validierung"""
    # Erlaubt nur gültige IP-Adressen und Hostnamen
    ip_pattern = r'^(\d{1,3}\.){3}\d{1,3}$'
    hostname_pattern = r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$'
    return bool(re.match(ip_pattern, host) or re.match(hostname_pattern, host))

@app.route("/")
def index():
    return render_template_string(HTML_TEMPLATE, output=None, error=None, host_value="")

@app.route("/ping", methods=["POST"])
def ping():
    host = request.form.get("host", "").strip()

    # HÄRTUNG: Input-Validierung
    if not is_valid_host(host):
        return render_template_string(HTML_TEMPLATE,
            output=None,
            error="Ungültige Eingabe! Nur IP-Adressen und Hostnamen erlaubt.",
            host_value=host)

    # HÄRTUNG: Kein shell=True, Argumente als Liste
    try:
        result = subprocess.run(
            ["ping", "-c", "2", host],
            capture_output=True,
            text=True,
            timeout=10
        )
        output = result.stdout + result.stderr
    except (subprocess.TimeoutExpired, OSError) as e:
        output = f"Fehler: {e}"
    return render_template_string(HTML_TEMPLATE, output=output, error=None, host_value=host)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
