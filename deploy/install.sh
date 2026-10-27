#!/usr/bin/env bash
# Ставит сайт unosystem.ru на сервер с Docker, не мешая другим проектам на нём.
#
# Файлы сайта отдаёт свой контейнер unosystem-web: Caddy без внешних портов в сети Docker «unosystem».
# HTTPS — на входе, который уже есть на сервере:
#   • порт 443 держит Caddy другого проекта в Docker (сейчас — CRMUNO): в его Caddyfile дописывается блок
#     с нашими доменами между метками, его контейнер подключается к сети unosystem, конфиг проверяется
#     и мягко перезагружается. Чужой контейнер не перезапускается; при ошибке Caddyfile возвращается из копии;
#   • порт 443 свободен: запускается свой входной Caddy — контейнер unosystem-proxy.
# Повторный запуск безопасен. Запуск от root:
#   curl -fsSL https://raw.githubusercontent.com/omskmarket55-ctrl/unosystem-site/main/deploy/install.sh | sudo bash
set -euo pipefail

REPO_URL=https://github.com/omskmarket55-ctrl/unosystem-site.git
SRC=/opt/unosystem-site
WWW=/srv/unosystem
NET=unosystem
IMAGE=caddy:2-alpine
UPDATER=/usr/local/sbin/unosystem-site-update
MARK_BEGIN='# >>> unosystem.ru — этот блок ведёт /opt/unosystem-site/deploy/install.sh, вручную не править'
MARK_END='# <<< unosystem.ru'
HOSTS_RE='(^|[[:space:],/])(www\.|pulse\.)?unosystem\.ru([[:space:],:{]|$)'

log() { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# Caddyfile без нашего блока и без пустых строк в конце
strip_block() {
  awk '/^# >>> unosystem\.ru/ { skip = 1 }
       !skip { lines[++n] = $0 }
       /^# <<< unosystem\.ru/ { skip = 0 }
       END { while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print lines[i] }' "$1"
}

# Вход — Caddy другого проекта в Docker: дописываем наш блок в его Caddyfile
shared_front() {
  local c=$1 conf_in host_conf stamp backup tmp
  docker exec "$c" caddy version > /dev/null 2>&1 || die "Порт 443 держит контейнер $c, но это не Caddy. Ничего не меняю"
  conf_in=$(docker inspect -f '{{json .Config.Cmd}}' "$c" | grep -oE '"--config","[^"]+"' | cut -d'"' -f4 || true)
  conf_in=${conf_in:-/etc/caddy/Caddyfile}
  host_conf=$(docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{.Destination}}|{{.Source}}{{println}}{{end}}{{end}}' "$c" \
    | awk -F'|' -v d="$conf_in" '$1 == d { print $2 }')
  [ -n "$host_conf" ] && [ -f "$host_conf" ] || die "Caddyfile контейнера $c не вынесен на сервер — правки не переживут перезапуск. Ничего не меняю"
  ok "Вход: Caddy в контейнере $c, его конфиг на сервере — $host_conf"
  if git -C "$(dirname "$host_conf")" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    printf '  Внимание: %s лежит в git-репозитории. Если при деплое того проекта git не даст обновиться из-за\n' "$host_conf"
    printf '  изменённого Caddyfile — уберите наш блок (git checkout -- Caddyfile), обновитесь и запустите install.sh снова.\n'
  fi

  if strip_block "$host_conf" | grep -vE '^[[:space:]]*#' | grep -E "$HOSTS_RE" > /dev/null; then
    die "В $host_conf уже есть настройки для unosystem.ru вне нашего блока — уберите их и запустите снова"
  fi

  if ! docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$c" | grep -qw "$NET"; then
    docker network connect "$NET" "$c"
    ok "$c подключён к сети $NET (без перезапуска)"
  fi

  stamp=$(date +%Y%m%d-%H%M%S)
  backup="$host_conf.bak-unosystem-$stamp"
  cp -a "$host_conf" "$backup"
  tmp=$(mktemp)
  { strip_block "$host_conf"; printf '\n%s\n' "$MARK_BEGIN"; cat "$SRC/deploy/sites.caddy"; printf '%s\n' "$MARK_END"; } > "$tmp"
  # Пишем поверх, не меняя inode: файл примонтирован в контейнер, новый файл контейнер бы не увидел
  cat "$tmp" > "$host_conf"
  rm -f "$tmp"

  log "Проверяю итоговый конфиг Caddy в $c"
  if ! docker exec "$c" caddy validate --config "$conf_in" --adapter caddyfile > /tmp/unosystem-validate.log 2>&1; then
    cat "$backup" > "$host_conf"
    tail -n 20 /tmp/unosystem-validate.log >&2
    die "Конфиг не прошёл проверку. Caddyfile вернул как было, Caddy не перезагружал"
  fi
  if ! docker exec "$c" caddy reload --config "$conf_in" --adapter caddyfile > /tmp/unosystem-reload.log 2>&1; then
    cat "$backup" > "$host_conf"
    tail -n 20 /tmp/unosystem-reload.log >&2
    die "Caddy не принял конфиг — продолжает работать со старым. Caddyfile вернул как было"
  fi
  ok "Caddy в $c перезагружен мягко, сайты CRMUNO работают как раньше (копия конфига: $backup)"
}

# Порт 443 свободен: свой входной Caddy
own_front() {
  if docker ps --format '{{.Names}}' | grep -qx unosystem-proxy; then
    docker exec unosystem-proxy caddy reload --config /etc/unosystem/front.caddy --adapter caddyfile > /dev/null
    ok "Вход: свой Caddy unosystem-proxy, конфиг перечитан"
    return
  fi
  docker rm -f unosystem-proxy > /dev/null 2>&1 || true
  docker run -d --name unosystem-proxy --restart unless-stopped --network "$NET" \
    -p 80:80 -p 443:443 -p 443:443/udp \
    -v unosystem_caddy_data:/data -v unosystem_caddy_config:/config -v "$SRC/deploy":/etc/unosystem:ro \
    "$IMAGE" caddy run --config /etc/unosystem/front.caddy --adapter caddyfile > /dev/null \
    || die "Не удалось запустить unosystem-proxy — вероятно, порт 80 занят. Пришлите: ss -ltnp"
  ok "Вход: свой Caddy unosystem-proxy на портах 80 и 443"
}

main() {
  [ "$(id -u)" -eq 0 ] || die "Нужен root: запустите через sudo"
  command -v docker > /dev/null || die "Не найден Docker"

  # 1. Код сайта
  command -v git > /dev/null || { log "Ставлю git"; apt-get update -qq < /dev/null && apt-get install -y -qq git < /dev/null; }
  if [ -d "$SRC/.git" ]; then
    log "Обновляю $SRC"
    git -C "$SRC" fetch -q --depth 1 origin main
    git -C "$SRC" reset -q --hard origin/main
  else
    log "Скачиваю сайт в $SRC"
    git clone -q --depth 1 "$REPO_URL" "$SRC"
  fi

  # 2. Файлы сайта в /srv/unosystem
  install -m 755 "$SRC/deploy/update.sh" "$UPDATER"
  "$UPDATER" --force

  # 3. Контейнер с файлами сайта
  docker network inspect "$NET" > /dev/null 2>&1 || docker network create "$NET" > /dev/null
  docker rm -f unosystem-web > /dev/null 2>&1 || true
  docker run -d --name unosystem-web --restart unless-stopped --network "$NET" \
    -v "$WWW":/srv:ro -v "$SRC/deploy":/etc/unosystem:ro \
    "$IMAGE" caddy run --config /etc/unosystem/web.caddy --adapter caddyfile > /dev/null
  for _ in $(seq 1 15); do
    docker exec unosystem-web wget -qO- --header 'Host: unosystem.ru' http://127.0.0.1/ 2> /dev/null | grep -q 'Uno System' && break
    sleep 1
  done
  docker exec unosystem-web wget -qO- --header 'Host: unosystem.ru' http://127.0.0.1/ 2> /dev/null | grep -q 'Uno System' \
    || die "Контейнер unosystem-web не отдаёт сайт. Пришлите: docker logs unosystem-web"
  ok "Контейнер unosystem-web отдаёт сайт"

  # 4. Вход HTTPS
  local front
  front=$(docker ps --filter publish=443 --format '{{.Names}}' | head -1)
  if [ -n "$front" ] && [ "$front" != unosystem-proxy ]; then
    shared_front "$front"
  elif [ -z "$front" ] && ss -ltnH 'sport = :443' 2> /dev/null | grep -q .; then
    die "Порт 443 занят не Docker-контейнером. Ничего не меняю — пришлите: ss -ltnp"
  else
    own_front
  fi

  # 5. Автообновление файлов раз в 5 минут
  cat > /etc/systemd/system/unosystem-site-update.service <<UNIT
[Unit]
Description=Uno System: обновление файлов сайта из GitHub
After=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=$UPDATER
UNIT
  cat > /etc/systemd/system/unosystem-site-update.timer <<UNIT
[Unit]
Description=Uno System: проверка обновлений сайта каждые 5 минут

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
UNIT
  systemctl daemon-reload
  systemctl enable --now unosystem-site-update.timer > /dev/null
  ok "Автообновление включено (unosystem-site-update.timer)"

  # 6. Проверка: сертификаты Let's Encrypt выпускаются за несколько секунд, DNS уже указывает на сервер
  log "Проверяю HTTPS"
  local host code
  for host in unosystem.ru www.unosystem.ru pulse.unosystem.ru; do
    code=000
    for _ in $(seq 1 20); do
      code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://$host/" || true)
      [ "$code" != "000" ] && break
      sleep 3
    done
    if [ "$code" = "000" ]; then
      printf '  %-22s пока нет HTTPS — сертификат ещё выпускается, проверьте через минуту\n' "$host"
    else
      printf '  %-22s HTTP %s\n' "$host" "$code"
    fi
  done
  ok "Готово: https://unosystem.ru"
}

main "$@"
