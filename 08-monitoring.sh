#!/bin/bash
# RareTriccks VPN Panel - 08-monitoring.sh
# Bandwidth/IP-limit auto-kill tracker for both SSH and V2Ray users.
# NOTE: once Xray access-log shows the REAL client IP (see 06-xray-core.sh +
# 05-realip-tracker.sh proxy-protocol fix), get_v2ray_active_ips() below
# automatically becomes accurate too - no changes needed here.
source /etc/raretriccks/00-common.sh

install_python_tracker() {
cat << 'EOF' > /usr/local/bin/autokill.py
import os
import sys
import time
import subprocess
import re
import json
import datetime

USER_DIR = "/etc/raretriccks/users"
V2USER_DIR = "/etc/raretriccks/v2users"
XRAY_CONFIG = "/usr/local/etc/xray/config.json"
XRAY_ACCESS_LOG = "/var/log/xray/access.log"
XRAY_API_ADDR = "127.0.0.1:10085"

def get_auth_logs():
    raw = ""
    try:
        raw = subprocess.check_output(["journalctl", "-u", "dropbear", "--no-pager", "-n", "300"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
    except Exception:
        pass
    if os.path.exists("/var/log/auth.log"):
        try:
            with open("/var/log/auth.log", "r", encoding="utf-8", errors="ignore") as f:
                raw += "\n" + f.read()
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
                        m = re.search(r"for \x27(\w+)\x27", last_line)
                        if not m:
                            m = re.search(r"for (\w+)", last_line)
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


def xray_strip_client(email):
    """Remove a client (by email/username) from every inbound in the xray config, then restart."""
    try:
        with open(XRAY_CONFIG, "r") as f:
            cfg = json.load(f)
        changed = False
        for ib in cfg.get("inbounds", []):
            clients = ib.get("settings", {}).get("clients")
            if clients:
                new_clients = [c for c in clients if c.get("email") != email]
                if len(new_clients) != len(clients):
                    ib["settings"]["clients"] = new_clients
                    changed = True
        if changed:
            with open(XRAY_CONFIG, "w") as f:
                json.dump(cfg, f, indent=2)
            subprocess.call(["systemctl", "restart", "xray"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass


def get_v2ray_delta_mb(email):
    """
    Reads (and resets) the per-user traffic counter via xray's gRPC stats API.
    Requires the 'api'/'stats'/'policy' blocks + api-in inbound added in configure_xray().
    NOTE: exact CLI flags can differ slightly between xray-core releases -
    verify with `xray api statsquery --help` on the target box if this stops matching.
    """
    total_bytes = 0
    try:
        out = subprocess.check_output(
            ["xray", "api", "statsquery",
             "--server=" + XRAY_API_ADDR,
             "-pattern", "user>>>{}>>>traffic".format(email),
             "-reset"],
            stderr=subprocess.DEVNULL, timeout=5
        ).decode("utf-8", errors="ignore")
        data = json.loads(out)
        for stat in data.get("stat", []):
            try:
                total_bytes += int(stat.get("value", 0))
            except Exception:
                pass
    except Exception:
        pass
    return total_bytes / (1024.0 * 1024.0)


def get_v2ray_active_ips(email, log_lines):
    """Approximates 'currently connected' source IPs by scanning the recent xray access log tail."""
    ips = set()
    needle = "email: {}".format(email)
    for line in log_lines:
        if needle in line:
            m = re.search(r"from (\d+\.\d+\.\d+\.\d+):", line)
            if m:
                ips.add(m.group(1))
    return ips


def process_v2ray_users():
    if not os.path.exists(V2USER_DIR):
        return

    log_lines = []
    try:
        with open(XRAY_ACCESS_LOG, "r", errors="ignore") as f:
            log_lines = f.readlines()[-1500:]
    except Exception:
        pass

    for fname in os.listdir(V2USER_DIR):
        if not fname.endswith(".conf"):
            continue
        uname = fname[:-5]
        conf_path = os.path.join(V2USER_DIR, fname)

        data = {}
        try:
            with open(conf_path, "r") as f:
                lines = f.readlines()
        except Exception:
            continue

        for line in lines:
            line = line.strip()
            if "=" in line:
                k, v = line.split("=", 1)
                data[k] = v

        if data.get("LOCKED", "0") == "1":
            continue

        ip_limit = 0
        try:
            ip_limit = int(data.get("IP_LIMIT", "0") or 0)
        except Exception:
            pass
        gb_limit = data.get("GB_LIMIT", "Unlimited")
        used_mb = 0.0
        try:
            used_mb = float(data.get("USED_MB", "0.0") or 0.0)
        except Exception:
            pass
        expire_date = data.get("EXPIRE_DATE", "Unlimited")

        delta_mb = get_v2ray_delta_mb(uname)
        if delta_mb > 0:
            used_mb += delta_mb

        active_ips = get_v2ray_active_ips(uname, log_lines)

        breach = False
        if gb_limit != "Unlimited":
            try:
                if used_mb >= float(gb_limit) * 1024.0:
                    breach = True
            except Exception:
                pass
        if ip_limit > 0 and len(active_ips) > ip_limit:
            breach = True
        if expire_date != "Unlimited":
            try:
                exp = datetime.datetime.strptime(expire_date, "%Y-%m-%d").date()
                if datetime.date.today() >= exp:
                    breach = True
            except Exception:
                pass

        data["USED_MB"] = "{:.2f}".format(used_mb)
        if breach:
            data["LOCKED"] = "1"
            xray_strip_client(uname)

        try:
            with open(conf_path, "w") as f:
                for k, v in data.items():
                    f.write("{}={}\n".format(k, v))
        except Exception:
            pass


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
                        new_lines.append(f"USED_MB={used_mb:.2f}\n")
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

        process_v2ray_users()

    except Exception:
        pass

    time.sleep(3)
EOF
    chmod +x /usr/local/bin/autokill.py

cat << 'EOF' > /etc/systemd/system/autokill.service
[Unit]
Description=RareTriccks Auto-Kill & Bandwidth Tracking Service
After=network.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/autokill.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable autokill
    systemctl restart autokill
}

WS_SSH_PORT=2082          
