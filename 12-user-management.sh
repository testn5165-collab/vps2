#!/bin/bash
# RareTriccks VPN Panel - 12-user-management.sh
# Renew expiry / modify IP+GB limits for SSH & V2Ray accounts.
source /etc/raretriccks/00-common.sh

renew_expiry_option() {
    clear
    echo -e "${CYAN}--- Renew Account Expiry ---${NC}"
    read -rp "Account Type (1=SSH/SlowDNS, 2=V2Ray): " at
    read -rp "Username: " uname
    read -rp "New Expiry (Days from today, 0 = unlimited): " days

    if [[ "$at" == "1" ]]; then
        if ! id "$uname" &>/dev/null; then
            echo -e "${RED}[ERROR] SSH user nahi mila.${NC}"
        else
            if [[ "$days" == "0" ]]; then
                usermod -e "" "$uname"
            else
                usermod -e "$(date -d "+$days days" +"%Y-%m-%d")" "$uname"
            fi
            passwd -u "$uname" &>/dev/null
            echo -e "${GREEN}[SUCCESS] SSH user '${uname}' expiry updated & account unlocked.${NC}"
        fi
    elif [[ "$at" == "2" ]]; then
        local conf="${V2USERS_DIR}/${uname}.conf"
        if [[ ! -f "$conf" ]]; then
            echo -e "${RED}[ERROR] V2Ray user nahi mila.${NC}"
        else
            if [[ "$days" == "0" ]]; then
                sed -i "s/^EXPIRE_DATE=.*/EXPIRE_DATE=Unlimited/" "$conf"
            else
                sed -i "s/^EXPIRE_DATE=.*/EXPIRE_DATE=$(date -d "+$days days" +"%Y-%m-%d")/" "$conf"
            fi
            v2ray_unlock_user "$uname"
            echo -e "${GREEN}[SUCCESS] V2Ray user '${uname}' expiry updated & auto-unlocked.${NC}"
        fi
    else
        echo -e "${RED}[ERROR] Invalid account type.${NC}"
    fi
    press_any_key
}

modify_ip_limit_option() {
    clear
    echo -e "${CYAN}--- Extend / Modify IP Limit (Auto Unlock) ---${NC}"
    read -rp "Account Type (1=SSH/SlowDNS, 2=V2Ray): " at
    read -rp "Username: " uname
    read -rp "New IP Limit (0 = unlimited): " newip

    if [[ "$at" == "1" ]]; then
        local conf="${USERS_DIR}/${uname}.conf"
        if [[ ! -f "$conf" ]]; then
            echo -e "${RED}[ERROR] SSH user conf nahi mila.${NC}"
        else
            sed -i "s/^IP_LIMIT=.*/IP_LIMIT=${newip}/" "$conf"
            passwd -u "$uname" &>/dev/null
            echo -e "${GREEN}[SUCCESS] SSH IP limit updated to ${newip} & account auto-unlocked.${NC}"
        fi
    elif [[ "$at" == "2" ]]; then
        local conf="${V2USERS_DIR}/${uname}.conf"
        if [[ ! -f "$conf" ]]; then
            echo -e "${RED}[ERROR] V2Ray user conf nahi mila.${NC}"
        else
            sed -i "s/^IP_LIMIT=.*/IP_LIMIT=${newip}/" "$conf"
            v2ray_unlock_user "$uname"
            echo -e "${GREEN}[SUCCESS] V2Ray IP limit updated to ${newip} & user auto-unlocked.${NC}"
        fi
    else
        echo -e "${RED}[ERROR] Invalid account type.${NC}"
    fi
    press_any_key
}

modify_gb_limit_option() {
    clear
    echo -e "${CYAN}--- Extend / Modify GB Data Quota (Auto Unlock) ---${NC}"
    read -rp "Account Type (1=SSH/SlowDNS, 2=V2Ray): " at
    read -rp "Username: " uname
    read -rp "New GB Limit (e.g. 20 or Unlimited): " newgb
    read -rp "Reset used-data counter to 0? (y/n): " doreset

    if [[ "$at" == "1" ]]; then
        local conf="${USERS_DIR}/${uname}.conf"
        if [[ ! -f "$conf" ]]; then
            echo -e "${RED}[ERROR] SSH user conf nahi mila.${NC}"
        else
            sed -i "s/^GB_LIMIT=.*/GB_LIMIT=${newgb}/" "$conf"
            [[ "$doreset" == "y" || "$doreset" == "Y" ]] && sed -i "s/^USED_MB=.*/USED_MB=0.0/" "$conf"
            passwd -u "$uname" &>/dev/null
            echo -e "${GREEN}[SUCCESS] SSH GB quota updated & account auto-unlocked.${NC}"
        fi
    elif [[ "$at" == "2" ]]; then
        local conf="${V2USERS_DIR}/${uname}.conf"
        if [[ ! -f "$conf" ]]; then
            echo -e "${RED}[ERROR] V2Ray user conf nahi mila.${NC}"
        else
            sed -i "s/^GB_LIMIT=.*/GB_LIMIT=${newgb}/" "$conf"
            [[ "$doreset" == "y" || "$doreset" == "Y" ]] && sed -i "s/^USED_MB=.*/USED_MB=0.0/" "$conf"
            v2ray_unlock_user "$uname"
            echo -e "${GREEN}[SUCCESS] V2Ray GB quota updated & user auto-unlocked.${NC}"
        fi
    else
        echo -e "${RED}[ERROR] Invalid account type.${NC}"
    fi
    press_any_key
}

user_management_menu() {
    while true; do
        clear
        echo -e "${CYAN}====================================================${NC}"
        echo -e "${YELLOW}       RareTriccks VPN Panel - USER MANAGEMENT     ${NC}"
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
        read -rp "Select Option [1-8]: " u_opt

        case $u_opt in
            1)
                read -rp "Account Type (1=SSH/SlowDNS, 2=V2Ray): " at
                case "$at" in
                    1) ssh_add_user_flow ;;
                    2) v2ray_add_user_flow ;;
                    *) echo -e "${RED}Invalid type.${NC}"; press_any_key ;;
                esac
                ;;
            2)
                read -rp "Account Type (1=SSH/SlowDNS, 2=V2Ray): " at
                case "$at" in
                    1) ssh_delete_user_flow ;;
                    2) v2ray_delete_user_flow ;;
                    *) echo -e "${RED}Invalid type.${NC}"; press_any_key ;;
                esac
                ;;
            3) check_connected_ips_option ;;
            4) check_status_quota_option ;;
            5) renew_expiry_option ;;
            6) modify_ip_limit_option ;;
            7) modify_gb_limit_option ;;
            8) return ;;
        esac
    done
}

