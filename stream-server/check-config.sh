#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[1/4] Проверка синтаксиса автоматического плейлиста"
bash -n stream-server/playlist/loop.sh

echo "[2/4] Проверка JSON-файлов эфира"
python3 - <<'PY'
import json
from pathlib import Path

for name in ("broadcast.json", "broadcast/playlist.json", "broadcast/status.json"):
    with Path(name).open(encoding="utf-8") as f:
        json.load(f)
    print(f"OK: {name}")

with Path("broadcast/playlist.json").open(encoding="utf-8") as f:
    playlist = json.load(f)
with Path("broadcast.json").open(encoding="utf-8") as f:
    broadcast = json.load(f)
with Path("broadcast/status.json").open(encoding="utf-8") as f:
    status = json.load(f)

if not isinstance(playlist.get("items"), list):
    raise SystemExit("Ошибка: broadcast/playlist.json items должен быть списком")
if not playlist["items"]:
    is_explicit_test_signal = (
        broadcast.get("status") == "test_signal"
        and broadcast.get("testSignal") is True
        and isinstance(broadcast.get("streamUrl"), str)
        and broadcast["streamUrl"].startswith("https://")
    )
    if status.get("streaming") is not False:
        raise SystemExit("Ошибка: пустой плейлист не должен отмечаться как эфир мультфильмов")
    if broadcast.get("status") != "offline" and not is_explicit_test_signal:
        raise SystemExit("Ошибка: пустой плейлист допускает только offline или явно обозначенный test_signal")
print("OK: пустой плейлист не выдаётся за эфир мультфильмов; тестовый сигнал помечен отдельно")
PY

echo "[3/4] Проверка обязательных настроек SRS"
grep -Eq 'listen[[:space:]]+1935;' stream-server/srs.conf
grep -Eq 'listen[[:space:]]+8080;' stream-server/srs.conf
grep -Eq 'enabled[[:space:]]+on;' stream-server/srs.conf

echo "[4/4] Проверка Docker Compose (если Docker установлен)"
if command -v docker >/dev/null 2>&1; then
  docker compose -f stream-server/docker-compose.yml config --quiet
else
  echo "Пропущено: Docker не установлен; YAML проверится при локальном запуске."
fi

echo "Проверки завершены успешно. Это проверка конфигурации, а не тест реального видеопотока."
