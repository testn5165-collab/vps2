#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - install-all.sh
# Sab modules sahi order mein chalata hai. GitHub raw se pull karke run karo:
#   bash install-all.sh yourdomain.com
# ==============================================================================
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="$1"

if [[ -z "$DOMAIN" ]]; then
    echo "Usage: bash install-all.sh yourdomain.com"
    exit 1
fi

mkdir -p /etc/raretriccks
cp -f "$SCRIPT_DIR/00-common.sh" /etc/raretriccks/00-common.sh
cp -f "$SCRIPT_DIR/menu.sh" /etc/raretriccks/menu.sh
cp -f "$SCRIPT_DIR/09-user-manager.sh" /etc/raretriccks/09-user-manager.sh
echo "$DOMAIN" > /etc/raretriccks/domain.conf

bash "$SCRIPT_DIR/01-base-install.sh"
bash "$SCRIPT_DIR/03-dropbear-ssh.sh"
bash "$SCRIPT_DIR/04-ssh-ws.sh"
bash "$SCRIPT_DIR/10-dtunnel-support.sh"
bash "$SCRIPT_DIR/02-ssl-cert.sh"
bash "$SCRIPT_DIR/05-ssh-ssl-stunnel.sh"
bash "$SCRIPT_DIR/07-xray-vless.sh"
bash "$SCRIPT_DIR/06-nginx-multiplexer.sh"
bash "$SCRIPT_DIR/08-badvpn-udpgw.sh"

echo -e "\n\033[0;32m[ALL DONE] RARETRICCKS MULTI PROTOCOL fully installed on ${DOMAIN}\033[0m"
echo "User banane ke liye: bash ${SCRIPT_DIR}/09-user-manager.sh add <user> <pass> <days> <ip_limit> <gb_limit>"
