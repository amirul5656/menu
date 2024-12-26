#!/bin/bash

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Function to draw a line
draw_line() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to draw a box with title
draw_box_title() {
    local title="$1"
    echo -e "${BLUE}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} ${WHITE}$title${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────────────┘${NC}"
}

# Function 1: Display system information
show_system_info() {
    clear
    draw_box_title "System Information"
    echo -e "${BLUE}• ${NC}OS      : $(lsb_release -d | cut -f2)"
    echo -e "${BLUE}• ${NC}RAM     : $(free -m | awk 'NR==2{printf "%s/%s MB\n", $3,$2 }')"
    echo -e "${BLUE}• ${NC}DATE    : $(date +"%Y-%m-%d")"
    echo -e "${BLUE}• ${NC}TIME    : $(date +"%H:%M:%S")"
    echo -e "${BLUE}• ${NC}UPTIME  : $(uptime -p)"
    echo -e "${BLUE}• ${NC}IP      : $(hostname -I | awk '{print $1}')"
    echo -e "${BLUE}• ${NC}HOSTNAME: $(hostname)"
    draw_line
}

# Function 2: WordPress Installation
install_wordpress() {
    clear
    draw_box_title "WordPress Installation"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]
    then
        echo "This script must be run as root or with sudo"
        read -p "Press enter to continue..."
        return
    fi

    read -p "Enter domain name (example: example.com): " DOMAIN
    read -p "Enter database name: " DB_NAME
    read -p "Enter database user: " DB_USER
    read -sp "Enter database user password: " DB_PASS
    echo
    read -sp "Enter MariaDB root password: " MARIADB_ROOT_PASSWORD
    echo
    read -p "Enter email for SSL certificate: " SSL_EMAIL

    DOC_ROOT="/var/www/html/$DOMAIN"
    NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
    NGINX_LINK="/etc/nginx/sites-enabled/$DOMAIN"

    draw_line
    echo "Installing WordPress..."
    
    # Add PHP 8.3 repository
    add-apt-repository -y ppa:ondrej/php
    apt-get update

    # Install required packages
    apt-get install -y nginx php8.3-fpm php8.3-mysql php8.3-curl php8.3-gd php8.3-mbstring php8.3-xml php8.3-xmlrpc php8.3-soap php8.3-intl php8.3-zip unzip

    # Check and install MariaDB if needed
    if ! dpkg -l | grep -q mariadb-server; then
        echo "Installing MariaDB..."
        apt-get install -y mariadb-server
    fi

    # Configure MariaDB
    mysql -u root -p"$MARIADB_ROOT_PASSWORD" <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

    # Create document root directory
    mkdir -p $DOC_ROOT
    chown -R www-data:www-data $DOC_ROOT
    chmod -R 755 $DOC_ROOT

    # Configure Nginx
    cat <<EOL > $NGINX_CONF
server {
    listen 80;
    root $DOC_ROOT;
    index index.php index.html index.htm index.nginx-debian.html;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

    # Enable Nginx configuration
    ln -s $NGINX_CONF $NGINX_LINK
    nginx -t && systemctl reload nginx

    # Download and configure WordPress
    wget https://wordpress.org/latest.tar.gz -O /tmp/latest.tar.gz
    tar -xzvf /tmp/latest.tar.gz -C /tmp/
    cp -r /tmp/wordpress/* $DOC_ROOT/
    rm /tmp/latest.tar.gz

    # Configure wp-config.php
    cp $DOC_ROOT/wp-config-sample.php $DOC_ROOT/wp-config.php
    sed -i "s/database_name_here/$DB_NAME/" $DOC_ROOT/wp-config.php
    sed -i "s/username_here/$DB_USER/" $DOC_ROOT/wp-config.php
    sed -i "s/password_here/$DB_PASS/" $DOC_ROOT/wp-config.php

    # Set permissions
    chown -R www-data:www-data $DOC_ROOT
    chmod -R 755 $DOC_ROOT

    # Install and configure SSL
    apt-get install -y certbot python3-certbot-nginx
    certbot --nginx -d $DOMAIN -d www.$DOMAIN --non-interactive --agree-tos --email $SSL_EMAIL

    # Update Nginx configuration for SSL
    cat <<EOL > $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN www.$DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    root $DOC_ROOT;
    index index.php index.html index.htm index.nginx-debian.html;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

    nginx -t && systemctl reload nginx
    echo "WordPress installation completed. You can access your site at https://$DOMAIN"
    read -p "Press enter to continue..."
}

# Function 3: Service Management
manage_services() {
    clear
    draw_box_title "Service Management"
    echo "1. View running services"
    echo "2. Start a service"
    echo "3. Stop a service"
    draw_line
    read -p "Select option: " subchoice
    case $subchoice in
        1) systemctl list-units --type=service --state=running ;;
        2) 
            read -p "Enter service name: " service
            systemctl start $service 
            ;;
        3) 
            read -p "Enter service name: " service
            systemctl stop $service 
            ;;
    esac
    read -p "Press enter to continue..."
}

# Function 4: System Updates
do_system_updates() {
    clear
    draw_box_title "System Updates"
    apt update && apt upgrade -y
    read -p "Press enter to continue..."
}

# Function 5: Network Diagnostics
network_diagnostics() {
    clear
    draw_box_title "Network Diagnostics"
    ping -c 4 8.8.8.8
    draw_line
    read -p "Press enter to continue..."
}

# Function 6: User Management
manage_users() {
    clear
    draw_box_title "User Management"
    cut -d: -f1 /etc/passwd
    draw_line
    read -p "Press enter to continue..."
}

# Function 7: View System Logs
view_logs() {
    clear
    draw_box_title "System Logs"
    tail -n 50 /var/log/syslog
    draw_line
    read -p "Press enter to continue..."
}

# Function 8: Disk Usage
check_disk_usage() {
    clear
    draw_box_title "Disk Usage"
    df -h
    draw_line
    read -p "Press enter to continue..."
}

# Function 9: Process Monitor
monitor_processes() {
    clear
    draw_box_title "Process Monitor"
    top -n 1
    draw_line
    read -p "Press enter to continue..."
}

# Main menu function
show_menu() {
    while true; do
        show_system_info
        echo
        draw_box_title "Main Menu"
        echo -e "${BLUE}[01]${NC} System Information     ${BLUE}[06]${NC} User Management"
        echo -e "${BLUE}[02]${NC} Install WordPress      ${BLUE}[07]${NC} View System Logs"
        echo -e "${BLUE}[03]${NC} Service Management     ${BLUE}[08]${NC} Disk Usage"
        echo -e "${BLUE}[04]${NC} System Updates         ${BLUE}[09]${NC} Process Monitor"
        echo -e "${BLUE}[05]${NC} Network Diagnostics    ${BLUE}[10]${NC} Exit"
        draw_line
        echo
        read -p "Select menu [1-10]: " choice

        case $choice in
            1) show_system_info; read -p "Press enter to continue..." ;;
            2) install_wordpress ;;
            3) manage_services ;;
            4) do_system_updates ;;
            5) network_diagnostics ;;
            6) manage_users ;;
            7) view_logs ;;
            8) check_disk_usage ;;
            9) monitor_processes ;;
            10) 
                clear
                echo "Thank you for using the system"
                exit 0 
                ;;
            *) echo "Invalid option" ;;
        esac
    done
}

# Start the menu
show_menu
