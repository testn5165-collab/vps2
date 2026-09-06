#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - 09-user-manager.sh
# Ek command se SSH account + V2Ray (UUID, sab inbounds) dono create,
# aur "Remarks" block print karta hai jaisa RareTriccks format mein chahiye.
# Usage: bash 09-user-manager.sh add <username> <password> <days> <ip_limit> <gb_limit>
#        bash 09-user-manager.sh del <username>
# ==============================================================================
set -e
source /etc/raretriccks/00-common.sh

DOMAIN=$(get_domain)

add_ssh_user() {
    local uname="$1" pass="$2" days="$3" ip_limit="$4" gb_limit="$5"
    local exp_date
    exp_date=$(date -d "+${days} days" +%Y-%m-%d)
    useradd -M -s /bin/false -e "$exp_date" "$uname"
    # NOTE: Ubuntu 24.04 default hash = yescrypt ($y$), jo Dropbear verify nahi kar pata.
    # Isliye SHA512 ($6$) crypt force kar rahe hain taaki Dropbear login kaam kare.
    echo "${uname}:${pass}" | chpasswd -c SHA512
    mkdir -p "$USERS_DIR"
    cat << CONF_EOF > "${USERS_DIR}/${uname}.conf"
IP_LIMIT=${ip_limit}
GB_LIMIT=${gb_limit}
USED_MB=0.0
EXP_DATE=${exp_date}
CONF_EOF
    echo "$exp_date"
}

del_ssh_user() {
    local uname="$1"
    userdel -f "$uname" 2>/dev/null || true
    rm -f "${USERS_DIR}/${uname}.conf"
}

add_v2ray_client() {
    local uname="$1" uuid="$2"
    for tag in ws-tls-in ws-plain-in xhttp-tls-in tcp-plain-in tcp-tls-in grpc-in; do
        tmp=$(mktemp)
        jq --arg tag "$tag" --arg id "$uuid" --arg email "$uname" \
           '(.inbounds[] | select(.tag==$tag) | .settings.clients) += [{"id": $id, "email": $email, "flow": ""}]' \
           "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    done
    systemctl restart xray
}

del_v2ray_client() {
    local uname="$1"
    tmp=$(mktemp)
    jq --arg email "$uname" \
       '(.inbounds[].settings.clients) |= map(select(.email != $email))' \
       "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    systemctl restart xray
}

print_remarks() {
    local uname="$1" uuid="$2" ip_limit="$3" gb_limit="$4" pass="$5" days="$6"
    local tls_list="${SSH_WS_TLS_PORTS[*]}"
    local plain_list="${SSH_WS_PLAIN_PORTS[*]}"

    echo -e "${CYAN}┌──────────────────────────────────────${NC}"
    echo -e "${CYAN}│${NC} Username    : ${uname}"
    echo -e "${CYAN}│${NC} Password    : ${pass}"
    echo -e "${CYAN}│${NC} Expires     : ${days} days"
    echo -e "${CYAN}└──────────────────────────────────────${NC}"
    echo -e "${YELLOW}▸ Server${NC}"
    echo -e "${CYAN}┌──────────────────────────────────────${NC}"
    echo -e "${CYAN}│${NC} Host        : ${DOMAIN}"
    echo -e "${CYAN}│${NC} Protocol    : SSH / SSH-WS / V2Ray"
    echo -e "${CYAN}│${NC} TLS ports   : ${tls_list// /, }"
    echo -e "${CYAN}│${NC} Plain ports : ${plain_list// /, }"
    echo -e "${CYAN}│${NC} SSH+SSL raw : ${SSH_SSL_STUNNEL_PORT}"
    echo -e "${CYAN}│${NC} SSH Direct  : 22"
    echo -e "${CYAN}└──────────────────────────────────────${NC}"
    echo -e "${YELLOW}▸ V2Ray (VLESS)${NC}"
    echo -e "${CYAN}┌──────────────────────────────────────${NC}"
    echo -e "${CYAN}│${NC} UUID         : ${uuid}"
    echo -e "${CYAN}│${NC} IP Limit     : ${ip_limit}"
    echo -e "${CYAN}│${NC} GB Limit     : ${gb_limit}"
    echo -e "${CYAN}│${NC} BadVPN UDPGW : ${UDPGW_BIND}:${UDPGW_PORT} (Gaming & Calls)"
    echo -e "${CYAN}└──────────────────────────────────────${NC}"
    echo -e "Link WS TLS (any TLS port)  : vless://${uuid}@${DOMAIN}:443?type=ws&encryption=none&security=tls&host=${DOMAIN}&path=${V2RAY_WS_PATH}#XRAY_VLESS_WS_${uname}"
    echo -e "Link WS NoTLS (any plain)   : vless://${uuid}@${DOMAIN}:80?type=ws&encryption=none&security=none&host=${DOMAIN}&path=${V2RAY_WS_PATH}#XRAY_VLESS_WS_${uname}"
    echo -e "Link XHTTP (TLS)            : vless://${uuid}@${DOMAIN}:${XRAY_XHTTP_PORT}?type=xhttp&encryption=none&security=tls&host=${DOMAIN}&path=${V2RAY_XHTTP_PATH}&mode=auto#XRAY_VLESS_XHTTP_${uname}"
    echo -e "Link TCP (Plain)            : vless://${uuid}@${DOMAIN}:${XRAY_TCP_PLAIN_PORT}?type=tcp&encryption=none&security=none#XRAY_VLESS_TCP_${uname}"
    echo -e "Link TCP (TLS)              : vless://${uuid}@${DOMAIN}:${XRAY_TCP_TLS_PORT}?type=tcp&encryption=none&security=tls&host=${DOMAIN}#XRAY_VLESS_TCP_TLS_${uname}"
    echo -e "Link gRPC                   : vless://${uuid}@${DOMAIN}:${XRAY_GRPC_PORT}?type=grpc&encryption=none&security=none&serviceName=vless-grpc#XRAY_VLESS_GRPC_${uname}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}[NOTE] SSH-WS/SSH-WS+SSL kaam karega upar diye HAR TLS/Plain port par (443, 2053, 2083... waghera) — same account.${NC}"
}

ACTION="$1"
case "$ACTION" in
    add)
        UNAME="$2"; PASS="$3"; DAYS="${4:-30}"; IPLIM="${5:-0}"; GBLIM="${6:-Unlimited}"
        [[ -z "$UNAME" || -z "$PASS" ]] && { echo "Usage: $0 add <user> <pass> <days> <ip_limit> <gb_limit>"; exit 1; }
        UUID=$(uuidgen)
        add_ssh_user "$UNAME" "$PASS" "$DAYS" "$IPLIM" "$GBLIM" >/dev/null
        add_v2ray_client "$UNAME" "$UUID"
        echo -e "${GREEN}[SUCCESS] User ${UNAME} created (SSH + V2Ray, expires in ${DAYS}d)${NC}"
        print_remarks "$UNAME" "$UUID" "$IPLIM" "$GBLIM" "$PASS" "$DAYS"
        ;;
    del)
        UNAME="$2"
        [[ -z "$UNAME" ]] && { echo "Usage: $0 del <user>"; exit 1; }
        del_ssh_user "$UNAME"
        del_v2ray_client "$UNAME"
        echo -e "${GREEN}[SUCCESS] User ${UNAME} deleted (SSH + V2Ray)${NC}"
        ;;
    *)
        echo "Usage: $0 add <user> <pass> <days> <ip_limit> <gb_limit>"
        echo "       $0 del <user>"
        exit 1
        ;;
esac
