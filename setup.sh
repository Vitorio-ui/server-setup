#!/bin/bash

echo "=== НАСТРОЙКА СЕРВЕРА ==="

# Запрос параметров
read -p "Введите имя нового пользователя: " username
read -sp "Введите пароль: " password
echo
read -p "SSH порт (по умолчанию 62223): " ssh_port
ssh_port=${ssh_port:-62223}

# Обновление системы
echo "Обновление пакетов..."
apt update && apt upgrade -y
apt install -y sudo ufw fail2ban

# Создание пользователя
echo "Создание пользователя $username..."
adduser --disabled-password --gecos "" $username
echo "$username:$password" | chpasswd
usermod -aG sudo $username

# Настройка SSH
echo "Настройка SSH..."
sed -i "s/#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
echo "AllowUsers $username" >> /etc/ssh/sshd_config
systemctl restart sshd

# Настройка UFW
echo "Настройка фаервола..."
ufw disable
ufw allow $ssh_port/tcp
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

# Настройка Fail2Ban
echo "Настройка Fail2Ban..."
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
echo "Отключение IPv6..."
cat >> /etc/sysctl.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl -p

# Безопасная установка x-ui
echo "Установка x-ui..."
mkdir -p /tmp/x-ui-install
curl -o /tmp/x-ui-install/install.sh -L https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh
echo "Проверьте содержимое скрипта:"
less /tmp/x-ui-install/install.sh
read -p "Нажмите Enter для продолжения установки или Ctrl+C для отмены..."
bash /tmp/x-ui-install/install.sh

echo "=== НАСТРОЙКА ЗАВЕРШЕНА ==="
echo "Для подключения используйте:"
echo "1. Сохраните этот ключ на Windows:"
cat /home/$username/.ssh/id_ed25519
echo "2. Подключайтесь командой:"
echo "ssh -p $ssh_port -i путь_к_ключу $username@$(hostname -I | awk '{print $1}')"
