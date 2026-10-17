#!/bin/sh
# Brings the server in line with GitHub: the latest compose file and Caddyfile
# from this repository, then the latest image of every project. Containers
# whose image did not change are left running. Run by portfolio-update.timer
# every 10 minutes, or by hand.
set -eu
cd "$(dirname "$0")"

git -C .. pull --quiet --ff-only
docker compose pull --quiet
docker compose up --detach --remove-orphans --quiet-pull
# Caddy only rereads its config when told to.
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 || true
docker image prune --force >/dev/null
