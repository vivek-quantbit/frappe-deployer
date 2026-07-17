#!/usr/bin/env bash

readonly APP_NAME="frappe-deployer"
readonly APP_VERSION="$(<"${PROJECT_ROOT}/VERSION")"
readonly SUPPORTED_OS_ID="ubuntu"
readonly SUPPORTED_OS_VERSION="22.04"
readonly DEFAULT_DEPLOY_USER="frappe"
readonly DEFAULT_BENCH_PARENT="/home/${DEFAULT_DEPLOY_USER}"
readonly DEFAULT_STATE_DIR="/var/lib/${APP_NAME}"
readonly DEFAULT_LOG_DIR="/var/log/${APP_NAME}"
readonly TOTAL_STAGES=14
readonly FRAPPE_BRANCH="version-15"
readonly NODE_MAJOR="22"
readonly MIN_MEMORY_MB=2048
readonly MIN_DISK_MB=10240
readonly APT_MAX_AGE_SECONDS=86400
readonly NODE_KEYRING="/usr/share/keyrings/nodesource.gpg"
readonly NODE_SOURCE_LIST="/etc/apt/sources.list.d/nodesource.list"
readonly NODE_KEY_URL="https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key"
readonly WKHTMLTOPDF_VERSION="0.12.6.1-2"
readonly WKHTMLTOPDF_DEB="wkhtmltox_${WKHTMLTOPDF_VERSION}.jammy_amd64.deb"
readonly WKHTMLTOPDF_URL="https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOPDF_VERSION}/${WKHTMLTOPDF_DEB}"
readonly MARIADB_CONFIG_SOURCE="${PROJECT_ROOT}/config/mariadb.cnf"
readonly MARIADB_CONFIG_TARGET="/etc/mysql/mariadb.conf.d/60-frappe-deployer.cnf"
readonly BENCH_VENV="/opt/frappe-deployer/bench-venv"
readonly BENCH_EXECUTABLE="${BENCH_VENV}/bin/bench"
readonly BENCH_LINK="/usr/local/bin/bench"
readonly BENCH_COMMAND_PATH="${BENCH_VENV}/bin:/usr/local/bin:/usr/bin:/bin"

readonly -a BASE_PACKAGES=(
  apt-transport-https build-essential ca-certificates cron curl fontconfig
  fonts-dejavu-core fonts-liberation git gnupg jq libffi-dev libjpeg-dev
  liblcms2-dev libmariadb-dev libmariadb-dev-compat libpango1.0-dev
  libssl-dev libtiff5-dev libwebp-dev libxrender1 mariadb-client
  mariadb-server nginx pkg-config python3 python3-dev python3-pip
  python3-setuptools python3-venv redis-server software-properties-common
  xvfb zlib1g-dev
)

readonly -a PROTECTED_BENCH_PARENTS=(
  "/" "/bin" "/boot" "/dev" "/etc" "/lib" "/lib64" "/proc"
  "/home" "/media" "/mnt" "/opt" "/root" "/run" "/sbin" "/srv"
  "/sys" "/tmp" "/usr" "/var"
)
