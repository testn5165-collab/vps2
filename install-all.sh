#!/bin/bash
# ==============================================================================
# RareTriccks VPN Panel - install-all.sh (LOCAL)
# Chalao jab saari .sh files already isi folder mein maujood hon
# (e.g. git clone karne ke baad).
#
# Usage: bash install-all.sh
# ==============================================================================
set -e

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Root chahiye. sudo -i karke phir se chalao."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

echo "-> RareTriccks panel files /etc/raretriccks mein copy ho rahe hain..."
for f in "${FILES[@]}"; do
    if [[ ! -f "${SCRIPT_DIR}/${f}" ]]; then
        echo "[ERROR] ${f} is folder mein nahi mili: ${SCRIPT_DIR}"
        exit 1
    fi
    cp "${SCRIPT_DIR}/${f}" "${BASE_DIR}/${f}"
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
