#!/bin/sh
# certbot-renew.sh — Renews Let's Encrypt certificate and reloads nginx
#
# Run as a cron job on the EC2 host:
#   0 0 * * 0 /opt/project-sauron/monitoring/nginx/scripts/certbot-renew.sh
#
# Make executable after deploy: chmod +x /opt/project-sauron/monitoring/nginx/scripts/certbot-renew.sh
set -e

echo "$(date): Running certbot renew..."
docker compose -f /opt/project-sauron/monitoring/docker-compose.yml run --rm certbot renew --webroot -w /var/www/certbot --quiet

echo "$(date): Reloading nginx..."
docker compose -f /opt/project-sauron/monitoring/docker-compose.yml exec nginx nginx -s reload

echo "$(date): Renewal complete."
