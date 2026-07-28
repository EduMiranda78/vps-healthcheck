#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

readonly TEST_PROGRAM_NAME="vps-healthcheck test runner"
readonly TEST_PROGRAM_VERSION="0.1.0"

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(
    cd -- "$(dirname -- "$SCRIPT_PATH")" >/dev/null 2>&1
    pwd -P
)"

PROJECT_ROOT="$(
    cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1
    pwd -P
)"

LIB_DIR="${PROJECT_ROOT}/lib"
CONFIG_DIR="${PROJECT_ROOT}/config"
TESTS_DIR="${PROJECT_ROOT}/tests"

CONFIG_FILE="${CONFIG_DIR}/healthcheck.conf"
THRESHOLDS_FILE="${CONFIG_DIR}/thresholds.conf"

TEST_TEMP_ROOT=""
TEST_LOG_FILE=""

TEST_TOTAL=0
TEST_PASSED=0
TEST_FAILED=0
TEST_SKIPPED=0

VERBOSE=0
STOP_ON_FAILURE=0
RUN_INTEGRATION_TESTS=1
RUN_LIBRARY_TESTS=1
RUN_FILE_TESTS=1

declare -a TEST_FAILURES=()
declare -a TEST_SKIPS=()

print_help() {
    cat <<EOF
${TEST_PROGRAM_NAME} ${TEST_PROGRAM_VERSION}

USO:
  ./tests/run_tests.sh [OPÇÕES]

OPÇÕES:
  --verbose             Exibe detalhes adicionais.
  --stop-on-failure     Interrompe após a primeira falha.
  --libraries-only      Executa somente os testes das bibliotecas.
  --files-only          Executa somente os testes de arquivos e estrutura.
  --no-integration      Não executa testes de integração.
  --version             Exibe a versão.
  --help                Exibe esta ajuda.
EOF
}

print_version() {
    printf '%s %s\n' \
        "$TEST_PROGRAM_NAME" \
        "$TEST_PROGRAM_VERSION"
}

parse_arguments() {
    while (($# > 0)); do
        case "$1" in
            --verbose)
                VERBOSE=1
                shift
                ;;
            --stop-on-failure)
                STOP_ON_FAILURE=1
                shift
                ;;
            --libraries-only)
                RUN_LIBRARY_TESTS=1
                RUN_FILE_TESTS=0
                RUN_INTEGRATION_TESTS=0
                shift
                ;;
            --files-only)
                RUN_LIBRARY_TESTS=0
                RUN_FILE_TESTS=1
                RUN_INTEGRATION_TESTS=0
                shift
                ;;
            --no-integration)
                RUN_INTEGRATION_TESTS=0
                shift
                ;;
            --version|-V)
                print_version
                exit 0
                ;;
            --help|-h)
                print_help
                exit 0
                ;;
            *)
                printf 'ERRO: opção desconhecida: %s\n' "$1" >&2
                exit 2
                ;;
        esac
    done
}

cleanup() {
    local exit_code=$?

    trap - EXIT INT TERM HUP

    if [[ -n "$TEST_TEMP_ROOT" && -d "$TEST_TEMP_ROOT" ]]; then
        rm -rf -- "$TEST_TEMP_ROOT"
    fi

    exit "$exit_code"
}

handle_interrupt() {
    printf '\nTestes interrompidos.\n' >&2
    exit 130
}

register_traps() {
    trap cleanup EXIT
    trap handle_interrupt INT TERM HUP
}

prepare_environment() {
    TEST_TEMP_ROOT="$(
        mktemp -d \
            "${TMPDIR:-/tmp}/vps-healthcheck-tests.XXXXXX"
    )"

    TEST_LOG_FILE="${TEST_TEMP_ROOT}/tests.log"

    export PROJECT_ROOT
    export LIB_DIR
    export CONFIG_DIR
    export TESTS_DIR
    export CONFIG_FILE
    export THRESHOLDS_FILE

    export RUN_ID="test_$(date '+%Y%m%d_%H%M%S')_$$"
    export CURRENT_LOG_FILE="$TEST_LOG_FILE"
    export LOGS_DIR="$TEST_TEMP_ROOT"
    export REPORTS_DIR="${TEST_TEMP_ROOT}/reports"
    export CURRENT_REPORT_DIR="${TEST_TEMP_ROOT}/reports/current"
    export TEMP_ROOT="${TEST_TEMP_ROOT}/runtime"

    export NO_COLOR=1
    export QUIET=1
    export VERBOSE
    export NON_INTERACTIVE=1
    export USE_SUDO=0
    export KEEP_TEMP=0

    mkdir -p \
        "$CURRENT_REPORT_DIR" \
        "$TEMP_ROOT"

    touch "$CURRENT_LOG_FILE"
}

print_header() {
    printf '%s %s\n' \
        "$TEST_PROGRAM_NAME" \
        "$TEST_PROGRAM_VERSION"

    printf 'Projeto: %s\n' "$PROJECT_ROOT"
    printf 'Bash:    %s\n\n' "$BASH_VERSION"
}

test_start() {
    local description="${1:-Teste sem descrição}"

    TEST_TOTAL=$((TEST_TOTAL + 1))

    if ((VERBOSE == 1)); then
        printf 'TESTE %03d: %s\n' \
            "$TEST_TOTAL" \
            "$description"
    fi
}

test_pass() {
    local description="${1:-Teste}"

    TEST_PASSED=$((TEST_PASSED + 1))

    printf '[OK]    %s\n' "$description"
}

test_fail() {
    local description="${1:-Teste}"
    local details="${2:-}"

    TEST_FAILED=$((TEST_FAILED + 1))
    TEST_FAILURES+=("$description")

    printf '[FALHA] %s\n' "$description" >&2

    if [[ -n "$details" ]]; then
        printf '        %s\n' "$details" >&2
    fi

    if ((STOP_ON_FAILURE == 1)); then
        print_summary
        exit 1
    fi
}

test_skip() {
    local description="${1:-Teste}"
    local reason="${2:-Não aplicável}"

    TEST_SKIPPED=$((TEST_SKIPPED + 1))
    TEST_SKIPS+=("${description}: ${reason}")

    printf '[PULAR] %s, %s\n' \
        "$description" \
        "$reason"
}

run_command_test() {
    local description="${1:-}"
    shift || true

    local output_file
    local error_file
    local exit_code=0
    local details=""

    test_start "$description"

    output_file="${TEST_TEMP_ROOT}/stdout_${TEST_TOTAL}.txt"
    error_file="${TEST_TEMP_ROOT}/stderr_${TEST_TOTAL}.txt"

    if "$@" >"$output_file" 2>"$error_file"; then
        test_pass "$description"
        return 0
    else
        exit_code=$?
    fi

    details="código=${exit_code}"

    if [[ -s "$error_file" ]]; then
        details+=" | erro=$(tr '\n' ' ' <"$error_file")"
    elif [[ -s "$output_file" ]]; then
        details+=" | saída=$(tr '\n' ' ' <"$output_file")"
    fi

    test_fail "$description" "$details"
    return 1
}

run_function_test() {
    local description="${1:-}"
    local function_name="${2:-}"

    test_start "$description"

    if ! declare -F "$function_name" >/dev/null 2>&1; then
        test_fail \
            "$description" \
            "Função não encontrada: ${function_name}"

        return 1
    fi

    if "$function_name" >/dev/null; then
        test_pass "$description"
        return 0
    fi

    test_fail \
        "$description" \
        "A função ${function_name} retornou falha."

    return 1
}

assert_file_exists() {
    local description="${1:-}"
    local file_path="${2:-}"

    test_start "$description"

    if [[ -f "$file_path" ]]; then
        test_pass "$description"
    else
        test_fail \
            "$description" \
            "Arquivo não encontrado: ${file_path}"
    fi
}

assert_file_readable() {
    local description="${1:-}"
    local file_path="${2:-}"

    test_start "$description"

    if [[ -r "$file_path" ]]; then
        test_pass "$description"
    else
        test_fail \
            "$description" \
            "Arquivo sem permissão de leitura: ${file_path}"
    fi
}

assert_file_executable() {
    local description="${1:-}"
    local file_path="${2:-}"

    test_start "$description"

    if [[ -x "$file_path" ]]; then
        test_pass "$description"
    else
        test_fail \
            "$description" \
            "Arquivo sem permissão de execução: ${file_path}"
    fi
}

load_libraries() {
    # shellcheck disable=SC1091
    source "${LIB_DIR}/constants.sh"

    # shellcheck disable=SC1091
    source "${LIB_DIR}/colors.sh"

    # shellcheck disable=SC1091
    source "${LIB_DIR}/errors.sh"

    # shellcheck disable=SC1091
    source "${LIB_DIR}/utils.sh"

    # shellcheck disable=SC1091
    source "${LIB_DIR}/logger.sh"

    # shellcheck disable=SC1091
    source "${LIB_DIR}/config.sh"

    # shellcheck disable=SC1091
    source "${LIB_DIR}/dependencies.sh"

    # shellcheck disable=SC1091
    source "${LIB_DIR}/collector.sh"
}

run_structure_tests() {
    printf '\nEstrutura e arquivos\n'

    assert_file_exists \
        "healthcheck.sh existe" \
        "${PROJECT_ROOT}/healthcheck.sh"

    assert_file_executable \
        "healthcheck.sh é executável" \
        "${PROJECT_ROOT}/healthcheck.sh"

    assert_file_exists \
        "configuração principal existe" \
        "$CONFIG_FILE"

    assert_file_readable \
        "configuração principal é legível" \
        "$CONFIG_FILE"

    assert_file_exists \
        "arquivo de limites existe" \
        "$THRESHOLDS_FILE"

    assert_file_readable \
        "arquivo de limites é legível" \
        "$THRESHOLDS_FILE"

    local library

    for library in \
        constants.sh \
        colors.sh \
        errors.sh \
        utils.sh \
        logger.sh \
        config.sh \
        dependencies.sh \
        collector.sh; do

        assert_file_exists \
            "lib/${library} existe" \
            "${LIB_DIR}/${library}"

        assert_file_readable \
            "lib/${library} é legível" \
            "${LIB_DIR}/${library}"
    done
}

run_syntax_tests() {
    printf '\nSintaxe Bash\n'

    local file

    run_command_test \
        "sintaxe de healthcheck.sh" \
        bash -n "${PROJECT_ROOT}/healthcheck.sh"

    for file in \
        "${CONFIG_FILE}" \
        "${THRESHOLDS_FILE}" \
        "${LIB_DIR}/constants.sh" \
        "${LIB_DIR}/colors.sh" \
        "${LIB_DIR}/errors.sh" \
        "${LIB_DIR}/utils.sh" \
        "${LIB_DIR}/logger.sh" \
        "${LIB_DIR}/config.sh" \
        "${LIB_DIR}/dependencies.sh" \
        "${LIB_DIR}/collector.sh"; do

        run_command_test \
            "sintaxe de ${file#${PROJECT_ROOT}/}" \
            bash -n "$file"
    done
}

run_library_tests() {
    printf '\nBibliotecas\n'

    load_libraries

    run_function_test \
        "validação de constants.sh" \
        "hc_constants_validate"

    run_command_test \
	"testes especificos de utils.sh" \
	"${TESTS_DIR}/test_utils.sh"
    
    run_function_test \
        "validação de colors.sh" \
        "colors_validate"

    run_function_test \
        "validação de errors.sh" \
        "errors_validate"

    run_function_test \
        "validação de utils.sh" \
        "utils_validate"

    run_function_test \
        "validação de logger.sh" \
        "logger_validate"

    run_function_test \
        "validação de config.sh" \
        "config_validate"

    run_function_test \
        "validação de dependencies.sh" \
        "dependencies_validate"

    run_function_test \
        "validação de collector.sh" \
        "collector_validate"
}

run_configuration_tests() {
    printf '\nConfiguração real\n'

    test_start "carregamento dos arquivos reais"

    if config_load_all \
        "$CONFIG_FILE" \
        "$THRESHOLDS_FILE" >/dev/null; then

        test_pass "carregamento dos arquivos reais"
    else
        test_fail \
            "carregamento dos arquivos reais" \
            "config_load_all retornou falha."
    fi

    test_start "limite de CPU está disponível"

    if [[ "$(config_get HC_CPU_USAGE_WARNING_PERCENT)" == "75" ]]; then
        test_pass "limite de CPU está disponível"
    else
        test_fail \
            "limite de CPU está disponível" \
            "Valor diferente de 75."
    fi

    test_start "configuração de Docker está disponível"

    if [[ "$(config_get HC_DOCKER_ENABLED)" =~ ^[01]$ ]]; then
        test_pass "configuração de Docker está disponível"
    else
        test_fail \
            "configuração de Docker está disponível" \
            "Valor inválido."
    fi
}

run_cli_tests() {
    printf '\nInterface de linha de comando\n'

    run_command_test \
        "--version funciona" \
        "${PROJECT_ROOT}/healthcheck.sh" \
        --version

    run_command_test \
        "--help funciona" \
        "${PROJECT_ROOT}/healthcheck.sh" \
        --help

    run_command_test \
        "--list-modules funciona" \
        "${PROJECT_ROOT}/healthcheck.sh" \
        --list-modules

    run_command_test \
        "--self-test funciona" \
        "${PROJECT_ROOT}/healthcheck.sh" \
        --self-test
}

run_shellcheck_tests() {
    printf '\nAnálise estática\n'

    if ! command -v shellcheck >/dev/null 2>&1; then
        test_start "ShellCheck"
        test_skip \
            "ShellCheck" \
            "comando shellcheck não instalado"
        return 0
    fi

    local -a files=(
        "${PROJECT_ROOT}/healthcheck.sh"
        "${LIB_DIR}/constants.sh"
        "${LIB_DIR}/colors.sh"
        "${LIB_DIR}/errors.sh"
        "${LIB_DIR}/utils.sh"
        "${LIB_DIR}/logger.sh"
        "${LIB_DIR}/config.sh"
        "${LIB_DIR}/dependencies.sh"
        "${LIB_DIR}/collector.sh"
    )

    run_command_test \
        "ShellCheck da fundação" \
        shellcheck \
        --severity=warning \
        "${files[@]}"
}

print_summary() {
    printf '\nResumo dos testes\n'
    printf '  Total:      %s\n' "$TEST_TOTAL"
    printf '  Aprovados:  %s\n' "$TEST_PASSED"
    printf '  Falhas:     %s\n' "$TEST_FAILED"
    printf '  Ignorados:  %s\n' "$TEST_SKIPPED"

    if ((${#TEST_FAILURES[@]} > 0)); then
        printf '\nFalhas registradas:\n'

        printf '  - %s\n' "${TEST_FAILURES[@]}"
    fi

    if ((${#TEST_SKIPS[@]} > 0)) && ((VERBOSE == 1)); then
        printf '\nTestes ignorados:\n'

        printf '  - %s\n' "${TEST_SKIPS[@]}"
    fi

    printf '\n'
}

main() {
    parse_arguments "$@"
    register_traps
    prepare_environment
    print_header

    if ((RUN_FILE_TESTS == 1)); then
        run_structure_tests
        run_syntax_tests
    fi

    if ((RUN_LIBRARY_TESTS == 1)); then
        run_library_tests
        run_configuration_tests
    fi

    if ((RUN_INTEGRATION_TESTS == 1)); then
        run_cli_tests
        run_shellcheck_tests
    fi

    print_summary

    if ((TEST_FAILED > 0)); then
        return 1
    fi

    return 0
}

main "$@"
