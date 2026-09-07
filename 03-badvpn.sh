#!/bin/bash
# RareTriccks VPN Panel - 03-badvpn.sh
# BadVPN UDP Gateway (gaming/calls) install.
source /etc/raretriccks/00-common.sh

install_badvpn_udpgw() {
    echo -e "${BLUE}[+] Installing & Auto-Starting BadVPN UDP Gateway for Gaming & Calls...${NC}"
    
    if [[ ! -f /usr/local/bin/badvpn-udpgw ]]; then
        wget -O /usr/local/bin/badvpn-udpgw https://github.com/ambrop72/badvpn/raw/master/udpgw/badvpn-udpgw 2>/dev/null || true
        if [[ ! -f /usr/local/bin/badvpn-udpgw ]]; then
            apt install -y cmake build-essential libssl-dev git &>/dev/null || true
            if [[ ! -d /tmp/badvpn ]]; then
                git clone https://github.com/ambrop72/badvpn.git /tmp/badvpn &>/dev/null || true
            fi
            if [[ -d /tmp/badvpn ]]; then
                mkdir -p /tmp/badvpn/build
                cd /tmp/badvpn/build
                cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 &>/dev/null
                make install &>/dev/null || true
                cd ~
            fi
        fi
    fi

    if [[ -f /usr/local/bin/badvpn-udpgw ]]; then
        chmod +x /usr/local/bin/badvpn-udpgw
    fi

cat << 'EOF' > /etc/systemd/system/badvpn.service
[Unit]
Description=BadVPN UDP Gateway for Gaming & Voice Calls
After=network.target

[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000 --max-connections 2000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable badvpn
    systemctl restart badvpn
    wait_for_port 127.0.0.1 7300 "BadVPN UDPGW (7300)" 5 || true
}

