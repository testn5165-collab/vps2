#!/bin/bash
# ==============================================================================
# RareTriccks VPN Panel - 07-nginx-proxy.sh
# SAB TRAFFIC NGINX KE THROUGH, REAL CLIENT IP KE SAATH:
#   Port 80  : SSH-WS (-> ws-proxy)      + V2Ray VLESS-WS non-TLS (-> relay -> Xray)
#   Port 443 : SSH-WS+SSL (TLS here)     + V2Ray VLESS-WS TLS     (-> relay -> Xray)
#   Port 8443: V2Ray VLESS-XHTTP (auto)  - Nginx STREAM + proxy_protocol -> Xray (TLS by Xray)
#   Port 8444: V2Ray VLESS-TCP+TLS       - Nginx STREAM + proxy_protocol -> Xray (TLS by Xray)
# Real IP: WS ports route via the tiny relay in 05-realip-tracker.sh (http
# module can't send PROXY protocol, so the relay converts X-Forwarded-For
# into a PROXY protocol line for Xray). The two dedicated ports use Nginx's
# STREAM module directly, which DOES support "proxy_protocol on;".
# ==============================================================================
source /etc/raretriccks/00-common.sh

copy_xray_certs() {
    local CERT_DOM=$(get_cert_domain)
    mkdir -p "$XRAY_CERT_DIR"
    if [[ -f "/etc/letsencrypt/live/${CERT_DOM}/fullchain.pem" && -f "/etc/letsencrypt/live/${CERT_DOM}/privkey.pem" ]]; then
        cp "/etc/letsencrypt/live/${CERT_DOM}/fullchain.pem" "$XRAY_CERT_FILE"
        cp "/etc/letsencrypt/live/${CERT_DOM}/privkey.pem" "$XRAY_KEY_FILE"
        chown -R "${XRAY_SVC_USER}:${XRAY_SVC_USER}" "$XRAY_CERT_DIR" 2>/dev/null || chown -R nobody:nogroup "$XRAY_CERT_DIR"
        chmod 750 "$XRAY_CERT_DIR"
        chmod 640 "$XRAY_CERT_FILE" "$XRAY_KEY_FILE"
        return 0
    fi
    return 1
}

nginx_stream_module_available() {
    # Stream module ya to statically compiled hoga (--with-stream in nginx -V)
    # ya dynamic module ke roop mein modules-enabled mein load hoga.
    if nginx -V 2>&1 | grep -q -- '--with-stream'; then
        return 0
    fi
    if grep -rl "ngx_stream_module" /etc/nginx/modules-enabled/ 2>/dev/null | grep -q .; then
        return 0
    fi
    return 1
}

ensure_nginx_stream_block() {
    mkdir -p /etc/nginx/stream.d

    if ! nginx_stream_module_available; then
        # Module missing hai - agar package abhi tak install nahi hua, ek aakhri
        # koshish karo (kabhi kabhi pehli baar apt update na hone ki wajah se fail hota hai).
        apt-get install -y libnginx-mod-stream &>/dev/null

        if ! nginx_stream_module_available; then
            echo -e "${RED}[WARN] Nginx stream module load nahi ho paya - 'libnginx-mod-stream' install karke check karein.${NC}"
            echo -e "${YELLOW}[INFO] Stream config (port ${XRAY_XHTTP_PORT}/${XRAY_TCP_TLS_PORT}) skip kiya ja raha hai taaki nginx.conf corrupt na ho.${NC}"
            # Agar pehle kisi purani run mein stream{} block bina check ke likh diya gaya tha,
            # usko yahan se hata do warna nginx -t hamesha fail karta rahega.
            if grep -q "^stream {" /etc/nginx/nginx.conf 2>/dev/null; then
                cp /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak.$(date +%s)"
                sed -i '/^stream {$/,/^}$/d' /etc/nginx/nginx.conf
            fi
            return 1
        fi
    fi

    # nginx.conf mein by default stream{} context nahi hota - ek baar add karo (idempotent).
    if ! grep -q "^stream {" /etc/nginx/nginx.conf 2>/dev/null; then
        cp /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak.$(date +%s)"
        cat << 'STREAM_BLOCK' >> /etc/nginx/nginx.conf

stream {
    include /etc/nginx/stream.d/*.conf;
}
STREAM_BLOCK
    fi
    return 0
}

apply_nginx_stream_config() {
    if ! ensure_nginx_stream_block; then
        echo -e "${YELLOW}[INFO] XHTTP/TCP-TLS (ports ${XRAY_XHTTP_PORT}/${XRAY_TCP_TLS_PORT}) is baar public nahi honge (stream module missing). WS/SSH aur VLESS-WS (80/443) par koi asar nahi.${NC}"
        return 1
    fi
    # Xray khud hi TLS/handshake handle karta hai in dono ports par (XHTTP + TCP-TLS);
    # Nginx sirf public entry point hai, PROXY protocol ke saath real IP forward karta hai.
    cat << STREAM_EOF > "$NGINX_STREAM_CONF"
server {
    listen ${XRAY_XHTTP_PORT};
    proxy_pass 127.0.0.1:${XRAY_XHTTP_PORT};
    proxy_protocol on;
}

server {
    listen ${XRAY_TCP_TLS_PORT};
    proxy_pass 127.0.0.1:${XRAY_TCP_TLS_PORT};
    proxy_protocol on;
}
STREAM_EOF
}

configure_nginx_proxy() {
    local MY_DOMAIN=$(get_domain)
    local CERT_DOM=$(get_cert_domain)
    local HAVE_SSL=0

    if [[ -f "/etc/letsencrypt/live/${CERT_DOM}/fullchain.pem" ]]; then
        HAVE_SSL=1
    fi

    mkdir -p /etc/nginx/conf.d

cat << NGINX_EOF > "$NGINX_CONF"
server {
    listen 80;
    listen [::]:80;
    server_name ${MY_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location ${V2RAY_WS_PATH} {
        proxy_pass http://127.0.0.1:${V2RAY_RELAY_PLAIN_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location / {
        proxy_pass http://127.0.0.1:${WS_SSH_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX_EOF

    if [[ "$HAVE_SSL" -eq 1 ]]; then
cat << NGINX_EOF >> "$NGINX_CONF"
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${MY_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${CERT_DOM}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${CERT_DOM}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location ${V2RAY_WS_PATH} {
        proxy_pass http://127.0.0.1:${V2RAY_RELAY_TLS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location / {
        proxy_pass http://127.0.0.1:${WS_SSH_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX_EOF
    fi

    apply_nginx_stream_config || true

    nginx -t &>/tmp/nginx_check.log
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}[ERROR] Nginx config invalid!${NC}"
        cat /tmp/nginx_check.log
        return 1
    fi

    systemctl enable nginx &>/dev/null
    systemctl restart nginx
    wait_for_port 127.0.0.1 80 "Nginx (80)" 10
    if [[ "$HAVE_SSL" -eq 1 ]]; then
        wait_for_port 127.0.0.1 443 "Nginx (443, TLS)" 10
    fi
}

add_domain_option() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}        ADD / CHANGE DOMAIN NAME                    ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    read -rp " Apna Domain Enter Karein (e.g. sub.yourdomain.com): " new_dom

    if [[ -z "$new_dom" ]]; then
        echo -e "${RED}[ERROR] Domain khaali nahi chhod sakte!${NC}"
    else
        mkdir -p /etc/raretriccks
        echo "$new_dom" > "$DOMAIN_FILE"
        echo -e "\n${GREEN}[SUCCESS] Domain successfully set to: ${CYAN}${new_dom}${NC}"
        configure_nginx_proxy
    fi
    press_any_key
}
