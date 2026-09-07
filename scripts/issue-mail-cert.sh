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

# certbot's container writes /etc/letsencrypt/live/<host> as root, mode 700
# (it protects the private key regardless of what we'd prefer) — a plain
# host-side `cp` as this script's own user can't even read into it. Do the
# copy inside a throwaway root container instead, writing out with our uid,
# so this never needs sudo (renew-mail-cert.sh runs this same way, unattended
# from cron, where a sudo password prompt would just hang forever).
docker run --rm \
  -v "$(pwd)/certbot-etc:/etc/letsencrypt:ro" \
  -v "$(pwd)/drive-osx-mail/tls:/out" \
  alpine sh -c "
    cp /etc/letsencrypt/live/$MAIL_HOST/fullchain.pem /out/fullchain.pem &&
    cp /etc/letsencrypt/live/$MAIL_HOST/privkey.pem /out/privkey.pem &&
    chown $(id -u):$(id -g) /out/fullchain.pem /out/privkey.pem &&
    chmod 644 /out/fullchain.pem /out/privkey.pem
  "

echo
echo "Certificate installed at drive-osx-mail/tls/. Restart the mail service to pick it up:"
echo "  docker compose restart drive-osx-mail"
echo
echo "Set up renewal now: crontab -e, then add"
echo "  0 3 1,15 * * $(pwd)/scripts/renew-mail-cert.sh >> /var/log/mail-cert-renew.log 2>&1"
