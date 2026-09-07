#!/bin/bash
# RareTriccks VPN Panel - 02-slowdns.sh
# SlowDNS (SSH over DNS) install + management menu.
source /etc/raretriccks/00-common.sh

get_ns_domain() {
    if [[ -s "$SLOWDNS_NS_FILE" ]]; then
        cat "$SLOWDNS_NS_FILE" | tr -d '\r\n'
    else
        echo ""
    fi
}

free_port_53() {
    if ss -uln 2>/dev/null | grep -q ':53 '; then
        if systemctl is-active systemd-resolved &>/dev/null; then
            mkdir -p /etc/systemd/resolved.conf.d
            if grep -q '^DNSStubListener=' /etc/systemd/resolved.conf 2>/dev/null; then
                sed -i 's/^DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
            else
                echo 'DNSStubListener=no' >> /etc/systemd/resolved.conf
            fi
            systemctl restart systemd-resolved 2>/dev/null
            sleep 1
            rm -f /etc/resolv.conf
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
            echo "nameserver 1.1.1.1" >> /etc/resolv.conf
        fi
    fi

    for svc in named bind9 dnsmasq; do
        systemctl is-active "$svc" &>/dev/null && systemctl stop "$svc" 2>/dev/null && systemctl disable "$svc" 2>/dev/null
    done
}

install_slowdns_binary() {
    [[ -x "$SLOWDNS_BIN" ]] && return 0

    echo -e "${BLUE}[+] Installing SlowDNS (dnstt-server) binary...${NC}"
    apt install -y golang-go git build-essential &>/dev/null

    # NEW: the old sh4hin/eightbitlabs GitHub forks are gone/private, which
    # made "git clone" fall back to an interactive username/password prompt
    # and hang the whole install. GIT_TERMINAL_PROMPT=0 kills that prompt
    # for good (any future broken/private URL just fails fast instead of
    # hanging), and we clone the real, currently-maintained upstream
    # project instead -- bamsoftware's own git host, not GitHub, so no
    # GitHub auth is ever involved.
    export GIT_TERMINAL_PROMPT=0

    rm -rf /tmp/dnstt-src
    # NOTE: no --depth here -- bamsoftware's git server uses the "dumb"
    # HTTP transport, which rejects shallow-clone requests outright.
    if ! git clone https://www.bamsoftware.com/git/dnstt.git /tmp/dnstt-src &>/tmp/slowdns_clone.log; then
        echo -e "${RED}[ERROR] dnstt source clone fail ho gaya. /tmp/slowdns_clone.log check karein.${NC}"
        cat /tmp/slowdns_clone.log
        return 1
    fi

    (
        cd /tmp/dnstt-src/dnstt-server || exit 1
        go build -o "$SLOWDNS_BIN" . 2>/tmp/slowdns_build.log
    )

    if [[ ! -x "$SLOWDNS_BIN" ]]; then
        echo -e "${RED}[ERROR] SlowDNS (dnstt-server) binary build nahi ho saka. /tmp/slowdns_build.log check karein.${NC}"
        cat /tmp/slowdns_build.log 2>/dev/null
        return 1
    fi
    chmod +x "$SLOWDNS_BIN"
    return 0
}

slowdns_generate_keys() {
    mkdir -p "$SLOWDNS_DIR"
    if [[ ! -f "$SLOWDNS_PRIVKEY" || ! -f "$SLOWDNS_PUBKEY" ]]; then
        "$SLOWDNS_BIN" -gen-key -privkey-file "$SLOWDNS_PRIVKEY" -pubkey-file "$SLOWDNS_PUBKEY" &>/tmp/slowdns_keygen.log
    fi
    if [[ ! -f "$SLOWDNS_PRIVKEY" || ! -f "$SLOWDNS_PUBKEY" ]]; then
        echo -e "${RED}[ERROR] SlowDNS keypair generate nahi ho saka.${NC}"
        cat /tmp/slowdns_keygen.log 2>/dev/null
        return 1
    fi
    chmod 600 "$SLOWDNS_PRIVKEY"
    chmod 644 "$SLOWDNS_PUBKEY"
    return 0
}

configure_slowdns_service() {
    local ns_dom
    ns_dom=$(get_ns_domain)
    if [[ -z "$ns_dom" ]]; then
        echo -e "${RED}[ERROR] NS Domain set nahi hai. Pehle SlowDNS menu se 'Set / Change NS Domain' use karein.${NC}"
        return 1
    fi

    free_port_53

cat << SD_EOF > /etc/systemd/system/slowdns.service
[Unit]
Description=SlowDNS (SSH over DNS) Tunnel Server
After=network.target dropbear.service

[Service]
ExecStart=${SLOWDNS_BIN} -udp :${SLOWDNS_UDP_PORT} -privkey-file ${SLOWDNS_PRIVKEY} ${ns_dom} ${SLOWDNS_FORWARD_HOST}:${SLOWDNS_FORWARD_PORT}
Restart=always
RestartSec=3
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
SD_EOF

    systemctl daemon-reload
    systemctl enable slowdns &>/dev/null
    systemctl restart slowdns

    sleep 2
    if ss -uln 2>/dev/null | grep -q ":${SLOWDNS_UDP_PORT} "; then
        echo -e "${GREEN}[OK] SlowDNS UDP/${SLOWDNS_UDP_PORT} par listening hai.${NC}"
    else
        echo -e "${RED}[WARN] SlowDNS port ${SLOWDNS_UDP_PORT} par listen nahi kar raha. 'journalctl -u slowdns -n 50' check karein.${NC}"
    fi
}

install_slowdns() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}          SLOWDNS INSTALL / CONFIGURE              ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    if [[ -z "$(get_ns_domain)" ]]; then
        echo -e "${YELLOW}[INFO] NS Domain abhi set nahi hai, pehle wahi set karte hain.${NC}"
        slowdns_set_ns_domain_flow
    fi

    if ! install_slowdns_binary; then
        press_any_key
        return 1
    fi

    if ! slowdns_generate_keys; then
        press_any_key
        return 1
    fi

    configure_slowdns_service
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "${GREEN}[SUCCESS] SlowDNS install/configure complete.${NC}"
    echo -e "${YELLOW}[REMEMBER] SlowDNS wahi SSH/WS accounts (SSH Management se bane) use karta hai -${NC}"
    echo -e "${YELLOW}           unhi ka GB/IP limit yahan bhi automatically apply hota hai.${NC}"
    press_any_key
}

slowdns_set_ns_domain_flow() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}          SET / CHANGE NS DOMAIN                   ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}[IMPORTANT] Yeh koi normal domain nahi hai - yeh ek NS (Nameserver) record hai.${NC}"
    echo -e " Apne domain registrar/DNS panel me:"
    echo -e "   1) Ek subdomain banayen, e.g. ${CYAN}ns.yourdomain.com${NC}"
    echo -e "   2) Uske liye ek ${CYAN}NS record${NC} add karein jiski value ho: ${CYAN}dns.yourdomain.com${NC} (ya isi tarah ka glue domain)"
    echo -e "   3) Us glue domain (${CYAN}dns.yourdomain.com${NC}) ke liye ek ${CYAN}A record${NC} add karein jo is server ki Public IP par point kare"
    echo -e " Iske bina SlowDNS kabhi resolve nahi hoga, chahe service chal bhi rahi ho."
    echo -e "${CYAN}----------------------------------------------------${NC}"
    read -rp "NS Subdomain enter karein (e.g. ns.yourdomain.com): " ns_input
    if [[ -z "$ns_input" ]]; then
        echo -e "${RED}[ERROR] NS domain khaali nahi ho sakta.${NC}"
    else
        mkdir -p "$SLOWDNS_DIR"
        echo "$ns_input" > "$SLOWDNS_NS_FILE"
        echo -e "${GREEN}[SUCCESS] NS Domain set to: ${CYAN}${ns_input}${NC}"
        if [[ -f "$SLOWDNS_PRIVKEY" ]]; then
            configure_slowdns_service
        fi
    fi
    press_any_key
}

slowdns_show_info() {
    clear
    local ns_dom pubkey pubip
    ns_dom=$(get_ns_domain)
    pubkey=$(cat "$SLOWDNS_PUBKEY" 2>/dev/null)
    pubip=$(curl -s ifconfig.me 2>/dev/null)
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}          SLOWDNS CONNECTION INFO                  ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " Service Status : $(systemctl is-active slowdns 2>/dev/null)"
    echo -e " NS Domain      : ${ns_dom:-Not Set}"
    echo -e " Server Public IP: ${pubip:-Unknown}"
    echo -e " Public Key     : ${pubkey:-Not Generated}"
    echo -e " UDP Port       : ${SLOWDNS_UDP_PORT}"
    echo -e " Forwards To    : ${SLOWDNS_FORWARD_HOST}:${SLOWDNS_FORWARD_PORT} (Dropbear SSH)"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "${YELLOW}Client apps (HTTP Injector / NapsternetV / etc.) me daalna hai:${NC}"
    echo -e "  DNS Server / NS         : ${ns_dom:-<ns domain not set>}"
    echo -e "  Public Key              : ${pubkey:-<not generated>}"
    echo -e "  SSH Username/Password   : koi bhi SSH/WS account (SSH Management se bana hua)"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}[NOTE] GB/IP limits SlowDNS users ke liye alag se track nahi hote - ${NC}"
    echo -e "${YELLOW}       wahi SSH account ke IP_LIMIT/GB_LIMIT (SSH Management me set) automatically apply hote hain,${NC}"
    echo -e "${YELLOW}       kyunki SlowDNS traffic bhi isi Dropbear daemon ke through jaata hai.${NC}"
    press_any_key
}

slowdns_menu() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}          SLOWDNS MANAGEMENT                       ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " 1) Install / Reinstall SlowDNS Server"
    echo -e " 2) Set / Change NS Domain"
    echo -e " 3) Show Public Key & Connection Info"
    echo -e " 4) Restart SlowDNS Service"
    echo -e " 5) Back"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Option [1-5]: " sd_opt
    case $sd_opt in
        1) install_slowdns ;;
        2) slowdns_set_ns_domain_flow ;;
        3) slowdns_show_info ;;
        4)
            free_port_53
            systemctl restart slowdns 2>/dev/null
            echo -e "${GREEN}[SUCCESS] SlowDNS service restart kar diya gaya.${NC}"
            press_any_key
            ;;
        5) return ;;
    esac
}
