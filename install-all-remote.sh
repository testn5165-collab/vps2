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
    01-dropbear.sh
    02-slowdns.sh
    03-badvpn.sh
    04-ws-proxy.sh
    05-realip-tracker.sh
    06-xray-core.sh
    07-nginx-proxy.sh
    08-monitoring.sh
    09-ssh-manager.sh
    10-ssl.sh
    11-status.sh
    12-user-management.sh
    13-uninstall.sh
    14-install-components.sh
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

echo "-> Base system install ho raha hai (packages + Dropbear + SSH-WS + V2Ray + Real-IP tracker)..."
bash -c "
source '${BASE_DIR}/00-common.sh'
source '${BASE_DIR}/01-dropbear.sh'
source '${BASE_DIR}/02-slowdns.sh'
source '${BASE_DIR}/03-badvpn.sh'
source '${BASE_DIR}/04-ws-proxy.sh'
source '${BASE_DIR}/05-realip-tracker.sh'
source '${BASE_DIR}/06-xray-core.sh'
source '${BASE_DIR}/07-nginx-proxy.sh'
source '${BASE_DIR}/08-monitoring.sh'
source '${BASE_DIR}/14-install-components.sh'
install_all_components
" < /dev/null

cat > /usr/local/bin/menu << 'SHORTCUT'
#!/bin/bash
bash /etc/raretriccks/menu.sh
SHORTCUT
chmod +x /usr/local/bin/menu

echo -e "\n\033[0;32m[DONE] RareTriccks Panel install ho gaya.\033[0m"
echo "Ab kahin se bhi 'menu' likh ke Enter dabao - interactive panel khul jayega."
echo "Wahan se: Domain set karo -> SSL issue karo -> Users banao."
echo ""
echo "Real Client IP check karne ke liye: menu -> Option 7 (User Management) -> Option 3 (Connected IPs)."
