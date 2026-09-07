#!/bin/bash
# RareTriccks VPN Panel - 13-uninstall.sh
# Full panel removal (services, users, configs, menu command).
source /etc/raretriccks/00-common.sh

uninstall_panel() {
    clear
    read -rp "Confirm karne ke liye 'YES' likhein: " confirm
    [[ "$confirm" != "YES" ]] && return

    systemctl stop ws-proxy autokill dropbear nginx xray badvpn slowdns v2ray-relay-tls v2ray-relay-plain 2>/dev/null
    systemctl disable ws-proxy autokill dropbear nginx xray badvpn slowdns v2ray-relay-tls v2ray-relay-plain 2>/dev/null
    rm -f /etc/systemd/system/ws-proxy.service /etc/systemd/system/autokill.service \
          /etc/systemd/system/badvpn.service /etc/systemd/system/slowdns.service \
          /etc/systemd/system/v2ray-relay-tls.service /etc/systemd/system/v2ray-relay-plain.service
    systemctl daemon-reload
    rm -f /usr/local/bin/ws-proxy.py /usr/local/bin/autokill.py /usr/local/bin/badvpn-udpgw \
          /usr/local/bin/dns-server /usr/local/bin/v2ray_realip_relay.py /usr/local/bin/realip_ssh_map.py
    rm -f "$NGINX_CONF" "$XRAY_CONFIG" "$NGINX_STREAM_CONF"
    rm -rf /etc/raretriccks /etc/slowdns /etc/xray
    echo -e "${GREEN}[SUCCESS] Uninstall complete.${NC}"
    echo -e "${YELLOW}[NOTE] Nginx.conf ke stream{} block ko manually check kar lena agar poori tarah saaf karna hai.${NC}"
    exit 0
}
