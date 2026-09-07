#!/bin/bash
# RareTriccks VPN Panel - 10-stunnel.sh
# SSH-over-SSL (stunnel) — wraps Dropbear traffic in a real TLS tunnel on
# its own port so it never collides with Nginx (80/443), OpenSSH (22),
# Dropbear (109/447) or any Xray port.
source /etc/raretriccks/00-common.sh

setup_stunnel() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}     SETUP SSH OVER SSL (STUNNEL)                  ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    local dom=$(get_domain)
    if [[ "$dom" == "No Domain Set" || -z "$dom" ]]; then
        echo -e "${RED}[ERROR] Pehle Domain set karein (Option 2)!${NC}"
        press_any_key
        return
    fi
    if [[ ! -f "/etc/letsencrypt/live/${dom}/fullchain.pem" ]]; then
        echo -e "${RED}[ERROR] SSL certificate nahi mila. Pehle 'Issue SSL Certificate' (Option 3) chalayein!${NC}"
        press_any_key
        return
    fi

    echo -e "${BLUE}[1/5] Installing stunnel4...${NC}"
    apt install -y stunnel4 >/dev/null 2>&1

    echo -e "${BLUE}[2/5] Preparing TLS cert bundle for stunnel...${NC}"
    mkdir -p /etc/stunnel
    cat "/etc/letsencrypt/live/${dom}/fullchain.pem" "/etc/letsencrypt/live/${dom}/privkey.pem" > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem

    echo -e "${BLUE}[3/5] Writing stunnel config (port ${STUNNEL_PORT} -> Dropbear ${STUNNEL_TARGET_PORT})...${NC}"
    cat << STUNNEL_EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel4.pid
cert = /etc/stunnel/stunnel.pem
client = no
socket = a:SO_REUSEADDR=1
socket = l:TCP_NODELAY=1

[ssh-ssl]
accept = ${STUNNEL_PORT}
connect = 127.0.0.1:${STUNNEL_TARGET_PORT}
STUNNEL_EOF

    if [[ -f /etc/default/stunnel4 ]]; then
        if grep -q "^ENABLED=" /etc/default/stunnel4; then
            sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4
        else
            echo "ENABLED=1" >> /etc/default/stunnel4
        fi
    else
        echo "ENABLED=1" > /etc/default/stunnel4
    fi

    echo -e "${BLUE}[4/5] Opening firewall port ${STUNNEL_PORT}...${NC}"
    if command -v ufw &>/dev/null; then
        ufw allow ${STUNNEL_PORT}/tcp >/dev/null 2>&1
    fi

    echo -e "${BLUE}[5/5] Starting stunnel4 service...${NC}"
    systemctl daemon-reload
    systemctl enable stunnel4 2>/dev/null
    systemctl restart stunnel4
    sleep 1

    if systemctl is-active --quiet stunnel4; then
        echo -e "\n${GREEN}[SUCCESS] SSH-over-SSL active!${NC}"
        echo -e "${CYAN}----------------------------------------------------${NC}"
        echo -e " Host          : ${dom}"
        echo -e " SSL/TLS Port  : ${STUNNEL_PORT}  (client connects here over TLS)"
        echo -e " Forwards to   : Dropbear 127.0.0.1:${STUNNEL_TARGET_PORT}"
        echo -e "${CYAN}----------------------------------------------------${NC}"
        echo -e " Client apps (HTTP Injector / NPV Tunnel / etc.) settings:"
        echo -e "   SSL/TLS   -> ON, Server = ${dom}, Port = ${STUNNEL_PORT}"
        echo -e "   SSH       -> Server = 127.0.0.1 (through the SSL tunnel), Port = ${STUNNEL_TARGET_PORT}"
        echo -e "${CYAN}----------------------------------------------------${NC}"
    else
        echo -e "\n${RED}[ERROR] Stunnel start nahi hua. Check: journalctl -u stunnel4 -n 50 --no-pager${NC}"
    fi
    press_any_key
}
