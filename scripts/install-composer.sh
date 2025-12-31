#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (use: sudo $0)"
  exit 1
fi

echo "==> Installing prerequisites"
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl php-cli unzip git

echo "==> Downloading Composer installer"
cd /tmp
EXPECTED_SIG="$(curl -fsSL https://composer.github.io/installer.sig)"
curl -fsSL https://getcomposer.org/installer -o composer-setup.php
ACTUAL_SIG="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [[ "$EXPECTED_SIG" != "$ACTUAL_SIG" ]]; then
  echo "ERROR: Invalid Composer installer signature"
  echo "Expected: $EXPECTED_SIG"
  echo "Actual:   $ACTUAL_SIG"
  rm -f composer-setup.php
  exit 1
fi

echo "==> Installing Composer globally to /usr/local/bin/composer"
php composer-setup.php --install-dir=/usr/local/bin --filename=composer

echo "==> Cleaning up"
rm -f composer-setup.php

echo "==> Verifying"
composer --version
