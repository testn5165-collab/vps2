#!/bin/bash
# RareTriccks VPN Panel - 08-uninstall.sh
# Full panel removal (services, users, configs, menu command).
source /etc/raretriccks/00-common.sh

uninstall_panel() {
    clear
    echo -e "${RED}${BOLD}====================================================================${NC}"
    echo -e "${RED}${BOLD}               UNINSTALL RARETRICCKS VPN PANEL                      ${NC}"
    echo -e "${RED}${BOLD}====================================================================${NC}"
    echo -e "${YELLOW}Yeh operation ye sab permanently remove kar dega:${NC}"
    echo -e "  - WebSocket Proxy & Auto-Kill systemd services"
    echo -e "  - Xray (V2Ray) engine, config aur saare V2Ray users"
    echo -e "  - Stunnel (SSH-over-SSL) config"
    echo -e "  - Telegram Bot service aur config"
    echo -e "  - Nginx VPN reverse-proxy config"
    echo -e "  - Saare panel-created SSH users aur unki config files"
    echo -e "  - Domain config aur SSH banner reset"
    echo -e "  - Menu command khud (/usr/local/bin/menu, /usr/bin/menu)"
    echo -e "${RED}Yeh action UNDO nahi ho sakta!${NC}\n"
    read -rp "Confirm karne ke liye 'YES' likhein (case-sensitive): " confirm

    if [[ "$confirm" != "YES" ]]; then
        echo -e "${YELLOW}Uninstall cancel kar diya gaya.${NC}"
        press_any_key
        return
    fi

    echo -e "\n${BLUE}[1/7] Stopping & disabling services...${NC}"
    systemctl stop ws-proxy 2>/dev/null
    systemctl stop autokill 2>/dev/null
    systemctl stop tgbot 2>/dev/null
    systemctl stop dropbear 2>/dev/null
    systemctl stop xray 2>/dev/null
    systemctl stop stunnel4 2>/dev/null
    systemctl disable ws-proxy 2>/dev/null
    systemctl disable autokill 2>/dev/null
    systemctl disable tgbot 2>/dev/null
    systemctl disable xray 2>/dev/null
    systemctl disable stunnel4 2>/dev/null

    echo -e "${BLUE}[2/7] Removing systemd service files...${NC}"
    rm -f /etc/systemd/system/ws-proxy.service
    rm -f /etc/systemd/system/autokill.service
    rm -f /etc/systemd/system/tgbot.service
    rm -f /etc/systemd/system/dropbear.service.d/override.conf
    rm -rf /etc/systemd/system/xray.service.d
    systemctl daemon-reload

    echo -e "${BLUE}[3/7] Removing panel scripts...${NC}"
    rm -f /usr/local/bin/ws-proxy.py
    rm -f /usr/local/bin/autokill.py
    rm -f /usr/local/bin/tgbot.py
    rm -rf /opt/rr-tgbot-venv

    echo -e "${BLUE}[4/7] Removing Nginx VPN config...${NC}"
    rm -f /etc/nginx/conf.d/vpn.conf
    systemctl restart nginx 2>/dev/null

    echo -e "${BLUE}[5/7] Removing Xray engine, config & stunnel...${NC}"
    bash -c "$(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove 2>/dev/null
    rm -rf "$XRAY_DIR" "$XRAY_LOG_DIR" "$XRAY_CERT_DIR"
    id -u "$XRAY_SYS_USER" &>/dev/null && userdel -f "$XRAY_SYS_USER" 2>/dev/null
    apt remove -y stunnel4 >/dev/null 2>&1
    rm -rf /etc/stunnel
    rm -f /etc/letsencrypt/renewal-hooks/deploy/raretriccks-sync.sh

    echo -e "${BLUE}[6/7] Removing all panel-created SSH users...${NC}"
    if [[ -d /etc/raretriccks/users ]]; then
        for conf in /etc/raretriccks/users/*.conf; do
            [[ -e "$conf" ]] || continue
            local uname=$(basename "$conf" .conf)
            userdel -f "$uname" 2>/dev/null
        done
    fi
    rm -rf /etc/raretriccks

    echo -e "${BLUE}[7/7] Removing menu command...${NC}"
    echo -e "${GREEN}[SUCCESS] Uninstall complete.${NC}"
    echo -e "${YELLOW}[NOTE] Nginx, Dropbear, Certbot packages khud remove nahi kiye gaye.${NC}"
    echo -e "${YELLOW}       Poori tarah hataane ke liye manually chalayein: apt remove --purge nginx dropbear certbot${NC}"
    echo -e "\n${YELLOW}Panel band ho raha hai...${NC}"
    sleep 2
    rm -f /usr/local/bin/menu /usr/bin/menu
    exit 0
}

