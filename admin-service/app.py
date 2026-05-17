from flask import Flask, jsonify

app = Flask(__name__)

# Simulated internal admin data - should never be accessible from outside
ADMIN_DATA = {
    "internal_api_keys": {
        "aws_access_key": "AKIAIOSFODNN7EXAMPLE",
        "aws_secret_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "database_master_password": "SuperSecret123!"
    },
    "admin_users": [
        {"username": "admin", "role": "superadmin", "email": "admin@firma.local"},
        {"username": "backup-svc", "role": "service-account", "email": "backup@firma.local"}
    ]
}

@app.route("/")
def index():
    return "<h1>Internal Admin Service</h1><p>This service is for internal use only.</p>"

@app.route("/api/config")
def config():
    return jsonify(ADMIN_DATA)

@app.route("/health")
def health():
    return jsonify({"status": "ok", "service": "admin-internal"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
