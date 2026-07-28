#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_CONSTANTS_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_CONSTANTS_LOADED=1

# ---------------------------------------------------------------------------
# Identificação do projeto
# ---------------------------------------------------------------------------

readonly HC_APPLICATION_NAME="${PROGRAM_NAME:-vps-healthcheck}"
readonly HC_APPLICATION_VERSION="${PROGRAM_VERSION:-0.1.0}"
readonly HC_APPLICATION_DESCRIPTION="${PROGRAM_DESCRIPTION:-Ferramenta de auditoria, monitoramento e inventário para VPS Linux}"

readonly HC_PROJECT_ROOT="${PROJECT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P)}"
readonly HC_CONFIG_DIR="${CONFIG_DIR:-${HC_PROJECT_ROOT}/config}"
readonly HC_LIB_DIR="${LIB_DIR:-${HC_PROJECT_ROOT}/lib}"
readonly HC_REPORTS_DIR="${REPORTS_DIR:-${HC_PROJECT_ROOT}/reports}"
readonly HC_LOGS_DIR="${LOGS_DIR:-${HC_PROJECT_ROOT}/logs}"
readonly HC_TEMPLATES_DIR="${TEMPLATES_DIR:-${HC_PROJECT_ROOT}/templates}"
readonly HC_ASSETS_DIR="${ASSETS_DIR:-${HC_PROJECT_ROOT}/assets}"
readonly HC_TESTS_DIR="${TESTS_DIR:-${HC_PROJECT_ROOT}/tests}"

readonly HC_DEFAULT_CONFIG_FILE="${HC_CONFIG_DIR}/healthcheck.conf"
readonly HC_DEFAULT_THRESHOLDS_FILE="${HC_CONFIG_DIR}/thresholds.conf"

# ---------------------------------------------------------------------------
# Versões mínimas e plataformas suportadas
# ---------------------------------------------------------------------------

readonly HC_MINIMUM_BASH_MAJOR=4
readonly HC_MINIMUM_BASH_MINOR=4

readonly HC_SUPPORTED_KERNEL="Linux"
readonly HC_SUPPORTED_ARCH_X86_64="x86_64"
readonly HC_SUPPORTED_ARCH_AMD64="amd64"
readonly HC_SUPPORTED_ARCH_ARM64="aarch64"
readonly HC_SUPPORTED_ARCH_ARMV8="arm64"

readonly HC_SUPPORTED_DEBIAN_MINIMUM_MAJOR=12
readonly HC_SUPPORTED_UBUNTU_MINIMUM_MAJOR=22
readonly HC_SUPPORTED_UBUNTU_MINIMUM_MINOR=4

readonly HC_OS_DEBIAN="debian"
readonly HC_OS_UBUNTU="ubuntu"
readonly HC_OS_UNKNOWN="unknown"

# ---------------------------------------------------------------------------
# Estados de saúde
# ---------------------------------------------------------------------------

readonly HC_STATUS_OK="OK"
readonly HC_STATUS_WARNING="WARNING"
readonly HC_STATUS_CRITICAL="CRITICAL"
readonly HC_STATUS_UNKNOWN="UNKNOWN"
readonly HC_STATUS_SKIPPED="SKIPPED"

readonly HC_STATUS_OK_LABEL="Saudável"
readonly HC_STATUS_WARNING_LABEL="Atenção"
readonly HC_STATUS_CRITICAL_LABEL="Crítico"
readonly HC_STATUS_UNKNOWN_LABEL="Desconhecido"
readonly HC_STATUS_SKIPPED_LABEL="Ignorado"

readonly HC_STATUS_OK_WEIGHT=0
readonly HC_STATUS_SKIPPED_WEIGHT=1
readonly HC_STATUS_UNKNOWN_WEIGHT=2
readonly HC_STATUS_WARNING_WEIGHT=3
readonly HC_STATUS_CRITICAL_WEIGHT=4

readonly HC_STATUS_OK_EXIT_CODE=0
readonly HC_STATUS_WARNING_EXIT_CODE=10
readonly HC_STATUS_CRITICAL_EXIT_CODE=20
readonly HC_STATUS_UNKNOWN_EXIT_CODE=30
readonly HC_STATUS_SKIPPED_EXIT_CODE=40

declare -grA HC_STATUS_LABELS=(
    ["${HC_STATUS_OK}"]="${HC_STATUS_OK_LABEL}"
    ["${HC_STATUS_WARNING}"]="${HC_STATUS_WARNING_LABEL}"
    ["${HC_STATUS_CRITICAL}"]="${HC_STATUS_CRITICAL_LABEL}"
    ["${HC_STATUS_UNKNOWN}"]="${HC_STATUS_UNKNOWN_LABEL}"
    ["${HC_STATUS_SKIPPED}"]="${HC_STATUS_SKIPPED_LABEL}"
)

declare -grA HC_STATUS_WEIGHTS=(
    ["${HC_STATUS_OK}"]="${HC_STATUS_OK_WEIGHT}"
    ["${HC_STATUS_SKIPPED}"]="${HC_STATUS_SKIPPED_WEIGHT}"
    ["${HC_STATUS_UNKNOWN}"]="${HC_STATUS_UNKNOWN_WEIGHT}"
    ["${HC_STATUS_WARNING}"]="${HC_STATUS_WARNING_WEIGHT}"
    ["${HC_STATUS_CRITICAL}"]="${HC_STATUS_CRITICAL_WEIGHT}"
)

declare -grA HC_STATUS_EXIT_CODES=(
    ["${HC_STATUS_OK}"]="${HC_STATUS_OK_EXIT_CODE}"
    ["${HC_STATUS_WARNING}"]="${HC_STATUS_WARNING_EXIT_CODE}"
    ["${HC_STATUS_CRITICAL}"]="${HC_STATUS_CRITICAL_EXIT_CODE}"
    ["${HC_STATUS_UNKNOWN}"]="${HC_STATUS_UNKNOWN_EXIT_CODE}"
    ["${HC_STATUS_SKIPPED}"]="${HC_STATUS_SKIPPED_EXIT_CODE}"
)

# ---------------------------------------------------------------------------
# Estados operacionais
# ---------------------------------------------------------------------------

readonly HC_AVAILABILITY_AVAILABLE="available"
readonly HC_AVAILABILITY_UNAVAILABLE="unavailable"
readonly HC_AVAILABILITY_PERMISSION_DENIED="permission_denied"
readonly HC_AVAILABILITY_ERROR="error"
readonly HC_AVAILABILITY_NOT_APPLICABLE="not_applicable"

readonly HC_SERVICE_ACTIVE="active"
readonly HC_SERVICE_INACTIVE="inactive"
readonly HC_SERVICE_FAILED="failed"
readonly HC_SERVICE_ACTIVATING="activating"
readonly HC_SERVICE_DEACTIVATING="deactivating"
readonly HC_SERVICE_RELOADING="reloading"
readonly HC_SERVICE_UNKNOWN="unknown"
readonly HC_SERVICE_NOT_FOUND="not_found"

readonly HC_ENABLED="enabled"
readonly HC_DISABLED="disabled"
readonly HC_STATIC="static"
readonly HC_MASKED="masked"
readonly HC_INDIRECT="indirect"
readonly HC_GENERATED="generated"
readonly HC_TRANSIENT="transient"
readonly HC_NOT_FOUND="not_found"
readonly HC_UNKNOWN="unknown"

readonly HC_BOOLEAN_TRUE="true"
readonly HC_BOOLEAN_FALSE="false"

# ---------------------------------------------------------------------------
# Níveis de log
# ---------------------------------------------------------------------------

readonly HC_LOG_LEVEL_DEBUG="DEBUG"
readonly HC_LOG_LEVEL_INFO="INFO"
readonly HC_LOG_LEVEL_NOTICE="NOTICE"
readonly HC_LOG_LEVEL_WARNING="WARNING"
readonly HC_LOG_LEVEL_ERROR="ERROR"
readonly HC_LOG_LEVEL_CRITICAL="CRITICAL"

readonly HC_LOG_PRIORITY_DEBUG=10
readonly HC_LOG_PRIORITY_INFO=20
readonly HC_LOG_PRIORITY_NOTICE=25
readonly HC_LOG_PRIORITY_WARNING=30
readonly HC_LOG_PRIORITY_ERROR=40
readonly HC_LOG_PRIORITY_CRITICAL=50

declare -grA HC_LOG_LEVEL_PRIORITIES=(
    ["${HC_LOG_LEVEL_DEBUG}"]="${HC_LOG_PRIORITY_DEBUG}"
    ["${HC_LOG_LEVEL_INFO}"]="${HC_LOG_PRIORITY_INFO}"
    ["${HC_LOG_LEVEL_NOTICE}"]="${HC_LOG_PRIORITY_NOTICE}"
    ["${HC_LOG_LEVEL_WARNING}"]="${HC_LOG_PRIORITY_WARNING}"
    ["${HC_LOG_LEVEL_ERROR}"]="${HC_LOG_PRIORITY_ERROR}"
    ["${HC_LOG_LEVEL_CRITICAL}"]="${HC_LOG_PRIORITY_CRITICAL}"
)

# ---------------------------------------------------------------------------
# Tipos de coleta
# ---------------------------------------------------------------------------

readonly HC_DATA_TYPE_STRING="string"
readonly HC_DATA_TYPE_INTEGER="integer"
readonly HC_DATA_TYPE_FLOAT="float"
readonly HC_DATA_TYPE_BOOLEAN="boolean"
readonly HC_DATA_TYPE_BYTES="bytes"
readonly HC_DATA_TYPE_PERCENTAGE="percentage"
readonly HC_DATA_TYPE_SECONDS="seconds"
readonly HC_DATA_TYPE_TIMESTAMP="timestamp"
readonly HC_DATA_TYPE_DATE="date"
readonly HC_DATA_TYPE_DURATION="duration"
readonly HC_DATA_TYPE_ARRAY="array"
readonly HC_DATA_TYPE_OBJECT="object"
readonly HC_DATA_TYPE_TABLE="table"

# ---------------------------------------------------------------------------
# Delimitadores internos
# ---------------------------------------------------------------------------

readonly HC_FIELD_SEPARATOR=$'\t'
readonly HC_RECORD_SEPARATOR=$'\036'
readonly HC_UNIT_SEPARATOR=$'\037'

readonly HC_NULL_VALUE="null"
readonly HC_EMPTY_VALUE=""
readonly HC_NOT_AVAILABLE_VALUE="N/D"
readonly HC_NOT_APPLICABLE_VALUE="N/A"
readonly HC_REDACTED_VALUE="[oculto]"

# ---------------------------------------------------------------------------
# Formatos de relatório
# ---------------------------------------------------------------------------

readonly HC_REPORT_FORMAT_TERMINAL="terminal"
readonly HC_REPORT_FORMAT_TXT="txt"
readonly HC_REPORT_FORMAT_JSON="json"
readonly HC_REPORT_FORMAT_HTML="html"

readonly HC_REPORT_TXT_EXTENSION=".txt"
readonly HC_REPORT_JSON_EXTENSION=".json"
readonly HC_REPORT_HTML_EXTENSION=".html"

readonly HC_REPORT_BASENAME="vps-healthcheck"
readonly HC_REPORT_ENCODING="UTF-8"

declare -gra HC_SUPPORTED_REPORT_FORMATS=(
    "${HC_REPORT_FORMAT_TERMINAL}"
    "${HC_REPORT_FORMAT_TXT}"
    "${HC_REPORT_FORMAT_JSON}"
    "${HC_REPORT_FORMAT_HTML}"
)

# ---------------------------------------------------------------------------
# Modos de execução
# ---------------------------------------------------------------------------

readonly HC_RUN_MODE_QUICK="quick"
readonly HC_RUN_MODE_FULL="full"
readonly HC_RUN_MODE_CUSTOM="custom"

readonly HC_SCAN_MODE_LIGHT="light"
readonly HC_SCAN_MODE_STANDARD="standard"
readonly HC_SCAN_MODE_DEEP="deep"

# ---------------------------------------------------------------------------
# Módulos
# ---------------------------------------------------------------------------

readonly HC_MODULE_SYSTEM="system"
readonly HC_MODULE_CPU="cpu"
readonly HC_MODULE_MEMORY="memory"
readonly HC_MODULE_DISK="disk"
readonly HC_MODULE_NETWORK="network"
readonly HC_MODULE_PYTHON="python"
readonly HC_MODULE_DOCKER="docker"
readonly HC_MODULE_NGINX="nginx"
readonly HC_MODULE_SSL="ssl"
readonly HC_MODULE_DATABASE="database"
readonly HC_MODULE_FIREWALL="firewall"
readonly HC_MODULE_SECURITY="security"
readonly HC_MODULE_SERVICES="services"
readonly HC_MODULE_LOGS="logs"
readonly HC_MODULE_UPDATES="updates"
readonly HC_MODULE_AI="ai"
readonly HC_MODULE_OLLAMA="ollama"

declare -gra HC_ALL_MODULES=(
    "${HC_MODULE_SYSTEM}"
    "${HC_MODULE_CPU}"
    "${HC_MODULE_MEMORY}"
    "${HC_MODULE_DISK}"
    "${HC_MODULE_NETWORK}"
    "${HC_MODULE_SERVICES}"
    "${HC_MODULE_UPDATES}"
    "${HC_MODULE_PYTHON}"
    "${HC_MODULE_DOCKER}"
    "${HC_MODULE_NGINX}"
    "${HC_MODULE_SSL}"
    "${HC_MODULE_DATABASE}"
    "${HC_MODULE_FIREWALL}"
    "${HC_MODULE_SECURITY}"
    "${HC_MODULE_LOGS}"
    "${HC_MODULE_AI}"
    "${HC_MODULE_OLLAMA}"
)

declare -gra HC_QUICK_MODULES=(
    "${HC_MODULE_SYSTEM}"
    "${HC_MODULE_CPU}"
    "${HC_MODULE_MEMORY}"
    "${HC_MODULE_DISK}"
    "${HC_MODULE_NETWORK}"
    "${HC_MODULE_SERVICES}"
    "${HC_MODULE_UPDATES}"
)

declare -gra HC_REQUIRED_MODULES=(
    "${HC_MODULE_SYSTEM}"
    "${HC_MODULE_CPU}"
    "${HC_MODULE_MEMORY}"
    "${HC_MODULE_DISK}"
    "${HC_MODULE_NETWORK}"
    "${HC_MODULE_SERVICES}"
)

declare -gra HC_OPTIONAL_MODULES=(
    "${HC_MODULE_UPDATES}"
    "${HC_MODULE_PYTHON}"
    "${HC_MODULE_DOCKER}"
    "${HC_MODULE_NGINX}"
    "${HC_MODULE_SSL}"
    "${HC_MODULE_DATABASE}"
    "${HC_MODULE_FIREWALL}"
    "${HC_MODULE_SECURITY}"
    "${HC_MODULE_LOGS}"
    "${HC_MODULE_AI}"
    "${HC_MODULE_OLLAMA}"
)

declare -grA HC_MODULE_LABELS=(
    ["${HC_MODULE_SYSTEM}"]="Sistema"
    ["${HC_MODULE_CPU}"]="CPU"
    ["${HC_MODULE_MEMORY}"]="Memória"
    ["${HC_MODULE_DISK}"]="Disco"
    ["${HC_MODULE_NETWORK}"]="Rede"
    ["${HC_MODULE_PYTHON}"]="Python"
    ["${HC_MODULE_DOCKER}"]="Docker"
    ["${HC_MODULE_NGINX}"]="Nginx"
    ["${HC_MODULE_SSL}"]="SSL"
    ["${HC_MODULE_DATABASE}"]="Bancos de dados"
    ["${HC_MODULE_FIREWALL}"]="Firewall"
    ["${HC_MODULE_SECURITY}"]="Segurança"
    ["${HC_MODULE_SERVICES}"]="Serviços"
    ["${HC_MODULE_LOGS}"]="Logs"
    ["${HC_MODULE_UPDATES}"]="Atualizações"
    ["${HC_MODULE_AI}"]="Serviços de IA"
    ["${HC_MODULE_OLLAMA}"]="Ollama"
)

# ---------------------------------------------------------------------------
# Limites padrão de saúde
# Estes valores poderão ser sobrescritos por config/thresholds.conf.
# ---------------------------------------------------------------------------

readonly HC_DEFAULT_CPU_WARNING_PERCENT=75
readonly HC_DEFAULT_CPU_CRITICAL_PERCENT=90

readonly HC_DEFAULT_LOAD_WARNING_FACTOR="1.00"
readonly HC_DEFAULT_LOAD_CRITICAL_FACTOR="1.50"

readonly HC_DEFAULT_MEMORY_WARNING_PERCENT=80
readonly HC_DEFAULT_MEMORY_CRITICAL_PERCENT=92

readonly HC_DEFAULT_SWAP_WARNING_PERCENT=50
readonly HC_DEFAULT_SWAP_CRITICAL_PERCENT=80

readonly HC_DEFAULT_DISK_WARNING_PERCENT=75
readonly HC_DEFAULT_DISK_CRITICAL_PERCENT=90

readonly HC_DEFAULT_INODE_WARNING_PERCENT=75
readonly HC_DEFAULT_INODE_CRITICAL_PERCENT=90

readonly HC_DEFAULT_SSL_WARNING_DAYS=30
readonly HC_DEFAULT_SSL_CRITICAL_DAYS=15

readonly HC_DEFAULT_UPDATES_WARNING_COUNT=20
readonly HC_DEFAULT_UPDATES_CRITICAL_COUNT=50

readonly HC_DEFAULT_SECURITY_UPDATES_WARNING_COUNT=1
readonly HC_DEFAULT_SECURITY_UPDATES_CRITICAL_COUNT=10

readonly HC_DEFAULT_HTTP_WARNING_MS=1000
readonly HC_DEFAULT_HTTP_CRITICAL_MS=3000
readonly HC_DEFAULT_HTTP_CONNECT_TIMEOUT_SECONDS=5
readonly HC_DEFAULT_HTTP_TOTAL_TIMEOUT_SECONDS=10

readonly HC_DEFAULT_LARGE_LOG_SIZE_BYTES=104857600
readonly HC_DEFAULT_LARGE_FILE_SIZE_BYTES=1073741824

readonly HC_DEFAULT_TOP_DIRECTORIES_LIMIT=50
readonly HC_DEFAULT_TOP_FILES_LIMIT=50
readonly HC_DEFAULT_TOP_PROCESSES_LIMIT=20
readonly HC_DEFAULT_CONNECTIONS_LIMIT=100
readonly HC_DEFAULT_JOURNAL_LINES=200

readonly HC_DEFAULT_COMMAND_TIMEOUT_SECONDS=30
readonly HC_DEFAULT_LONG_COMMAND_TIMEOUT_SECONDS=300
readonly HC_DEFAULT_DNS_TIMEOUT_SECONDS=5

readonly HC_DEFAULT_CERTIFICATE_PORT=443
readonly HC_DEFAULT_HTTP_PORT=80
readonly HC_DEFAULT_HTTPS_PORT=443
readonly HC_DEFAULT_SSH_PORT=22

# ---------------------------------------------------------------------------
# Portas comuns
# ---------------------------------------------------------------------------

readonly HC_PORT_SSH=22
readonly HC_PORT_DNS=53
readonly HC_PORT_HTTP=80
readonly HC_PORT_HTTPS=443
readonly HC_PORT_MYSQL=3306
readonly HC_PORT_POSTGRESQL=5432
readonly HC_PORT_REDIS=6379
readonly HC_PORT_MONGODB=27017
readonly HC_PORT_DOCKER_API=2375
readonly HC_PORT_DOCKER_TLS_API=2376
readonly HC_PORT_OLLAMA=11434
readonly HC_PORT_OPEN_WEBUI=3000
readonly HC_PORT_N8N=5678
readonly HC_PORT_FLOWISE=3000
readonly HC_PORT_LANGFLOW=7860
readonly HC_PORT_QDRANT_HTTP=6333
readonly HC_PORT_QDRANT_GRPC=6334
readonly HC_PORT_CHROMADB=8000

# ---------------------------------------------------------------------------
# Serviços e aplicações conhecidas
# ---------------------------------------------------------------------------

declare -gra HC_PYTHON_FRAMEWORKS=(
    "Django"
    "Flask"
    "FastAPI"
    "Python"
)

declare -gra HC_PYTHON_SERVERS=(
    "gunicorn"
    "uvicorn"
    "daphne"
    "hypercorn"
    "waitress"
)

declare -gra HC_PYTHON_WORKERS=(
    "celery"
    "rq"
    "dramatiq"
    "huey"
)

declare -gra HC_DATABASE_TYPES=(
    "postgresql"
    "redis"
    "mariadb"
    "mysql"
    "mongodb"
)

declare -gra HC_AI_SERVICES=(
    "ollama"
    "open-webui"
    "anythingllm"
    "flowise"
    "n8n"
    "langflow"
    "qdrant"
    "chromadb"
    "redis"
    "postgresql"
)

# ---------------------------------------------------------------------------
# Caminhos Linux conhecidos
# ---------------------------------------------------------------------------

readonly HC_PATH_OS_RELEASE="/etc/os-release"
readonly HC_PATH_DEBIAN_VERSION="/etc/debian_version"
readonly HC_PATH_PROC="/proc"
readonly HC_PATH_SYS="/sys"
readonly HC_PATH_DEV="/dev"
readonly HC_PATH_RUN="/run"
readonly HC_PATH_VAR="/var"
readonly HC_PATH_VAR_LOG="/var/log"
readonly HC_PATH_VAR_LIB="/var/lib"
readonly HC_PATH_ETC="/etc"
readonly HC_PATH_HOME="/home"
readonly HC_PATH_ROOT="/root"
readonly HC_PATH_TMP="/tmp"

readonly HC_PATH_SSH_CONFIG="/etc/ssh/sshd_config"
readonly HC_PATH_SSH_CONFIG_DIR="/etc/ssh/sshd_config.d"
readonly HC_PATH_NGINX="/etc/nginx"
readonly HC_PATH_NGINX_CONF="/etc/nginx/nginx.conf"
readonly HC_PATH_NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
readonly HC_PATH_NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
readonly HC_PATH_LETSENCRYPT="/etc/letsencrypt"
readonly HC_PATH_LETSENCRYPT_LIVE="/etc/letsencrypt/live"
readonly HC_PATH_SYSTEMD_SYSTEM="/etc/systemd/system"
readonly HC_PATH_SYSTEMD_LIB="/lib/systemd/system"
readonly HC_PATH_SYSTEMD_USR_LIB="/usr/lib/systemd/system"

readonly HC_PATH_DOCKER_DATA="/var/lib/docker"
readonly HC_PATH_CONTAINERD_DATA="/var/lib/containerd"
readonly HC_PATH_OLLAMA_SYSTEM="/usr/share/ollama"
readonly HC_PATH_OLLAMA_VAR_LIB="/var/lib/ollama"
readonly HC_PATH_OLLAMA_USER_SUFFIX=".ollama"

readonly HC_PATH_POSTGRESQL_DATA="/var/lib/postgresql"
readonly HC_PATH_MYSQL_DATA="/var/lib/mysql"
readonly HC_PATH_MONGODB_DATA="/var/lib/mongodb"
readonly HC_PATH_REDIS_DATA="/var/lib/redis"

# ---------------------------------------------------------------------------
# Sistemas de arquivos ignorados
# ---------------------------------------------------------------------------

declare -gra HC_IGNORED_FILESYSTEM_TYPES=(
    "autofs"
    "binfmt_misc"
    "bpf"
    "cgroup"
    "cgroup2"
    "configfs"
    "debugfs"
    "devpts"
    "devtmpfs"
    "efivarfs"
    "fusectl"
    "hugetlbfs"
    "mqueue"
    "overlay"
    "proc"
    "pstore"
    "securityfs"
    "sysfs"
    "tmpfs"
    "tracefs"
)

declare -gra HC_IGNORED_SCAN_PATHS=(
    "/proc"
    "/sys"
    "/dev"
    "/run"
    "/snap"
    "/var/lib/docker/overlay2"
    "/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs"
)

# ---------------------------------------------------------------------------
# Comandos principais
# ---------------------------------------------------------------------------

declare -gra HC_CORE_COMMANDS=(
    "awk"
    "basename"
    "cat"
    "cut"
    "date"
    "df"
    "dirname"
    "find"
    "grep"
    "hostname"
    "id"
    "ip"
    "mount"
    "ps"
    "sed"
    "sort"
    "ss"
    "stat"
    "tr"
    "uname"
    "uptime"
)

declare -gra HC_RECOMMENDED_COMMANDS=(
    "curl"
    "dig"
    "docker"
    "fail2ban-client"
    "findmnt"
    "free"
    "hostnamectl"
    "jq"
    "journalctl"
    "lsof"
    "nginx"
    "openssl"
    "systemctl"
    "timeout"
    "ufw"
)

# ---------------------------------------------------------------------------
# Expressões regulares
# ---------------------------------------------------------------------------

readonly HC_REGEX_IPV4='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
readonly HC_REGEX_IPV6='^[0-9A-Fa-f:]+$'
readonly HC_REGEX_DOMAIN='^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'
readonly HC_REGEX_PORT='^[0-9]{1,5}$'
readonly HC_REGEX_INTEGER='^-?[0-9]+$'
readonly HC_REGEX_UNSIGNED_INTEGER='^[0-9]+$'
readonly HC_REGEX_DECIMAL='^-?[0-9]+([.][0-9]+)?$'
readonly HC_REGEX_PERCENTAGE='^([0-9]|[1-9][0-9]|100)([.][0-9]+)?$'
readonly HC_REGEX_SYSTEMD_UNIT='^[A-Za-z0-9_.@:-]+\.(service|socket|timer|target|mount|path)$'

# ---------------------------------------------------------------------------
# Códigos HTTP
# ---------------------------------------------------------------------------

readonly HC_HTTP_STATUS_MIN_SUCCESS=200
readonly HC_HTTP_STATUS_MAX_SUCCESS=399
readonly HC_HTTP_STATUS_UNREACHABLE=0

# ---------------------------------------------------------------------------
# Permissões
# ---------------------------------------------------------------------------

readonly HC_PERMISSION_EXECUTABLE="executable"
readonly HC_PERMISSION_READABLE="readable"
readonly HC_PERMISSION_WRITABLE="writable"

readonly HC_DEFAULT_DIRECTORY_MODE="0750"
readonly HC_DEFAULT_REPORT_MODE="0640"
readonly HC_DEFAULT_LOG_MODE="0640"
readonly HC_DEFAULT_CONFIG_MODE="0640"
readonly HC_DEFAULT_EXECUTABLE_MODE="0750"

# ---------------------------------------------------------------------------
# Datas e timestamps
# ---------------------------------------------------------------------------

readonly HC_DATE_FORMAT="%Y-%m-%d"
readonly HC_TIME_FORMAT="%H:%M:%S"
readonly HC_DATETIME_FORMAT="%Y-%m-%d %H:%M:%S"
readonly HC_ISO8601_FORMAT="%Y-%m-%dT%H:%M:%S%z"
readonly HC_FILENAME_TIMESTAMP_FORMAT="%Y%m%d_%H%M%S"

# ---------------------------------------------------------------------------
# Funções auxiliares relacionadas às constantes
# ---------------------------------------------------------------------------

hc_status_is_valid() {
    local status="${1:-}"

    [[ -n "$status" && -n "${HC_STATUS_LABELS[$status]+x}" ]]
}

hc_status_label() {
    local status="${1:-}"

    if hc_status_is_valid "$status"; then
        printf '%s\n' "${HC_STATUS_LABELS[$status]}"
        return 0
    fi

    printf '%s\n' "${HC_STATUS_LABELS[$HC_STATUS_UNKNOWN]}"
    return 1
}

hc_status_weight() {
    local status="${1:-}"

    if hc_status_is_valid "$status"; then
        printf '%s\n' "${HC_STATUS_WEIGHTS[$status]}"
        return 0
    fi

    printf '%s\n' "${HC_STATUS_WEIGHTS[$HC_STATUS_UNKNOWN]}"
    return 1
}

hc_status_exit_code() {
    local status="${1:-}"

    if hc_status_is_valid "$status"; then
        printf '%s\n' "${HC_STATUS_EXIT_CODES[$status]}"
        return 0
    fi

    printf '%s\n' "${HC_STATUS_EXIT_CODES[$HC_STATUS_UNKNOWN]}"
    return 1
}

hc_status_worst() {
    local first_status="${1:-$HC_STATUS_UNKNOWN}"
    local second_status="${2:-$HC_STATUS_UNKNOWN}"
    local first_weight
    local second_weight

    if ! hc_status_is_valid "$first_status"; then
        first_status="$HC_STATUS_UNKNOWN"
    fi

    if ! hc_status_is_valid "$second_status"; then
        second_status="$HC_STATUS_UNKNOWN"
    fi

    first_weight="${HC_STATUS_WEIGHTS[$first_status]}"
    second_weight="${HC_STATUS_WEIGHTS[$second_status]}"

    if ((first_weight >= second_weight)); then
        printf '%s\n' "$first_status"
    else
        printf '%s\n' "$second_status"
    fi
}

hc_log_level_is_valid() {
    local level="${1:-}"

    [[ -n "$level" && -n "${HC_LOG_LEVEL_PRIORITIES[$level]+x}" ]]
}

hc_log_level_priority() {
    local level="${1:-}"

    if hc_log_level_is_valid "$level"; then
        printf '%s\n' "${HC_LOG_LEVEL_PRIORITIES[$level]}"
        return 0
    fi

    printf '%s\n' "${HC_LOG_LEVEL_PRIORITIES[$HC_LOG_LEVEL_INFO]}"
    return 1
}

hc_module_is_valid() {
    local requested_module="${1:-}"
    local module

    for module in "${HC_ALL_MODULES[@]}"; do
        if [[ "$module" == "$requested_module" ]]; then
            return 0
        fi
    done

    return 1
}

hc_module_is_required() {
    local requested_module="${1:-}"
    local module

    for module in "${HC_REQUIRED_MODULES[@]}"; do
        if [[ "$module" == "$requested_module" ]]; then
            return 0
        fi
    done

    return 1
}

hc_module_label() {
    local module="${1:-}"

    if [[ -n "$module" && -n "${HC_MODULE_LABELS[$module]+x}" ]]; then
        printf '%s\n' "${HC_MODULE_LABELS[$module]}"
        return 0
    fi

    printf '%s\n' "$module"
    return 1
}

hc_report_format_is_valid() {
    local requested_format="${1:-}"
    local format

    for format in "${HC_SUPPORTED_REPORT_FORMATS[@]}"; do
        if [[ "$format" == "$requested_format" ]]; then
            return 0
        fi
    done

    return 1
}

hc_architecture_is_supported() {
    local architecture="${1:-}"

    case "$architecture" in
        "$HC_SUPPORTED_ARCH_X86_64" | \
        "$HC_SUPPORTED_ARCH_AMD64" | \
        "$HC_SUPPORTED_ARCH_ARM64" | \
        "$HC_SUPPORTED_ARCH_ARMV8")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

hc_constants_validate() {
    local failure=0
    local status
    local module
    local format

    for status in \
        "$HC_STATUS_OK" \
        "$HC_STATUS_WARNING" \
        "$HC_STATUS_CRITICAL" \
        "$HC_STATUS_UNKNOWN" \
        "$HC_STATUS_SKIPPED"; do

        if ! hc_status_is_valid "$status"; then
            printf 'Constante de estado inválida: %s\n' "$status" >&2
            failure=1
        fi
    done

    for module in "${HC_ALL_MODULES[@]}"; do
        if [[ -z "${HC_MODULE_LABELS[$module]+x}" ]]; then
            printf 'Módulo sem rótulo: %s\n' "$module" >&2
            failure=1
        fi
    done

    for format in "${HC_SUPPORTED_REPORT_FORMATS[@]}"; do
        if ! hc_report_format_is_valid "$format"; then
            printf 'Formato de relatório inválido: %s\n' "$format" >&2
            failure=1
        fi
    done

    if ((HC_DEFAULT_CPU_WARNING_PERCENT >= HC_DEFAULT_CPU_CRITICAL_PERCENT)); then
        printf 'Limites padrão de CPU estão inconsistentes.\n' >&2
        failure=1
    fi

    if ((HC_DEFAULT_MEMORY_WARNING_PERCENT >= HC_DEFAULT_MEMORY_CRITICAL_PERCENT)); then
        printf 'Limites padrão de memória estão inconsistentes.\n' >&2
        failure=1
    fi

    if ((HC_DEFAULT_DISK_WARNING_PERCENT >= HC_DEFAULT_DISK_CRITICAL_PERCENT)); then
        printf 'Limites padrão de disco estão inconsistentes.\n' >&2
        failure=1
    fi

    if ((HC_DEFAULT_SSL_WARNING_DAYS <= HC_DEFAULT_SSL_CRITICAL_DAYS)); then
        printf 'Limites padrão de SSL estão inconsistentes.\n' >&2
        failure=1
    fi

    return "$failure"
}
