#!/bin/sh
# One-time setup on a fresh Ubuntu server that already has Docker and
# docker compose. Run as the login user (who must be in the docker group):
#
#   curl -fsSL https://raw.githubusercontent.com/Nafiz001/portfolio-deploy/main/server/install.sh | sh
#
# STACK chooses which directory of this repository the server runs: server
# (the default: most of the portfolio) or vernissage (Vernissage's API and
# database, which needs SITE_URL as well):
#
#   curl -fsSL .../server/install.sh | STACK=vernissage SITE_URL=https://<site> sh
#
# It clones this repository to /opt/portfolio, writes the stack's .env with
# its init-env.sh, installs a systemd timer that runs the stack's update.sh
# every 10 minutes, and starts everything.
set -eu

REPO=https://github.com/Nafiz001/portfolio-deploy.git
DIR=/opt/portfolio
STACK=${STACK:-server}

if [ ! -d "$DIR/.git" ]; then
  sudo mkdir -p "$DIR"
  sudo chown "$(id -un)" "$DIR"
  git clone --quiet "$REPO" "$DIR"
fi
cd "$DIR/$STACK"

if [ ! -f .env ]; then
  sh ./init-env.sh > .env.new
  mv .env.new .env
  chmod 600 .env
fi

sudo tee /etc/systemd/system/portfolio-update.service >/dev/null <<EOF
[Unit]
Description=Pull the latest images for the $STACK stack and restart what changed
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$(id -un)
ExecStart=$DIR/$STACK/update.sh
EOF

sudo tee /etc/systemd/system/portfolio-update.timer >/dev/null <<EOF
[Unit]
Description=Update the $STACK stack every 10 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now portfolio-update.timer >/dev/null
sh ./update.sh
echo "Up: the $STACK stack."
