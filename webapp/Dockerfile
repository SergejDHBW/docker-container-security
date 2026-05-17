FROM python:3.11-slim

# Install network tools for the demo (ping, curl, etc.)
RUN apt-get update && apt-get install -y \
    iputils-ping \
    net-tools \
    curl \
    default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

RUN pip install flask

# VULNERABLE: Running as root (no USER directive)
WORKDIR /app
COPY app.py .

EXPOSE 5000
CMD ["python", "app.py"]
