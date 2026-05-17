FROM python:3.11-slim

RUN pip install flask

WORKDIR /app
COPY app.py .

EXPOSE 8080
CMD ["python", "app.py"]
