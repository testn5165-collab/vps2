#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - 05-ssh-ssl-stunnel.sh
# "SSH+SSL" (raw, non-websocket) — client seedha TLS handshake karta hai,
# stunnel usko decrypt karke Dropbear (109) ko forward karta hai.
# Public port: SSH_SSL_STUNNEL_PORT (default 444)
# ==============================================================================
set -e
source /etc/raretriccks/00-common.sh

DOMAIN=$(require_domain_or_die)

clear
echo -e "${CYAN}====================================================${NC}"
echo -e "${YELLOW}   ${PANEL_NAME} - SSH+SSL (STUNNEL) SETUP          ${NC}"
echo -e "${CYAN}====================================================${NC}"

if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    echo -e "${RED}[ERROR] Pehle 02-ssl-cert.sh chalao (SSL cert chahiye).${NC}"
    exit 1
fi

mkdir -p /etc/stunnel
cat "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" \
    "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" > /etc/stunnel/stunnel.pem
chmod 600 /etc/stunnel/stunnel.pem

cat << STUNNEL_EOF > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel4.pid
cert = /etc/stunnel/stunnel.pem
client = no

[ssh-ssl]
accept = ${SSH_SSL_STUNNEL_PORT}
connect = 127.0.0.1:109
STUNNEL_EOF

# Enable stunnel4 daemon (Debian/Ubuntu style)
if [[ -f /etc/default/stunnel4 ]]; then
    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4
fi

systemctl daemon-reload
systemctl enable stunnel4
systemctl restart stunnel4

echo -e "\n${GREEN}[DONE] Raw SSH+SSL live on public port ${SSH_SSL_STUNNEL_PORT} -> dropbear:109${NC}"
echo -e "${CYAN}Client config: Host=${DOMAIN}, Port=${SSH_SSL_STUNNEL_PORT}, TLS=on, Payload=none (raw SSH inside TLS)${NC}"
