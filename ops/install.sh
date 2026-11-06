#!/bin/sh
# Sets up this server's scheduled jobs. Run once as the login user:
#
#   ops/install.sh server|vernissage
#
# The micro (server) gets keep-active; the A1 (vernissage) doesn't need it,
# since its memory stays above Oracle's idle line. Both get the nightly backup.
# Prints the backup deploy key, which goes on the portfolio-backups repository.
set -eu

STACK=$1
OPS=$(cd "$(dirname "$0")" && pwd)

command -v age >/dev/null || { sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq age >/dev/null 2>&1; }

sudo test -f /root/.ssh/portfolio-backup ||
  sudo ssh-keygen -q -t ed25519 -N '' -C "backup@$(hostname)" -f /root/.ssh/portfolio-backup

sed "s/@STACK@/$STACK/" "$OPS/backup.service" | sudo tee /etc/systemd/system/portfolio-backup.service >/dev/null
sudo cp "$OPS/backup.timer" /etc/systemd/system/portfolio-backup.timer
timers=portfolio-backup.timer

if [ "$STACK" = server ]; then
  sudo cp "$OPS/keep-active.service" "$OPS/keep-active.timer" /etc/systemd/system/
  timers="$timers keep-active.timer"
fi

sudo systemctl daemon-reload
sudo systemctl enable --now $timers >/dev/null
sudo cat /root/.ssh/portfolio-backup.pub
