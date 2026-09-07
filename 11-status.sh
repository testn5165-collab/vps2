#!/bin/bash
# RareTriccks VPN Panel - 11-status.sh
# Status dashboard + connected-IP viewer (real IPs, see 05-realip-tracker.sh).
source /etc/raretriccks/00-common.sh

status_check_inline() {
    local current_dom=$(get_domain)
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e " Domain        : ${current_dom}"
    echo -e " Nginx         : $(systemctl is-active nginx)"
    echo -e " Dropbear SSH  : $(systemctl is-active dropbear)"
    echo -e " WS Proxy      : $(systemctl is-active ws-proxy)"
    echo -e " BadVPN UDPGW  : $(systemctl is-active badvpn)"
    echo -e " Xray-core     : $(systemctl is-active xray)"
    echo -e " V2Ray Relay(443): $(systemctl is-active v2ray-relay-tls)"
    echo -e " V2Ray Relay(80) : $(systemctl is-active v2ray-relay-plain)"
    echo -e " SlowDNS       : $(systemctl is-active slowdns)"
    echo -e " Auto-Kill     : $(systemctl is-active autokill)"
    echo -e " Port 80       : $(ss -tln 2>/dev/null | grep -q ':80 ' && echo LISTENING || echo DOWN)"
    echo -e " Port 443      : $(ss -tln 2>/dev/null | grep -q ':443 ' && echo LISTENING || echo DOWN)"
    echo -e " UDPGW Port    : $(ss -tln 2>/dev/null | grep -q ':7300 ' && echo LISTENING || echo DOWN)"
    echo -e " SlowDNS Port  : $(ss -uln 2>/dev/null | grep -q ':53 ' && echo LISTENING || echo DOWN)"
    echo -e "${CYAN}----------------------------------------------------${NC}"
}

status_check() {
    clear
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}                     SYSTEM & PROTOCOL STATUS                       ${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    status_check_inline
    press_any_key
}

check_connected_ips_option() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}     CONNECTED IPs & ACTIVE ONLINE USERS           ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    show_ssh_realip_map
    echo ""
    echo -e "${BLUE}--- SSH / Dropbear Active Sessions (process list) ---${NC}"
    ps aux 2>/dev/null | grep '[d]ropbear'
    echo ""
    show_v2ray_realip_map
    echo -e "${CYAN}====================================================${NC}"
    press_any_key
}

check_status_quota_option() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}     USER STATUS, QUOTA & LIMITS                   ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${BLUE}--- SSH Users ---${NC}"
    if [[ -d "$USERS_DIR" ]]; then
        for f in "${USERS_DIR}"/*.conf; do
            [[ -e "$f" ]] || continue
            local uname ip gb used exp lockstat
            uname=$(grep '^USERNAME=' "$f" | cut -d= -f2)
            ip=$(grep '^IP_LIMIT=' "$f" | cut -d= -f2)
            gb=$(grep '^GB_LIMIT=' "$f" | cut -d= -f2)
            used=$(grep '^USED_MB=' "$f" | cut -d= -f2)
            exp=$(chage -l "$uname" 2>/dev/null | grep "Account expires" | awk -F': ' '{print $2}')
            lockstat=$(passwd -S "$uname" 2>/dev/null | awk '{print $2}')
            echo -e " ${uname}: IP_LIMIT=${ip} GB_LIMIT=${gb} USED_MB=${used} EXPIRES=${exp:-N/A} STATUS=${lockstat:-N/A}"
        done
    else
        echo " (koi SSH user nahi mila)"
    fi
    echo ""
    echo -e "${BLUE}--- V2Ray Users ---${NC}"
    v2ray_list_users
    echo -e "${CYAN}====================================================${NC}"
    press_any_key
}

