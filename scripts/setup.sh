#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PHP_VERSION="8.2"
TIMEZONE="UTC"
DEPLOY_USER="deploy"
DEPLOY_GROUP="deploy"
APP_PATH="/var/www/laravel-app"
APP_URL="https://example.com"
SSH_PORT="22"
DEPLOY_SSH_KEY=""
REPO_URL=""
WITH_NODE="false"
WITH_REDIS="false"
WITH_SUPERVISOR="false"
WITH_LETSENCRYPT="false"
WITH_MYSQL="false"
FORCE_HTTPS="false"
RUN_MIGRATIONS="false"
SKIP_SSH_HARDENING="false"
SKIP_FIREWALL="false"

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  --php-version <ver>       PHP version to install (default: $PHP_VERSION)
  --timezone <tz>           Timezone for the server (default: $TIMEZONE)
  --deploy-user <user>      Deploy user to create/manage (default: $DEPLOY_USER)
  --deploy-group <group>    Deploy group (default: $DEPLOY_GROUP)
  --app-path <path>         Application directory (default: $APP_PATH)
  --app-url <url>           Application URL for .env (default: $APP_URL)
  --repo-url <git>          Git repository to clone (optional)
  --ssh-port <port>         SSH port (default: $SSH_PORT)
  --deploy-ssh-key <key>    Public key to authorize for deploy user (~/.ssh/authorized_keys)
  --with-node               Install Node.js + npm
  --with-redis              Install Redis server
  --with-supervisor         Install Supervisor for queue workers
  --with-letsencrypt        Install Certbot for HTTPS
  --with-mysql              Install MySQL server
  --force-https             Configure Nginx to force HTTPS (requires certificate)
  --run-migrations          Run php artisan migrate --force
  --skip-ssh-hardening      Do not modify sshd_config
  --skip-firewall           Skip UFW setup
  --dry-run                 Print commands without executing
  --skip-root-check         Bypass root check (useful for dry-run/tests)
  --help                    Show this help message

Environment overrides:
  DRY_RUN=true              Same as --dry-run
  SKIP_ROOT_CHECK=true      Same as --skip-root-check
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --php-version) PHP_VERSION="$2"; shift 2 ;;
      --timezone) TIMEZONE="$2"; shift 2 ;;
      --deploy-user) DEPLOY_USER="$2"; shift 2 ;;
      --deploy-group) DEPLOY_GROUP="$2"; shift 2 ;;
      --app-path) APP_PATH="$2"; shift 2 ;;
      --app-url) APP_URL="$2"; shift 2 ;;
      --repo-url) REPO_URL="$2"; shift 2 ;;
      --ssh-port) SSH_PORT="$2"; shift 2 ;;
      --deploy-ssh-key) DEPLOY_SSH_KEY="$2"; shift 2 ;;
      --with-node) WITH_NODE="true"; shift ;;
      --with-redis) WITH_REDIS="true"; shift ;;
      --with-supervisor) WITH_SUPERVISOR="true"; shift ;;
      --with-letsencrypt) WITH_LETSENCRYPT="true"; shift ;;
      --with-mysql) WITH_MYSQL="true"; shift ;;
      --force-https) FORCE_HTTPS="true"; shift ;;
      --run-migrations) RUN_MIGRATIONS="true"; shift ;;
      --skip-ssh-hardening) SKIP_SSH_HARDENING="true"; shift ;;
      --skip-firewall) SKIP_FIREWALL="true"; shift ;;
      --dry-run) DRY_RUN="true"; export DRY_RUN; shift ;;
      --skip-root-check) SKIP_ROOT_CHECK="true"; export SKIP_ROOT_CHECK; shift ;;
      --help) usage; exit 0 ;;
      *) log "ERROR" "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
}

update_os() {
  log "INFO" "Updating OS packages and installing basics"
  run_cmd "apt-get update"
  run_cmd "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
  ensure_package tzdata
  run_cmd "timedatectl set-timezone '$TIMEZONE'"
  ensure_package sudo
  ensure_package ufw
  ensure_package fail2ban
  ensure_package unattended-upgrades
}

create_deploy_user() {
  log "INFO" "Ensuring deploy user $DEPLOY_USER exists"
  if id "$DEPLOY_USER" >/dev/null 2>&1; then
    log "INFO" "User $DEPLOY_USER already exists"
  else
    run_cmd "groupadd -f $DEPLOY_GROUP"
    run_cmd "useradd -m -g $DEPLOY_GROUP -s /bin/bash $DEPLOY_USER"
    run_cmd "usermod -aG sudo $DEPLOY_USER"
  fi

  ensure_directory "/home/$DEPLOY_USER/.ssh" "$DEPLOY_USER:$DEPLOY_GROUP" 700
  if [[ -n "$DEPLOY_SSH_KEY" ]]; then
    run_cmd "touch /home/$DEPLOY_USER/.ssh/authorized_keys"
    run_cmd "chmod 600 /home/$DEPLOY_USER/.ssh/authorized_keys"
    run_cmd "chown $DEPLOY_USER:$DEPLOY_GROUP /home/$DEPLOY_USER/.ssh/authorized_keys"
    append_unique_line "$DEPLOY_SSH_KEY" "/home/$DEPLOY_USER/.ssh/authorized_keys"
  fi
}

configure_ssh() {
  if [[ "$SKIP_SSH_HARDENING" == "true" ]]; then
    log "INFO" "Skipping SSH hardening"
    return
  fi
  log "INFO" "Hardening SSH configuration"
  local sshd_conf="/etc/ssh/sshd_config"
  run_cmd "sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' $sshd_conf"
  run_cmd "sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' $sshd_conf"
  run_cmd "sed -i 's/^#\?Port.*/Port $SSH_PORT/' $sshd_conf"
  run_cmd "systemctl restart sshd"
}

configure_firewall() {
  if [[ "$SKIP_FIREWALL" == "true" ]]; then
    log "INFO" "Skipping firewall setup"
    return
  fi
  log "INFO" "Configuring UFW firewall"
  run_cmd "ufw allow $SSH_PORT/tcp"
  run_cmd "ufw allow 'Nginx Full'"
  run_cmd "ufw --force enable"
}

install_php_stack() {
  log "INFO" "Installing PHP $PHP_VERSION, Nginx and extensions"
  run_cmd "apt-get install -y software-properties-common ca-certificates lsb-release apt-transport-https"
  run_cmd "add-apt-repository -y ppa:ondrej/php"
  run_cmd "apt-get update"
  local php_packages=("php$PHP_VERSION" "php$PHP_VERSION-fpm" "php$PHP_VERSION-cli" "php$PHP_VERSION-common" \
    "php$PHP_VERSION-mysql" "php$PHP_VERSION-xml" "php$PHP_VERSION-mbstring" "php$PHP_VERSION-curl" "php$PHP_VERSION-zip" \
    "php$PHP_VERSION-bcmath" "php$PHP_VERSION-intl" "php$PHP_VERSION-gd" "php$PHP_VERSION-imagick" "php$PHP_VERSION-redis")
  run_cmd "apt-get install -y nginx git ${php_packages[*]}"
  run_cmd "systemctl enable nginx php$PHP_VERSION-fpm"
  run_cmd "systemctl restart nginx php$PHP_VERSION-fpm"
}

install_composer() {
  log "INFO" "Installing Composer"
  if command -v composer >/dev/null 2>&1; then
    log "INFO" "Composer already installed"
    return
  fi
  run_cmd "php -r 'copy(\"https://getcomposer.org/installer\", \"composer-setup.php\");'"
  run_cmd "php composer-setup.php --install-dir=/usr/local/bin --filename=composer"
  run_cmd "rm composer-setup.php"
}

install_node() {
  if [[ "$WITH_NODE" != "true" ]]; then return; fi
  log "INFO" "Installing Node.js and npm"
  run_cmd "apt-get install -y nodejs npm"
}

install_optional_services() {
  if [[ "$WITH_REDIS" == "true" ]]; then
    ensure_package redis-server
    run_cmd "systemctl enable redis-server"
    run_cmd "systemctl restart redis-server"
  fi

  if [[ "$WITH_SUPERVISOR" == "true" ]]; then
    ensure_package supervisor
    run_cmd "systemctl enable supervisor"
    run_cmd "systemctl restart supervisor"
  fi

  if [[ "$WITH_LETSENCRYPT" == "true" ]]; then
    ensure_package certbot
    ensure_package python3-certbot-nginx
  fi
}

setup_app_directory() {
  log "INFO" "Preparing application directory at $APP_PATH"
  ensure_directory "$APP_PATH" "$DEPLOY_USER:$DEPLOY_GROUP" 755
}

generate_ssh_key() {
  local key_path="/home/$DEPLOY_USER/.ssh/id_ed25519"
  if [[ -f "$key_path" ]]; then
    log "INFO" "SSH key already exists at $key_path"
    return
  fi
  log "INFO" "Generating SSH key for $DEPLOY_USER"
  run_cmd "sudo -u $DEPLOY_USER ssh-keygen -t ed25519 -f $key_path -N ''"
  run_cmd "chown $DEPLOY_USER:$DEPLOY_GROUP $key_path $key_path.pub"
  log "INFO" "Public key to add in Git provider:\n$(cat $key_path.pub 2>/dev/null || true)"
}

clone_repo() {
  if [[ -z "$REPO_URL" ]]; then
    log "INFO" "No repo-url provided, skipping clone"
    return
  fi
  log "INFO" "Cloning repository $REPO_URL into $APP_PATH"
  run_cmd "sudo -u $DEPLOY_USER git clone $REPO_URL $APP_PATH"
}

configure_env() {
  local env_file="$APP_PATH/.env"
  if [[ ! -f "$env_file" && -f "$APP_PATH/.env.example" ]]; then
    run_cmd "sudo -u $DEPLOY_USER cp $APP_PATH/.env.example $env_file"
  fi
  run_cmd "sudo -u $DEPLOY_USER php -r \"file_exists('$env_file') ?: exit(0);\""
  run_cmd "sudo -u $DEPLOY_USER sed -i 's/^APP_ENV=.*/APP_ENV=production/' $env_file"
  run_cmd "sudo -u $DEPLOY_USER sed -i 's/^APP_DEBUG=.*/APP_DEBUG=false/' $env_file"
  run_cmd "sudo -u $DEPLOY_USER sed -i "'"'"s#^APP_URL=.*#APP_URL=$APP_URL#'"'"'" $env_file"
}

install_dependencies() {
  log "INFO" "Installing Composer dependencies"
  run_cmd "cd $APP_PATH && sudo -u $DEPLOY_USER composer install --no-dev --optimize-autoloader"
  if [[ "$WITH_NODE" == "true" ]]; then
    run_cmd "cd $APP_PATH && sudo -u $DEPLOY_USER npm install"
    run_cmd "cd $APP_PATH && sudo -u $DEPLOY_USER npm run build"
  fi
}

setup_permissions() {
  log "INFO" "Setting Laravel writable directories"
  run_cmd "chown -R $DEPLOY_USER:$DEPLOY_GROUP $APP_PATH"
  run_cmd "find $APP_PATH -type f -exec chmod 644 {} +"
  run_cmd "find $APP_PATH -type d -exec chmod 755 {} +"
  run_cmd "chgrp -R www-data $APP_PATH/storage $APP_PATH/bootstrap/cache"
  run_cmd "chmod -R 775 $APP_PATH/storage $APP_PATH/bootstrap/cache"
}

artisan_tasks() {
  if [[ -x "$APP_PATH/artisan" ]]; then
    run_cmd "cd $APP_PATH && sudo -u $DEPLOY_USER php artisan key:generate --force"
    run_cmd "cd $APP_PATH && sudo -u $DEPLOY_USER php artisan storage:link"
    if [[ "$RUN_MIGRATIONS" == "true" ]]; then
      run_cmd "cd $APP_PATH && sudo -u $DEPLOY_USER php artisan migrate --force"
    fi
    run_cmd "cd $APP_PATH && sudo -u $DEPLOY_USER php artisan config:cache"
    run_cmd "cd $APP_PATH && sudo -u $DEPLOY_USER php artisan route:cache"
    run_cmd "cd $APP_PATH && sudo -u $DEPLOY_USER php artisan view:cache"
  else
    log "INFO" "artisan not found, skipping framework tasks"
  fi
}

configure_nginx() {
  log "INFO" "Configuring Nginx site"
  local site_name
  site_name=$(basename "$APP_PATH")
  local nginx_conf="/etc/nginx/sites-available/$site_name"
  local php_sock="/run/php/php$PHP_VERSION-fpm.sock"
  cat <<NGINX_CONF | run_cmd "cat > $nginx_conf"
server {
    listen 80;
    server_name _;
    root $APP_PATH/public;

    index index.php index.html;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$php_sock;
    }

    location ~ /\. {
        deny all;
    }
}
NGINX_CONF

  if [[ "$FORCE_HTTPS" == "true" ]]; then
    cat <<HTTPS_CONF | run_cmd "cat >> $nginx_conf"

server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}
HTTPS_CONF
  fi

  run_cmd "ln -sf $nginx_conf /etc/nginx/sites-enabled/$site_name"
  run_cmd "nginx -t"
  run_cmd "systemctl reload nginx"
}

main() {
  parse_args "$@"
  require_root

  update_os
  create_deploy_user
  configure_ssh
  configure_firewall
  install_php_stack
  install_composer
  install_node
  install_optional_services
  setup_app_directory
  generate_ssh_key
  clone_repo
  configure_env
  install_dependencies
  setup_permissions
  artisan_tasks
  configure_nginx

  log "INFO" "Setup complete"
}

main "$@"
