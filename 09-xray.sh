#!/bin/bash
# RareTriccks VPN Panel - 09-xray.sh
# Xray-core install + VLESS multi-protocol inbound manager
# (WS via Nginx, XHTTP, TCP, TCP+TLS, gRPC) — runs alongside SSH/SSH-WS
# without port clashes.
source /etc/raretriccks/00-common.sh
source /etc/raretriccks/01-nginx-domain.sh

build_xray_base_config() {
    mkdir -p "$XRAY_DIR" "$XRAY_LOG_DIR"

    cat << JSON_EOF > "$XRAY_CONFIG"
{
  "log": {
    "loglevel": "warning",
    "access": "${XRAY_LOG_DIR}/access.log",
    "error": "${XRAY_LOG_DIR}/error.log"
  },
  "inbounds": [
    {
      "tag": "vless-ws",
      "listen": "127.0.0.1",
      "port": ${PORT_WS_INTERNAL},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "${V2RAY_WS_PATH}" }
      }
    },
    {
      "tag": "vless-xhttp",
      "listen": "0.0.0.0",
      "port": ${PORT_XHTTP_TLS},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${XRAY_CERT_DIR}/fullchain.pem",
              "keyFile": "${XRAY_CERT_DIR}/privkey.pem"
            }
          ]
        },
        "xhttpSettings": { "path": "/vless-xhttp", "mode": "auto" }
      }
    },
    {
      "tag": "vless-tcp",
      "listen": "0.0.0.0",
      "port": ${PORT_TCP_PLAIN},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": { "network": "tcp", "security": "none" }
    },
    {
      "tag": "vless-tcp-tls",
      "listen": "0.0.0.0",
      "port": ${PORT_TCP_TLS},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${XRAY_CERT_DIR}/fullchain.pem",
              "keyFile": "${XRAY_CERT_DIR}/privkey.pem"
            }
          ]
        }
      }
    },
    {
      "tag": "vless-grpc",
      "listen": "0.0.0.0",
      "port": ${PORT_GRPC},
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": { "serviceName": "vless-grpc" }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" }
  ]
}
JSON_EOF
}

install_xray() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}   INSTALLING XRAY-CORE (V2RAY MULTI-PROTOCOL)     ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    local dom=$(get_domain)
    if [[ "$dom" == "No Domain Set" || -z "$dom" ]]; then
        echo -e "${RED}[ERROR] Pehle Domain set karein (Option 2)!${NC}"
        press_any_key
        return
    fi
    if [[ ! -f "/etc/letsencrypt/live/${dom}/fullchain.pem" ]]; then
        echo -e "${RED}[ERROR] SSL certificate nahi mila. Pehle 'Issue SSL Certificate' (Option 3) chalayein!${NC}"
        press_any_key
        return
    fi

    echo -e "${BLUE}[1/7] Installing Xray-core (official installer)...${NC}"
    bash -c "$(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    if ! command -v xray &>/dev/null; then
        echo -e "${RED}[ERROR] Xray-core install fail ho gaya. Internet/curl check karein.${NC}"
        press_any_key
        return
    fi

    echo -e "${BLUE}[2/7] Creating dedicated system user for Xray (permission fix)...${NC}"
    id -u "$XRAY_SYS_USER" &>/dev/null || useradd -r -s /usr/sbin/nologin "$XRAY_SYS_USER"

    echo -e "${BLUE}[3/7] Syncing SSL certificate copy for Xray...${NC}"
    sync_all_certs
    install_cert_renew_hook

    echo -e "${BLUE}[4/7] Writing Xray multi-protocol config (WS/XHTTP/TCP/TCP-TLS/gRPC)...${NC}"
    if [[ -f "$XRAY_CONFIG" ]]; then
        cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$(date +%s)" 2>/dev/null
    fi
    build_xray_base_config

    echo -e "${BLUE}[5/7] Fixing ownership & systemd override...${NC}"
    mkdir -p "$XRAY_LOG_DIR"
    chown -R "${XRAY_SYS_USER}:${XRAY_SYS_USER}" "$XRAY_DIR" "$XRAY_LOG_DIR" "$XRAY_CERT_DIR" 2>/dev/null

    mkdir -p /etc/systemd/system/xray.service.d
    cat << OVR_EOF > /etc/systemd/system/xray.service.d/override.conf
[Service]
User=${XRAY_SYS_USER}
Group=${XRAY_SYS_USER}
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=false
OVR_EOF

    echo -e "${BLUE}[6/7] Updating Nginx (adds ${V2RAY_WS_PATH} WebSocket route) & opening firewall ports...${NC}"
    apply_nginx_config

    if command -v ufw &>/dev/null; then
        ufw allow ${PORT_XHTTP_TLS}/tcp >/dev/null 2>&1
        ufw allow ${PORT_TCP_PLAIN}/tcp >/dev/null 2>&1
        ufw allow ${PORT_TCP_TLS}/tcp >/dev/null 2>&1
        ufw allow ${PORT_GRPC}/tcp >/dev/null 2>&1
    fi

    echo -e "${BLUE}[7/7] Starting Xray service...${NC}"
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray
    sleep 1

    if systemctl is-active --quiet xray; then
        echo -e "\n${GREEN}[SUCCESS] Xray V2Ray Engine Installed & Running!${NC}"
        echo -e "${CYAN}Ports -> WS(via Nginx): 80/443${V2RAY_WS_PATH} | XHTTP-TLS: ${PORT_XHTTP_TLS} | TCP: ${PORT_TCP_PLAIN} | TCP-TLS: ${PORT_TCP_TLS} | gRPC: ${PORT_GRPC}${NC}"
    else
        echo -e "\n${RED}[ERROR] Xray start nahi hua. Check: journalctl -u xray -n 50 --no-pager${NC}"
    fi
    press_any_key
}

reload_xray() {
    systemctl restart xray 2>/dev/null
}

add_v2ray_user() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}          ADD NEW V2RAY (XRAY) USER                ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    if [[ ! -f "$XRAY_CONFIG" ]]; then
        echo -e "${RED}[ERROR] Xray abhi install nahi hai. Pehle 'Install / Reinstall Xray Engine' chalayein!${NC}"
        press_any_key
        return
    fi
    if ! systemctl is-active --quiet xray; then
        echo -e "${YELLOW}[WARN] Xray service active nahi hai, restart kar rahe hain...${NC}"
        systemctl restart xray
    fi

    local dom=$(get_domain)
    read -rp "Username/email tag: " uname
    if [[ -z "$uname" ]]; then
        echo -e "${RED}[ERROR] Naam khaali nahi ho sakta!${NC}"
        press_any_key
        return
    fi
    if [[ -f "${XRAY_USERS_DIR}/${uname}.uuid" ]]; then
        echo -e "${RED}[ERROR] Yeh username pehle se maujood hai!${NC}"
        press_any_key
        return
    fi

    local uuid=$(cat /proc/sys/kernel/random/uuid)

    python3 - "$XRAY_CONFIG" "$uuid" "$uname" << 'PYEOF'
import json, sys
config_path, uuid, uname = sys.argv[1], sys.argv[2], sys.argv[3]
with open(config_path) as f:
    conf = json.load(f)
tag_map = {
    "vless-ws": f"WS_{uname}",
    "vless-xhttp": f"XHTTP_{uname}",
    "vless-tcp": f"TCP_{uname}",
    "vless-tcp-tls": f"TCP_TLS_{uname}",
    "vless-grpc": f"GRPC_{uname}",
}
for inbound in conf.get("inbounds", []):
    tag = inbound.get("tag")
    if tag in tag_map:
        inbound["settings"]["clients"].append({"id": uuid, "email": tag_map[tag]})
with open(config_path, "w") as f:
    json.dump(conf, f, indent=2)
PYEOF

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[ERROR] Config update fail ho gaya (JSON error). User add nahi hua.${NC}"
        press_any_key
        return
    fi

    reload_xray
    sleep 1
    if ! systemctl is-active --quiet xray; then
        echo -e "${RED}[ERROR] Xray restart ke baad crash ho gaya! Check: journalctl -u xray -n 50 --no-pager${NC}"
        press_any_key
        return
    fi

    mkdir -p "$XRAY_USERS_DIR"
    echo "$uuid" > "${XRAY_USERS_DIR}/${uname}.uuid"

    echo -e "\n${GREEN}[SUCCESS] V2Ray user '${uname}' added.${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "UUID : ${uuid}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "Link WS TLS      : vless://${uuid}@${dom}:443?type=ws&encryption=none&security=tls&host=${dom}&path=${V2RAY_WS_PATH}#XRAY_WS_${uname}"
    echo ""
    echo -e "Link WS NoTLS    : vless://${uuid}@${dom}:80?type=ws&encryption=none&security=none&host=${dom}&path=${V2RAY_WS_PATH}#XRAY_WS_${uname}"
    echo ""
    echo -e "Link XHTTP (TLS) : vless://${uuid}@${dom}:${PORT_XHTTP_TLS}?type=xhttp&encryption=none&security=tls&host=${dom}&path=/vless-xhttp&mode=auto#XRAY_XHTTP_${uname}"
    echo ""
    echo -e "Link TCP Plain   : vless://${uuid}@${dom}:${PORT_TCP_PLAIN}?type=tcp&encryption=none&security=none#XRAY_TCP_${uname}"
    echo ""
    echo -e "Link TCP TLS     : vless://${uuid}@${dom}:${PORT_TCP_TLS}?type=tcp&encryption=none&security=tls&host=${dom}#XRAY_TCP_TLS_${uname}"
    echo ""
    echo -e "Link gRPC        : vless://${uuid}@${dom}:${PORT_GRPC}?type=grpc&encryption=none&security=none&serviceName=vless-grpc#XRAY_GRPC_${uname}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    press_any_key
}

delete_v2ray_user() {
    clear
    echo -e "${CYAN}--- Existing V2Ray Users ---${NC}"
    mkdir -p "$XRAY_USERS_DIR"
    local found=0
    for f in "$XRAY_USERS_DIR"/*.uuid; do
        [[ -e "$f" ]] || continue
        echo "  - $(basename "$f" .uuid)"
        found=1
    done
    [[ $found -eq 0 ]] && echo -e "${YELLOW}  Koi V2Ray user nahi mila.${NC}"
    echo -e "${CYAN}----------------------${NC}"
    read -rp "Username to delete: " uname

    if [[ -z "$uname" || ! -f "$XRAY_CONFIG" ]]; then
        echo -e "${RED}[ERROR] Invalid!${NC}"
        press_any_key
        return
    fi

    python3 - "$XRAY_CONFIG" "$uname" << 'PYEOF'
import json, sys
config_path, uname = sys.argv[1], sys.argv[2]
with open(config_path) as f:
    conf = json.load(f)
for inbound in conf.get("inbounds", []):
    clients = inbound.get("settings", {}).get("clients")
    if clients:
        inbound["settings"]["clients"] = [
            c for c in clients if not c.get("email", "").endswith(f"_{uname}")
        ]
with open(config_path, "w") as f:
    json.dump(conf, f, indent=2)
PYEOF

    rm -f "${XRAY_USERS_DIR}/${uname}.uuid"
    reload_xray
    echo -e "${GREEN}V2Ray user ${uname} deleted successfully!${NC}"
    press_any_key
}

v2ray_menu() {
    while true; do
        clear
        echo -e "${CYAN}====================================================${NC}"
        echo -e "${YELLOW}     ${PANEL_NAME} - V2RAY / XRAY MANAGEMENT      ${NC}"
        echo -e "${CYAN}====================================================${NC}"
        echo -e " 1) Install / Reinstall Xray Engine"
        echo -e " 2) Add New V2Ray User"
        echo -e " 3) Delete V2Ray User"
        echo -e " 4) Restart Xray Service"
        echo -e " 5) Back to Main Menu"
        echo -e "${CYAN}====================================================${NC}"
        read -rp "Option [1-5]: " v_choice
        case $v_choice in
            1) install_xray ;;
            2) add_v2ray_user ;;
            3) delete_v2ray_user ;;
            4)
                reload_xray
                sleep 1
                if systemctl is-active --quiet xray; then
                    echo -e "${GREEN}Xray restarted successfully.${NC}"
                else
                    echo -e "${RED}Xray restart fail ho gaya, logs check karein.${NC}"
                fi
                sleep 1
                ;;
            5) return ;;
            *) echo "Invalid Option"; sleep 1 ;;
        esac
    done
}
