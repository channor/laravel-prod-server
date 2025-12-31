#!/usr/bin/env bash
set -euo pipefail

PHP_VERSION="8.2"
export DEBIAN_FRONTEND=noninteractive

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (use: sudo $0)"
  exit 1
fi

echo "==> Updating apt + installing prerequisites"
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release software-properties-common apt-transport-https

echo "==> Adding Ondrej PHP PPA (for PHP ${PHP_VERSION} on Ubuntu)"
add-apt-repository -y ppa:ondrej/php
apt-get update -y

echo "==> Installing NGINX, Git, PHP ${PHP_VERSION} (FPM/CLI) + common extensions"
apt-get install -y \
  nginx git \
  "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-cli" "php${PHP_VERSION}-common" \
  "php${PHP_VERSION}-opcache" "php${PHP_VERSION}-readline" \
  "php${PHP_VERSION}-mbstring" "php${PHP_VERSION}-xml" "php${PHP_VERSION}-curl" \
  "php${PHP_VERSION}-zip" "php${PHP_VERSION}-bcmath" "php${PHP_VERSION}-intl" \
  "php${PHP_VERSION}-gd" \
  "php${PHP_VERSION}-mysql" "php${PHP_VERSION}-pgsql" \
  "php${PHP_VERSION}-redis"

echo "==> Installing Imagick (best-effort)"
# PPA usually provides versioned imagick; fall back to distro package name if needed.
if apt-cache show "php${PHP_VERSION}-imagick" >/dev/null 2>&1; then
  apt-get install -y "php${PHP_VERSION}-imagick" imagemagick
else
  apt-get install -y php-imagick imagemagick || true
fi

echo "==> Enabling + starting services"
if command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now nginx
  systemctl enable --now "php${PHP_VERSION}-fpm"
else
  service nginx start || true
  service "php${PHP_VERSION}-fpm" start || true
fi

echo "==> Quick sanity checks"
php -v | head -n 2 || true
php -m | egrep -i 'mbstring|xml|curl|zip|bcmath|intl|gd|imagick|mysqli|pdo_mysql|pgsql|pdo_pgsql|redis|opcache' || true
nginx -v 2>&1 || true

echo "==> Done."
echo "PHP-FPM socket is typically at: /run/php/php${PHP_VERSION}-fpm.sock"
