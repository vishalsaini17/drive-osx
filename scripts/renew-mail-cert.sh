#!/usr/bin/env bash
set -euo pipefail

# Run periodically via cron (see the crontab line issue-mail-cert.sh prints).
# `certbot renew` only actually renews certificates within 30 days of expiry,
# so this is safe to run often — most invocations do nothing.
#
# Caddy keeps serving the ACME challenge the whole time (Caddyfile's
# mail.driveosx.com block), so this never needs to stop the proxy.

cd "$(dirname "$0")/.."

MAIL_HOST="mail.${MAIL_DOMAIN:-driveosx.com}"

docker run --rm \
  -v "$(pwd)/certbot-webroot:/var/www/certbot" \
  -v "$(pwd)/certbot-etc:/etc/letsencrypt" \
  certbot/certbot renew --webroot -w /var/www/certbot --quiet

BEFORE=""
if [ -f drive-osx-mail/tls/fullchain.pem ]; then
  BEFORE=$(sha256sum drive-osx-mail/tls/fullchain.pem | cut -d' ' -f1)
fi

# certbot's live/<host> dir is root-owned, mode 700 (protects the private
# key) — this script's own user can't read into it, let alone compare
# mtimes on it, so the copy has to happen inside a root container, same as
# issue-mail-cert.sh.
docker run --rm \
  -v "$(pwd)/certbot-etc:/etc/letsencrypt:ro" \
  -v "$(pwd)/drive-osx-mail/tls:/out" \
  alpine sh -c "
    cp /etc/letsencrypt/live/$MAIL_HOST/fullchain.pem /out/fullchain.pem &&
    cp /etc/letsencrypt/live/$MAIL_HOST/privkey.pem /out/privkey.pem &&
    chown $(id -u):$(id -g) /out/fullchain.pem /out/privkey.pem &&
    chmod 644 /out/fullchain.pem /out/privkey.pem
  "

AFTER=$(sha256sum drive-osx-mail/tls/fullchain.pem | cut -d' ' -f1)

if [ "$BEFORE" != "$AFTER" ]; then
  docker compose restart drive-osx-mail
  echo "$(date -Is): renewed and restarted drive-osx-mail"
fi
