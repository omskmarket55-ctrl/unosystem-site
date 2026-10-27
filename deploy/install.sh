#!/usr/bin/env bash
# Ставит сайт unosystem.ru на сервер, где Caddy уже обслуживает другие сайты (например, CRMUNO).
# Чужие сайты не трогает: кладёт свой файл /etc/caddy/unosystem.caddy, добавляет в Caddyfile одну строку
# import, проверяет итоговый конфиг и мягко перезагружает Caddy. Если проверка не прошла — всё возвращает.
# Повторный запуск безопасен. Запуск от root:
#   curl -fsSL https://raw.githubusercontent.com/omskmarket55-ctrl/unosystem-site/main/deploy/install.sh | bash
set -euo pipefail

REPO_URL="https://github.com/omskmarket55-ctrl/unosystem-site.git"
SRC=/opt/unosystem-site
SITE_CONF=/etc/caddy/unosystem.caddy
UPDATER=/usr/local/sbin/unosystem-site-update

log() { printf '\033[1;34m▸\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

main() {
  [ "$(id -u)" -eq 0 ] || die "Нужен root: запустите через sudo"

  # 1. Кто держит порт 443. Работаем только с Caddy, установленным как служба systemd.
  log "Проверяю, как запущен Caddy"
  LISTENER=$(ss -ltnpH 'sport = :443' 2>/dev/null | grep -oE 'users:\(\("[^"]+"' | head -1 | cut -d'"' -f2 || true)
  case "$LISTENER" in
    caddy) ;;
    docker-proxy) die "Порт 443 держит Docker-контейнер. Автоматически ничего не меняю — пришлите вывод: docker ps" ;;
    "") die "Порт 443 никто не слушает. Пришлите вывод: ss -ltnp; systemctl status caddy" ;;
    *) die "Порт 443 занят процессом «$LISTENER», это не Caddy. Ничего не меняю" ;;
  esac
  systemctl is-active --quiet caddy || die "Caddy работает не как служба systemd. Пришлите вывод: ps aux | grep caddy"
  CADDYFILE=$(systemctl show -p ExecStart caddy | grep -oE -- '--config [^ ;]+' | head -1 | awk '{print $2}' || true)
  CADDYFILE=${CADDYFILE:-/etc/caddy/Caddyfile}
  [ -f "$CADDYFILE" ] || die "Не найден конфиг Caddy: $CADDYFILE"
  case "$CADDYFILE" in *.json) die "Caddy настроен JSON-файлом ($CADDYFILE) — автоматически не меняю" ;; esac
  ok "Caddy: служба systemd, конфиг $CADDYFILE"

  # 2. Код сайта
  command -v git >/dev/null || { log "Ставлю git"; apt-get update -qq < /dev/null && apt-get install -y -qq git < /dev/null; }
  if [ -d "$SRC/.git" ]; then
    log "Обновляю $SRC"
    git -C "$SRC" fetch -q --depth 1 origin main
    git -C "$SRC" reset -q --hard origin/main
  else
    log "Скачиваю сайт в $SRC"
    git clone -q --depth 1 "$REPO_URL" "$SRC"
  fi

  # 3. Файлы сайта в /var/www
  install -m 755 "$SRC/deploy/update.sh" "$UPDATER"
  "$UPDATER" --force

  # 4. Конфиг Caddy: свой файл + одна строка import, с проверкой и откатом
  if grep -vE '^\s*(#|import )' "$CADDYFILE" | grep -E '(^|[[:space:],/])(www\.|pulse\.)?unosystem\.ru([[:space:],:{]|$)' > /dev/null; then
    die "В $CADDYFILE уже есть настройки для unosystem.ru — уберите их и запустите снова"
  fi
  STAMP=$(date +%Y%m%d-%H%M%S)
  cp -a "$CADDYFILE" "$CADDYFILE.bak-$STAMP"
  HAD_CONF=0
  if [ -f "$SITE_CONF" ]; then HAD_CONF=1; cp -a "$SITE_CONF" "$SITE_CONF.bak-$STAMP"; fi

  install -m 644 "$SRC/deploy/unosystem.caddy" "$SITE_CONF"
  if ! grep -qxF "import $SITE_CONF" "$CADDYFILE"; then
    printf '\n# Uno System (unosystem.ru) — добавлено %s/deploy/install.sh\nimport %s\n' "$SRC" "$SITE_CONF" >> "$CADDYFILE"
  fi

  log "Проверяю итоговый конфиг Caddy"
  if ! caddy validate --config "$CADDYFILE" --adapter caddyfile > /tmp/unosystem-validate.log 2>&1; then
    cp -a "$CADDYFILE.bak-$STAMP" "$CADDYFILE"
    if [ "$HAD_CONF" -eq 1 ]; then cp -a "$SITE_CONF.bak-$STAMP" "$SITE_CONF"; else rm -f "$SITE_CONF"; fi
    tail -n 20 /tmp/unosystem-validate.log >&2
    die "Конфиг не прошёл проверку. Всё вернул как было, Caddy не перезагружал"
  fi
  systemctl reload caddy || die "Caddy не принял новый конфиг (старый продолжает работать). Пришлите: journalctl -u caddy -n 50"
  ok "Caddy перезагружен мягко, остальные сайты работают как раньше"

  # 5. Автообновление: раз в 5 минут забирать новую версию файлов сайта
  cat > /etc/systemd/system/unosystem-site-update.service <<UNIT
[Unit]
Description=Uno System: обновление файлов сайта из GitHub
After=network-online.target

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

  # 6. Проверка: сертификат Let's Encrypt выпускается за несколько секунд после того, как DNS указывает на сервер
  log "Жду HTTPS для unosystem.ru"
  for host in unosystem.ru www.unosystem.ru pulse.unosystem.ru; do
    code=000
    for _ in $(seq 1 20); do
      code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://$host/" || true)
      [ "$code" != "000" ] && break
      sleep 3
    done
    if [ "$code" = "000" ]; then
      printf '  %-22s пока нет HTTPS — проверьте DNS (dig +short %s), сертификат выпустится сам\n' "$host" "$host"
    else
      printf '  %-22s HTTP %s\n' "$host" "$code"
    fi
  done
  ok "Готово: https://unosystem.ru"
}

main "$@"
