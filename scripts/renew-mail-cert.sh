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

if [ "certbot-etc/live/$MAIL_HOST/fullchain.pem" -nt "drive-osx-mail/tls/fullchain.pem" ]; then
  cp "certbot-etc/live/$MAIL_HOST/fullchain.pem" drive-osx-mail/tls/fullchain.pem
  cp "certbot-etc/live/$MAIL_HOST/privkey.pem" drive-osx-mail/tls/privkey.pem
  chmod 644 drive-osx-mail/tls/fullchain.pem drive-osx-mail/tls/privkey.pem
  docker compose restart drive-osx-mail
  echo "$(date -Is): renewed and restarted drive-osx-mail"
fi
