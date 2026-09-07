#!/bin/bash
# ==============================================================================
# RareTriccks VPN Panel - 04-ws-proxy.sh
# SSH-WS engine (WebSocket handshake -> Dropbear:109).
# PATCHED: ab har connection ka REAL_IP + LOCAL_PORT dono log hote hain
# (/var/log/ws-proxy.log). LOCAL_PORT wahi ephemeral port hai jis se yeh
# script Dropbear ko connect karta hai - Dropbear apne auth log mein isi
# port ko "from 127.0.0.1:PORT" ke roop mein dikhata hai. 05-realip-tracker.sh
# in dono logs ko PORT par join karke "username -> real IP" nikaalta hai.
# ==============================================================================
source /etc/raretriccks/00-common.sh

install_ws_proxy() {
    echo -e "${BLUE}[+] Installing SSH-WS Python engine (with real-IP logging)...${NC}"

cat << PY_EOF > /usr/local/bin/ws-proxy.py
import socket, threading, select, time

PORT = ${WS_SSH_PORT}
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 109
LOG_FILE = '/var/log/ws-proxy.log'

def log_client_ip(ip, local_port):
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} REAL_IP:{ip} LOCAL_PORT:{local_port}\n")
    except Exception:
        pass

def handle_client(client_socket, client_addr):
    real_ip = client_addr[0]
    try:
        client_socket.settimeout(10)
        request_raw = client_socket.recv(4096)
        if not request_raw:
            client_socket.close()
            return

        request = request_raw.decode('utf-8', errors='ignore')

        for line in request.split('\r\n'):
            low = line.lower()
            if low.startswith('x-forwarded-for:') or low.startswith('x-real-ip:'):
                real_ip = line.split(':', 1)[1].strip().split(',')[0].strip()
                break

        response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
        client_socket.sendall(response.encode('utf-8'))

        target_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target_socket.connect((TARGET_HOST, TARGET_PORT))
        local_port = target_socket.getsockname()[1]
        log_client_ip(real_ip, local_port)

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
server.bind(('0.0.0.0', PORT))
server.listen(200)

while True:
    client, addr = server.accept()
    threading.Thread(target=handle_client, args=(client, addr), daemon=True).start()
PY_EOF

cat << SVC_EOF > /etc/systemd/system/ws-proxy.service
[Unit]
Description=RareTriccks WebSocket Proxy Service (real-IP logging)
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
    wait_for_port 127.0.0.1 "${WS_SSH_PORT}" "WS-Proxy (${WS_SSH_PORT})" 10
}
