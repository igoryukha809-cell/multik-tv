import json
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

playlist_path = Path("broadcast/playlist.json")
status_path = Path("broadcast/status.json")
errors = []
items = []

try:
    data = json.loads(playlist_path.read_text(encoding="utf-8"))
    raw_items = data.get("items", [])
    if not isinstance(raw_items, list):
        errors.append("Поле items должно быть списком.")
        raw_items = []
    for index, item in enumerate(raw_items, 1):
        if not isinstance(item, dict):
            errors.append(f"Запись {index}: ожидается объект.")
            continue
        url = item.get("url", "")
        parsed = urlparse(url) if isinstance(url, str) else None
        if not parsed or parsed.scheme != "https" or not parsed.netloc:
            errors.append(f"Запись {index}: нужен публичный HTTPS URL.")
            continue
        if not item.get("title"):
            errors.append(f"Запись {index}: отсутствует title.")
            continue
        items.append(item)
except FileNotFoundError:
    errors.append("Не найден broadcast/playlist.json.")
except Exception as exc:
    errors.append(f"Не удалось прочитать плейлист: {type(exc).__name__}.")

if errors:
    state = "playlist_has_errors"
    message = "Автопроверка нашла ошибки. См. список errors."
elif not items:
    state = "not_configured"
    message = "Плейлист пуст. Автопроверка работает, но видеотрансляции нет."
else:
    state = "playlist_ready_server_required"
    message = "Плейлист прошёл базовую проверку. Для общего эфира нужен работающий видеосервер."

status = {
    "channel": "МУЛЬТИК ТВ",
    "state": state,
    "checkedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "activeItem": None,
    "itemsChecked": len(items),
    "errors": errors,
    "message": message,
    "streaming": False
}
status_path.parent.mkdir(parents=True, exist_ok=True)
status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(status, ensure_ascii=False, indent=2))
