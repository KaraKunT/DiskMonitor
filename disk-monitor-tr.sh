#!/bin/bash

# Disk Kapasitesi İzleme Scripti
# Güncelleme: mailx yerine CURL ile SMTP entegrasyonu

# Varsayılan Ayarlar
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

# Konfigürasyon dosyası
CONFIG_FILE="/etc/disk-monitor.conf"

# Log dosyası
LOG_FILE="/var/log/disk-monitor.log"
touch "$LOG_FILE"

# Renkli çıktılar
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Log fonksiyonu
log_message() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Yardım mesajı
show_help() {
    echo -e "${YELLOW}Kullanım:${NC}"
    echo "  ./disk-monitor.sh       : Normal çalıştırma"
    echo "  ./disk-monitor.sh --init: Interaktif kurulum"
    echo -e "\n${YELLOW}Özellikler:${NC}"
    echo "  - Konfigürasyon dosyasını otomatik oluşturur"
    echo "  - Crontab'a otomatik ekleme yapar"
    echo "  - Interaktif disk seçimi"
}

# Mevcut config'den varsayılan değerleri yükle
load_config_defaults() {
    if [ -f "$CONFIG_FILE" ]; then
        # Diskler
        while read -r line; do
            if [[ "$line" =~ ^/dev/ ]]; then
                DEFAULT_DISKS+=("$line")
            fi
        done < <(grep '^/dev/' "$CONFIG_FILE")

        # RAM Threshold
        # RAM Threshold (geliştirilmiş versiyon)
        DEFAULT_RAM_THRESHOLD=$(awk '/^RAM / {print $2}' "$CONFIG_FILE")

        # Eğer değer okunamazsa varsayılanı kullan
        [ -z "$DEFAULT_RAM_THRESHOLD" ] && DEFAULT_RAM_THRESHOLD=80

        # E-posta Ayarları
        DEFAULT_EMAIL_TO=$(grep '^EMAIL_TO=' "$CONFIG_FILE" | cut -d= -f2-)
        DEFAULT_SMTP_SERVER=$(grep '^SMTP_SERVER=' "$CONFIG_FILE" | cut -d= -f2-)
        DEFAULT_SMTP_PORT=$(grep '^SMTP_PORT=' "$CONFIG_FILE" | cut -d= -f2-)
        DEFAULT_SMTP_USER=$(grep '^SMTP_USER=' "$CONFIG_FILE" | cut -d= -f2-)
        DEFAULT_SMTP_PASS=$(grep '^SMTP_PASS=' "$CONFIG_FILE" | cut -d= -f2-)
        DEFAULT_EMAIL_FROM=$(grep '^EMAIL_FROM=' "$CONFIG_FILE" | cut -d= -f2-)
    fi
}

# Validasyon fonksiyonu
validate_input() {
    local prompt="$1"
    local default="$2"
    local min="$3"
    local max="$4"

    while true; do
        read -p "$prompt" value
        value=${value:-$default}

        # Sayısal kontrol
        if ! [[ "$value" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}HATA: Lütfen sayısal bir değer girin!${NC}" >&2
            continue
        fi

        # Aralık kontrolü
        if ((value < min)); then
            echo -e "${RED}HATA: Değer en az $min olmalı!${NC}" >&2
            continue
        elif ((value > max)); then
            echo -e "${RED}HATA: Değer en fazla $max olmalı!${NC}" >&2
            continue
        fi

        echo "$value"
        break
    done
}

manage_disks() {
    declare -A current_disks

    # Config'den diskleri oku (varsa)
    if [ -f "$CONFIG_FILE" ]; then
        while read -r line; do
            if [[ "$line" =~ ^/dev/ ]]; then
                disk=$(echo "$line" | awk '{print $1}')
                threshold=$(echo "$line" | awk '{print $2}')
                current_disks["$disk"]=$threshold
            fi
        done <"$CONFIG_FILE"
    else
        # Varsayılan diskleri yükle
        for entry in "${DEFAULT_DISKS[@]}"; do
            disk=$(echo "$entry" | awk '{print $1}')
            threshold=$(echo "$entry" | awk '{print $2}')
            current_disks["$disk"]=$threshold
        done
    fi

    while true; do
        clear
        echo -e "${GREEN}=== Disk Yönetimi ===${NC}"
        echo -e "${YELLOW}Mevcut Diskler:${NC}"

        # Diskleri numaralandırarak listele
        local i=1
        declare -a disk_list
        for disk in "${!current_disks[@]}"; do
            disk_list[$i]="$disk"
            if [ -b "$disk" ]; then
                status="${GREEN}✓${NC}"
            else
                status="${RED}✗${NC}"
            fi
            echo -e "$i) $status $disk - Eşik: %${current_disks[$disk]}"
            ((i++))
        done

        echo -e "\n${YELLOW}İşlem Seçin:${NC}"
        echo "1) Yeni Disk Ekle"
        echo "2) Disk Sil"
        echo "3) Tamamlandı"
        # Varsayılan 3 ile input alma
        read -p $'\e[33mSeçiminiz [1-3] (varsayılan 3): \e[0m' choice
        choice=${choice:-3} # Enter'a basılırsa otomatik 3 seçilir

        case $choice in
        1)

            # Disk listeleme kısmını güncelleyelim
            echo -e "\n${GREEN}Sistemdeki Tüm Diskler:${NC}"
            local j=1
            declare -a all_disks
            while read -r name type size maj_min mount; do
                # echo "mount:'$mount', type:'$type', size:'$size', maj_min:'$maj_min'"

                # Filtreleme kuralları
                [[ "$type" != "disk" && "$type" != "part" && "$type" != "lvm" ]] && continue
                [[ "$mount" == "" || "$mount" == "[SWAP]" ]] && continue # Bağlı olmayanları ve SWAP'leri atla
                [[ "$size" == *M && ${size%M} -lt 100 ]] && continue     # 100MB altını atla
                [[ "$size" == *K ]] && continue                          # Kilobayt seviyesindeki diskleri atla

                # LVM kontrolü
                if [[ "$type" == "lvm" ]]; then
                    disk_path="/dev/mapper/$(lsblk -ln -o NAME,MAJ:MIN | awk -v m="$maj_min" '$2 == m {print $1}')"
                else
                    disk_path="/dev/$name"
                fi

                all_disks[$j]="$disk_path"
                echo -e "$j) $disk_path (${size}) - Tür: $type - Bağlantı: ${mount:-'-'}"
                ((j++))
            done < <(lsblk -ln -o NAME,TYPE,SIZE,MAJ:MIN,MOUNTPOINT | grep -v 'loop\|rom\|cdrom')

            read -p "Eklemek istediğiniz disk numarası: " disk_num
            selected_disk="${all_disks[$disk_num]}"

            if [ -z "$selected_disk" ]; then
                echo -e "${RED}Geçersiz numara!${NC}"
                sleep 1
                continue
            fi

            # Disk eşik değeri için
            new_threshold=$(validate_input \
                "Disk için kritik kullanım % (varsayılan 10): " \
                10 1 100)
            #read -p "Eşik değeri (varsayılan %10): " new_threshold
            current_disks["$selected_disk"]=${new_threshold:-10}
            ;;

        2)
            read -p "Silmek istediğiniz disk numarası: " del_num
            selected_disk="${disk_list[$del_num]}"

            if [ -n "$selected_disk" ]; then
                unset current_disks["$selected_disk"]
                echo -e "${RED}Disk silindi: $selected_disk${NC}"
            else
                echo -e "${RED}Geçersiz numara!${NC}"
            fi
            sleep 1
            ;;

        3)
            break
            ;;
        *)
            echo -e "${RED}Geçersiz seçim!${NC}"
            sleep 1
            ;;
        esac
    done

    # Sonuçları global değişkene aktar
    declare -gA __managed_discks=()
    for key in "${!current_disks[@]}"; do
        __managed_discks["$key"]="${current_disks[$key]}"
    done
}

# Kurulum sihirbazı
setup_wizard() {
    # Config'den varsayılanları yükle
    load_config_defaults

    echo -e "\n${GREEN}=== Disk İzleme Kurulum Sihirbazı ===${NC}"

    # Disk Yönetimi
    manage_disks

    # RAM Threshold
    echo -e "\n${YELLOW}RAM Ayarları:${NC}"
    ram_threshold=$(validate_input \
        "RAM için kritik boş alan % (varsayılan ${DEFAULT_RAM_THRESHOLD}): " \
        "$DEFAULT_RAM_THRESHOLD" 1 99)

    # E-posta Ayarları
    echo -e "\n${YELLOW}E-posta Ayarları:${NC}"
    read -p "Alıcı e-posta [${DEFAULT_EMAIL_TO}]: " email_to
    read -p "Gönderici e-posta [${DEFAULT_EMAIL_FROM}]: " email_from
    read -p "SMTP Sunucu [${DEFAULT_SMTP_SERVER}]: " smtp_server
    smtp_port=$(validate_input \
        "SMTP Port (1-65535) [${DEFAULT_SMTP_PORT}]: " \
        "$DEFAULT_SMTP_PORT" 1 65535)
    read -p "SMTP Kullanıcı [${DEFAULT_SMTP_USER}]: " smtp_user
    read -s -p "SMTP Şifre [********]: " smtp_pass
    echo

    # Değer Atamaları
    email_to=${email_to:-$DEFAULT_EMAIL_TO}
    email_from=${email_from:-$DEFAULT_EMAIL_FROM}
    smtp_server=${smtp_server:-$DEFAULT_SMTP_SERVER}
    smtp_port=${smtp_port:-$DEFAULT_SMTP_PORT}
    smtp_user=${smtp_user:-$DEFAULT_SMTP_USER}
    smtp_pass=${smtp_pass:-$DEFAULT_SMTP_PASS}

    # Konfigürasyon Dosyasını Oluştur
    {
        echo "# Disk İzleme Konfigürasyonu"
        echo -e "\n# Diskler (Device Threshold%)"
        for disk in "${!__managed_discks[@]}"; do
            echo "$disk ${__managed_discks[$disk]}"
        done
        echo -e "\n# RAM Threshold%"
        echo "RAM $ram_threshold"
        echo -e "\n# E-posta Ayarları"
        echo "EMAIL_TO=$email_to"
        echo "EMAIL_FROM=$email_from"
        echo "SMTP_SERVER=$smtp_server"
        echo "SMTP_PORT=$smtp_port"
        echo "SMTP_USER=$smtp_user"
        echo "SMTP_PASS=$smtp_pass"
    } >"$CONFIG_FILE"

    # Crontab ayarı
    echo -e "\n${YELLOW}Crontab ayarları:${NC}"
    cron_interval=$(validate_input \
        "Kontrol sıklığı (1-60 dakika) [varsayılan $DEFAULT_CRON_INTERVAL]: " \
        $DEFAULT_CRON_INTERVAL 1 60)

    script_path=$(realpath "$0") 

    (
        crontab -l 2>/dev/null | grep -v "disk-monitor.sh"
        echo "*/$cron_interval * * * * $script_path"
    ) | crontab -

    crontab -l

    echo -e "\n${GREEN}Kurulum tamamlandı!${NC}"
    echo -e "Script her $cron_interval dakikada bir çalışacak"

    echo -e "${GREEN}✔ Konfigürasyon başarıyla güncellendi!${NC}"
}

# E-posta içerik hazırlama
prepare_email() {
    local server_ip=$(hostname -I | awk '{print $1}')

    local email_file=$(mktemp)
    echo "From: $EMAIL_FROM" >"$email_file"
    echo "To: $EMAIL_TO" >>"$email_file"
    echo "Subject: $EMAIL_SUBJECT [$(hostname)] [$(date '+%Y-%m-%d')]" >>"$email_file"
    echo "Content-Type: text/plain; charset=UTF-8" >>"$email_file"
    echo >>"$email_file"
    echo "Sunucu Adı: $(hostname)" >>"$email_file"
    echo "IP Adresi: $server_ip" >>"$email_file"
    echo "Tarih/Saat: $(date '+%d.%m.%Y %H:%M:%S')" >>"$email_file"
    echo >>"$email_file"

    if [ -s "$TEMP_FILE" ]; then
        echo "Aşağıdaki kaynaklarda kritik seviye aşıldı:" >>"$email_file"
        cat "$TEMP_FILE" >>"$email_file"
    else
        echo "Tüm kaynaklar normal seviyelerde." >>"$email_file"
    fi

    echo "$email_file"
}

# RAM kontrol fonksiyonu
check_ram() {
    local threshold=$1
    local total used free used_percent free_percent

    read total used free <<<$(free -m | awk '/Mem:/ {print $2, $3, $4}')

    if [ "$total" -gt 0 ]; then
        used_percent=$(awk "BEGIN {printf \"%.0f\", ($used/$total)*100}")
        free_percent=$((100 - used_percent))

        log_message "RAM Kontrol: Kullanım %$used_percent | Boş %$free_percent | Eşik %$threshold"

        # Düzeltme: Boş alan eşik değerinin altındaysa uyarı
        if [ "$free_percent" -lt "$threshold" ]; then
            log_message "KRİTİK RAM: Boş alan %$free_percent (Eşik: %$threshold)"

            echo "RAM Durumu:" >>"$TEMP_FILE"
            echo "--------------------------------" >>"$TEMP_FILE"
            echo "Toplam: ${total}MB" >>"$TEMP_FILE"
            echo "Kullanılan: ${used}MB (%$used_percent)" >>"$TEMP_FILE"
            echo "Boş Alan: %$free_percent" >>"$TEMP_FILE"
            echo "Kritik Eşik: %$threshold" >>"$TEMP_FILE"
            echo >>"$TEMP_FILE"

            return 1
        fi
    else
        log_message "HATA: RAM bilgisi alınamadı"
    fi
    return 0
}

# Disk kontrol fonksiyonu
check_disk() {
    local disk=$1
    local threshold=$2

    if [ -b "$disk" ] || grep -q "$disk" /proc/mounts; then
        local disk_info=$(df -h "$disk" | awk 'NR==2')
        local disk_name=$(awk '{print $1}' <<<"$disk_info")
        local mount_point=$(awk '{print $6}' <<<"$disk_info")
        local use_percent=$(awk '{gsub(/%/,""); print $5}' <<<"$disk_info")
        local free_percent=$((100 - use_percent))

        log_message "Disk Kontrol: $disk_name | Boş %$free_percent | Eşik %$threshold"

        if [ "$free_percent" -lt "$threshold" ]; then
            log_message "KRİTİK DİSK: $disk_name (%$free_percent < %$threshold)"

            # Geçici dosyaya yaz
            echo "Disk Bilgisi:" >>"$TEMP_FILE"
            echo "--------------------------------" >>"$TEMP_FILE"
            echo "Aygıt: $disk_name" >>"$TEMP_FILE"
            echo "Bağlantı Noktası: $mount_point" >>"$TEMP_FILE"
            echo "Kullanım Oranı: %$use_percent" >>"$TEMP_FILE"
            echo "Boş Alan: %$free_percent" >>"$TEMP_FILE"
            echo "Kritik Eşik: %$threshold" >>"$TEMP_FILE"
            echo >>"$TEMP_FILE"

            return 1
        fi
    else
        log_message "HATA: $disk bulunamadı"
    fi
    return 0
}

# Ana kontrol döngüsü
main() {
    # İlk çalıştırmada veya --init ile kurulum
    if [ ! -f "$CONFIG_FILE" ] || [ "$1" == "--init" ]; then
        setup_wizard
        exit 0
    fi

    # Değişkenleri sıfırla
    TEMP_FILE=$(mktemp)
    CRITICAL_COUNT=0

    # Konfigürasyon yükle
    source <(grep -E '^(EMAIL_TO|SMTP_SERVER|SMTP_PORT|SMTP_USER|SMTP_PASS|EMAIL_FROM)=' "$CONFIG_FILE")
    EMAIL_SUBJECT="SUNUCU UYARISI: Kritik Kaynak Seviyesi"

    # Kaynak kontrolü
    while read -r line; do
        # Yorum ve boş satırları atla
        [[ "$line" =~ ^# || -z "$line" ]] && continue

        # RAM kontrolü
        if [[ "$line" =~ ^RAM[[:space:]]+([0-9]+) ]]; then
            check_ram "${BASH_REMATCH[1]}" || CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
            continue
        fi

        # Disk kontrolü
        if [[ "$line" =~ ^/[^[:space:]]+[[:space:]]+[0-9]+ ]]; then
            disk=$(awk '{print $1}' <<<"$line")
            threshold=$(awk '{print $2}' <<<"$line")
            check_disk "$disk" "$threshold" || CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
        fi
    done <"$CONFIG_FILE"

    # E-posta işlemleri
    if [ "$CRITICAL_COUNT" -gt 0 ]; then
        log_message "Kritik durum sayısı: $CRITICAL_COUNT"
        local email_file=$(prepare_email)

        # CURL ile gönderim
        curl --silent --show-error \
            --url "smtp://${SMTP_SERVER}:${SMTP_PORT}" \
            --ssl-reqd \
            --tlsv1.2 \
            --mail-from "$EMAIL_FROM" \
            --mail-rcpt "$EMAIL_TO" \
            --user "${SMTP_USER}:${SMTP_PASS}" \
            --upload-file "$email_file" >>"$LOG_FILE" 2>&1

        [ $? -eq 0 ] && log_message "E-posta gönderildi" || log_message "E-posta gönderilemedi"
        rm -f "$email_file"
    else
        log_message "Tüm kaynaklar normal"
    fi

    # Temizlik
    rm -f "$TEMP_FILE"
}

# Bağımlılık kontrolü
check_dependencies() {
    if ! command -v curl &>/dev/null; then
        log_message "curl yüklü değil, yükleniyor..."
        apt-get update && apt-get install -y curl
    fi
}

# Giriş noktası
case "$1" in
"--help" | "-h")
    show_help
    ;;
*)
    check_dependencies
    main "$@"
    ;;
esac
