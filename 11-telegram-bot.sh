#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - 11-telegram-bot.sh
# Telegram Bot: user management (SSH+V2Ray via 09-user-manager.sh) + notifications
#
# Commands (admin chat ID se hi kaam karenge):
#   /adduser <username> <password> <days> <ip_limit> <gb_limit>
#   /deluser <username>
#   /renew   <username> <extra_days>
#   /listusers
#   /status
#
# Notifications (proactive, cron se):
#   - User ka plan expire hone se 1 din pehle / expire hone par admin ko alert
#
# Usage: bash 11-telegram-bot.sh   (run after install-all.sh, root chahiye)
# ==============================================================================
set -e
source /etc/raretriccks/00-common.sh

BOT_DIR="${BASE_DIR}/telegram-bot"
BOT_CONF="${BOT_DIR}/bot.conf"
BOT_SCRIPT="${BOT_DIR}/bot.sh"
NOTIFY_SCRIPT="${BOT_DIR}/notify.sh"
EXPIRY_SCRIPT="${BOT_DIR}/expiry-check.sh"
BOT_SERVICE="/etc/systemd/system/raretriccks-bot.service"
USER_MGR="${BASE_DIR}/09-user-manager.sh"

mkdir -p "$BOT_DIR"

echo -e "${CYAN}====================================================${NC}"
echo -e "${YELLOW}   RARETRICCKS - Telegram Bot Setup${NC}"
echo -e "${CYAN}====================================================${NC}"
read -rp "Bot Token (BotFather se): " BOT_TOKEN
read -rp "Admin Telegram Chat ID: " ADMIN_ID

if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" ]]; then
    echo -e "${RED}[ERROR] Bot Token aur Admin Chat ID dono zaroori hain.${NC}"
    exit 1
fi

echo -e "${YELLOW}-> curl, jq install ho rahe hain...${NC}"
apt-get update -y >/dev/null 2>&1
apt-get install -y curl jq >/dev/null 2>&1

cat > "$BOT_CONF" <<EOF
BOT_TOKEN="$BOT_TOKEN"
ADMIN_ID="$ADMIN_ID"
EOF
chmod 600 "$BOT_CONF"

# ------------------------------------------------------------------
# notify.sh  -> admin ko free-form message bhejne ke liye (HTML safe)
# ------------------------------------------------------------------
cat > "$NOTIFY_SCRIPT" <<'NOTIFY'
#!/bin/bash
# Usage: notify.sh "<b>bold</b> ya plain text"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/bot.conf"
MSG="$1"
[[ -z "$MSG" ]] && exit 0
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${ADMIN_ID}" \
  -d parse_mode="HTML" \
  --data-urlencode text="$MSG" > /dev/null
NOTIFY
chmod +x "$NOTIFY_SCRIPT"

# ------------------------------------------------------------------
# bot.sh -> polling bot jo commands sunta hai
# ------------------------------------------------------------------
cat > "$BOT_SCRIPT" <<BOTEOF
#!/bin/bash
source /etc/raretriccks/00-common.sh
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
source "\$DIR/bot.conf"
USER_MGR="$USER_MGR"
API="https://api.telegram.org/bot\${BOT_TOKEN}"
OFFSET=0

html_escape() {
    local s="\$1"
    s="\${s//&/&amp;}"; s="\${s//</&lt;}"; s="\${s//>/&gt;}"
    echo "\$s"
}

send() {
    local chat="\$1" text="\$2"
    curl -s -X POST "\${API}/sendMessage" \\
        -d chat_id="\$chat" \\
        -d parse_mode="HTML" \\
        --data-urlencode text="\$text" > /dev/null
}

is_admin() { [[ "\$1" == "\$ADMIN_ID" ]]; }

while true; do
    UPDATES=\$(curl -s "\${API}/getUpdates?timeout=30&offset=\$((OFFSET+1))")
    LEN=\$(echo "\$UPDATES" | jq '.result | length' 2>/dev/null)
    [[ -z "\$LEN" || "\$LEN" == "null" ]] && { sleep 3; continue; }

    for ((i=0; i<LEN; i++)); do
        UPD=\$(echo "\$UPDATES" | jq ".result[\$i]")
        UPDATE_ID=\$(echo "\$UPD" | jq '.update_id')
        OFFSET=\$UPDATE_ID
        CHAT_ID=\$(echo "\$UPD" | jq '.message.chat.id')
        TEXT=\$(echo "\$UPD" | jq -r '.message.text // empty')
        [[ -z "\$TEXT" ]] && continue

        if ! is_admin "\$CHAT_ID"; then
            send "\$CHAT_ID" "❌ Unauthorized. Ye bot sirf admin ke liye hai."
            continue
        fi

        CMD=\$(echo "\$TEXT" | awk '{print \$1}')
        case "\$CMD" in
            /start|/help)
                send "\$CHAT_ID" "<b>RARETRICCKS Bot</b>
/adduser username password days ip_limit gb_limit
/deluser username
/renew username extra_days
/listusers
/status"
                ;;
            /adduser)
                ARGS=\$(echo "\$TEXT" | cut -d' ' -f2-)
                if [[ -z "\$ARGS" || "\$ARGS" == "\$TEXT" ]]; then
                    send "\$CHAT_ID" "Usage: /adduser username password days ip_limit gb_limit"
                    continue
                fi
                OUT=\$(bash "\$USER_MGR" add \$ARGS 2>&1)
                send "\$CHAT_ID" "<pre>\$(html_escape "\$OUT")</pre>"
                ;;
            /deluser)
                UNAME=\$(echo "\$TEXT" | awk '{print \$2}')
                if [[ -z "\$UNAME" ]]; then
                    send "\$CHAT_ID" "Usage: /deluser username"
                    continue
                fi
                OUT=\$(bash "\$USER_MGR" del "\$UNAME" 2>&1)
                send "\$CHAT_ID" "<pre>\$(html_escape "\$OUT")</pre>"
                ;;
            /renew)
                UNAME=\$(echo "\$TEXT" | awk '{print \$2}')
                XDAYS=\$(echo "\$TEXT" | awk '{print \$3}')
                if [[ -z "\$UNAME" || -z "\$XDAYS" ]]; then
                    send "\$CHAT_ID" "Usage: /renew username extra_days"
                    continue
                fi
                if ! id "\$UNAME" &>/dev/null; then
                    send "\$CHAT_ID" "❌ User '\$UNAME' nahi mila."
                    continue
                fi
                NEW_EXP=\$(date -d "+\${XDAYS} days" +%Y-%m-%d)
                usermod -e "\$NEW_EXP" "\$UNAME"
                passwd -u "\$UNAME" &>/dev/null
                sed -i "s/^EXP_DATE=.*/EXP_DATE=\${NEW_EXP}/" "\${USERS_DIR}/\${UNAME}.conf" 2>/dev/null
                send "\$CHAT_ID" "✅ '\$UNAME' renewed till <b>\$NEW_EXP</b>."
                ;;
            /listusers)
                LIST="No user found."
                if [[ -d "\$USERS_DIR" ]] && ls "\$USERS_DIR"/*.conf >/dev/null 2>&1; then
                    LIST=""
                    for f in "\$USERS_DIR"/*.conf; do
                        u=\$(basename "\$f" .conf)
                        st="Deleted"
                        if id "\$u" &>/dev/null; then
                            st=\$(passwd -S "\$u" 2>/dev/null | grep -q " L " && echo "LOCKED" || echo "Active")
                        fi
                        exp=\$(grep EXP_DATE "\$f" | cut -d= -f2)
                        LIST="\${LIST}\${u}  |  Expiry: \${exp}  |  \${st}
"
                    done
                fi
                send "\$CHAT_ID" "<pre>\$(html_escape "\$LIST")</pre>"
                ;;
            /status)
                DOMAIN=\$(get_domain)
                STATUS="Domain: \${DOMAIN}
"
                for svc in nginx dropbear ws-proxy stunnel4 xray autokill badvpn-udpgw; do
                    st=\$(systemctl is-active "\$svc" 2>/dev/null)
                    STATUS="\${STATUS}\${svc}: \${st}
"
                done
                send "\$CHAT_ID" "<pre>\$(html_escape "\$STATUS")</pre>"
                ;;
            *)
                send "\$CHAT_ID" "Unknown command. /help bhejo."
                ;;
        esac
    done
done
BOTEOF
chmod +x "$BOT_SCRIPT"

# ------------------------------------------------------------------
# expiry-check.sh -> proactive notifications (cron se daily chalega)
# ------------------------------------------------------------------
cat > "$EXPIRY_SCRIPT" <<'EXPEOF'
#!/bin/bash
source /etc/raretriccks/00-common.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TODAY_TS=$(date +%s)

[[ -d "$USERS_DIR" ]] || exit 0
for f in "$USERS_DIR"/*.conf; do
    [[ -e "$f" ]] || continue
    uname=$(basename "$f" .conf)
    exp=$(grep EXP_DATE "$f" | cut -d= -f2)
    exp_ts=$(date -d "$exp" +%s 2>/dev/null) || continue
    diff_days=$(( (exp_ts - TODAY_TS) / 86400 ))

    if [[ $diff_days -eq 1 ]]; then
        "$DIR/notify.sh" "⚠️ User <b>${uname}</b> ka plan <b>kal</b> expire ho raha hai (${exp})."
    elif [[ $diff_days -eq 0 ]]; then
        "$DIR/notify.sh" "⚠️ User <b>${uname}</b> ka plan <b>aaj</b> expire ho raha hai (${exp})."
    elif [[ $diff_days -eq -1 ]]; then
        "$DIR/notify.sh" "⛔ User <b>${uname}</b> ka plan expire ho chuka hai (${exp})."
    fi
done
EXPEOF
chmod +x "$EXPIRY_SCRIPT"

# ------------------------------------------------------------------
# systemd service -> bot hamesha chalta rahe, reboot pe bhi
# ------------------------------------------------------------------
cat > "$BOT_SERVICE" <<EOF
[Unit]
Description=RARETRICCKS Telegram Bot
After=network.target

[Service]
ExecStart=/bin/bash ${BOT_SCRIPT}
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable raretriccks-bot >/dev/null 2>&1
systemctl restart raretriccks-bot

# ------------------------------------------------------------------
# cron -> daily expiry check (roz subah 9 baje)
# ------------------------------------------------------------------
( crontab -l 2>/dev/null | grep -v "$EXPIRY_SCRIPT" ; echo "0 9 * * * bash $EXPIRY_SCRIPT" ) | crontab -

sleep 1
"$NOTIFY_SCRIPT" "✅ Telegram bot install ho gaya aur chal raha hai on <b>$(hostname)</b>."

echo -e "\n${GREEN}[SUCCESS] Telegram bot LIVE hai.${NC}"
echo -e "${CYAN}Apne bot ko Telegram par /help bhej ke test karo.${NC}"
echo -e "${YELLOW}Service manage karne ke commands:${NC}"
echo -e "  systemctl status raretriccks-bot"
echo -e "  systemctl restart raretriccks-bot"
echo -e "  journalctl -u raretriccks-bot -f"
