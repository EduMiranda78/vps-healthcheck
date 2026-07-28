#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_DEPENDENCIES_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_DEPENDENCIES_LOADED=1

# ---------------------------------------------------------------------------
# Estado interno
# ---------------------------------------------------------------------------

HC_DEPENDENCIES_INITIALIZED=0

declare -ag HC_DEPENDENCIES_REQUIRED=()
declare -ag HC_DEPENDENCIES_OPTIONAL=()
declare -ag HC_DEPENDENCIES_AVAILABLE=()
declare -ag HC_DEPENDENCIES_MISSING_REQUIRED=()
declare -ag HC_DEPENDENCIES_MISSING_OPTIONAL=()

declare -gA HC_DEPENDENCY_PATHS=()
declare -gA HC_DEPENDENCY_VERSIONS=()
declare -gA HC_DEPENDENCY_PACKAGES_DEBIAN=()
declare -gA HC_DEPENDENCY_DESCRIPTIONS=()
declare -gA HC_DEPENDENCY_REQUIRED_FLAGS=()

# ---------------------------------------------------------------------------
# Dependências conhecidas
# ---------------------------------------------------------------------------

dependencies_register_defaults() {
    HC_DEPENDENCIES_REQUIRED=(
        "awk"
        "basename"
        "cat"
        "cut"
        "date"
        "df"
        "dirname"
        "du"
        "find"
        "grep"
        "head"
        "hostname"
        "id"
        "ip"
        "mktemp"
        "mount"
        "ps"
        "sed"
        "sort"
        "ss"
        "stat"
        "tail"
        "tr"
        "uname"
        "uptime"
    )

    HC_DEPENDENCIES_OPTIONAL=(
        "apt-get"
        "curl"
        "dig"
        "docker"
        "fail2ban-client"
        "findmnt"
        "flock"
        "free"
        "getent"
        "hostnamectl"
        "iconv"
        "jq"
        "journalctl"
        "lsof"
        "nginx"
        "openssl"
        "realpath"
        "resolvectl"
        "sudo"
        "systemctl"
        "timeout"
        "ufw"
    )

    HC_DEPENDENCY_PACKAGES_DEBIAN=(
        [awk]="gawk"
        [basename]="coreutils"
        [cat]="coreutils"
        [cut]="coreutils"
        [date]="coreutils"
        [df]="coreutils"
        [dirname]="coreutils"
        [du]="coreutils"
        [find]="findutils"
        [grep]="grep"
        [head]="coreutils"
        [hostname]="hostname"
        [id]="coreutils"
        [ip]="iproute2"
        [mktemp]="coreutils"
        [mount]="mount"
        [ps]="procps"
        [sed]="sed"
        [sort]="coreutils"
        [ss]="iproute2"
        [stat]="coreutils"
        [tail]="coreutils"
        [tr]="coreutils"
        [uname]="coreutils"
        [uptime]="procps"

        [apt-get]="apt"
        [curl]="curl"
        [dig]="dnsutils"
        [docker]="docker.io"
        [fail2ban-client]="fail2ban"
        [findmnt]="util-linux"
        [flock]="util-linux"
        [free]="procps"
        [getent]="libc-bin"
        [hostnamectl]="systemd"
        [iconv]="libc-bin"
        [jq]="jq"
        [journalctl]="systemd"
        [lsof]="lsof"
        [nginx]="nginx"
        [openssl]="openssl"
        [realpath]="coreutils"
        [resolvectl]="systemd-resolved"
        [sudo]="sudo"
        [systemctl]="systemd"
        [timeout]="coreutils"
        [ufw]="ufw"
    )

    HC_DEPENDENCY_DESCRIPTIONS=(
        [awk]="Processamento de texto e cálculos."
        [basename]="Extração de nomes de arquivos."
        [cat]="Leitura de arquivos."
        [cut]="Extração de campos."
        [date]="Datas e timestamps."
        [df]="Uso de sistemas de arquivos."
        [dirname]="Extração de diretórios."
        [du]="Uso de espaço em arquivos e diretórios."
        [find]="Busca de arquivos."
        [grep]="Busca por padrões."
        [head]="Leitura inicial de arquivos."
        [hostname]="Identificação do host."
        [id]="Identificação de usuário e grupos."
        [ip]="Informações de rede."
        [mktemp]="Criação segura de arquivos temporários."
        [mount]="Informações de montagem."
        [ps]="Informações de processos."
        [sed]="Processamento de texto."
        [sort]="Ordenação."
        [ss]="Sockets e portas de rede."
        [stat]="Metadados de arquivos."
        [tail]="Leitura final de arquivos."
        [tr]="Conversão de caracteres."
        [uname]="Informações do kernel."
        [uptime]="Tempo de atividade e carga."

        [apt-get]="Instalação de pacotes."
        [curl]="Requisições HTTP e testes de saúde."
        [dig]="Consultas DNS."
        [docker]="Auditoria de containers."
        [fail2ban-client]="Auditoria do Fail2Ban."
        [findmnt]="Detalhes de sistemas montados."
        [flock]="Controle de execução concorrente."
        [free]="Uso de memória."
        [getent]="Consultas ao banco de dados do sistema."
        [hostnamectl]="Metadados do sistema."
        [iconv]="Conversão de codificação."
        [jq]="Validação e geração de JSON."
        [journalctl]="Consulta ao journal do systemd."
        [lsof]="Arquivos e portas abertas."
        [nginx]="Validação de configuração do Nginx."
        [openssl]="Certificados SSL e criptografia."
        [realpath]="Normalização de caminhos."
        [resolvectl]="Informações de resolução DNS."
        [sudo]="Execução privilegiada."
        [systemctl]="Consulta de serviços systemd."
        [timeout]="Limite de tempo para comandos."
        [ufw]="Auditoria do firewall UFW."
    )

    local command_name

    for command_name in "${HC_DEPENDENCIES_REQUIRED[@]}"; do
        HC_DEPENDENCY_REQUIRED_FLAGS["$command_name"]=1
    done

    for command_name in "${HC_DEPENDENCIES_OPTIONAL[@]}"; do
        HC_DEPENDENCY_REQUIRED_FLAGS["$command_name"]=0
    done
}

# ---------------------------------------------------------------------------
# Funções básicas
# ---------------------------------------------------------------------------

dependencies_command_exists() {
    local command_name="${1:-}"

    [[ -n "$command_name" ]] &&
        command -v "$command_name" >/dev/null 2>&1
}

dependencies_command_path() {
    local command_name="${1:-}"

    if ! dependencies_command_exists "$command_name"; then
        return 1
    fi

    command -v "$command_name"
}

dependencies_is_required() {
    local command_name="${1:-}"

    [[ "${HC_DEPENDENCY_REQUIRED_FLAGS[$command_name]:-0}" == "1" ]]
}

dependencies_description() {
    local command_name="${1:-}"

    printf '%s\n' \
        "${HC_DEPENDENCY_DESCRIPTIONS[$command_name]:-Sem descrição.}"
}

dependencies_package_name() {
    local command_name="${1:-}"

    printf '%s\n' \
        "${HC_DEPENDENCY_PACKAGES_DEBIAN[$command_name]:-$command_name}"
}

# ---------------------------------------------------------------------------
# Detecção de versão
# ---------------------------------------------------------------------------

dependencies_extract_version() {
    local command_name="${1:-}"
    local output=""

    if ! dependencies_command_exists "$command_name"; then
        return 1
    fi

    case "$command_name" in
        awk)
            output="$(
                awk --version 2>&1 |
                    head -n 1 ||
                    true
            )"

            if [[ -z "$output" ]]; then
                output="$(
                    awk -W version 2>&1 |
                        head -n 1 ||
                        true
                )"
            fi
            ;;
        ip)
            output="$(
                ip -Version 2>&1 |
                    head -n 1 ||
                    true
            )"
            ;;
        ss)
            output="$(
                ss --version 2>&1 |
                    head -n 1 ||
                    true
            )"
            ;;
        ps)
            output="$(
                ps --version 2>&1 |
                    head -n 1 ||
                    true
            )"
            ;;
        docker)
            output="$(
                docker --version 2>&1 |
                    head -n 1 ||
                    true
            )"
            ;;
        fail2ban-client)
            output="$(
                fail2ban-client --version 2>&1 |
                    head -n 1 ||
                    true
            )"
            ;;
        nginx)
            output="$(
                nginx -v 2>&1 |
                    head -n 1 ||
                    true
            )"
            ;;
        openssl)
            output="$(
                openssl version 2>&1 |
                    head -n 1 ||
                    true
            )"
            ;;
        systemctl)
            output="$(
                systemctl --version 2>&1 |
                    head -n 1 ||
                    true
            )"
            ;;
        journalctl)
            output="$(
                journalctl --version 2>&1 |
                    head -n 1 ||
                    true
            )"
            ;;
        ufw)
            output="$(
                ufw version 2>&1 |
                    head -n 1 ||
                    true
            )"
            ;;
        *)
            output="$(
                "$command_name" --version 2>&1 |
                    head -n 1 ||
                    true
            )"
            ;;
    esac

    if declare -F utils_sanitize_single_line >/dev/null 2>&1; then
        utils_sanitize_single_line "$output"
    else
        output="${output//$'\r'/ }"
        output="${output//$'\n'/ }"
        output="${output//$'\t'/ }"
        printf '%s\n' "$output"
    fi
}

# ---------------------------------------------------------------------------
# Coleta
# ---------------------------------------------------------------------------

dependencies_reset_results() {
    HC_DEPENDENCIES_AVAILABLE=()
    HC_DEPENDENCIES_MISSING_REQUIRED=()
    HC_DEPENDENCIES_MISSING_OPTIONAL=()

    HC_DEPENDENCY_PATHS=()
    HC_DEPENDENCY_VERSIONS=()
}

dependencies_check_command() {
    local command_name="${1:-}"
    local command_path
    local command_version

    if [[ -z "$command_name" ]]; then
        return 2
    fi

    if dependencies_command_exists "$command_name"; then
        command_path="$(dependencies_command_path "$command_name")"
        command_version="$(dependencies_extract_version "$command_name" || true)"

        HC_DEPENDENCIES_AVAILABLE+=("$command_name")
        HC_DEPENDENCY_PATHS["$command_name"]="$command_path"
        HC_DEPENDENCY_VERSIONS["$command_name"]="$command_version"

        return 0
    fi

    if dependencies_is_required "$command_name"; then
        HC_DEPENDENCIES_MISSING_REQUIRED+=("$command_name")
        return 1
    fi

    HC_DEPENDENCIES_MISSING_OPTIONAL+=("$command_name")
    return 2
}

dependencies_check_all() {
    local command_name

    dependencies_reset_results

    for command_name in "${HC_DEPENDENCIES_REQUIRED[@]}"; do
        dependencies_check_command "$command_name" || true
    done

    for command_name in "${HC_DEPENDENCIES_OPTIONAL[@]}"; do
        dependencies_check_command "$command_name" || true
    done

    if ((${#HC_DEPENDENCIES_MISSING_REQUIRED[@]} > 0)); then
        return 1
    fi

    return 0
}

dependencies_check_list() {
    local required_flag="${1:-0}"
    shift || true

    local command_name
    local missing=0

    if [[ ! "$required_flag" =~ ^[01]$ ]]; then
        return 2
    fi

    for command_name in "$@"; do
        if [[ -z "$command_name" ]]; then
            continue
        fi

        if dependencies_command_exists "$command_name"; then
            continue
        fi

        if ((required_flag == 1)); then
            missing=1
        fi
    done

    return "$missing"
}

dependencies_missing_required_count() {
    printf '%s\n' "${#HC_DEPENDENCIES_MISSING_REQUIRED[@]}"
}

dependencies_missing_optional_count() {
    printf '%s\n' "${#HC_DEPENDENCIES_MISSING_OPTIONAL[@]}"
}

dependencies_available_count() {
    printf '%s\n' "${#HC_DEPENDENCIES_AVAILABLE[@]}"
}

dependencies_has_missing_required() {
    ((${#HC_DEPENDENCIES_MISSING_REQUIRED[@]} > 0))
}

dependencies_has_missing_optional() {
    ((${#HC_DEPENDENCIES_MISSING_OPTIONAL[@]} > 0))
}

# ---------------------------------------------------------------------------
# Requisitos por módulo
# ---------------------------------------------------------------------------

dependencies_module_required_commands() {
    local module="${1:-}"

    case "$module" in
        system)
            printf '%s\n' \
                "uname" \
                "hostname" \
                "uptime" \
                "ps"
            ;;
        cpu)
            printf '%s\n' \
                "awk" \
                "grep" \
                "ps"
            ;;
        memory)
            printf '%s\n' \
                "awk" \
                "grep" \
                "ps"
            ;;
        disk)
            printf '%s\n' \
                "df" \
                "du" \
                "find" \
                "sort" \
                "stat"
            ;;
        network)
            printf '%s\n' \
                "ip" \
                "ss" \
                "hostname"
            ;;
        python)
            printf '%s\n' \
                "ps" \
                "grep" \
                "find"
            ;;
        docker)
            printf '%s\n' "docker"
            ;;
        nginx)
            printf '%s\n' \
                "grep" \
                "find" \
                "nginx"
            ;;
        ssl)
            printf '%s\n' "openssl"
            ;;
        database)
            printf '%s\n' \
                "ps" \
                "ss"
            ;;
        firewall)
            printf '%s\n' \
                "ip" \
                "ss"
            ;;
        security)
            printf '%s\n' \
                "grep" \
                "ps"
            ;;
        services)
            printf '%s\n' \
                "ps"
            ;;
        logs)
            printf '%s\n' \
                "find" \
                "du" \
                "sort"
            ;;
        updates)
            printf '%s\n' \
                "grep"
            ;;
        ai)
            printf '%s\n' \
                "ps" \
                "ss"
            ;;
        ollama)
            printf '%s\n' \
                "ps" \
                "ss"
            ;;
        *)
            return 1
            ;;
    esac
}

dependencies_module_optional_commands() {
    local module="${1:-}"

    case "$module" in
        system)
            printf '%s\n' \
                "hostnamectl" \
                "systemctl"
            ;;
        cpu)
            printf '%s\n' \
                "lscpu"
            ;;
        memory)
            printf '%s\n' \
                "free"
            ;;
        disk)
            printf '%s\n' \
                "findmnt" \
                "lsof"
            ;;
        network)
            printf '%s\n' \
                "dig" \
                "getent" \
                "lsof" \
                "resolvectl"
            ;;
        python)
            printf '%s\n' \
                "curl" \
                "systemctl"
            ;;
        docker)
            printf '%s\n' \
                "jq"
            ;;
        nginx)
            printf '%s\n' \
                "curl" \
                "openssl" \
                "systemctl"
            ;;
        ssl)
            printf '%s\n' \
                "curl"
            ;;
        database)
            printf '%s\n' \
                "docker" \
                "systemctl"
            ;;
        firewall)
            printf '%s\n' \
                "ufw" \
                "fail2ban-client"
            ;;
        security)
            printf '%s\n' \
                "fail2ban-client" \
                "journalctl" \
                "systemctl"
            ;;
        services)
            printf '%s\n' \
                "systemctl" \
                "journalctl"
            ;;
        logs)
            printf '%s\n' \
                "journalctl" \
                "lsof"
            ;;
        updates)
            printf '%s\n' \
                "apt-get"
            ;;
        ai)
            printf '%s\n' \
                "curl" \
                "docker" \
                "systemctl"
            ;;
        ollama)
            printf '%s\n' \
                "curl" \
                "systemctl"
            ;;
        *)
            return 1
            ;;
    esac
}

dependencies_check_module() {
    local module="${1:-}"
    local command_name
    local missing_required=0
    local -a required_commands=()
    local -a optional_commands=()

    if [[ -z "$module" ]]; then
        return 2
    fi

    mapfile -t required_commands < <(
        dependencies_module_required_commands "$module" 2>/dev/null ||
            true
    )

    mapfile -t optional_commands < <(
        dependencies_module_optional_commands "$module" 2>/dev/null ||
            true
    )

    for command_name in "${required_commands[@]}"; do
        if [[ -z "$command_name" ]]; then
            continue
        fi

        if ! dependencies_command_exists "$command_name"; then
            missing_required=1

            if declare -F logger_error >/dev/null 2>&1; then
                logger_error \
                    "Dependência obrigatória ausente para ${module}: ${command_name}"
            fi
        fi
    done

    for command_name in "${optional_commands[@]}"; do
        if [[ -z "$command_name" ]]; then
            continue
        fi

        if ! dependencies_command_exists "$command_name"; then
            if declare -F logger_debug >/dev/null 2>&1; then
                logger_debug \
                    "Dependência opcional ausente para ${module}: ${command_name}"
            fi
        fi
    done

    return "$missing_required"
}

# ---------------------------------------------------------------------------
# Pacotes ausentes
# ---------------------------------------------------------------------------

dependencies_missing_required_packages() {
    local command_name
    local package_name
    local -A seen_packages=()

    for command_name in "${HC_DEPENDENCIES_MISSING_REQUIRED[@]}"; do
        package_name="$(dependencies_package_name "$command_name")"

        if [[ -z "${seen_packages[$package_name]+x}" ]]; then
            printf '%s\n' "$package_name"
            seen_packages["$package_name"]=1
        fi
    done
}

dependencies_missing_optional_packages() {
    local command_name
    local package_name
    local -A seen_packages=()

    for command_name in "${HC_DEPENDENCIES_MISSING_OPTIONAL[@]}"; do
        package_name="$(dependencies_package_name "$command_name")"

        if [[ -z "${seen_packages[$package_name]+x}" ]]; then
            printf '%s\n' "$package_name"
            seen_packages["$package_name"]=1
        fi
    done
}

dependencies_install_command() {
    local include_optional="${1:-0}"
    local -a packages=()
    local package_name

    mapfile -t packages < <(
        dependencies_missing_required_packages
    )

    if [[ "$include_optional" == "1" ]]; then
        while IFS= read -r package_name; do
            [[ -n "$package_name" ]] &&
                packages+=("$package_name")
        done < <(
            dependencies_missing_optional_packages
        )
    fi

    if ((${#packages[@]} == 0)); then
        printf 'Nenhum pacote precisa ser instalado.\n'
        return 0
    fi

    printf 'sudo apt-get update && sudo apt-get install -y'

    for package_name in "${packages[@]}"; do
        printf ' %q' "$package_name"
    done

    printf '\n'
}

# ---------------------------------------------------------------------------
# Instalação
# ---------------------------------------------------------------------------

dependencies_can_install() {
    if ! dependencies_command_exists "apt-get"; then
        return 1
    fi

    if ((EUID == 0)); then
        return 0
    fi

    if [[ "${USE_SUDO:-1}" != "1" ]]; then
        return 1
    fi

    dependencies_command_exists "sudo"
}

dependencies_install_packages() {
    local include_optional="${1:-0}"
    local update_indexes="${2:-1}"
    local -a packages=()
    local package_name

    if [[ ! "$include_optional" =~ ^[01]$ ]] ||
        [[ ! "$update_indexes" =~ ^[01]$ ]]; then
        return 2
    fi

    if ! dependencies_can_install; then
        return "${EXIT_PERMISSION_ERROR:-4}"
    fi

    mapfile -t packages < <(
        dependencies_missing_required_packages
    )

    if ((include_optional == 1)); then
        while IFS= read -r package_name; do
            [[ -n "$package_name" ]] &&
                packages+=("$package_name")
        done < <(
            dependencies_missing_optional_packages
        )
    fi

    if ((${#packages[@]} == 0)); then
        return 0
    fi

    if ((update_indexes == 1)); then
        if ((EUID == 0)); then
            apt-get update
        else
            sudo apt-get update
        fi
    fi

    if ((EUID == 0)); then
        apt-get install -y -- "${packages[@]}"
    else
        sudo apt-get install -y -- "${packages[@]}"
    fi
}

# ---------------------------------------------------------------------------
# Relatório em terminal
# ---------------------------------------------------------------------------

dependencies_print_summary() {
    local command_name
    local status
    local description
    local package_name
    local command_path
    local version

    printf '\nDependências\n'
    printf '%-22s %-12s %-28s %s\n' \
        "Comando" \
        "Estado" \
        "Pacote" \
        "Descrição"

    printf '%-22s %-12s %-28s %s\n' \
        "----------------------" \
        "------------" \
        "----------------------------" \
        "--------------------------------"

    for command_name in "${HC_DEPENDENCIES_REQUIRED[@]}"; do
        description="$(dependencies_description "$command_name")"
        package_name="$(dependencies_package_name "$command_name")"

        if dependencies_command_exists "$command_name"; then
            status="OK"
        else
            status="AUSENTE"
        fi

        printf '%-22s %-12s %-28s %s\n' \
            "$command_name" \
            "$status" \
            "$package_name" \
            "$description"
    done

    for command_name in "${HC_DEPENDENCIES_OPTIONAL[@]}"; do
        description="$(dependencies_description "$command_name")"
        package_name="$(dependencies_package_name "$command_name")"

        if dependencies_command_exists "$command_name"; then
            status="OK"
        else
            status="OPCIONAL"
        fi

        printf '%-22s %-12s %-28s %s\n' \
            "$command_name" \
            "$status" \
            "$package_name" \
            "$description"
    done

    if ((${#HC_DEPENDENCIES_AVAILABLE[@]} > 0)); then
        printf '\nDisponíveis: %s\n' \
            "${#HC_DEPENDENCIES_AVAILABLE[@]}"
    fi

    if ((${#HC_DEPENDENCIES_MISSING_REQUIRED[@]} > 0)); then
        printf 'Obrigatórias ausentes: %s\n' \
            "$(
                IFS=','
                printf '%s' "${HC_DEPENDENCIES_MISSING_REQUIRED[*]}"
            )"
    fi

    if ((${#HC_DEPENDENCIES_MISSING_OPTIONAL[@]} > 0)); then
        printf 'Opcionais ausentes: %s\n' \
            "$(
                IFS=','
                printf '%s' "${HC_DEPENDENCIES_MISSING_OPTIONAL[*]}"
            )"
    fi

    if [[ "${VERBOSE:-0}" == "1" ]]; then
        printf '\nDetalhes das dependências disponíveis\n'

        for command_name in "${HC_DEPENDENCIES_AVAILABLE[@]}"; do
            command_path="${HC_DEPENDENCY_PATHS[$command_name]:-}"
            version="${HC_DEPENDENCY_VERSIONS[$command_name]:-}"

            printf '  %-20s %s' \
                "${command_name}:" \
                "$command_path"

            if [[ -n "$version" ]]; then
                printf ' | %s' "$version"
            fi

            printf '\n'
        done
    fi
}

# ---------------------------------------------------------------------------
# Integração com coleta
# ---------------------------------------------------------------------------

dependencies_export_state() {
    export HC_DEPENDENCIES_INITIALIZED
}

dependencies_initialize() {
    dependencies_register_defaults
    dependencies_check_all || true

    HC_DEPENDENCIES_INITIALIZED=1
    dependencies_export_state

    if declare -F logger_info >/dev/null 2>&1; then
        logger_info \
            "Dependências verificadas | disponíveis=${#HC_DEPENDENCIES_AVAILABLE[@]} | obrigatórias_ausentes=${#HC_DEPENDENCIES_MISSING_REQUIRED[@]} | opcionais_ausentes=${#HC_DEPENDENCIES_MISSING_OPTIONAL[@]}"
    fi

    if dependencies_has_missing_required; then
        if declare -F logger_error >/dev/null 2>&1; then
            logger_error \
                "Dependências obrigatórias ausentes: $(IFS=','; printf '%s' "${HC_DEPENDENCIES_MISSING_REQUIRED[*]}")"
        fi

        return 1
    fi

    return 0
}

dependencies_is_initialized() {
    ((HC_DEPENDENCIES_INITIALIZED == 1))
}

# ---------------------------------------------------------------------------
# Validação interna
# ---------------------------------------------------------------------------

dependencies_validate() {
    local failure=0
    local command_name
    local package_name
    local required_count
    local optional_count

    dependencies_register_defaults
    dependencies_check_all || true

    required_count="${#HC_DEPENDENCIES_REQUIRED[@]}"
    optional_count="${#HC_DEPENDENCIES_OPTIONAL[@]}"

    if ((required_count == 0)); then
        printf 'Nenhuma dependência obrigatória registrada.\n' >&2
        failure=1
    fi

    if ((optional_count == 0)); then
        printf 'Nenhuma dependência opcional registrada.\n' >&2
        failure=1
    fi

    for command_name in "${HC_DEPENDENCIES_REQUIRED[@]}"; do
        if ! dependencies_is_required "$command_name"; then
            printf 'Dependência deveria ser obrigatória: %s\n' \
                "$command_name" >&2
            failure=1
        fi

        package_name="$(dependencies_package_name "$command_name")"

        if [[ -z "$package_name" ]]; then
            printf 'Dependência sem pacote associado: %s\n' \
                "$command_name" >&2
            failure=1
        fi
    done

    for command_name in "${HC_DEPENDENCIES_OPTIONAL[@]}"; do
        if dependencies_is_required "$command_name"; then
            printf 'Dependência deveria ser opcional: %s\n' \
                "$command_name" >&2
            failure=1
        fi
    done

    if ! dependencies_command_exists "sh"; then
        printf 'Falha ao localizar o comando sh.\n' >&2
        failure=1
    fi

    if dependencies_command_exists \
        "comando-que-nao-deve-exist-vps-healthcheck"; then

        printf 'Detecção incorreta de comando inexistente.\n' >&2
        failure=1
    fi

    if [[ "$(dependencies_package_name "curl")" != "curl" ]]; then
        printf 'Pacote incorreto associado ao curl.\n' >&2
        failure=1
    fi

    if [[ "$(dependencies_package_name "ss")" != "iproute2" ]]; then
        printf 'Pacote incorreto associado ao ss.\n' >&2
        failure=1
    fi

    if ! dependencies_check_module "system"; then
        printf 'Dependências essenciais do módulo system ausentes.\n' >&2
        failure=1
    fi

    return "$failure"
}
