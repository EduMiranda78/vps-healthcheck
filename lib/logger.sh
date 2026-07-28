#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_LOGGER_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_LOGGER_LOADED=1

# ---------------------------------------------------------------------------
# Configuração padrão
# ---------------------------------------------------------------------------

HC_LOG_INITIALIZED=0
HC_LOG_FILE="${CURRENT_LOG_FILE:-}"
HC_LOG_LEVEL="${HC_LOG_LEVEL:-INFO}"
HC_LOG_TO_FILE="${HC_LOG_TO_FILE:-1}"
HC_LOG_TO_STDOUT="${HC_LOG_TO_STDOUT:-0}"
HC_LOG_INCLUDE_TIMESTAMP="${HC_LOG_INCLUDE_TIMESTAMP:-1}"
HC_LOG_INCLUDE_PID="${HC_LOG_INCLUDE_PID:-1}"
HC_LOG_INCLUDE_SOURCE="${HC_LOG_INCLUDE_SOURCE:-1}"
HC_LOG_MAX_SIZE_BYTES="${HC_LOG_MAX_SIZE_BYTES:-10485760}"
HC_LOG_ROTATION_COUNT="${HC_LOG_ROTATION_COUNT:-5}"
HC_LOG_FILE_MODE="${HC_LOG_FILE_MODE:-0640}"

declare -ag HC_LOG_BUFFER=()

# ---------------------------------------------------------------------------
# Validação
# ---------------------------------------------------------------------------

logger_level_is_valid() {
    local level="${1:-}"

    case "$level" in
        DEBUG | INFO | NOTICE | WARNING | ERROR | CRITICAL)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

logger_level_priority() {
    local level="${1:-INFO}"

    if declare -F hc_log_level_priority >/dev/null 2>&1; then
        hc_log_level_priority "$level"
        return
    fi

    case "$level" in
        DEBUG)
            printf '10\n'
            ;;
        INFO)
            printf '20\n'
            ;;
        NOTICE)
            printf '25\n'
            ;;
        WARNING)
            printf '30\n'
            ;;
        ERROR)
            printf '40\n'
            ;;
        CRITICAL)
            printf '50\n'
            ;;
        *)
            printf '20\n'
            return 1
            ;;
    esac
}

logger_should_log() {
    local requested_level="${1:-INFO}"
    local configured_priority
    local requested_priority

    if ! logger_level_is_valid "$requested_level"; then
        requested_level="INFO"
    fi

    configured_priority="$(logger_level_priority "$HC_LOG_LEVEL")"
    requested_priority="$(logger_level_priority "$requested_level")"

    ((requested_priority >= configured_priority))
}

logger_validate_configuration() {
    local failure=0

    if ! logger_level_is_valid "$HC_LOG_LEVEL"; then
        printf 'Nível de log inválido: %s\n' "$HC_LOG_LEVEL" >&2
        failure=1
    fi

    if [[ ! "$HC_LOG_TO_FILE" =~ ^[01]$ ]]; then
        printf 'HC_LOG_TO_FILE deve ser 0 ou 1.\n' >&2
        failure=1
    fi

    if [[ ! "$HC_LOG_TO_STDOUT" =~ ^[01]$ ]]; then
        printf 'HC_LOG_TO_STDOUT deve ser 0 ou 1.\n' >&2
        failure=1
    fi

    if [[ ! "$HC_LOG_INCLUDE_TIMESTAMP" =~ ^[01]$ ]]; then
        printf 'HC_LOG_INCLUDE_TIMESTAMP deve ser 0 ou 1.\n' >&2
        failure=1
    fi

    if [[ ! "$HC_LOG_INCLUDE_PID" =~ ^[01]$ ]]; then
        printf 'HC_LOG_INCLUDE_PID deve ser 0 ou 1.\n' >&2
        failure=1
    fi

    if [[ ! "$HC_LOG_INCLUDE_SOURCE" =~ ^[01]$ ]]; then
        printf 'HC_LOG_INCLUDE_SOURCE deve ser 0 ou 1.\n' >&2
        failure=1
    fi

    if [[ ! "$HC_LOG_MAX_SIZE_BYTES" =~ ^[0-9]+$ ]]; then
        printf 'HC_LOG_MAX_SIZE_BYTES deve ser inteiro não negativo.\n' >&2
        failure=1
    fi

    if [[ ! "$HC_LOG_ROTATION_COUNT" =~ ^[0-9]+$ ]]; then
        printf 'HC_LOG_ROTATION_COUNT deve ser inteiro não negativo.\n' >&2
        failure=1
    fi

    return "$failure"
}

# ---------------------------------------------------------------------------
# Caminho do arquivo
# ---------------------------------------------------------------------------

logger_default_file() {
    local log_directory
    local run_identifier

    log_directory="${LOGS_DIR:-${PROJECT_ROOT:-.}/logs}"
    run_identifier="${RUN_ID:-$(date '+%Y%m%d_%H%M%S')_$$}"

    printf '%s/healthcheck_%s.log\n' \
        "$log_directory" \
        "$run_identifier"
}

logger_set_file() {
    local file_path="${1:-}"
    local parent_directory

    if [[ -z "$file_path" ]]; then
        return 1
    fi

    parent_directory="$(dirname -- "$file_path")"

    if declare -F utils_ensure_directory >/dev/null 2>&1; then
        utils_ensure_directory "$parent_directory" "0750"
    else
        mkdir -p -- "$parent_directory"
        chmod 0750 "$parent_directory" 2>/dev/null || true
    fi

    if [[ -e "$file_path" && ! -f "$file_path" ]]; then
        return 1
    fi

    touch -- "$file_path"
    chmod "$HC_LOG_FILE_MODE" "$file_path" 2>/dev/null || true

    HC_LOG_FILE="$file_path"
    CURRENT_LOG_FILE="$file_path"

    export HC_LOG_FILE
    export CURRENT_LOG_FILE
}

logger_get_file() {
    printf '%s\n' "$HC_LOG_FILE"
}

# ---------------------------------------------------------------------------
# Rotação
# ---------------------------------------------------------------------------

logger_file_size() {
    local file_path="${1:-$HC_LOG_FILE}"

    if [[ -z "$file_path" || ! -f "$file_path" ]]; then
        printf '0\n'
        return 1
    fi

    if declare -F utils_file_size_bytes >/dev/null 2>&1; then
        utils_file_size_bytes "$file_path"
    else
        stat -c '%s' -- "$file_path" 2>/dev/null || printf '0\n'
    fi
}

logger_rotate() {
    local file_path="${1:-$HC_LOG_FILE}"
    local index
    local previous_file
    local rotated_file

    if [[ -z "$file_path" || ! -f "$file_path" ]]; then
        return 0
    fi

    if ((HC_LOG_ROTATION_COUNT == 0)); then
        : >"$file_path"
        return 0
    fi

    for ((index = HC_LOG_ROTATION_COUNT; index >= 1; index--)); do
        rotated_file="${file_path}.${index}"

        if ((index == HC_LOG_ROTATION_COUNT)); then
            rm -f -- "$rotated_file"
        fi

        if ((index == 1)); then
            previous_file="$file_path"
        else
            previous_file="${file_path}.$((index - 1))"
        fi

        if [[ -f "$previous_file" ]]; then
            mv -f -- "$previous_file" "$rotated_file"
        fi
    done

    touch -- "$file_path"
    chmod "$HC_LOG_FILE_MODE" "$file_path" 2>/dev/null || true
}

logger_rotate_if_needed() {
    local file_size

    if ((HC_LOG_TO_FILE == 0)); then
        return 0
    fi

    if [[ -z "$HC_LOG_FILE" || ! -f "$HC_LOG_FILE" ]]; then
        return 0
    fi

    if ((HC_LOG_MAX_SIZE_BYTES == 0)); then
        return 0
    fi

    file_size="$(logger_file_size "$HC_LOG_FILE" 2>/dev/null || printf '0')"

    if [[ ! "$file_size" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if ((file_size >= HC_LOG_MAX_SIZE_BYTES)); then
        logger_rotate "$HC_LOG_FILE"
    fi
}

# ---------------------------------------------------------------------------
# Formatação
# ---------------------------------------------------------------------------

logger_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

logger_source_context() {
    local function_name="${1:-}"
    local source_file="${2:-}"
    local source_line="${3:-}"

    if [[ -z "$function_name" ]]; then
        function_name="main"
    fi

    if [[ -z "$source_file" ]]; then
        source_file="desconhecido"
    fi

    if [[ -z "$source_line" ]]; then
        source_line="0"
    fi

    printf '%s@%s:%s' \
        "$function_name" \
        "$source_file" \
        "$source_line"
}

logger_sanitize_message() {
    local message="${1:-}"

    if declare -F utils_sanitize_single_line >/dev/null 2>&1; then
        utils_sanitize_single_line "$message"
        return
    fi

    message="${message//$'\r'/ }"
    message="${message//$'\n'/ }"
    message="${message//$'\t'/ }"

    while [[ "$message" == *"  "* ]]; do
        message="${message//  / }"
    done

    printf '%s' "$message"
}

logger_format_line() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local function_name="${3:-main}"
    local source_file="${4:-desconhecido}"
    local source_line="${5:-0}"
    local line=""

    message="$(logger_sanitize_message "$message")"

    if ((HC_LOG_INCLUDE_TIMESTAMP == 1)); then
        line+="$(logger_timestamp) "
    fi

    line+="[${level}]"

    if ((HC_LOG_INCLUDE_PID == 1)); then
        line+=" [pid=$$]"
    fi

    if ((HC_LOG_INCLUDE_SOURCE == 1)); then
        line+=" [$(logger_source_context \
            "$function_name" \
            "$source_file" \
            "$source_line")]"
    fi

    line+=" ${message}"

    printf '%s' "$line"
}

# ---------------------------------------------------------------------------
# Cores para terminal
# ---------------------------------------------------------------------------

logger_level_color() {
    local level="${1:-INFO}"

    case "$level" in
        DEBUG)
            printf '%s' "${HC_COLOR_MUTED:-}"
            ;;
        INFO)
            printf '%s' "${HC_COLOR_INFO:-}"
            ;;
        NOTICE)
            printf '%s' "${HC_COLOR_NOTICE:-}"
            ;;
        WARNING)
            printf '%s' "${HC_COLOR_WARNING:-}"
            ;;
        ERROR)
            printf '%s' "${HC_COLOR_ERROR:-}"
            ;;
        CRITICAL)
            printf '%s' "${HC_COLOR_CRITICAL:-}"
            ;;
        *)
            printf '%s' "${HC_COLOR_RESET:-}"
            ;;
    esac
}

logger_print_terminal() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local color
    local reset

    color="$(logger_level_color "$level")"
    reset="${HC_COLOR_RESET:-}"

    case "$level" in
        ERROR | CRITICAL)
            printf '%s[%s]%s %s\n' \
                "$color" \
                "$level" \
                "$reset" \
                "$message" >&2
            ;;
        *)
            printf '%s[%s]%s %s\n' \
                "$color" \
                "$level" \
                "$reset" \
                "$message"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Escrita
# ---------------------------------------------------------------------------

logger_write_file() {
    local line="${1:-}"

    if ((HC_LOG_TO_FILE == 0)); then
        return 0
    fi

    if [[ -z "$HC_LOG_FILE" ]]; then
        return 1
    fi

    logger_rotate_if_needed

    printf '%s\n' "$line" >>"$HC_LOG_FILE"
}

logger_write_stdout() {
    local level="${1:-INFO}"
    local message="${2:-}"

    if ((HC_LOG_TO_STDOUT == 0)); then
        return 0
    fi

    logger_print_terminal "$level" "$message"
}

logger_buffer_add() {
    local line="${1:-}"

    HC_LOG_BUFFER+=("$line")
}

logger_buffer_flush() {
    local line

    if ((${#HC_LOG_BUFFER[@]} == 0)); then
        return 0
    fi

    for line in "${HC_LOG_BUFFER[@]}"; do
        logger_write_file "$line"
    done

    HC_LOG_BUFFER=()
}

# ---------------------------------------------------------------------------
# Função principal
# ---------------------------------------------------------------------------

logger_log() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local function_name="${3:-${FUNCNAME[1]:-main}}"
    local source_file="${4:-${BASH_SOURCE[1]:-desconhecido}}"
    local source_line="${5:-${BASH_LINENO[0]:-0}}"
    local formatted_line

    level="${level^^}"

    if ! logger_level_is_valid "$level"; then
        level="INFO"
    fi

    if ! logger_should_log "$level"; then
        return 0
    fi

    formatted_line="$(
        logger_format_line \
            "$level" \
            "$message" \
            "$function_name" \
            "$source_file" \
            "$source_line"
    )"

    if ((HC_LOG_INITIALIZED == 0)); then
        logger_buffer_add "$formatted_line"

        if ((HC_LOG_TO_STDOUT == 1)); then
            logger_write_stdout "$level" "$message"
        fi

        return 0
    fi

    logger_write_file "$formatted_line"
    logger_write_stdout "$level" "$message"
}

# ---------------------------------------------------------------------------
# Atalhos
# ---------------------------------------------------------------------------

logger_debug() {
    logger_log \
        "DEBUG" \
        "${1:-}" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_SOURCE[1]:-desconhecido}" \
        "${BASH_LINENO[0]:-0}"
}

logger_info() {
    logger_log \
        "INFO" \
        "${1:-}" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_SOURCE[1]:-desconhecido}" \
        "${BASH_LINENO[0]:-0}"
}

logger_notice() {
    logger_log \
        "NOTICE" \
        "${1:-}" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_SOURCE[1]:-desconhecido}" \
        "${BASH_LINENO[0]:-0}"
}

logger_warning() {
    logger_log \
        "WARNING" \
        "${1:-}" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_SOURCE[1]:-desconhecido}" \
        "${BASH_LINENO[0]:-0}"
}

logger_error() {
    logger_log \
        "ERROR" \
        "${1:-}" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_SOURCE[1]:-desconhecido}" \
        "${BASH_LINENO[0]:-0}"
}

logger_critical() {
    logger_log \
        "CRITICAL" \
        "${1:-}" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_SOURCE[1]:-desconhecido}" \
        "${BASH_LINENO[0]:-0}"
}

# ---------------------------------------------------------------------------
# Configuração dinâmica
# ---------------------------------------------------------------------------

logger_set_level() {
    local level="${1:-}"

    level="${level^^}"

    if ! logger_level_is_valid "$level"; then
        return 1
    fi

    HC_LOG_LEVEL="$level"
    export HC_LOG_LEVEL
}

logger_enable_file() {
    HC_LOG_TO_FILE=1
    export HC_LOG_TO_FILE
}

logger_disable_file() {
    HC_LOG_TO_FILE=0
    export HC_LOG_TO_FILE
}

logger_enable_stdout() {
    HC_LOG_TO_STDOUT=1
    export HC_LOG_TO_STDOUT
}

logger_disable_stdout() {
    HC_LOG_TO_STDOUT=0
    export HC_LOG_TO_STDOUT
}

logger_set_max_size() {
    local size_bytes="${1:-}"

    if [[ ! "$size_bytes" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    HC_LOG_MAX_SIZE_BYTES="$size_bytes"
    export HC_LOG_MAX_SIZE_BYTES
}

logger_set_rotation_count() {
    local count="${1:-}"

    if [[ ! "$count" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    HC_LOG_ROTATION_COUNT="$count"
    export HC_LOG_ROTATION_COUNT
}

# ---------------------------------------------------------------------------
# Inicialização
# ---------------------------------------------------------------------------

logger_initialize() {
    local selected_file

    logger_validate_configuration

    if [[ -z "$HC_LOG_FILE" ]]; then
        selected_file="$(logger_default_file)"
        logger_set_file "$selected_file"
    else
        logger_set_file "$HC_LOG_FILE"
    fi

    HC_LOG_INITIALIZED=1
    export HC_LOG_INITIALIZED

    logger_buffer_flush

    logger_info \
        "Logger inicializado | arquivo=${HC_LOG_FILE} | nível=${HC_LOG_LEVEL}"
}

logger_shutdown() {
    if ((HC_LOG_INITIALIZED == 0)); then
        return 0
    fi

    logger_info "Logger finalizado"

    logger_buffer_flush

    HC_LOG_INITIALIZED=0
    export HC_LOG_INITIALIZED
}

logger_is_initialized() {
    ((HC_LOG_INITIALIZED == 1))
}

# ---------------------------------------------------------------------------
# Leitura e consulta
# ---------------------------------------------------------------------------

logger_tail() {
    local lines="${1:-50}"

    if [[ ! "$lines" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [[ -z "$HC_LOG_FILE" || ! -r "$HC_LOG_FILE" ]]; then
        return 1
    fi

    tail -n "$lines" -- "$HC_LOG_FILE"
}

logger_count_by_level() {
    local level="${1:-INFO}"

    level="${level^^}"

    if ! logger_level_is_valid "$level"; then
        return 1
    fi

    if [[ -z "$HC_LOG_FILE" || ! -r "$HC_LOG_FILE" ]]; then
        printf '0\n'
        return 1
    fi

    grep -c "\[${level}\]" "$HC_LOG_FILE" 2>/dev/null ||
        printf '0\n'
}

logger_search() {
    local pattern="${1:-}"

    if [[ -z "$pattern" ]]; then
        return 1
    fi

    if [[ -z "$HC_LOG_FILE" || ! -r "$HC_LOG_FILE" ]]; then
        return 1
    fi

    grep -F -- "$pattern" "$HC_LOG_FILE"
}

# ---------------------------------------------------------------------------
# Validação interna
# ---------------------------------------------------------------------------

logger_validate() {
    local failure=0
    local temporary_directory
    local temporary_file

    local original_log_file="$HC_LOG_FILE"
    local original_current_log_file="${CURRENT_LOG_FILE:-}"
    local original_initialized="$HC_LOG_INITIALIZED"
    local original_to_file="$HC_LOG_TO_FILE"
    local original_to_stdout="$HC_LOG_TO_STDOUT"
    local original_level="$HC_LOG_LEVEL"
    local original_max_size="$HC_LOG_MAX_SIZE_BYTES"
    local original_rotation_count="$HC_LOG_ROTATION_COUNT"
    local original_file_mode="$HC_LOG_FILE_MODE"

    local -a original_buffer=("${HC_LOG_BUFFER[@]}")

    if declare -F utils_create_temp_directory >/dev/null 2>&1; then
        temporary_directory="$(
            utils_create_temp_directory "logger-test"
        )"
    else
        temporary_directory="$(
            mktemp -d "${TMPDIR:-/tmp}/logger-test.XXXXXX"
        )"
    fi

    temporary_file="${temporary_directory}/test.log"

    HC_LOG_FILE="$temporary_file"
    CURRENT_LOG_FILE="$temporary_file"
    HC_LOG_INITIALIZED=0
    HC_LOG_TO_FILE=1
    HC_LOG_TO_STDOUT=0
    HC_LOG_LEVEL="DEBUG"

    # A rotação não faz parte deste teste. Um limite pequeno pode mover
    # mensagens para arquivos rotacionados antes das verificações.
    HC_LOG_MAX_SIZE_BYTES=0
    HC_LOG_ROTATION_COUNT=0
    HC_LOG_FILE_MODE="0640"

    # O teste deve ser isolado das mensagens armazenadas antes da
    # inicialização normal do logger.
    HC_LOG_BUFFER=()

    if ! logger_initialize; then
        printf 'Falha ao inicializar o logger de teste.\n' >&2
        failure=1
    else
        logger_debug "mensagem debug"
        logger_info "mensagem info"
        logger_warning "mensagem warning"
        logger_error "mensagem error"

        if [[ ! -s "$temporary_file" ]]; then
            printf 'Falha ao gravar arquivo de log.\n' >&2
            failure=1
        fi

        if ! grep -F "[DEBUG]" "$temporary_file" >/dev/null 2>&1; then
            printf 'Falha ao registrar nível DEBUG.\n' >&2
            failure=1
        fi

        if ! grep -F "[INFO]" "$temporary_file" >/dev/null 2>&1; then
            printf 'Falha ao registrar nível INFO.\n' >&2
            failure=1
        fi

        if ! grep -F "[WARNING]" "$temporary_file" >/dev/null 2>&1; then
            printf 'Falha ao registrar nível WARNING.\n' >&2
            failure=1
        fi

        if ! grep -F "[ERROR]" "$temporary_file" >/dev/null 2>&1; then
            printf 'Falha ao registrar nível ERROR.\n' >&2
            failure=1
        fi

        if [[ "$(logger_count_by_level "DEBUG")" != "1" ]]; then
            printf 'Falha ao contar registros DEBUG.\n' >&2
            failure=1
        fi

        if [[ "$(logger_count_by_level "INFO")" != "2" ]]; then
            printf 'Falha ao contar registros INFO.\n' >&2
            failure=1
        fi

        if [[ "$(logger_count_by_level "WARNING")" != "1" ]]; then
            printf 'Falha ao contar registros WARNING.\n' >&2
            failure=1
        fi

        if [[ "$(logger_count_by_level "ERROR")" != "1" ]]; then
            printf 'Falha ao contar registros ERROR.\n' >&2
            failure=1
        fi

        if ! logger_search "mensagem warning" >/dev/null 2>&1; then
            printf 'Falha em logger_search.\n' >&2
            failure=1
        fi

        logger_shutdown
    fi

    rm -rf -- "$temporary_directory"

    HC_LOG_FILE="$original_log_file"
    CURRENT_LOG_FILE="$original_current_log_file"
    HC_LOG_INITIALIZED="$original_initialized"
    HC_LOG_TO_FILE="$original_to_file"
    HC_LOG_TO_STDOUT="$original_to_stdout"
    HC_LOG_LEVEL="$original_level"
    HC_LOG_MAX_SIZE_BYTES="$original_max_size"
    HC_LOG_ROTATION_COUNT="$original_rotation_count"
    HC_LOG_FILE_MODE="$original_file_mode"
    HC_LOG_BUFFER=("${original_buffer[@]}")

    export HC_LOG_FILE
    export CURRENT_LOG_FILE
    export HC_LOG_INITIALIZED
    export HC_LOG_TO_FILE
    export HC_LOG_TO_STDOUT
    export HC_LOG_LEVEL
    export HC_LOG_MAX_SIZE_BYTES
    export HC_LOG_ROTATION_COUNT
    export HC_LOG_FILE_MODE

    return "$failure"
}
