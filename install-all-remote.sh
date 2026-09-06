#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - install-all-remote.sh
# ONE-CLICK INSTALLER. Sab modules GitHub se download karke sahi order mein
# chalata hai. Process-substitution (bash <(curl ...)) se sirf ye ek file
# memory mein aati hai, isliye ye khud baaki saari .sh files repo se fetch
# karta hai.
#
# Usage:
#   bash <(curl -Ls https://raw.githubusercontent.com/testn5165-collab/vps2/main/install-all-remote.sh) yourdomain.com
# ==============================================================================
set -e
DOMAIN="$1"

if [[ -z "$DOMAIN" ]]; then
    echo "Usage: bash <(curl -Ls .../install-all-remote.sh) yourdomain.com"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Root chahiye. sudo -i karke phir se chalao."
    exit 1
fi

REPO_RAW="https://raw.githubusercontent.com/testn5165-collab/vps2/main"
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

echo "-> RARETRICCKS scripts download ho rahe hain (${REPO_RAW})..."
for f in "${FILES[@]}"; do
    if ! curl -fLs "${REPO_RAW}/${f}" -o "${BASE_DIR}/${f}"; then
        echo "[ERROR] ${f} download nahi ho payi. Repo/branch/filename check karo: ${REPO_RAW}/${f}"
        exit 1
    fi
    # Khali ya 404-HTML file ko bhi pakdo (curl -f zyadatar cases handle karta
    # hai, lekin extra safety ke liye size bhi check kar rahe hain).
    if [[ ! -s "${BASE_DIR}/${f}" ]]; then
        echo "[ERROR] ${f} khaali download hui. Ruk raha hoon."
        exit 1
    fi
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
echo "User banane ke liye: bash ${BASE_DIR}/09-user-manager.sh add <user> <pass> <days> <ip_limit> <gb_limit>"
echo "Telegram bot (optional): bash ${BASE_DIR}/11-telegram-bot.sh"
echo "Menu shortcut (optional): bash ${BASE_DIR}/12-menu-shortcut.sh"
