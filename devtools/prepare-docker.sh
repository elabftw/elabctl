#!/usr/bin/env sh
apt update
apt install -y git zip dialog curl vim sudo
echo "pwet" > /usr/bin/docker-compose
chmod +x /usr/bin/docker-compose
cd /root || exit 1
