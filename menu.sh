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
    echo -e " 4) Manage Accounts (Add/Delete/Renew/Limits)"
    echo -e " 5) Check Status & Ports"
    echo -e " 6) Set / Edit SSH Banner"
    echo -e " 7) Fix SSH WS & WS+SSL Connection"
    echo -e " 8) Setup / Manage Telegram Bot"
    echo -e " 9) ${RED}Uninstall Panel (Remove All Components)${NC}"
    echo -e " 10) Exit Panel"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Select Option [1-10]: " opt

    case $opt in
        1) install_all_components ;;
        2) add_domain_option ;;
        3) setup_ssl ;;
        4) user_menu ;;
        5) status_check ;;
        6) set_banner ;;
        7) fix_websocket ;;
        8) setup_telegram_bot ;;
        9) uninstall_panel ;;
        10) exit 0 ;;
        *) echo "Invalid option"; sleep 1 ;;
    esac
done
