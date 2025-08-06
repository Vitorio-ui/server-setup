#!/bin/bash

# Вывод приветствия
echo "Начинаем настройку сервера..."

# Запрос имени пользователя и пароля
read -p "Введите имя нового пользователя: " username
read -sp "Введите пароль для пользователя $username: " password
echo

# Запрос порта для SSH
read -p "Введите номер порта для SSH (по умолчанию 62223): " ssh_port
ssh_port=${ssh_port:-62223}  # Если порт не введён, используем 62223

# Обновление системы
echo "Обновление пакетов..."
apt update && apt upgrade -y

# Установка sudo
echo "Установка sudo..."
apt install sudo -y

# Установка UFW
echo "Установка UFW..."
apt install ufw -y

# Проверка статуса UFW
ufw_status=$(sudo ufw status | grep -w "Status" | awk '{print $2}')
echo "Текущий статус UFW: $ufw_status"

# Если UFW активен, останавливаем его
if [ "$ufw_status" = "active" ]; then
    echo "Останавливаем UFW..."
    sudo ufw disable
fi

# Добавление правил UFW
echo "Добавление правил UFW..."
sudo ufw allow $ssh_port/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Проверка статуса UFW после добавления правил
echo "Проверка статуса UFW после добавления правил..."
sudo ufw status

# Установка и настройка Fail2Ban
echo "Установка Fail2Ban..."
apt install fail2ban -y

# Создание конфигурации Fail2Ban
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = $ssh_port
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
EOF

# Перезапуск Fail2Ban
systemctl restart fail2ban