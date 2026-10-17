#!/bin/sh
# One-time setup on a fresh Ubuntu server that already has Docker and
# docker compose. Run as the login user (who must be in the docker group):
#
#   curl -fsSL https://raw.githubusercontent.com/Nafiz001/portfolio-deploy/main/server/install.sh | sh
#
# It clones this repository to /opt/portfolio, writes server/.env (the domain
# from the server's public IP, and a random salt for kirie), installs a
# systemd timer that runs update.sh every 10 minutes, and starts everything.
set -eu

REPO=https://github.com/Nafiz001/portfolio-deploy.git
DIR=/opt/portfolio

if [ ! -d "$DIR/.git" ]; then
  sudo mkdir -p "$DIR"
  sudo chown "$(id -un)" "$DIR"
  git clone --quiet "$REPO" "$DIR"
fi
cd "$DIR/server"

if [ ! -f .env ]; then
  ip=$(curl -fsS https://api.ipify.org)
  {
    echo "# Written by install.sh. Not in git: KIRIE_SALT is a secret."
    echo "DOMAIN=$(echo "$ip" | tr . -).sslip.io"
    echo "KIRIE_SALT=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  } > .env
  chmod 600 .env
fi

sudo tee /etc/systemd/system/portfolio-update.service >/dev/null <<EOF
[Unit]
Description=Pull the latest portfolio images and restart what changed
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$(id -un)
ExecStart=$DIR/server/update.sh
EOF

sudo tee /etc/systemd/system/portfolio-update.timer >/dev/null <<EOF
[Unit]
Description=Update the portfolio every 10 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now portfolio-update.timer >/dev/null
sh ./update.sh
echo "Up. Sites: https://$(grep '^DOMAIN=' .env | cut -d= -f2)"
