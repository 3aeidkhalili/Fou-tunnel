#!/bin/bash

CONFIG_FILE="/etc/fou_tunnel_config"
SERVICE_FILE="/etc/systemd/system/fou-tunnel.service"
echo -e "\033c"
echo -e "\e[1;32m
 ____  ____  ____  ____  _  ____  ____  _     
/  _ \/  _ \/ ___\/ ___\/ \/  __\/  _ \/ \  /|
| / \|| / \||    \|    \| ||  \/|| / \|| |\ ||
| |-||| |-||\___ |\___ || ||    /| |-||| | \||
\_/ \|\_/ \|\____/\____/\_/\_/\_\\_/ \|\_/  \|

TeleGram ID : @TurkAbr

\e[0m"

if [ ! -f "$CONFIG_FILE" ]; then
    # آدرس‌های IP دو سرور را وارد کنید
    read -p "Enter local IP address: " LOCAL_IP
    read -p "Enter remote IP address: " REMOTE_IP
    read -p "Enter local tunnel IP (e.g., 10.20.30.*): " LOCAL_TUNNEL_IP
    read -p "Enter remote tunnel IP (e.g., 10.20.30.*): " REMOTE_TUNNEL_IP
    read -p "Enter local IPv6 tunnel IP (e.g., 2001:db8::1): " LOCAL_IPV6_TUNNEL_IP
    read -p "Enter remote IPv6 tunnel IP (e.g., 2001:db8::2): " REMOTE_IPV6_TUNNEL_IP
    read -p "Enter IPsec PSK: " IPSEC_PSK

    # ذخیره IPها در فایل تنظیمات
    echo "LOCAL_IP=$LOCAL_IP" > $CONFIG_FILE
    echo "REMOTE_IP=$REMOTE_IP" >> $CONFIG_FILE
    echo "LOCAL_TUNNEL_IP=$LOCAL_TUNNEL_IP" >> $CONFIG_FILE
    echo "REMOTE_TUNNEL_IP=$REMOTE_TUNNEL_IP" >> $CONFIG_FILE
    echo "LOCAL_IPV6_TUNNEL_IP=$LOCAL_IPV6_TUNNEL_IP" >> $CONFIG_FILE
    echo "REMOTE_IPV6_TUNNEL_IP=$REMOTE_IPV6_TUNNEL_IP" >> $CONFIG_FILE
    echo "IPSEC_PSK=$IPSEC_PSK" >> $CONFIG_FILE
else
    # خواندن IPها از فایل تنظیمات
    source $CONFIG_FILE
fi

FOU_PORT=5555

# ماژول‌های مورد نیاز را بارگذاری کنید
sudo modprobe fou
sudo modprobe ip_gre
sudo modprobe ip6_tunnel

# حذف رابط‌های شبکه موجود با همان نام قبل از ایجاد آنها
sudo ip link del gre1 2>/dev/null
sudo ip link del new-german 2>/dev/null

# ساخت سوکت FOU برای GRE
sudo ip fou add port $FOU_PORT ipproto gre

# ایجاد رابط تونل GRE با بسته‌بندی FOU
sudo ip link add gre1 type gre key 1 remote $REMOTE_IP local $LOCAL_IP ttl 255 encap fou encap-sport $FOU_PORT encap-dport $FOU_PORT

# تخصیص آدرس IP به تونل GRE
sudo ip addr add $LOCAL_TUNNEL_IP/24 dev gre1

# فعال کردن رابط GRE
sudo ip link set gre1 up

# اضافه کردن مسیر برای شبکه از راه دور
sudo ip route add $REMOTE_TUNNEL_IP/32 dev gre1

# ایجاد تونل 4to6 به روش شما
sudo ip tunnel add new-german mode sit remote $REMOTE_IPV6_TUNNEL_IP local $LOCAL_IPV6_TUNNEL_IP ttl 126
sudo ip link set dev new-german up mtu 1500
sudo ip addr add $LOCAL_IPV6_TUNNEL_IP/64 dev new-german
sudo ip link set new-german mtu 1436
sudo ip link set new-german up

# اجازه ترافیک UDP در پورت 5555 را بدهید
sudo iptables -A INPUT -p udp --dport $FOU_PORT -j ACCEPT
sudo iptables -A OUTPUT -p udp --sport $FOU_PORT -j ACCEPT

# نصب strongSwan اگر قبلاً نصب نشده باشد
if ! command -v ipsec &> /dev/null; then
    sudo apt-get update
    sudo apt-get install -y strongswan
fi

# تنظیم strongSwan
echo "config setup
    charondebug=\"ike 2, knl 2, cfg 2\"

conn %default
    keyexchange=ikev2
    ike=aes256-sha256-modp1024!
    esp=aes256-sha256!

conn ipv6-tunnel
    left=$LOCAL_IPV6_TUNNEL_IP
    leftsubnet=$LOCAL_IPV6_TUNNEL_IP/128
    right=$REMOTE_IPV6_TUNNEL_IP
    rightsubnet=$REMOTE_IPV6_TUNNEL_IP/128
    auto=start
" | sudo tee /etc/ipsec.conf > /dev/null

echo ": PSK \"$IPSEC_PSK\"" | sudo tee /etc/ipsec.secrets > /dev/null

# راه‌اندازی IPsec
sudo systemctl restart strongswan

echo "FOU tunnel has been configured between $LOCAL_IP and $REMOTE_IP"
echo "IPv6 tunnel has been configured between $LOCAL_IPV6_TUNNEL_IP and $REMOTE_IPV6_TUNNEL_IP"
echo "IPsec has been configured and started."

# ایجاد فایل سرویس systemd
sudo bash -c "cat > $SERVICE_FILE" << EOL
[Unit]
Description=FOU Tunnel Setup
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash $0
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOL

# فعال‌سازی سرویس
sudo systemctl daemon-reload
sudo systemctl enable fou-tunnel.service
sudo systemctl start fou-tunnel.service

echo "FOU tunnel service has been created and started."
