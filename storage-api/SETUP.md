# Облачное хранилище МУЛЬТИК ТВ — Backblaze B2

Сервис хранения заменён с Tigris на Backblaze B2. Сервер использует S3-совместимый API через уже установленный AWS SDK.

## Настройка

Учётную запись, ключи и любые платёжные настройки должен контролировать взрослый владелец. Регистрация: https://www.backblaze.com/sign-up/s3

Официальная инструкция по созданию ключей: https://www.backblaze.com/docs/cloud-storage-create-and-manage-application-keys

1. Включить B2 Cloud Storage и создать bucket для видео.
2. Открыть B2 Cloud Storage → Application Keys → Add a New Application Key.
3. Ограничить ключ созданным bucket и выбрать Read and Write. Для ограниченного bucket включить Allow List All Bucket Names, необходимый для S3 List Buckets.
4. Создать ключ и сохранить keyID и applicationKey в защищённом месте. Секрет показывается только один раз. Не использовать Master Application Key.

## Переменные окружения сервера

- B2_BUCKET — точное имя bucket.
- B2_ENDPOINT — S3 endpoint, показанный в настройках bucket, например https://s3.us-west-004.backblazeb2.com.
- B2_REGION — регион из endpoint, например us-west-004.
- AWS_ACCESS_KEY_ID — keyID.
- AWS_SECRET_ACCESS_KEY — applicationKey.
- ADMIN_API_TOKEN — отдельный секрет администратора для управления собственными ключами. Владелец должен создать его случайным генератором паролей и задать только в переменных окружения сервера.\n- UPLOAD_API_TOKEN — необязательный старый пароль загрузчика; новые ключи создаются в панели «Ключи доступа».\n- DATA_DIR — каталог данных, например `/var/data`; он должен быть подключён к постоянному диску Render. Без постоянного диска список ключей может пропасть после перезапуска или нового развёртывания.
- ALLOWED_ORIGINS — https://igoryukha809-cell.github.io

Все секреты вводятся только в защищённые переменные сервера Render. Не помещать их в GitHub, HTML/JavaScript, логи или сообщения.

## Проверка

Открыть /health. После настройки ожидается ok: true, storage: backblaze-b2 и configured: true.

- Каталог: GET /api/videos
- Плейлист: GET /api/playlist
- Загрузка: POST /api/upload, multipart поле video, заголовок Authorization: Bearer <UPLOAD_API_TOKEN>

## Стоимость и ограничения

Первые 10 GB хранения указаны как бесплатные. Сверх лимита хранение платное; исходящий трафик бесплатен до 3× среднемесячного объёма хранения, затем может взиматься плата. Проверять актуальные условия до загрузки: https://www.backblaze.com/cloud-storage/pricing

Это объектное хранилище, а не видеотранслятор. Оно само не создаёт HLS-эфир и не обеспечивает круглосуточное вещание. Для эфира отдельно нужен playout/streaming-сервер и разрешения на публичный показ каждого материала.