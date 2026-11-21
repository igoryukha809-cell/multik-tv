FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIPER_MODEL=/app/voices/ru_RU-denis-medium.onnx

WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends espeak-ng libespeak-ng1 curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN mkdir -p /app/voices && \
    curl -fL --retry 3 -o /app/voices/ru_RU-denis-medium.onnx https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/denis/medium/ru_RU-denis-medium.onnx && \
    curl -fL --retry 3 -o /app/voices/ru_RU-denis-medium.onnx.json https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/denis/medium/ru_RU-denis-medium.onnx.json
COPY app.py .
EXPOSE 10000
CMD ["sh", "-c", "uvicorn app:app --host 0.0.0.0 --port ${PORT:-10000}"]
