#!/bin/bash
# RareTriccks VPN Panel - menu.sh
# Main interactive menu. Sources every module then runs the menu loop.
source /etc/raretriccks/00-common.sh
source /etc/raretriccks/01-dropbear.sh
source /etc/raretriccks/02-slowdns.sh
source /etc/raretriccks/03-badvpn.sh
source /etc/raretriccks/04-ws-proxy.sh
source /etc/raretriccks/05-realip-tracker.sh
source /etc/raretriccks/06-xray-core.sh
source /etc/raretriccks/07-nginx-proxy.sh
source /etc/raretriccks/08-monitoring.sh
source /etc/raretriccks/09-ssh-manager.sh
source /etc/raretriccks/10-ssl.sh
source /etc/raretriccks/11-status.sh
source /etc/raretriccks/12-user-management.sh
source /etc/raretriccks/13-uninstall.sh
source /etc/raretriccks/14-install-components.sh

while true; do
    clear
    CURRENT_DOM=$(get_domain)
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${GREEN}              ${PANEL_NAME}                       ${NC}"
    echo -e "${CYAN}              Build: ${PANEL_VERSION}${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " Domain Target: ${YELLOW}${CURRENT_DOM}${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e " 1) Auto Install System Components (BadVPN Built-in)"
    echo -e " 2) Add / Change Domain Name"
    echo -e " 3) Issue SSL Certificate (Let's Encrypt)"
    echo -e " 4) V2Ray / Xray Management (WS/XHTTP/TCP, Real-IP)"
    echo -e " 5) SSH / WS Account Management"
    echo -e " 6) SlowDNS Management (SSH over DNS)"
    echo -e " 7) User Management (Add/Delete/IPs/Quota/Expiry)"
    echo -e " 8) Check Status & Ports"
    echo -e " 9) Uninstall Panel"
    echo -e " 10) Exit Panel"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Select Option [1-10]: " opt

    case $opt in
        1) install_all_components ;;
        2) add_domain_option ;;
        3) setup_ssl ;;
        4) v2ray_menu ;;
        5) ssh_menu ;;
        6) slowdns_menu ;;
        7) user_management_menu ;;
        8) status_check ;;
        9) uninstall_panel ;;
        10) exit 0 ;;
    esac
done
