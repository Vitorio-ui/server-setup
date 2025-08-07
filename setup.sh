#!/bin/bash

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
  echo "Этот скрипт должен быть запущен с правами root. Используйте sudo!" >&2
  exit 1
fi

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Запрос параметров
echo -e "\n${GREEN}=== НАСТРОЙКА СЕРВЕРА UBUNTU ===${NC}"
read -p "Введите имя нового пользователя: " username
read -sp "Введите сложный пароль для пользователя $username: " password
echo
read -p "Введите SSH порт (по умолчанию 62223): " ssh_port
ssh_port=${ssh_port:-62223}
read -p "Введите порт для x-ui панели (по умолчанию 2053): " xui_port
xui_port=${xui_port:-2053}
read -p "Введите путь к панели x-ui (например /secretpath/): " xui_path
xui_path=${xui_path:-/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)/}

# 1. Обновление системы
echo -e "\n${YELLOW}[1/8] Обновление системы...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y sudo ufw fail2ban curl sqlite3

# 2. Настройка пользователя
echo -e "\n${YELLOW}[2/8] Создание пользователя $username...${NC}"
adduser --disabled-password --gecos "" "$username"
echo "$username:$password" | chpasswd
usermod -aG sudo "$username"

# 3. Настройка UFW
echo -e "\n${YELLOW}[3/8] Настройка UFW...${NC}"
ufw disable
ufw allow "$xui_port/tcp"  # Временно открываем порт x-ui
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

# 4. Настройка Fail2Ban
echo -e "\n${YELLOW}[4/8] Настройка Fail2Ban...${NC}"
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 3
EOF
systemctl restart fail2ban

# 5. Отключение IPv6
echo -e "\n${YELLOW}[5/8] Отключение IPv6...${NC}"
cat >> /etc/sysctl.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sysctl -p

# 6. Установка x-ui с проверкой
echo -e "\n${YELLOW}[6/8] Установка x-ui...${NC}"
mkdir -p /tmp/x-ui-install
curl -o /tmp/x-ui-install/install.sh -L https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh

echo -e "\n${YELLOW}=== Просмотр скрипта установки x-ui ===${NC}"
echo -e "Нажмите Enter для просмотра скрипта (прокрутка: Space, выход: Q)"
read
less /tmp/x-ui-install/install.sh

read -p "Продолжить установку x-ui? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  echo -e "${GREEN}Установка x-ui...${NC}"
  bash /tmp/x-ui-install/install.sh
  
  # Настройка x-ui
  echo -e "${YELLOW}Настройка панели x-ui...${NC}"
  systemctl stop x-ui
  sqlite3 /etc/x-ui/x-ui.db <<EOF
  UPDATE setting SET value='$xui_port' WHERE key='webPort';
  UPDATE setting SET value='$xui_path' WHERE key='webBasePath';
  UPDATE setting SET value='' WHERE key='webCertFile';
  UPDATE setting SET value='' WHERE key='webKeyFile';
  UPDATE setting SET value='true' WHERE key='webListen';
EOF
  systemctl start x-ui
else
  echo -e "${RED}Установка x-ui отменена${NC}"
fi

# 7. Настройка SSH (в самом конце)
echo -e "\n${YELLOW}[7/8] Настройка SSH...${NC}"
sed -i "s/#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
echo "AllowUsers $username" >> /etc/ssh/sshd_config

# Обновление Fail2Ban для нового SSH порта
sed -i "s/port = .*/port = $ssh_port/" /etc/fail2ban/jail.local
systemctl restart fail2ban

# Обновление UFW
ufw allow "$ssh_port/tcp"
ufw --force enable

systemctl restart sshd

# 8. Финальная настройка
echo -e "\n${YELLOW}[8/8] Завершение настройки...${NC}"
echo -e "${GREEN}=== НАСТРОЙКА ЗАВЕРШЕНА ===${NC}"

# Вывод параметров
echo -e "\n${YELLOW}=== ПАРАМЕТРЫ ДОСТУПА ===${NC}"
echo -e "SSH подключение:"
echo -e "  Порт: ${GREEN}$ssh_port${NC}"
echo -e "  Пользователь: ${GREEN}$username${NC}"
echo -e "\nПанель x-ui:"
echo -e "  URL: ${GREEN}http://$(curl -s ifconfig.me):$xui_port$xui_path${NC}"
echo -e "  Логин: ${GREEN}admin${NC}"
echo -e "  Пароль: ${GREEN}admin${NC}"
echo -e "  Случайный путь: ${GREEN}$xui_path${NC}"
echo -e "\n${RED}ВАЖНО:${NC}"
echo -e "1. Сразу смените пароль в панели x-ui!"
echo -e "2. Для защиты рекомендуется:"
echo -e "   - Настроить SSH туннель для доступа к панели"
echo -e "   - Установить HTTPS сертификат"
echo -e "3. Команда для SSH туннеля:"
echo -e "   ${GREEN}ssh -p $ssh_port -L 8080:localhost:$xui_port $username@$(curl -s ifconfig.me)${NC}"
echo -e "   Затем откройте в браузере: ${GREEN}http://localhost:8080$xui_path${NC}"
