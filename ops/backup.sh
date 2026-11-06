#!/bin/sh
# Encrypts this stack's data and pushes it to a private GitHub repository, one
# branch per server and weekday, so a week of backups lives outside Oracle.
# Only the public age key is on the server; the private key is on the owner's
# PC, so a stolen server cannot read old backups. See "Backups" in the README.
#
#   ops/backup.sh server|vernissage
set -eu

STACK=$1
OPS=$(cd "$(dirname "$0")" && pwd)
REPO=git@github.com:Nafiz001/portfolio-backups.git
BRANCH=$(hostname)-$(date +%a | tr '[:upper:]' '[:lower:]')

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/data" "$WORK/repo"
DATA=$WORK/data
cd "$OPS/../$STACK"
cp .env "$DATA/env"

# The database named in the container's own environment.
dump() {
  docker compose exec -T "$1" sh -c 'pg_dump --clean --if-exists -U "$POSTGRES_USER" "$POSTGRES_DB"' </dev/null >"$DATA/$1.sql"
}

case $STACK in
  vernissage)
    for db in db kori-db katar-db order-db inventory-db; do dump "$db"; done
    docker compose exec -T noctiluca python -c "import sqlite3; sqlite3.connect('/data/sea.sqlite3').backup(sqlite3.connect('/tmp/backup.sqlite3'))" </dev/null
    docker compose cp noctiluca:/tmp/backup.sqlite3 "$DATA/noctiluca.sqlite3" >/dev/null 2>&1
    docker compose exec -T noctiluca rm -f /tmp/backup.sqlite3 </dev/null
    ;;
  server)
    for v in ebru-data kirie-data; do
      tar -C "/var/lib/docker/volumes/portfolio_$v/_data" -cf "$DATA/$v.tar" .
    done
    ;;
esac

tar -C "$DATA" -cf - . | gzip -9 | age -R "$OPS/backup-recipient.txt" >"$WORK/repo/$STACK-$(date +%F).tar.gz.age"

cd "$WORK/repo"
git init --quiet --initial-branch="$BRANCH"
git add .
git -c user.name=portfolio-backup -c user.email=backup@localhost commit --quiet -m "Backup of $STACK from $(hostname), $(date +%F)"
# Each branch is one commit, replaced each week, so the repository stays small.
GIT_SSH_COMMAND="ssh -i /root/.ssh/portfolio-backup -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
  git push --quiet --force "$REPO" "$BRANCH"
echo "Pushed $(du -h "$WORK"/repo/*.age | cut -f1) to $BRANCH"
