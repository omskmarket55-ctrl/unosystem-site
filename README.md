# unosystem.ru

Главная страница Uno System: витрина продуктов — Пульс КЦ, CRMUNO, OfferUNO, Трубка.
Статический сайт без сборки и внешних запросов: шрифты и картинки лежат рядом, cookies и счётчиков нет.

## Структура

- `public/` — сайт unosystem.ru (`index.html`, `assets/css`, `assets/js`, `assets/fonts`, `assets/img`, иконки, `og-image.png`).
- `pulse-soon/` — временная страница pulse.unosystem.ru, пока Пульс КЦ не запущен.
- `deploy/unosystem.caddy` — настройки Caddy для unosystem.ru, www.unosystem.ru и pulse.unosystem.ru.
- `deploy/install.sh` — установка на сервер.
- `deploy/update.sh` — обновление файлов сайта из `main`.

Фирменный стиль — брендбук Uno System v1.0: фон «Ночь» `#05070D`, акцент «Синий свет» `#2F7BFF`,
заголовки Exo 2, текст Manrope.

## Сервер

Сайт живёт на сервере рядом с другими сайтами и не мешает им: использует тот же Caddy,
добавляя в его Caddyfile одну строку `import /etc/caddy/unosystem.caddy`.

Первая установка — от root на сервере:

```sh
curl -fsSL https://raw.githubusercontent.com/omskmarket55-ctrl/unosystem-site/main/deploy/install.sh | bash
```

Скрипт:

1. проверяет, что порт 443 держит Caddy как служба systemd (иначе останавливается, ничего не меняя);
2. скачивает репозиторий в `/opt/unosystem-site` и раскладывает файлы в `/var/www/unosystem` и `/var/www/pulse-soon`;
3. кладёт `/etc/caddy/unosystem.caddy`, добавляет строку `import`, проверяет конфиг (`caddy validate`)
   и мягко перезагружает Caddy; если проверка не прошла — возвращает Caddyfile из резервной копии;
4. включает таймер `unosystem-site-update.timer`: раз в 5 минут забирает новую версию из `main`.

Таймер обновляет только файлы сайта. Изменения в `deploy/unosystem.caddy` применяются повторным запуском `install.sh`.

Полезное на сервере:

```sh
systemctl list-timers unosystem-site-update.timer   # когда следующая проверка
journalctl -u unosystem-site-update -n 20           # журнал обновлений
unosystem-site-update --force                       # обновить сейчас
```

## Локально

```sh
python3 -m http.server 8080 --directory public
```

После правки `site.css` или `site.js` увеличьте `?v=` в ссылках на них в `index.html` и `404.html` —
браузеры кэшируют `/assets/` на неделю.
