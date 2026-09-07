#!/bin/bash
# RareTriccks VPN Panel - menu.sh
# Main interactive menu. Sources every module then runs the menu loop.
source /etc/raretriccks/00-common.sh
source /etc/raretriccks/01-nginx-domain.sh
source /etc/raretriccks/02-install-components.sh
source /etc/raretriccks/03-ssl.sh
source /etc/raretriccks/04-monitoring.sh
source /etc/raretriccks/05-user-manager.sh
source /etc/raretriccks/06-status-banner.sh
source /etc/raretriccks/07-telegram-bot.sh
source /etc/raretriccks/08-uninstall.sh
source /etc/raretriccks/09-xray.sh
source /etc/raretriccks/10-stunnel.sh

while true; do
    clear
    CURRENT_DOM=$(get_domain)
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${GREEN}              ${PANEL_NAME}                       ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " Domain Target: ${YELLOW}${CURRENT_DOM}${NC}"
    echo -e " Custom Path  : ${YELLOW}${CUSTOM_PATH}${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e " 1) Auto Install System Components"
    echo -e " 2) Add / Change Domain Name"
    echo -e " 3) Issue SSL Certificate"
    echo -e " 4) Manage SSH Accounts (Add/Delete/Renew/Limits)"
    echo -e " 5) Install / Manage V2Ray (Xray Multi-Protocol)"
    echo -e " 6) Setup SSH-over-SSL (Stunnel)"
    echo -e " 7) Check Status & Ports"
    echo -e " 8) Set / Edit SSH Banner"
    echo -e " 9) Fix SSH WS & WS+SSL Connection"
    echo -e " 10) Setup / Manage Telegram Bot"
    echo -e " 11) ${RED}Uninstall Panel (Remove All Components)${NC}"
    echo -e " 12) Exit Panel"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Select Option [1-12]: " opt

    case $opt in
        1) install_all_components ;;
        2) add_domain_option ;;
        3) setup_ssl ;;
        4) user_menu ;;
        5) v2ray_menu ;;
        6) setup_stunnel ;;
        7) status_check ;;
        8) set_banner ;;
        9) fix_websocket ;;
        10) setup_telegram_bot ;;
        11) uninstall_panel ;;
        12) exit 0 ;;
        *) echo "Invalid option"; sleep 1 ;;
    esac
done
