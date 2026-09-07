#!/bin/bash
# ==============================================================================
# RareTriccks VPN Panel - install-all-remote.sh (ONE-CLICK)
# Saari module .sh files GitHub se download karke base system install karta hai.
#
# Usage:
#   bash <(curl -Ls https://raw.githubusercontent.com/<user>/<repo>/main/install-all-remote.sh)
#
# IMPORTANT: Neeche REPO_RAW ko apne asli GitHub repo (user/repo/branch) se
# update kar lena upload karne ke baad.
# ==============================================================================
set -e

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Root chahiye. sudo -i karke phir se chalao."
    exit 1
fi

REPO_RAW="https://raw.githubusercontent.com/testn5165-collab/vps2/main"
BASE_DIR="/etc/raretriccks"

mkdir -p "$BASE_DIR"

FILES=(
    00-common.sh
    01-nginx-domain.sh
    02-install-components.sh
    03-ssl.sh
    04-monitoring.sh
    05-user-manager.sh
    06-status-banner.sh
    07-telegram-bot.sh
    08-uninstall.sh
    09-xray.sh
    10-stunnel.sh
    menu.sh
)

echo "-> RareTriccks panel files download ho rahe hain (${REPO_RAW})..."
for f in "${FILES[@]}"; do
    if ! curl -fLs "${REPO_RAW}/${f}" -o "${BASE_DIR}/${f}"; then
        echo "[ERROR] ${f} download nahi ho payi. Repo/branch/filename check karo: ${REPO_RAW}/${f}"
        exit 1
    fi
    if [[ ! -s "${BASE_DIR}/${f}" ]]; then
        echo "[ERROR] ${f} khaali download hui. Ruk raha hoon."
        exit 1
    fi
done
chmod +x "${BASE_DIR}"/*.sh

echo "-> Base system install ho raha hai (packages + Dropbear + WS proxy + tracker)..."
bash -c "
source '${BASE_DIR}/00-common.sh'
source '${BASE_DIR}/01-nginx-domain.sh'
source '${BASE_DIR}/02-install-components.sh'
install_all_components
" < /dev/null

cat > /usr/local/bin/menu << 'SHORTCUT'
#!/bin/bash
bash /etc/raretriccks/menu.sh
SHORTCUT
chmod +x /usr/local/bin/menu

echo -e "\n\033[0;32m[DONE] RareTriccks Panel install ho gaya.\033[0m"
echo "Ab kahin se bhi 'menu' likh ke Enter dabao - interactive panel khul jayega."
echo "Wahan se: Domain set karo (2) -> SSL issue karo (3) -> SSH users banao (4)"
echo "         -> V2Ray/Xray install + users (5) -> SSH-over-SSL setup (6)."
