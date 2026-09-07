#!/bin/bash
# RareTriccks VPN Panel - 09-ssh-manager.sh
# SSH/WS account add/delete/list.
source /etc/raretriccks/00-common.sh

ssh_add_user_flow() {
    local MY_DOMAIN=$(get_domain)
    read -rp "Username: " su
    read -rp "Password: " sp
    read -rp "Expired Days: " sd
    read -rp "IP Limit (0 for unlimited): " sil
    read -rp "GB Limit (e.g. 10 or Unlimited): " sgb

    if id "$su" &>/dev/null; then
        echo -e "${RED}User pehle se mojood hai!${NC}"
        press_any_key
        return
    fi

    useradd -e "$(date -d "+$sd days" +"%Y-%m-%d")" -s /bin/bash -m "$su"
    echo -e "$sp\n$sp" | passwd "$su" &>/dev/null

    mkdir -p "$USERS_DIR"
cat << U_EOF > "${USERS_DIR}/${su}.conf"
USERNAME=$su
PASSWORD=$sp
IP_LIMIT=$sil
GB_LIMIT=$sgb
USED_MB=0.0
U_EOF

    echo -e "\n${GREEN}[SUCCESS] SSH WS Account Created Successfully!${NC}"
    echo -e "${CYAN}Username    : ${su}${NC}"
    echo -e "${CYAN}Password    : ${sp}${NC}"
    echo -e "${CYAN}Host/IP     : ${MY_DOMAIN}${NC}"
    echo -e "${CYAN}WS Port     : 80 / 443 (via Nginx -> 2082)${NC}"
    echo -e "${CYAN}BadVPN Port : 127.0.0.1:${BADVPN_PORT} (Active for Gaming & Calls)${NC}"
    if systemctl is-active slowdns &>/dev/null; then
        echo -e "${CYAN}SlowDNS     : Isi username/password se bhi login hoga (NS: $(get_ns_domain), Pubkey: SlowDNS Management > Show Info)${NC}"
    fi
    echo -e "${CYAN}====================================================${NC}"
    press_any_key
}

ssh_delete_user_flow() {
    read -rp "Username to delete: " su
    userdel -f "$su" &>/dev/null
    rm -f "${USERS_DIR}/${su}.conf"
    echo -e "${GREEN}[SUCCESS] SSH User removed.${NC}"
    press_any_key
}

ssh_list_users() {
    ls -l "${USERS_DIR}" 2>/dev/null | awk '{print $9}' | sed 's/\.conf//g'
}

ssh_menu() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}          SSH / DROPBEAR / WS MANAGEMENT           ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " 1) Add SSH / WS Account (Auth Fixed / Safe Shell)"
    echo -e " 2) Delete SSH Account"
    echo -e " 3) List SSH Accounts"
    echo -e " 4) Back"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Option [1-4]: " s_opt
    case $s_opt in
        1) ssh_add_user_flow ;;
        2) ssh_delete_user_flow ;;
        3)
            clear
            echo -e "${CYAN}--- Active SSH Users ---${NC}"
            ssh_list_users
            press_any_key
            ;;
        4) return ;;
    esac
}

