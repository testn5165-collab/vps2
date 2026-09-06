#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - install-all.sh
# Sab modules sahi order mein chalata hai.
#
# One-click install ke case mein (bash <(curl ...)) ye script khud se hi
# baaki saari zaroori .sh files GitHub se download karta hai — kyunki
# process-substitution se sirf ye file hi memory mein aati hai, folder
# ke baaki files nahi.
#
#   bash <(curl -Ls https://raw.githubusercontent.com/testn5165-collab/vps-script-1/main/install-all.sh) yourdomain.com
# ==============================================================================
set -e
DOMAIN="$1"

if [[ -z "$DOMAIN" ]]; then
    echo "Usage: bash install-all.sh yourdomain.com"
    exit 1
fi

REPO_RAW="https://raw.githubusercontent.com/testn5165-collab/vps-script-1/main"
BASE_DIR="/etc/raretriccks"

mkdir -p "$BASE_DIR"

FILES=(
    00-common.sh
    01-base-install.sh
    02-ssl-cert.sh
    03-dropbear-ssh.sh
    04-ssh-ws.sh
    05-ssh-ssl-stunnel.sh
    06-nginx-multiplexer.sh
    07-xray-vless.sh
    08-badvpn-udpgw.sh
    09-user-manager.sh
    10-dtunnel-support.sh
    11-telegram-bot.sh
    12-menu-shortcut.sh
    menu.sh
)

echo "-> RARETRICCKS scripts download ho rahe hain..."
for f in "${FILES[@]}"; do
    curl -Ls "${REPO_RAW}/${f}" -o "${BASE_DIR}/${f}"
done
chmod +x "${BASE_DIR}"/*.sh

echo "$DOMAIN" > "${BASE_DIR}/domain.conf"

bash "${BASE_DIR}/01-base-install.sh"
bash "${BASE_DIR}/03-dropbear-ssh.sh"
bash "${BASE_DIR}/04-ssh-ws.sh"
bash "${BASE_DIR}/10-dtunnel-support.sh"
bash "${BASE_DIR}/02-ssl-cert.sh"
bash "${BASE_DIR}/05-ssh-ssl-stunnel.sh"
bash "${BASE_DIR}/07-xray-vless.sh"
bash "${BASE_DIR}/06-nginx-multiplexer.sh"
bash "${BASE_DIR}/08-badvpn-udpgw.sh"

echo -e "\n\033[0;32m[ALL DONE] RARETRICCKS MULTI PROTOCOL fully installed on ${DOMAIN}\033[0m"
