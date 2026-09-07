#!/bin/bash
# RareTriccks VPN Panel - 06-xray-core.sh
# Xray-core install + VLESS config + user management.
# PATCHED for real-IP:
#   - ws-tls-in / ws-plain-in / xhttp-in / tcp-tls-in now have
#     streamSettings.sockopt.acceptProxyProtocol = true
#   - xhttp-in and tcp-tls-in now listen on 127.0.0.1 only (Nginx STREAM
#     fronts them publicly on the same port numbers - see 07-nginx-proxy.sh)
source /etc/raretriccks/00-common.sh

install_xray_core() {
    if ! command -v xray &>/dev/null; then
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    fi
    mkdir -p /usr/local/etc/xray
    fix_xray_service_user
    systemctl enable xray &>/dev/null
    if ! command -v xray &>/dev/null; then
        echo -e "${RED}[ERROR] Xray binary /usr/local/bin/xray nahi mila. Install script fail ho gaya.${NC}"
        return 1
    fi
    return 0
}

fix_xray_service_user() {
    if ! id "$XRAY_SVC_USER" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin "$XRAY_SVC_USER" 2>/dev/null
    fi

    local unit="/etc/systemd/system/xray.service"
    if [[ -f "$unit" ]]; then
        if grep -q '^User=' "$unit"; then
            sed -i "s/^User=.*/User=${XRAY_SVC_USER}/" "$unit"
        else
            sed -i "/\[Service\]/a User=${XRAY_SVC_USER}" "$unit"
        fi
        if grep -q '^Group=' "$unit"; then
            sed -i "s/^Group=.*/Group=${XRAY_SVC_USER}/" "$unit"
        else
            sed -i "/\[Service\]/a Group=${XRAY_SVC_USER}" "$unit"
        fi
        systemctl daemon-reload
    fi
}

configure_xray() {
    mkdir -p /usr/local/etc/xray
    fix_xray_service_user
    local MY_DOMAIN=$(get_domain)
    local HAVE_CERT=0
    if copy_xray_certs; then HAVE_CERT=1; fi
    local CERT_FILE="$XRAY_CERT_FILE"
    local KEY_FILE="$XRAY_KEY_FILE"

    mkdir -p /var/log/xray
    chown -R "${XRAY_SVC_USER}:${XRAY_SVC_USER}" /var/log/xray 2>/dev/null || chown -R nobody:nogroup /var/log/xray

cat << XR_EOF > "$XRAY_CONFIG"
{
  "log": { "loglevel": "warning", "access": "${XRAY_ACCESS_LOG}" },
  "api": { "tag": "api", "services": ["HandlerService", "StatsService", "LoggerService"] },
  "stats": {},
  "policy": {
    "levels": { "0": { "statsUserUplink": true, "statsUserDownlink": true } },
    "system": { "statsInboundUplink": true, "statsInboundDownlink": true }
  },
  "inbounds": [
    {
      "tag": "api-in",
      "listen": "127.0.0.1",
      "port": 10085,
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" }
    },
    {
      "tag": "ws-tls-in",
      "listen": "127.0.0.1",
      "port": ${XRAY_WS_TLS_PORT},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": { "network": "ws", "sockopt": { "acceptProxyProtocol": true }, "wsSettings": { "path": "${V2RAY_WS_PATH}" } }
    },
    {
      "tag": "ws-plain-in",
      "listen": "127.0.0.1",
      "port": ${XRAY_WS_PLAIN_PORT},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": { "network": "ws", "sockopt": { "acceptProxyProtocol": true }, "wsSettings": { "path": "${V2RAY_WS_PATH}" } }
    },
    {
      "tag": "xhttp-in",
      "listen": "127.0.0.1",
      "port": ${XRAY_XHTTP_PORT},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": { "network": "xhttp", "security": "none", "sockopt": { "acceptProxyProtocol": true }, "xhttpSettings": { "path": "${V2RAY_XHTTP_PATH}", "mode": "auto" } }
    },
    {
      "tag": "tcp-plain-in",
      "listen": "0.0.0.0",
      "port": ${XRAY_TCP_PLAIN_PORT},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": { "network": "tcp" }
    },
    {
      "tag": "tcp-tls-in",
      "listen": "127.0.0.1",
      "port": ${XRAY_TCP_TLS_PORT},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": { "network": "tcp", "security": "none", "sockopt": { "acceptProxyProtocol": true } }
    },
    {
      "tag": "grpc-in",
      "listen": "0.0.0.0",
      "port": ${XRAY_GRPC_PORT},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "${V2RAY_GRPC_SERVICE}" } }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" } ],
  "routing": {
    "rules": [
      { "type": "field", "inboundTag": ["api-in"], "outboundTag": "api" }
    ]
  }
}
XR_EOF
    chmod 644 "$XRAY_CONFIG"

    if [[ "$HAVE_CERT" -eq 1 && -f "$CERT_FILE" && -f "$KEY_FILE" ]]; then
        tmp=$(mktemp)
        jq --arg cert "$CERT_FILE" --arg key "$KEY_FILE" \
           '(.inbounds[] | select(.tag=="xhttp-in" or .tag=="tcp-tls-in") | .streamSettings) += { "security": "tls", "tlsSettings": { "certificates": [ { "certificateFile": $cert, "keyFile": $key } ] } }' \
           "$XRAY_CONFIG" > "$tmp"
        if [[ -s "$tmp" ]] && jq empty "$tmp" &>/dev/null; then
            mv "$tmp" "$XRAY_CONFIG"
        else
            rm -f "$tmp"
        fi
        chmod 644 "$XRAY_CONFIG"
    fi

    if ! xray run -test -config "$XRAY_CONFIG" &>/tmp/xray_check.log; then
        echo -e "${RED}[ERROR] Xray config invalid!${NC}"
        cat /tmp/xray_check.log
        return 1
    fi

    systemctl restart xray
    wait_for_port 127.0.0.1 "$XRAY_WS_TLS_PORT" "Xray ws-tls-in" 10
    wait_for_port 127.0.0.1 "$XRAY_WS_PLAIN_PORT" "Xray ws-plain-in" 10
}

v2ray_inject_client() {
    local uname="$1"
    local uuid="$2"
    local backup
    backup=$(mktemp)
    cp "$XRAY_CONFIG" "$backup"

    for tag in ws-tls-in ws-plain-in xhttp-in tcp-plain-in tcp-tls-in grpc-in; do
        tmp=$(mktemp)
        jq --arg tag "$tag" --arg id "$uuid" --arg email "$uname" \
           '(.inbounds[] | select(.tag==$tag) | .settings.clients) += [{"id": $id, "email": $email}]' \
           "$XRAY_CONFIG" > "$tmp"
        if [[ -s "$tmp" ]] && jq empty "$tmp" &>/dev/null; then
            mv "$tmp" "$XRAY_CONFIG"
        else
            rm -f "$tmp"
            cp "$backup" "$XRAY_CONFIG"
            rm -f "$backup"
            return 1
        fi
    done
    chmod 644 "$XRAY_CONFIG"

    if ! xray run -test -config "$XRAY_CONFIG" &>/tmp/xray_check.log; then
        cp "$backup" "$XRAY_CONFIG"
        rm -f "$backup"
        systemctl restart xray &>/dev/null
        return 1
    fi
    rm -f "$backup"

    timeout 15 systemctl restart xray
    return 0
}

v2ray_strip_client() {
    local uname="$1"
    local backup
    backup=$(mktemp)
    cp "$XRAY_CONFIG" "$backup"

    tmp=$(mktemp)
    jq --arg email "$uname" \
       '(.inbounds[].settings.clients) |= map(select(.email != $email))' \
       "$XRAY_CONFIG" > "$tmp"
    if [[ -s "$tmp" ]] && jq empty "$tmp" &>/dev/null; then
        mv "$tmp" "$XRAY_CONFIG"
    else
        rm -f "$tmp" "$backup"
        return 1
    fi
    chmod 644 "$XRAY_CONFIG"

    if ! xray run -test -config "$XRAY_CONFIG" &>/tmp/xray_check.log; then
        cp "$backup" "$XRAY_CONFIG"
        rm -f "$backup"
        systemctl restart xray &>/dev/null
        return 1
    fi
    rm -f "$backup"

    timeout 15 systemctl restart xray
}

v2ray_add_user() {
    local uname="$1"
    local uuid="$2"
    local ip_limit="${3:-0}"
    local gb_limit="${4:-Unlimited}"
    local exp_days="${5:-0}"
    [[ -z "$uuid" ]] && uuid=$(cat /proc/sys/kernel/random/uuid)

    if ! v2ray_inject_client "$uname" "$uuid"; then
        return 1
    fi

    mkdir -p "$V2USERS_DIR"
    local expire_date="Unlimited"
    if [[ "$exp_days" =~ ^[0-9]+$ && "$exp_days" -gt 0 ]]; then
        expire_date=$(date -d "+${exp_days} days" +"%Y-%m-%d")
    fi

cat << V2_EOF > "${V2USERS_DIR}/${uname}.conf"
USERNAME=$uname
UUID=$uuid
IP_LIMIT=$ip_limit
GB_LIMIT=$gb_limit
USED_MB=0.0
EXPIRE_DATE=$expire_date
LOCKED=0
V2_EOF

    echo "$uuid"
}

v2ray_delete_user() {
    local uname="$1"
    if v2ray_strip_client "$uname"; then
        rm -f "${V2USERS_DIR}/${uname}.conf"
        return 0
    fi
    return 1
}

v2ray_unlock_user() {
    local uname="$1"
    local conf="${V2USERS_DIR}/${uname}.conf"
    [[ -f "$conf" ]] || return 1
    local uuid
    uuid=$(grep '^UUID=' "$conf" | cut -d= -f2)
    [[ -z "$uuid" ]] && return 1

    v2ray_strip_client "$uname" &>/dev/null
    if v2ray_inject_client "$uname" "$uuid"; then
        sed -i 's/^LOCKED=.*/LOCKED=0/' "$conf"
        return 0
    fi
    return 1
}

v2ray_list_users() {
    jq -r '.inbounds[] | select(.tag=="ws-tls-in") | .settings.clients[]? | "\(.email)  ->  \(.id)"' "$XRAY_CONFIG" 2>/dev/null
    if [[ -d "$V2USERS_DIR" ]]; then
        echo -e "\n${CYAN}--- Limits / Quota (from conf) ---${NC}"
        for f in "${V2USERS_DIR}"/*.conf; do
            [[ -e "$f" ]] || continue
            local uname ip gb used exp locked
            uname=$(grep '^USERNAME=' "$f" | cut -d= -f2)
            ip=$(grep '^IP_LIMIT=' "$f" | cut -d= -f2)
            gb=$(grep '^GB_LIMIT=' "$f" | cut -d= -f2)
            used=$(grep '^USED_MB=' "$f" | cut -d= -f2)
            exp=$(grep '^EXPIRE_DATE=' "$f" | cut -d= -f2)
            locked=$(grep '^LOCKED=' "$f" | cut -d= -f2)
            echo -e " ${uname}: IP_LIMIT=${ip} GB_LIMIT=${gb} USED_MB=${used} EXPIRE=${exp} LOCKED=${locked}"
        done
    fi
}

v2ray_add_user_flow() {
    local MY_DOMAIN=$(get_domain)
    read -rp "Username/Remarks (e.g. test): " vu
    read -rp "Custom UUID (Leave blank for auto-generate): " custom_uuid
    read -rp "Expired Days (0 for unlimited): " vexp
    read -rp "IP Limit (0 for unlimited): " vip
    read -rp "GB Limit (e.g. 10 or Unlimited): " vgb
    [[ -z "$vu" ]] && { echo -e "${RED}Username khaali nahi ho saka${NC}"; press_any_key; return; }
    local gen_uuid
    gen_uuid=$(v2ray_add_user "$vu" "$custom_uuid" "$vip" "$vgb" "$vexp")
    if [[ -z "$gen_uuid" ]]; then
        echo -e "\n${RED}[FAILED] User add nahi ho saka.${NC}"
        press_any_key
        return
    fi
    echo -e "\n${GREEN}[SUCCESS] V2Ray User '${vu}' added successfully!${NC}"
    echo -e "${CYAN}UUID          : ${gen_uuid}${NC}"
    echo -e "${CYAN}IP Limit      : ${vip:-0}${NC}"
    echo -e "${CYAN}GB Limit      : ${vgb:-Unlimited}${NC}"
    echo -e "${CYAN}BadVPN UDPGW  : 127.0.0.1:${BADVPN_PORT} (Built-in active for Gaming & Calls)${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "${GREEN}Link WS TLS       :${NC} vless://${gen_uuid}@${MY_DOMAIN}:443?type=ws&encryption=none&security=tls&host=${MY_DOMAIN}&path=${V2RAY_WS_PATH}#XRAY_VLESS_WS_${vu}"
    echo -e "${GREEN}Link WS NoTLS     :${NC} vless://${gen_uuid}@${MY_DOMAIN}:80?type=ws&encryption=none&security=none&host=${MY_DOMAIN}&path=${V2RAY_WS_PATH}#XRAY_VLESS_WS_${vu}"
    echo -e "${GREEN}Link XHTTP (TLS)  :${NC} vless://${gen_uuid}@${MY_DOMAIN}:${XRAY_XHTTP_PORT}?type=xhttp&encryption=none&security=tls&host=${MY_DOMAIN}&path=${V2RAY_XHTTP_PATH}&mode=auto#XRAY_VLESS_XHTTP_${vu}"
    echo -e "${GREEN}Link TCP (Plain)  :${NC} vless://${gen_uuid}@${MY_DOMAIN}:${XRAY_TCP_PLAIN_PORT}?type=tcp&encryption=none&security=none#XRAY_VLESS_TCP_${vu}"
    echo -e "${GREEN}Link TCP (TLS)    :${NC} vless://${gen_uuid}@${MY_DOMAIN}:${XRAY_TCP_TLS_PORT}?type=tcp&encryption=none&security=tls&host=${MY_DOMAIN}#XRAY_VLESS_TCP_TLS_${vu}"
    echo -e "${GREEN}Link gRPC         :${NC} vless://${gen_uuid}@${MY_DOMAIN}:${XRAY_GRPC_PORT}?type=grpc&encryption=none&security=none&serviceName=${V2RAY_GRPC_SERVICE}#XRAY_VLESS_GRPC_${vu}"
    echo -e "${CYAN}====================================================${NC}"
    press_any_key
}

v2ray_delete_user_flow() {
    read -rp "Username/Remarks to delete: " vu
    if v2ray_delete_user "$vu"; then
        echo -e "${GREEN}[SUCCESS] User removed.${NC}"
    else
        echo -e "${RED}[FAILED] User remove nahi ho saka.${NC}"
    fi
    press_any_key
}

v2ray_menu() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}          V2RAY / XRAY MANAGEMENT                  ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " 1) Add V2Ray User (Auto UUID or Custom + BadVPN)"
    echo -e " 2) Delete V2Ray User"
    echo -e " 3) List V2Ray Users"
    echo -e " 4) Back"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Option [1-4]: " v_opt
    case $v_opt in
        1) v2ray_add_user_flow ;;
        2) v2ray_delete_user_flow ;;
        3)
            clear
            echo -e "${CYAN}--- Active V2Ray Users ---${NC}"
            v2ray_list_users
            press_any_key
            ;;
        4) return ;;
    esac
}

