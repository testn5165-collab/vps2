#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - 01-base-install.sh
# Base OS packages jo baaki saare modules ko chahiye.
# ==============================================================================
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p /etc/raretriccks
cp -f "$SCRIPT_DIR/00-common.sh" /etc/raretriccks/00-common.sh 2>/dev/null || true
source /etc/raretriccks/00-common.sh

clear
echo -e "${CYAN}====================================================${NC}"
echo -e "${YELLOW}   ${PANEL_NAME} - BASE INSTALL                    ${NC}"
echo -e "${CYAN}====================================================${NC}"

echo -e "${BLUE}[1/3] apt update & upgrade...${NC}"
apt update -y && apt upgrade -y

echo -e "${BLUE}[2/3] Installing core tools...${NC}"
apt install -y curl wget unzip tar git build-essential net-tools socat \
    jq openssl nginx stunnel4 dropbear certbot python3 python3-pip \
    lsof iptables uuid-runtime acl

echo -e "${BLUE}[3/3] Basic firewall sanity (UFW skip if not present)...${NC}"
if command -v ufw &>/dev/null; then
    # SSH core + stunnel
    ufw allow 22/tcp   || true
    ufw allow 109/tcp  || true
    ufw allow 8022/tcp || true
    ufw allow 444/tcp  || true
    # Nginx multi-port SSH-WS (TLS)
    for p in 443 2053 2083 2087 2096 8443 445 447 777; do ufw allow ${p}/tcp || true; done
    # Nginx multi-port SSH-WS (plain)
    for p in 80 8080 8880 2052 2082 2086 2095; do ufw allow ${p}/tcp || true; done
    # Xray dedicated ports
    ufw allow 9443/tcp || true
    ufw allow 9444/tcp || true
    ufw allow 9880/tcp || true
    ufw allow 9005/tcp || true
fi

echo -e "\n${GREEN}[DONE] Base packages installed. Ab domain set karke agla script chalao:${NC}"
echo -e "${CYAN}echo yourdomain.com > ${DOMAIN_FILE}${NC}"
