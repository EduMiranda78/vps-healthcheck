#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Identificação
# ---------------------------------------------------------------------------

readonly PROGRAM_NAME="vps-healthcheck"
readonly PROGRAM_VERSION="0.1.1"
readonly PROGRAM_DESCRIPTION="Ferramenta de auditoria, monitoramento e inventário para VPS Linux"

# ---------------------------------------------------------------------------
# Códigos de saída
# ---------------------------------------------------------------------------

readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_INVALID_ARGUMENT=2
readonly EXIT_DEPENDENCY_ERROR=3
readonly EXIT_PERMISSION_ERROR=4
readonly EXIT_MODULE_ERROR=5
readonly EXIT_REPORT_ERROR=6
readonly EXIT_CONFIGURATION_ERROR=7
readonly EXIT_VALIDATION_ERROR=8
readonly EXIT_COMMAND_ERROR=9
readonly EXIT_TIMEOUT_ERROR=10
readonly EXIT_NOT_FOUND=11
readonly EXIT_UNSUPPORTED=12
readonly EXIT_INTERRUPTED=130

# ---------------------------------------------------------------------------
# Caminhos do projeto
# ---------------------------------------------------------------------------

resolve_script_dir() {
    local source="${BASH_SOURCE[0]}"

    while [[ -h "$source" ]]; do
        local directory

        directory="$(
            cd -P "$(dirname "$source")" >/dev/null 2>&1
            pwd
        )"

        source="$(readlink "$source")"

        if [[ "$source" != /* ]]; then
            source="${directory}/${source}"
        fi
    done

    cd -P "$(dirname "$source")" >/dev/null 2>&1
    pwd
}

SCRIPT_PATH="${BASH_SOURCE[0]}"

SCRIPT_DIR="$(resolve_script_dir)"

PROJECT_ROOT="$SCRIPT_DIR"

CONFIG_DIR="${PROJECT_ROOT}/config"
LIB_DIR="${PROJECT_ROOT}/lib"
REPORTS_DIR="${PROJECT_ROOT}/reports"
LOGS_DIR="${PROJECT_ROOT}/logs"
TEMPLATES_DIR="${PROJECT_ROOT}/templates"
ASSETS_DIR="${PROJECT_ROOT}/assets"
TESTS_DIR="${PROJECT_ROOT}/tests"

DEFAULT_CONFIG_FILE="${CONFIG_DIR}/healthcheck.conf"
DEFAULT_THRESHOLDS_FILE="${CONFIG_DIR}/thresholds.conf"

CONFIG_FILE="$DEFAULT_CONFIG_FILE"
THRESHOLDS_FILE="$DEFAULT_THRESHOLDS_FILE"
OUTPUT_DIR="$REPORTS_DIR"

# ---------------------------------------------------------------------------
# Identificação da execução
# ---------------------------------------------------------------------------

RUN_ID="$(date '+%Y%m%d_%H%M%S')_$$"
START_TIMESTAMP="$(date '+%Y-%m-%dT%H:%M:%S%z')"
START_EPOCH="$(date '+%s')"

TEMP_ROOT=""
CURRENT_LOG_FILE=""
CURRENT_REPORT_DIR=""

# ---------------------------------------------------------------------------
# Opções
# ---------------------------------------------------------------------------

RUN_MODE=""

NO_COLOR=0
VERBOSE=0
QUIET=0
NON_INTERACTIVE=0
USE_SUDO=1
KEEP_TEMP=0

SHOW_HELP=0
SHOW_VERSION=0
LIST_MODULES=0
RUN_SELF_TEST=0

TERMINAL_OUTPUT_DISABLED=0

CLI_RUN_MODE_SET=0
CLI_OUTPUT_FORMAT_SET=0
CLI_OUTPUT_DIR_SET=0
CLI_CONFIG_FILE_SET=0
CLI_THRESHOLDS_FILE_SET=0
CLI_NO_COLOR_SET=0
CLI_VERBOSE_SET=0
CLI_QUIET_SET=0
CLI_NON_INTERACTIVE_SET=0
CLI_USE_SUDO_SET=0
CLI_KEEP_TEMP_SET=0

declare -a OUTPUT_FORMATS=()
declare -a SELECTED_MODULES=()

declare -a LOADED_MODULES=()
declare -a FAILED_MODULES=()
declare -a SKIPPED_MODULES=()
declare -a COMPLETED_MODULES=()

# ---------------------------------------------------------------------------
# Registro de módulos
# ---------------------------------------------------------------------------

declare -A MODULE_FILES=(
    [system]="system.sh"
    [cpu]="cpu.sh"
    [memory]="memory.sh"
    [disk]="disk.sh"
    [network]="network.sh"
    [python]="python.sh"
    [docker]="docker.sh"
    [nginx]="nginx.sh"
    [ssl]="ssl.sh"
    [database]="database.sh"
    [firewall]="firewall.sh"
    [security]="security.sh"
    [services]="services.sh"
    [logs]="logs.sh"
    [updates]="updates.sh"
    [ai]="ai.sh"
    [ollama]="ollama.sh"
)

declare -A MODULE_FUNCTIONS=(
    [system]="system_run"
    [cpu]="cpu_run"
    [memory]="memory_run"
    [disk]="disk_run"
    [network]="network_run"
    [python]="python_run"
    [docker]="docker_run"
    [nginx]="nginx_run"
    [ssl]="ssl_run"
    [database]="database_run"
    [firewall]="firewall_run"
    [security]="security_run"
    [services]="services_run"
    [logs]="logs_run"
    [updates]="updates_run"
    [ai]="ai_run"
    [ollama]="ollama_run"
)

declare -A MODULE_REQUIRED=(
    [system]=1
    [cpu]=1
    [memory]=1
    [disk]=1
    [network]=1
    [python]=0
    [docker]=0
    [nginx]=0
    [ssl]=0
    [database]=0
    [firewall]=0
    [security]=0
    [services]=1
    [logs]=0
    [updates]=0
    [ai]=0
    [ollama]=0
)

declare -A MODULE_CONFIG_KEYS=(
    [system]="HC_SYSTEM_ENABLED"
    [cpu]="HC_CPU_ENABLED"
    [memory]="HC_MEMORY_ENABLED"
    [disk]="HC_DISK_ENABLED"
    [network]="HC_NETWORK_ENABLED"
    [python]="HC_PYTHON_ENABLED"
    [docker]="HC_DOCKER_ENABLED"
    [nginx]="HC_NGINX_ENABLED"
    [ssl]="HC_SSL_ENABLED"
    [database]="HC_DATABASE_ENABLED"
    [firewall]="HC_FIREWALL_ENABLED"
    [security]="HC_SECURITY_ENABLED"
    [services]="HC_SERVICES_ENABLED"
    [logs]="HC_LOGS_ENABLED"
    [updates]="HC_UPDATES_ENABLED"
    [ai]="HC_AI_ENABLED"
    [ollama]="HC_OLLAMA_ENABLED"
)

declare -A MODULE_LABELS=(
    [system]="Sistema"
    [cpu]="CPU"
    [memory]="Memória"
    [disk]="Disco"
    [network]="Rede"
    [python]="Python"
    [docker]="Docker"
    [nginx]="Nginx"
    [ssl]="SSL"
    [database]="Bancos de dados"
    [firewall]="Firewall"
    [security]="Segurança"
    [services]="Serviços"
    [logs]="Logs"
    [updates]="Atualizações"
    [ai]="Serviços de IA"
    [ollama]="Ollama"
)

declare -a CORE_LIBRARY_FILES=(
    "constants.sh"
    "colors.sh"
    "errors.sh"
    "utils.sh"
    "logger.sh"
    "config.sh"
    "dependencies.sh"
    "collector.sh"
)

declare -a QUICK_MODULES=(
    "system"
    "cpu"
    "memory"
    "disk"
    "network"
    "services"
    "updates"
)

declare -a FULL_MODULES=(
    "system"
    "cpu"
    "memory"
    "disk"
    "network"
    "services"
    "updates"
    "python"
    "docker"
    "nginx"
    "ssl"
    "database"
    "firewall"
    "security"
    "logs"
    "ai"
    "ollama"
)

declare -a AVAILABLE_OUTPUT_FORMATS=(
    "terminal"
    "txt"
    "json"
    "html"
)

# ---------------------------------------------------------------------------
# Saída antes do logger
# ---------------------------------------------------------------------------

bootstrap_print_error() {
    local message="${1:-Erro não especificado.}"

    printf 'ERRO: %s\n' "$message" >&2
}

bootstrap_print_warning() {
    local message="${1:-Aviso não especificado.}"

    printf 'AVISO: %s\n' "$message" >&2
}

bootstrap_print_info() {
    local message="${1:-}"

    if ((QUIET == 0)); then
        printf '%s\n' "$message"
    fi
}

# ---------------------------------------------------------------------------
# Ajuda
# ---------------------------------------------------------------------------

print_version() {
    printf '%s %s\n' "$PROGRAM_NAME" "$PROGRAM_VERSION"
}

print_help() {
    cat <<EOF
${PROGRAM_NAME} ${PROGRAM_VERSION}

${PROGRAM_DESCRIPTION}

USO:
  ./healthcheck.sh [MODO] [OPÇÕES]

MODOS:
  --quick                 Executa uma auditoria rápida.
  --full                  Executa uma auditoria completa.
  --system                Executa somente o módulo de sistema.
  --cpu                   Executa somente o módulo de CPU.
  --memory                Executa somente o módulo de memória.
  --disk                  Executa somente o módulo de disco.
  --network               Executa somente o módulo de rede.
  --services              Executa somente o módulo de serviços.
  --updates               Executa somente o módulo de atualizações.
  --python                Executa somente o módulo Python.
  --docker                Executa somente o módulo Docker.
  --nginx                 Executa somente o módulo Nginx.
  --ssl                   Executa somente o módulo SSL.
  --database              Executa o módulo de bancos de dados.
  --firewall              Executa somente o módulo de firewall.
  --security              Executa segurança e firewall.
  --logs                  Executa somente o módulo de logs.
  --ai                    Executa o módulo de serviços de IA.
  --ollama                Executa somente o módulo Ollama.
  --module NOME           Executa um módulo pelo nome.
  --modules A,B,C         Executa uma lista de módulos.

FORMATOS:
  --terminal              Exibe resultado no terminal.
  --no-terminal           Desativa a saída detalhada no terminal.
  --txt                   Gera relatório TXT.
  --json                  Gera relatório JSON.
  --html                  Gera relatório HTML.

CONFIGURAÇÃO:
  --config ARQUIVO        Arquivo principal de configuração.
  --thresholds ARQUIVO    Arquivo de limites de saúde.
  --output-dir DIRETÓRIO  Diretório de saída dos relatórios.
  --no-color              Desativa cores ANSI.
  --no-sudo               Não utiliza sudo.
  --non-interactive       Não solicita confirmação ou senha.
  --keep-temp             Preserva arquivos temporários.

DIAGNÓSTICO:
  --verbose               Exibe informações adicionais.
  --quiet                 Exibe somente erros e resultados essenciais.
  --list-modules          Lista os módulos disponíveis.
  --self-test             Valida a instalação atual.
  --version               Exibe a versão.
  --help                  Exibe esta ajuda.

EXEMPLOS:
  ./healthcheck.sh --quick
  ./healthcheck.sh --full --html
  ./healthcheck.sh --full --json --html
  ./healthcheck.sh --python --json
  ./healthcheck.sh --docker --nginx --ssl
  ./healthcheck.sh --modules system,cpu,memory,disk
  ./healthcheck.sh --full --output-dir /var/reports/vps-healthcheck
EOF
}

list_available_modules() {
    local module
    local requirement

    printf 'Módulos disponíveis:\n'

    for module in "${FULL_MODULES[@]}"; do
        if [[ "${MODULE_REQUIRED[$module]}" == "1" ]]; then
            requirement="obrigatório"
        else
            requirement="opcional"
        fi

        printf '  %-12s %-20s %s\n' \
            "$module" \
            "${MODULE_LABELS[$module]}" \
            "$requirement"
    done
}

# ---------------------------------------------------------------------------
# Arrays
# ---------------------------------------------------------------------------

array_contains() {
    local target="${1:-}"
    shift || true

    local item

    for item in "$@"; do
        if [[ "$item" == "$target" ]]; then
            return 0
        fi
    done

    return 1
}

add_selected_module() {
    local module="${1:-}"

    if ! is_known_module "$module"; then
        bootstrap_print_error "Módulo desconhecido: ${module}"
        exit "$EXIT_INVALID_ARGUMENT"
    fi

    if ! array_contains "$module" "${SELECTED_MODULES[@]}"; then
        SELECTED_MODULES+=("$module")
    fi
}

add_output_format() {
    local format="${1:-}"

    if ! array_contains "$format" "${AVAILABLE_OUTPUT_FORMATS[@]}"; then
        bootstrap_print_error "Formato de saída desconhecido: ${format}"
        exit "$EXIT_INVALID_ARGUMENT"
    fi

    if ! array_contains "$format" "${OUTPUT_FORMATS[@]}"; then
        OUTPUT_FORMATS+=("$format")
    fi
}

remove_output_format() {
    local format="${1:-}"
    local item
    local -a updated_formats=()

    for item in "${OUTPUT_FORMATS[@]}"; do
        if [[ "$item" != "$format" ]]; then
            updated_formats+=("$item")
        fi
    done

    OUTPUT_FORMATS=("${updated_formats[@]}")
}

# ---------------------------------------------------------------------------
# Caminhos
# ---------------------------------------------------------------------------

resolve_project_path() {
    local path="${1:-}"

    if [[ -z "$path" ]]; then
        return 1
    fi

    if [[ "$path" == /* ]]; then
        printf '%s\n' "$path"
    else
        printf '%s/%s\n' "$PROJECT_ROOT" "$path"
    fi
}

normalize_runtime_paths() {
    CONFIG_FILE="$(resolve_project_path "$CONFIG_FILE")"
    THRESHOLDS_FILE="$(resolve_project_path "$THRESHOLDS_FILE")"
    OUTPUT_DIR="$(resolve_project_path "$OUTPUT_DIR")"
}

# ---------------------------------------------------------------------------
# Validação de módulos
# ---------------------------------------------------------------------------

is_known_module() {
    local module="${1:-}"

    [[ -n "$module" && -n "${MODULE_FILES[$module]+x}" ]]
}

module_is_enabled() {
    local module="${1:-}"
    local config_key
    local value="1"

    if ! is_known_module "$module"; then
        return 1
    fi

    config_key="${MODULE_CONFIG_KEYS[$module]:-}"

    if [[ -z "$config_key" ]]; then
        return 0
    fi

    if declare -F config_get >/dev/null 2>&1; then
        value="$(config_get "$config_key" "1")"
    elif [[ -n "${!config_key+x}" ]]; then
        value="${!config_key}"
    fi

    [[ "$value" == "1" ]]
}

module_label() {
    local module="${1:-}"

    printf '%s\n' "${MODULE_LABELS[$module]:-$module}"
}

# ---------------------------------------------------------------------------
# Argumentos
# ---------------------------------------------------------------------------

require_option_value() {
    local option="${1:-}"
    local value="${2:-}"

    if [[ -z "$value" || "$value" == --* ]]; then
        bootstrap_print_error "A opção ${option} exige um valor."
        exit "$EXIT_INVALID_ARGUMENT"
    fi
}

set_run_mode() {
    local requested_mode="${1:-}"

    if [[ -n "$RUN_MODE" && "$RUN_MODE" != "$requested_mode" ]]; then
        bootstrap_print_error \
            "Os modos --quick e --full não podem ser usados juntos."

        exit "$EXIT_INVALID_ARGUMENT"
    fi

    RUN_MODE="$requested_mode"
    CLI_RUN_MODE_SET=1
}

parse_module_list() {
    local raw_list="${1:-}"
    local item
    local normalized
    local -a module_items=()

    if [[ -z "$raw_list" ]]; then
        bootstrap_print_error "A lista de módulos não pode ficar vazia."
        exit "$EXIT_INVALID_ARGUMENT"
    fi

    IFS=',' read -r -a module_items <<<"$raw_list"

    for item in "${module_items[@]}"; do
        normalized="${item//[[:space:]]/}"

        if [[ -n "$normalized" ]]; then
            add_selected_module "$normalized"
        fi
    done
}

parse_arguments() {
    while (($# > 0)); do
        case "$1" in
            --quick)
                set_run_mode "quick"
                shift
                ;;
            --full)
                set_run_mode "full"
                shift
                ;;
            --system)
                add_selected_module "system"
                shift
                ;;
            --cpu)
                add_selected_module "cpu"
                shift
                ;;
            --memory)
                add_selected_module "memory"
                shift
                ;;
            --disk)
                add_selected_module "disk"
                shift
                ;;
            --network)
                add_selected_module "network"
                shift
                ;;
            --services)
                add_selected_module "services"
                shift
                ;;
            --updates)
                add_selected_module "updates"
                shift
                ;;
            --python)
                add_selected_module "python"
                shift
                ;;
            --docker)
                add_selected_module "docker"
                shift
                ;;
            --nginx)
                add_selected_module "nginx"
                shift
                ;;
            --ssl)
                add_selected_module "ssl"
                shift
                ;;
            --database)
                add_selected_module "database"
                shift
                ;;
            --firewall)
                add_selected_module "firewall"
                shift
                ;;
            --security)
                add_selected_module "security"
                add_selected_module "firewall"
                shift
                ;;
            --logs)
                add_selected_module "logs"
                shift
                ;;
            --ai)
                add_selected_module "ai"
                shift
                ;;
            --ollama)
                add_selected_module "ollama"
                shift
                ;;
            --module)
                require_option_value "$1" "${2:-}"
                add_selected_module "$2"
                shift 2
                ;;
            --module=*)
                add_selected_module "${1#*=}"
                shift
                ;;
            --modules)
                require_option_value "$1" "${2:-}"
                parse_module_list "$2"
                shift 2
                ;;
            --modules=*)
                parse_module_list "${1#*=}"
                shift
                ;;
            --terminal)
                CLI_OUTPUT_FORMAT_SET=1
                TERMINAL_OUTPUT_DISABLED=0
                add_output_format "terminal"
                shift
                ;;
            --no-terminal)
                CLI_OUTPUT_FORMAT_SET=1
                TERMINAL_OUTPUT_DISABLED=1
                remove_output_format "terminal"
                shift
                ;;
            --txt)
                CLI_OUTPUT_FORMAT_SET=1
                add_output_format "txt"
                shift
                ;;
            --json)
                CLI_OUTPUT_FORMAT_SET=1
                add_output_format "json"
                shift
                ;;
            --html)
                CLI_OUTPUT_FORMAT_SET=1
                add_output_format "html"
                shift
                ;;
            --config)
                require_option_value "$1" "${2:-}"
                CONFIG_FILE="$2"
                CLI_CONFIG_FILE_SET=1
                shift 2
                ;;
            --config=*)
                CONFIG_FILE="${1#*=}"
                CLI_CONFIG_FILE_SET=1
                shift
                ;;
            --thresholds)
                require_option_value "$1" "${2:-}"
                THRESHOLDS_FILE="$2"
                CLI_THRESHOLDS_FILE_SET=1
                shift 2
                ;;
            --thresholds=*)
                THRESHOLDS_FILE="${1#*=}"
                CLI_THRESHOLDS_FILE_SET=1
                shift
                ;;
            --output-dir)
                require_option_value "$1" "${2:-}"
                OUTPUT_DIR="$2"
                CLI_OUTPUT_DIR_SET=1
                shift 2
                ;;
            --output-dir=*)
                OUTPUT_DIR="${1#*=}"
                CLI_OUTPUT_DIR_SET=1
                shift
                ;;
            --no-color)
                NO_COLOR=1
                CLI_NO_COLOR_SET=1
                shift
                ;;
            --verbose)
                VERBOSE=1
                CLI_VERBOSE_SET=1
                shift
                ;;
            --quiet)
                QUIET=1
                CLI_QUIET_SET=1
                shift
                ;;
            --non-interactive)
                NON_INTERACTIVE=1
                CLI_NON_INTERACTIVE_SET=1
                shift
                ;;
            --no-sudo)
                USE_SUDO=0
                CLI_USE_SUDO_SET=1
                shift
                ;;
            --keep-temp)
                KEEP_TEMP=1
                CLI_KEEP_TEMP_SET=1
                shift
                ;;
            --list-modules)
                LIST_MODULES=1
                shift
                ;;
            --self-test)
                RUN_SELF_TEST=1
                shift
                ;;
            --version|-V)
                SHOW_VERSION=1
                shift
                ;;
            --help|-h)
                SHOW_HELP=1
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                bootstrap_print_error "Opção desconhecida: $1"
                bootstrap_print_error "Use --help para consultar as opções."
                exit "$EXIT_INVALID_ARGUMENT"
                ;;
            *)
                bootstrap_print_error "Argumento inesperado: $1"
                exit "$EXIT_INVALID_ARGUMENT"
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Ambiente
# ---------------------------------------------------------------------------

validate_runtime_environment() {
    if [[ -z "${BASH_VERSION:-}" ]]; then
        bootstrap_print_error "Este programa deve ser executado com Bash."
        exit "$EXIT_GENERAL_ERROR"
    fi

    if ((BASH_VERSINFO[0] < 4)) ||
        ((BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4)); then

        bootstrap_print_error \
            "Bash 4.4 ou superior é necessário. Versão atual: ${BASH_VERSION}"

        exit "$EXIT_DEPENDENCY_ERROR"
    fi

    if [[ ! -d "$PROJECT_ROOT" ]]; then
        bootstrap_print_error \
            "Diretório do projeto não encontrado: ${PROJECT_ROOT}"

        exit "$EXIT_GENERAL_ERROR"
    fi

    if [[ "$(uname -s 2>/dev/null || true)" != "Linux" ]]; then
        bootstrap_print_error "Somente sistemas Linux são suportados."
        exit "$EXIT_UNSUPPORTED"
    fi
}

validate_option_combinations() {
    if ((VERBOSE == 1 && QUIET == 1)); then
        bootstrap_print_error \
            "--verbose e --quiet não podem ser usados juntos."

        exit "$EXIT_INVALID_ARGUMENT"
    fi

    if ((NO_COLOR == 1)); then
        export NO_COLOR=1
    fi

    if ((NON_INTERACTIVE == 1)); then
        export DEBIAN_FRONTEND="noninteractive"
    fi
}

# ---------------------------------------------------------------------------
# Carregamento de bibliotecas
# ---------------------------------------------------------------------------

source_file_safely() {
    local file_path="${1:-}"
    local file_description="${2:-arquivo}"

    if [[ ! -f "$file_path" ]]; then
        bootstrap_print_error \
            "${file_description} não encontrado: ${file_path}"

        return 1
    fi

    if [[ ! -r "$file_path" ]]; then
        bootstrap_print_error \
            "${file_description} sem permissão de leitura: ${file_path}"

        return 1
    fi

    # shellcheck disable=SC1090
    source "$file_path"
}

load_core_libraries() {
    local library_file
    local library_path

    for library_file in "${CORE_LIBRARY_FILES[@]}"; do
        library_path="${LIB_DIR}/${library_file}"

        if ! source_file_safely \
            "$library_path" \
            "Biblioteca principal"; then

            bootstrap_print_error \
                "Biblioteca necessária ausente: ${library_file}"

            exit "$EXIT_DEPENDENCY_ERROR"
        fi
    done
}

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------

load_configuration() {
    if ! declare -F config_load_all >/dev/null 2>&1; then
        bootstrap_print_error \
            "A função config_load_all não foi carregada."

        exit "$EXIT_CONFIGURATION_ERROR"
    fi

    if ! config_load_all "$CONFIG_FILE" "$THRESHOLDS_FILE"; then
        bootstrap_print_error \
            "Falha ao carregar os arquivos de configuração."

        exit "$EXIT_CONFIGURATION_ERROR"
    fi
}

apply_configured_flags() {
    if ((CLI_NON_INTERACTIVE_SET == 0)); then
        NON_INTERACTIVE="$(
            config_get "HC_NON_INTERACTIVE" "$NON_INTERACTIVE"
        )"
    fi

    if ((CLI_USE_SUDO_SET == 0)); then
        USE_SUDO="$(
            config_get "HC_USE_SUDO" "$USE_SUDO"
        )"
    fi

    if ((CLI_KEEP_TEMP_SET == 0)); then
        KEEP_TEMP="$(
            config_get "HC_KEEP_TEMP_FILES" "$KEEP_TEMP"
        )"
    fi

    if ((NON_INTERACTIVE == 1)); then
        export DEBIAN_FRONTEND="noninteractive"
    fi

    export NON_INTERACTIVE
    export USE_SUDO
    export KEEP_TEMP
}

apply_configured_directories() {
    local configured_reports
    local configured_logs
    local configured_temp

    if ((CLI_OUTPUT_DIR_SET == 0)); then
        configured_reports="$(
            config_get "HC_REPORTS_DIRECTORY" "reports"
        )"

        OUTPUT_DIR="$(resolve_project_path "$configured_reports")"
    fi

    configured_logs="$(
        config_get "HC_LOGS_DIRECTORY" "logs"
    )"

    LOGS_DIR="$(resolve_project_path "$configured_logs")"

    configured_temp="$(
        config_get "HC_TEMP_DIRECTORY" ""
    )"

    if [[ -n "$configured_temp" ]]; then
        TMPDIR="$(resolve_project_path "$configured_temp")"
        export TMPDIR
    fi
}

apply_configured_run_mode() {
    if ((CLI_RUN_MODE_SET == 0)) &&
        [[ -z "$RUN_MODE" ]] &&
        ((${#SELECTED_MODULES[@]} == 0)); then

        RUN_MODE="$(
            config_get "HC_DEFAULT_RUN_MODE" "quick"
        )"
    fi
}

apply_configured_output_formats() {
    local configured_formats
    local format
    local -a format_items=()

    if ((CLI_OUTPUT_FORMAT_SET == 1)); then
        return 0
    fi

    configured_formats="$(
        config_get \
            "HC_DEFAULT_OUTPUT_FORMATS" \
            "terminal,txt"
    )"

    IFS=',' read -r -a format_items <<<"$configured_formats"

    for format in "${format_items[@]}"; do
        format="${format//[[:space:]]/}"

        if [[ -n "$format" ]]; then
            add_output_format "$format"
        fi
    done

    if [[ "$(config_get "HC_ENABLE_TERMINAL_OUTPUT" "1")" != "1" ]]; then
        remove_output_format "terminal"
    fi

    if [[ "$(config_get "HC_ENABLE_TXT_REPORT" "1")" == "1" ]]; then
        add_output_format "txt"
    else
        remove_output_format "txt"
    fi

    if [[ "$(config_get "HC_ENABLE_JSON_REPORT" "0")" == "1" ]]; then
        add_output_format "json"
    else
        remove_output_format "json"
    fi

    if [[ "$(config_get "HC_ENABLE_HTML_REPORT" "0")" == "1" ]]; then
        add_output_format "html"
    else
        remove_output_format "html"
    fi
}

apply_configuration() {
    apply_configured_flags
    apply_configured_directories
    apply_configured_run_mode
    apply_configured_output_formats

    OUTPUT_DIR="$(resolve_project_path "$OUTPUT_DIR")"

    export CONFIG_FILE
    export THRESHOLDS_FILE
    export OUTPUT_DIR
    export LOGS_DIR
    export RUN_MODE
}

# ---------------------------------------------------------------------------
# Seleção de módulos
# ---------------------------------------------------------------------------

apply_mode_modules() {
    local module

    case "$RUN_MODE" in
        quick)
            for module in "${QUICK_MODULES[@]}"; do
                add_selected_module "$module"
            done
            ;;
        full)
            for module in "${FULL_MODULES[@]}"; do
                add_selected_module "$module"
            done
            ;;
        custom|"")
            ;;
        *)
            bootstrap_print_error \
                "Modo de execução inválido: ${RUN_MODE}"

            exit "$EXIT_CONFIGURATION_ERROR"
            ;;
    esac
}

apply_default_selection() {
    if [[ -z "$RUN_MODE" ]] &&
        ((${#SELECTED_MODULES[@]} == 0)); then

        RUN_MODE="quick"
    fi

    apply_mode_modules
}

apply_default_output_formats() {
    if ((${#OUTPUT_FORMATS[@]} == 0)); then
        if ((TERMINAL_OUTPUT_DISABLED == 0)); then
            add_output_format "terminal"
        fi

        add_output_format "txt"
    fi
}

# ---------------------------------------------------------------------------
# Diretórios da execução
# ---------------------------------------------------------------------------

prepare_directories() {
    local create_subdirectory
    local report_directory_mode
    local report_file_mode
    local log_directory_mode
    local log_file_mode

    create_subdirectory="$(
        config_get "HC_CREATE_EXECUTION_SUBDIRECTORY" "1"
    )"

    report_directory_mode="$(
        config_get "HC_REPORT_DIRECTORY_MODE" "0750"
    )"

    report_file_mode="$(
        config_get "HC_REPORT_FILE_MODE" "0640"
    )"

    log_directory_mode="$(
        config_get "HC_LOG_DIRECTORY_MODE" "0750"
    )"

    log_file_mode="$(
        config_get "HC_LOG_FILE_MODE" "0640"
    )"

    if ! mkdir -p -- "$OUTPUT_DIR"; then
        bootstrap_print_error \
            "Não foi possível criar o diretório de relatórios: ${OUTPUT_DIR}"

        exit "$EXIT_PERMISSION_ERROR"
    fi

    chmod "$report_directory_mode" "$OUTPUT_DIR" 2>/dev/null || true

    if [[ "$create_subdirectory" == "1" ]]; then
        CURRENT_REPORT_DIR="${OUTPUT_DIR}/${RUN_ID}"
    else
        CURRENT_REPORT_DIR="$OUTPUT_DIR"
    fi

    if ! mkdir -p -- "$CURRENT_REPORT_DIR"; then
        bootstrap_print_error \
            "Não foi possível criar o diretório da execução: ${CURRENT_REPORT_DIR}"

        exit "$EXIT_PERMISSION_ERROR"
    fi

    chmod "$report_directory_mode" "$CURRENT_REPORT_DIR" 2>/dev/null || true

    if ! mkdir -p -- "$LOGS_DIR"; then
        bootstrap_print_error \
            "Não foi possível criar o diretório de logs: ${LOGS_DIR}"

        exit "$EXIT_PERMISSION_ERROR"
    fi

    chmod "$log_directory_mode" "$LOGS_DIR" 2>/dev/null || true

    CURRENT_LOG_FILE="${LOGS_DIR}/healthcheck_${RUN_ID}.log"

    if ! touch -- "$CURRENT_LOG_FILE"; then
        bootstrap_print_error \
            "Não foi possível criar o arquivo de log: ${CURRENT_LOG_FILE}"

        exit "$EXIT_PERMISSION_ERROR"
    fi

    chmod "$log_file_mode" "$CURRENT_LOG_FILE" 2>/dev/null || true

    if [[ -n "${TMPDIR:-}" ]]; then
        mkdir -p -- "$TMPDIR"
    fi

    TEMP_ROOT="$(
        mktemp -d \
            "${TMPDIR:-/tmp}/${PROGRAM_NAME}.${RUN_ID}.XXXXXX"
    )"

    export PROGRAM_NAME
    export PROGRAM_VERSION
    export PROGRAM_DESCRIPTION
    export PROJECT_ROOT
    export CONFIG_DIR
    export LIB_DIR
    export REPORTS_DIR
    export LOGS_DIR
    export TEMPLATES_DIR
    export ASSETS_DIR
    export TESTS_DIR
    export CONFIG_FILE
    export THRESHOLDS_FILE
    export OUTPUT_DIR
    export CURRENT_REPORT_DIR
    export CURRENT_LOG_FILE
    export TEMP_ROOT
    export RUN_ID
    export START_TIMESTAMP
    export START_EPOCH
    export NO_COLOR
    export VERBOSE
    export QUIET
    export NON_INTERACTIVE
    export USE_SUDO
    export KEEP_TEMP

    HC_LOG_FILE="$CURRENT_LOG_FILE"
    HC_LOG_FILE_MODE="$report_file_mode"

    export HC_LOG_FILE
    export HC_LOG_FILE_MODE
}

# ---------------------------------------------------------------------------
# Sinais e limpeza
# ---------------------------------------------------------------------------

cleanup() {
    local exit_code=$?

    trap - EXIT INT TERM HUP

    if declare -F logger_shutdown >/dev/null 2>&1; then
        if declare -F logger_is_initialized >/dev/null 2>&1 &&
            logger_is_initialized; then

            logger_shutdown || true
        fi
    fi

    if [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]]; then
        if ((KEEP_TEMP == 1)); then
            bootstrap_print_warning \
                "Arquivos temporários preservados em: ${TEMP_ROOT}"
        else
            rm -rf -- "$TEMP_ROOT"
        fi
    fi

    exit "$exit_code"
}

handle_interrupt() {
    local signal="${1:-INT}"

    if declare -F logger_error >/dev/null 2>&1; then
        logger_error "Execução interrompida pelo sinal ${signal}."
    else
        bootstrap_print_error \
            "Execução interrompida pelo sinal ${signal}."
    fi

    exit "$EXIT_INTERRUPTED"
}

register_signal_handlers() {
    trap cleanup EXIT
    trap 'handle_interrupt INT' INT
    trap 'handle_interrupt TERM' TERM
    trap 'handle_interrupt HUP' HUP
}

# ---------------------------------------------------------------------------
# Inicialização
# ---------------------------------------------------------------------------

initialize_runtime() {
    logger_initialize

    if ! dependencies_initialize; then
        logger_error \
            "Uma ou mais dependências obrigatórias estão ausentes."

        return "$EXIT_DEPENDENCY_ERROR"
    fi

    collector_initialize
}

# ---------------------------------------------------------------------------
# Cabeçalho
# ---------------------------------------------------------------------------

terminal_output_is_enabled() {
    array_contains "terminal" "${OUTPUT_FORMATS[@]}"
}

print_header() {
    if ((QUIET == 1)) || ! terminal_output_is_enabled; then
        return 0
    fi

    if declare -F ui_print_header >/dev/null 2>&1; then
        ui_print_header \
            "$PROGRAM_NAME" \
            "$PROGRAM_VERSION" \
            "$RUN_ID"

        printf 'Modo:       %s\n' "${RUN_MODE:-custom}"
        printf 'Host:       %s\n' \
            "$(hostname -f 2>/dev/null || hostname)"
        printf 'Início:     %s\n' "$START_TIMESTAMP"
        printf 'Relatórios: %s\n\n' "$CURRENT_REPORT_DIR"

        return 0
    fi

    printf '\n%s %s\n' "$PROGRAM_NAME" "$PROGRAM_VERSION"
    printf '%s\n\n' "$PROGRAM_DESCRIPTION"
}

# ---------------------------------------------------------------------------
# Módulos
# ---------------------------------------------------------------------------

load_module() {
    local module="${1:-}"
    local module_file
    local module_path

    if ! is_known_module "$module"; then
        logger_error "Módulo desconhecido solicitado: ${module}"
        FAILED_MODULES+=("$module")
        return 1
    fi

    module_file="${MODULE_FILES[$module]}"
    module_path="${LIB_DIR}/${module_file}"

    if [[ ! -f "$module_path" ]]; then
        if [[ "${MODULE_REQUIRED[$module]}" == "1" ]]; then
            logger_error \
                "Módulo obrigatório não encontrado: ${module_path}"

            FAILED_MODULES+=("$module")
            return 1
        fi

        logger_warning \
            "Módulo opcional não encontrado: ${module_path}"

        SKIPPED_MODULES+=("$module")
        return 2
    fi

    if ! source_file_safely \
        "$module_path" \
        "Módulo ${module}"; then

        logger_error "Falha ao carregar o módulo: ${module}"
        FAILED_MODULES+=("$module")
        return 1
    fi

    if ! array_contains "$module" "${LOADED_MODULES[@]}"; then
        LOADED_MODULES+=("$module")
    fi

    logger_debug "Módulo carregado: ${module}"
    return 0
}

execute_module() {
    local module="${1:-}"
    local function_name
    local load_result=0
    local module_status="${HC_STATUS_OK:-OK}"
    local module_message="Coleta concluída."

    if ! module_is_enabled "$module"; then
        logger_info \
            "Módulo desabilitado pela configuração: ${module}"

        SKIPPED_MODULES+=("$module")

        collector_module_skip \
            "$module" \
            "Módulo desabilitado pela configuração." \
            "$(module_label "$module")"

        return 0
    fi

    if load_module "$module"; then
        load_result=0
    else
        load_result=$?
    fi

    case "$load_result" in
        0)
            ;;
        2)
            collector_module_skip \
                "$module" \
                "Arquivo do módulo não disponível." \
                "$(module_label "$module")"

            return 0
            ;;
        *)
            collector_module_error \
                "$module" \
                "Não foi possível carregar o módulo."

            if [[ "${MODULE_REQUIRED[$module]}" == "1" ]]; then
                return 1
            fi

            return 0
            ;;
    esac

    function_name="${MODULE_FUNCTIONS[$module]:-}"

    if [[ -z "$function_name" ]]; then
        logger_error \
            "Função principal não definida para o módulo: ${module}"

        FAILED_MODULES+=("$module")

        collector_module_error \
            "$module" \
            "Função principal não definida."

        return 1
    fi

    if ! declare -F "$function_name" >/dev/null 2>&1; then
        logger_error \
            "Função ${function_name} não encontrada no módulo ${module}"

        FAILED_MODULES+=("$module")

        collector_module_error \
            "$module" \
            "Função ${function_name} não encontrada."

        return 1
    fi

    collector_module_start \
        "$module" \
        "$(module_label "$module")"

    logger_info "Iniciando módulo: ${module}"

    if "$function_name"; then
        COMPLETED_MODULES+=("$module")

        module_status="$(
            collector_module_get_status "$module"
        )"

        if [[ "$module_status" == "${HC_STATUS_UNKNOWN:-UNKNOWN}" ]]; then
            module_status="${HC_STATUS_OK:-OK}"
        fi

        collector_module_finish \
            "$module" \
            "$module_status" \
            "$module_message"

        logger_info \
            "Módulo concluído: ${module} | status=${module_status}"

        return 0
    fi

    FAILED_MODULES+=("$module")

    collector_module_error \
        "$module" \
        "Falha durante a execução do módulo."

    collector_module_finish \
        "$module" \
        "${HC_STATUS_CRITICAL:-CRITICAL}" \
        "Falha durante a coleta."

    logger_error \
        "Falha durante a execução do módulo: ${module}"

    if [[ "${MODULE_REQUIRED[$module]}" == "1" ]]; then
        return 1
    fi

    return 0
}

execute_selected_modules() {
    local module
    local required_failure=0
    local continue_required
    local continue_optional

    continue_required="$(
        config_get \
            "HC_CONTINUE_ON_REQUIRED_MODULE_FAILURE" \
            "0"
    )"

    continue_optional="$(
        config_get \
            "HC_CONTINUE_ON_OPTIONAL_MODULE_FAILURE" \
            "1"
    )"

    for module in "${SELECTED_MODULES[@]}"; do
        if execute_module "$module"; then
            continue
        fi

        if [[ "${MODULE_REQUIRED[$module]}" == "1" ]]; then
            required_failure=1

            if [[ "$continue_required" != "1" ]]; then
                logger_error \
                    "Execução interrompida após falha obrigatória: ${module}"

                break
            fi
        elif [[ "$continue_optional" != "1" ]]; then
            logger_error \
                "Execução interrompida após falha opcional: ${module}"

            break
        fi
    done

    return "$required_failure"
}

# ---------------------------------------------------------------------------
# Relatórios
# ---------------------------------------------------------------------------

load_report_library() {
    local format="${1:-}"
    local report_file
    local report_path

    case "$format" in
        terminal)
            return 0
            ;;
        txt)
            report_file="report_txt.sh"
            ;;
        json)
            report_file="report_json.sh"
            ;;
        html)
            report_file="report_html.sh"
            ;;
        *)
            logger_error \
                "Formato de relatório inválido: ${format}"

            return 1
            ;;
    esac

    report_path="${LIB_DIR}/${report_file}"

    if [[ ! -f "$report_path" ]]; then
        logger_error \
            "Biblioteca de relatório não encontrada: ${report_path}"

        return 1
    fi

    source_file_safely \
        "$report_path" \
        "Biblioteca de relatório ${format}"
}

generate_report() {
    local format="${1:-}"
    local function_name
    local output_file

    case "$format" in
        terminal)
            return 0
            ;;
        txt)
            function_name="report_txt_generate"
            output_file="${CURRENT_REPORT_DIR}/report.txt"
            ;;
        json)
            function_name="report_json_generate"
            output_file="${CURRENT_REPORT_DIR}/report.json"
            ;;
        html)
            function_name="report_html_generate"
            output_file="${CURRENT_REPORT_DIR}/report.html"
            ;;
        *)
            logger_error "Formato não suportado: ${format}"
            return 1
            ;;
    esac

    if ! load_report_library "$format"; then
        return 1
    fi

    if ! declare -F "$function_name" >/dev/null 2>&1; then
        logger_error \
            "Função de relatório ausente: ${function_name}"

        return 1
    fi

    logger_info \
        "Gerando relatório ${format^^}: ${output_file}"

    if "$function_name" "$output_file"; then
        logger_info \
            "Relatório ${format^^} gerado com sucesso"

        return 0
    fi

    logger_error \
        "Falha ao gerar relatório ${format^^}"

    return 1
}

generate_selected_reports() {
    local format
    local report_failure=0

    for format in "${OUTPUT_FORMATS[@]}"; do
        if ! generate_report "$format"; then
            report_failure=1
        fi
    done

    return "$report_failure"
}

# ---------------------------------------------------------------------------
# Autoavaliação
# ---------------------------------------------------------------------------

run_library_validation() {
    local function_name="${1:-}"
    local label="${2:-}"

    if ! declare -F "$function_name" >/dev/null 2>&1; then
        printf '%-45s %s\n' "$label" "FALHA"
        return 1
    fi

    if "$function_name" >/dev/null; then
        printf '%-45s %s\n' "$label" "OK"
        return 0
    fi

    printf '%-45s %s\n' "$label" "FALHA"
    return 1
}

run_installation_self_test() {
    local failure=0
    local library_file
    local library_path
    local module
    local module_path

    printf 'Validação da instalação do %s\n\n' "$PROGRAM_NAME"

    printf '%-45s %s\n' "Item" "Resultado"
    printf '%-45s %s\n' \
        "---------------------------------------------" \
        "----------"

    if [[ -x "$SCRIPT_PATH" ]]; then
        printf '%-45s %s\n' "healthcheck.sh executável" "OK"
    else
        printf '%-45s %s\n' "healthcheck.sh executável" "FALHA"
        failure=1
    fi

    for library_file in "${CORE_LIBRARY_FILES[@]}"; do
        library_path="${LIB_DIR}/${library_file}"

        if [[ -r "$library_path" ]]; then
            printf '%-45s %s\n' \
                "lib/${library_file}" \
                "OK"
        else
            printf '%-45s %s\n' \
                "lib/${library_file}" \
                "FALHA"

            failure=1
        fi
    done

    if [[ -r "$CONFIG_FILE" ]]; then
        printf '%-45s %s\n' \
            "config/healthcheck.conf" \
            "OK"
    else
        printf '%-45s %s\n' \
            "config/healthcheck.conf" \
            "FALHA"

        failure=1
    fi

    if [[ -r "$THRESHOLDS_FILE" ]]; then
        printf '%-45s %s\n' \
            "config/thresholds.conf" \
            "OK"
    else
        printf '%-45s %s\n' \
            "config/thresholds.conf" \
            "FALHA"

        failure=1
    fi

    printf '\nValidações internas\n'

    run_library_validation \
        "hc_constants_validate" \
        "constants.sh" || failure=1

    run_library_validation \
        "colors_validate" \
        "colors.sh" || failure=1

    run_library_validation \
        "errors_validate" \
        "errors.sh" || failure=1

    run_library_validation \
        "utils_validate" \
        "utils.sh" || failure=1

    run_library_validation \
        "logger_validate" \
        "logger.sh" || failure=1

    run_library_validation \
        "config_validate" \
        "config.sh" || failure=1

    run_library_validation \
        "dependencies_validate" \
        "dependencies.sh" || failure=1

    run_library_validation \
        "collector_validate" \
        "collector.sh" || failure=1

    printf '\nMódulos funcionais\n'

    for module in "${FULL_MODULES[@]}"; do
        module_path="${LIB_DIR}/${MODULE_FILES[$module]}"

        if [[ -r "$module_path" ]]; then
            printf '%-45s %s\n' \
                "módulo ${module}" \
                "OK"
        elif [[ "${MODULE_REQUIRED[$module]}" == "1" ]]; then
            printf '%-45s %s\n' \
                "módulo ${module}" \
                "PENDENTE"
        else
            printf '%-45s %s\n' \
                "módulo ${module}" \
                "OPCIONAL"
        fi
    done

    printf '\n'

    if ((failure == 0)); then
        printf 'Fundação validada sem falhas.\n'
        return 0
    fi

    printf 'A fundação possui uma ou mais falhas.\n'
    return 1
}

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------

print_execution_summary() {
    local end_epoch
    local duration

    end_epoch="$(date '+%s')"
    duration=$((end_epoch - START_EPOCH))

    if ((QUIET == 1)) || ! terminal_output_is_enabled; then
        return 0
    fi

    printf '\nResumo da execução\n'
    printf '  Status geral:         %s\n' \
        "${HC_COLLECTOR_OVERALL_STATUS:-UNKNOWN}"
    printf '  Duração:              %ss\n' "$duration"
    printf '  Módulos selecionados: %s\n' \
        "${#SELECTED_MODULES[@]}"
    printf '  Módulos carregados:   %s\n' \
        "${#LOADED_MODULES[@]}"
    printf '  Módulos concluídos:   %s\n' \
        "${#COMPLETED_MODULES[@]}"
    printf '  Módulos ignorados:    %s\n' \
        "${#SKIPPED_MODULES[@]}"
    printf '  Módulos com falha:    %s\n' \
        "${#FAILED_MODULES[@]}"
    printf '  Relatórios:           %s\n' \
        "$CURRENT_REPORT_DIR"
    printf '  Log:                  %s\n' \
        "$CURRENT_LOG_FILE"

    if ((${#FAILED_MODULES[@]} > 0)); then
        printf '  Falhas:               %s\n' \
            "$(IFS=','; printf '%s' "${FAILED_MODULES[*]}")"
    fi

    if ((${#SKIPPED_MODULES[@]} > 0)); then
        printf '  Ignorados:            %s\n' \
            "$(IFS=','; printf '%s' "${SKIPPED_MODULES[*]}")"
    fi

    printf '\n'
}

# ---------------------------------------------------------------------------
# Função principal
# ---------------------------------------------------------------------------

main() {
    local module_failure=0
    local report_failure=0

    parse_arguments "$@"

    if ((SHOW_HELP == 1)); then
        print_help
        return "$EXIT_SUCCESS"
    fi

    if ((SHOW_VERSION == 1)); then
        print_version
        return "$EXIT_SUCCESS"
    fi

    if ((LIST_MODULES == 1)); then
        list_available_modules
        return "$EXIT_SUCCESS"
    fi

    validate_option_combinations
    validate_runtime_environment
    normalize_runtime_paths

    load_core_libraries
    load_configuration
    apply_configuration

    validate_option_combinations
    apply_default_selection
    apply_default_output_formats

    if ((RUN_SELF_TEST == 1)); then
        run_installation_self_test
        return $?
    fi

    prepare_directories
    register_signal_handlers

    if ! initialize_runtime; then
        bootstrap_print_error \
            "Falha ao inicializar o ambiente de execução."

        return "$EXIT_DEPENDENCY_ERROR"
    fi

    logger_info \
        "Início da execução ${RUN_ID} | versão=${PROGRAM_VERSION} | modo=${RUN_MODE}"

    print_header

    if ! execute_selected_modules; then
        module_failure=1
    fi

    collector_finalize

    if ! generate_selected_reports; then
        report_failure=1
    fi

    print_execution_summary

    if ((module_failure == 1)); then
        logger_error \
            "Execução concluída com falha de módulo obrigatório"

        return "$EXIT_MODULE_ERROR"
    fi

    if ((report_failure == 1)); then
        logger_error \
            "Execução concluída com falha de relatório"

        return "$EXIT_REPORT_ERROR"
    fi

    logger_info \
        "Execução concluída | status=${HC_COLLECTOR_OVERALL_STATUS}"

    return "$EXIT_SUCCESS"
}

main "$@"
