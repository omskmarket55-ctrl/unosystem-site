# unosystem.ru

Главная страница Uno System: витрина продуктов — Пульс КЦ, CRMUNO, OfferUNO, Трубка.
Статический сайт без сборки и внешних запросов: шрифты и картинки лежат рядом, cookies и счётчиков нет.

## Структура

- `public/` — сайт unosystem.ru (`index.html`, `assets/css`, `assets/js`, `assets/fonts`, `assets/img`, иконки, `og-image.png`).
- `pulse-soon/` — временная страница pulse.unosystem.ru, пока Пульс КЦ не запущен.
- `deploy/web.caddy`, `deploy/sites.caddy`, `deploy/front.caddy` — настройки Caddy (подробнее — ниже).
- `deploy/install.sh` — установка на сервер.
- `deploy/update.sh` — обновление файлов сайта из `main`.

Фирменный стиль — брендбук Uno System v1.0: фон «Ночь» `#05070D`, акцент «Синий свет» `#2F7BFF`,
заголовки Exo 2, текст Manrope.

## Сервер

Сайт живёт на сервере рядом с другими проектами и не мешает им.

- `deploy/web.caddy` — контейнер `unosystem-web` (образ `caddy:2-alpine`): отдаёт файлы из `/srv/unosystem`
  по HTTP внутри сети Docker `unosystem`, наружу портов не открывает.
- `deploy/sites.caddy` — наши домены на входном Caddy: HTTPS и `reverse_proxy unosystem-web:80`.
- Входной Caddy — тот, что уже держит порт 443. Сейчас это контейнер CRMUNO: `install.sh` дописывает
  `sites.caddy` в его Caddyfile между метками `# >>> unosystem.ru` и `# <<< unosystem.ru`, подключает контейнер
  к сети `unosystem`, проверяет конфиг (`caddy validate`) и мягко перезагружает его. Чужой контейнер
  не перезапускается; если проверка не прошла, Caddyfile возвращается из копии.
- Если порт 443 свободен (например, CRMUNO убрали с сервера), `install.sh` запускает свой входной Caddy —
  контейнер `unosystem-proxy` с `deploy/front.caddy`.

Установка и повторный запуск (после смены `deploy/*.caddy` или входа) — от root на сервере:

```sh
curl -fsSL https://raw.githubusercontent.com/omskmarket55-ctrl/unosystem-site/main/deploy/install.sh | sudo bash
```

Таймер `unosystem-site-update.timer` раз в 5 минут забирает новую версию из `main` и подменяет файлы
в `/srv/unosystem` — только файлы сайта, конфиги Caddy он не трогает. Ещё он подключает входной Caddy обратно
к сети `unosystem`, если его контейнер пересоздали.

Полезное на сервере:

```sh
systemctl list-timers unosystem-site-update.timer   # когда следующая проверка
journalctl -u unosystem-site-update -n 20           # журнал обновлений
unosystem-site-update --force                       # обновить сейчас
docker logs unosystem-web                           # журнал контейнера с сайтом
```

Убрать сайт с общего входа: удалить блок между метками в Caddyfile входного Caddy и выполнить в его контейнере
`caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile`.

## Локально

```sh
python3 -m http.server 8080 --directory public
```

После правки `site.css` или `site.js` увеличьте `?v=` в ссылках на них в `index.html` и `404.html` —
браузеры кэшируют `/assets/` на неделю.
