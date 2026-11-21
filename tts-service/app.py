import io
import os
import time
import threading
import wave
from collections import defaultdict, deque

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from pydantic import BaseModel, Field
from piper import PiperVoice, SynthesisConfig

VOICE_PATH = os.getenv("PIPER_MODEL", "/app/voices/ru_RU-denis-medium.onnx")
ALLOWED_ORIGIN = os.getenv("ALLOWED_ORIGIN", "https://igoryukha809-cell.github.io/multik-tv")
MAX_CHARS = 1200
RATE_LIMIT = 8
WINDOW_SECONDS = 60

app = FastAPI(title="Channel TTS", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[ALLOWED_ORIGIN],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)

voice = None
voice_lock = threading.Lock()
requests_by_ip = defaultdict(deque)

class SpeechRequest(BaseModel):
    text: str = Field(min_length=1, max_length=MAX_CHARS)
    rate: float = Field(default=1.0, ge=0.8, le=1.2)

@app.on_event("startup")
def load_voice():
    global voice
    if not os.path.exists(VOICE_PATH):
        raise RuntimeError(f"Piper model not found: {VOICE_PATH}")
    voice = PiperVoice.load(VOICE_PATH)

@app.get("/health")
def health():
    return {"status": "ok", "engine": "Piper", "voice": "ru_RU-denis-medium", "loaded": voice is not None}

@app.post("/api/tts")
def synthesize(payload: SpeechRequest, request: Request):
    if voice is None:
        raise HTTPException(status_code=503, detail="Voice model is loading")
    text = payload.text.strip()
    if not text:
        raise HTTPException(status_code=422, detail="Text is empty")
    ip = request.client.host if request.client else "unknown"
    now = time.monotonic()
    history = requests_by_ip[ip]
    while history and now - history[0] > WINDOW_SECONDS:
        history.popleft()
    if len(history) >= RATE_LIMIT:
        raise HTTPException(status_code=429, detail="Rate limit reached; try again in a minute")
    history.append(now)

    # Piper length_scale: values above 1 are slower; invert the UI rate.
    config = SynthesisConfig(length_scale=1.0 / payload.rate)
    output = io.BytesIO()
    with voice_lock:
        with wave.open(output, "wb") as wav_file:
            voice.synthesize_wav(text, wav_file, syn_config=config)
    return Response(
        content=output.getvalue(),
        media_type="audio/wav",
        headers={"Content-Disposition": 'inline; filename="channel-voice.wav"', "Cache-Control": "no-store"},
    )
