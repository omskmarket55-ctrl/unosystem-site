#!/usr/bin/env bash
# Обновляет файлы сайта из GitHub: забирает main и подменяет папки в /var/www целиком.
# Конфиг Caddy не трогает. install.sh кладёт копию этого файла в /usr/local/sbin/unosystem-site-update,
# её раз в 5 минут запускает таймер systemd — так изменения в репозитории меняют только файлы сайта.
set -euo pipefail

SRC=/opt/unosystem-site
FORCE=${1:-}

cd "$SRC"
git fetch -q --depth 1 origin main
if [ "$FORCE" != "--force" ] && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]; then
  exit 0
fi
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

mkdir -p /var/www
deploy_dir "$SRC/public" /var/www/unosystem
deploy_dir "$SRC/pulse-soon" /var/www/pulse-soon
echo "$(date '+%F %T') сайт обновлён до $(git rev-parse --short HEAD)"
