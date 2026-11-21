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
# Fail the image build unless the downloaded model can synthesize a valid WAV.
RUN python -c "import io,wave; from piper import PiperVoice; voice=PiperVoice.load('/app/voices/ru_RU-denis-medium.onnx'); chunks=list(voice.synthesize('Проверка голосового эфира.')); assert chunks, 'Piper returned no audio'; out=io.BytesIO(); wav=wave.open(out,'wb'); wav.setnchannels(chunks[0].sample_channels); wav.setsampwidth(2); wav.setframerate(chunks[0].sample_rate); wav.writeframes(b''.join(c.audio_int16_bytes for c in chunks)); wav.close(); data=out.getvalue(); assert data[:4] == b'RIFF' and len(data) > 44, 'Piper returned an invalid WAV'; print('PIPER_SMOKE_TEST_OK bytes=' + str(len(data)))"
COPY app.py .
EXPOSE 10000
CMD ["sh", "-c", "uvicorn app:app --host 0.0.0.0 --port ${PORT:-10000}"]
