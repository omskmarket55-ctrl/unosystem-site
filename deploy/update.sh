#!/usr/bin/env bash
# Обновляет файлы сайта из GitHub: забирает main и подменяет папки в /srv/unosystem целиком.
# Конфиги Caddy не трогает. install.sh кладёт копию этого файла в /usr/local/sbin/unosystem-site-update,
# её раз в 5 минут запускает таймер systemd — так изменения в репозитории меняют только файлы сайта.
set -euo pipefail

SRC=/opt/unosystem-site
WWW=/srv/unosystem          # примонтирована в unosystem-web как /srv; внутри меняются только подпапки
NET=unosystem
FORCE=${1:-}

cd "$SRC"
git fetch -q --depth 1 origin main
if [ "$FORCE" = "--force" ] || [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
  git reset -q --hard origin/main

  # Новая версия собирается рядом и встаёт на место одним переименованием
  deploy_dir() {
    local src=$1 dst=$2
    rm -rf "$dst.new" "$dst.old"
    cp -a "$src" "$dst.new"
    chmod -R a+rX "$dst.new"
    if [ -d "$dst" ]; then mv "$dst" "$dst.old"; fi
    mv "$dst.new" "$dst"
    rm -rf "$dst.old"
  }
  mkdir -p "$WWW"
  deploy_dir "$SRC/public" "$WWW/site"
  deploy_dir "$SRC/pulse-soon" "$WWW/pulse-soon"
  echo "$(date '+%F %T') сайт обновлён до $(git rev-parse --short HEAD)"
fi

# Если вход — Caddy другого проекта и его контейнер пересоздали, он выпадает из сети unosystem.
# Подключаем обратно, но только если в его Caddyfile есть наш блок.
front=$(docker ps --filter publish=443 --format '{{.Names}}' | head -1)
if [ -n "$front" ] && [ "$front" != unosystem-proxy ] && docker network inspect "$NET" > /dev/null 2>&1; then
  if ! docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$front" | grep -qw "$NET" \
     && docker exec "$front" grep -q '^# >>> unosystem.ru' /etc/caddy/Caddyfile 2> /dev/null; then
    docker network connect "$NET" "$front"
    echo "$(date '+%F %T') $front снова подключён к сети $NET"
  fi
fi
