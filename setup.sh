#!/bin/bash

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    echo "Этот скрипт должен быть запущен с правами root. Используйте sudo!" >&2
    exit 1
fi

# Функция для выбора порта с валидацией
select_port() {
    local prompt="$1"
    local default_port="$2"
    local port
    
    while true; do
        read -p "${prompt} [${default_port}]: " port
        port=${port:-$default_port}
        
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1024 ] && [ "$port" -le 65535 ]; then
            echo "$port"
            return
        else
            echo "Ошибка: порт должен быть числом от 1024 до 65535"
        fi
    done
}

# Запрос параметров
echo -e "\n\033[1;34m=== НАСТРОЙКА СЕРВЕРА UBUNTU ===\033[0m"
read -p "Введите имя нового пользователя: " username
ssh_port=$(select_port "Введите SSH порт" 62223)
xui_port=$(select_port "Введите порт для x-ui панели" 2053)

# Обновление системы
echo -e "\n\033[1;32m[1/7] Обновление системы...\033[0m"
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y sudo ufw fail2ban git curl

# Создание пользователя и настройка SSH
echo -e "\n\033[1;32m[2/7] Настройка пользователя и SSH...\033[0m"
adduser --disabled-password --gecos "" "$username"
usermod -aG sudo "$username"

# Настройка SSH
sed -i "s/#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
echo "AllowUsers $username" >> /etc/ssh/sshd_config
systemctl restart sshd

# Настройка брандмауэра
echo -e "\n\033[1;32m[3/7] Настройка UFW...\033[0m"
ufw disable
ufw allow "$ssh_port/tcp"
ufw allow "$xui_port/tcp"
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

# Настройка Fail2Ban
echo -e "\n\033[1;32m[4/7] Настройка Fail2Ban...\033[0m"
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3

[sshd]
enabled = true
port = $ssh_port
EOF
systemctl restart fail2ban

# Отключение IPv6
echo -e "\n\033[1;32m[5/7] Отключение IPv6...\033[0m"
cat >> /etc/sysctl.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl -p

# Генерация SSH ключей для root
echo -e "\n\033[1;32m[6/7] Генерация SSH ключей для root...\033[0m"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N "" -q
cat /root/.ssh/id_ed25519.pub > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

# Установка x-ui с безопасной проверкой
echo -e "\n\033[1;32m[7/7] Установка x-ui...\033[0m"
mkdir -p /tmp/x-ui-install
curl -o /tmp/x-ui-install/install.sh -L https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh

echo -e "\n\033[1;33m=== ВАЖНО! Просмотрите скрипт установки x-ui ===\033[0m"
echo "Нажмите Enter, чтобы открыть скрипт для просмотра..."
read
less /tmp/x-ui-install/install.sh

read -p "Вы уверены, что хотите установить x-ui? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    # Запускаем установку и настраиваем порт
    bash /tmp/x-ui-install/install.sh
    
    # Настройка порта x-ui
    if [ -f "/etc/x-ui/x-ui.db" ]; then
        echo "Настройка порта x-ui: $xui_port"
        systemctl stop x-ui
        apt install -y sqlite3
        sqlite3 /etc/x-ui/x-ui.db "UPDATE setting SET value='$xui_port' WHERE key='webPort'"
        systemctl start x-ui
    fi
else
    echo "Установка x-ui отменена."
fi

# Финализация
echo -e "\n\033[1;34m=== НАСТРОЙКА ЗАВЕРШЕНА ===\033[0m"
echo -e "\033[1;33mСохраните приватный ключ для доступа к серверу:\033[0m"
echo "-----------------------------------------"
cat /root/.ssh/id_ed25519
echo "-----------------------------------------"
echo -e "\nДля подключения к серверу используйте:"
echo "ssh -p $ssh_port -i ~/.ssh/sw_server_key root@$(curl -s ifconfig.me)"
echo -e "\nПорт панели x-ui: \033[1;32m$xui_port\033[0m"
