#!/bin/bash
# RareTriccks VPN Panel - 07-telegram-bot.sh
# Optional Telegram remote-admin bot (Python, isolated venv).
source /etc/raretriccks/00-common.sh

install_tgbot_script() {
    cat << 'PY_EOF' > /usr/local/bin/tgbot.py
import os
import re
import json
import asyncio
import subprocess
from datetime import datetime, timedelta

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, ContextTypes, filters,
)

PANEL_NAME = "RareTriccks VPN Panel"
CONFIG_FILE = "/etc/raretriccks/tgbot/config.json"
ADMINS_FILE = "/etc/raretriccks/tgbot/admins.json"
USERS_DIR = "/etc/raretriccks/users"
DOMAIN_FILE = "/etc/raretriccks/domain.conf"
BANNER_FILE = "/etc/issue.net"

NGINX_TEMPLATE = """server {{
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name {dom} _;

    location / {{
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }}

    location /raretriccks {{
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }}
}}

server {{
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    server_name {dom} _;

    ssl_certificate /etc/letsencrypt/live/{dom}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/{dom}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {{
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }}

    location /raretriccks {{
        proxy_redirect off;
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }}
}}
"""

FLOWS = {
    "add_user": [
        ("username", "\U0001F464 Username enter karein:"),
        ("password", "\U0001F511 Password enter karein:"),
        ("days", "\U0001F4C5 Expiry days enter karein (e.g. 30):"),
        ("ip_limit", "\U0001F310 Max IP Limit enter karein (e.g. 1):"),
        ("gb_limit", "\U0001F4BE Data Limit GB enter karein (e.g. 5, ya Unlimited):"),
    ],
    "del_user": [("username", "\U0001F464 Delete karne ke liye Username enter karein:")],
    "renew_user": [
        ("username", "\U0001F464 Username enter karein jise renew karna hai:"),
        ("days", "\U0001F4C5 Kitne additional days add karne hain?"),
    ],
    "ip_limit": [
        ("username", "\U0001F464 Username enter karein:"),
        ("value", "\U0001F310 Naya IP Limit enter karein:"),
    ],
    "gb_limit": [
        ("username", "\U0001F464 Username enter karein:"),
        ("value", "\U0001F4BE Naya GB Limit enter karein:"),
    ],
    "domain": [("value", "\U0001F30D Naya domain enter karein (e.g. sub.example.com):")],
    "banner": [("value", "\U0001F4E2 Naya SSH banner text bhejein:")],
    "add_admin": [("value", "\U0001F451 Naye Admin ka Telegram User ID enter karein:")],
    "remove_admin": [("value", "\U0001F5D1 Remove karne ke liye Admin ka Telegram User ID enter karein:")],
}

def load_config():
    with open(CONFIG_FILE) as f:
        return json.load(f)

def load_admins():
    if not os.path.exists(ADMINS_FILE):
        return []
    with open(ADMINS_FILE) as f:
        return json.load(f)

def save_admins(admins):
    with open(ADMINS_FILE, "w") as f:
        json.dump(admins, f)

def is_admin(uid):
    return uid in load_admins()

def is_super(uid):
    cfg = load_config()
    return uid == cfg.get("super_admin")

def sh(cmd_list, input_data=None):
    return subprocess.run(cmd_list, capture_output=True, text=True, input=input_data)

def run(cmd_str):
    return subprocess.run(cmd_str, shell=True, capture_output=True, text=True)

def get_domain():
    if os.path.exists(DOMAIN_FILE):
        with open(DOMAIN_FILE) as f:
            d = f.read().strip()
            return d if d else "No Domain Set"
    return "No Domain Set"

def apply_nginx_config():
    dom = get_domain()
    if dom == "No Domain Set":
        return
    os.makedirs("/etc/nginx/conf.d", exist_ok=True)
    with open("/etc/nginx/conf.d/vpn.conf", "w") as f:
        f.write(NGINX_TEMPLATE.format(dom=dom))
    sh(["rm", "-f", "/etc/nginx/sites-enabled/default"])
    sh(["systemctl", "restart", "nginx"])

def valid_username(u):
    return re.match(r"^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$", u) is not None

def add_user(username, password, days, ip_limit, gb_limit):
    if not valid_username(username):
        return False, "Invalid username (letter se start, sirf a-z 0-9 _ - allowed)."
    try:
        exp_date = (datetime.now() + timedelta(days=int(days))).strftime("%Y-%m-%d")
    except ValueError:
        return False, "Invalid days value."
    r = sh(["useradd", "-M", "-s", "/bin/bash", "-e", exp_date, username])
    if r.returncode != 0:
        return False, (r.stderr.strip() or "User create failed (already exists?)")
    sh(["chpasswd"], input_data=f"{username}:{password}\n")
    os.makedirs(USERS_DIR, exist_ok=True)
    with open(f"{USERS_DIR}/{username}.conf", "w") as f:
        f.write(f"IP_LIMIT={ip_limit}\nGB_LIMIT={gb_limit}\nUSED_MB=0.0\n")
    return True, exp_date

def delete_user(username):
    sh(["userdel", "-f", username])
    try:
        os.remove(f"{USERS_DIR}/{username}.conf")
    except FileNotFoundError:
        pass

def renew_user(username, days):
    r = sh(["id", username])
    if r.returncode != 0:
        return False
    try:
        new_exp = (datetime.now() + timedelta(days=int(days))).strftime("%Y-%m-%d")
    except ValueError:
        return False
    sh(["usermod", "-e", new_exp, username])
    sh(["passwd", "-u", username])
    return True

def update_conf_field(username, field, value):
    path = f"{USERS_DIR}/{username}.conf"
    if not os.path.exists(path):
        return False
    lines = open(path).readlines()
    new_lines = []
    found = False
    for line in lines:
        if line.startswith(f"{field}="):
            new_lines.append(f"{field}={value}\n")
            found = True
        else:
            new_lines.append(line)
    if not found:
        new_lines.append(f"{field}={value}\n")
    with open(path, "w") as f:
        f.writelines(new_lines)
    sh(["passwd", "-u", username])
    return True

def list_users_text():
    if not os.path.isdir(USERS_DIR):
        return "Koi user nahi mila."
    entries = []
    for fname in sorted(os.listdir(USERS_DIR)):
        if not fname.endswith(".conf"):
            continue
        uname = fname[:-5]
        data = {}
        for l in open(f"{USERS_DIR}/{fname}"):
            if "=" in l:
                k, v = l.strip().split("=", 1)
                data[k] = v
        exists = sh(["id", uname]).returncode == 0
        status = "Deleted"
        if exists:
            p = sh(["passwd", "-S", uname])
            status = "LOCKED" if " L " in f" {p.stdout} " else "Active"
        used_mb = 0.0
        try:
            used_mb = float(data.get("USED_MB", "0") or 0)
        except ValueError:
            pass
        used_gb = round(used_mb / 1024, 2)
        entries.append(
            f"\U0001F464 {uname} | IP:{data.get('IP_LIMIT', '?')} | "
            f"Used:{used_gb}GB / {data.get('GB_LIMIT', '?')}GB | {status}"
        )
    return "\n".join(entries) if entries else "Koi user nahi mila."

def connected_ips_text():
    r = sh(["ss", "-tnp"])
    lines = [l for l in r.stdout.splitlines() if (":109" in l or ":447" in l or ":22" in l) and "ESTAB" in l]
    return f"\U0001F50C Active SSH/WS sessions (approx): {len(lines)}"

def status_text():
    def st(svc):
        r = sh(["systemctl", "is-active", svc])
        return "\U0001F7E2 ACTIVE" if r.stdout.strip() == "active" else "\U0001F534 INACTIVE"

    dom = get_domain()
    return (
        f"\U0001F30D Domain: {dom}\n\n"
        f"Nginx: {st('nginx')}\n"
        f"Dropbear: {st('dropbear')}\n"
        f"WS Proxy: {st('ws-proxy')}\n"
        f"Auto-Kill: {st('autokill')}"
    )

def set_domain(new_domain):
    os.makedirs("/etc/raretriccks", exist_ok=True)
    with open(DOMAIN_FILE, "w") as f:
        f.write(new_domain)
    apply_nginx_config()

def setup_ssl():
    dom = get_domain()
    if dom == "No Domain Set":
        return False, "Pehle domain set karein."
    sh(["systemctl", "stop", "nginx"])
    r = sh([
        "certbot", "certonly", "--standalone", "--preferred-challenges", "http",
        "--agree-tos", "--register-unsafely-without-email", "-d", dom,
    ])
    ok = os.path.exists(f"/etc/letsencrypt/live/{dom}/fullchain.pem")
    if ok:
        apply_nginx_config()
        return True, "SSL issued successfully."
    return False, "SSL fail ho gaya. Domain A record VPS IP par pointed hai check karein."

def fix_websocket():
    sh(["systemctl", "restart", "dropbear"])
    sh(["systemctl", "daemon-reload"])
    sh(["systemctl", "restart", "ws-proxy"])
    sh(["systemctl", "restart", "autokill"])
    apply_nginx_config()
    return "WebSocket & Bandwidth engine restarted."

WS_PROXY_SRC = """import socket, threading, select, time

PORT = 2082
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 109
LOG_FILE = '/var/log/ws-proxy.log'

def log_client_ip(ip):
    try:
        with open(LOG_FILE, 'a') as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - REAL_IP:{ip}\\n")
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

        for line in request.split('\\r\\n'):
            if line.lower().startswith('x-forwarded-for:') or line.lower().startswith('x-real-ip:'):
                real_ip = line.split(':')[1].strip().split(',')[0].strip()
                break

        log_client_ip(real_ip)

        response = "HTTP/1.1 101 Switching Protocols\\r\\nUpgrade: websocket\\r\\nConnection: Upgrade\\r\\n\\r\\n"
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
server.bind(('0.0.0.0', PORT))
server.listen(200)

while True:
    client, addr = server.accept()
    threading.Thread(target=handle_client, args=(client, addr), daemon=True).start()
"""

WS_PROXY_SERVICE = """[Unit]
Description=RareTriccks WebSocket Proxy Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/ws-proxy.py
Restart=always

[Install]
WantedBy=multi-user.target
"""

AUTOKILL_SRC = """import os
import subprocess
import re
import time

USER_DIR = "/etc/raretriccks/users"

def get_auth_logs():
    raw = ""
    try:
        raw = subprocess.check_output(["journalctl", "-u", "dropbear", "--no-pager", "-n", "300"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
    except Exception:
        pass
    if os.path.exists("/var/log/auth.log"):
        try:
            with open("/var/log/auth.log", "r", encoding="utf-8", errors="ignore") as f:
                raw += "\\n" + f.read()
        except Exception:
            pass
    return raw

def get_active_users_and_pids(raw_logs):
    user_pids = {}
    try:
        ps_out = subprocess.check_output(["ps", "aux"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
        for line in ps_out.splitlines():
            if "dropbear" in line and "grep" not in line:
                parts = line.split()
                if len(parts) > 1:
                    pid = parts[1]
                    matches = [l for l in raw_logs.splitlines() if f"dropbear[{pid}]" in l and "Password auth succeeded" in l]
                    if matches:
                        last_line = matches[-1]
                        m = re.search(r"for \\x27(\\w+)\\x27", last_line)
                        if not m:
                            m = re.search(r"for (\\w+)", last_line)
                        if m:
                            uname = m.group(1)
                            if uname not in user_pids:
                                user_pids[uname] = []
                            user_pids[uname].append(pid)
    except Exception:
        pass
    return user_pids

def get_pid_io_bytes(pid):
    io_file = f"/proc/{pid}/io"
    total_bytes = 0
    if os.path.exists(io_file):
        try:
            with open(io_file, "r") as f:
                for line in f:
                    if line.startswith("rchar:") or line.startswith("wchar:"):
                        total_bytes += int(line.split(":")[1].strip())
        except Exception:
            pass
    return total_bytes

last_pid_bytes = {}

while True:
    try:
        raw_logs = get_auth_logs()
        user_pids_map = get_active_users_and_pids(raw_logs)

        if os.path.exists(USER_DIR):
            for fname in os.listdir(USER_DIR):
                if not fname.endswith(".conf"):
                    continue

                uname = fname[:-5]
                conf_path = os.path.join(USER_DIR, fname)

                ip_limit = 0
                gb_limit = "Unlimited"
                used_mb = 0.0

                with open(conf_path, "r") as f:
                    lines = f.readlines()

                for line in lines:
                    if line.startswith("IP_LIMIT="):
                        try: ip_limit = int(line.strip().split("=")[1])
                        except Exception: pass
                    elif line.startswith("GB_LIMIT="):
                        gb_limit = line.strip().split("=")[1]
                    elif line.startswith("USED_MB="):
                        try: used_mb = float(line.strip().split("=")[1])
                        except Exception: pass

                active_pids = user_pids_map.get(uname, [])

                for pid in active_pids:
                    current_b = get_pid_io_bytes(pid)
                    if pid in last_pid_bytes:
                        diff = current_b - last_pid_bytes[pid]
                        if diff > 0:
                            used_mb += (diff / (1024.0 * 1024.0))
                    last_pid_bytes[pid] = current_b

                new_lines = []
                for line in lines:
                    if line.startswith("USED_MB="):
                        new_lines.append(f"USED_MB={used_mb:.2f}\\n")
                    else:
                        new_lines.append(line)
                with open(conf_path, "w") as f:
                    f.writelines(new_lines)

                if gb_limit != "Unlimited":
                    try:
                        max_mb = float(gb_limit) * 1024.0
                        if used_mb >= max_mb:
                            subprocess.call(["passwd", "-l", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            for pid in active_pids:
                                subprocess.call(["kill", "-9", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    except Exception:
                        pass

                if ip_limit > 0 and len(active_pids) > ip_limit:
                    subprocess.call(["passwd", "-l", uname], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    for pid in active_pids:
                        subprocess.call(["kill", "-9", pid], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    except Exception:
        pass

    time.sleep(3)
"""

AUTOKILL_SERVICE = """[Unit]
Description=RareTriccks Auto-Kill & Bandwidth Tracking Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/autokill.py
Restart=always

[Install]
WantedBy=multi-user.target
"""

DEFAULT_BANNER = (
    '<font color="green">==========================================</font><br>\n'
    '<font color="yellow"><b>WELCOME TO RARETRICCKS VIP VPN</b></font><br>\n'
    '<font color="red"><b>- NO TORRENT / NO MULTILOGIN</b></font><br>\n'
    '<font color="green">==========================================</font><br>\n'
)

def install_components_sync():
    sh(["apt-get", "update", "-y"])
    sh([
        "apt-get", "install", "-y", "curl", "wget", "unzip", "tar", "net-tools",
        "socat", "jq", "openssl", "nginx", "dropbear", "certbot", "python3",
        "python3-pip", "lsof", "iptables",
    ])

    if not os.path.exists(BANNER_FILE) or os.path.getsize(BANNER_FILE) == 0:
        with open(BANNER_FILE, "w") as f:
            f.write(DEFAULT_BANNER)

    run("bash -c '$(declare -f fix_dropbear_core); fix_dropbear_core'")

    run("sed -i 's/#Banner none/Banner \\/etc\\/issue.net/g' /etc/ssh/sshd_config")
    sh(["systemctl", "restart", "ssh"])

    with open("/usr/local/bin/ws-proxy.py", "w") as f:
        f.write(WS_PROXY_SRC)
    sh(["chmod", "+x", "/usr/local/bin/ws-proxy.py"])
    with open("/etc/systemd/system/ws-proxy.service", "w") as f:
        f.write(WS_PROXY_SERVICE)

    with open("/usr/local/bin/autokill.py", "w") as f:
        f.write(AUTOKILL_SRC)
    sh(["chmod", "+x", "/usr/local/bin/autokill.py"])
    with open("/etc/systemd/system/autokill.service", "w") as f:
        f.write(AUTOKILL_SERVICE)

    sh(["systemctl", "daemon-reload"])
    sh(["systemctl", "enable", "ws-proxy"])
    sh(["systemctl", "restart", "ws-proxy"])
    sh(["systemctl", "enable", "autokill"])
    sh(["systemctl", "restart", "autokill"])

    apply_nginx_config()

def uninstall_all():
    sh(["systemctl", "stop", "ws-proxy"])
    sh(["systemctl", "stop", "autokill"])
    sh(["systemctl", "stop", "dropbear"])
    sh(["systemctl", "disable", "ws-proxy"])
    sh(["systemctl", "disable", "autokill"])
    for f in [
        "/etc/systemd/system/ws-proxy.service",
        "/etc/systemd/system/autokill.service",
        "/etc/systemd/system/dropbear.service.d/override.conf",
        "/usr/local/bin/ws-proxy.py",
        "/usr/local/bin/autokill.py",
        "/etc/nginx/conf.d/vpn.conf",
    ]:
        try:
            os.remove(f)
        except FileNotFoundError:
            pass
    sh(["systemctl", "daemon-reload"])
    sh(["systemctl", "restart", "nginx"])
    if os.path.isdir(USERS_DIR):
        for fname in os.listdir(USERS_DIR):
            if fname.endswith(".conf"):
                sh(["userdel", "-f", fname[:-5]])
    sh(["rm", "-rf", "/etc/raretriccks"])
    sh(["rm", "-rf", "/opt/rr-tgbot-venv"])
    for f in ["/usr/local/bin/menu", "/usr/bin/menu"]:
        try:
            os.remove(f)
        except FileNotFoundError:
            pass

def schedule_self_removal():
    subprocess.Popen([
        "bash", "-c",
        "sleep 3 && systemctl disable tgbot 2>/dev/null; "
        "systemctl stop tgbot 2>/dev/null; "
        "rm -f /etc/systemd/system/tgbot.service /usr/local/bin/tgbot.py; "
        "systemctl daemon-reload",
    ])

def back_keyboard():
    return InlineKeyboardMarkup([[InlineKeyboardButton("\u2B05\uFE0F Back to Menu", callback_data="back_main")]])

def main_menu_keyboard(uid):
    rows = [
        [InlineKeyboardButton("\u2795 Add User", callback_data="add_user"),
         InlineKeyboardButton("\U0001F5D1 Delete User", callback_data="del_user")],
        [InlineKeyboardButton("\U0001F4CB User List", callback_data="list_users"),
         InlineKeyboardButton("\u23F3 Renew User", callback_data="renew_user")],
        [InlineKeyboardButton("\U0001F310 IP Limit", callback_data="ip_limit"),
         InlineKeyboardButton("\U0001F4BE GB Limit", callback_data="gb_limit")],
        [InlineKeyboardButton("\U0001F50C Connected IPs", callback_data="conn_ips"),
         InlineKeyboardButton("\u2699\uFE0F Status", callback_data="sys_status")],
        [InlineKeyboardButton("\U0001F30D Domain", callback_data="domain"),
         InlineKeyboardButton("\U0001F512 SSL", callback_data="ssl")],
        [InlineKeyboardButton("\U0001F4E2 Banner", callback_data="banner"),
         InlineKeyboardButton("\U0001F6E0 Fix WebSocket", callback_data="fix_ws")],
        [InlineKeyboardButton("\U0001F4E6 Install Components", callback_data="install"),
         InlineKeyboardButton("\U0001F9E8 Uninstall Panel", callback_data="uninstall")],
    ]
    if is_super(uid):
        rows.append([InlineKeyboardButton("\U0001F451 Admin Management", callback_data="admin_mgmt")])
    return InlineKeyboardMarkup(rows)

def admins_text():
    cfg = load_config()
    admins = load_admins()
    lines = ["\U0001F451 *Admin Management*\n"]
    for a in admins:
        tag = " (Super Admin)" if a == cfg.get("super_admin") else ""
        lines.append(f"\u2022 `{a}`{tag}")
    return "\n".join(lines)

def admin_menu_keyboard():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("\u2795 Add Admin", callback_data="add_admin"),
         InlineKeyboardButton("\u2796 Remove Admin", callback_data="remove_admin")],
        [InlineKeyboardButton("\u2B05\uFE0F Back", callback_data="back_main")],
    ])

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    if not is_admin(uid):
        await update.message.reply_text("\u26D4 Access Denied. Aap authorized admin nahi hain.")
        return
    context.user_data['flow'] = None
    await update.message.reply_text(
        f"\U0001F44B Welcome to {PANEL_NAME}\n\nApna option chunein:",
        reply_markup=main_menu_keyboard(uid),
    )

async def cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    context.user_data['flow'] = None
    await update.message.reply_text("Cancelled.")

async def execute_flow(flow, data, update: Update):
    if flow == "add_user":
        ok, info = add_user(data["username"], data["password"], data["days"], data["ip_limit"], data["gb_limit"])
        if ok:
            dom = get_domain()
            payload = f"GET /raretriccks HTTP/1.1[crlf]Host: {dom}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
            msg = (
                f"\u2705 *Account Created*\n\n"
                f"Domain: `{dom}`\n"
                f"Username: `{data['username']}`\n"
                f"Password: `{data['password']}`\n"
                f"Expiry: `{info}`\n"
                f"IP Limit: `{data['ip_limit']}`\n"
                f"GB Limit: `{data['gb_limit']}`\n\n"
                f"SSH Direct: 22, 109, 447\nSSH WS (HTTP): 80\nSSH WS (SSL): 443\n\n"
                f"Payload:\n`{payload}`"
            )
        else:
            msg = f"\u274C User create fail: {info}"
        await update.message.reply_text(msg, parse_mode="Markdown", reply_markup=back_keyboard())
    elif flow == "renew_user":
        ok = renew_user(data["username"], data["days"])
        await update.message.reply_text(
            "\u2705 Renewed." if ok else "\u274C User not found.", reply_markup=back_keyboard()
        )
    elif flow == "ip_limit":
        ok = update_conf_field(data["username"], "IP_LIMIT", data["value"])
        await update.message.reply_text(
            "\u2705 IP limit updated." if ok else "\u274C User config not found.",
            reply_markup=back_keyboard(),
        )
    elif flow == "gb_limit":
        ok = update_conf_field(data["username"], "GB_LIMIT", data["value"])
        await update.message.reply_text(
            "\u2705 GB limit updated." if ok else "\u274C User config not found.",
            reply_markup=back_keyboard(),
        )
    elif flow == "domain":
        set_domain(data["value"])
        await update.message.reply_text(f"\u2705 Domain set to {data['value']}", reply_markup=back_keyboard())
    elif flow == "banner":
        with open(BANNER_FILE, "w") as f:
            f.write(data["value"])
        sh(["systemctl", "restart", "dropbear"])
        sh(["systemctl", "restart", "ssh"])
        await update.message.reply_text("\u2705 Banner updated.", reply_markup=back_keyboard())
    elif flow == "add_admin":
        try:
            new_id = int(data["value"])
        except ValueError:
            await update.message.reply_text("\u274C Invalid ID.")
            return
        admins = load_admins()
        if new_id in admins:
            await update.message.reply_text("\u26A0\uFE0F Already an admin.")
        else:
            admins.append(new_id)
            save_admins(admins)
            await update.message.reply_text(f"\u2705 Admin {new_id} added.", reply_markup=admin_menu_keyboard())

async def text_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    if not is_admin(uid):
        return
    flow = context.user_data.get('flow')
    if not flow:
        return
    step = context.user_data.get('step', 0)
    field, _ = FLOWS[flow][step]
    context.user_data.setdefault('data', {})[field] = update.message.text.strip()
    step += 1
    if step < len(FLOWS[flow]):
        context.user_data['step'] = step
        await update.message.reply_text(FLOWS[flow][step][1])
        return

    data = context.user_data['data']
    context.user_data['flow'] = None

    if flow == "del_user":
        username = data["username"]
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("\u2705 Confirm Delete", callback_data=f"do_del:{username}"),
            InlineKeyboardButton("\u274C Cancel", callback_data="back_main"),
        ]])
        await update.message.reply_text(f"\u26A0\uFE0F '{username}' delete karna confirm karein:", reply_markup=kb)
        return

    if flow == "remove_admin":
        try:
            target = int(data["value"])
        except ValueError:
            await update.message.reply_text("\u274C Invalid ID.")
            return
        cfg = load_config()
        if target == cfg.get("super_admin"):
            await update.message.reply_text("\u274C Super admin remove nahi ho sakta.")
            return
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("\u2705 Confirm Remove", callback_data=f"rm_admin:{target}"),
            InlineKeyboardButton("\u274C Cancel", callback_data="back_main"),
        ]])
        await update.message.reply_text(f"\u26A0\uFE0F Admin {target} remove karna confirm karein:", reply_markup=kb)
        return

    await execute_flow(flow, data, update)

async def button_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    uid = q.from_user.id
    if not is_admin(uid):
        await q.answer("Access denied.", show_alert=True)
        return
    data = q.data
    await q.answer()

    if data == "back_main":
        context.user_data['flow'] = None
        await q.edit_message_text("\U0001F4CB Main Menu", reply_markup=main_menu_keyboard(uid))
    elif data in FLOWS:
        context.user_data['flow'] = data
        context.user_data['step'] = 0
        context.user_data['data'] = {}
        field, prompt = FLOWS[data][0]
        await q.edit_message_text(prompt)
    elif data == "list_users":
        await q.edit_message_text(list_users_text(), reply_markup=back_keyboard())
    elif data == "conn_ips":
        await q.edit_message_text(connected_ips_text(), reply_markup=back_keyboard())
    elif data == "sys_status":
        await q.edit_message_text(status_text(), reply_markup=back_keyboard())
    elif data == "ssl":
        await q.edit_message_text("\U0001F512 SSL issue ho raha hai, wait karein...")
        ok, msg = await asyncio.to_thread(setup_ssl)
        await q.message.reply_text(("\u2705 " if ok else "\u274C ") + msg, reply_markup=back_keyboard())
    elif data == "fix_ws":
        msg = fix_websocket()
        await q.edit_message_text(f"\u2705 {msg}", reply_markup=back_keyboard())
    elif data == "install":
        await q.edit_message_text("\U0001F4E6 Poora system install ho raha hai (packages + Dropbear + WebSocket + Auto-Kill), 2-5 min lagega...")
        await asyncio.to_thread(install_components_sync)
        await q.message.reply_text(
            "\u2705 Installation complete! Packages, Dropbear, Banner, WebSocket Proxy aur "
            "Auto-Kill/Bandwidth service sab deploy ho gaye hain.\n"
            "\u2139\uFE0F Agar aapne pehle domain set nahi kiya to Nginx SSL block abhi apply nahi hoga "
            "\u2014 pehle Domain option se domain set karein, phir SSL issue karein.",
            reply_markup=back_keyboard(),
        )
    elif data == "uninstall":
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("\u2705 Haan, Uninstall karein", callback_data="do_uninstall"),
            InlineKeyboardButton("\u274C Cancel", callback_data="back_main"),
        ]])
        await q.edit_message_text(
            "\u26A0\uFE0F Yeh sab kuch permanently remove kar dega (users, services, config, is bot samet). "
            "Confirm karein:",
            reply_markup=kb,
        )
    elif data == "do_uninstall":
        await q.edit_message_text("\U0001F9E8 Uninstalling...")
        await asyncio.to_thread(uninstall_all)
        await q.message.reply_text("\u2705 Uninstall complete. Bot khud bhi band ho raha hai.")
        schedule_self_removal()
    elif data == "admin_mgmt":
        if not is_super(uid):
            await q.answer("Sirf Super Admin ke liye.", show_alert=True)
            return
        await q.edit_message_text(admins_text(), parse_mode="Markdown", reply_markup=admin_menu_keyboard())
    elif data.startswith("do_del:"):
        username = data.split(":", 1)[1]
        delete_user(username)
        await q.edit_message_text(f"\u2705 User {username} deleted.", reply_markup=back_keyboard())
    elif data.startswith("rm_admin:"):
        target = int(data.split(":", 1)[1])
        cfg = load_config()
        if target == cfg.get("super_admin"):
            await q.answer("Super admin remove nahi ho sakta.", show_alert=True)
            return
        admins = load_admins()
        if target in admins:
            admins.remove(target)
            save_admins(admins)
        await q.edit_message_text(admins_text(), parse_mode="Markdown", reply_markup=admin_menu_keyboard())

def main():
    cfg = load_config()
    app = Application.builder().token(cfg["token"]).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("cancel", cancel))
    app.add_handler(CallbackQueryHandler(button_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))
    app.run_polling()

if __name__ == "__main__":
    main()
PY_EOF
    chmod +x /usr/local/bin/tgbot.py

    cat << 'SVC_EOF' > /etc/systemd/system/tgbot.service
[Unit]
Description=RareTriccks Telegram Bot
After=network.target

[Service]
ExecStart=/opt/rr-tgbot-venv/bin/python3 /usr/local/bin/tgbot.py
Restart=always

[Install]
WantedBy=multi-user.target
SVC_EOF
}

setup_telegram_bot() {
    clear
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}       ${PANEL_NAME} - TELEGRAM BOT SETUP          ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " 1) Install / Configure Bot (Token + Super Admin ID)"
    echo -e " 2) Restart Bot Service"
    echo -e " 3) Stop Bot Service"
    echo -e " 4) View Bot Status"
    echo -e " 5) Back"
    echo -e "${CYAN}====================================================${NC}"
    read -rp "Option [1-5]: " tb_opt

    case $tb_opt in
        1)
            echo -e "${YELLOW}Tip: Bot Token @BotFather se milta hai. Apna Telegram User ID @userinfobot se maloom karein.${NC}"
            read -rp "Telegram Bot Token enter karein: " bot_token
            read -rp "Apna Telegram User ID enter karein (yeh Super Admin banega): " super_id

            if [[ -z "$bot_token" || -z "$super_id" ]]; then
                echo -e "${RED}[ERROR] Token aur ID dono zaroori hain!${NC}"
                press_any_key
                return
            fi
            if ! [[ "$super_id" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}[ERROR] User ID sirf numbers ka hona chahiye!${NC}"
                press_any_key
                return
            fi

            echo -e "${BLUE}[1/5] Installing Python & venv...${NC}"
            apt install -y python3 python3-venv python3-pip

            echo -e "${BLUE}[2/5] Creating isolated virtual environment...${NC}"
            rm -rf /opt/rr-tgbot-venv
            python3 -m venv /opt/rr-tgbot-venv
            /opt/rr-tgbot-venv/bin/pip install --upgrade pip
            /opt/rr-tgbot-venv/bin/pip install "python-telegram-bot==20.7"

            if [[ $? -ne 0 ]]; then
                echo -e "${RED}[ERROR] Bot dependencies install nahi hui! Internet connection ya apt sources check karein.${NC}"
                press_any_key
                return
            fi

            echo -e "${BLUE}[3/5] Writing config...${NC}"
            mkdir -p /etc/raretriccks/tgbot
            cat << CFG_EOF > /etc/raretriccks/tgbot/config.json
{"token": "${bot_token}", "super_admin": ${super_id}}
CFG_EOF
            echo "[${super_id}]" > /etc/raretriccks/tgbot/admins.json

            echo -e "${BLUE}[4/5] Installing bot script...${NC}"
            install_tgbot_script

            echo -e "${BLUE}[5/5] Starting Telegram bot service...${NC}"
            systemctl daemon-reload
            systemctl enable tgbot
            systemctl restart tgbot

            echo -e "\n${GREEN}[SUCCESS] Telegram Bot Active! Apne bot ko Telegram par /start bhejein.${NC}"
            echo -e "${CYAN}Sirf aapki ID (${super_id}) ke paas Admin Management access hoga.${NC}"
            press_any_key
            ;;
        2)
            systemctl restart tgbot
            echo -e "${GREEN}Bot restarted.${NC}"
            press_any_key
            ;;
        3)
            systemctl stop tgbot
            echo -e "${YELLOW}Bot stopped.${NC}"
            press_any_key
            ;;
        4)
            clear
            systemctl status tgbot --no-pager
            press_any_key
            ;;
        *) return ;;
    esac
}

