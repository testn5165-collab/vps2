#!/bin/bash
# RareTriccks VPN Panel - 06-status-banner.sh
# Service status view, SSH/WS banner editor, WebSocket "fix" repair action.
source /etc/raretriccks/00-common.sh
source /etc/raretriccks/01-nginx-domain.sh
source /etc/raretriccks/02-install-components.sh

status_check() {
    clear
    local current_dom=$(get_domain)
    local nginx_status=$(systemctl is-active nginx 2>/dev/null)
    local dropbear_status=$(systemctl is-active dropbear 2>/dev/null)
    local ws_status=$(systemctl is-active ws-proxy 2>/dev/null)
    local ak_status=$(systemctl is-active autokill 2>/dev/null)

    local ngx_badge="${RED}[ INACTIVE ]${NC}"
    local db_badge="${RED}[ INACTIVE ]${NC}"
    local ws_badge="${RED}[ INACTIVE ]${NC}"
    local ak_badge="${RED}[ INACTIVE ]${NC}"

    [[ "$nginx_status" == "active" ]] && ngx_badge="${GREEN}[ ACTIVE ]${NC}"
    [[ "$dropbear_status" == "active" ]] && db_badge="${GREEN}[ ACTIVE ]${NC}"
    [[ "$ws_status" == "active" ]] && ws_badge="${GREEN}[ ACTIVE ]${NC}"
    [[ "$ak_status" == "active" ]] && ak_badge="${GREEN}[ ACTIVE ]${NC}"

    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}                     SYSTEM & PROTOCOL STATUS                       ${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    echo -e " Target Domain : ${BOLD}${current_dom}${NC}"
    echo -e " Active Path   : ${BOLD}${CUSTOM_PATH}${NC}\n"

    echo -e "${CYAN} SERVICES STATUS${NC}"
    echo -e "${CYAN} ------------------------------------------------------------------${NC}"
    printf "   %-28s : %b\n" "Nginx SSL Proxy Engine" "$ngx_badge"
    printf "   %-28s : %b\n" "Dropbear SSH Core" "$db_badge"
    printf "   %-28s : %b\n" "Python WebSocket Service" "$ws_badge"
    printf "   %-28s : %b\n" "Auto-Lock & Bandwidth Daemon" "$ak_badge"
    echo ""

    echo -e "${CYAN}====================================================================${NC}"
    press_any_key
}

set_banner() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}       ${PANEL_NAME} - SET SSH / WS BANNER       ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "1) Write HTML / Custom Banner"
    echo -e "2) View Current Banner"
    echo -e "3) Reset/Clear Banner"
    echo -e "4) Back"
    read -rp "Option [1-4]: " b_opt

    case $b_opt in
        1)
            echo -e "${YELLOW}Text banner paste karke [ENTER] dabayein (Ending line par END likhein):${NC}"
            > $BANNER_FILE
            while IFS= read -r line; do
                [[ $line == "END" ]] && break
                echo "$line" >> $BANNER_FILE
            done
            systemctl restart dropbear
            systemctl restart ssh
            echo -e "${GREEN}[SUCCESS] Banner updated!${NC}"
            press_any_key
            ;;
        2)
            clear
            echo -e "${CYAN}--- Current SSH Banner ---${NC}"
            cat $BANNER_FILE
            press_any_key
            ;;
        3)
            echo "" > $BANNER_FILE
            systemctl restart dropbear
            systemctl restart ssh
            echo -e "${GREEN}Banner cleared!${NC}"
            press_any_key
            ;;
        *) return ;;
    esac
}

fix_websocket() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}       FIXING SSH WS & WS+SSL ENGINE               ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    fuser -k 109/tcp 2>/dev/null
    fix_dropbear_core
    systemctl restart ws-proxy
    install_python_tracker
    apply_nginx_config

    echo -e "\n${GREEN}[COMPLETED] WebSocket System & Bandwidth Engine Active!${NC}"
    press_any_key
}

