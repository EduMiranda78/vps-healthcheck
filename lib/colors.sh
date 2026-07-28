#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_COLORS_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_COLORS_LOADED=1

# ---------------------------------------------------------------------------
# Detecção de suporte a cores
# ---------------------------------------------------------------------------

HC_COLOR_ENABLED=1

if [[ -n "${NO_COLOR:-}" ]]; then
    HC_COLOR_ENABLED=0
fi

if [[ "${TERM:-}" == "dumb" ]]; then
    HC_COLOR_ENABLED=0
fi

if [[ ! -t 1 ]]; then
    HC_COLOR_ENABLED=0
fi

if [[ "${NO_COLOR:-0}" == "1" ]]; then
    HC_COLOR_ENABLED=0
fi

# ---------------------------------------------------------------------------
# Sequências ANSI
# ---------------------------------------------------------------------------

readonly HC_ANSI_RESET=$'\033[0m'
readonly HC_ANSI_BOLD=$'\033[1m'
readonly HC_ANSI_DIM=$'\033[2m'
readonly HC_ANSI_UNDERLINE=$'\033[4m'
readonly HC_ANSI_BLINK=$'\033[5m'
readonly HC_ANSI_REVERSE=$'\033[7m'
readonly HC_ANSI_HIDDEN=$'\033[8m'

readonly HC_ANSI_BLACK=$'\033[30m'
readonly HC_ANSI_RED=$'\033[31m'
readonly HC_ANSI_GREEN=$'\033[32m'
readonly HC_ANSI_YELLOW=$'\033[33m'
readonly HC_ANSI_BLUE=$'\033[34m'
readonly HC_ANSI_MAGENTA=$'\033[35m'
readonly HC_ANSI_CYAN=$'\033[36m'
readonly HC_ANSI_WHITE=$'\033[37m'

readonly HC_ANSI_BRIGHT_BLACK=$'\033[90m'
readonly HC_ANSI_BRIGHT_RED=$'\033[91m'
readonly HC_ANSI_BRIGHT_GREEN=$'\033[92m'
readonly HC_ANSI_BRIGHT_YELLOW=$'\033[93m'
readonly HC_ANSI_BRIGHT_BLUE=$'\033[94m'
readonly HC_ANSI_BRIGHT_MAGENTA=$'\033[95m'
readonly HC_ANSI_BRIGHT_CYAN=$'\033[96m'
readonly HC_ANSI_BRIGHT_WHITE=$'\033[97m'

readonly HC_ANSI_BG_BLACK=$'\033[40m'
readonly HC_ANSI_BG_RED=$'\033[41m'
readonly HC_ANSI_BG_GREEN=$'\033[42m'
readonly HC_ANSI_BG_YELLOW=$'\033[43m'
readonly HC_ANSI_BG_BLUE=$'\033[44m'
readonly HC_ANSI_BG_MAGENTA=$'\033[45m'
readonly HC_ANSI_BG_CYAN=$'\033[46m'
readonly HC_ANSI_BG_WHITE=$'\033[47m'

readonly HC_ANSI_BG_BRIGHT_BLACK=$'\033[100m'
readonly HC_ANSI_BG_BRIGHT_RED=$'\033[101m'
readonly HC_ANSI_BG_BRIGHT_GREEN=$'\033[102m'
readonly HC_ANSI_BG_BRIGHT_YELLOW=$'\033[103m'
readonly HC_ANSI_BG_BRIGHT_BLUE=$'\033[104m'
readonly HC_ANSI_BG_BRIGHT_MAGENTA=$'\033[105m'
readonly HC_ANSI_BG_BRIGHT_CYAN=$'\033[106m'
readonly HC_ANSI_BG_BRIGHT_WHITE=$'\033[107m'

# ---------------------------------------------------------------------------
# Cores semânticas
# ---------------------------------------------------------------------------

HC_COLOR_RESET=""
HC_COLOR_TITLE=""
HC_COLOR_SUBTITLE=""
HC_COLOR_SECTION=""
HC_COLOR_LABEL=""
HC_COLOR_VALUE=""
HC_COLOR_MUTED=""
HC_COLOR_INFO=""
HC_COLOR_NOTICE=""
HC_COLOR_SUCCESS=""
HC_COLOR_WARNING=""
HC_COLOR_ERROR=""
HC_COLOR_CRITICAL=""
HC_COLOR_BORDER=""
HC_COLOR_ACCENT=""

HC_COLOR_STATUS_OK=""
HC_COLOR_STATUS_WARNING=""
HC_COLOR_STATUS_CRITICAL=""
HC_COLOR_STATUS_UNKNOWN=""
HC_COLOR_STATUS_SKIPPED=""

# ---------------------------------------------------------------------------
# Símbolos
# ---------------------------------------------------------------------------

readonly HC_SYMBOL_OK="●"
readonly HC_SYMBOL_WARNING="●"
readonly HC_SYMBOL_CRITICAL="●"
readonly HC_SYMBOL_UNKNOWN="●"
readonly HC_SYMBOL_SKIPPED="●"

readonly HC_SYMBOL_CHECK="✓"
readonly HC_SYMBOL_CROSS="✗"
readonly HC_SYMBOL_ARROW=">"
readonly HC_SYMBOL_BULLET="•"
readonly HC_SYMBOL_INFO="i"
readonly HC_SYMBOL_WARNING_TEXT="!"
readonly HC_SYMBOL_CRITICAL_TEXT="x"

readonly HC_ASCII_SYMBOL_OK="[OK]"
readonly HC_ASCII_SYMBOL_WARNING="[AVISO]"
readonly HC_ASCII_SYMBOL_CRITICAL="[CRÍTICO]"
readonly HC_ASCII_SYMBOL_UNKNOWN="[N/D]"
readonly HC_ASCII_SYMBOL_SKIPPED="[IGNORADO]"

# ---------------------------------------------------------------------------
# Inicialização
# ---------------------------------------------------------------------------

colors_initialize() {
    if ((HC_COLOR_ENABLED == 0)); then
        colors_disable
        return 0
    fi

    HC_COLOR_RESET="$HC_ANSI_RESET"

    HC_COLOR_TITLE="${HC_ANSI_BOLD}${HC_ANSI_BRIGHT_CYAN}"
    HC_COLOR_SUBTITLE="${HC_ANSI_BOLD}${HC_ANSI_CYAN}"
    HC_COLOR_SECTION="${HC_ANSI_BOLD}${HC_ANSI_BRIGHT_BLUE}"
    HC_COLOR_LABEL="${HC_ANSI_BOLD}${HC_ANSI_WHITE}"
    HC_COLOR_VALUE="${HC_ANSI_BRIGHT_WHITE}"
    HC_COLOR_MUTED="${HC_ANSI_DIM}${HC_ANSI_WHITE}"

    HC_COLOR_INFO="${HC_ANSI_CYAN}"
    HC_COLOR_NOTICE="${HC_ANSI_BRIGHT_BLUE}"
    HC_COLOR_SUCCESS="${HC_ANSI_GREEN}"
    HC_COLOR_WARNING="${HC_ANSI_YELLOW}"
    HC_COLOR_ERROR="${HC_ANSI_RED}"
    HC_COLOR_CRITICAL="${HC_ANSI_BOLD}${HC_ANSI_BRIGHT_RED}"

    HC_COLOR_BORDER="${HC_ANSI_BRIGHT_BLACK}"
    HC_COLOR_ACCENT="${HC_ANSI_BRIGHT_MAGENTA}"

    HC_COLOR_STATUS_OK="${HC_ANSI_BOLD}${HC_ANSI_GREEN}"
    HC_COLOR_STATUS_WARNING="${HC_ANSI_BOLD}${HC_ANSI_YELLOW}"
    HC_COLOR_STATUS_CRITICAL="${HC_ANSI_BOLD}${HC_ANSI_BRIGHT_RED}"
    HC_COLOR_STATUS_UNKNOWN="${HC_ANSI_BOLD}${HC_ANSI_BRIGHT_BLACK}"
    HC_COLOR_STATUS_SKIPPED="${HC_ANSI_DIM}${HC_ANSI_WHITE}"

    export HC_COLOR_RESET
    export HC_COLOR_TITLE
    export HC_COLOR_SUBTITLE
    export HC_COLOR_SECTION
    export HC_COLOR_LABEL
    export HC_COLOR_VALUE
    export HC_COLOR_MUTED
    export HC_COLOR_INFO
    export HC_COLOR_NOTICE
    export HC_COLOR_SUCCESS
    export HC_COLOR_WARNING
    export HC_COLOR_ERROR
    export HC_COLOR_CRITICAL
    export HC_COLOR_BORDER
    export HC_COLOR_ACCENT
    export HC_COLOR_STATUS_OK
    export HC_COLOR_STATUS_WARNING
    export HC_COLOR_STATUS_CRITICAL
    export HC_COLOR_STATUS_UNKNOWN
    export HC_COLOR_STATUS_SKIPPED
}

colors_disable() {
    HC_COLOR_ENABLED=0

    HC_COLOR_RESET=""
    HC_COLOR_TITLE=""
    HC_COLOR_SUBTITLE=""
    HC_COLOR_SECTION=""
    HC_COLOR_LABEL=""
    HC_COLOR_VALUE=""
    HC_COLOR_MUTED=""
    HC_COLOR_INFO=""
    HC_COLOR_NOTICE=""
    HC_COLOR_SUCCESS=""
    HC_COLOR_WARNING=""
    HC_COLOR_ERROR=""
    HC_COLOR_CRITICAL=""
    HC_COLOR_BORDER=""
    HC_COLOR_ACCENT=""

    HC_COLOR_STATUS_OK=""
    HC_COLOR_STATUS_WARNING=""
    HC_COLOR_STATUS_CRITICAL=""
    HC_COLOR_STATUS_UNKNOWN=""
    HC_COLOR_STATUS_SKIPPED=""

    export HC_COLOR_ENABLED
    export HC_COLOR_RESET
    export HC_COLOR_TITLE
    export HC_COLOR_SUBTITLE
    export HC_COLOR_SECTION
    export HC_COLOR_LABEL
    export HC_COLOR_VALUE
    export HC_COLOR_MUTED
    export HC_COLOR_INFO
    export HC_COLOR_NOTICE
    export HC_COLOR_SUCCESS
    export HC_COLOR_WARNING
    export HC_COLOR_ERROR
    export HC_COLOR_CRITICAL
    export HC_COLOR_BORDER
    export HC_COLOR_ACCENT
    export HC_COLOR_STATUS_OK
    export HC_COLOR_STATUS_WARNING
    export HC_COLOR_STATUS_CRITICAL
    export HC_COLOR_STATUS_UNKNOWN
    export HC_COLOR_STATUS_SKIPPED
}

colors_enable() {
    HC_COLOR_ENABLED=1
    export HC_COLOR_ENABLED
    colors_initialize
}

colors_are_enabled() {
    ((HC_COLOR_ENABLED == 1))
}

colors_support_unicode() {
    local locale_value

    locale_value="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"

    case "$locale_value" in
        *UTF-8* | *utf8* | *UTF8*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

colors_terminal_width() {
    local width=""

    if command -v tput >/dev/null 2>&1; then
        width="$(tput cols 2>/dev/null || true)"
    fi

    if [[ ! "$width" =~ ^[0-9]+$ ]] || ((width < 20)); then
        width="${COLUMNS:-80}"
    fi

    if [[ ! "$width" =~ ^[0-9]+$ ]] || ((width < 20)); then
        width=80
    fi

    printf '%s\n' "$width"
}

# ---------------------------------------------------------------------------
# Seleção de cores por estado
# ---------------------------------------------------------------------------

colors_status_color() {
    local status="${1:-UNKNOWN}"

    case "$status" in
        "${HC_STATUS_OK:-OK}")
            printf '%s' "$HC_COLOR_STATUS_OK"
            ;;
        "${HC_STATUS_WARNING:-WARNING}")
            printf '%s' "$HC_COLOR_STATUS_WARNING"
            ;;
        "${HC_STATUS_CRITICAL:-CRITICAL}")
            printf '%s' "$HC_COLOR_STATUS_CRITICAL"
            ;;
        "${HC_STATUS_SKIPPED:-SKIPPED}")
            printf '%s' "$HC_COLOR_STATUS_SKIPPED"
            ;;
        "${HC_STATUS_UNKNOWN:-UNKNOWN}" | *)
            printf '%s' "$HC_COLOR_STATUS_UNKNOWN"
            ;;
    esac
}

colors_status_symbol() {
    local status="${1:-UNKNOWN}"

    if ! colors_support_unicode; then
        case "$status" in
            "${HC_STATUS_OK:-OK}")
                printf '%s' "$HC_ASCII_SYMBOL_OK"
                ;;
            "${HC_STATUS_WARNING:-WARNING}")
                printf '%s' "$HC_ASCII_SYMBOL_WARNING"
                ;;
            "${HC_STATUS_CRITICAL:-CRITICAL}")
                printf '%s' "$HC_ASCII_SYMBOL_CRITICAL"
                ;;
            "${HC_STATUS_SKIPPED:-SKIPPED}")
                printf '%s' "$HC_ASCII_SYMBOL_SKIPPED"
                ;;
            "${HC_STATUS_UNKNOWN:-UNKNOWN}" | *)
                printf '%s' "$HC_ASCII_SYMBOL_UNKNOWN"
                ;;
        esac

        return 0
    fi

    case "$status" in
        "${HC_STATUS_OK:-OK}")
            printf '%s' "$HC_SYMBOL_OK"
            ;;
        "${HC_STATUS_WARNING:-WARNING}")
            printf '%s' "$HC_SYMBOL_WARNING"
            ;;
        "${HC_STATUS_CRITICAL:-CRITICAL}")
            printf '%s' "$HC_SYMBOL_CRITICAL"
            ;;
        "${HC_STATUS_SKIPPED:-SKIPPED}")
            printf '%s' "$HC_SYMBOL_SKIPPED"
            ;;
        "${HC_STATUS_UNKNOWN:-UNKNOWN}" | *)
            printf '%s' "$HC_SYMBOL_UNKNOWN"
            ;;
    esac
}

colors_status_text() {
    local status="${1:-UNKNOWN}"
    local label="$status"
    local color

    if declare -F hc_status_label >/dev/null 2>&1; then
        label="$(hc_status_label "$status" 2>/dev/null || printf '%s' "$status")"
    fi

    color="$(colors_status_color "$status")"

    printf '%s%s%s %s' \
        "$color" \
        "$(colors_status_symbol "$status")" \
        "$HC_COLOR_RESET" \
        "$label"
}

# ---------------------------------------------------------------------------
# Impressão formatada
# ---------------------------------------------------------------------------

colorize() {
    local color="${1:-}"
    shift || true

    printf '%s%s%s' "$color" "$*" "$HC_COLOR_RESET"
}

ui_print() {
    local color="${1:-}"
    shift || true

    printf '%s%s%s' "$color" "$*" "$HC_COLOR_RESET"
}

ui_print_line() {
    local color="${1:-}"
    shift || true

    printf '%s%s%s\n' "$color" "$*" "$HC_COLOR_RESET"
}

ui_print_title() {
    local text="${1:-}"

    printf '%s%s%s\n' \
        "$HC_COLOR_TITLE" \
        "$text" \
        "$HC_COLOR_RESET"
}

ui_print_subtitle() {
    local text="${1:-}"

    printf '%s%s%s\n' \
        "$HC_COLOR_SUBTITLE" \
        "$text" \
        "$HC_COLOR_RESET"
}

ui_print_section() {
    local text="${1:-}"

    printf '\n%s%s%s\n' \
        "$HC_COLOR_SECTION" \
        "$text" \
        "$HC_COLOR_RESET"
}

ui_print_label_value() {
    local label="${1:-}"
    local value="${2:-}"
    local label_width="${3:-24}"

    if [[ ! "$label_width" =~ ^[0-9]+$ ]]; then
        label_width=24
    fi

    printf '  %s%-*s%s %s%s%s\n' \
        "$HC_COLOR_LABEL" \
        "$label_width" \
        "${label}:" \
        "$HC_COLOR_RESET" \
        "$HC_COLOR_VALUE" \
        "$value" \
        "$HC_COLOR_RESET"
}

ui_print_status_line() {
    local status="${1:-${HC_STATUS_UNKNOWN:-UNKNOWN}}"
    local label="${2:-}"
    local value="${3:-}"
    local label_width="${4:-24}"
    local color
    local symbol

    if [[ ! "$label_width" =~ ^[0-9]+$ ]]; then
        label_width=24
    fi

    color="$(colors_status_color "$status")"
    symbol="$(colors_status_symbol "$status")"

    printf '  %s%s%s %-*s %s%s%s\n' \
        "$color" \
        "$symbol" \
        "$HC_COLOR_RESET" \
        "$label_width" \
        "${label}:" \
        "$color" \
        "$value" \
        "$HC_COLOR_RESET"
}

ui_print_success() {
    local text="${1:-}"

    printf '%s%s%s %s\n' \
        "$HC_COLOR_SUCCESS" \
        "$HC_SYMBOL_CHECK" \
        "$HC_COLOR_RESET" \
        "$text"
}

ui_print_warning() {
    local text="${1:-}"

    printf '%s%s%s %s\n' \
        "$HC_COLOR_WARNING" \
        "$HC_SYMBOL_WARNING_TEXT" \
        "$HC_COLOR_RESET" \
        "$text"
}

ui_print_error() {
    local text="${1:-}"

    printf '%s%s%s %s\n' \
        "$HC_COLOR_ERROR" \
        "$HC_SYMBOL_CROSS" \
        "$HC_COLOR_RESET" \
        "$text" >&2
}

ui_print_info() {
    local text="${1:-}"

    printf '%s%s%s %s\n' \
        "$HC_COLOR_INFO" \
        "$HC_SYMBOL_INFO" \
        "$HC_COLOR_RESET" \
        "$text"
}

ui_print_muted() {
    local text="${1:-}"

    printf '%s%s%s\n' \
        "$HC_COLOR_MUTED" \
        "$text" \
        "$HC_COLOR_RESET"
}

# ---------------------------------------------------------------------------
# Bordas e separadores
# ---------------------------------------------------------------------------

ui_repeat_character() {
    local character="${1:--}"
    local count="${2:-1}"
    local output=""

    if [[ ! "$count" =~ ^[0-9]+$ ]]; then
        count=1
    fi

    if ((count <= 0)); then
        return 0
    fi

    printf -v output '%*s' "$count" ''
    output="${output// /$character}"

    printf '%s' "$output"
}

ui_print_separator() {
    local character="${1:--}"
    local width="${2:-}"

    if [[ -z "$width" ]]; then
        width="$(colors_terminal_width)"
    fi

    if [[ ! "$width" =~ ^[0-9]+$ ]] || ((width < 1)); then
        width=80
    fi

    printf '%s' "$HC_COLOR_BORDER"
    ui_repeat_character "$character" "$width"
    printf '%s\n' "$HC_COLOR_RESET"
}

ui_print_box_title() {
    local text="${1:-}"
    local width="${2:-}"
    local available_width
    local text_length
    local left_count
    local right_count

    if [[ -z "$width" ]]; then
        width="$(colors_terminal_width)"
    fi

    if [[ ! "$width" =~ ^[0-9]+$ ]] || ((width < 20)); then
        width=80
    fi

    text_length=${#text}
    available_width=$((width - text_length - 2))

    if ((available_width < 2)); then
        ui_print_title "$text"
        return 0
    fi

    left_count=$((available_width / 2))
    right_count=$((available_width - left_count))

    printf '%s' "$HC_COLOR_BORDER"
    ui_repeat_character "-" "$left_count"
    printf '%s %s%s%s ' \
        "$HC_COLOR_RESET" \
        "$HC_COLOR_TITLE" \
        "$text" \
        "$HC_COLOR_RESET"
    printf '%s' "$HC_COLOR_BORDER"
    ui_repeat_character "-" "$right_count"
    printf '%s\n' "$HC_COLOR_RESET"
}

ui_print_header() {
    local application_name="${1:-vps-healthcheck}"
    local application_version="${2:-}"
    local run_id="${3:-}"
    local title

    title="$application_name"

    if [[ -n "$application_version" ]]; then
        title+=" ${application_version}"
    fi

    printf '\n'
    ui_print_separator "="
    ui_print_box_title "$title"

    if [[ -n "$run_id" ]]; then
        printf '%sExecução:%s %s\n' \
            "$HC_COLOR_LABEL" \
            "$HC_COLOR_RESET" \
            "$run_id"
    fi

    ui_print_separator "="
    printf '\n'
}

# ---------------------------------------------------------------------------
# Barras de progresso
# ---------------------------------------------------------------------------

ui_progress_bar() {
    local percentage="${1:-0}"
    local width="${2:-30}"
    local status="${3:-${HC_STATUS_UNKNOWN:-UNKNOWN}}"
    local filled
    local empty
    local color

    if [[ ! "$percentage" =~ ^[0-9]+$ ]]; then
        percentage=0
    fi

    if ((percentage < 0)); then
        percentage=0
    elif ((percentage > 100)); then
        percentage=100
    fi

    if [[ ! "$width" =~ ^[0-9]+$ ]] || ((width < 5)); then
        width=30
    fi

    filled=$((percentage * width / 100))
    empty=$((width - filled))
    color="$(colors_status_color "$status")"

    printf '['
    printf '%s' "$color"
    ui_repeat_character "#" "$filled"
    printf '%s' "$HC_COLOR_RESET"
    ui_repeat_character "." "$empty"
    printf '] %3d%%' "$percentage"
}

# ---------------------------------------------------------------------------
# Remoção de ANSI
# ---------------------------------------------------------------------------

colors_strip_ansi() {
    local text="${1:-}"

    printf '%s' "$text" | sed -E \
        $'s/\x1B\\[[0-9;]*[[:alpha:]]//g'
}

# ---------------------------------------------------------------------------
# Validação
# ---------------------------------------------------------------------------

colors_validate() {
    local failure=0
    local width
    local stripped

    width="$(colors_terminal_width)"

    if [[ ! "$width" =~ ^[0-9]+$ ]]; then
        printf 'Falha ao detectar a largura do terminal.\n' >&2
        failure=1
    fi

    stripped="$(
        colors_strip_ansi \
            "${HC_ANSI_RED}teste${HC_ANSI_RESET}"
    )"

    if [[ "$stripped" != "teste" ]]; then
        printf 'Falha ao remover sequências ANSI.\n' >&2
        failure=1
    fi

    return "$failure"
}

colors_initialize
