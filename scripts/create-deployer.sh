#!/usr/bin/env bash
set -euo pipefail

# Create a deploy user on Ubuntu with an optional name, optional SSH key, optional passwordless sudo.
#
# Examples:
#   sudo bash create-deployer.sh --name deploy
#   sudo bash create-deployer.sh --name vake --pubkey "ssh-ed25519 AAAA... user@host"
#   sudo bash create-deployer.sh --name deploy --passwordless-sudo

usage() {
  cat <<'USAGE'
Usage:
  sudo bash create-deployer.sh --name <username> [--pubkey "<ssh-public-key>"] [--passwordless-sudo]

Options:
  --name <username>           Username to create (required)
  --pubkey "<ssh-public-key>" Adds this public key to /home/<username>/.ssh/authorized_keys (optional)
  --passwordless-sudo         Grants NOPASSWD sudo via /etc/sudoers.d/<username> (optional)

Notes:
  - If the user already exists, the script will ensure sudo group membership
    and (if provided) install the SSH key.
USAGE
}

NAME=""
PUBKEY=""
PASSWORDLESS_SUDO="0"

# Simple long-arg parser
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      NAME="${2:-}"; shift 2;;
    --pubkey)
      PUBKEY="${2:-}"; shift 2;;
    --passwordless-sudo)
      PASSWORDLESS_SUDO="1"; shift 1;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2
      usage; exit 1;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (use: sudo $0 ...)" >&2
  exit 1
fi

if [[ -z "$NAME" ]]; then
  echo "ERROR: --name is required" >&2
  usage
  exit 1
fi

# Basic username validation (Ubuntu-friendly)
if ! [[ "$NAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "ERROR: Invalid username: '$NAME'" >&2
  echo "Use lowercase letters/numbers/underscore/dash; must start with a letter or underscore." >&2
  exit 1
fi

echo "==> Ensuring user exists: $NAME"
if id "$NAME" >/dev/null 2>&1; then
  echo "User '$NAME' already exists."
else
  adduser --disabled-password --gecos "" "$NAME"
fi

echo "==> Ensuring sudo group membership"
usermod -aG sudo "$NAME"

HOME_DIR="$(getent passwd "$NAME" | cut -d: -f6)"
if [[ -z "$HOME_DIR" || ! -d "$HOME_DIR" ]]; then
  echo "ERROR: Could not determine home directory for '$NAME'." >&2
  exit 1
fi

if [[ -n "$PUBKEY" ]]; then
  echo "==> Installing SSH public key for $NAME"
  install -d -m 700 -o "$NAME" -g "$NAME" "$HOME_DIR/.ssh"
  AUTH_KEYS="$HOME_DIR/.ssh/authorized_keys"
  touch "$AUTH_KEYS"
  chown "$NAME:$NAME" "$AUTH_KEYS"
  chmod 600 "$AUTH_KEYS"

  # Append only if not already present
  if grep -Fqx "$PUBKEY" "$AUTH_KEYS"; then
    echo "SSH key already present in authorized_keys."
  else
    echo "$PUBKEY" >> "$AUTH_KEYS"
    echo "SSH key added."
  fi
fi

if [[ "$PASSWORDLESS_SUDO" == "1" ]]; then
  echo "==> Enabling passwordless sudo for $NAME"
  SUDOERS_FILE="/etc/sudoers.d/$NAME"
  echo "$NAME ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
  chmod 440 "$SUDOERS_FILE"
  visudo -c -f "$SUDOERS_FILE" >/dev/null
fi

echo "==> Done."
echo "User: $NAME"
echo "Home: $HOME_DIR"
echo "Sudo: enabled (group sudo)${PASSWORDLESS_SUDO:+, passwordless=$PASSWORDLESS_SUDO}"
