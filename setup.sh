#!/bin/bash

# Вывод приветствия
echo "Начинаем настройку сервера..."

# Запрос имени пользователя и пароля
read -p "Введите имя нового пользователя: " username
read -sp "Введите пароль для пользователя $username: " password
echo

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
sudo ufw allow 62223/tcp
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
port = 62223
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
EOF

# Перезапуск Fail2Ban
systemctl restart fail2ban

# Установка панели x-ui
echo "Установка панели x-ui..."
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# Получение порта панели x-ui
xui_port=$(grep -oP '(?<=port: )\d+' /etc/x-ui/x-ui.yaml)

# Добавление порта x-ui в правила UFW
echo "Добавление порта x-ui ($xui_port) в правила UFW..."
sudo ufw allow $xui_port/tcp

# Проверка статуса UFW после добавления порта x-ui
echo "Проверка статуса UFW после добавления порта x-ui..."
sudo ufw status

# Создание пользователя и добавление в группу sudo
echo "Создание пользователя $username..."
adduser $username --gecos "" --disabled-password
echo "$username:$password" | chpasswd
usermod -aG sudo $username

# Настройка SSH
echo "Настройка SSH..."
sed -i 's/^PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#Port 22/Port 62223/' /etc/ssh/sshd_config
systemctl restart ssh

echo "Настройка завершена!"
echo "Порт панели x-ui: $xui_port"
