#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - 10-dtunnel-support.sh
# DTunnel / HTTP-Injector jugaad: ws-proxy.py already generic WS-handshake deta
# hai (kisi bhi path/payload par 101 response), lekin DTunnel kabhi "CONNECT"
# method use karta hai (proxy-style). Ye patch CONNECT support add karta hai
# taake DTunnel "Custom Payload" mode bhi isi 2082 listener se kaam kare —
# koi naya port nahi chahiye, same SSH-WS engine reuse hota hai.
# ==============================================================================
set -e
source /etc/raretriccks/00-common.sh

clear
echo -e "${CYAN}====================================================${NC}"
echo -e "${YELLOW}   ${PANEL_NAME} - DTUNNEL / HTTP-INJECTOR PATCH     ${NC}"
echo -e "${CYAN}====================================================${NC}"

if [[ ! -f /usr/local/bin/ws-proxy.py ]]; then
    echo -e "${RED}[ERROR] Pehle 04-ssh-ws.sh chalao.${NC}"
    exit 1
fi

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

        first_line = request.split('\r\n', 1)[0] if request else ''
        is_connect = first_line.upper().startswith('CONNECT')

        for line in request.split('\r\n'):
            low = line.lower()
            if low.startswith('x-forwarded-for:') or low.startswith('x-real-ip:'):
                real_ip = line.split(':', 1)[1].strip().split(',')[0].strip()
                break

        log_client_ip(real_ip)

        # DTunnel "Custom Payload" mode often opens with an HTTP CONNECT line.
        # Respond like a proxy accepting the tunnel, then behave identically
        # to the WS-upgrade path below (raw pass-through to dropbear).
        if is_connect:
            client_socket.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        else:
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
systemctl restart ws-proxy

echo -e "\n${GREEN}[DONE] ws-proxy ab CONNECT (DTunnel) aur WS-Upgrade (normal SSH-WS clients) dono handle karta hai.${NC}"
echo -e "${YELLOW}DTunnel client config example:${NC}"
echo -e "  Payload : CONNECT \$HOST HTTP/1.1[crlf]Host: ${CYAN}$(get_domain)${NC}[crlf][crlf]"
echo -e "  Server  : $(get_domain)   Port: 80 (no-SSL) or 443 (SSL, DTunnel TLS ON)"
echo -e "  Proxy   : same port (80/443) — koi alag proxy IP/port nahi chahiye"
