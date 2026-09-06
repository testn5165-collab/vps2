#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - 04-ssh-ws.sh
# SSH-WS engine: WebSocket handshake -> forwards to Dropbear (109).
# Isi ek listener (2082, localhost) ko HAProxy 80 aur 443 dono se hit karega,
# isliye "SSH WS+SSL" aur "SSH WS (non-SSL)" dono automatically kaam karte hain.
# ==============================================================================
set -e
source /etc/raretriccks/00-common.sh

clear
echo -e "${CYAN}====================================================${NC}"
echo -e "${YELLOW}   ${PANEL_NAME} - SSH-WS ENGINE                    ${NC}"
echo -e "${CYAN}====================================================${NC}"

cat << WS_EOF > /usr/local/bin/ws-proxy.py
import socket, threading, select, time

PORT = ${SSH_WS_INTERNAL_PORT}
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 109
LOG_FILE = '/var/log/ws-proxy.log'

def log_client_ip(ip):
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - REAL_IP:{ip}\n")
    except Exception:
        pass

def handle_client(client_socket, client_addr):
    real_ip = client_addr[0]
    try:
        client_socket.settimeout(10)
        request = client_socket.recv(4096).decode('utf-8', errors='ignore')
        if not request:
            client_socket.close()
            return

        # Standard headers + DTunnel/HTTP-Injector style custom headers
        for line in request.split('\r\n'):
            low = line.lower()
            if low.startswith('x-forwarded-for:') or low.startswith('x-real-ip:'):
                real_ip = line.split(':', 1)[1].strip().split(',')[0].strip()
                break

        log_client_ip(real_ip)

        response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
        client_socket.sendall(response.encode('utf-8'))

        target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target_socket.connect((TARGET_HOST, TARGET_PORT))

        sockets = [client_socket, target_socket]
        client_socket.settimeout(None)

        while True:
            readable, _, _ = select.select(sockets, [], [])
            for s in readable:
                other = target_socket if s is client_socket else client_socket
                data = s.recv(8192)
                if not data:
                    return
                other.sendall(data)
    except Exception:
        pass
    finally:
        client_socket.close()

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(('127.0.0.1', PORT))
server.listen(200)

while True:
    client, addr = server.accept()
    threading.Thread(target=handle_client, args=(client, addr), daemon=True).start()
WS_EOF

chmod +x /usr/local/bin/ws-proxy.py

cat << SVC_EOF > /etc/systemd/system/ws-proxy.service
[Unit]
Description=RareTriccks SSH-WS Proxy
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF

systemctl daemon-reload
systemctl enable ws-proxy
systemctl restart ws-proxy

echo -e "\n${GREEN}[DONE] SSH-WS listening on 127.0.0.1:${SSH_WS_INTERNAL_PORT} (public expose via HAProxy in module 06).${NC}"
