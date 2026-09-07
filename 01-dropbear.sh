#!/bin/bash
# RareTriccks VPN Panel - 01-dropbear.sh
# Dropbear SSH core setup (ports 22, 109 internal, 447 backup).
source /etc/raretriccks/00-common.sh

fix_dropbear_core() {
    mkdir -p /etc/dropbear
    chmod 700 /etc/dropbear

    grep -qxF "/bin/bash" /etc/shells || echo "/bin/bash" >> /etc/shells
    grep -qxF "/usr/sbin/nologin" /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells

    if [[ ! -f /etc/dropbear/dropbear_rsa_host_key ]]; then
        dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key &>/dev/null
    fi
    if [[ ! -f /etc/dropbear/dropbear_ecdsa_host_key ]]; then
        dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key &>/dev/null
    fi
    if [[ ! -f /etc/dropbear/dropbear_ed25519_host_key ]]; then
        dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key &>/dev/null
    fi

    chmod 600 /etc/dropbear/*_host_key 2>/dev/null
    rm -rf /etc/systemd/system/dropbear.service.d

cat << 'EOF' > /etc/default/dropbear
NO_START=0
DROPBEAR_PORT=22
DROPBEAR_EXTRA_ARGS="-p 109 -p 447 -b /etc/issue.net"
DROPBEAR_BANNER="/etc/issue.net"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

    systemctl daemon-reload
    systemctl enable dropbear
    systemctl restart dropbear
    wait_for_port 127.0.0.1 109 "Dropbear (109)" 10
}
