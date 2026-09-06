#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - 06-nginx-multiplexer.sh
# Multi-port Nginx multiplexer (HAProxy ki jagah):
#   SSH_WS_TLS_PORTS   -> TLS terminated here, SSH-WS+SSL (+ V2Ray-WS+TLS on
#                          path /v2ray)
#   SSH_WS_PLAIN_PORTS -> plain HTTP, SSH-WS (+ V2Ray-WS non-TLS on /v2ray)
# Dono arrays 00-common.sh mein edit ho sakte hain. Har port same do backend
# (ws-proxy.py aur xray) mein se ek par jaata hai, path ke hisaab se route
# hota hai.
#
# HAProxy se switch karne ki wajah: nginx zyada battle-tested hai is exact
# use-case (TLS-terminate + path-based reverse proxy) ke liye, aur permission
# / user-mismatch jaisi dikkatein kam aati hain kyunki nginx worker apne aap
# config file root se hi parse karta hai (sirf www-data ko cert access chahiye
# hota hai, jo standard packages already handle karte hain).
# ==============================================================================
set -e
source /etc/raretriccks/00-common.sh

DOMAIN=$(require_domain_or_die)

if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    echo -e "${RED}[ERROR] Cert missing. Pehle 02-ssl-cert.sh chalao.${NC}"
    exit 1
fi

clear
echo -e "${CYAN}====================================================${NC}"
echo -e "${YELLOW}   ${PANEL_NAME} - NGINX MULTI-PORT MULTIPLEXER    ${NC}"
echo -e "${CYAN}====================================================${NC}"

if ! command -v nginx &>/dev/null; then
    echo -e "${BLUE}Installing nginx...${NC}"
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y nginx
fi

# Purana default site hata do warna 80/443 par conflict hoga.
rm -f /etc/nginx/sites-enabled/default

mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

{
# ---- Ek TLS server block, har port SSH_WS_TLS_PORTS mein ----
for p in "${SSH_WS_TLS_PORTS[@]}"; do
cat << NG_TLS
server {
    listen ${p} ssl;
    listen [::]:${p} ssl;
    server_name _;

    ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    client_header_timeout 86400s;
    client_body_timeout   86400s;

    location ${V2RAY_WS_PATH} {
        proxy_pass http://127.0.0.1:${XRAY_WS_TLS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location / {
        proxy_pass http://127.0.0.1:${SSH_WS_INTERNAL_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}

NG_TLS
done

# ---- Ek plain server block, har port SSH_WS_PLAIN_PORTS mein ----
for p in "${SSH_WS_PLAIN_PORTS[@]}"; do
cat << NG_PLAIN
server {
    listen ${p};
    listen [::]:${p};
    server_name _;

    client_header_timeout 86400s;
    client_body_timeout   86400s;

    location ${V2RAY_WS_PATH} {
        proxy_pass http://127.0.0.1:${XRAY_WS_PLAIN_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }

    location / {
        proxy_pass http://127.0.0.1:${SSH_WS_INTERNAL_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}

NG_PLAIN
done
} > /etc/nginx/sites-available/raretriccks-multiplexer.conf

ln -sf /etc/nginx/sites-available/raretriccks-multiplexer.conf /etc/nginx/sites-enabled/raretriccks-multiplexer.conf

# Purana haproxy agar installed/running hai to bandh kar do taaki port clash na ho.
systemctl disable --now haproxy 2>/dev/null || true

nginx -t
systemctl enable nginx
systemctl restart nginx

echo -e "\n${GREEN}[DONE] Nginx multiplexer live (HAProxy replaced).${NC}"
echo -e "${CYAN}TLS ports   (SSH-WS+SSL / V2Ray-WS+TLS)  : ${SSH_WS_TLS_PORTS[*]}${NC}"
echo -e "${CYAN}Plain ports (SSH-WS / V2Ray-WS non-TLS)  : ${SSH_WS_PLAIN_PORTS[*]}${NC}"
