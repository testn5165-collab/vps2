#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - 03-dropbear-ssh.sh
# SSH Direct core: dropbear on 22, 109 (WS backend), 8022 (backup).
# ==============================================================================
set -e
source /etc/raretriccks/00-common.sh

clear
echo -e "${CYAN}====================================================${NC}"
echo -e "${YELLOW}   ${PANEL_NAME} - DROPBEAR SSH SETUP               ${NC}"
echo -e "${CYAN}====================================================${NC}"

mkdir -p /etc/dropbear
chmod 700 /etc/dropbear

for kt in rsa:dropbear_rsa_host_key ecdsa:dropbear_ecdsa_host_key ed25519:dropbear_ed25519_host_key; do
    algo="${kt%%:*}"; file="${kt##*:}"
    [[ -f "/etc/dropbear/${file}" ]] || dropbearkey -t "$algo" -f "/etc/dropbear/${file}" &>/dev/null
done
chmod 600 /etc/dropbear/*_host_key 2>/dev/null || true
rm -rf /etc/systemd/system/dropbear.service.d

cat << 'BANNER_EOF' > "$BANNER_FILE"
<font color="green">==========================================</font><br>
<font color="yellow"><b>WELCOME TO RARETRICCKS MULTI PROTOCOL</b></font><br>
<font color="red"><b>- NO TORRENT / NO MULTILOGIN</b></font><br>
<font color="green">==========================================</font><br>
BANNER_EOF

# Build DROPBEAR_EXTRA_ARGS -p flags from DROPBEAR_PORTS (excluding 22, jo default hai)
extra_args=""
for p in $DROPBEAR_PORTS; do
    [[ "$p" == "22" ]] && continue
    extra_args+=" -p ${p}"
done

cat << DB_CONF > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=22
DROPBEAR_EXTRA_ARGS="${extra_args} -b ${BANNER_FILE}"
DROPBEAR_BANNER="${BANNER_FILE}"
DROPBEAR_RECEIVE_WINDOW=65536
DB_CONF

sed -i 's/#Banner none/Banner \/etc\/issue.net/g' /etc/ssh/sshd_config 2>/dev/null || true
systemctl restart ssh 2>/dev/null || true

systemctl daemon-reload
systemctl enable dropbear
systemctl restart dropbear

echo -e "\n${GREEN}[DONE] Dropbear active on: ${DROPBEAR_PORTS}${NC}"
