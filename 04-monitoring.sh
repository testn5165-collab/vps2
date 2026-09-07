#!/bin/bash
# RareTriccks VPN Panel - 04-monitoring.sh
# Connected-IPs view + bandwidth/expiry/lock status view.
source /etc/raretriccks/00-common.sh

check_connected_ips() {
    clear
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}                     CONNECTED IPS & ACTIVE USERS                   ${NC}"
    echo -e "${CYAN}====================================================================${NC}"

    echo -e "${GREEN}Active Online SSH / WebSocket Sessions:${NC}"
    echo -e "${CYAN}--------------------------------------------------------------------${NC}"

    local total_count=0
    local raw_logs=""
    if command -v journalctl &>/dev/null; then
        raw_logs=$(journalctl -u dropbear --no-pager -n 400 2>/dev/null)
    fi
    [[ -f "/var/log/auth.log" ]] && raw_logs+=$'\n'$(cat /var/log/auth.log 2>/dev/null)

    mapfile -t external_ips < <(ss -tnp 2>/dev/null | grep -E ":(80|443|2082)" | grep "ESTAB" | awk '{print $5}' | cut -d: -f1 | grep -vE "^127\.|^::1" | sort -u)
    mapfile -t ws_logged_ips < <(grep -oP "(?<=REAL_IP:)\S+" /var/log/ws-proxy.log 2>/dev/null | tail -n 20 | sort -u)

    local real_ip_pool=($(echo "${external_ips[@]} ${ws_logged_ips[@]}" | tr ' ' '\n' | sort -u))
    local ip_index=0

    for pid in $(ps aux | grep dropbear | grep -v grep | awk '{print $2}'); do
        local user_match=$(echo "$raw_logs" | grep "dropbear\[$pid\]" | grep -i "Password auth succeeded" | tail -n 1)

        if [[ -n "$user_match" ]]; then
            local username=$(echo "$user_match" | grep -oP "(?<=for ')\w+(?=')" || echo "$user_match" | awk '{for(i=1;i<=NF;i++) if($i=="for") print $(i+1)}')
            local logged_ip=$(echo "$user_match" | grep -oP "(?<=from )\S+(?=:)")
            local final_ip="$logged_ip"

            if [[ "$logged_ip" == "127.0.0.1" || -z "$logged_ip" ]]; then
                if [[ ${#real_ip_pool[@]} -gt 0 && $ip_index -lt ${#real_ip_pool[@]} ]]; then
                    final_ip="${real_ip_pool[$ip_index]} (WS Tunnel)"
                    ip_index=$((ip_index + 1))
                else
                    final_ip="WS-Proxy Client"
                fi
            fi

            if [[ -n "$username" ]]; then
                printf " User: %-18s | IP/Source: %-25s [ONLINE]\n" "$username" "$final_ip"
                total_count=$((total_count + 1))
            fi
        fi
    done

    local active_sockets=$(ss -tnp 2>/dev/null | grep -E ":(109|447|22)" | grep -i "ESTAB" | wc -l)
    if [[ $total_count -lt $active_sockets ]]; then
        echo -e "${YELLOW} Detected ${active_sockets} Active Tunnel Socket(s) connected to Dropbear Core.${NC}"
        [[ $total_count -eq 0 ]] && total_count=$active_sockets
    fi

    if [[ $total_count -eq 0 ]]; then
        echo -e "${YELLOW} Filhal koi active user connected nahi hai.${NC}"
    fi

    echo -e "${CYAN}====================================================================${NC}"
    echo -e " Total Active Sessions: ${BOLD}${total_count}${NC}"
    echo -e "${CYAN}====================================================================${NC}"
    press_any_key
}

check_gb_usage() {
    clear
    echo -e "${CYAN}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}                USER BANDWIDTH / EXPIRY & LOCK STATUS               ${NC}"
    echo -e "${CYAN}====================================================================${NC}"

    printf " %-14s | %-7s | %-10s | %-12s | %-10s\n" "USERNAME" "IP LIMIT" "DATA USED" "DATA LIMIT" "STATUS"
    echo -e "${CYAN}--------------------------------------------------------------------${NC}"

    mkdir -p /etc/raretriccks/users

    for conf in /etc/raretriccks/users/*.conf; do
        [[ -e "$conf" ]] || continue
        local uname=$(basename "$conf" .conf)
        local limit=$(grep "^GB_LIMIT=" "$conf" | cut -d= -f2)
        local ip_l=$(grep "^IP_LIMIT=" "$conf" | cut -d= -f2)
        local used_mb=$(grep "^USED_MB=" "$conf" | cut -d= -f2)

        [[ -z "$limit" ]] && limit="Unlimited"
        [[ -z "$ip_l" ]] && ip_l="1"
        [[ -z "$used_mb" ]] && used_mb="0"

        local used_gb=$(python3 -c "print(f'{$used_mb/1024:.2f}')")

        local status="${GREEN}Active${NC}"
        if id "$uname" &>/dev/null; then
            if passwd -S "$uname" 2>/dev/null | grep -q "L"; then
                status="${RED}LOCKED${NC}"
            fi
        else
            status="${RED}Deleted${NC}"
        fi

        printf " %-14s | %-8s | %-7s GB | %-9s GB | %b\n" "$uname" "$ip_l" "$used_gb" "$limit" "$status"
    done

    echo -e "${CYAN}====================================================================${NC}"
    press_any_key
}

