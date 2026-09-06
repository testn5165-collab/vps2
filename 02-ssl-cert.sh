#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - 02-ssl-cert.sh
# Let's Encrypt cert issue karta hai. Nginx/stunnel/Xray seedha
# /etc/letsencrypt/live/<domain>/{fullchain,privkey}.pem padhte hain, isliye
# koi alag combined bundle banane ki zarurat nahi (HAProxy ke time thi).
# Prerequisite: domain A record VPS IP par pointed ho, port 80 free ho.
# ==============================================================================
set -e
source /etc/raretriccks/00-common.sh

DOMAIN=$(require_domain_or_die)

clear
echo -e "${CYAN}====================================================${NC}"
echo -e "${YELLOW}   ${PANEL_NAME} - SSL SETUP (${DOMAIN})           ${NC}"
echo -e "${CYAN}====================================================${NC}"

systemctl stop nginx 2>/dev/null || true

certbot certonly --standalone --preferred-challenges http --agree-tos \
    --register-unsafely-without-email -d "$DOMAIN"

if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    echo -e "${RED}[ERROR] SSL fail. DNS/A-record check karo.${NC}"
    exit 1
fi

# Nginx aur Xray (XHTTP/TCP-TLS dedicated ports) dono apna cert seedha LE
# path se padhते hain, isliye alag combined bundle banane ki zarurat nahi.
# Xray user ko cert access chahiye - fix_xray_perms wahi ACL laga deta hai.
fix_xray_perms

mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat << HOOK_EOF > /etc/letsencrypt/renewal-hooks/deploy/raretriccks-reload.sh
#!/bin/bash
DOM="${DOMAIN}"
source /etc/raretriccks/00-common.sh
fix_xray_perms
systemctl restart nginx 2>/dev/null
systemctl restart xray 2>/dev/null
systemctl restart stunnel4 2>/dev/null
HOOK_EOF
chmod +x /etc/letsencrypt/renewal-hooks/deploy/raretriccks-reload.sh

echo -e "\n${GREEN}[DONE] SSL issued for ${DOMAIN}. Auto-renew hook installed (nginx + xray perms auto-fix).${NC}"
