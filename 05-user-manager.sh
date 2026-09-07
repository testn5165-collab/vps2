#!/bin/bash
# RareTriccks VPN Panel - 05-user-manager.sh
# Add/Delete/Renew users, IP & GB limit management.
source /etc/raretriccks/00-common.sh
source /etc/raretriccks/04-monitoring.sh

user_menu() {
    local cur_dom=$(get_domain)
    while true; do
        clear
        echo -e "${CYAN}====================================================${NC}"
        echo -e "${YELLOW}       ${PANEL_NAME} - USER MANAGEMENT           ${NC}"
        echo -e "${CYAN}====================================================${NC}"
        echo -e " 1) Add New User"
        echo -e " 2) Delete User"
        echo -e " 3) Check Connected IPs & Active Online Users"
        echo -e " 4) Check User Status, Quota & Limits"
        echo -e " 5) Renew Account Expiry Days"
        echo -e " 6) Extend / Modify IP Limit (Auto Unlock)"
        echo -e " 7) Extend / Modify GB Data Quota (Auto Unlock)"
        echo -e " 8) Back to Main Menu"
        echo -e "${CYAN}====================================================${NC}"
        read -rp "Option [1-8]: " u_choice

        case $u_choice in
            1)
                read -rp "Username: " username
                read -rp "Password: " password
                read -rp "Days Expiry (e.g. 30): " days
                read -rp "Max IP Limit (e.g. 1 ya 2): " ip_limit
                read -rp "Quota / Data Limit in GB (e.g. 0.5 ya 50): " gb_limit

                exp_date=$(date -d "+$days days" +%Y-%m-%d)

                useradd -M -s /bin/bash -e "$exp_date" "$username"
                if [[ $? -ne 0 ]]; then
                    echo -e "${RED}[ERROR] User create nahi hua! Upar wala error dekhein (username already exists ho sakta hai).${NC}"
                    press_any_key
                    continue
                fi
                echo "$username:$password" | chpasswd
                if [[ $? -ne 0 ]]; then
                    echo -e "${RED}[ERROR] Password set nahi hua!${NC}"
                fi

                mkdir -p /etc/raretriccks/users
                echo "IP_LIMIT=$ip_limit" > "/etc/raretriccks/users/${username}.conf"
                echo "GB_LIMIT=$gb_limit" >> "/etc/raretriccks/users/${username}.conf"
                echo "USED_MB=0.0" >> "/etc/raretriccks/users/${username}.conf"

                echo -e "\n${GREEN}====================================================${NC}"
                echo -e "${YELLOW}           ACCOUNT CREATED BY RARETRICCKS           ${NC}"
                echo -e "${GREEN}====================================================${NC}"
                echo -e " Domain       : ${CYAN}${cur_dom}${NC}"
                echo -e " Username     : ${CYAN}${username}${NC}"
                echo -e " Password     : ${CYAN}${password}${NC}"
                echo -e " Expired On   : ${CYAN}${exp_date}${NC}"
                echo -e " Max IP Limit : ${CYAN}${ip_limit} Device(s)${NC}"
                echo -e " Data Limit   : ${CYAN}${gb_limit} GB${NC}"
                echo -e "${CYAN}----------------------------------------------------${NC}"
                echo -e " SSH Direct   : ${CYAN}22, 109, 447${NC}"
                echo -e " SSH WS (HTTP): ${CYAN}80${NC}"
                echo -e " SSH WS (SSL) : ${CYAN}443${NC}"
                echo -e "${CYAN}----------------------------------------------------${NC}"
                echo -e " Payload      :"
                echo -e "${CYAN}GET ${CUSTOM_PATH} HTTP/1.1[crlf]Host: ${cur_dom}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]${NC}"
                echo -e "${CYAN}----------------------------------------------------${NC}"
                press_any_key
                ;;
            2)
                echo -e "${CYAN}--- Existing Users ---${NC}"
                mkdir -p /etc/raretriccks/users
                local found=0
                for conf in /etc/raretriccks/users/*.conf; do
                    [[ -e "$conf" ]] || continue
                    local uname=$(basename "$conf" .conf)
                    local exp=$(chage -l "$uname" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
                    [[ -z "$exp" ]] && exp="N/A"
                    printf "  - %-18s (expires: %s)\n" "$uname" "$exp"
                    found=1
                done
                [[ $found -eq 0 ]] && echo -e "${YELLOW}  Koi user nahi mila.${NC}"
                echo -e "${CYAN}----------------------${NC}"
                read -rp "Username to delete: " username
                if [[ -z "$username" ]]; then
                    echo -e "${RED}[ERROR] Username khaali nahi chhod sakte!${NC}"
                    press_any_key
                    continue
                fi
                userdel -f "$username" 2>/dev/null
                rm -f "/etc/raretriccks/users/${username}.conf"
                echo -e "${GREEN}User ${username} deleted successfully!${NC}"
                press_any_key
                ;;
            3) check_connected_ips ;;
            4) check_gb_usage ;;
            5)
                read -rp "Username to Renew: " username
                if id "$username" &>/dev/null; then
                    read -rp "Kitne additional days add karne hain? (e.g. 30): " r_days
                    new_exp=$(date -d "+$r_days days" +%Y-%m-%d)
                    usermod -e "$new_exp" "$username"
                    passwd -u "$username" 2>/dev/null
                    echo -e "${GREEN}[SUCCESS] User ${username} Expiry Extended. New Expiry: ${new_exp}${NC}"
                else
                    echo -e "${RED}[ERROR] User exist nahi karta!${NC}"
                fi
                press_any_key
                ;;
            6)
                read -rp "Username to change IP Limit: " username
                if [[ -f "/etc/raretriccks/users/${username}.conf" ]]; then
                    read -rp "Nayi IP Limit enter karein (e.g. 2 ya 3): " new_ip_l
                    sed -i "s/IP_LIMIT=.*/IP_LIMIT=${new_ip_l}/g" "/etc/raretriccks/users/${username}.conf"
                    passwd -u "$username" 2>/dev/null
                    echo -e "${GREEN}[SUCCESS] IP limit updated to ${new_ip_l} Device(s).${NC}"
                    echo -e "${GREEN}[INFO] Account ${username} is now UNLOCKED and Active!${NC}"
                else
                    echo -e "${RED}[ERROR] User config nahi mili!${NC}"
                fi
                press_any_key
                ;;
            7)
                read -rp "Username to extend GB limit: " username
                if [[ -f "/etc/raretriccks/users/${username}.conf" ]]; then
                    read -rp "Naya Data Limit GB me enter karein (e.g. 1 ya 50): " new_gb
                    sed -i "s/GB_LIMIT=.*/GB_LIMIT=${new_gb}/g" "/etc/raretriccks/users/${username}.conf"
                    passwd -u "$username" 2>/dev/null
                    echo -e "${GREEN}[SUCCESS] GB Limit updated to ${new_gb} GB.${NC}"
                    echo -e "${GREEN}[INFO] Account ${username} is now UNLOCKED and Active!${NC}"
                else
                    echo -e "${RED}[ERROR] User config nahi mili!${NC}"
                fi
                press_any_key
                ;;
            8) return ;;
            *) echo "Invalid Option"; sleep 1 ;;
        esac
    done
}

