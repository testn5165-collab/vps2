#!/bin/bash
# RareTriccks VPN Panel - 14-install-components.sh
# Master "Auto Install" routine, sab modules ko sahi order mein call karta hai.
source /etc/raretriccks/00-common.sh

install_all_components() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}   ${PANEL_NAME} - SYSTEM INSTALLATION           ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    echo -e "${BLUE}[1/9] Updating Packages...${NC}"
    apt update -y && apt upgrade -y

    echo -e "${BLUE}[2/9] Installing Required Tools...${NC}"
    apt install -y curl wget unzip tar net-tools socat jq openssl nginx dropbear certbot \
        python3 python3-pip lsof iptables golang-go
    # Nginx stream module - some distros ship it separately from the main nginx package.
    apt install -y libnginx-mod-stream 2>/dev/null || true

    echo -e "${BLUE}[3/9] Configuring Dropbear SSH & Banner...${NC}"
cat << 'EOF' > $BANNER_FILE
<font color="green">==========================================</font><br>
<font color="yellow"><b>WELCOME TO RARETRICCKS VIP VPN</b></font><br>
<font color="red"><b>- NO TORRENT / NO MULTILOGIN</b></font><br>
<font color="green">==========================================</font><br>
EOF

    fix_dropbear_core
    sed -i 's/#Banner none/Banner \/etc\/issue.net/g' /etc/ssh/sshd_config
    systemctl restart ssh

    echo -e "${BLUE}[4/9] Installing BadVPN UDP Gateway (Gaming/Calls)...${NC}"
    install_badvpn_udpgw

    echo -e "${BLUE}[5/9] Creating Python SSH-WS Service (real-IP logging)...${NC}"
    install_ws_proxy

    echo -e "${BLUE}[6/9] Installing Xray-core & Nginx Reverse Proxy...${NC}"
    install_xray_core
    if command -v xray &>/dev/null; then
        configure_xray
        install_realip_tracker
        configure_nginx_proxy
    else
        echo -e "${RED}[ERROR] Xray-core install fail ho gaya, Nginx proxy skip kiya ja raha hai.${NC}"
    fi

    echo -e "${BLUE}[7/9] Installing Bandwidth Tracking Engine...${NC}"
    install_python_tracker

    echo -e "${BLUE}[8/9] SlowDNS (SSH over DNS)...${NC}"
    if [[ -n "$(get_ns_domain)" ]]; then
        install_slowdns_binary && slowdns_generate_keys && configure_slowdns_service
    else
        echo -e "${YELLOW}[SKIP] NS Domain abhi set nahi hai. Install ke baad 'SlowDNS Management' menu se NS Domain set karke install karein.${NC}"
    fi

    echo -e "${BLUE}[9/9] Finishing up...${NC}"
    echo -e "\n${GREEN}[SUCCESS] Base components, BadVPN, Xray, Nginx, Real-IP Tracker & SlowDNS setup complete!${NC}"
    status_check_inline
    press_any_key
}
