# Подключение административного доступа МУЛЬТИК ТВ

## Что уже подготовлено
- Админ-панель `admin.html` со ссылками на инструменты сайта.
- Защитная проверка для страниц управления через `admin-guard.js`.
- Общедоступными остаются только просмотр `tv.html` / `watch.html` и телепрограмма `guide.html`.
- Вход использует существующую страницу `login.html` (Supabase magic link).

## Важное ограничение
GitHub Pages — статический хостинг. Проверка в браузере закрывает страницы от обычного посетителя, но не является полноценной серверной защитой секретов или серверных операций. Не храните в репозитории секреты, пароли или service_role key. Для защищённых данных и действий используйте серверные функции и RLS.

## Настройка владельцем проекта (с участием взрослого администратора)
1. Создать проект Supabase и включить Authentication → Email.
2. В Supabase URL Configuration добавить адреса:
   - `https://igoryukha809-cell.github.io/multik-tv/login.html`
   - `https://igoryukha809-cell.github.io/multik-tv/admin.html`
3. В `admin-config.js` заменить `SUPABASE_URL` и `SUPABASE_ANON_KEY` на Project URL и публичный anon/publishable key. Не вставлять service_role key.
4. В SQL Editor выполнить:

```sql
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;
create policy "admins can read their own role"
on public.admin_users for select to authenticated
using (auth.uid() = user_id);
```

5. Взрослый владелец входит через `login.html`. После первого входа добавить его UUID в `admin_users` через SQL Editor, используя email, с которым он вошёл:

```sql
insert into public.admin_users(user_id)
select id from auth.users where email = 'ADMIN_EMAIL_HERE'
on conflict do nothing;
```

6. После настройки открыть `admin.html` и проверить вход.

## Не делайте
- Не добавляйте всех зарегистрированных пользователей в admin_users.
- Не вставляйте service_role key в HTML/JavaScript или GitHub.
- Не используйте этот клиентский замок как единственную защиту финансовых, персональных или иных секретных операций.
