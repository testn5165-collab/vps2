#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - 08-badvpn-udpgw.sh
# BadVPN UDP Gateway — localhost:7300, sab SSH/V2Ray clients isko use kar sakte
# hain UDP traffic (games, calls) ko fast forward karne ke liye.
# ==============================================================================
set -e
source /etc/raretriccks/00-common.sh

clear
echo -e "${CYAN}====================================================${NC}"
echo -e "${YELLOW}   ${PANEL_NAME} - BADVPN UDPGW SETUP                ${NC}"
echo -e "${CYAN}====================================================${NC}"

if [[ ! -f /usr/local/bin/badvpn-udpgw ]]; then
    echo -e "${BLUE}Downloading prebuilt badvpn-udpgw binary...${NC}"
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        curl -L -o /usr/local/bin/badvpn-udpgw \
            "https://github.com/daybreakersx/dockerscripts/raw/master/badvpn-udpgw64"
    else
        curl -L -o /usr/local/bin/badvpn-udpgw \
            "https://github.com/daybreakersx/dockerscripts/raw/master/badvpn-udpgw32"
    fi
    chmod +x /usr/local/bin/badvpn-udpgw
fi

cat << SVC_EOF > /etc/systemd/system/badvpn-udpgw.service
[Unit]
Description=RareTriccks BadVPN UDPGW (Gaming & Calls)
After=network.target

[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr ${UDPGW_BIND}:${UDPGW_PORT} --max-clients 500 --max-connections-for-client 20
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF

systemctl daemon-reload
systemctl enable badvpn-udpgw
systemctl restart badvpn-udpgw

echo -e "\n${GREEN}[DONE] BadVPN UDPGW active: ${UDPGW_BIND}:${UDPGW_PORT}${NC}"
echo -e "${YELLOW}[NOTE] Agar binary URL dead ho, source se build karo: git clone badvpn repo -> cmake -> make udpgw${NC}"
