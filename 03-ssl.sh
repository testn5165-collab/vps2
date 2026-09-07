#!/bin/bash
# RareTriccks VPN Panel - 03-ssl.sh
# Let's Encrypt SSL issuance for the configured domain.
source /etc/raretriccks/00-common.sh
source /etc/raretriccks/01-nginx-domain.sh

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

    systemctl stop nginx

    certbot certonly --standalone --preferred-challenges http --agree-tos --register-unsafely-without-email -d "$current_dom"

    if [[ -f "/etc/letsencrypt/live/$current_dom/fullchain.pem" ]]; then
        echo -e "\n${GREEN}[SUCCESS] SSL Active for ${current_dom}!${NC}"
        apply_nginx_config
        install_cert_renew_hook
        sync_all_certs
        echo -e "${GREEN}[SUCCESS] Nginx SSL & WebSocket Proxy Configured!${NC}"
        echo -e "${GREEN}[SUCCESS] Xray & Stunnel certs synced (auto-sync on future renewals too)!${NC}"
    else
        echo -e "${RED}[ERROR] SSL Fail ho gaya! Domain A Record IP par pointed hai ya nahi check karein.${NC}"
    fi

    press_any_key
}

