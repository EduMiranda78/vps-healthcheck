#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_CONFIG_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_CONFIG_LOADED=1

# ---------------------------------------------------------------------------
# Estado interno
# ---------------------------------------------------------------------------

HC_CONFIG_LOADER_INITIALIZED=0
HC_CONFIG_MAIN_LOADED=0
HC_CONFIG_THRESHOLDS_LOADED=0

HC_CONFIG_MAIN_PATH=""
HC_CONFIG_THRESHOLDS_PATH=""

declare -gA HC_CONFIG_VALUES=()
declare -gA HC_THRESHOLD_VALUES=()
declare -gA HC_CONFIG_SOURCES=()

declare -ag HC_CONFIG_LOADED_KEYS=()
declare -ag HC_THRESHOLD_LOADED_KEYS=()
declare -ag HC_CONFIG_WARNINGS=()
declare -ag HC_CONFIG_ERRORS=()

# ---------------------------------------------------------------------------
# Mensagens
# ---------------------------------------------------------------------------

config_log_debug() {
    local message="${1:-}"

    if declare -F logger_debug >/dev/null 2>&1; then
        logger_debug "$message"
    fi
}

config_log_info() {
    local message="${1:-}"

    if declare -F logger_info >/dev/null 2>&1; then
        logger_info "$message"
    fi
}

config_log_warning() {
    local message="${1:-}"

    HC_CONFIG_WARNINGS+=("$message")

    if declare -F logger_warning >/dev/null 2>&1; then
        logger_warning "$message"
    fi
}

config_log_error() {
    local message="${1:-}"

    HC_CONFIG_ERRORS+=("$message")

    if declare -F logger_error >/dev/null 2>&1; then
        logger_error "$message"
    else
        printf 'ERRO: %s\n' "$message" >&2
    fi
}

# ---------------------------------------------------------------------------
# Funções auxiliares
# ---------------------------------------------------------------------------

config_trim() {
    local value="${1:-}"

    if declare -F utils_trim >/dev/null 2>&1; then
        utils_trim "$value"
        return
    fi

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s' "$value"
}

config_strip_quotes() {
    local value="${1:-}"

    if declare -F utils_strip_quotes >/dev/null 2>&1; then
        utils_strip_quotes "$value"
        return
    fi

    if [[ ${#value} -ge 2 ]]; then
        if [[ "$value" == \"*\" && "$value" == *\" ]]; then
            value="${value:1:${#value}-2}"
        elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
            value="${value:1:${#value}-2}"
        fi
    fi

    printf '%s' "$value"
}

config_array_contains() {
    local needle="${1:-}"
    shift || true

    local item

    for item in "$@"; do
        if [[ "$item" == "$needle" ]]; then
            return 0
        fi
    done

    return 1
}

config_is_integer() {
    local value="${1:-}"

    [[ "$value" =~ ^-?[0-9]+$ ]]
}

config_is_unsigned_integer() {
    local value="${1:-}"

    [[ "$value" =~ ^[0-9]+$ ]]
}

config_is_decimal() {
    local value="${1:-}"

    [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

config_is_boolean_integer() {
    local value="${1:-}"

    [[ "$value" == "0" || "$value" == "1" ]]
}

config_is_file_mode() {
    local value="${1:-}"

    [[ "$value" =~ ^0?[0-7]{3,4}$ ]]
}

config_is_status() {
    local value="${1:-}"

    case "$value" in
        OK | WARNING | CRITICAL | UNKNOWN | SKIPPED)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

config_key_is_valid() {
    local key="${1:-}"

    [[ "$key" =~ ^HC_[A-Z][A-Z0-9_]*$ ]]
}

config_key_is_threshold() {
    local key="${1:-}"

    case "$key" in
        HC_THRESHOLDS_VERSION)
            return 0
            ;;
        HC_*_WARNING_* | \
        HC_*_CRITICAL_* | \
        HC_*_STATUS | \
        HC_*_REQUIRED)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

config_value_contains_forbidden_syntax() {
    local value="${1:-}"

    case "$value" in
        *'$('* | \
        *'`'* | \
        *'${'* | \
        *'$['* | \
        *'<('* | \
        *'>('* | \
        *';'* | \
        *'&&'* | \
        *'||'*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Parser seguro
# ---------------------------------------------------------------------------

config_parse_assignment() {
    local input_line="${1:-}"
    local output_key_name="${2:-}"
    local output_value_name="${3:-}"

    local internal_key=""
    local internal_value=""
    local first_character=""
    local last_character=""

    if [[ -z "$output_key_name" || -z "$output_value_name" ]]; then
        return 2
    fi

    if [[ ! "$output_key_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
        [[ ! "$output_value_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        return 2
    fi

    local -n output_key_ref="$output_key_name"
    local -n output_value_ref="$output_value_name"

    output_key_ref=""
    output_value_ref=""

    input_line="${input_line%$'\r'}"
    input_line="$(config_trim "$input_line")"

    if [[ -z "$input_line" || "$input_line" == \#* ]]; then
        return 1
    fi

    if [[ "$input_line" == export[[:space:]]* ]]; then
        input_line="${input_line#export}"
        input_line="$(config_trim "$input_line")"
    fi

    if [[ "$input_line" != *=* ]]; then
        return 3
    fi

    internal_key="${input_line%%=*}"
    internal_value="${input_line#*=}"

    internal_key="$(config_trim "$internal_key")"
    internal_value="$(config_trim "$internal_value")"

    if ! config_key_is_valid "$internal_key"; then
        return 4
    fi

    if [[ -n "$internal_value" ]]; then
        first_character="${internal_value:0:1}"
        last_character="${internal_value: -1}"

        if [[ "$first_character" == '"' || "$first_character" == "'" ]]; then
            if [[ "$last_character" != "$first_character" ]]; then
                return 5
            fi

            internal_value="${internal_value:1:${#internal_value}-2}"
        else
            if [[ "$internal_value" =~ [[:space:]] ]]; then
                return 6
            fi

            if [[ "$internal_value" == *"#"* ]]; then
                internal_value="${internal_value%%#*}"
                internal_value="$(config_trim "$internal_value")"
            fi
        fi
    fi

    if config_value_contains_forbidden_syntax "$internal_value"; then
        return 7
    fi

    output_key_ref="$internal_key"
    output_value_ref="$internal_value"

    return 0
}

config_parser_error_message() {
    local result_code="${1:-1}"

    case "$result_code" in
        1)
            printf 'linha vazia ou comentário'
            ;;
        2)
            printf 'erro interno do parser'
            ;;
        3)
            printf 'atribuição sem sinal de igual'
            ;;
        4)
            printf 'nome de variável inválido'
            ;;
        5)
            printf 'aspas não fechadas'
            ;;
        6)
            printf 'valor sem aspas contém espaços'
            ;;
        7)
            printf 'valor contém sintaxe proibida'
            ;;
        *)
            printf 'erro de sintaxe desconhecido'
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Armazenamento
# ---------------------------------------------------------------------------

config_store_value() {
    local key="${1:-}"
    local value="${2:-}"
    local source_type="${3:-config}"
    local source_file="${4:-}"

    if ! config_key_is_valid "$key"; then
        return 1
    fi

    case "$source_type" in
        config)
            HC_CONFIG_VALUES["$key"]="$value"

            if ! config_array_contains "$key" "${HC_CONFIG_LOADED_KEYS[@]}"; then
                HC_CONFIG_LOADED_KEYS+=("$key")
            fi
            ;;
        thresholds)
            HC_THRESHOLD_VALUES["$key"]="$value"

            if ! config_array_contains "$key" "${HC_THRESHOLD_LOADED_KEYS[@]}"; then
                HC_THRESHOLD_LOADED_KEYS+=("$key")
            fi
            ;;
        *)
            return 2
            ;;
    esac

    HC_CONFIG_SOURCES["$key"]="$source_file"

    printf -v "$key" '%s' "$value"
    export "$key"
}

config_get() {
    local key="${1:-}"
    local default_value="${2:-}"

    if [[ -n "${HC_THRESHOLD_VALUES[$key]+x}" ]]; then
        printf '%s\n' "${HC_THRESHOLD_VALUES[$key]}"
        return 0
    fi

    if [[ -n "${HC_CONFIG_VALUES[$key]+x}" ]]; then
        printf '%s\n' "${HC_CONFIG_VALUES[$key]}"
        return 0
    fi

    if [[ -n "${!key+x}" ]]; then
        printf '%s\n' "${!key}"
        return 0
    fi

    printf '%s\n' "$default_value"
    return 1
}

config_has() {
    local key="${1:-}"

    [[ -n "${HC_CONFIG_VALUES[$key]+x}" ||
        -n "${HC_THRESHOLD_VALUES[$key]+x}" ||
        -n "${!key+x}" ]]
}

config_source_for_key() {
    local key="${1:-}"

    printf '%s\n' "${HC_CONFIG_SOURCES[$key]:-}"
}

# ---------------------------------------------------------------------------
# Carregamento
# ---------------------------------------------------------------------------

config_load_file() {
    local file_path="${1:-}"
    local source_type="${2:-config}"

    local line=""
    local key=""
    local value=""
    local line_number=0
    local parser_result=0
    local failures=0

    if [[ -z "$file_path" ]]; then
        config_log_error "Caminho de configuração não informado."
        return 2
    fi

    if [[ ! -e "$file_path" ]]; then
        config_log_error "Arquivo de configuração não encontrado: ${file_path}"
        return 3
    fi

    if [[ ! -f "$file_path" ]]; then
        config_log_error "O caminho não é um arquivo regular: ${file_path}"
        return 4
    fi

    if [[ ! -r "$file_path" ]]; then
        config_log_error "Arquivo sem permissão de leitura: ${file_path}"
        return 5
    fi

    case "$source_type" in
        config | thresholds)
            ;;
        *)
            config_log_error "Tipo de configuração inválido: ${source_type}"
            return 6
            ;;
    esac

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_number=$((line_number + 1))
        key=""
        value=""

        if config_parse_assignment "$line" key value; then
            config_store_value \
                "$key" \
                "$value" \
                "$source_type" \
                "$file_path"

            config_log_debug \
                "Configuração carregada: ${key} | origem=${file_path}:${line_number}"

            continue
        else
            parser_result=$?
        fi

        if ((parser_result == 1)); then
            continue
        fi

        config_log_error \
            "Configuração inválida em ${file_path}:${line_number}: $(config_parser_error_message "$parser_result")"

        failures=$((failures + 1))
    done <"$file_path"

    if ((failures > 0)); then
        return 7
    fi

    return 0
}

config_load_main() {
    local file_path="${1:-${CONFIG_FILE:-}}"

    if ! config_load_file "$file_path" "config"; then
        return $?
    fi

    HC_CONFIG_MAIN_PATH="$file_path"
    HC_CONFIG_MAIN_LOADED=1

    export HC_CONFIG_MAIN_PATH
    export HC_CONFIG_MAIN_LOADED

    config_log_info \
        "Configuração principal carregada | arquivo=${file_path} | chaves=${#HC_CONFIG_LOADED_KEYS[@]}"
}

config_load_thresholds() {
    local file_path="${1:-${THRESHOLDS_FILE:-}}"

    if ! config_load_file "$file_path" "thresholds"; then
        return $?
    fi

    HC_CONFIG_THRESHOLDS_PATH="$file_path"
    HC_CONFIG_THRESHOLDS_LOADED=1

    export HC_CONFIG_THRESHOLDS_PATH
    export HC_CONFIG_THRESHOLDS_LOADED

    config_log_info \
        "Limites de saúde carregados | arquivo=${file_path} | chaves=${#HC_THRESHOLD_LOADED_KEYS[@]}"
}

# ---------------------------------------------------------------------------
# Validação genérica
# ---------------------------------------------------------------------------

config_validate_boolean_key() {
    local key="${1:-}"
    local value

    if ! config_has "$key"; then
        return 0
    fi

    value="$(config_get "$key")"

    if ! config_is_boolean_integer "$value"; then
        config_log_error "${key} deve possuir valor 0 ou 1."
        return 1
    fi
}

config_validate_unsigned_key() {
    local key="${1:-}"
    local value

    if ! config_has "$key"; then
        return 0
    fi

    value="$(config_get "$key")"

    if ! config_is_unsigned_integer "$value"; then
        config_log_error "${key} deve ser um número inteiro não negativo."
        return 1
    fi
}

config_validate_decimal_key() {
    local key="${1:-}"
    local value

    if ! config_has "$key"; then
        return 0
    fi

    value="$(config_get "$key")"

    if ! config_is_decimal "$value"; then
        config_log_error "${key} deve ser um número válido."
        return 1
    fi
}

config_validate_status_key() {
    local key="${1:-}"
    local value

    if ! config_has "$key"; then
        return 0
    fi

    value="$(config_get "$key")"

    if ! config_is_status "$value"; then
        config_log_error \
            "${key} deve ser OK, WARNING, CRITICAL, UNKNOWN ou SKIPPED."
        return 1
    fi
}

config_validate_mode_key() {
    local key="${1:-}"
    local value

    if ! config_has "$key"; then
        return 0
    fi

    value="$(config_get "$key")"

    if ! config_is_file_mode "$value"; then
        config_log_error "${key} possui modo de arquivo inválido: ${value}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Validação da configuração principal
# ---------------------------------------------------------------------------

config_validate_main() {
    local failure=0
    local key

    local -a boolean_keys=(
        "HC_ENABLE_TERMINAL_OUTPUT"
        "HC_ENABLE_TXT_REPORT"
        "HC_ENABLE_JSON_REPORT"
        "HC_ENABLE_HTML_REPORT"
        "HC_NON_INTERACTIVE"
        "HC_USE_SUDO"
        "HC_KEEP_TEMP_FILES"
        "HC_CONTINUE_ON_OPTIONAL_MODULE_FAILURE"
        "HC_CONTINUE_ON_REQUIRED_MODULE_FAILURE"
        "HC_CREATE_EXECUTION_SUBDIRECTORY"
        "HC_LOG_TO_FILE"
        "HC_LOG_TO_STDOUT"
        "HC_LOG_INCLUDE_TIMESTAMP"
        "HC_LOG_INCLUDE_PID"
        "HC_LOG_INCLUDE_SOURCE"
        "HC_LOG_COMMAND_OUTPUT"
        "HC_LOG_SKIPPED_CHECKS"
        "HC_REDACT_SECRETS"
        "HC_REDACT_PUBLIC_IP"
        "HC_REDACT_PRIVATE_IP"
        "HC_REDACT_HOSTNAME"
        "HC_REDACT_USERNAMES"
        "HC_REDACT_DOMAINS"
        "HC_INCLUDE_COMMAND_LINES"
        "HC_INCLUDE_PROCESS_ENVIRONMENT"
        "HC_INCLUDE_SENSITIVE_CONFIG_VALUES"
        "HC_SYSTEM_ENABLED"
        "HC_CPU_ENABLED"
        "HC_MEMORY_ENABLED"
        "HC_DISK_ENABLED"
        "HC_NETWORK_ENABLED"
        "HC_SERVICES_ENABLED"
        "HC_UPDATES_ENABLED"
        "HC_PYTHON_ENABLED"
        "HC_DOCKER_ENABLED"
        "HC_NGINX_ENABLED"
        "HC_SSL_ENABLED"
        "HC_DATABASE_ENABLED"
        "HC_FIREWALL_ENABLED"
        "HC_SECURITY_ENABLED"
        "HC_LOGS_ENABLED"
        "HC_AI_ENABLED"
        "HC_OLLAMA_ENABLED"
        "HC_TEST_MODE"
        "HC_TEST_ALLOW_PRIVILEGED_COMMANDS"
    )

    local -a unsigned_keys=(
        "HC_LOG_MAX_SIZE_BYTES"
        "HC_LOG_ROTATION_COUNT"
        "HC_COMMAND_TIMEOUT_SECONDS"
        "HC_LONG_COMMAND_TIMEOUT_SECONDS"
        "HC_HTTP_CONNECT_TIMEOUT_SECONDS"
        "HC_HTTP_TOTAL_TIMEOUT_SECONDS"
        "HC_DNS_TIMEOUT_SECONDS"
        "HC_KILL_COMMAND_AFTER_SECONDS"
        "HC_CPU_SAMPLE_SECONDS"
        "HC_CPU_TOP_PROCESSES_LIMIT"
        "HC_MEMORY_TOP_PROCESSES_LIMIT"
        "HC_DISK_TOP_DIRECTORIES_LIMIT"
        "HC_DISK_TOP_FILES_LIMIT"
        "HC_NETWORK_CONNECTIONS_LIMIT"
        "HC_SERVICES_MAX_RESULTS"
        "HC_PYTHON_PROJECT_MAX_DEPTH"
        "HC_PYTHON_PROJECT_LIMIT"
        "HC_DOCKER_STATS_TIMEOUT_SECONDS"
        "HC_DOCKER_MAX_CONTAINERS"
        "HC_DOCKER_MAX_IMAGES"
        "HC_DOCKER_MAX_VOLUMES"
        "HC_DOCKER_MAX_NETWORKS"
        "HC_NGINX_MAX_CONFIG_FILES"
        "HC_SSL_CERTIFICATE_MAX_DEPTH"
        "HC_SSL_CERTIFICATE_LIMIT"
        "HC_FIREWALL_MAX_RULES"
        "HC_SECURITY_LAST_LOGINS_LIMIT"
        "HC_SECURITY_FAILED_LOGINS_LIMIT"
        "HC_LOGS_JOURNAL_LINES"
        "HC_LOGS_RECENT_HOURS"
        "HC_LOGS_MAX_RESULTS"
        "HC_OLLAMA_MAX_MODELS"
        "HC_REPORT_RETENTION_DAYS"
        "HC_LOG_RETENTION_DAYS"
    )

    local -a mode_keys=(
        "HC_REPORT_DIRECTORY_MODE"
        "HC_REPORT_FILE_MODE"
        "HC_LOG_DIRECTORY_MODE"
        "HC_LOG_FILE_MODE"
    )

    for key in "${boolean_keys[@]}"; do
        config_validate_boolean_key "$key" || failure=1
    done

    for key in "${unsigned_keys[@]}"; do
        config_validate_unsigned_key "$key" || failure=1
    done

    for key in "${mode_keys[@]}"; do
        config_validate_mode_key "$key" || failure=1
    done

    case "$(config_get "HC_DEFAULT_RUN_MODE" "quick")" in
        quick | full | custom)
            ;;
        *)
            config_log_error \
                "HC_DEFAULT_RUN_MODE deve ser quick, full ou custom."
            failure=1
            ;;
    esac

    case "$(config_get "HC_LOG_LEVEL" "INFO")" in
        DEBUG | INFO | NOTICE | WARNING | ERROR | CRITICAL)
            ;;
        *)
            config_log_error \
                "HC_LOG_LEVEL possui valor inválido."
            failure=1
            ;;
    esac

    case "$(config_get "HC_COLOR_MODE" "auto")" in
        auto | always | never)
            ;;
        *)
            config_log_error \
                "HC_COLOR_MODE deve ser auto, always ou never."
            failure=1
            ;;
    esac

    case "$(config_get "HC_UNICODE_MODE" "auto")" in
        auto | always | never)
            ;;
        *)
            config_log_error \
                "HC_UNICODE_MODE deve ser auto, always ou never."
            failure=1
            ;;
    esac

    return "$failure"
}

# ---------------------------------------------------------------------------
# Validação dos limites
# ---------------------------------------------------------------------------

config_validate_threshold_relationship() {
    local warning_key="${1:-}"
    local critical_key="${2:-}"
    local direction="${3:-higher_is_worse}"

    local warning_value
    local critical_value

    if ! config_has "$warning_key" || ! config_has "$critical_key"; then
        return 0
    fi

    warning_value="$(config_get "$warning_key")"
    critical_value="$(config_get "$critical_key")"

    if ! config_is_decimal "$warning_value" ||
        ! config_is_decimal "$critical_value"; then

        config_log_error \
            "Os limites ${warning_key} e ${critical_key} devem ser numéricos."

        return 1
    fi

    case "$direction" in
        higher_is_worse)
            if awk \
                -v warning="$warning_value" \
                -v critical="$critical_value" \
                'BEGIN { exit !(warning < critical) }'; then
                return 0
            fi

            config_log_error \
                "${warning_key} deve ser menor que ${critical_key}."
            ;;
        lower_is_worse)
            if awk \
                -v warning="$warning_value" \
                -v critical="$critical_value" \
                'BEGIN { exit !(warning > critical) }'; then
                return 0
            fi

            config_log_error \
                "${warning_key} deve ser maior que ${critical_key}."
            ;;
        *)
            config_log_error \
                "Direção inválida na validação dos limites: ${direction}"
            return 2
            ;;
    esac

    return 1
}

config_validate_thresholds() {
    local failure=0
    local key
    local value

    for key in "${HC_THRESHOLD_LOADED_KEYS[@]}"; do
        value="$(config_get "$key")"

        case "$key" in
            *_STATUS)
                config_validate_status_key "$key" || failure=1
                ;;
            *_REQUIRED | *_ENABLED)
                config_validate_boolean_key "$key" || failure=1
                ;;
            *_WARNING_* | *_CRITICAL_*)
                if [[ "$key" != *_STATUS ]]; then
                    config_validate_decimal_key "$key" || failure=1
                fi
                ;;
        esac
    done

    config_validate_threshold_relationship \
        "HC_CPU_USAGE_WARNING_PERCENT" \
        "HC_CPU_USAGE_CRITICAL_PERCENT" \
        "higher_is_worse" || failure=1

    config_validate_threshold_relationship \
        "HC_MEMORY_USAGE_WARNING_PERCENT" \
        "HC_MEMORY_USAGE_CRITICAL_PERCENT" \
        "higher_is_worse" || failure=1

    config_validate_threshold_relationship \
        "HC_SWAP_USAGE_WARNING_PERCENT" \
        "HC_SWAP_USAGE_CRITICAL_PERCENT" \
        "higher_is_worse" || failure=1

    config_validate_threshold_relationship \
        "HC_DISK_USAGE_WARNING_PERCENT" \
        "HC_DISK_USAGE_CRITICAL_PERCENT" \
        "higher_is_worse" || failure=1

    config_validate_threshold_relationship \
        "HC_DISK_INODE_WARNING_PERCENT" \
        "HC_DISK_INODE_CRITICAL_PERCENT" \
        "higher_is_worse" || failure=1

    config_validate_threshold_relationship \
        "HC_SSL_EXPIRATION_WARNING_DAYS" \
        "HC_SSL_EXPIRATION_CRITICAL_DAYS" \
        "lower_is_worse" || failure=1

    config_validate_threshold_relationship \
        "HC_HTTP_RESPONSE_WARNING_MS" \
        "HC_HTTP_RESPONSE_CRITICAL_MS" \
        "higher_is_worse" || failure=1

    config_validate_threshold_relationship \
        "HC_UPDATES_AVAILABLE_WARNING_COUNT" \
        "HC_UPDATES_AVAILABLE_CRITICAL_COUNT" \
        "higher_is_worse" || failure=1

    config_validate_threshold_relationship \
        "HC_SECURITY_UPDATES_WARNING_COUNT" \
        "HC_SECURITY_UPDATES_CRITICAL_COUNT" \
        "higher_is_worse" || failure=1

    config_validate_threshold_relationship \
        "HC_DOCKER_CONTAINER_CPU_WARNING_PERCENT" \
        "HC_DOCKER_CONTAINER_CPU_CRITICAL_PERCENT" \
        "higher_is_worse" || failure=1

    config_validate_threshold_relationship \
        "HC_DOCKER_CONTAINER_MEMORY_WARNING_PERCENT" \
        "HC_DOCKER_CONTAINER_MEMORY_CRITICAL_PERCENT" \
        "higher_is_worse" || failure=1

    config_validate_threshold_relationship \
        "HC_OLLAMA_MEMORY_WARNING_PERCENT" \
        "HC_OLLAMA_MEMORY_CRITICAL_PERCENT" \
        "higher_is_worse" || failure=1

    return "$failure"
}

# ---------------------------------------------------------------------------
# Aplicação das configurações
# ---------------------------------------------------------------------------

config_apply_runtime_settings() {
    HC_LOG_LEVEL="$(config_get "HC_LOG_LEVEL" "${HC_LOG_LEVEL:-INFO}")"
    HC_LOG_TO_FILE="$(config_get "HC_LOG_TO_FILE" "${HC_LOG_TO_FILE:-1}")"
    HC_LOG_TO_STDOUT="$(config_get "HC_LOG_TO_STDOUT" "${HC_LOG_TO_STDOUT:-0}")"
    HC_LOG_INCLUDE_TIMESTAMP="$(
        config_get \
            "HC_LOG_INCLUDE_TIMESTAMP" \
            "${HC_LOG_INCLUDE_TIMESTAMP:-1}"
    )"
    HC_LOG_INCLUDE_PID="$(
        config_get \
            "HC_LOG_INCLUDE_PID" \
            "${HC_LOG_INCLUDE_PID:-1}"
    )"
    HC_LOG_INCLUDE_SOURCE="$(
        config_get \
            "HC_LOG_INCLUDE_SOURCE" \
            "${HC_LOG_INCLUDE_SOURCE:-1}"
    )"
    HC_LOG_MAX_SIZE_BYTES="$(
        config_get \
            "HC_LOG_MAX_SIZE_BYTES" \
            "${HC_LOG_MAX_SIZE_BYTES:-10485760}"
    )"
    HC_LOG_ROTATION_COUNT="$(
        config_get \
            "HC_LOG_ROTATION_COUNT" \
            "${HC_LOG_ROTATION_COUNT:-5}"
    )"
    HC_LOG_FILE_MODE="$(
        config_get \
            "HC_LOG_FILE_MODE" \
            "${HC_LOG_FILE_MODE:-0640}"
    )"

    if [[ "${NO_COLOR:-0}" != "1" ]]; then
        case "$(config_get "HC_COLOR_MODE" "auto")" in
            never)
                NO_COLOR=1
                export NO_COLOR

                if declare -F colors_disable >/dev/null 2>&1; then
                    colors_disable
                fi
                ;;
            always)
                unset NO_COLOR

                if declare -F colors_enable >/dev/null 2>&1; then
                    colors_enable
                fi
                ;;
            auto)
                ;;
        esac
    fi

    export HC_LOG_LEVEL
    export HC_LOG_TO_FILE
    export HC_LOG_TO_STDOUT
    export HC_LOG_INCLUDE_TIMESTAMP
    export HC_LOG_INCLUDE_PID
    export HC_LOG_INCLUDE_SOURCE
    export HC_LOG_MAX_SIZE_BYTES
    export HC_LOG_ROTATION_COUNT
    export HC_LOG_FILE_MODE
}

# ---------------------------------------------------------------------------
# Carregamento completo
# ---------------------------------------------------------------------------

config_load_all() {
    local main_file="${1:-${CONFIG_FILE:-}}"
    local thresholds_file="${2:-${THRESHOLDS_FILE:-}}"
    local failure=0

    HC_CONFIG_WARNINGS=()
    HC_CONFIG_ERRORS=()

    if ! config_load_main "$main_file"; then
        failure=1
    fi

    if ! config_load_thresholds "$thresholds_file"; then
        failure=1
    fi

    if ((failure == 1)); then
        config_log_error \
            "Não foi possível carregar completamente os arquivos de configuração."
        return "${EXIT_CONFIGURATION_ERROR:-7}"
    fi

    if ! config_validate_main; then
        failure=1
    fi

    if ! config_validate_thresholds; then
        failure=1
    fi

    if ((failure == 1)); then
        config_log_error \
            "A validação dos arquivos de configuração falhou."
        return "${EXIT_CONFIGURATION_ERROR:-7}"
    fi

    config_apply_runtime_settings

    HC_CONFIG_LOADER_INITIALIZED=1
    export HC_CONFIG_LOADER_INITIALIZED

    config_log_info \
        "Configuração validada | principal=${#HC_CONFIG_LOADED_KEYS[@]} chaves | limites=${#HC_THRESHOLD_LOADED_KEYS[@]} chaves"

    return 0
}

config_is_initialized() {
    ((HC_CONFIG_LOADER_INITIALIZED == 1))
}

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------

config_print_summary() {
    printf 'Configuração\n'
    printf '  Principal:          %s\n' \
        "${HC_CONFIG_MAIN_PATH:-não carregada}"
    printf '  Limites:            %s\n' \
        "${HC_CONFIG_THRESHOLDS_PATH:-não carregado}"
    printf '  Chaves principais:  %s\n' \
        "${#HC_CONFIG_LOADED_KEYS[@]}"
    printf '  Chaves de limites:  %s\n' \
        "${#HC_THRESHOLD_LOADED_KEYS[@]}"
    printf '  Avisos:             %s\n' \
        "${#HC_CONFIG_WARNINGS[@]}"
    printf '  Erros:              %s\n' \
        "${#HC_CONFIG_ERRORS[@]}"
}

# ---------------------------------------------------------------------------
# Validação interna
# ---------------------------------------------------------------------------

config_validate() {
    local failure=0
    local temporary_directory
    local main_file
    local thresholds_file
    local parsed_key=""
    local parsed_value=""

    temporary_directory="$(
        mktemp -d "${TMPDIR:-/tmp}/vps-healthcheck-config-test.XXXXXX"
    )"

    main_file="${temporary_directory}/healthcheck.conf"
    thresholds_file="${temporary_directory}/thresholds.conf"

    cat >"$main_file" <<'EOF'
HC_CONFIG_VERSION="1"
HC_DEFAULT_RUN_MODE="quick"
HC_LOG_LEVEL="DEBUG"
HC_LOG_TO_FILE="1"
HC_LOG_TO_STDOUT="0"
HC_LOG_INCLUDE_TIMESTAMP="1"
HC_LOG_INCLUDE_PID="1"
HC_LOG_INCLUDE_SOURCE="1"
HC_LOG_MAX_SIZE_BYTES="10485760"
HC_LOG_ROTATION_COUNT="5"
HC_LOG_FILE_MODE="0640"
HC_COLOR_MODE="auto"
HC_UNICODE_MODE="auto"
HC_SYSTEM_ENABLED="1"
EOF

    cat >"$thresholds_file" <<'EOF'
HC_THRESHOLDS_VERSION="1"
HC_CPU_USAGE_WARNING_PERCENT="75"
HC_CPU_USAGE_CRITICAL_PERCENT="90"
HC_MEMORY_USAGE_WARNING_PERCENT="80"
HC_MEMORY_USAGE_CRITICAL_PERCENT="92"
HC_SWAP_USAGE_WARNING_PERCENT="50"
HC_SWAP_USAGE_CRITICAL_PERCENT="80"
HC_DISK_USAGE_WARNING_PERCENT="75"
HC_DISK_USAGE_CRITICAL_PERCENT="90"
HC_DISK_INODE_WARNING_PERCENT="75"
HC_DISK_INODE_CRITICAL_PERCENT="90"
HC_SSL_EXPIRATION_WARNING_DAYS="30"
HC_SSL_EXPIRATION_CRITICAL_DAYS="15"
HC_HTTP_RESPONSE_WARNING_MS="1000"
HC_HTTP_RESPONSE_CRITICAL_MS="3000"
HC_UPDATES_AVAILABLE_WARNING_COUNT="20"
HC_UPDATES_AVAILABLE_CRITICAL_COUNT="50"
HC_SECURITY_UPDATES_WARNING_COUNT="1"
HC_SECURITY_UPDATES_CRITICAL_COUNT="10"
HC_DOCKER_CONTAINER_CPU_WARNING_PERCENT="80"
HC_DOCKER_CONTAINER_CPU_CRITICAL_PERCENT="95"
HC_DOCKER_CONTAINER_MEMORY_WARNING_PERCENT="80"
HC_DOCKER_CONTAINER_MEMORY_CRITICAL_PERCENT="95"
HC_OLLAMA_MEMORY_WARNING_PERCENT="70"
HC_OLLAMA_MEMORY_CRITICAL_PERCENT="90"
HC_HTTP_CONNECTION_FAILURE_STATUS="CRITICAL"
EOF

    if ! config_parse_assignment \
        'HC_TEST_VALUE="valor de teste"' \
        parsed_key \
        parsed_value; then

        printf 'Falha em config_parse_assignment.\n' >&2
        failure=1
    elif [[ "$parsed_key" != "HC_TEST_VALUE" ||
        "$parsed_value" != "valor de teste" ]]; then

        printf 'Resultado incorreto em config_parse_assignment.\n' >&2
        failure=1
    fi

    if config_parse_assignment \
        'HC_TEST_VALUE="$(id)"' \
        parsed_key \
        parsed_value; then

        printf 'O parser aceitou substituição de comando.\n' >&2
        failure=1
    fi

    if config_parse_assignment \
        'VARIAVEL_INVALIDA="teste"' \
        parsed_key \
        parsed_value; then

        printf 'O parser aceitou chave fora do prefixo HC_.\n' >&2
        failure=1
    fi

    if ! config_load_all "$main_file" "$thresholds_file"; then
        printf 'Falha em config_load_all.\n' >&2
        failure=1
    fi

    if [[ "$(config_get "HC_LOG_LEVEL")" != "DEBUG" ]]; then
        printf 'Falha em config_get para configuração principal.\n' >&2
        failure=1
    fi

    if [[ "$(config_get "HC_CPU_USAGE_WARNING_PERCENT")" != "75" ]]; then
        printf 'Falha em config_get para limites.\n' >&2
        failure=1
    fi

    if ! config_is_initialized; then
        printf 'O carregador não foi marcado como inicializado.\n' >&2
        failure=1
    fi

    rm -rf -- "$temporary_directory"

    return "$failure"
}
