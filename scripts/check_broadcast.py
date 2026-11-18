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

        title = item.get("title")
        url = item.get("url")
        parsed = urlparse(url) if isinstance(url, str) else None

        if not isinstance(title, str) or not title.strip():
            errors.append(f"Запись {index}: отсутствует title.")
            continue
        if not parsed or parsed.scheme != "https" or not parsed.hostname:
            errors.append(f"Запись {index}: нужен корректный публичный HTTPS URL.")
            continue
        if item.get("rightsConfirmed") is not True:
            errors.append(f"Запись {index}: требуется rightsConfirmed: true после проверки прав.")
            continue
        if not isinstance(item.get("license"), str) or not item["license"].strip():
            errors.append(f"Запись {index}: укажи лицензию или основание разрешения.")
            continue
        if not isinstance(item.get("attribution"), str) or not item["attribution"].strip():
            errors.append(f"Запись {index}: укажи автора/правообладателя для титров.")
            continue
        if not isinstance(item.get("rightsEvidence"), str) or not item["rightsEvidence"].strip():
            errors.append(f"Запись {index}: добавь ссылку или описание подтверждения прав.")
            continue

        items.append(item)

except FileNotFoundError:
    errors.append("Не найден broadcast/playlist.json.")
except json.JSONDecodeError:
    errors.append("broadcast/playlist.json содержит некорректный JSON.")
except Exception as exc:
    errors.append(f"Не удалось прочитать плейлист: {type(exc).__name__}.")

if errors:
    state = "playlist_has_errors"
    message = "Автопроверка нашла ошибки. Исправь записи и проверь права на публичный показ."
elif not items:
    state = "not_configured"
    message = "Плейлист пуст. Автопроверка работает, но видеотрансляции нет."
else:
    state = "playlist_ready_server_required"
    message = "Записи прошли проверку заполнения и декларации прав. Работающий видеосервер всё ещё необходим."

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
