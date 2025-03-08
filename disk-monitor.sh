#!/bin/bash

# Disk Capacity Monitoring Script
# Update: Replaced mailx with CURL for SMTP integration

# Default Settings
#DEFAULT_DISKS=("/dev/sda1 10" "/dev/sdb2 15")
DEFAULT_DISKS=("/dev/sda1 10")
DEFAULT_RAM_THRESHOLD=25
DEFAULT_EMAIL_TO=""
DEFAULT_SMTP_SERVER=""
DEFAULT_SMTP_PORT=587
DEFAULT_SMTP_USER=""
DEFAULT_SMTP_PASS=""
DEFAULT_EMAIL_FROM=""
DEFAULT_CRON_INTERVAL=5

# Configuration file
CONFIG_FILE="/etc/disk-monitor.conf"

# Log file
LOG_FILE="/var/log/disk-monitor.log"
touch "$LOG_FILE"

# Colored output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Log function
log_message() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Help message
show_help() {
    echo -e "${YELLOW}Usage:${NC}"
    echo "  ./disk-monitor.sh       : Normal execution"
    echo "  ./disk-monitor.sh --init: Interactive setup"
    echo -e "\n${YELLOW}Features:${NC}"
    echo "  - Automatically creates the configuration file"
    echo "  - Automatically adds entry to crontab"
    echo "  - Interactive disk selection"
}

# Load default values from existing config
load_config_defaults() {
    if [ -f "$CONFIG_FILE" ]; then
        # Disks
        while read -r line; do
            if [[ "$line" =~ ^/dev/ ]]; then
                DEFAULT_DISKS+=("$line")
            fi
        done < <(grep '^/dev/' "$CONFIG_FILE")

        # RAM Threshold
        # RAM Threshold (enhanced version)
        DEFAULT_RAM_THRESHOLD=$(awk '/^RAM / {print $2}' "$CONFIG_FILE")

        # Use default if the value cannot be read
        [ -z "$DEFAULT_RAM_THRESHOLD" ] && DEFAULT_RAM_THRESHOLD=80

        # Email Settings
        DEFAULT_EMAIL_TO=$(grep '^EMAIL_TO=' "$CONFIG_FILE" | cut -d= -f2-)
        DEFAULT_SMTP_SERVER=$(grep '^SMTP_SERVER=' "$CONFIG_FILE" | cut -d= -f2-)
        DEFAULT_SMTP_PORT=$(grep '^SMTP_PORT=' "$CONFIG_FILE" | cut -d= -f2-)
        DEFAULT_SMTP_USER=$(grep '^SMTP_USER=' "$CONFIG_FILE" | cut -d= -f2-)
        DEFAULT_SMTP_PASS=$(grep '^SMTP_PASS=' "$CONFIG_FILE" | cut -d= -f2-)
        DEFAULT_EMAIL_FROM=$(grep '^EMAIL_FROM=' "$CONFIG_FILE" | cut -d= -f2-)
    fi
}

# Validation function
validate_input() {
    local prompt="$1"
    local default="$2"
    local min="$3"
    local max="$4"

    while true; do
        read -p "$prompt" value
        value=${value:-$default}

        # Numeric check
        if ! [[ "$value" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}ERROR: Please enter a numeric value!${NC}" >&2
            continue
        fi

        # Range check
        if ((value < min)); then
            echo -e "${RED}ERROR: Value must be at least $min!${NC}" >&2
            continue
        elif ((value > max)); then
            echo -e "${RED}ERROR: Value must be at most $max!${NC}" >&2
            continue
        fi

        echo "$value"
        break
    done
}

manage_disks() {
    declare -A current_disks

    # Read disks from config (if available)
    if [ -f "$CONFIG_FILE" ]; then
        while read -r line; do
            if [[ "$line" =~ ^/dev/ ]]; then
                disk=$(echo "$line" | awk '{print $1}')
                threshold=$(echo "$line" | awk '{print $2}')
                current_disks["$disk"]=$threshold
            fi
        done <"$CONFIG_FILE"
    else
        # Load default disks
        for entry in "${DEFAULT_DISKS[@]}"; do
            disk=$(echo "$entry" | awk '{print $1}')
            threshold=$(echo "$entry" | awk '{print $2}')
            current_disks["$disk"]=$threshold
        done
    fi

    while true; do
        clear
        echo -e "${GREEN}=== Disk Management ===${NC}"
        echo -e "${YELLOW}Current Disks:${NC}"

        # List disks with numbering
        local i=1
        declare -a disk_list
        for disk in "${!current_disks[@]}"; do
            disk_list[$i]="$disk"
            if [ -b "$disk" ]; then
                status="${GREEN}✓${NC}"
            else
                status="${RED}✗${NC}"
            fi
            echo -e "$i) $status $disk - Threshold: %${current_disks[$disk]}"
            ((i++))
        done

        echo -e "\n${YELLOW}Select an action:${NC}"
        echo "1) Add New Disk"
        echo "2) Remove Disk"
        echo "3) Done"
        # Default to 3 for input
        read -p $'\e[33mYour choice [1-3] (default 3): \e[0m' choice
        choice=${choice:-3} # Defaults to 3 when Enter is pressed

        case $choice in
        1)

            # Update disk listing section
            echo -e "\n${GREEN}All Disks in System:${NC}"
            local j=1
            declare -a all_disks
            while read -r name type size maj_min mount; do
                # echo "mount:'$mount', type:'$type', size:'$size', maj_min:'$maj_min'"

                # Filtering rules
                [[ "$type" != "disk" && "$type" != "part" && "$type" != "lvm" ]] && continue
                [[ "$mount" == "" || "$mount" == "[SWAP]" ]] && continue # Skip unmounted and SWAP disks
                [[ "$size" == *M && ${size%M} -lt 100 ]] && continue     # Skip below 100MB
                [[ "$size" == *K ]] && continue                          # Skip kilobyte-level disks

                # LVM check
                if [[ "$type" == "lvm" ]]; then
                    disk_path="/dev/mapper/$(lsblk -ln -o NAME,MAJ:MIN | awk -v m="$maj_min" '$2 == m {print $1}')"
                else
                    disk_path="/dev/$name"
                fi

                all_disks[$j]="$disk_path"
                echo -e "$j) $disk_path (${size}) - Type: $type - Mount: ${mount:-'-'}"
                ((j++))
            done < <(lsblk -ln -o NAME,TYPE,SIZE,MAJ:MIN,MOUNTPOINT | grep -v 'loop\|rom\|cdrom')

            read -p "Enter the number of the disk to add: " disk_num
            selected_disk="${all_disks[$disk_num]}"

            if [ -z "$selected_disk" ]; then
                echo -e "${RED}Invalid number!${NC}"
                sleep 1
                continue
            fi

            # Set threshold for disk
            new_threshold=$(validate_input \
                "Critical usage % for the disk (default 10): " \
                10 1 100)
            #read -p "Threshold value (default %10): " new_threshold
            current_disks["$selected_disk"]=${new_threshold:-10}
            ;;

        2)
            read -p "Enter the number of the disk to remove: " del_num
            selected_disk="${disk_list[$del_num]}"

            if [ -n "$selected_disk" ]; then
                unset current_disks["$selected_disk"]
                echo -e "${RED}Disk removed: $selected_disk${NC}"
            else
                echo -e "${RED}Invalid number!${NC}"
            fi
            sleep 1
            ;;

        3)
            break
            ;;
        *)
            echo -e "${RED}Invalid choice!${NC}"
            sleep 1
            ;;
        esac
    done

    # Transfer results to global variable
    declare -gA __managed_discks=()
    for key in "${!current_disks[@]}"; do
        __managed_discks["$key"]="${current_disks[$key]}"
    done
}

# Setup wizard
setup_wizard() {
    # Load defaults from config
    load_config_defaults

    echo -e "\n${GREEN}=== Disk Monitoring Setup Wizard ===${NC}"

    # Disk Management
    manage_disks

    # RAM Threshold
    echo -e "\n${YELLOW}RAM Settings:${NC}"
    ram_threshold=$(validate_input \
        "Critical free RAM % (default ${DEFAULT_RAM_THRESHOLD}): " \
        "$DEFAULT_RAM_THRESHOLD" 1 99)

    # Email Settings
    echo -e "\n${YELLOW}Email Settings:${NC}"
    read -p "Recipient email [${DEFAULT_EMAIL_TO}]: " email_to
    read -p "Sender email [${DEFAULT_EMAIL_FROM}]: " email_from
    read -p "SMTP Server [${DEFAULT_SMTP_SERVER}]: " smtp_server
    smtp_port=$(validate_input \
        "SMTP Port (1-65535) [${DEFAULT_SMTP_PORT}]: " \
        "$DEFAULT_SMTP_PORT" 1 65535)
    read -p "SMTP User [${DEFAULT_SMTP_USER}]: " smtp_user
    read -s -p "SMTP Password [********]: " smtp_pass
    echo

    # Assign values
    email_to=${email_to:-$DEFAULT_EMAIL_TO}
    email_from=${email_from:-$DEFAULT_EMAIL_FROM}
    smtp_server=${smtp_server:-$DEFAULT_SMTP_SERVER}
    smtp_port=${smtp_port:-$DEFAULT_SMTP_PORT}
    smtp_user=${smtp_user:-$DEFAULT_SMTP_USER}
    smtp_pass=${smtp_pass:-$DEFAULT_SMTP_PASS}

    # Create Configuration File
    {
        echo "# Disk Monitoring Configuration"
        echo -e "\n# Disks (Device Threshold%)"
        for disk in "${!__managed_discks[@]}"; do
            echo "$disk ${__managed_discks[$disk]}"
        done
        echo -e "\n# RAM Threshold%"
        echo "RAM $ram_threshold"
        echo -e "\n# Email Settings"
        echo "EMAIL_TO=$email_to"
        echo "EMAIL_FROM=$email_from"
        echo "SMTP_SERVER=$smtp_server"
        echo "SMTP_PORT=$smtp_port"
        echo "SMTP_USER=$smtp_user"
        echo "SMTP_PASS=$smtp_pass"
    } >"$CONFIG_FILE"

    # Crontab setting
    echo -e "\n${YELLOW}Crontab settings:${NC}"
    cron_interval=$(validate_input \
        "Check frequency (1-60 minutes) [default $DEFAULT_CRON_INTERVAL]: " \
        $DEFAULT_CRON_INTERVAL 1 60)

    (
        crontab -l 2>/dev/null | grep -v "disk-monitor.sh"
        echo "*/$cron_interval * * * * $(pwd)/disk-monitor.sh"
    ) | crontab -

    crontab -l

    echo -e "\n${GREEN}Setup complete!${NC}"
    echo -e "The script will run every $cron_interval minutes"

    echo -e "${GREEN}✔ Configuration successfully updated!${NC}"
}

# Prepare email content
prepare_email() {
    local server_ip=$(hostname -I | awk '{print $1}')

    local email_file=$(mktemp)
    echo "From: $EMAIL_FROM" >"$email_file"
    echo "To: $EMAIL_TO" >>"$email_file"
    echo "Subject: $EMAIL_SUBJECT [$(hostname)] [$(date '+%Y-%m-%d')]" >>"$email_file"
    echo "Content-Type: text/plain; charset=UTF-8" >>"$email_file"
    echo >>"$email_file"
    echo "Server Name: $(hostname)" >>"$email_file"
    echo "IP Address: $server_ip" >>"$email_file"
    echo "Date/Time: $(date '+%d.%m.%Y %H:%M:%S')" >>"$email_file"
    echo >>"$email_file"

    if [ -s "$TEMP_FILE" ]; then
        echo "Critical level exceeded on the following resources:" >>"$email_file"
        cat "$TEMP_FILE" >>"$email_file"
    else
        echo "All resources are at normal levels." >>"$email_file"
    fi

    echo "$email_file"
}

# RAM check function
check_ram() {
    local threshold=$1
    local total used free used_percent free_percent

    read total used free <<<$(free -m | awk '/Mem:/ {print $2, $3, $4}')

    if [ "$total" -gt 0 ]; then
        used_percent=$(awk "BEGIN {printf \"%.0f\", ($used/$total)*100}")
        free_percent=$((100 - used_percent))

        log_message "RAM Check: Usage %$used_percent | Free %$free_percent | Threshold %$threshold"

        # Fix: Warning if free memory falls below the threshold
        if [ "$free_percent" -lt "$threshold" ]; then
            log_message "CRITICAL RAM: Free space %$free_percent (Threshold: %$threshold)"

            echo "RAM Status:" >>"$TEMP_FILE"
            echo "--------------------------------" >>"$TEMP_FILE"
            echo "Total: ${total}MB" >>"$TEMP_FILE"
            echo "Used: ${used}MB (%$used_percent)" >>"$TEMP_FILE"
            echo "Free: %$free_percent" >>"$TEMP_FILE"
            echo "Critical Threshold: %$threshold" >>"$TEMP_FILE"
            echo >>"$TEMP_FILE"

            return 1
        fi
    else
        log_message "ERROR: RAM information could not be retrieved"
    fi
    return 0
}

# Disk check function
check_disk() {
    local disk=$1
    local threshold=$2

    if [ -b "$disk" ] || grep -q "$disk" /proc/mounts; then
        local disk_info=$(df -h "$disk" | awk 'NR==2')
        local disk_name=$(awk '{print $1}' <<<"$disk_info")
        local mount_point=$(awk '{print $6}' <<<"$disk_info")
        local use_percent=$(awk '{gsub(/%/,""); print $5}' <<<"$disk_info")
        local free_percent=$((100 - use_percent))

        log_message "Disk Check: $disk_name | Free %$free_percent | Threshold %$threshold"

        if [ "$free_percent" -lt "$threshold" ]; then
            log_message "CRITICAL DISK: $disk_name (%$free_percent < %$threshold)"

            # Write to temporary file
            echo "Disk Information:" >>"$TEMP_FILE"
            echo "--------------------------------" >>"$TEMP_FILE"
            echo "Device: $disk_name" >>"$TEMP_FILE"
            echo "Mount Point: $mount_point" >>"$TEMP_FILE"
            echo "Usage: %$use_percent" >>"$TEMP_FILE"
            echo "Free Space: %$free_percent" >>"$TEMP_FILE"
            echo "Critical Threshold: %$threshold" >>"$TEMP_FILE"
            echo >>"$TEMP_FILE"

            return 1
        fi
    else
        log_message "ERROR: $disk not found"
    fi
    return 0
}

# Main control loop
main() {
    # Initial run or setup with --init
    if [ ! -f "$CONFIG_FILE" ] || [ "$1" == "--init" ]; then
        setup_wizard
        exit 0
    fi

    # Reset variables
    TEMP_FILE=$(mktemp)
    CRITICAL_COUNT=0

    # Load configuration
    source <(grep -E '^(EMAIL_TO|SMTP_SERVER|SMTP_PORT|SMTP_USER|SMTP_PASS|EMAIL_FROM)=' "$CONFIG_FILE")
    EMAIL_SUBJECT="SERVER ALERT: Critical Resource Level"

    # Resource check
    while read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^# || -z "$line" ]] && continue

        # RAM check
        if [[ "$line" =~ ^RAM[[:space:]]+([0-9]+) ]]; then
            check_ram "${BASH_REMATCH[1]}" || CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
            continue
        fi

        # Disk check
        if [[ "$line" =~ ^/[^[:space:]]+[[:space:]]+[0-9]+ ]]; then
            disk=$(awk '{print $1}' <<<"$line")
            threshold=$(awk '{print $2}' <<<"$line")
            check_disk "$disk" "$threshold" || CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
        fi
    done <"$CONFIG_FILE"

    # Email operations
    if [ "$CRITICAL_COUNT" -gt 0 ]; then
        log_message "Number of critical issues: $CRITICAL_COUNT"
        local email_file=$(prepare_email)

        # Send via CURL
        curl --silent --show-error \
            --url "smtp://${SMTP_SERVER}:${SMTP_PORT}" \
            --ssl-reqd \
            --tlsv1.2 \
            --mail-from "$EMAIL_FROM" \
            --mail-rcpt "$EMAIL_TO" \
            --user "${SMTP_USER}:${SMTP_PASS}" \
            --upload-file "$email_file" >>"$LOG_FILE" 2>&1

        [ $? -eq 0 ] && log_message "Email sent" || log_message "Email could not be sent"
        rm -f "$email_file"
    else
        log_message "All resources are normal"
    fi

    # Cleanup
    rm -f "$TEMP_FILE"
}

# Dependency check
check_dependencies() {
    if ! command -v curl &>/dev/null; then
        log_message "curl is not installed, installing..."
        apt-get update && apt-get install -y curl
    fi
}

# Entry point
case "$1" in
"--help" | "-h")
    show_help
    ;;
*)
    check_dependencies
    main "$@"
    ;;
esac
