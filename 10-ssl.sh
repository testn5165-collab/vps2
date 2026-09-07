#!/bin/bash
# RareTriccks VPN Panel - 10-ssl.sh
# Lets Encrypt issuance + renewal hook (restarts Nginx, Xray, and the
# real-IP relay services so certs/config stay in sync).
source /etc/raretriccks/00-common.sh

setup_ssl() {
    clear
    local current_dom=$(get_domain)

    if [[ "$current_dom" == "No Domain Set" || -z "$current_dom" ]]; then
        echo -e "${RED}[ERROR] Pehle Option 2 se Domain Add karein!${NC}"
        press_any_key
        return
    fi

    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}  ${PANEL_NAME} - ISSUING SSL (${current_dom}) ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    rm -f "$WILDCARD_FILE"

    systemctl stop nginx 2>/dev/null
    certbot certonly --standalone --preferred-challenges http --agree-tos --register-unsafely-without-email -d "$current_dom"

    if [[ -f "/etc/letsencrypt/live/$current_dom/fullchain.pem" ]]; then
        echo -e "\n${GREEN}[SUCCESS] SSL Active for ${current_dom}!${NC}"
        install_renewal_hook
        configure_xray
        configure_nginx_proxy
        echo -e "${GREEN}[SUCCESS] Nginx reloaded with SSL cert!${NC}"
    else
        echo -e "${RED}[ERROR] SSL Fail ho gaya!${NC}"
    fi
    press_any_key
}

install_renewal_hook() {
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat << 'HOOK_EOF' > /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
#!/bin/bash
systemctl restart nginx
systemctl restart xray
systemctl restart v2ray-relay-tls 2>/dev/null
systemctl restart v2ray-relay-plain 2>/dev/null
HOOK_EOF
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/nginx-reload.sh
}

