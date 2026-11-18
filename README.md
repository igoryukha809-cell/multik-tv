# МУЛЬТИК ТВ

Детский онлайн-проект телеканала «МУЛЬТИК ТВ».

[![Проверка видеосервера](https://github.com/igoryukha809-cell/multik-tv/actions/workflows/stream-server-check.yml/badge.svg)](https://github.com/igoryukha809-cell/multik-tv/actions/workflows/stream-server-check.yml)
[![Публикация сайта](https://github.com/igoryukha809-cell/multik-tv/actions/workflows/deploy-pages.yml/badge.svg)](https://github.com/igoryukha809-cell/multik-tv/actions/workflows/deploy-pages.yml)

## Открыть сайт

- [Главная страница](https://igoryukha809-cell.github.io/multik-tv/)
- [Публичный плеер](https://igoryukha809-cell.github.io/multik-tv/live.html)
- [Каталог](https://igoryukha809-cell.github.io/multik-tv/online-catalog.html)
- [Телепрограмма](https://igoryukha809-cell.github.io/multik-tv/guide.html)
- [Статус канала](https://igoryukha809-cell.github.io/multik-tv/channel.html)

## Облачный тестовый видеосервер

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/igoryukha809-cell/multik-tv)

Кнопка открывает подготовленную конфигурацию Render. Перед запуском взрослый должен проверить, что создаётся только один сервис Free без платных ресурсов, и подтвердить действие в аккаунте. Это тестовый видеосервер, не полноценный эфир телеканала.

**Ограничения:** бесплатный веб-сервис Render засыпает после 15 минут без входящих запросов, может перезапускаться и имеет лимит 750 часов на рабочее пространство в месяц. Поэтому 24/7 не гарантируется. Подробности: [официальные ограничения Render](https://render.com/docs/free).

## Текущий статус

Сайт опубликован на GitHub Pages. GitHub Actions проверяет конфигурацию Docker и собирает образ видеоплейлиста. Эти проверки не запускают видеосервер и не означают, что идёт эфир.

Пока сервер не подключён, публичный эфир должен отображаться как **OFFLINE**. Не добавляй в плейлист мультфильмы без явного разрешения на публичный показ.

## Сервер

Инструкция и конфигурация локального тестового сервера находятся в папке [stream-server](stream-server/README.md). Запуск сервера требует отдельного компьютера, работающего Docker и стабильного интернета. Не публикуй домашний адрес или IP и не меняй настройки роутера без помощи родителя или опекуна.

## Права на видео

Используй только собственные видео или материалы, для которых получено явное разрешение на публичный показ. Бесплатный просмотр ролика не означает разрешение ретранслировать его на телеканале.
