#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

MYSQL_ROOT_PASSWORD=""
APP_DB="laravel_prod"
APP_DB_USER="laravel_user"
APP_DB_PASSWORD=""
MIGRATION_USER="laravel_migrator"
MIGRATION_PASSWORD=""
BIND_ADDRESS="127.0.0.1"

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  --root-password <pwd>     Root password (default: generated)
  --app-db <name>           Application database name (default: $APP_DB)
  --app-user <user>         Application DB user (default: $APP_DB_USER)
  --app-password <pwd>      Application DB user password (default: generated)
  --migration-user <user>   Migration DB user (default: $MIGRATION_USER)
  --migration-password <p>  Migration DB user password (default: generated)
  --bind-address <addr>     MySQL bind address (default: $BIND_ADDRESS)
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
      --root-password) MYSQL_ROOT_PASSWORD="$2"; shift 2 ;;
      --app-db) APP_DB="$2"; shift 2 ;;
      --app-user) APP_DB_USER="$2"; shift 2 ;;
      --app-password) APP_DB_PASSWORD="$2"; shift 2 ;;
      --migration-user) MIGRATION_USER="$2"; shift 2 ;;
      --migration-password) MIGRATION_PASSWORD="$2"; shift 2 ;;
      --bind-address) BIND_ADDRESS="$2"; shift 2 ;;
      --dry-run) DRY_RUN="true"; export DRY_RUN; shift ;;
      --skip-root-check) SKIP_ROOT_CHECK="true"; export SKIP_ROOT_CHECK; shift ;;
      --help) usage; exit 0 ;;
      *) log "ERROR" "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
}

mysql_query() {
  local query="$1"
  local auth=("-u" "root")
  if [[ -n "$MYSQL_ROOT_PASSWORD" ]]; then
    auth+=("-p$MYSQL_ROOT_PASSWORD")
  fi
  run_cmd "mysql ${auth[*]} -e \"$query\""
}

install_mysql() {
  log "INFO" "Installing MySQL server"
  run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server"
  run_cmd "sed -i 's/^bind-address.*/bind-address = $BIND_ADDRESS/' /etc/mysql/mysql.conf.d/mysqld.cnf"
  run_cmd "systemctl enable mysql"
  run_cmd "systemctl restart mysql"
}

secure_mysql() {
  log "INFO" "Securing MySQL root account"
  if [[ -z "$MYSQL_ROOT_PASSWORD" ]]; then
    MYSQL_ROOT_PASSWORD=$(generate_password)
    log "INFO" "Generated root password: $MYSQL_ROOT_PASSWORD"
  fi
  mysql_query "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD'; FLUSH PRIVILEGES;"
}

create_database_and_users() {
  log "INFO" "Creating database and users"
  [[ -n "$APP_DB_PASSWORD" ]] || APP_DB_PASSWORD=$(generate_password)
  [[ -n "$MIGRATION_PASSWORD" ]] || MIGRATION_PASSWORD=$(generate_password)
  mysql_query "CREATE DATABASE IF NOT EXISTS \`$APP_DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  mysql_query "CREATE USER IF NOT EXISTS '$APP_DB_USER'@'%' IDENTIFIED BY '$APP_DB_PASSWORD';"
  mysql_query "CREATE USER IF NOT EXISTS '$MIGRATION_USER'@'%' IDENTIFIED BY '$MIGRATION_PASSWORD';"
  mysql_query "GRANT SELECT, INSERT, UPDATE, DELETE ON \`$APP_DB\`.* TO '$APP_DB_USER'@'%';"
  mysql_query "GRANT ALL PRIVILEGES ON \`$APP_DB\`.* TO '$MIGRATION_USER'@'%';"
  mysql_query "FLUSH PRIVILEGES;"
  log "INFO" "Application user password: $APP_DB_PASSWORD"
  log "INFO" "Migration user password: $MIGRATION_PASSWORD"
}

main() {
  parse_args "$@"
  require_root
  install_mysql
  secure_mysql
  create_database_and_users
  log "INFO" "MySQL provisioning complete"
}

main "$@"
