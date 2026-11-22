# Единая авторизация МУЛЬТИК ТВ — Logto

В проекте используется **только Logto** для входа и проверки прав администратора. Не подключайте Supabase или другие провайдеры авторизации.

## Единая конфигурация сайта

Публичные настройки находятся в `logto-config.js`:

- Logto endpoint: `https://v74j2v.logto.app`
- SPA application ID: `gvfs0kxuu7rtdeqi3z0zm`
- API resource URI: `https://multik-tv-access-api-production.up.railway.app`
- Redirect URI: `https://igoryukha809-cell.github.io/multik-tv/access-keys.html`
- Post-logout redirect URI: `https://igoryukha809-cell.github.io/multik-tv/`

Эти значения — публичная конфигурация браузерного приложения, не секреты.

## Настройки приложения Logto

В Logto Console проверьте приложение типа **Single-page application / Pure JavaScript**:

- Добавьте Redirect URI из списка выше.
- Добавьте Post sign-out redirect URI из списка выше.
- В API resources должен существовать ресурс с URI, в точности совпадающим с API resource URI из `logto-config.js`.
- Для профиля пользователя запрашивается scope `email`.

Не публикуйте client secrets, коды входа, refresh tokens или access tokens.

## Серверная проверка

Сервис Railway `multik-tv-access-api` использует каталог `storage-api` репозитория и обслуживает API по адресу:

`https://multik-tv-access-api-production.up.railway.app`

Защищённые переменные сервиса:

- `LOGTO_ENDPOINT=https://v74j2v.logto.app`
- `LOGTO_API_RESOURCE=https://multik-tv-access-api-production.up.railway.app`
- `ADMIN_EMAIL` — подтверждённая почта администратора.

Сервер проверяет подпись JWT через Logto JWKS, issuer, audience и срок действия. Затем сервер получает профиль через Logto UserInfo и проверяет, что email подтверждён и совпадает с `ADMIN_EMAIL`. Сам факт регистрации или входа не даёт административных прав.

## Страницы проекта

- `login.html` — начинает защищённый вход через Logto.
- `access-keys.html` — обрабатывает callback Logto, проверяет сессию и управляет ключами через защищённый API.
- `admin.html` — открывает инструменты администрирования только после проверки прав сервером.
- `logto-config.js` — единый источник публичных настроек Logto.

Новые административные страницы должны использовать тот же Logto SPA client и серверную проверку прав. Нельзя считать пользователя администратором только на основании данных, сохранённых в браузере.

## Ключи доступа

Ключи для отдельных технических операций — это не способ входа в аккаунт и не замена Logto:

- `upload` — загрузка видео.
- `api` — API-операции, включая удаление видео.

Ключ создаётся только после проверки администратора через Logto. Полный ключ показывается один раз; на сервере хранится его SHA-256-хеш. При утрате ключ следует отозвать и создать новый.

## Данные пользовательских разделов

Профиль, баллы, достижения и идеи в тех разделах, где они пока сохраняются локально, остаются в браузере. Это не отдельная система авторизации и не синхронизация аккаунта между устройствами. Если потребуется облачный профиль, его следует реализовать отдельным API с проверкой токенов Logto на сервере.

## Проверка

Откройте `https://multik-tv-access-api-production.up.railway.app/health`. Проверка доступности API не заменяет проверку прав пользователя. При ошибке входа проверьте Redirect URI, API resource URI и защищённые переменные Railway.

Все секреты задаются только в защищённых настройках хостинга. Не помещайте их в GitHub, HTML/JavaScript, логи или сообщения.
