FROM python:3.11-slim

# Install network tools
RUN apt-get update && apt-get install -y \
    iputils-ping \
    net-tools \
    curl \
    default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

RUN pip install flask

# VULNERABLE (Image-Layer-Secret): This credential is baked into the image history.
# Even if deleted in a later layer, it remains visible via: docker history --no-trunc
RUN echo "BACKUP_DB_URL=mysql://backup_user:Backup@2024!@db-prod.firma.local/kundenportal" \
    >> /etc/environment

# VULNERABLE: Running as root (no USER directive)
WORKDIR /app
COPY app.py .

EXPOSE 5000
CMD ["python", "app.py"]
