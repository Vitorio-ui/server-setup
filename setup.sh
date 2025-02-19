#!/bin/bash

# Запрос имени пользователя
read -p "Введите имя нового пользователя: " username
read -sp "Введите пароль для пользователя $username: " password
echo

# Обновление системы
echo "Обновление пакетов..."
apt update && apt upgrade -y

# Установка sudo
echo "Установка sudo..."
apt install sudo -y

# Установка и настройка UFW
echo "Установка UFW..."
apt install ufw -y

# Добавление правил UFW (статус UFW остаётся inactive)
ufw allow 62223/tcp
ufw default deny incoming
ufw default allow outgoing

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
port = 62223
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
EOF

# Перезапуск Fail2Ban
systemctl restart fail2ban

# Проверка статуса Fail2Ban
echo "Проверка статуса Fail2Ban..."
fail2ban-client status

# Установка панели x-ui
echo "Установка панели x-ui..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# Получение порта панели x-ui
xui_port=$(grep -oP '(?<=port: )\d+' /etc/x-ui/x-ui.yaml)

# Добавление порта x-ui в правила UFW
ufw allow $xui_port/tcp

# Создание пользователя
echo "Создание пользователя $username..."
adduser $username --gecos "" --disabled-password
echo "$username:$password" | chpasswd

# Добавление пользователя в группу sudo
usermod -aG sudo $username

# Редактирование конфигурации SSH
echo "Настройка SSH..."
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#Port 22/Port 62223/' /etc/ssh/sshd_config

# Перезапуск SSH
systemctl restart ssh

# Напоминание о необходимости добавления правил UFW для inbound-портов
echo "============================================================"
echo "НАПОМИНАНИЕ:"
echo "Если позже появятся дополнительные inbound-порты, добавьте их в UFW:"
echo "  sudo ufw allow <порт>/tcp"
echo "============================================================"

# Напоминание о необходимости активации UFW
echo "============================================================"
echo "НАПОМИНАНИЕ:"
echo "Чтобы активировать UFW, выполните команду:"
echo "  sudo ufw enable"
echo "Текущий статус UFW:"
ufw status
echo "============================================================"

echo "Настройка завершена!"
echo "Порт панели x-ui: $xui_port"
