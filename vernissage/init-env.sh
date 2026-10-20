#!/bin/sh
# Prints this stack's .env for install.sh: the API's domain from the
# server's public IP, the site's address (SITE_URL, given to install.sh),
# and random secrets for the database and the live-room tickets.
set -eu
ip=$(curl -fsS https://api.ipify.org)
secret() { head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
echo "# Written by install.sh. Not in git: the passwords are secrets."
echo "API_DOMAIN=api.$(echo "$ip" | tr . -).sslip.io"
echo "NOCTILUCA_DOMAIN=noctiluca.$(echo "$ip" | tr . -).sslip.io"
echo "NOCTILUCA_SITE_HOST=${NOCTILUCA_SITE_HOST:?run install.sh with NOCTILUCA_SITE_HOST=<the noctiluca site's host>}"
echo "NOCTILUCA_SECRET_KEY=$(secret)"
echo "KORI_DOMAIN=kori.$(echo "$ip" | tr . -).sslip.io"
echo "QUILL_DOMAIN=quill.$(echo "$ip" | tr . -).sslip.io"
echo "KORI_DB_PASSWORD=$(secret)"
echo "KORI_JWT_SECRET=$(secret)"
echo "WAREHOUSE_DOMAIN=warehouse.$(echo "$ip" | tr . -).sslip.io"
echo "GRAFANA_DOMAIN=grafana.$(echo "$ip" | tr . -).sslip.io"
echo "SANDGLASS_DOMAIN=sandglass.$(echo "$ip" | tr . -).sslip.io"
echo "WAREHOUSE_DB_PASSWORD=$(secret)"
echo "WAREHOUSE_GRAFANA_PASSWORD=$(secret)"
echo "SITE_URL=${SITE_URL:?run install.sh with SITE_URL=https://<the site>}"
echo "POSTGRES_PASSWORD=$(secret)"
echo "VERNISSAGE_SECRET=$(secret)"
