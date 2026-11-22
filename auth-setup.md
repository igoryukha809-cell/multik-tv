# Вход в МУЛЬТИК ТВ через Logto

Основной вход сайта выполняется через Logto SPA. Приложение Logto: `gvfs0kxuu7rtdeqi3z0zm`, endpoint `https://v74j2v.logto.app`.

## Настройки приложения Logto

- Тип приложения: Single-page application → Pure JavaScript.
- Redirect URI: `https://igoryukha809-cell.github.io/multik-tv/access-keys.html`
- Post sign-out redirect URI: `https://igoryukha809-cell.github.io/multik-tv/`
- В Logto Console откройте API resources и создайте ресурс с URI:
  `https://multik-tv-access-api-production.up.railway.app`

## Настройки Railway

Для сервиса `multik-tv-access-api` задайте:
- `LOGTO_ENDPOINT=https://v74j2v.logto.app`
- `LOGTO_API_RESOURCE=https://multik-tv-access-api-production.up.railway.app`
- `ADMIN_EMAIL` — подтверждённая почта администратора (существующая переменная).

Не присылайте секреты или коды подтверждения в чат. Endpoint, app ID и API resource — публичная конфигурация SPA.

## Проверка

Браузер получает access token для API resource. Сервер проверяет подпись JWT через Logto JWKS, issuer, audience и срок действия, затем запрашивает подтверждённую почту через Logto UserInfo endpoint и сравнивает её с ADMIN_EMAIL. Простая регистрация не выдаёт права администратора.


## Данные пользовательских разделов

Профиль, баллы, достижения и идеи хранятся локально в браузере пользователя. Они не синхронизируются между устройствами и не являются частью административной авторизации. Вход администратора выполняется только через Logto.
