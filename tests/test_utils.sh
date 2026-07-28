#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

readonly TEST_NAME="test_utils"
readonly TEST_VERSION="0.1.0"

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

TEST_TEMP_ROOT=""
TEST_TOTAL=0
TEST_PASSED=0
TEST_FAILED=0

declare -a TEST_FAILURES=()

# ---------------------------------------------------------------------------
# Preparação
# ---------------------------------------------------------------------------

prepare_environment() {
    TEST_TEMP_ROOT="$(
        mktemp -d \
            "${TMPDIR:-/tmp}/vps-healthcheck-utils-test.XXXXXX"
    )"

    export PROJECT_ROOT
    export LIB_DIR
    export TEMP_ROOT="${TEST_TEMP_ROOT}/runtime"
    export NO_COLOR=1
    export QUIET=1
    export VERBOSE=0
    export NON_INTERACTIVE=1
    export USE_SUDO=0
    export KEEP_TEMP=0

    mkdir -p "$TEMP_ROOT"
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

load_libraries() {
    # shellcheck disable=SC1091
    source "${LIB_DIR}/constants.sh"

    # shellcheck disable=SC1091
    source "${LIB_DIR}/colors.sh"

    # shellcheck disable=SC1091
    source "${LIB_DIR}/errors.sh"

    # shellcheck disable=SC1091
    source "${LIB_DIR}/utils.sh"
}

# ---------------------------------------------------------------------------
# Infraestrutura de testes
# ---------------------------------------------------------------------------

test_start() {
    TEST_TOTAL=$((TEST_TOTAL + 1))
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
}

assert_equals() {
    local description="${1:-}"
    local expected="${2:-}"
    local actual="${3:-}"

    test_start

    if [[ "$actual" == "$expected" ]]; then
        test_pass "$description"
    else
        test_fail \
            "$description" \
            "esperado='${expected}' obtido='${actual}'"
    fi
}

assert_not_equals() {
    local description="${1:-}"
    local unexpected="${2:-}"
    local actual="${3:-}"

    test_start

    if [[ "$actual" != "$unexpected" ]]; then
        test_pass "$description"
    else
        test_fail \
            "$description" \
            "valor inesperado='${unexpected}'"
    fi
}

assert_true() {
    local description="${1:-}"
    shift || true

    test_start

    if "$@"; then
        test_pass "$description"
    else
        test_fail "$description" "A condição retornou falso."
    fi
}

assert_false() {
    local description="${1:-}"
    shift || true

    test_start

    if "$@"; then
        test_fail "$description" "A condição retornou verdadeiro."
    else
        test_pass "$description"
    fi
}

assert_file_exists() {
    local description="${1:-}"
    local file_path="${2:-}"

    test_start

    if [[ -f "$file_path" ]]; then
        test_pass "$description"
    else
        test_fail \
            "$description" \
            "Arquivo não encontrado: ${file_path}"
    fi
}

assert_directory_exists() {
    local description="${1:-}"
    local directory_path="${2:-}"

    test_start

    if [[ -d "$directory_path" ]]; then
        test_pass "$description"
    else
        test_fail \
            "$description" \
            "Diretório não encontrado: ${directory_path}"
    fi
}

assert_command_success() {
    local description="${1:-}"
    shift || true

    test_start

    if "$@" >/dev/null 2>&1; then
        test_pass "$description"
    else
        test_fail \
            "$description" \
            "O comando retornou falha."
    fi
}

assert_command_failure() {
    local description="${1:-}"
    shift || true

    test_start

    if "$@" >/dev/null 2>&1; then
        test_fail \
            "$description" \
            "O comando deveria falhar."
    else
        test_pass "$description"
    fi
}

# ---------------------------------------------------------------------------
# Testes de validação
# ---------------------------------------------------------------------------

test_numeric_validation() {
    assert_true \
        "utils_is_integer aceita inteiro positivo" \
        utils_is_integer \
        "10"

    assert_true \
        "utils_is_integer aceita inteiro negativo" \
        utils_is_integer \
        "-10"

    assert_false \
        "utils_is_integer rejeita decimal" \
        utils_is_integer \
        "10.5"

    assert_false \
        "utils_is_integer rejeita texto" \
        utils_is_integer \
        "abc"

    assert_true \
        "utils_is_unsigned_integer aceita zero" \
        utils_is_unsigned_integer \
        "0"

    assert_true \
        "utils_is_unsigned_integer aceita inteiro positivo" \
        utils_is_unsigned_integer \
        "100"

    assert_false \
        "utils_is_unsigned_integer rejeita negativo" \
        utils_is_unsigned_integer \
        "-1"

    assert_true \
        "utils_is_decimal aceita inteiro" \
        utils_is_decimal \
        "100"

    assert_true \
        "utils_is_decimal aceita decimal" \
        utils_is_decimal \
        "100.25"

    assert_true \
        "utils_is_decimal aceita decimal negativo" \
        utils_is_decimal \
        "-100.25"

    assert_false \
        "utils_is_decimal rejeita vírgula decimal" \
        utils_is_decimal \
        "100,25"

    assert_true \
        "utils_is_percentage aceita zero" \
        utils_is_percentage \
        "0"

    assert_true \
        "utils_is_percentage aceita cem" \
        utils_is_percentage \
        "100"

    assert_true \
        "utils_is_percentage aceita decimal" \
        utils_is_percentage \
        "99.9"

    assert_false \
        "utils_is_percentage rejeita valor acima de cem" \
        utils_is_percentage \
        "100.1"

    assert_false \
        "utils_is_percentage rejeita valor negativo" \
        utils_is_percentage \
        "-1"
}

test_boolean_validation() {
    assert_true \
        "utils_is_boolean aceita true" \
        utils_is_boolean \
        "true"

    assert_true \
        "utils_is_boolean aceita false" \
        utils_is_boolean \
        "false"

    assert_true \
        "utils_is_boolean aceita sim" \
        utils_is_boolean \
        "sim"

    assert_true \
        "utils_is_boolean aceita não" \
        utils_is_boolean \
        "não"

    assert_true \
        "utils_is_boolean aceita enabled" \
        utils_is_boolean \
        "enabled"

    assert_false \
        "utils_is_boolean rejeita valor desconhecido" \
        utils_is_boolean \
        "talvez"

    assert_equals \
        "utils_boolean_normalize converte yes" \
        "true" \
        "$(utils_boolean_normalize "yes")"

    assert_equals \
        "utils_boolean_normalize converte off" \
        "false" \
        "$(utils_boolean_normalize "off")"

    assert_equals \
        "utils_boolean_to_integer converte true" \
        "1" \
        "$(utils_boolean_to_integer "true")"

    assert_equals \
        "utils_boolean_to_integer converte false" \
        "0" \
        "$(utils_boolean_to_integer "false")"
}

test_network_validation() {
    assert_true \
        "utils_is_ipv4 aceita localhost" \
        utils_is_ipv4 \
        "127.0.0.1"

    assert_true \
        "utils_is_ipv4 aceita endereço privado" \
        utils_is_ipv4 \
        "192.168.1.10"

    assert_false \
        "utils_is_ipv4 rejeita octeto acima de 255" \
        utils_is_ipv4 \
        "256.168.1.10"

    assert_false \
        "utils_is_ipv4 rejeita endereço incompleto" \
        utils_is_ipv4 \
        "192.168.1"

    assert_true \
        "utils_is_ipv6 aceita loopback" \
        utils_is_ipv6 \
        "::1"

    assert_true \
        "utils_is_ipv6 aceita endereço completo" \
        utils_is_ipv6 \
        "2001:0db8:85a3:0000:0000:8a2e:0370:7334"

    assert_false \
        "utils_is_ipv6 rejeita IPv4" \
        utils_is_ipv6 \
        "127.0.0.1"

    assert_true \
        "utils_is_port aceita porta mínima" \
        utils_is_port \
        "1"

    assert_true \
        "utils_is_port aceita porta máxima" \
        utils_is_port \
        "65535"

    assert_false \
        "utils_is_port rejeita zero" \
        utils_is_port \
        "0"

    assert_false \
        "utils_is_port rejeita porta acima do limite" \
        utils_is_port \
        "65536"

    assert_true \
        "utils_is_domain aceita domínio válido" \
        utils_is_domain \
        "example.com"

    assert_true \
        "utils_is_domain aceita subdomínio" \
        utils_is_domain \
        "api.example.com"

    assert_false \
        "utils_is_domain rejeita nome simples" \
        utils_is_domain \
        "localhost"

    assert_true \
        "utils_is_url aceita HTTP" \
        utils_is_url \
        "http://127.0.0.1:8080/health"

    assert_true \
        "utils_is_url aceita HTTPS" \
        utils_is_url \
        "https://example.com/status"

    assert_false \
        "utils_is_url rejeita FTP" \
        utils_is_url \
        "ftp://example.com"
}

# ---------------------------------------------------------------------------
# Testes de strings
# ---------------------------------------------------------------------------

test_string_functions() {
    assert_equals \
        "utils_trim remove espaços laterais" \
        "teste" \
        "$(utils_trim "   teste   ")"

    assert_equals \
        "utils_ltrim remove espaços à esquerda" \
        "teste   " \
        "$(utils_ltrim "   teste   ")"

    assert_equals \
        "utils_rtrim remove espaços à direita" \
        "   teste" \
        "$(utils_rtrim "   teste   ")"

    assert_equals \
        "utils_to_lower converte para minúsculas" \
        "teste" \
        "$(utils_to_lower "TESTE")"

    assert_equals \
        "utils_to_upper converte para maiúsculas" \
        "TESTE" \
        "$(utils_to_upper "teste")"

    assert_equals \
        "utils_capitalize converte primeira letra" \
        "Teste" \
        "$(utils_capitalize "teste")"

    assert_true \
        "utils_starts_with detecta prefixo" \
        utils_starts_with \
        "vps-healthcheck" \
        "vps"

    assert_true \
        "utils_ends_with detecta sufixo" \
        utils_ends_with \
        "healthcheck.sh" \
        ".sh"

    assert_true \
        "utils_contains detecta fragmento" \
        utils_contains \
        "servidor venom-vps" \
        "venom"

    assert_equals \
        "utils_repeat repete caractere" \
        "=====" \
        "$(utils_repeat "=" "5")"

    assert_equals \
        "utils_truncate preserva valor curto" \
        "teste" \
        "$(utils_truncate "teste" "10")"

    assert_equals \
        "utils_truncate reduz valor longo" \
        "abcdefg..." \
        "$(utils_truncate "abcdefghijklmnop" "10")"

    assert_equals \
        "utils_sanitize_single_line remove quebras" \
        "linha 1 linha 2 valor" \
        "$(utils_sanitize_single_line $'linha 1\nlinha 2\tvalor')"

    assert_equals \
        "utils_slugify gera slug ASCII" \
        "relatorio-da-vps" \
        "$(utils_slugify "Relatório da VPS")"

    assert_equals \
        "utils_join_by combina valores" \
        "a,b,c" \
        "$(utils_join_by "," "a" "b" "c")"

    assert_equals \
        "utils_strip_quotes remove aspas duplas" \
        "valor" \
        "$(utils_strip_quotes '"valor"')"

    assert_equals \
        "utils_strip_quotes remove aspas simples" \
        "valor" \
        "$(utils_strip_quotes "'valor'")"

    assert_equals \
        "utils_mask_secret mascara conteúdo" \
        "ab****yz" \
        "$(utils_mask_secret "abcdefyz" "2" "2")"
}

# ---------------------------------------------------------------------------
# Testes numéricos
# ---------------------------------------------------------------------------

test_numeric_functions() {
    assert_equals \
        "utils_min retorna menor valor" \
        "10" \
        "$(utils_min "10" "20")"

    assert_equals \
        "utils_max retorna maior valor" \
        "20" \
        "$(utils_max "10" "20")"

    assert_equals \
        "utils_clamp aplica limite mínimo" \
        "0" \
        "$(utils_clamp "-10" "0" "100")"

    assert_equals \
        "utils_clamp aplica limite máximo" \
        "100" \
        "$(utils_clamp "150" "0" "100")"

    assert_equals \
        "utils_round arredonda decimal" \
        "10.13" \
        "$(utils_round "10.125" "2")"

    assert_equals \
        "utils_safe_divide divide valores" \
        "2.50" \
        "$(utils_safe_divide "5" "2" "2")"

    assert_equals \
        "utils_percentage calcula percentual" \
        "75.0" \
        "$(utils_percentage "750" "1000" "1")"

    assert_true \
        "utils_compare_numbers compara maior" \
        utils_compare_numbers \
        "10" \
        "gt" \
        "5"

    assert_true \
        "utils_compare_numbers compara menor ou igual" \
        utils_compare_numbers \
        "5" \
        "le" \
        "5"

    assert_false \
        "utils_compare_numbers rejeita comparação falsa" \
        utils_compare_numbers \
        "5" \
        "gt" \
        "10"
}

# ---------------------------------------------------------------------------
# Testes de bytes
# ---------------------------------------------------------------------------

test_byte_functions() {
    assert_equals \
        "utils_bytes_to_human converte bytes" \
        "1.00 KiB" \
        "$(utils_bytes_to_human "1024" "2")"

    assert_equals \
        "utils_bytes_to_human converte GiB" \
        "4.00 GiB" \
        "$(utils_bytes_to_human "4294967296" "2")"

    assert_equals \
        "utils_kib_to_bytes converte KiB" \
        "1024" \
        "$(utils_kib_to_bytes "1")"

    assert_equals \
        "utils_mib_to_bytes converte MiB" \
        "1048576" \
        "$(utils_mib_to_bytes "1")"

    assert_equals \
        "utils_gib_to_bytes converte GiB" \
        "1073741824" \
        "$(utils_gib_to_bytes "1")"

    assert_equals \
        "utils_human_to_bytes converte KiB" \
        "1024" \
        "$(utils_human_to_bytes "1KiB")"

    assert_equals \
        "utils_human_to_bytes converte decimal GiB" \
        "1610612736" \
        "$(utils_human_to_bytes "1.5GiB")"
}

# ---------------------------------------------------------------------------
# Testes de tempo
# ---------------------------------------------------------------------------

test_time_functions() {
    local now_epoch
    local timestamp
    local elapsed

    now_epoch="$(utils_now_epoch)"
    timestamp="$(utils_timestamp_filename)"

    assert_true \
        "utils_now_epoch retorna inteiro" \
        utils_is_unsigned_integer \
        "$now_epoch"

    test_start

    if [[ "$timestamp" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        test_pass "utils_timestamp_filename retorna formato correto"
    else
        test_fail \
            "utils_timestamp_filename retorna formato correto" \
            "valor=${timestamp}"
    fi

    assert_equals \
        "utils_seconds_to_duration converte segundos" \
        "1h 1m 1s" \
        "$(utils_seconds_to_duration "3661")"

    assert_equals \
        "utils_seconds_to_duration converte dias" \
        "1d 2h 3m 4s" \
        "$(utils_seconds_to_duration "93784")"

    assert_equals \
        "utils_milliseconds_to_duration mantém milissegundos" \
        "500 ms" \
        "$(utils_milliseconds_to_duration "500")"

    assert_equals \
        "utils_milliseconds_to_duration converte segundos" \
        "1.50 s" \
        "$(utils_milliseconds_to_duration "1500")"

    elapsed="$(utils_elapsed_seconds "100" "150")"

    assert_equals \
        "utils_elapsed_seconds calcula intervalo" \
        "50" \
        "$elapsed"
}

# ---------------------------------------------------------------------------
# Testes de arquivos
# ---------------------------------------------------------------------------

test_file_functions() {
    local test_directory
    local test_file
    local copied_file
    local atomic_file
    local size
    local first_line

    test_directory="${TEST_TEMP_ROOT}/files"
    test_file="${test_directory}/source.txt"
    copied_file="${test_directory}/copy.txt"
    atomic_file="${test_directory}/atomic.txt"

    assert_command_success \
        "utils_ensure_directory cria diretório" \
        utils_ensure_directory \
        "$test_directory" \
        "0750"

    assert_directory_exists \
        "diretório criado existe" \
        "$test_directory"

    assert_command_success \
        "utils_ensure_file cria arquivo" \
        utils_ensure_file \
        "$test_file" \
        "0640"

    assert_file_exists \
        "arquivo criado existe" \
        "$test_file"

    printf 'linha 1\nlinha 2\n' >"$test_file"

    first_line="$(utils_read_first_line "$test_file")"

    assert_equals \
        "utils_read_first_line lê primeira linha" \
        "linha 1" \
        "$first_line"

    size="$(utils_file_size_bytes "$test_file")"

    assert_true \
        "utils_file_size_bytes retorna inteiro" \
        utils_is_unsigned_integer \
        "$size"

    assert_command_success \
        "utils_copy_file_atomic copia arquivo" \
        utils_copy_file_atomic \
        "$test_file" \
        "$copied_file" \
        "0640"

    assert_file_exists \
        "cópia atômica existe" \
        "$copied_file"

    assert_equals \
        "cópia atômica preserva conteúdo" \
        "$(cat "$test_file")" \
        "$(cat "$copied_file")"

    test_start

    if printf 'conteúdo atômico\n' |
        utils_atomic_write "$atomic_file" "0640"; then

        test_pass "utils_atomic_write grava conteúdo"
    else
        test_fail \
            "utils_atomic_write grava conteúdo" \
            "A função retornou falha."
    fi

    assert_equals \
        "utils_atomic_write preserva conteúdo" \
        "conteúdo atômico" \
        "$(cat "$atomic_file")"

    assert_true \
        "utils_file_exists detecta arquivo" \
        utils_file_exists \
        "$atomic_file"

    assert_true \
        "utils_directory_exists detecta diretório" \
        utils_directory_exists \
        "$test_directory"

    assert_true \
        "utils_is_readable detecta leitura" \
        utils_is_readable \
        "$atomic_file"

    assert_true \
        "utils_is_writable detecta escrita" \
        utils_is_writable \
        "$atomic_file"

    assert_command_failure \
        "utils_read_file rejeita arquivo inexistente" \
        utils_read_file \
        "${test_directory}/inexistente.txt"
}

# ---------------------------------------------------------------------------
# Testes de comandos
# ---------------------------------------------------------------------------

test_command_functions() {
    local command_output=""
    local command_error=""
    local command_code=""

    assert_true \
        "utils_command_exists encontra sh" \
        utils_command_exists \
        "sh"

    assert_false \
        "utils_command_exists rejeita comando inexistente" \
        utils_command_exists \
        "comando-inexistente-vps-healthcheck"

    test_start

    if [[ -n "$(utils_command_path "sh")" ]]; then
        test_pass "utils_command_path retorna caminho"
    else
        test_fail \
            "utils_command_path retorna caminho" \
            "Caminho vazio."
    fi

    assert_equals \
        "utils_quote_command escapa argumentos" \
        "printf %s teste\\ com\\ espaço" \
        "$(utils_quote_command printf "%s" "teste com espaço")"

    assert_command_success \
        "utils_run_with_timeout executa comando rápido" \
        utils_run_with_timeout \
        "2" \
        sh \
        -c \
        "exit 0"

    test_start

    if utils_capture_command \
        command_output \
        command_error \
        command_code \
        sh \
        -c \
        'printf "saida"; printf "erro" >&2; exit 7'; then

        if [[ "$command_output" == "saida" &&
            "$command_error" == "erro" &&
            "$command_code" == "7" ]]; then

            test_pass "utils_capture_command captura saída e código"
        else
            test_fail \
                "utils_capture_command captura saída e código" \
                "stdout=${command_output} stderr=${command_error} code=${command_code}"
        fi
    else
        test_fail \
            "utils_capture_command captura saída e código" \
            "A função de captura retornou falha."
    fi
}

# ---------------------------------------------------------------------------
# Testes de arrays
# ---------------------------------------------------------------------------

test_array_functions() {
    local -a input_values=(
        "docker"
        "nginx"
        "docker"
        "ollama"
    )

    local -a unique_values=()
    local -a sorted_values=()

    assert_true \
        "utils_array_contains encontra item" \
        utils_array_contains \
        "nginx" \
        "${input_values[@]}"

    assert_false \
        "utils_array_contains rejeita item ausente" \
        utils_array_contains \
        "redis" \
        "${input_values[@]}"

    utils_array_unique \
        input_values \
        unique_values

    assert_equals \
        "utils_array_unique remove duplicados" \
        "3" \
        "${#unique_values[@]}"

    utils_array_sort \
        unique_values \
        sorted_values

    assert_equals \
        "utils_array_sort ordena primeiro item" \
        "docker" \
        "${sorted_values[0]}"

    assert_equals \
        "utils_array_sort ordena último item" \
        "ollama" \
        "${sorted_values[2]}"
}

# ---------------------------------------------------------------------------
# Testes JSON e HTML
# ---------------------------------------------------------------------------

test_serialization_functions() {
    assert_equals \
        "utils_json_escape escapa aspas e quebra" \
        'a\"b\nc' \
        "$(utils_json_escape $'a"b\nc')"

    assert_equals \
        "utils_json_string adiciona aspas" \
        '"Servidor VPS"' \
        "$(utils_json_string "Servidor VPS")"

    assert_equals \
        "utils_json_boolean converte true" \
        "true" \
        "$(utils_json_boolean "true")"

    assert_equals \
        "utils_json_number_or_null mantém número" \
        "10.5" \
        "$(utils_json_number_or_null "10.5")"

    assert_equals \
        "utils_json_number_or_null converte inválido em null" \
        "null" \
        "$(utils_json_number_or_null "abc")"

    assert_equals \
        "utils_html_escape escapa caracteres especiais" \
        '&lt;teste &amp; servidor&gt;' \
        "$(utils_html_escape "<teste & servidor>")"

    assert_equals \
        "utils_html_attribute_escape remove quebra de linha" \
        'teste &quot;valor&quot;' \
        "$(utils_html_attribute_escape $'teste\n"valor"')"
}

# ---------------------------------------------------------------------------
# Testes de configuração simples
# ---------------------------------------------------------------------------

test_config_functions() {
    local test_config
    local parsed_key=""
    local parsed_value=""
    local -A loaded_values=()

    test_config="${TEST_TEMP_ROOT}/test.conf"

    cat >"$test_config" <<'EOF'
# comentário
TESTE="valor"
NUMERO=10
ATIVO=1
EOF

    test_start

    if utils_parse_config_line \
        'TESTE="valor"' \
        parsed_key \
        parsed_value; then

        if [[ "$parsed_key" == "TESTE" &&
            "$parsed_value" == "valor" ]]; then

            test_pass "utils_parse_config_line interpreta atribuição"
        else
            test_fail \
                "utils_parse_config_line interpreta atribuição" \
                "chave=${parsed_key} valor=${parsed_value}"
        fi
    else
        test_fail \
            "utils_parse_config_line interpreta atribuição" \
            "A função retornou falha."
    fi

    utils_read_key_value_file \
        "$test_config" \
        loaded_values

    assert_equals \
        "utils_read_key_value_file carrega texto" \
        "valor" \
        "${loaded_values[TESTE]}"

    assert_equals \
        "utils_read_key_value_file carrega número" \
        "10" \
        "${loaded_values[NUMERO]}"

    assert_equals \
        "utils_read_key_value_file carrega booleano" \
        "1" \
        "${loaded_values[ATIVO]}"
}

# ---------------------------------------------------------------------------
# Testes de status
# ---------------------------------------------------------------------------

test_status_functions() {
    assert_equals \
        "utils_status_from_high_usage retorna OK" \
        "$HC_STATUS_OK" \
        "$(utils_status_from_high_usage "50" "75" "90")"

    assert_equals \
        "utils_status_from_high_usage retorna WARNING" \
        "$HC_STATUS_WARNING" \
        "$(utils_status_from_high_usage "80" "75" "90")"

    assert_equals \
        "utils_status_from_high_usage retorna CRITICAL" \
        "$HC_STATUS_CRITICAL" \
        "$(utils_status_from_high_usage "95" "75" "90")"

    assert_equals \
        "utils_status_from_low_remaining retorna OK" \
        "$HC_STATUS_OK" \
        "$(utils_status_from_low_remaining "60" "30" "15")"

    assert_equals \
        "utils_status_from_low_remaining retorna WARNING" \
        "$HC_STATUS_WARNING" \
        "$(utils_status_from_low_remaining "20" "30" "15")"

    assert_equals \
        "utils_status_from_low_remaining retorna CRITICAL" \
        "$HC_STATUS_CRITICAL" \
        "$(utils_status_from_low_remaining "10" "30" "15")"
}

# ---------------------------------------------------------------------------
# Teste interno do módulo
# ---------------------------------------------------------------------------

test_internal_validation() {
    assert_command_success \
        "utils_validate conclui sem falhas" \
        utils_validate
}

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------

print_summary() {
    printf '\nResumo de %s\n' "$TEST_NAME"
    printf '  Total:      %s\n' "$TEST_TOTAL"
    printf '  Aprovados:  %s\n' "$TEST_PASSED"
    printf '  Falhas:     %s\n' "$TEST_FAILED"

    if ((${#TEST_FAILURES[@]} > 0)); then
        printf '\nFalhas registradas:\n'
        printf '  - %s\n' "${TEST_FAILURES[@]}"
    fi

    printf '\n'
}

# ---------------------------------------------------------------------------
# Execução principal
# ---------------------------------------------------------------------------

main() {
    register_traps
    prepare_environment
    load_libraries

    printf '%s %s\n\n' "$TEST_NAME" "$TEST_VERSION"

    test_numeric_validation
    test_boolean_validation
    test_network_validation
    test_string_functions
    test_numeric_functions
    test_byte_functions
    test_time_functions
    test_file_functions
    test_command_functions
    test_array_functions
    test_serialization_functions
    test_config_functions
    test_status_functions
    test_internal_validation

    print_summary

    if ((TEST_FAILED > 0)); then
        return 1
    fi

    return 0
}

main "$@"
