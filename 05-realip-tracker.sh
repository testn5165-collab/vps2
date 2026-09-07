#!/bin/bash
# ==============================================================================
# RareTriccks VPN Panel - 05-realip-tracker.sh
# REAL CLIENT IP for both protocols (e.g. Pakistan se connect karo to Pakistan
# ka IP hi dikhna chahiye, chahe traffic Nginx ke through kyun na guzre):
#
# SSH-WS: ws-proxy.py already logs REAL_IP + the LOCAL_PORT it used to reach
#         Dropbear. Dropbear's own auth log shows "from 127.0.0.1:PORT" for
#         that same connection. realip_ssh_map.py joins the two on PORT to
#         print "username -> real IP".
#
# V2Ray (VLESS-WS on 80/443, shared with SSH via Nginx path-routing): Nginx's
#         http module CANNOT send PROXY protocol upstream, so a tiny Python
#         relay sits between Nginx and Xray's real WS port. It reads the
#         X-Forwarded-For header Nginx already sets, converts it into a
#         PROXY protocol v1 line, and forwards that + the original bytes to
#         Xray. Xray inbound has "acceptProxyProtocol": true (see
#         06-xray-core.sh) so its OWN access log then shows the real client
#         IP against the right "email:" (=username) - exactly like SSH.
#
# V2Ray (VLESS-XHTTP :8443 and VLESS-TCP+TLS :8444): these move from Xray
#         listening on 0.0.0.0 to Xray listening on 127.0.0.1 only, fronted
#         by an Nginx STREAM block with "proxy_protocol on;" (Nginx's stream
#         module DOES support sending PROXY protocol, unlike its http
#         module) - so real IP works here too, and all traffic still enters
#         through Nginx as requested.
# ==============================================================================
source /etc/raretriccks/00-common.sh

install_realip_tracker() {
    echo -e "${BLUE}[+] Installing Real-IP tracker (SSH port-map + V2Ray relay)...${NC}"

    # ---- SSH real-IP <-> username mapper ----
cat << 'PY_EOF' > /usr/local/bin/realip_ssh_map.py
import subprocess, re, sys

def get_dropbear_logs():
    try:
        return subprocess.check_output(
            ["journalctl", "-u", "dropbear", "--no-pager", "-n", "500"],
            stderr=subprocess.DEVNULL
        ).decode("utf-8", errors="ignore")
    except Exception:
        return ""

def get_wsproxy_logs():
    try:
        with open("/var/log/ws-proxy.log", "r", errors="ignore") as f:
            return f.readlines()[-1000:]
    except Exception:
        return []

def main():
    dropbear_raw = get_dropbear_logs()
    ws_lines = get_wsproxy_logs()

    # port -> real_ip (most recent wins)
    port_to_ip = {}
    for line in ws_lines:
        m = re.search(r"REAL_IP:(\S+) LOCAL_PORT:(\d+)", line)
        if m:
            port_to_ip[m.group(2)] = m.group(1)

    # username -> port (most recent successful auth wins)
    results = []
    for line in dropbear_raw.splitlines():
        if "Password auth succeeded" not in line:
            continue
        um = re.search(r"for '?([\w.-]+)'? from 127\.0\.0\.1:(\d+)", line)
        if not um:
            continue
        uname, port = um.group(1), um.group(2)
        real_ip = port_to_ip.get(port, "unknown (direct/legacy connection)")
        results.append((uname, real_ip, port))

    if not results:
        print("  (koi recent SSH-WS login nahi mila)")
        return

    seen = {}
    for uname, ip, port in results:
        seen[uname] = ip  # keep last (most recent) real IP per user
    for uname, ip in seen.items():
        print(f"  {uname:20s} -> {ip}")

if __name__ == "__main__":
    main()
PY_EOF
    chmod +x /usr/local/bin/realip_ssh_map.py

    # ---- V2Ray WS real-IP relay (Nginx -> relay -> Xray, PROXY protocol injected) ----
cat << 'PY_EOF' > /usr/local/bin/v2ray_realip_relay.py
import socket, threading, select, sys

LISTEN_PORT = int(sys.argv[1])
TARGET_PORT = int(sys.argv[2])

def handle(client_sock, addr):
    real_ip = addr[0]
    try:
        client_sock.settimeout(10)
        data = client_sock.recv(65536)
        if not data:
            client_sock.close()
            return

        try:
            text = data.decode("utf-8", errors="ignore")
            for line in text.split("\r\n"):
                low = line.lower()
                if low.startswith("x-forwarded-for:") or low.startswith("x-real-ip:"):
                    real_ip = line.split(":", 1)[1].strip().split(",")[0].strip()
                    break
        except Exception:
            pass

        target = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        target.connect(("127.0.0.1", TARGET_PORT))

        # PROXY protocol v1 header so Xray (acceptProxyProtocol=true) logs the real IP
        proxy_line = f"PROXY TCP4 {real_ip} 127.0.0.1 0 {TARGET_PORT}\r\n"
        target.sendall(proxy_line.encode())
        target.sendall(data)  # forward original WS handshake bytes untouched

        client_sock.settimeout(None)
        socks = [client_sock, target]
        while True:
            r, _, _ = select.select(socks, [], [])
            for s in r:
                other = target if s is client_sock else client_sock
                buf = s.recv(8192)
                if not buf:
                    return
                other.sendall(buf)
    except Exception:
        pass
    finally:
        client_sock.close()

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", LISTEN_PORT))
srv.listen(200)

while True:
    c, a = srv.accept()
    threading.Thread(target=handle, args=(c, a), daemon=True).start()
PY_EOF
    chmod +x /usr/local/bin/v2ray_realip_relay.py

cat << SVC_EOF > /etc/systemd/system/v2ray-relay-tls.service
[Unit]
Description=RareTriccks V2Ray Real-IP Relay (TLS/443 side)
After=network.target xray.service

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/v2ray_realip_relay.py ${V2RAY_RELAY_TLS_PORT} ${XRAY_WS_TLS_PORT}
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF

cat << SVC_EOF > /etc/systemd/system/v2ray-relay-plain.service
[Unit]
Description=RareTriccks V2Ray Real-IP Relay (Plain/80 side)
After=network.target xray.service

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/v2ray_realip_relay.py ${V2RAY_RELAY_PLAIN_PORT} ${XRAY_WS_PLAIN_PORT}
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF

    systemctl daemon-reload
    systemctl enable v2ray-relay-tls v2ray-relay-plain
    systemctl restart v2ray-relay-tls v2ray-relay-plain
    wait_for_port 127.0.0.1 "${V2RAY_RELAY_TLS_PORT}" "V2Ray Real-IP Relay TLS" 10 || true
    wait_for_port 127.0.0.1 "${V2RAY_RELAY_PLAIN_PORT}" "V2Ray Real-IP Relay Plain" 10 || true
}

show_ssh_realip_map() {
    echo -e "${BLUE}--- SSH-WS Real Client IPs (username -> real IP) ---${NC}"
    if [[ -x /usr/local/bin/realip_ssh_map.py ]]; then
        python3 /usr/local/bin/realip_ssh_map.py
    else
        echo "  (realip tracker abhi install nahi hui - install_all_components chalao)"
    fi
}

show_v2ray_realip_map() {
    echo -e "${BLUE}--- V2Ray Real Client IPs (from Xray access log) ---${NC}"
    if [[ -f "$XRAY_ACCESS_LOG" ]]; then
        tail -n 300 "$XRAY_ACCESS_LOG" | grep -oE "from [0-9.]+:[0-9]+ .*email: [A-Za-z0-9_.-]+" | tail -n 30
    else
        echo "  (Xray access log abhi maujood nahi)"
    fi
}
