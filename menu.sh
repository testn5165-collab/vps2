#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - menu.sh
# Master interactive menu: SSH management alag, V2Ray management alag.
# Usage: bash menu.sh   (run after install-all.sh has been executed once)
# ==============================================================================
source /etc/raretriccks/00-common.sh

# ---------------------------------------------------------------------------
# SSH HELPERS
# ---------------------------------------------------------------------------
ssh_add_user() {
    read -rp "Username: " uname
    read -rp "Password: " pass
    read -rp "Expiry (days): " days
    read -rp "IP Limit (0 = unlimited): " iplim
    read -rp "GB Limit (type 'Unlimited' or a number): " gblim

    [[ -z "$uname" || -z "$pass" ]] && { echo -e "${RED}Username/password khaali nahi ho sakte.${NC}"; return; }

    local exp_date
    exp_date=$(date -d "+${days} days" +%Y-%m-%d)
    useradd -M -s /bin/false -e "$exp_date" "$uname" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[ERROR] User create fail (pehle se maujood?)${NC}"
        return
    fi
    # NOTE: Ubuntu 24.04 default hash = yescrypt ($y$), jo Dropbear verify nahi kar pata.
    echo "${uname}:${pass}" | chpasswd -c SHA512
    mkdir -p "$USERS_DIR"
    cat << CONF_EOF > "${USERS_DIR}/${uname}.conf"
IP_LIMIT=${iplim}
GB_LIMIT=${gblim}
USED_MB=0.0
EXP_DATE=${exp_date}
CONF_EOF

    echo -e "${GREEN}[SUCCESS] SSH user '${uname}' created, expires ${exp_date}.${NC}"
    echo -e "${CYAN}Host: $(get_domain)${NC}"
    echo -e "${CYAN}TLS ports  : ${SSH_WS_TLS_PORTS[*]}${NC}"
    echo -e "${CYAN}Plain ports: ${SSH_WS_PLAIN_PORTS[*]}${NC}"
    echo -e "${CYAN}SSH Direct : 22   |  SSH+SSL raw: ${SSH_SSL_STUNNEL_PORT}${NC}"
}

ssh_delete_user() {
    read -rp "Username to delete: " uname
    userdel -f "$uname" 2>/dev/null
    rm -f "${USERS_DIR}/${uname}.conf"
    echo -e "${GREEN}[SUCCESS] SSH user '${uname}' removed (agar maujood tha).${NC}"
}

ssh_renew_user() {
    read -rp "Username to renew: " uname
    read -rp "Extra days: " days
    if ! id "$uname" &>/dev/null; then
        echo -e "${RED}[ERROR] User nahi mila.${NC}"; return
    fi
    local new_exp
    new_exp=$(date -d "+${days} days" +%Y-%m-%d)
    usermod -e "$new_exp" "$uname"
    passwd -u "$uname" &>/dev/null
    sed -i "s/^EXP_DATE=.*/EXP_DATE=${new_exp}/" "${USERS_DIR}/${uname}.conf" 2>/dev/null
    echo -e "${GREEN}[SUCCESS] '${uname}' renewed till ${new_exp}.${NC}"
}

ssh_list_users() {
    echo -e "${CYAN}--- SSH Users ---${NC}"
    if [[ ! -d "$USERS_DIR" ]]; then echo "Koi user nahi mila."; return; fi
    for f in "$USERS_DIR"/*.conf; do
        [[ -e "$f" ]] || continue
        local uname; uname=$(basename "$f" .conf)
        local status="Deleted"
        if id "$uname" &>/dev/null; then
            status=$(passwd -S "$uname" 2>/dev/null | grep -q " L " && echo "LOCKED" || echo "Active")
        fi
        local exp; exp=$(grep EXP_DATE "$f" | cut -d= -f2)
        echo -e "  ${uname}  |  Expiry: ${exp}  |  ${status}"
    done
}

ssh_online_sessions() {
    echo -e "${CYAN}--- Active SSH/WS sessions (approx) ---${NC}"
    ss -tnp 2>/dev/null | grep -E ":(22|109|8022|${SSH_SSL_STUNNEL_PORT})" | grep ESTAB
}

ssh_restart_services() {
    systemctl restart dropbear ws-proxy stunnel4 2>/dev/null
    echo -e "${GREEN}[SUCCESS] Dropbear, ws-proxy, stunnel4 restarted.${NC}"
}

ssh_set_banner() {
    read -rp "Banner text (single line): " btext
    echo "$btext" > "$BANNER_FILE"
    systemctl restart dropbear 2>/dev/null
    systemctl restart ssh 2>/dev/null
    echo -e "${GREEN}[SUCCESS] Banner updated.${NC}"
}

ssh_menu() {
    while true; do
        clear
        echo -e "${CYAN}====================================================${NC}"
        echo -e "${YELLOW}              SSH PROTOCOL MANAGEMENT              ${NC}"
        echo -e "${CYAN}====================================================${NC}"
        echo -e " 1) Add SSH User"
        echo -e " 2) Delete SSH User"
        echo -e " 3) Renew SSH User"
        echo -e " 4) List SSH Users"
        echo -e " 5) Check Online SSH Sessions"
        echo -e " 6) Restart SSH Services (Dropbear/WS/Stunnel)"
        echo -e " 7) Set/Edit SSH Banner"
        echo -e " 8) Back to Main Menu"
        echo -e "${CYAN}====================================================${NC}"
        read -rp "Option [1-8]: " o
        case $o in
            1) ssh_add_user ;;
            2) ssh_delete_user ;;
            3) ssh_renew_user ;;
            4) ssh_list_users ;;
            5) ssh_online_sessions ;;
            6) ssh_restart_services ;;
            7) ssh_set_banner ;;
            8) return ;;
            *) echo "Invalid option" ;;
        esac
        press_any_key
    done
}

# ---------------------------------------------------------------------------
# V2RAY HELPERS
# ---------------------------------------------------------------------------
v2ray_print_links() {
    local uname="$1" uuid="$2"
    local DOMAIN; DOMAIN=$(get_domain)
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "UUID : ${uuid}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "Link WS TLS      : vless://${uuid}@${DOMAIN}:443?type=ws&encryption=none&security=tls&host=${DOMAIN}&path=${V2RAY_WS_PATH}#XRAY_WS_${uname}"
    echo -e "Link WS NoTLS    : vless://${uuid}@${DOMAIN}:80?type=ws&encryption=none&security=none&host=${DOMAIN}&path=${V2RAY_WS_PATH}#XRAY_WS_${uname}"
    echo -e "Link XHTTP (TLS) : vless://${uuid}@${DOMAIN}:${XRAY_XHTTP_PORT}?type=xhttp&encryption=none&security=tls&host=${DOMAIN}&path=${V2RAY_XHTTP_PATH}&mode=auto#XRAY_XHTTP_${uname}"
    echo -e "Link TCP Plain   : vless://${uuid}@${DOMAIN}:${XRAY_TCP_PLAIN_PORT}?type=tcp&encryption=none&security=none#XRAY_TCP_${uname}"
    echo -e "Link TCP TLS     : vless://${uuid}@${DOMAIN}:${XRAY_TCP_TLS_PORT}?type=tcp&encryption=none&security=tls&host=${DOMAIN}#XRAY_TCP_TLS_${uname}"
    echo -e "Link gRPC        : vless://${uuid}@${DOMAIN}:${XRAY_GRPC_PORT}?type=grpc&encryption=none&security=none&serviceName=vless-grpc#XRAY_GRPC_${uname}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
}

v2ray_add_user() {
    read -rp "Username/email tag: " uname
    [[ -z "$uname" ]] && { echo -e "${RED}Khaali nahi chalega.${NC}"; return; }
    local uuid; uuid=$(uuidgen)
    for tag in ws-tls-in ws-plain-in xhttp-tls-in tcp-plain-in tcp-tls-in grpc-in; do
        tmp=$(mktemp)
        jq --arg tag "$tag" --arg id "$uuid" --arg email "$uname" \
           '(.inbounds[] | select(.tag==$tag) | .settings.clients) += [{"id": $id, "email": $email}]' \
           "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    done
    systemctl restart xray
    echo -e "${GREEN}[SUCCESS] V2Ray user '${uname}' added.${NC}"
    v2ray_print_links "$uname" "$uuid"
}

v2ray_delete_user() {
    read -rp "Username/email tag to delete: " uname
    tmp=$(mktemp)
    jq --arg email "$uname" \
       '(.inbounds[].settings.clients) |= map(select(.email != $email))' \
       "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    systemctl restart xray
    echo -e "${GREEN}[SUCCESS] '${uname}' removed (agar maujood tha).${NC}"
}

v2ray_list_users() {
    echo -e "${CYAN}--- V2Ray Users ---${NC}"
    jq -r '.inbounds[0].settings.clients[]? | "\(.email)  ->  \(.id)"' "$XRAY_CONFIG" 2>/dev/null
}

v2ray_show_links() {
    read -rp "Username/email tag: " uname
    local uuid
    uuid=$(jq -r --arg email "$uname" '.inbounds[0].settings.clients[]? | select(.email==$email) | .id' "$XRAY_CONFIG")
    if [[ -z "$uuid" ]]; then
        echo -e "${RED}[ERROR] User nahi mila.${NC}"; return
    fi
    v2ray_print_links "$uname" "$uuid"
}

v2ray_restart() {
    systemctl restart xray
    echo -e "${GREEN}[SUCCESS] Xray restarted.${NC}"
}

v2ray_change_paths() {
    read -rp "New WS path (current: ${V2RAY_WS_PATH}): " new_ws
    read -rp "New XHTTP path (current: ${V2RAY_XHTTP_PATH}): " new_xhttp
    [[ -n "$new_ws" ]] && sed -i "s#^V2RAY_WS_PATH=.*#V2RAY_WS_PATH=\"${new_ws}\"#" /etc/raretriccks/00-common.sh
    [[ -n "$new_xhttp" ]] && sed -i "s#^V2RAY_XHTTP_PATH=.*#V2RAY_XHTTP_PATH=\"${new_xhttp}\"#" /etc/raretriccks/00-common.sh
    echo -e "${YELLOW}[NOTE] Paths update ho gaye common config mein. Ab dobara chalao:${NC}"
    echo -e "${CYAN}  bash 07-xray-vless.sh   (Xray config me path rebuild - manual edit + restart)${NC}"
    echo -e "${CYAN}  bash 06-nginx-multiplexer.sh   (nginx conf me naya path)${NC}"
}

v2ray_menu() {
    while true; do
        clear
        echo -e "${CYAN}====================================================${NC}"
        echo -e "${YELLOW}             V2RAY (XRAY) MANAGEMENT               ${NC}"
        echo -e "${CYAN}====================================================${NC}"
        echo -e " 1) Add V2Ray User"
        echo -e " 2) Delete V2Ray User"
        echo -e " 3) List V2Ray Users"
        echo -e " 4) Show Connection Links (existing user)"
        echo -e " 5) Restart Xray"
        echo -e " 6) Change WS/XHTTP Path"
        echo -e " 7) Back to Main Menu"
        echo -e "${CYAN}====================================================${NC}"
        read -rp "Option [1-7]: " o
        case $o in
            1) v2ray_add_user ;;
            2) v2ray_delete_user ;;
            3) v2ray_list_users ;;
            4) v2ray_show_links ;;
            5) v2ray_restart ;;
            6) v2ray_change_paths ;;
            7) return ;;
            *) echo "Invalid option" ;;
        esac
        press_any_key
    done
}

# ---------------------------------------------------------------------------
# SYSTEM / STATUS
# ---------------------------------------------------------------------------
system_status() {
    clear
    local DOMAIN; DOMAIN=$(get_domain)
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}                 SYSTEM & PROTOCOL STATUS                           ${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    echo -e " Domain : ${DOMAIN}"
    for svc in nginx dropbear ws-proxy stunnel4 xray autokill badvpn-udpgw; do
        local st; st=$(systemctl is-active "$svc" 2>/dev/null)
        local badge="${RED}[ INACTIVE ]${NC}"
        [[ "$st" == "active" ]] && badge="${GREEN}[ ACTIVE ]${NC}"
        printf "   %-16s : %b\n" "$svc" "$badge"
    done
    echo -e "\n${CYAN}TLS ports   : ${SSH_WS_TLS_PORTS[*]}${NC}"
    echo -e "${CYAN}Plain ports : ${SSH_WS_PLAIN_PORTS[*]}${NC}"
}

combined_user_wizard() {
    read -rp "Username: " uname
    read -rp "Password: " pass
    read -rp "Expiry (days): " days
    read -rp "IP Limit (0 = unlimited): " iplim
    read -rp "GB Limit ('Unlimited' or number): " gblim
    bash /etc/raretriccks/09-user-manager.sh add "$uname" "$pass" "$days" "$iplim" "$gblim"
}

# ---------------------------------------------------------------------------
# MAIN MENU
# ---------------------------------------------------------------------------
while true; do
    clear
    CURRENT_DOM=$(get_domain)
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${GREEN}          ${PANEL_NAME}                            ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " Domain: ${YELLOW}${CURRENT_DOM}${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e " 1) SSH Management        (separate menu)"
    echo -e " 2) V2Ray Management      (separate menu)"
    echo -e " 3) Create Combined User (SSH + V2Ray together)"
    echo -e " 4) System & Protocol Status"
    echo -e " 5) Exit"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Select Option [1-5]: " opt
    case $opt in
        1) ssh_menu ;;
        2) v2ray_menu ;;
        3) combined_user_wizard; press_any_key ;;
        4) system_status; press_any_key ;;
        5) exit 0 ;;
        *) echo "Invalid option"; sleep 1 ;;
    esac
done
