#!/usr/bin/env bash
set -euo pipefail

# One-time issuance of the TLS certificate drive-osx-mail uses for STARTTLS.
# Run this ONCE on the production host, after:
#   - DNS: mail.driveosx.com A record points at this host
#   - docker-compose.proxy.yml is already up (Caddy must be answering on :80
#     and serving the ACME challenge block for mail.driveosx.com — see
#     Caddyfile)
#
# For renewal, use ./scripts/renew-mail-cert.sh via cron instead — this
# script uses `certonly`, which does not auto-renew.

cd "$(dirname "$0")/.."

DOMAIN="${MAIL_DOMAIN:-driveosx.com}"
MAIL_HOST="mail.${DOMAIN}"
EMAIL="${CERTBOT_EMAIL:-postmaster@${DOMAIN}}"

mkdir -p certbot-webroot certbot-etc

docker run --rm \
  -v "$(pwd)/certbot-webroot:/var/www/certbot" \
  -v "$(pwd)/certbot-etc:/etc/letsencrypt" \
  certbot/certbot certonly \
    --webroot -w /var/www/certbot \
    -d "$MAIL_HOST" \
    --email "$EMAIL" \
    --agree-tos \
    --non-interactive

mkdir -p drive-osx-mail/tls
cp "certbot-etc/live/$MAIL_HOST/fullchain.pem" drive-osx-mail/tls/fullchain.pem
cp "certbot-etc/live/$MAIL_HOST/privkey.pem" drive-osx-mail/tls/privkey.pem
chmod 644 drive-osx-mail/tls/fullchain.pem drive-osx-mail/tls/privkey.pem

echo
echo "Certificate installed at drive-osx-mail/tls/. Restart the mail service to pick it up:"
echo "  docker compose restart drive-osx-mail"
echo
echo "Set up renewal now: crontab -e, then add"
echo "  0 3 1,15 * * $(pwd)/scripts/renew-mail-cert.sh >> /var/log/mail-cert-renew.log 2>&1"
