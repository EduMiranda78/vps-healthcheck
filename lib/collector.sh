#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_COLLECTOR_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_COLLECTOR_LOADED=1

# ---------------------------------------------------------------------------
# Estado geral
# ---------------------------------------------------------------------------

HC_COLLECTOR_INITIALIZED=0
HC_COLLECTOR_SCHEMA_VERSION="1"
HC_COLLECTOR_STARTED_AT=""
HC_COLLECTOR_FINISHED_AT=""
HC_COLLECTOR_STARTED_EPOCH=0
HC_COLLECTOR_FINISHED_EPOCH=0
HC_COLLECTOR_DURATION_SECONDS=0
HC_COLLECTOR_OVERALL_STATUS="${HC_STATUS_UNKNOWN:-UNKNOWN}"

# ---------------------------------------------------------------------------
# Dados da execução
# ---------------------------------------------------------------------------

declare -gA HC_COLLECTOR_META=()

# ---------------------------------------------------------------------------
# Dados dos módulos
# ---------------------------------------------------------------------------

declare -ag HC_COLLECTOR_MODULE_ORDER=()

declare -gA HC_COLLECTOR_MODULE_LABELS=()
declare -gA HC_COLLECTOR_MODULE_STATUS=()
declare -gA HC_COLLECTOR_MODULE_AVAILABLE=()
declare -gA HC_COLLECTOR_MODULE_STARTED_AT=()
declare -gA HC_COLLECTOR_MODULE_FINISHED_AT=()
declare -gA HC_COLLECTOR_MODULE_STARTED_EPOCH=()
declare -gA HC_COLLECTOR_MODULE_FINISHED_EPOCH=()
declare -gA HC_COLLECTOR_MODULE_DURATION_SECONDS=()
declare -gA HC_COLLECTOR_MODULE_MESSAGES=()
declare -gA HC_COLLECTOR_MODULE_ERRORS=()

# ---------------------------------------------------------------------------
# Métricas
# ---------------------------------------------------------------------------

declare -ag HC_COLLECTOR_METRIC_ORDER=()

declare -gA HC_COLLECTOR_METRIC_MODULE=()
declare -gA HC_COLLECTOR_METRIC_SECTION=()
declare -gA HC_COLLECTOR_METRIC_KEY=()
declare -gA HC_COLLECTOR_METRIC_LABEL=()
declare -gA HC_COLLECTOR_METRIC_VALUE=()
declare -gA HC_COLLECTOR_METRIC_RAW_VALUE=()
declare -gA HC_COLLECTOR_METRIC_TYPE=()
declare -gA HC_COLLECTOR_METRIC_UNIT=()
declare -gA HC_COLLECTOR_METRIC_STATUS=()
declare -gA HC_COLLECTOR_METRIC_DESCRIPTION=()
declare -gA HC_COLLECTOR_METRIC_SOURCE=()
declare -gA HC_COLLECTOR_METRIC_TIMESTAMP=()

# ---------------------------------------------------------------------------
# Tabelas
# ---------------------------------------------------------------------------

declare -ag HC_COLLECTOR_TABLE_ORDER=()

declare -gA HC_COLLECTOR_TABLE_MODULE=()
declare -gA HC_COLLECTOR_TABLE_SECTION=()
declare -gA HC_COLLECTOR_TABLE_KEY=()
declare -gA HC_COLLECTOR_TABLE_LABEL=()
declare -gA HC_COLLECTOR_TABLE_COLUMNS=()
declare -gA HC_COLLECTOR_TABLE_ROW_COUNT=()
declare -gA HC_COLLECTOR_TABLE_DESCRIPTION=()
declare -gA HC_COLLECTOR_TABLE_STATUS=()

declare -gA HC_COLLECTOR_TABLE_ROWS=()

# ---------------------------------------------------------------------------
# Alertas
# ---------------------------------------------------------------------------

declare -ag HC_COLLECTOR_ALERT_ORDER=()

declare -gA HC_COLLECTOR_ALERT_MODULE=()
declare -gA HC_COLLECTOR_ALERT_STATUS=()
declare -gA HC_COLLECTOR_ALERT_TITLE=()
declare -gA HC_COLLECTOR_ALERT_MESSAGE=()
declare -gA HC_COLLECTOR_ALERT_RECOMMENDATION=()
declare -gA HC_COLLECTOR_ALERT_TIMESTAMP=()

# ---------------------------------------------------------------------------
# Contadores internos
# ---------------------------------------------------------------------------

HC_COLLECTOR_METRIC_SEQUENCE=0
HC_COLLECTOR_TABLE_SEQUENCE=0
HC_COLLECTOR_ALERT_SEQUENCE=0

# ---------------------------------------------------------------------------
# Funções básicas
# ---------------------------------------------------------------------------

collector_now_iso8601() {
    if declare -F utils_now_iso8601 >/dev/null 2>&1; then
        utils_now_iso8601
    else
        date '+%Y-%m-%dT%H:%M:%S%z'
    fi
}

collector_now_epoch() {
    if declare -F utils_now_epoch >/dev/null 2>&1; then
        utils_now_epoch
    else
        date '+%s'
    fi
}

collector_sanitize_identifier() {
    local value="${1:-}"

    value="${value,,}"
    value="${value//[^a-z0-9_.-]/_}"

    while [[ "$value" == *"__"* ]]; do
        value="${value//__/_}"
    done

    value="${value##_}"
    value="${value%%_}"

    printf '%s' "$value"
}

collector_status_is_valid() {
    local status="${1:-}"

    if declare -F hc_status_is_valid >/dev/null 2>&1; then
        hc_status_is_valid "$status"
        return
    fi

    case "$status" in
        OK | WARNING | CRITICAL | UNKNOWN | SKIPPED)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

collector_normalize_status() {
    local status="${1:-UNKNOWN}"

    status="${status^^}"

    if collector_status_is_valid "$status"; then
        printf '%s\n' "$status"
    else
        printf '%s\n' "${HC_STATUS_UNKNOWN:-UNKNOWN}"
        return 1
    fi
}

collector_worst_status() {
    local first="${1:-${HC_STATUS_UNKNOWN:-UNKNOWN}}"
    local second="${2:-${HC_STATUS_UNKNOWN:-UNKNOWN}}"

    if declare -F hc_status_worst >/dev/null 2>&1; then
        hc_status_worst "$first" "$second"
        return
    fi

    local first_weight
    local second_weight

    case "$first" in
        OK) first_weight=0 ;;
        SKIPPED) first_weight=1 ;;
        UNKNOWN) first_weight=2 ;;
        WARNING) first_weight=3 ;;
        CRITICAL) first_weight=4 ;;
        *) first_weight=2 ;;
    esac

    case "$second" in
        OK) second_weight=0 ;;
        SKIPPED) second_weight=1 ;;
        UNKNOWN) second_weight=2 ;;
        WARNING) second_weight=3 ;;
        CRITICAL) second_weight=4 ;;
        *) second_weight=2 ;;
    esac

    if ((first_weight >= second_weight)); then
        printf '%s\n' "$first"
    else
        printf '%s\n' "$second"
    fi
}

collector_array_contains() {
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

collector_join_fields() {
    local delimiter="${1:-$'\t'}"
    shift || true

    local first=1
    local value

    for value in "$@"; do
        value="${value//$'\r'/ }"
        value="${value//$'\n'/ }"
        value="${value//$delimiter/ }"

        if ((first == 1)); then
            printf '%s' "$value"
            first=0
        else
            printf '%s%s' "$delimiter" "$value"
        fi
    done
}

# ---------------------------------------------------------------------------
# Inicialização
# ---------------------------------------------------------------------------

collector_reset() {
    HC_COLLECTOR_INITIALIZED=0
    HC_COLLECTOR_STARTED_AT=""
    HC_COLLECTOR_FINISHED_AT=""
    HC_COLLECTOR_STARTED_EPOCH=0
    HC_COLLECTOR_FINISHED_EPOCH=0
    HC_COLLECTOR_DURATION_SECONDS=0
    HC_COLLECTOR_OVERALL_STATUS="${HC_STATUS_UNKNOWN:-UNKNOWN}"

    HC_COLLECTOR_META=()

    HC_COLLECTOR_MODULE_ORDER=()
    HC_COLLECTOR_MODULE_LABELS=()
    HC_COLLECTOR_MODULE_STATUS=()
    HC_COLLECTOR_MODULE_AVAILABLE=()
    HC_COLLECTOR_MODULE_STARTED_AT=()
    HC_COLLECTOR_MODULE_FINISHED_AT=()
    HC_COLLECTOR_MODULE_STARTED_EPOCH=()
    HC_COLLECTOR_MODULE_FINISHED_EPOCH=()
    HC_COLLECTOR_MODULE_DURATION_SECONDS=()
    HC_COLLECTOR_MODULE_MESSAGES=()
    HC_COLLECTOR_MODULE_ERRORS=()

    HC_COLLECTOR_METRIC_ORDER=()
    HC_COLLECTOR_METRIC_MODULE=()
    HC_COLLECTOR_METRIC_SECTION=()
    HC_COLLECTOR_METRIC_KEY=()
    HC_COLLECTOR_METRIC_LABEL=()
    HC_COLLECTOR_METRIC_VALUE=()
    HC_COLLECTOR_METRIC_RAW_VALUE=()
    HC_COLLECTOR_METRIC_TYPE=()
    HC_COLLECTOR_METRIC_UNIT=()
    HC_COLLECTOR_METRIC_STATUS=()
    HC_COLLECTOR_METRIC_DESCRIPTION=()
    HC_COLLECTOR_METRIC_SOURCE=()
    HC_COLLECTOR_METRIC_TIMESTAMP=()

    HC_COLLECTOR_TABLE_ORDER=()
    HC_COLLECTOR_TABLE_MODULE=()
    HC_COLLECTOR_TABLE_SECTION=()
    HC_COLLECTOR_TABLE_KEY=()
    HC_COLLECTOR_TABLE_LABEL=()
    HC_COLLECTOR_TABLE_COLUMNS=()
    HC_COLLECTOR_TABLE_ROW_COUNT=()
    HC_COLLECTOR_TABLE_DESCRIPTION=()
    HC_COLLECTOR_TABLE_STATUS=()
    HC_COLLECTOR_TABLE_ROWS=()

    HC_COLLECTOR_ALERT_ORDER=()
    HC_COLLECTOR_ALERT_MODULE=()
    HC_COLLECTOR_ALERT_STATUS=()
    HC_COLLECTOR_ALERT_TITLE=()
    HC_COLLECTOR_ALERT_MESSAGE=()
    HC_COLLECTOR_ALERT_RECOMMENDATION=()
    HC_COLLECTOR_ALERT_TIMESTAMP=()

    HC_COLLECTOR_METRIC_SEQUENCE=0
    HC_COLLECTOR_TABLE_SEQUENCE=0
    HC_COLLECTOR_ALERT_SEQUENCE=0
}

collector_initialize_metadata() {
    HC_COLLECTOR_META["schema_version"]="$HC_COLLECTOR_SCHEMA_VERSION"
    HC_COLLECTOR_META["application_name"]="${PROGRAM_NAME:-vps-healthcheck}"
    HC_COLLECTOR_META["application_version"]="${PROGRAM_VERSION:-0.1.0}"
    HC_COLLECTOR_META["run_id"]="${RUN_ID:-unknown}"
    HC_COLLECTOR_META["run_mode"]="${RUN_MODE:-custom}"
    HC_COLLECTOR_META["started_at"]="$HC_COLLECTOR_STARTED_AT"
    HC_COLLECTOR_META["finished_at"]=""
    HC_COLLECTOR_META["duration_seconds"]="0"
    HC_COLLECTOR_META["overall_status"]="${HC_STATUS_UNKNOWN:-UNKNOWN}"
    HC_COLLECTOR_META["hostname"]="$(hostname -f 2>/dev/null || hostname 2>/dev/null || printf 'unknown')"
    HC_COLLECTOR_META["kernel"]="$(uname -r 2>/dev/null || printf 'unknown')"
    HC_COLLECTOR_META["architecture"]="$(uname -m 2>/dev/null || printf 'unknown')"
    HC_COLLECTOR_META["current_user"]="$(id -un 2>/dev/null || printf 'unknown')"
    HC_COLLECTOR_META["effective_uid"]="$(id -u 2>/dev/null || printf '0')"
    HC_COLLECTOR_META["project_root"]="${PROJECT_ROOT:-}"
    HC_COLLECTOR_META["report_directory"]="${CURRENT_REPORT_DIR:-}"
    HC_COLLECTOR_META["log_file"]="${CURRENT_LOG_FILE:-}"
}

collector_initialize() {
    collector_reset

    HC_COLLECTOR_STARTED_AT="$(collector_now_iso8601)"
    HC_COLLECTOR_STARTED_EPOCH="$(collector_now_epoch)"
    HC_COLLECTOR_INITIALIZED=1

    collector_initialize_metadata

    export HC_COLLECTOR_INITIALIZED
    export HC_COLLECTOR_STARTED_AT
    export HC_COLLECTOR_STARTED_EPOCH
    export HC_COLLECTOR_OVERALL_STATUS

    if declare -F logger_info >/dev/null 2>&1; then
        logger_info \
            "Coletor inicializado | schema=${HC_COLLECTOR_SCHEMA_VERSION}"
    fi
}

collector_is_initialized() {
    ((HC_COLLECTOR_INITIALIZED == 1))
}

collector_require_initialized() {
    if ! collector_is_initialized; then
        collector_initialize
    fi
}

# ---------------------------------------------------------------------------
# Metadados
# ---------------------------------------------------------------------------

collector_meta_set() {
    local key="${1:-}"
    local value="${2:-}"

    collector_require_initialized

    key="$(collector_sanitize_identifier "$key")"

    if [[ -z "$key" ]]; then
        return 1
    fi

    HC_COLLECTOR_META["$key"]="$value"
}

collector_meta_get() {
    local key="${1:-}"
    local default_value="${2:-}"

    key="$(collector_sanitize_identifier "$key")"

    if [[ -n "$key" && -n "${HC_COLLECTOR_META[$key]+x}" ]]; then
        printf '%s\n' "${HC_COLLECTOR_META[$key]}"
    else
        printf '%s\n' "$default_value"
        return 1
    fi
}

collector_meta_has() {
    local key="${1:-}"

    key="$(collector_sanitize_identifier "$key")"

    [[ -n "$key" && -n "${HC_COLLECTOR_META[$key]+x}" ]]
}

# ---------------------------------------------------------------------------
# Módulos
# ---------------------------------------------------------------------------

collector_module_register() {
    local module="${1:-}"
    local label="${2:-}"
    local available="${3:-true}"

    collector_require_initialized

    module="$(collector_sanitize_identifier "$module")"

    if [[ -z "$module" ]]; then
        return 1
    fi

    if [[ -z "$label" ]]; then
        if declare -F hc_module_label >/dev/null 2>&1; then
            label="$(hc_module_label "$module" 2>/dev/null || printf '%s' "$module")"
        else
            label="$module"
        fi
    fi

    if ! collector_array_contains "$module" "${HC_COLLECTOR_MODULE_ORDER[@]}"; then
        HC_COLLECTOR_MODULE_ORDER+=("$module")
    fi

    HC_COLLECTOR_MODULE_LABELS["$module"]="$label"
    HC_COLLECTOR_MODULE_AVAILABLE["$module"]="$available"

    if [[ -z "${HC_COLLECTOR_MODULE_STATUS[$module]+x}" ]]; then
        HC_COLLECTOR_MODULE_STATUS["$module"]="${HC_STATUS_UNKNOWN:-UNKNOWN}"
    fi

    if [[ -z "${HC_COLLECTOR_MODULE_MESSAGES[$module]+x}" ]]; then
        HC_COLLECTOR_MODULE_MESSAGES["$module"]=""
    fi

    if [[ -z "${HC_COLLECTOR_MODULE_ERRORS[$module]+x}" ]]; then
        HC_COLLECTOR_MODULE_ERRORS["$module"]=""
    fi
}

collector_module_exists() {
    local module="${1:-}"

    module="$(collector_sanitize_identifier "$module")"

    [[ -n "$module" && -n "${HC_COLLECTOR_MODULE_LABELS[$module]+x}" ]]
}

collector_module_start() {
    local module="${1:-}"
    local label="${2:-}"

    collector_module_register "$module" "$label" "true"

    module="$(collector_sanitize_identifier "$module")"

    HC_COLLECTOR_MODULE_STARTED_AT["$module"]="$(collector_now_iso8601)"
    HC_COLLECTOR_MODULE_STARTED_EPOCH["$module"]="$(collector_now_epoch)"
    HC_COLLECTOR_MODULE_FINISHED_AT["$module"]=""
    HC_COLLECTOR_MODULE_FINISHED_EPOCH["$module"]="0"
    HC_COLLECTOR_MODULE_DURATION_SECONDS["$module"]="0"
    HC_COLLECTOR_MODULE_STATUS["$module"]="${HC_STATUS_UNKNOWN:-UNKNOWN}"

    if declare -F logger_debug >/dev/null 2>&1; then
        logger_debug "Coleta iniciada para o módulo ${module}"
    fi
}

collector_module_finish() {
    local module="${1:-}"
    local status="${2:-${HC_STATUS_UNKNOWN:-UNKNOWN}}"
    local message="${3:-}"
    local started_epoch
    local finished_epoch
    local duration=0

    module="$(collector_sanitize_identifier "$module")"
    status="$(collector_normalize_status "$status" 2>/dev/null || printf '%s' "${HC_STATUS_UNKNOWN:-UNKNOWN}")"

    if ! collector_module_exists "$module"; then
        collector_module_register "$module" "$module" "true"
    fi

    finished_epoch="$(collector_now_epoch)"
    started_epoch="${HC_COLLECTOR_MODULE_STARTED_EPOCH[$module]:-0}"

    if [[ "$started_epoch" =~ ^[0-9]+$ ]] &&
        [[ "$finished_epoch" =~ ^[0-9]+$ ]] &&
        ((finished_epoch >= started_epoch)); then

        duration=$((finished_epoch - started_epoch))
    fi

    HC_COLLECTOR_MODULE_FINISHED_AT["$module"]="$(collector_now_iso8601)"
    HC_COLLECTOR_MODULE_FINISHED_EPOCH["$module"]="$finished_epoch"
    HC_COLLECTOR_MODULE_DURATION_SECONDS["$module"]="$duration"
    HC_COLLECTOR_MODULE_STATUS["$module"]="$status"
    HC_COLLECTOR_MODULE_MESSAGES["$module"]="$message"

    collector_recalculate_overall_status

    if declare -F logger_debug >/dev/null 2>&1; then
        logger_debug \
            "Coleta finalizada para ${module} | status=${status} | duração=${duration}s"
    fi
}

collector_module_skip() {
    local module="${1:-}"
    local reason="${2:-Módulo não disponível.}"
    local label="${3:-}"

    collector_module_register "$module" "$label" "false"

    module="$(collector_sanitize_identifier "$module")"

    HC_COLLECTOR_MODULE_STATUS["$module"]="${HC_STATUS_SKIPPED:-SKIPPED}"
    HC_COLLECTOR_MODULE_MESSAGES["$module"]="$reason"
    HC_COLLECTOR_MODULE_STARTED_AT["$module"]="$(collector_now_iso8601)"
    HC_COLLECTOR_MODULE_FINISHED_AT["$module"]="$(collector_now_iso8601)"
    HC_COLLECTOR_MODULE_STARTED_EPOCH["$module"]="$(collector_now_epoch)"
    HC_COLLECTOR_MODULE_FINISHED_EPOCH["$module"]="${HC_COLLECTOR_MODULE_STARTED_EPOCH[$module]}"
    HC_COLLECTOR_MODULE_DURATION_SECONDS["$module"]="0"

    collector_recalculate_overall_status
}

collector_module_error() {
    local module="${1:-}"
    local message="${2:-Erro não especificado.}"

    module="$(collector_sanitize_identifier "$module")"

    if ! collector_module_exists "$module"; then
        collector_module_register "$module" "$module" "true"
    fi

    HC_COLLECTOR_MODULE_STATUS["$module"]="${HC_STATUS_CRITICAL:-CRITICAL}"
    HC_COLLECTOR_MODULE_ERRORS["$module"]="$message"

    collector_alert_add \
        "$module" \
        "${HC_STATUS_CRITICAL:-CRITICAL}" \
        "Falha no módulo" \
        "$message" \
        "Consulte o log da execução."

    collector_recalculate_overall_status
}

collector_module_set_status() {
    local module="${1:-}"
    local status="${2:-${HC_STATUS_UNKNOWN:-UNKNOWN}}"

    module="$(collector_sanitize_identifier "$module")"
    status="$(collector_normalize_status "$status" 2>/dev/null || printf '%s' "${HC_STATUS_UNKNOWN:-UNKNOWN}")"

    if ! collector_module_exists "$module"; then
        collector_module_register "$module" "$module" "true"
    fi

    HC_COLLECTOR_MODULE_STATUS["$module"]="$status"

    collector_recalculate_overall_status
}

collector_module_get_status() {
    local module="${1:-}"

    module="$(collector_sanitize_identifier "$module")"

    printf '%s\n' \
        "${HC_COLLECTOR_MODULE_STATUS[$module]:-${HC_STATUS_UNKNOWN:-UNKNOWN}}"
}

# ---------------------------------------------------------------------------
# Métricas
# ---------------------------------------------------------------------------

collector_metric_identifier() {
    local module="${1:-}"
    local section="${2:-}"
    local key="${3:-}"

    module="$(collector_sanitize_identifier "$module")"
    section="$(collector_sanitize_identifier "$section")"
    key="$(collector_sanitize_identifier "$key")"

    printf '%s.%s.%s' "$module" "$section" "$key"
}

collector_metric_exists() {
    local module="${1:-}"
    local section="${2:-}"
    local key="${3:-}"
    local identifier

    identifier="$(collector_metric_identifier "$module" "$section" "$key")"

    [[ -n "${HC_COLLECTOR_METRIC_KEY[$identifier]+x}" ]]
}

collector_metric_set() {
    local module="${1:-}"
    local section="${2:-general}"
    local key="${3:-}"
    local label="${4:-}"
    local value="${5:-}"
    local raw_value="${6:-}"
    local data_type="${7:-string}"
    local unit="${8:-}"
    local status="${9:-${HC_STATUS_UNKNOWN:-UNKNOWN}}"
    local description="${10:-}"
    local source="${11:-}"
    local identifier

    collector_require_initialized

    module="$(collector_sanitize_identifier "$module")"
    section="$(collector_sanitize_identifier "$section")"
    key="$(collector_sanitize_identifier "$key")"
    status="$(collector_normalize_status "$status" 2>/dev/null || printf '%s' "${HC_STATUS_UNKNOWN:-UNKNOWN}")"

    if [[ -z "$module" || -z "$section" || -z "$key" ]]; then
        return 1
    fi

    if [[ -z "$label" ]]; then
        label="$key"
    fi

    if ! collector_module_exists "$module"; then
        collector_module_register "$module" "$module" "true"
    fi

    identifier="$(collector_metric_identifier "$module" "$section" "$key")"

    if [[ -z "${HC_COLLECTOR_METRIC_KEY[$identifier]+x}" ]]; then
        HC_COLLECTOR_METRIC_ORDER+=("$identifier")
        HC_COLLECTOR_METRIC_SEQUENCE=$((HC_COLLECTOR_METRIC_SEQUENCE + 1))
    fi

    HC_COLLECTOR_METRIC_MODULE["$identifier"]="$module"
    HC_COLLECTOR_METRIC_SECTION["$identifier"]="$section"
    HC_COLLECTOR_METRIC_KEY["$identifier"]="$key"
    HC_COLLECTOR_METRIC_LABEL["$identifier"]="$label"
    HC_COLLECTOR_METRIC_VALUE["$identifier"]="$value"
    HC_COLLECTOR_METRIC_RAW_VALUE["$identifier"]="$raw_value"
    HC_COLLECTOR_METRIC_TYPE["$identifier"]="$data_type"
    HC_COLLECTOR_METRIC_UNIT["$identifier"]="$unit"
    HC_COLLECTOR_METRIC_STATUS["$identifier"]="$status"
    HC_COLLECTOR_METRIC_DESCRIPTION["$identifier"]="$description"
    HC_COLLECTOR_METRIC_SOURCE["$identifier"]="$source"
    HC_COLLECTOR_METRIC_TIMESTAMP["$identifier"]="$(collector_now_iso8601)"

    collector_module_recalculate_status "$module"
    collector_recalculate_overall_status
}

collector_metric_get() {
    local module="${1:-}"
    local section="${2:-general}"
    local key="${3:-}"
    local field="${4:-value}"
    local identifier

    identifier="$(collector_metric_identifier "$module" "$section" "$key")"

    if [[ -z "${HC_COLLECTOR_METRIC_KEY[$identifier]+x}" ]]; then
        return 1
    fi

    case "$field" in
        module)
            printf '%s\n' "${HC_COLLECTOR_METRIC_MODULE[$identifier]}"
            ;;
        section)
            printf '%s\n' "${HC_COLLECTOR_METRIC_SECTION[$identifier]}"
            ;;
        key)
            printf '%s\n' "${HC_COLLECTOR_METRIC_KEY[$identifier]}"
            ;;
        label)
            printf '%s\n' "${HC_COLLECTOR_METRIC_LABEL[$identifier]}"
            ;;
        value)
            printf '%s\n' "${HC_COLLECTOR_METRIC_VALUE[$identifier]}"
            ;;
        raw_value)
            printf '%s\n' "${HC_COLLECTOR_METRIC_RAW_VALUE[$identifier]}"
            ;;
        type)
            printf '%s\n' "${HC_COLLECTOR_METRIC_TYPE[$identifier]}"
            ;;
        unit)
            printf '%s\n' "${HC_COLLECTOR_METRIC_UNIT[$identifier]}"
            ;;
        status)
            printf '%s\n' "${HC_COLLECTOR_METRIC_STATUS[$identifier]}"
            ;;
        description)
            printf '%s\n' "${HC_COLLECTOR_METRIC_DESCRIPTION[$identifier]}"
            ;;
        source)
            printf '%s\n' "${HC_COLLECTOR_METRIC_SOURCE[$identifier]}"
            ;;
        timestamp)
            printf '%s\n' "${HC_COLLECTOR_METRIC_TIMESTAMP[$identifier]}"
            ;;
        *)
            return 2
            ;;
    esac
}

collector_metric_delete() {
    local module="${1:-}"
    local section="${2:-general}"
    local key="${3:-}"
    local identifier
    local item
    local -a new_order=()

    identifier="$(collector_metric_identifier "$module" "$section" "$key")"

    if [[ -z "${HC_COLLECTOR_METRIC_KEY[$identifier]+x}" ]]; then
        return 1
    fi

    unset 'HC_COLLECTOR_METRIC_MODULE[$identifier]'
    unset 'HC_COLLECTOR_METRIC_SECTION[$identifier]'
    unset 'HC_COLLECTOR_METRIC_KEY[$identifier]'
    unset 'HC_COLLECTOR_METRIC_LABEL[$identifier]'
    unset 'HC_COLLECTOR_METRIC_VALUE[$identifier]'
    unset 'HC_COLLECTOR_METRIC_RAW_VALUE[$identifier]'
    unset 'HC_COLLECTOR_METRIC_TYPE[$identifier]'
    unset 'HC_COLLECTOR_METRIC_UNIT[$identifier]'
    unset 'HC_COLLECTOR_METRIC_STATUS[$identifier]'
    unset 'HC_COLLECTOR_METRIC_DESCRIPTION[$identifier]'
    unset 'HC_COLLECTOR_METRIC_SOURCE[$identifier]'
    unset 'HC_COLLECTOR_METRIC_TIMESTAMP[$identifier]'

    for item in "${HC_COLLECTOR_METRIC_ORDER[@]}"; do
        if [[ "$item" != "$identifier" ]]; then
            new_order+=("$item")
        fi
    done

    HC_COLLECTOR_METRIC_ORDER=("${new_order[@]}")

    collector_module_recalculate_status "$module"
    collector_recalculate_overall_status
}

collector_metric_count() {
    local module="${1:-}"
    local identifier
    local count=0

    if [[ -z "$module" ]]; then
        printf '%s\n' "${#HC_COLLECTOR_METRIC_ORDER[@]}"
        return 0
    fi

    module="$(collector_sanitize_identifier "$module")"

    for identifier in "${HC_COLLECTOR_METRIC_ORDER[@]}"; do
        if [[ "${HC_COLLECTOR_METRIC_MODULE[$identifier]}" == "$module" ]]; then
            count=$((count + 1))
        fi
    done

    printf '%s\n' "$count"
}

# ---------------------------------------------------------------------------
# Tabelas
# ---------------------------------------------------------------------------

collector_table_identifier() {
    local module="${1:-}"
    local section="${2:-}"
    local key="${3:-}"

    module="$(collector_sanitize_identifier "$module")"
    section="$(collector_sanitize_identifier "$section")"
    key="$(collector_sanitize_identifier "$key")"

    printf '%s.%s.%s' "$module" "$section" "$key"
}

collector_table_exists() {
    local module="${1:-}"
    local section="${2:-general}"
    local key="${3:-}"
    local identifier

    identifier="$(collector_table_identifier "$module" "$section" "$key")"

    [[ -n "${HC_COLLECTOR_TABLE_KEY[$identifier]+x}" ]]
}

collector_table_create() {
    local module="${1:-}"
    local section="${2:-general}"
    local key="${3:-}"
    local label="${4:-}"
    local columns="${5:-}"
    local description="${6:-}"
    local status="${7:-${HC_STATUS_UNKNOWN:-UNKNOWN}}"
    local identifier

    collector_require_initialized

    module="$(collector_sanitize_identifier "$module")"
    section="$(collector_sanitize_identifier "$section")"
    key="$(collector_sanitize_identifier "$key")"
    status="$(collector_normalize_status "$status" 2>/dev/null || printf '%s' "${HC_STATUS_UNKNOWN:-UNKNOWN}")"

    if [[ -z "$module" || -z "$section" || -z "$key" || -z "$columns" ]]; then
        return 1
    fi

    if [[ -z "$label" ]]; then
        label="$key"
    fi

    if ! collector_module_exists "$module"; then
        collector_module_register "$module" "$module" "true"
    fi

    identifier="$(collector_table_identifier "$module" "$section" "$key")"

    if [[ -z "${HC_COLLECTOR_TABLE_KEY[$identifier]+x}" ]]; then
        HC_COLLECTOR_TABLE_ORDER+=("$identifier")
        HC_COLLECTOR_TABLE_SEQUENCE=$((HC_COLLECTOR_TABLE_SEQUENCE + 1))
    fi

    HC_COLLECTOR_TABLE_MODULE["$identifier"]="$module"
    HC_COLLECTOR_TABLE_SECTION["$identifier"]="$section"
    HC_COLLECTOR_TABLE_KEY["$identifier"]="$key"
    HC_COLLECTOR_TABLE_LABEL["$identifier"]="$label"
    HC_COLLECTOR_TABLE_COLUMNS["$identifier"]="$columns"
    HC_COLLECTOR_TABLE_ROW_COUNT["$identifier"]="0"
    HC_COLLECTOR_TABLE_DESCRIPTION["$identifier"]="$description"
    HC_COLLECTOR_TABLE_STATUS["$identifier"]="$status"

    collector_module_recalculate_status "$module"
    collector_recalculate_overall_status
}

collector_table_add_row() {
    local module="${1:-}"
    local section="${2:-general}"
    local key="${3:-}"
    shift 3 || true

    local identifier
    local row_count
    local row_key
    local columns
    local column_count
    local value_count

    identifier="$(collector_table_identifier "$module" "$section" "$key")"

    if [[ -z "${HC_COLLECTOR_TABLE_KEY[$identifier]+x}" ]]; then
        return 1
    fi

    columns="${HC_COLLECTOR_TABLE_COLUMNS[$identifier]}"
    column_count="$(awk -F $'\t' '{print NF}' <<<"$columns")"
    value_count=$#

    if ((value_count != column_count)); then
        return 2
    fi

    row_count="${HC_COLLECTOR_TABLE_ROW_COUNT[$identifier]:-0}"
    row_count=$((row_count + 1))
    row_key="${identifier}.${row_count}"

    HC_COLLECTOR_TABLE_ROWS["$row_key"]="$(collector_join_fields $'\t' "$@")"
    HC_COLLECTOR_TABLE_ROW_COUNT["$identifier"]="$row_count"
}

collector_table_get_row() {
    local module="${1:-}"
    local section="${2:-general}"
    local key="${3:-}"
    local row_number="${4:-0}"
    local identifier
    local row_key

    if [[ ! "$row_number" =~ ^[0-9]+$ ]] || ((row_number < 1)); then
        return 2
    fi

    identifier="$(collector_table_identifier "$module" "$section" "$key")"
    row_key="${identifier}.${row_number}"

    if [[ -z "${HC_COLLECTOR_TABLE_ROWS[$row_key]+x}" ]]; then
        return 1
    fi

    printf '%s\n' "${HC_COLLECTOR_TABLE_ROWS[$row_key]}"
}

collector_table_set_status() {
    local module="${1:-}"
    local section="${2:-general}"
    local key="${3:-}"
    local status="${4:-${HC_STATUS_UNKNOWN:-UNKNOWN}}"
    local identifier

    identifier="$(collector_table_identifier "$module" "$section" "$key")"
    status="$(collector_normalize_status "$status" 2>/dev/null || printf '%s' "${HC_STATUS_UNKNOWN:-UNKNOWN}")"

    if [[ -z "${HC_COLLECTOR_TABLE_KEY[$identifier]+x}" ]]; then
        return 1
    fi

    HC_COLLECTOR_TABLE_STATUS["$identifier"]="$status"

    collector_module_recalculate_status \
        "${HC_COLLECTOR_TABLE_MODULE[$identifier]}"

    collector_recalculate_overall_status
}

collector_table_count() {
    local module="${1:-}"
    local identifier
    local count=0

    if [[ -z "$module" ]]; then
        printf '%s\n' "${#HC_COLLECTOR_TABLE_ORDER[@]}"
        return 0
    fi

    module="$(collector_sanitize_identifier "$module")"

    for identifier in "${HC_COLLECTOR_TABLE_ORDER[@]}"; do
        if [[ "${HC_COLLECTOR_TABLE_MODULE[$identifier]}" == "$module" ]]; then
            count=$((count + 1))
        fi
    done

    printf '%s\n' "$count"
}

# ---------------------------------------------------------------------------
# Alertas
# ---------------------------------------------------------------------------

collector_alert_add() {
    local module="${1:-general}"
    local status="${2:-${HC_STATUS_WARNING:-WARNING}}"
    local title="${3:-Alerta}"
    local message="${4:-}"
    local recommendation="${5:-}"
    local identifier

    collector_require_initialized

    module="$(collector_sanitize_identifier "$module")"
    status="$(collector_normalize_status "$status" 2>/dev/null || printf '%s' "${HC_STATUS_UNKNOWN:-UNKNOWN}")"

    HC_COLLECTOR_ALERT_SEQUENCE=$((HC_COLLECTOR_ALERT_SEQUENCE + 1))
    printf -v identifier 'alert_%06d' "$HC_COLLECTOR_ALERT_SEQUENCE"

    HC_COLLECTOR_ALERT_ORDER+=("$identifier")
    HC_COLLECTOR_ALERT_MODULE["$identifier"]="$module"
    HC_COLLECTOR_ALERT_STATUS["$identifier"]="$status"
    HC_COLLECTOR_ALERT_TITLE["$identifier"]="$title"
    HC_COLLECTOR_ALERT_MESSAGE["$identifier"]="$message"
    HC_COLLECTOR_ALERT_RECOMMENDATION["$identifier"]="$recommendation"
    HC_COLLECTOR_ALERT_TIMESTAMP["$identifier"]="$(collector_now_iso8601)"

    if [[ "$status" == "${HC_STATUS_WARNING:-WARNING}" ||
        "$status" == "${HC_STATUS_CRITICAL:-CRITICAL}" ]]; then

        if collector_module_exists "$module"; then
            HC_COLLECTOR_MODULE_STATUS["$module"]="$(
                collector_worst_status \
                    "${HC_COLLECTOR_MODULE_STATUS[$module]}" \
                    "$status"
            )"
        fi

        collector_recalculate_overall_status
    fi
}

collector_alert_count() {
    local status="${1:-}"
    local identifier
    local count=0

    if [[ -z "$status" ]]; then
        printf '%s\n' "${#HC_COLLECTOR_ALERT_ORDER[@]}"
        return 0
    fi

    status="$(collector_normalize_status "$status" 2>/dev/null || printf '%s' "${HC_STATUS_UNKNOWN:-UNKNOWN}")"

    for identifier in "${HC_COLLECTOR_ALERT_ORDER[@]}"; do
        if [[ "${HC_COLLECTOR_ALERT_STATUS[$identifier]}" == "$status" ]]; then
            count=$((count + 1))
        fi
    done

    printf '%s\n' "$count"
}

# ---------------------------------------------------------------------------
# Cálculo de status
# ---------------------------------------------------------------------------

collector_module_recalculate_status() {
    local module="${1:-}"
    local identifier
    local current_status="${HC_STATUS_OK:-OK}"
    local found=0

    module="$(collector_sanitize_identifier "$module")"

    if ! collector_module_exists "$module"; then
        return 1
    fi

    if [[ "${HC_COLLECTOR_MODULE_AVAILABLE[$module]:-true}" != "true" ]]; then
        HC_COLLECTOR_MODULE_STATUS["$module"]="${HC_STATUS_SKIPPED:-SKIPPED}"
        return 0
    fi

    for identifier in "${HC_COLLECTOR_METRIC_ORDER[@]}"; do
        if [[ "${HC_COLLECTOR_METRIC_MODULE[$identifier]}" != "$module" ]]; then
            continue
        fi

        current_status="$(
            collector_worst_status \
                "$current_status" \
                "${HC_COLLECTOR_METRIC_STATUS[$identifier]}"
        )"

        found=1
    done

    for identifier in "${HC_COLLECTOR_TABLE_ORDER[@]}"; do
        if [[ "${HC_COLLECTOR_TABLE_MODULE[$identifier]}" != "$module" ]]; then
            continue
        fi

        current_status="$(
            collector_worst_status \
                "$current_status" \
                "${HC_COLLECTOR_TABLE_STATUS[$identifier]}"
        )"

        found=1
    done

    for identifier in "${HC_COLLECTOR_ALERT_ORDER[@]}"; do
        if [[ "${HC_COLLECTOR_ALERT_MODULE[$identifier]}" != "$module" ]]; then
            continue
        fi

        current_status="$(
            collector_worst_status \
                "$current_status" \
                "${HC_COLLECTOR_ALERT_STATUS[$identifier]}"
        )"

        found=1
    done

    if ((found == 0)); then
        current_status="${HC_STATUS_UNKNOWN:-UNKNOWN}"
    fi

    HC_COLLECTOR_MODULE_STATUS["$module"]="$current_status"
}

collector_recalculate_overall_status() {
    local module
    local current_status="${HC_STATUS_OK:-OK}"
    local found=0

    for module in "${HC_COLLECTOR_MODULE_ORDER[@]}"; do
        current_status="$(
            collector_worst_status \
                "$current_status" \
                "${HC_COLLECTOR_MODULE_STATUS[$module]:-${HC_STATUS_UNKNOWN:-UNKNOWN}}"
        )"

        found=1
    done

    if ((found == 0)); then
        current_status="${HC_STATUS_UNKNOWN:-UNKNOWN}"
    fi

    HC_COLLECTOR_OVERALL_STATUS="$current_status"
    HC_COLLECTOR_META["overall_status"]="$current_status"

    export HC_COLLECTOR_OVERALL_STATUS
}

collector_status_count() {
    local status="${1:-}"
    local scope="${2:-modules}"
    local identifier
    local count=0

    status="$(collector_normalize_status "$status" 2>/dev/null || printf '%s' "${HC_STATUS_UNKNOWN:-UNKNOWN}")"

    case "$scope" in
        modules)
            for identifier in "${HC_COLLECTOR_MODULE_ORDER[@]}"; do
                if [[ "${HC_COLLECTOR_MODULE_STATUS[$identifier]}" == "$status" ]]; then
                    count=$((count + 1))
                fi
            done
            ;;
        metrics)
            for identifier in "${HC_COLLECTOR_METRIC_ORDER[@]}"; do
                if [[ "${HC_COLLECTOR_METRIC_STATUS[$identifier]}" == "$status" ]]; then
                    count=$((count + 1))
                fi
            done
            ;;
        tables)
            for identifier in "${HC_COLLECTOR_TABLE_ORDER[@]}"; do
                if [[ "${HC_COLLECTOR_TABLE_STATUS[$identifier]}" == "$status" ]]; then
                    count=$((count + 1))
                fi
            done
            ;;
        alerts)
            collector_alert_count "$status"
            return
            ;;
        *)
            return 2
            ;;
    esac

    printf '%s\n' "$count"
}

# ---------------------------------------------------------------------------
# Finalização
# ---------------------------------------------------------------------------

collector_finalize() {
    local now_epoch

    collector_require_initialized

    now_epoch="$(collector_now_epoch)"

    HC_COLLECTOR_FINISHED_AT="$(collector_now_iso8601)"
    HC_COLLECTOR_FINISHED_EPOCH="$now_epoch"

    if [[ "$HC_COLLECTOR_STARTED_EPOCH" =~ ^[0-9]+$ ]] &&
        [[ "$now_epoch" =~ ^[0-9]+$ ]] &&
        ((now_epoch >= HC_COLLECTOR_STARTED_EPOCH)); then

        HC_COLLECTOR_DURATION_SECONDS=$(( 
            now_epoch - HC_COLLECTOR_STARTED_EPOCH
        ))
    else
        HC_COLLECTOR_DURATION_SECONDS=0
    fi

    collector_recalculate_overall_status

    HC_COLLECTOR_META["finished_at"]="$HC_COLLECTOR_FINISHED_AT"
    HC_COLLECTOR_META["duration_seconds"]="$HC_COLLECTOR_DURATION_SECONDS"
    HC_COLLECTOR_META["overall_status"]="$HC_COLLECTOR_OVERALL_STATUS"
    HC_COLLECTOR_META["module_count"]="${#HC_COLLECTOR_MODULE_ORDER[@]}"
    HC_COLLECTOR_META["metric_count"]="${#HC_COLLECTOR_METRIC_ORDER[@]}"
    HC_COLLECTOR_META["table_count"]="${#HC_COLLECTOR_TABLE_ORDER[@]}"
    HC_COLLECTOR_META["alert_count"]="${#HC_COLLECTOR_ALERT_ORDER[@]}"

    export HC_COLLECTOR_FINISHED_AT
    export HC_COLLECTOR_FINISHED_EPOCH
    export HC_COLLECTOR_DURATION_SECONDS
    export HC_COLLECTOR_OVERALL_STATUS

    if declare -F logger_info >/dev/null 2>&1; then
        logger_info \
            "Coleta finalizada | status=${HC_COLLECTOR_OVERALL_STATUS} | módulos=${#HC_COLLECTOR_MODULE_ORDER[@]} | métricas=${#HC_COLLECTOR_METRIC_ORDER[@]} | alertas=${#HC_COLLECTOR_ALERT_ORDER[@]}"
    fi
}

# ---------------------------------------------------------------------------
# Exportação TSV
# ---------------------------------------------------------------------------

collector_export_metrics_tsv() {
    local destination="${1:-}"
    local identifier
    local temporary_file=""

    if [[ -n "$destination" ]]; then
        temporary_file="${destination}.tmp.$$"
        exec 3>"$temporary_file"
    else
        exec 3>&1
    fi

    collector_join_fields $'\t' \
        "module" \
        "section" \
        "key" \
        "label" \
        "value" \
        "raw_value" \
        "type" \
        "unit" \
        "status" \
        "description" \
        "source" \
        "timestamp" >&3

    printf '\n' >&3

    for identifier in "${HC_COLLECTOR_METRIC_ORDER[@]}"; do
        collector_join_fields $'\t' \
            "${HC_COLLECTOR_METRIC_MODULE[$identifier]}" \
            "${HC_COLLECTOR_METRIC_SECTION[$identifier]}" \
            "${HC_COLLECTOR_METRIC_KEY[$identifier]}" \
            "${HC_COLLECTOR_METRIC_LABEL[$identifier]}" \
            "${HC_COLLECTOR_METRIC_VALUE[$identifier]}" \
            "${HC_COLLECTOR_METRIC_RAW_VALUE[$identifier]}" \
            "${HC_COLLECTOR_METRIC_TYPE[$identifier]}" \
            "${HC_COLLECTOR_METRIC_UNIT[$identifier]}" \
            "${HC_COLLECTOR_METRIC_STATUS[$identifier]}" \
            "${HC_COLLECTOR_METRIC_DESCRIPTION[$identifier]}" \
            "${HC_COLLECTOR_METRIC_SOURCE[$identifier]}" \
            "${HC_COLLECTOR_METRIC_TIMESTAMP[$identifier]}" >&3

        printf '\n' >&3
    done

    exec 3>&-

    if [[ -n "$destination" ]]; then
        mv -f -- "$temporary_file" "$destination"
        chmod 0640 "$destination" 2>/dev/null || true
    fi
}

collector_export_modules_tsv() {
    local destination="${1:-}"
    local module
    local temporary_file=""

    if [[ -n "$destination" ]]; then
        temporary_file="${destination}.tmp.$$"
        exec 3>"$temporary_file"
    else
        exec 3>&1
    fi

    collector_join_fields $'\t' \
        "module" \
        "label" \
        "status" \
        "available" \
        "started_at" \
        "finished_at" \
        "duration_seconds" \
        "message" \
        "error" >&3

    printf '\n' >&3

    for module in "${HC_COLLECTOR_MODULE_ORDER[@]}"; do
        collector_join_fields $'\t' \
            "$module" \
            "${HC_COLLECTOR_MODULE_LABELS[$module]}" \
            "${HC_COLLECTOR_MODULE_STATUS[$module]}" \
            "${HC_COLLECTOR_MODULE_AVAILABLE[$module]}" \
            "${HC_COLLECTOR_MODULE_STARTED_AT[$module]:-}" \
            "${HC_COLLECTOR_MODULE_FINISHED_AT[$module]:-}" \
            "${HC_COLLECTOR_MODULE_DURATION_SECONDS[$module]:-0}" \
            "${HC_COLLECTOR_MODULE_MESSAGES[$module]:-}" \
            "${HC_COLLECTOR_MODULE_ERRORS[$module]:-}" >&3

        printf '\n' >&3
    done

    exec 3>&-

    if [[ -n "$destination" ]]; then
        mv -f -- "$temporary_file" "$destination"
        chmod 0640 "$destination" 2>/dev/null || true
    fi
}

collector_export_alerts_tsv() {
    local destination="${1:-}"
    local identifier
    local temporary_file=""

    if [[ -n "$destination" ]]; then
        temporary_file="${destination}.tmp.$$"
        exec 3>"$temporary_file"
    else
        exec 3>&1
    fi

    collector_join_fields $'\t' \
        "id" \
        "module" \
        "status" \
        "title" \
        "message" \
        "recommendation" \
        "timestamp" >&3

    printf '\n' >&3

    for identifier in "${HC_COLLECTOR_ALERT_ORDER[@]}"; do
        collector_join_fields $'\t' \
            "$identifier" \
            "${HC_COLLECTOR_ALERT_MODULE[$identifier]}" \
            "${HC_COLLECTOR_ALERT_STATUS[$identifier]}" \
            "${HC_COLLECTOR_ALERT_TITLE[$identifier]}" \
            "${HC_COLLECTOR_ALERT_MESSAGE[$identifier]}" \
            "${HC_COLLECTOR_ALERT_RECOMMENDATION[$identifier]}" \
            "${HC_COLLECTOR_ALERT_TIMESTAMP[$identifier]}" >&3

        printf '\n' >&3
    done

    exec 3>&-

    if [[ -n "$destination" ]]; then
        mv -f -- "$temporary_file" "$destination"
        chmod 0640 "$destination" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------

collector_print_summary() {
    local module

    printf '\nResumo da coleta\n'
    printf '  Status geral:   %s\n' "$HC_COLLECTOR_OVERALL_STATUS"
    printf '  Módulos:        %s\n' "${#HC_COLLECTOR_MODULE_ORDER[@]}"
    printf '  Métricas:       %s\n' "${#HC_COLLECTOR_METRIC_ORDER[@]}"
    printf '  Tabelas:        %s\n' "${#HC_COLLECTOR_TABLE_ORDER[@]}"
    printf '  Alertas:        %s\n' "${#HC_COLLECTOR_ALERT_ORDER[@]}"
    printf '  Duração:        %ss\n' "$HC_COLLECTOR_DURATION_SECONDS"

    if ((${#HC_COLLECTOR_MODULE_ORDER[@]} > 0)); then
        printf '\n  Estado por módulo\n'

        for module in "${HC_COLLECTOR_MODULE_ORDER[@]}"; do
            printf '    %-16s %s\n' \
                "${HC_COLLECTOR_MODULE_LABELS[$module]}:" \
                "${HC_COLLECTOR_MODULE_STATUS[$module]}"
        done
    fi
}

# ---------------------------------------------------------------------------
# Validação interna
# ---------------------------------------------------------------------------

collector_validate() {
    local failure=0
    local metric_value
    local table_row
    local status

    collector_initialize

    collector_meta_set "test_key" "test_value"

    if [[ "$(collector_meta_get "test_key")" != "test_value" ]]; then
        printf 'Falha em collector_meta_set ou collector_meta_get.\n' >&2
        failure=1
    fi

    collector_module_start "system" "Sistema"

    collector_metric_set \
        "system" \
        "general" \
        "hostname" \
        "Nome do host" \
        "venom-vps" \
        "venom-vps" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Nome do servidor." \
        "hostname"

    collector_metric_set \
        "system" \
        "resources" \
        "disk_usage" \
        "Uso de disco" \
        "82%" \
        "82" \
        "percentage" \
        "%" \
        "${HC_STATUS_WARNING:-WARNING}" \
        "Percentual de uso do disco." \
        "df"

    metric_value="$(
        collector_metric_get \
            "system" \
            "general" \
            "hostname" \
            "value"
    )"

    if [[ "$metric_value" != "venom-vps" ]]; then
        printf 'Falha em collector_metric_get.\n' >&2
        failure=1
    fi

    if [[ "$(collector_metric_count "system")" != "2" ]]; then
        printf 'Falha em collector_metric_count.\n' >&2
        failure=1
    fi

    collector_table_create \
        "system" \
        "processes" \
        "top_processes" \
        "Principais processos" \
        $'PID\tNome\tCPU' \
        "Processos com maior uso de CPU." \
        "${HC_STATUS_OK:-OK}"

    collector_table_add_row \
        "system" \
        "processes" \
        "top_processes" \
        "123" \
        "python3" \
        "12.5"

    table_row="$(
        collector_table_get_row \
            "system" \
            "processes" \
            "top_processes" \
            "1"
    )"

    if [[ "$table_row" != $'123\tpython3\t12.5' ]]; then
        printf 'Falha em collector_table_add_row.\n' >&2
        failure=1
    fi

    collector_alert_add \
        "system" \
        "${HC_STATUS_WARNING:-WARNING}" \
        "Disco elevado" \
        "O disco está com 82% de uso." \
        "Revisar arquivos grandes."

    collector_module_finish \
        "system" \
        "${HC_STATUS_WARNING:-WARNING}" \
        "Coleta concluída."

    collector_finalize

    status="$(collector_module_get_status "system")"

    if [[ "$status" != "${HC_STATUS_WARNING:-WARNING}" ]]; then
        printf 'Falha no cálculo de status do módulo.\n' >&2
        failure=1
    fi

    if [[ "$HC_COLLECTOR_OVERALL_STATUS" != "${HC_STATUS_WARNING:-WARNING}" ]]; then
        printf 'Falha no cálculo de status geral.\n' >&2
        failure=1
    fi

    if [[ "$(collector_alert_count "${HC_STATUS_WARNING:-WARNING}")" != "1" ]]; then
        printf 'Falha em collector_alert_count.\n' >&2
        failure=1
    fi

    if [[ "$(collector_table_count "system")" != "1" ]]; then
        printf 'Falha em collector_table_count.\n' >&2
        failure=1
    fi

    return "$failure"
}
