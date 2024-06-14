#!/bin/bash

# Configuration files and variables
CONFIG_FILE="/etc/fou_tunnel_config"
SERVICE_FILE="/etc/systemd/system/fou-tunnel.service"
REMOTE_TUNNEL_IP=""
REMOTE_TUNNEL_IPV6=""  # Variable to store IPv6 address for IPv4-in-IPv6 tunnel

# Function to display the main menu
show_menu() {
    echo -e "\033c"
    echo -e "\e[1;32m
 ____  ____  ____  ____  _  ____  ____  _     
/  _ \/  _ \/ ___\/ ___\/ \/  __\/  _ \/ \  /|
| / \|| / \||    \|    \| ||  \/|| / \|| |\ ||
| |-||| |-||\___ |\___ || ||    /| |-||| | \||
\_/ \|\_/ \|\____/\____/\_/\_/\_\\_/ \|\_/  \|

TeleGram ID : @TurkAbr

\e[0m"
    echo "1. Configure Tunnel"
    echo "2. Check Remote Connection"
    echo "3. Install bbr.sh and tcp.sh"
    echo "4. Check Tunnel Status"
    echo "5. Exit"
    read -p "Choose an option: " choice
    case $choice in
        1) configure_tunnel ;;
        2) check_remote ;;
        3) install_scripts ;;
        4) check_tunnel_status ;;
        5) exit 0 ;;
        *) echo "Invalid option" && sleep 1 && show_menu ;;
    esac
}

# Function to check remote connection
check_remote() {
    if [ -f "$CONFIG_FILE" ]; then
        source $CONFIG_FILE
        echo "Checking connection to $REMOTE_IP..."
        if ping -c 4 $REMOTE_IP &> /dev/null; then
            echo "Remote IP $REMOTE_IP is reachable."
        else
            echo "Remote IP $REMOTE_IP is not reachable."
        fi
    else
        echo "Configuration file not found. Please configure the tunnel first."
    fi
    read -p "Press Enter to return to menu..." && show_menu
}

# Function to check tunnel status
check_tunnel_status() {
    if [ -z "$REMOTE_TUNNEL_IP" ]; then
        echo "Tunnel IP is not configured."
        read -p "Press Enter to return to menu..." && show_menu
        return
    fi
    
    echo "Checking tunnel status to $REMOTE_TUNNEL_IP..."
    if ping -c 4 $REMOTE_TUNNEL_IP &> /dev/null; then
        echo "Tunnel to $REMOTE_TUNNEL_IP is established and reachable."
    else
        echo "Tunnel to $REMOTE_TUNNEL_IP is not reachable. Re-establishing tunnel..."
        configure_tunnel  # Call configure_tunnel function to re-establish the tunnel
    fi
    read -p "Press Enter to return to menu..." && show_menu
}

# Function to install required scripts (bbr.sh and tcp.sh)
install_scripts() {
    # Install bbr.sh
    wget -N --no-check-certificate https://github.com/teddysun/across/raw/master/bbr.sh && chmod +x bbr.sh && bash bbr.sh

    # Install tcp.sh and execute with necessary inputs
    wget -N --no-check-certificate "https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh" && chmod +x tcp.sh

    # Execute tcp.sh script with specific inputs
    echo -e "10\n" | ./tcp.sh
    echo "4" | ./tcp.sh

    read -p "Press Enter to return to menu..." && show_menu
}

# Function to configure the tunnel
configure_tunnel() {
    if [ ! -f "$CONFIG_FILE" ]; then
        read -p "Enter local IP address: " LOCAL_IP
        read -p "Enter remote IP address: " REMOTE_IP
        read -p "Enter local tunnel IP (e.g., 30.30.30.2): " LOCAL_TUNNEL_IP
        read -p "Enter remote tunnel IP (e.g., 30.30.30.1): " REMOTE_TUNNEL_IP
        read -p "Enter remote IPv6 address for IPv4-in-IPv6 tunnel: " REMOTE_TUNNEL_IPV6

        echo "LOCAL_IP=$LOCAL_IP" > $CONFIG_FILE
        echo "REMOTE_IP=$REMOTE_IP" >> $CONFIG_FILE
        echo "LOCAL_TUNNEL_IP=$LOCAL_TUNNEL_IP" >> $CONFIG_FILE
        echo "REMOTE_TUNNEL_IP=$REMOTE_TUNNEL_IP" >> $CONFIG_FILE
        echo "REMOTE_TUNNEL_IPV6=$REMOTE_TUNNEL_IPV6" >> $CONFIG_FILE

        REMOTE_TUNNEL_IP=$REMOTE_TUNNEL_IP  # Set global variable for tunnel IP
    else
        source $CONFIG_FILE
        REMOTE_TUNNEL_IP=$REMOTE_TUNNEL_IP  # Set global variable for tunnel IP
    fi

    TCP_PORT=443

    # Install necessary packages if not already installed
    if ! command -v socat &> /dev/null; then
        echo "Installing socat..."
        sudo apt-get update
        sudo apt-get install -y socat
	sudo apt-get install -y strongswan strongswan-pki
    fi

    # Load necessary kernel modules if not already loaded
    sudo modprobe ip_gre

    sudo ip link del gre1 2>/dev/null

    sudo socat TCP-LISTEN:$TCP_PORT,fork,reuseaddr TUN:gre1,up &

    sudo ip link add gre1 type gre remote $REMOTE_IP local $LOCAL_IP ttl 255

    sudo ip addr add $LOCAL_TUNNEL_IP/24 dev gre1

    sudo ip link set gre1 mtu 1300

    sudo ip link set gre1 up

    sudo ip route add $REMOTE_TUNNEL_IP/32 dev gre1

    sudo iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1200

    sudo iptables -A INPUT -f -j ACCEPT
    sudo iptables -A OUTPUT -f -j ACCEPT
    sudo iptables -A FORWARD -f -j ACCEPT

    sudo iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

    sudo iptables -A INPUT -p tcp --dport $TCP_PORT -j ACCEPT
    sudo iptables -A OUTPUT -p tcp --sport $TCP_PORT -j ACCEPT

    echo "TCP tunnel has been configured between $LOCAL_IP and $REMOTE_IP"
    echo "IPv4-in-IPv6 tunnel configured to $REMOTE_TUNNEL_IPV6"

    # Define a function to handle tunnel reconfiguration and restart
    restart_tunnel() {
        sudo systemctl stop fou-tunnel.service
        sudo ip link del gre1 2>/dev/null
        sudo ip link add gre1 type gre remote $REMOTE_IP local $LOCAL_IP ttl 255
        sudo ip addr add $LOCAL_TUNNEL_IP/24 dev gre1
        sudo ip link set gre1 mtu 1300
        sudo ip link set gre1 up
        sudo ip route add $REMOTE_TUNNEL_IP/32 dev gre1
        sudo systemctl start fou-tunnel.service
    }

    # Infinite loop to check tunnel status every 20 minutes
    while true; do
        if ping -c 4 $REMOTE_TUNNEL_IP &> /dev/null; then
            echo "Tunnel to $REMOTE_TUNNEL_IP is established and reachable."
        else
            echo "Tunnel to $REMOTE_TUNNEL_IP is not reachable. Re-establishing tunnel..."
            restart_tunnel
        fi
        sleep 1200  # 20 minutes
    done
}

# Start executing the script by showing the menu
show_menu
