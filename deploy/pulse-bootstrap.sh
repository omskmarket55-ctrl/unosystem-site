#!/usr/bin/env bash
# Первичная загрузка Пульс КЦ на сервер. Репозиторий pulse-kc закрытый, поэтому сервер забирает код
# по ключу развёртывания (deploy key) — только на чтение. Первый запуск создаёт ключ и показывает его:
# добавьте ключ в GitHub и запустите команду снова. Дальше установку ведёт pulse-kc/deploy/install.sh.
# Запуск от root:
#   curl -fsSL https://raw.githubusercontent.com/omskmarket55-ctrl/unosystem-site/main/deploy/pulse-bootstrap.sh | sudo bash
set -euo pipefail

REPO=git@github.com:omskmarket55-ctrl/pulse-kc.git
SRC=/opt/pulse-kc
KEY=/root/.ssh/pulse-kc-deploy
KNOWN=/root/.ssh/known_hosts_github

ok() { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

main() {
  [ "$(id -u)" -eq 0 ] || die "Нужен root: запустите через sudo"
  command -v git > /dev/null || { apt-get update -qq < /dev/null && apt-get install -y -qq git < /dev/null; }
  install -d -m 700 /root/.ssh

  # Ключи github.com берём с api.github.com по HTTPS, чтобы не доверять первому подключению вслепую
  local strict=yes keys
  keys=$(curl -fsSL --max-time 15 https://api.github.com/meta | grep -oE '"(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa) [A-Za-z0-9+/=]+"' | tr -d '"' || true)
  if [ -n "$keys" ]; then
    printf '%s\n' "$keys" | sed 's/^/github.com /' > "$KNOWN"
  else
    printf '  Не удалось получить ключи github.com с api.github.com — запомню ключ при первом подключении\n'
    strict=accept-new
  fi
  export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o UserKnownHostsFile=$KNOWN -o StrictHostKeyChecking=$strict"

  if [ ! -f "$KEY" ]; then
    ssh-keygen -q -t ed25519 -N '' -C "pulse-kc deploy $(hostname)" -f "$KEY"
  fi
  if ! git ls-remote "$REPO" > /dev/null 2>&1; then
    printf '\n\033[1mДобавьте ключ сервера в GitHub (один раз):\033[0m\n'
    printf '  1. Откройте https://github.com/omskmarket55-ctrl/pulse-kc/settings/keys → Add deploy key\n'
    printf '  2. Title: сервер unosystem; Key — строка ниже; галочку «Allow write access» НЕ ставьте\n\n'
    cat "$KEY.pub"
    printf '\n  3. Запустите эту же команду ещё раз.\n'
    exit 1
  fi
  ok "Доступ к репозиторию pulse-kc есть"

  if [ -d "$SRC/.git" ]; then
    git -C "$SRC" fetch -q --depth 1 origin main
    git -C "$SRC" reset -q --hard origin/main
  else
    git clone -q --depth 1 "$REPO" "$SRC"
  fi
  git -C "$SRC" config core.sshCommand "$GIT_SSH_COMMAND"
  ok "Код Пульса в $SRC ($(git -C "$SRC" rev-parse --short HEAD))"

  exec bash "$SRC/deploy/install.sh"
}

main "$@"
