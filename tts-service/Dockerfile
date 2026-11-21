FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIPER_MODEL=/app/voices/ru_RU-denis-medium.onnx

WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends espeak-ng libespeak-ng1 curl \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN mkdir -p /app/voices && python -m piper.download_voices ru_RU-denis-medium --download-dir /app/voices
COPY app.py .
EXPOSE 10000
CMD ["sh", "-c", "uvicorn app:app --host 0.0.0.0 --port ${PORT:-10000}"]
