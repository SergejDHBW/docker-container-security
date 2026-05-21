from flask import Flask, request, render_template_string
import os
import subprocess

app = Flask(__name__)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Kundenportal - ServerCheck</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #f0f2f5; margin: 0; padding: 0; }
        .header { background: #1a237e; color: white; padding: 20px 40px; }
        .header h1 { margin: 0; font-size: 24px; }
        .container { max-width: 800px; margin: 40px auto; padding: 0 20px; }
        .card { background: white; border-radius: 8px; padding: 30px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .card h2 { color: #1a237e; margin-top: 0; }
        input[type="text"] { width: 100%; padding: 12px; border: 1px solid #ddd; border-radius: 4px; font-size: 16px; box-sizing: border-box; }
        button { background: #1a237e; color: white; border: none; padding: 12px 30px; border-radius: 4px; font-size: 16px; cursor: pointer; margin-top: 10px; }
        button:hover { background: #283593; }
        pre { background: #263238; color: #aed581; padding: 20px; border-radius: 4px; overflow-x: auto; white-space: pre-wrap; max-height: 400px; overflow-y: auto; }
        .info { color: #666; font-size: 14px; margin-top: 5px; }
        a.btn { display: inline-block; background: #1a237e; color: white; text-decoration: none; padding: 10px 20px; border-radius: 4px; font-size: 15px; margin-top: 10px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>&#127970; Kundenportal - Netzwerk-Diagnose</h1>
    </div>
    <div class="container">
        <div class="card">
            <h2>Server-Erreichbarkeit prüfen</h2>
            <p>Geben Sie eine IP-Adresse oder einen Hostnamen ein, um die Erreichbarkeit zu testen.</p>
            <form method="POST" action="/ping">
                <input type="text" name="host" placeholder="z.B. 8.8.8.8 oder google.com" value="{{ host_value }}">
                <p class="info">Dieses Tool führt einen Ping-Test zum angegebenen Server durch.</p>
                <button type="submit">Ping ausführen</button>
            </form>
        </div>
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

@app.route("/")
def index():
    return render_template_string(HTML_TEMPLATE, output=None, host_value="")

@app.route("/ping", methods=["POST"])
def ping():
    host = request.form.get("host", "")
    # VULNERABLE: User input is directly passed to a shell command (shell=True, no sanitization)
    result = subprocess.run(
        f"ping -c 2 {host}",
        shell=True,
        capture_output=True,
        text=True,
        timeout=10
    )
    output = result.stdout + result.stderr
    return render_template_string(HTML_TEMPLATE, output=output, host_value=host)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
