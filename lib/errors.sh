#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_ERRORS_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_ERRORS_LOADED=1

# ---------------------------------------------------------------------------
# Códigos de saída
# ---------------------------------------------------------------------------

if ! declare -p EXIT_SUCCESS >/dev/null 2>&1; then
    readonly EXIT_SUCCESS=0
fi

if ! declare -p EXIT_GENERAL_ERROR >/dev/null 2>&1; then
    readonly EXIT_GENERAL_ERROR=1
fi

if ! declare -p EXIT_INVALID_ARGUMENT >/dev/null 2>&1; then
    readonly EXIT_INVALID_ARGUMENT=2
fi

if ! declare -p EXIT_DEPENDENCY_ERROR >/dev/null 2>&1; then
    readonly EXIT_DEPENDENCY_ERROR=3
fi

if ! declare -p EXIT_PERMISSION_ERROR >/dev/null 2>&1; then
    readonly EXIT_PERMISSION_ERROR=4
fi

if ! declare -p EXIT_MODULE_ERROR >/dev/null 2>&1; then
    readonly EXIT_MODULE_ERROR=5
fi

if ! declare -p EXIT_REPORT_ERROR >/dev/null 2>&1; then
    readonly EXIT_REPORT_ERROR=6
fi

if ! declare -p EXIT_CONFIGURATION_ERROR >/dev/null 2>&1; then
    readonly EXIT_CONFIGURATION_ERROR=7
fi

if ! declare -p EXIT_VALIDATION_ERROR >/dev/null 2>&1; then
    readonly EXIT_VALIDATION_ERROR=8
fi

if ! declare -p EXIT_COMMAND_ERROR >/dev/null 2>&1; then
    readonly EXIT_COMMAND_ERROR=9
fi

if ! declare -p EXIT_TIMEOUT_ERROR >/dev/null 2>&1; then
    readonly EXIT_TIMEOUT_ERROR=10
fi

if ! declare -p EXIT_NOT_FOUND >/dev/null 2>&1; then
    readonly EXIT_NOT_FOUND=11
fi

if ! declare -p EXIT_UNSUPPORTED >/dev/null 2>&1; then
    readonly EXIT_UNSUPPORTED=12
fi

if ! declare -p EXIT_INTERRUPTED >/dev/null 2>&1; then
    readonly EXIT_INTERRUPTED=130
fi

# ---------------------------------------------------------------------------
# Categorias de erro
# ---------------------------------------------------------------------------

readonly HC_ERROR_CATEGORY_GENERAL="general"
readonly HC_ERROR_CATEGORY_ARGUMENT="argument"
readonly HC_ERROR_CATEGORY_DEPENDENCY="dependency"
readonly HC_ERROR_CATEGORY_PERMISSION="permission"
readonly HC_ERROR_CATEGORY_MODULE="module"
readonly HC_ERROR_CATEGORY_REPORT="report"
readonly HC_ERROR_CATEGORY_CONFIGURATION="configuration"
readonly HC_ERROR_CATEGORY_VALIDATION="validation"
readonly HC_ERROR_CATEGORY_COMMAND="command"
readonly HC_ERROR_CATEGORY_TIMEOUT="timeout"
readonly HC_ERROR_CATEGORY_NOT_FOUND="not_found"
readonly HC_ERROR_CATEGORY_UNSUPPORTED="unsupported"
readonly HC_ERROR_CATEGORY_INTERRUPTED="interrupted"

# ---------------------------------------------------------------------------
# Variáveis de estado
# ---------------------------------------------------------------------------

HC_LAST_ERROR_CODE=0
HC_LAST_ERROR_CATEGORY=""
HC_LAST_ERROR_MESSAGE=""
HC_LAST_ERROR_COMMAND=""
HC_LAST_ERROR_FUNCTION=""
HC_LAST_ERROR_SOURCE=""
HC_LAST_ERROR_LINE=""
HC_LAST_ERROR_TIMESTAMP=""
HC_LAST_ERROR_STACK=""

HC_ERROR_TRAP_ENABLED=0
HC_ERROR_TRAP_RUNNING=0
HC_ERROR_STACK_TRACE_ENABLED="${HC_ERROR_STACK_TRACE_ENABLED:-1}"

declare -ag HC_ERROR_HISTORY=()

# ---------------------------------------------------------------------------
# Tabela de mensagens
# ---------------------------------------------------------------------------

declare -gA HC_ERROR_CODE_MESSAGES=(
    ["${EXIT_SUCCESS}"]="Operação concluída com sucesso."
    ["${EXIT_GENERAL_ERROR}"]="Ocorreu um erro geral."
    ["${EXIT_INVALID_ARGUMENT}"]="Foi informado um argumento inválido."
    ["${EXIT_DEPENDENCY_ERROR}"]="Uma dependência necessária não está disponível."
    ["${EXIT_PERMISSION_ERROR}"]="A operação não possui permissão suficiente."
    ["${EXIT_MODULE_ERROR}"]="Ocorreu uma falha em um módulo."
    ["${EXIT_REPORT_ERROR}"]="Ocorreu uma falha ao gerar um relatório."
    ["${EXIT_CONFIGURATION_ERROR}"]="A configuração é inválida ou não pôde ser carregada."
    ["${EXIT_VALIDATION_ERROR}"]="Uma validação obrigatória falhou."
    ["${EXIT_COMMAND_ERROR}"]="Um comando externo retornou erro."
    ["${EXIT_TIMEOUT_ERROR}"]="A operação excedeu o tempo limite."
    ["${EXIT_NOT_FOUND}"]="O recurso solicitado não foi encontrado."
    ["${EXIT_UNSUPPORTED}"]="A operação ou plataforma não é suportada."
    ["${EXIT_INTERRUPTED}"]="A execução foi interrompida."
)

declare -gA HC_ERROR_CODE_CATEGORIES=(
    ["${EXIT_SUCCESS}"]="${HC_ERROR_CATEGORY_GENERAL}"
    ["${EXIT_GENERAL_ERROR}"]="${HC_ERROR_CATEGORY_GENERAL}"
    ["${EXIT_INVALID_ARGUMENT}"]="${HC_ERROR_CATEGORY_ARGUMENT}"
    ["${EXIT_DEPENDENCY_ERROR}"]="${HC_ERROR_CATEGORY_DEPENDENCY}"
    ["${EXIT_PERMISSION_ERROR}"]="${HC_ERROR_CATEGORY_PERMISSION}"
    ["${EXIT_MODULE_ERROR}"]="${HC_ERROR_CATEGORY_MODULE}"
    ["${EXIT_REPORT_ERROR}"]="${HC_ERROR_CATEGORY_REPORT}"
    ["${EXIT_CONFIGURATION_ERROR}"]="${HC_ERROR_CATEGORY_CONFIGURATION}"
    ["${EXIT_VALIDATION_ERROR}"]="${HC_ERROR_CATEGORY_VALIDATION}"
    ["${EXIT_COMMAND_ERROR}"]="${HC_ERROR_CATEGORY_COMMAND}"
    ["${EXIT_TIMEOUT_ERROR}"]="${HC_ERROR_CATEGORY_TIMEOUT}"
    ["${EXIT_NOT_FOUND}"]="${HC_ERROR_CATEGORY_NOT_FOUND}"
    ["${EXIT_UNSUPPORTED}"]="${HC_ERROR_CATEGORY_UNSUPPORTED}"
    ["${EXIT_INTERRUPTED}"]="${HC_ERROR_CATEGORY_INTERRUPTED}"
)

# ---------------------------------------------------------------------------
# Funções de consulta
# ---------------------------------------------------------------------------

errors_code_is_valid() {
    local code="${1:-}"

    [[ "$code" =~ ^[0-9]+$ ]] &&
        [[ -n "${HC_ERROR_CODE_MESSAGES[$code]+x}" ]]
}

errors_message_for_code() {
    local code="${1:-$EXIT_GENERAL_ERROR}"

    if errors_code_is_valid "$code"; then
        printf '%s\n' "${HC_ERROR_CODE_MESSAGES[$code]}"
        return 0
    fi

    printf '%s\n' "${HC_ERROR_CODE_MESSAGES[$EXIT_GENERAL_ERROR]}"
    return 1
}

errors_category_for_code() {
    local code="${1:-$EXIT_GENERAL_ERROR}"

    if errors_code_is_valid "$code"; then
        printf '%s\n' "${HC_ERROR_CODE_CATEGORIES[$code]}"
        return 0
    fi

    printf '%s\n' "$HC_ERROR_CATEGORY_GENERAL"
    return 1
}

errors_exit_code_for_category() {
    local category="${1:-}"

    case "$category" in
        "$HC_ERROR_CATEGORY_ARGUMENT")
            printf '%s\n' "$EXIT_INVALID_ARGUMENT"
            ;;
        "$HC_ERROR_CATEGORY_DEPENDENCY")
            printf '%s\n' "$EXIT_DEPENDENCY_ERROR"
            ;;
        "$HC_ERROR_CATEGORY_PERMISSION")
            printf '%s\n' "$EXIT_PERMISSION_ERROR"
            ;;
        "$HC_ERROR_CATEGORY_MODULE")
            printf '%s\n' "$EXIT_MODULE_ERROR"
            ;;
        "$HC_ERROR_CATEGORY_REPORT")
            printf '%s\n' "$EXIT_REPORT_ERROR"
            ;;
        "$HC_ERROR_CATEGORY_CONFIGURATION")
            printf '%s\n' "$EXIT_CONFIGURATION_ERROR"
            ;;
        "$HC_ERROR_CATEGORY_VALIDATION")
            printf '%s\n' "$EXIT_VALIDATION_ERROR"
            ;;
        "$HC_ERROR_CATEGORY_COMMAND")
            printf '%s\n' "$EXIT_COMMAND_ERROR"
            ;;
        "$HC_ERROR_CATEGORY_TIMEOUT")
            printf '%s\n' "$EXIT_TIMEOUT_ERROR"
            ;;
        "$HC_ERROR_CATEGORY_NOT_FOUND")
            printf '%s\n' "$EXIT_NOT_FOUND"
            ;;
        "$HC_ERROR_CATEGORY_UNSUPPORTED")
            printf '%s\n' "$EXIT_UNSUPPORTED"
            ;;
        "$HC_ERROR_CATEGORY_INTERRUPTED")
            printf '%s\n' "$EXIT_INTERRUPTED"
            ;;
        "$HC_ERROR_CATEGORY_GENERAL" | *)
            printf '%s\n' "$EXIT_GENERAL_ERROR"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Registro do erro atual
# ---------------------------------------------------------------------------

errors_clear_last() {
    HC_LAST_ERROR_CODE=0
    HC_LAST_ERROR_CATEGORY=""
    HC_LAST_ERROR_MESSAGE=""
    HC_LAST_ERROR_COMMAND=""
    HC_LAST_ERROR_FUNCTION=""
    HC_LAST_ERROR_SOURCE=""
    HC_LAST_ERROR_LINE=""
    HC_LAST_ERROR_TIMESTAMP=""
    HC_LAST_ERROR_STACK=""
}

errors_build_stack_trace() {
    local start_index="${1:-1}"
    local index
    local function_name
    local source_file
    local source_line
    local trace=""

    if [[ ! "$start_index" =~ ^[0-9]+$ ]]; then
        start_index=1
    fi

    for ((index = start_index; index < ${#FUNCNAME[@]}; index++)); do
        function_name="${FUNCNAME[$index]:-main}"
        source_file="${BASH_SOURCE[$index]:-${BASH_SOURCE[-1]:-desconhecido}}"
        source_line="${BASH_LINENO[$((index - 1))]:-0}"

        trace+="${function_name}() em ${source_file}:${source_line}"

        if ((index < ${#FUNCNAME[@]} - 1)); then
            trace+=$'\n'
        fi
    done

    printf '%s' "$trace"
}

errors_record() {
    local code="${1:-$EXIT_GENERAL_ERROR}"
    local message="${2:-}"
    local command="${3:-}"
    local function_name="${4:-${FUNCNAME[1]:-main}}"
    local source_file="${5:-${BASH_SOURCE[1]:-desconhecido}}"
    local source_line="${6:-${BASH_LINENO[0]:-0}}"
    local timestamp
    local history_entry

    if [[ ! "$code" =~ ^[0-9]+$ ]]; then
        code="$EXIT_GENERAL_ERROR"
    fi

    if [[ -z "$message" ]]; then
        message="$(errors_message_for_code "$code")"
    fi

    timestamp="$(date '+%Y-%m-%dT%H:%M:%S%z')"

    HC_LAST_ERROR_CODE="$code"
    HC_LAST_ERROR_CATEGORY="$(errors_category_for_code "$code")"
    HC_LAST_ERROR_MESSAGE="$message"
    HC_LAST_ERROR_COMMAND="$command"
    HC_LAST_ERROR_FUNCTION="$function_name"
    HC_LAST_ERROR_SOURCE="$source_file"
    HC_LAST_ERROR_LINE="$source_line"
    HC_LAST_ERROR_TIMESTAMP="$timestamp"

    if ((HC_ERROR_STACK_TRACE_ENABLED == 1)); then
        HC_LAST_ERROR_STACK="$(errors_build_stack_trace 2)"
    else
        HC_LAST_ERROR_STACK=""
    fi

    history_entry="$timestamp"
    history_entry+=$'\t'
    history_entry+="$code"
    history_entry+=$'\t'
    history_entry+="$HC_LAST_ERROR_CATEGORY"
    history_entry+=$'\t'
    history_entry+="$message"
    history_entry+=$'\t'
    history_entry+="$command"
    history_entry+=$'\t'
    history_entry+="$function_name"
    history_entry+=$'\t'
    history_entry+="$source_file"
    history_entry+=$'\t'
    history_entry+="$source_line"

    HC_ERROR_HISTORY+=("$history_entry")
}

errors_history_count() {
    printf '%s\n' "${#HC_ERROR_HISTORY[@]}"
}

errors_history_clear() {
    HC_ERROR_HISTORY=()
}

# ---------------------------------------------------------------------------
# Saída e integração com logger
# ---------------------------------------------------------------------------

errors_write_log() {
    local level="${1:-ERROR}"
    local message="${2:-}"

    if declare -F logger_log >/dev/null 2>&1; then
        logger_log "$level" "$message"
        return 0
    fi

    if [[ -n "${CURRENT_LOG_FILE:-}" ]]; then
        printf '%s [%s] %s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" \
            "$level" \
            "$message" >>"$CURRENT_LOG_FILE" 2>/dev/null || true
    fi
}

errors_print_stderr() {
    local level="${1:-ERROR}"
    local message="${2:-}"
    local prefix="$level"

    case "$level" in
        WARNING)
            if declare -F ui_print_warning >/dev/null 2>&1; then
                ui_print_warning "$message" >&2
                return 0
            fi

            prefix="AVISO"
            ;;
        CRITICAL)
            if declare -F ui_print_error >/dev/null 2>&1; then
                ui_print_error "$message"
                return 0
            fi

            prefix="CRÍTICO"
            ;;
        ERROR | *)
            if declare -F ui_print_error >/dev/null 2>&1; then
                ui_print_error "$message"
                return 0
            fi

            prefix="ERRO"
            ;;
    esac

    printf '%s: %s\n' "$prefix" "$message" >&2
}

errors_report() {
    local code="${1:-$EXIT_GENERAL_ERROR}"
    local message="${2:-}"
    local command="${3:-}"
    local function_name="${4:-${FUNCNAME[1]:-main}}"
    local source_file="${5:-${BASH_SOURCE[1]:-desconhecido}}"
    local source_line="${6:-${BASH_LINENO[0]:-0}}"
    local log_message

    errors_record \
        "$code" \
        "$message" \
        "$command" \
        "$function_name" \
        "$source_file" \
        "$source_line"

    log_message="$HC_LAST_ERROR_MESSAGE"
    log_message+=" | código=${HC_LAST_ERROR_CODE}"
    log_message+=" | categoria=${HC_LAST_ERROR_CATEGORY}"
    log_message+=" | função=${HC_LAST_ERROR_FUNCTION}"
    log_message+=" | origem=${HC_LAST_ERROR_SOURCE}:${HC_LAST_ERROR_LINE}"

    if [[ -n "$HC_LAST_ERROR_COMMAND" ]]; then
        log_message+=" | comando=${HC_LAST_ERROR_COMMAND}"
    fi

    errors_write_log "ERROR" "$log_message"
    errors_print_stderr "ERROR" "$HC_LAST_ERROR_MESSAGE"
}

errors_warn() {
    local message="${1:-Aviso não especificado.}"

    errors_write_log "WARNING" "$message"
    errors_print_stderr "WARNING" "$message"
}

errors_notice() {
    local message="${1:-}"

    errors_write_log "NOTICE" "$message"

    if [[ "${QUIET:-0}" == "1" ]]; then
        return 0
    fi

    if declare -F ui_print_info >/dev/null 2>&1; then
        ui_print_info "$message"
    else
        printf 'INFO: %s\n' "$message"
    fi
}

# ---------------------------------------------------------------------------
# Encerramento controlado
# ---------------------------------------------------------------------------

errors_die() {
    local code="${1:-$EXIT_GENERAL_ERROR}"
    local message="${2:-}"
    local command="${3:-}"
    local function_name="${4:-${FUNCNAME[1]:-main}}"
    local source_file="${5:-${BASH_SOURCE[1]:-desconhecido}}"
    local source_line="${6:-${BASH_LINENO[0]:-0}}"

    if [[ ! "$code" =~ ^[0-9]+$ ]] || ((code == 0)); then
        code="$EXIT_GENERAL_ERROR"
    fi

    errors_report \
        "$code" \
        "$message" \
        "$command" \
        "$function_name" \
        "$source_file" \
        "$source_line"

    exit "$code"
}

errors_die_invalid_argument() {
    local message="${1:-Argumento inválido.}"

    errors_die \
        "$EXIT_INVALID_ARGUMENT" \
        "$message" \
        "" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_SOURCE[1]:-desconhecido}" \
        "${BASH_LINENO[0]:-0}"
}

errors_die_dependency() {
    local message="${1:-Dependência obrigatória ausente.}"

    errors_die \
        "$EXIT_DEPENDENCY_ERROR" \
        "$message" \
        "" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_SOURCE[1]:-desconhecido}" \
        "${BASH_LINENO[0]:-0}"
}

errors_die_permission() {
    local message="${1:-Permissão insuficiente.}"

    errors_die \
        "$EXIT_PERMISSION_ERROR" \
        "$message" \
        "" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_SOURCE[1]:-desconhecido}" \
        "${BASH_LINENO[0]:-0}"
}

errors_die_configuration() {
    local message="${1:-Configuração inválida.}"

    errors_die \
        "$EXIT_CONFIGURATION_ERROR" \
        "$message" \
        "" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_SOURCE[1]:-desconhecido}" \
        "${BASH_LINENO[0]:-0}"
}

errors_die_validation() {
    local message="${1:-Validação obrigatória falhou.}"

    errors_die \
        "$EXIT_VALIDATION_ERROR" \
        "$message" \
        "" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_SOURCE[1]:-desconhecido}" \
        "${BASH_LINENO[0]:-0}"
}

# ---------------------------------------------------------------------------
# Asserções
# ---------------------------------------------------------------------------

errors_assert_non_empty() {
    local value="${1:-}"
    local name="${2:-valor}"

    if [[ -z "$value" ]]; then
        errors_report \
            "$EXIT_VALIDATION_ERROR" \
            "O campo ${name} não pode ficar vazio." \
            "" \
            "${FUNCNAME[1]:-main}" \
            "${BASH_SOURCE[1]:-desconhecido}" \
            "${BASH_LINENO[0]:-0}"
        return "$EXIT_VALIDATION_ERROR"
    fi

    return 0
}

errors_assert_integer() {
    local value="${1:-}"
    local name="${2:-valor}"

    if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
        errors_report \
            "$EXIT_VALIDATION_ERROR" \
            "O campo ${name} deve ser um número inteiro." \
            "" \
            "${FUNCNAME[1]:-main}" \
            "${BASH_SOURCE[1]:-desconhecido}" \
            "${BASH_LINENO[0]:-0}"
        return "$EXIT_VALIDATION_ERROR"
    fi

    return 0
}

errors_assert_unsigned_integer() {
    local value="${1:-}"
    local name="${2:-valor}"

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        errors_report \
            "$EXIT_VALIDATION_ERROR" \
            "O campo ${name} deve ser um número inteiro não negativo." \
            "" \
            "${FUNCNAME[1]:-main}" \
            "${BASH_SOURCE[1]:-desconhecido}" \
            "${BASH_LINENO[0]:-0}"
        return "$EXIT_VALIDATION_ERROR"
    fi

    return 0
}

errors_assert_file_exists() {
    local file_path="${1:-}"
    local description="${2:-arquivo}"

    if [[ -z "$file_path" || ! -f "$file_path" ]]; then
        errors_report \
            "$EXIT_NOT_FOUND" \
            "${description} não encontrado: ${file_path:-caminho vazio}" \
            "" \
            "${FUNCNAME[1]:-main}" \
            "${BASH_SOURCE[1]:-desconhecido}" \
            "${BASH_LINENO[0]:-0}"
        return "$EXIT_NOT_FOUND"
    fi

    return 0
}

errors_assert_directory_exists() {
    local directory_path="${1:-}"
    local description="${2:-diretório}"

    if [[ -z "$directory_path" || ! -d "$directory_path" ]]; then
        errors_report \
            "$EXIT_NOT_FOUND" \
            "${description} não encontrado: ${directory_path:-caminho vazio}" \
            "" \
            "${FUNCNAME[1]:-main}" \
            "${BASH_SOURCE[1]:-desconhecido}" \
            "${BASH_LINENO[0]:-0}"
        return "$EXIT_NOT_FOUND"
    fi

    return 0
}

errors_assert_readable() {
    local path="${1:-}"
    local description="${2:-recurso}"

    if [[ -z "$path" || ! -r "$path" ]]; then
        errors_report \
            "$EXIT_PERMISSION_ERROR" \
            "${description} sem permissão de leitura: ${path:-caminho vazio}" \
            "" \
            "${FUNCNAME[1]:-main}" \
            "${BASH_SOURCE[1]:-desconhecido}" \
            "${BASH_LINENO[0]:-0}"
        return "$EXIT_PERMISSION_ERROR"
    fi

    return 0
}

errors_assert_writable() {
    local path="${1:-}"
    local description="${2:-recurso}"

    if [[ -z "$path" || ! -w "$path" ]]; then
        errors_report \
            "$EXIT_PERMISSION_ERROR" \
            "${description} sem permissão de escrita: ${path:-caminho vazio}" \
            "" \
            "${FUNCNAME[1]:-main}" \
            "${BASH_SOURCE[1]:-desconhecido}" \
            "${BASH_LINENO[0]:-0}"
        return "$EXIT_PERMISSION_ERROR"
    fi

    return 0
}

errors_assert_command_exists() {
    local command_name="${1:-}"

    if [[ -z "$command_name" ]]; then
        errors_report \
            "$EXIT_INVALID_ARGUMENT" \
            "O nome do comando não pode ficar vazio." \
            "" \
            "${FUNCNAME[1]:-main}" \
            "${BASH_SOURCE[1]:-desconhecido}" \
            "${BASH_LINENO[0]:-0}"
        return "$EXIT_INVALID_ARGUMENT"
    fi

    if ! command -v "$command_name" >/dev/null 2>&1; then
        errors_report \
            "$EXIT_DEPENDENCY_ERROR" \
            "Comando obrigatório não encontrado: ${command_name}" \
            "$command_name" \
            "${FUNCNAME[1]:-main}" \
            "${BASH_SOURCE[1]:-desconhecido}" \
            "${BASH_LINENO[0]:-0}"
        return "$EXIT_DEPENDENCY_ERROR"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Execução protegida de comandos
# ---------------------------------------------------------------------------

errors_run_command() {
    local description="${1:-Comando}"
    shift || true

    local exit_code
    local command_text

    if (($# == 0)); then
        errors_report \
            "$EXIT_INVALID_ARGUMENT" \
            "Nenhum comando foi informado para ${description}." \
            "" \
            "${FUNCNAME[1]:-main}" \
            "${BASH_SOURCE[1]:-desconhecido}" \
            "${BASH_LINENO[0]:-0}"
        return "$EXIT_INVALID_ARGUMENT"
    fi

    printf -v command_text '%q ' "$@"
    command_text="${command_text% }"

    if "$@"; then
        return 0
    else
        exit_code=$?
    fi

    errors_report \
        "$exit_code" \
        "${description} falhou com código ${exit_code}." \
        "$command_text" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_SOURCE[1]:-desconhecido}" \
        "${BASH_LINENO[0]:-0}"

    return "$exit_code"
}

errors_run_command_quiet() {
    local description="${1:-Comando}"
    shift || true

    local exit_code
    local command_text

    if (($# == 0)); then
        errors_report \
            "$EXIT_INVALID_ARGUMENT" \
            "Nenhum comando foi informado para ${description}." \
            "" \
            "${FUNCNAME[1]:-main}" \
            "${BASH_SOURCE[1]:-desconhecido}" \
            "${BASH_LINENO[0]:-0}"
        return "$EXIT_INVALID_ARGUMENT"
    fi

    printf -v command_text '%q ' "$@"
    command_text="${command_text% }"

    if "$@" >/dev/null 2>&1; then
        return 0
    else
        exit_code=$?
    fi

    errors_record \
        "$exit_code" \
        "${description} falhou com código ${exit_code}." \
        "$command_text" \
        "${FUNCNAME[1]:-main}" \
        "${BASH_SOURCE[1]:-desconhecido}" \
        "${BASH_LINENO[0]:-0}"

    errors_write_log \
        "ERROR" \
        "${description} falhou | código=${exit_code} | comando=${command_text}"

    return "$exit_code"
}

# ---------------------------------------------------------------------------
# Trap ERR
# ---------------------------------------------------------------------------

errors_err_trap_handler() {
    local exit_code="${1:-$?}"
    local failed_command="${2:-${BASH_COMMAND:-desconhecido}}"
    local source_line="${3:-${BASH_LINENO[0]:-0}}"
    local source_file="${4:-${BASH_SOURCE[1]:-desconhecido}}"
    local function_name="${5:-${FUNCNAME[1]:-main}}"
    local message

    if ((HC_ERROR_TRAP_RUNNING == 1)); then
        return "$exit_code"
    fi

    HC_ERROR_TRAP_RUNNING=1

    message="Falha não tratada no comando: ${failed_command}"

    errors_record \
        "$exit_code" \
        "$message" \
        "$failed_command" \
        "$function_name" \
        "$source_file" \
        "$source_line"

    errors_write_log \
        "ERROR" \
        "${message} | código=${exit_code} | função=${function_name} | origem=${source_file}:${source_line}"

    if [[ "${VERBOSE:-0}" == "1" ]]; then
        errors_print_stderr \
            "ERROR" \
            "${message} em ${source_file}:${source_line}"
    fi

    HC_ERROR_TRAP_RUNNING=0
    return "$exit_code"
}

errors_enable_err_trap() {
    set -E
    trap 'errors_err_trap_handler "$?" "$BASH_COMMAND" "${BASH_LINENO[0]:-0}" "${BASH_SOURCE[0]:-desconhecido}" "${FUNCNAME[0]:-main}"' ERR
    HC_ERROR_TRAP_ENABLED=1
}

errors_disable_err_trap() {
    trap - ERR
    HC_ERROR_TRAP_ENABLED=0
}

errors_err_trap_is_enabled() {
    ((HC_ERROR_TRAP_ENABLED == 1))
}

# ---------------------------------------------------------------------------
# Exibição detalhada
# ---------------------------------------------------------------------------

errors_print_last() {
    if ((HC_LAST_ERROR_CODE == 0)); then
        printf 'Nenhum erro foi registrado.\n'
        return 0
    fi

    printf 'Último erro registrado\n'
    printf '  Código:      %s\n' "$HC_LAST_ERROR_CODE"
    printf '  Categoria:   %s\n' "$HC_LAST_ERROR_CATEGORY"
    printf '  Mensagem:    %s\n' "$HC_LAST_ERROR_MESSAGE"
    printf '  Função:      %s\n' "$HC_LAST_ERROR_FUNCTION"
    printf '  Origem:      %s:%s\n' \
        "$HC_LAST_ERROR_SOURCE" \
        "$HC_LAST_ERROR_LINE"
    printf '  Data:        %s\n' "$HC_LAST_ERROR_TIMESTAMP"

    if [[ -n "$HC_LAST_ERROR_COMMAND" ]]; then
        printf '  Comando:     %s\n' "$HC_LAST_ERROR_COMMAND"
    fi

    if [[ -n "$HC_LAST_ERROR_STACK" ]]; then
        printf '  Pilha:\n'
        printf '%s\n' "$HC_LAST_ERROR_STACK" |
            sed 's/^/    /'
    fi
}

errors_export_last() {
    export HC_LAST_ERROR_CODE
    export HC_LAST_ERROR_CATEGORY
    export HC_LAST_ERROR_MESSAGE
    export HC_LAST_ERROR_COMMAND
    export HC_LAST_ERROR_FUNCTION
    export HC_LAST_ERROR_SOURCE
    export HC_LAST_ERROR_LINE
    export HC_LAST_ERROR_TIMESTAMP
    export HC_LAST_ERROR_STACK
}

# ---------------------------------------------------------------------------
# Inicialização e validação
# ---------------------------------------------------------------------------

errors_initialize() {
    errors_clear_last
    errors_history_clear

    HC_ERROR_TRAP_ENABLED=0
    HC_ERROR_TRAP_RUNNING=0

    export HC_ERROR_STACK_TRACE_ENABLED
    export HC_ERROR_TRAP_ENABLED
}

errors_validate() {
    local failure=0
    local code
    local message
    local category

    for code in \
        "$EXIT_SUCCESS" \
        "$EXIT_GENERAL_ERROR" \
        "$EXIT_INVALID_ARGUMENT" \
        "$EXIT_DEPENDENCY_ERROR" \
        "$EXIT_PERMISSION_ERROR" \
        "$EXIT_MODULE_ERROR" \
        "$EXIT_REPORT_ERROR" \
        "$EXIT_CONFIGURATION_ERROR" \
        "$EXIT_VALIDATION_ERROR" \
        "$EXIT_COMMAND_ERROR" \
        "$EXIT_TIMEOUT_ERROR" \
        "$EXIT_NOT_FOUND" \
        "$EXIT_UNSUPPORTED" \
        "$EXIT_INTERRUPTED"; do

        if ! errors_code_is_valid "$code"; then
            printf 'Código de erro não registrado: %s\n' "$code" >&2
            failure=1
            continue
        fi

        message="$(errors_message_for_code "$code")"
        category="$(errors_category_for_code "$code")"

        if [[ -z "$message" ]]; then
            printf 'Código sem mensagem: %s\n' "$code" >&2
            failure=1
        fi

        if [[ -z "$category" ]]; then
            printf 'Código sem categoria: %s\n' "$code" >&2
            failure=1
        fi
    done

    return "$failure"
}

errors_initialize
