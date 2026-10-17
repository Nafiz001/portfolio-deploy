#!/bin/sh
# Prints this stack's .env for install.sh: the domain from the server's
# public IP, and a random salt for kirie.
set -eu
ip=$(curl -fsS https://api.ipify.org)
echo "# Written by install.sh. Not in git: KIRIE_SALT is a secret."
echo "DOMAIN=$(echo "$ip" | tr . -).sslip.io"
echo "KIRIE_SALT=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
