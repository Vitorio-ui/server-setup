#!/bin/bash

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
  echo "Скрипт должен быть запущен с правами root!" >&2
  exit 1
fi

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "\n${GREEN}=== НАСТРОЙКА СЕРВЕРА UBUNTU С X-UI И АВТОТУННЕЛЕМ ===${NC}"
read -p "Имя нового пользователя: " username
read -sp "Пароль для $username: " password
echo
read -p "Порт для панели x-ui (по умолчанию 54123): " xui_port
xui_port=${xui_port:-54123}
read -p "Путь к резервной копии x-ui (tar.gz): " xui_backup
read -p "Новый SSH порт на Middleman (по умолчанию 62223): " ssh_port
ssh_port=${ssh_port:-62223}

# Данные для автотуннеля
echo -e "\n${YELLOW}=== Настройка автотуннеля Middle → Gate ===${NC}"
read -p "SSH-пользователь на Gate: " gate_user
read -p "Публичный IP или домен Gate: " gate_host
read -p "Порт SSH на Gate (по умолчанию 62223): " gate_ssh_port
gate_ssh_port=${gate_ssh_port:-62223}
read -p "Локальный порт для проброса (например 30000): " local_port
read -p "Удалённый адрес назначения на Gate (например 127.0.0.1:10000): " remote_dest

# 1. Обновление системы
echo -e "\n${YELLOW}[1/9] Обновление системы...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y sudo ufw fail2ban curl sqlite3 tar autossh openssh-client net-tools

# 2. Создание пользователя
echo -e "\n${YELLOW}[2/9] Создание пользователя...${NC}"
adduser --disabled-password --gecos "" "$username"
echo "$username:$password" | chpasswd
usermod -aG sudo "$username"

# 3. Настройка UFW и Fail2Ban
echo -e "\n${YELLOW}[3/9] Настройка UFW и Fail2Ban...${NC}"
ufw disable
ufw default deny incoming
ufw default allow outgoing
ufw allow "$xui_port/tcp"

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
EOF
systemctl restart fail2ban

# 4. Отключение IPv6
echo -e "\n${YELLOW}[4/9] Отключение IPv6...${NC}"
cat >> /etc/sysctl.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl -p

# 5. Установка x-ui
echo -e "\n${YELLOW}[5/9] Установка x-ui...${NC}"
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)

# 5.1 Восстановление конфигурации
if [ -f "$xui_backup" ]; then
  echo -e "${YELLOW}Восстановление конфигурации x-ui...${NC}"
  systemctl stop x-ui
  tar xzvf "$xui_backup" -C /
  if [ "$xui_port" != "2053" ]; then
    sqlite3 /etc/x-ui/x-ui.db "UPDATE setting SET value='$xui_port' WHERE key='webPort';"
  fi
  systemctl start x-ui
  echo -e "${GREEN}Конфигурация восстановлена и x-ui запущен.${NC}"
else
  echo -e "${YELLOW}Резервная копия не найдена, пропуск восстановления.${NC}"
fi

# 6. Настройка SSH-ключа и копирование на Gate
echo -e "\n${YELLOW}[6/9] Настройка SSH-ключей...${NC}"
sudo -u "$username" ssh-keygen -t rsa -b 4096 -f /home/$username/.ssh/id_rsa -N "" -q
echo -e "${YELLOW}Копирование ключа на Gate...${NC}"
sudo -u "$username" ssh-copy-id -p "$gate_ssh_port" "$gate_user@$gate_host"

# 7. Создание автотуннеля через autossh
echo -e "\n${YELLOW}[7/9] Создание автотуннеля...${NC}"
cat > /etc/systemd/system/autossh-tunnel.service <<EOF
[Unit]
Description=AutoSSH tunnel to Gate
After=network.target

[Service]
User=$username
Environment="AUTOSSH_GATETIME=0"
Environment="AUTOSSH_PORT=0"
ExecStart=/usr/bin/autossh -N -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" \
  -p $gate_ssh_port -L $local_port:$remote_dest $gate_user@$gate_host
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable autossh-tunnel
systemctl start autossh-tunnel

# 8. Проверка туннеля
echo -e "\n${YELLOW}[8/9] Проверка туннеля...${NC}"
sleep 3
if netstat -tnlp | grep -q ":$local_port"; then
  echo -e "${GREEN}✅ Туннель слушает на localhost:$local_port${NC}"
else
  echo -e "${RED}❌ Локальный порт $local_port не слушает!${NC}"
fi

# 9. Настройка SSH (в конце)
echo -e "\n${YELLOW}[9/9] Настройка SSH...${NC}"
ufw allow "$ssh_port/tcp"
sed -i "s/#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
echo "AllowUsers $username" >> /etc/ssh/sshd_config
systemctl restart sshd

# Финал
echo -e "\n${GREEN}Настройка завершена.${NC}"
echo -e "SSH: ${GREEN}$username@$(curl -s ifconfig.me) -p $ssh_port${NC}"
echo -e "x-ui панель: ${GREEN}http://$(curl -s ifconfig.me):$xui_port${NC}"
echo -e "Автотуннель: ${GREEN}localhost:$local_port → $remote_dest на Gate${NC}"

read -p "Нажмите Enter для завершения сессии и входа под новым пользователем... " _
exit
