#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_SYSTEM_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_SYSTEM_LOADED=1

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------

system_config_enabled() {
    local key="${1:-}"
    local default_value="${2:-1}"
    local value="$default_value"

    if declare -F config_get >/dev/null 2>&1; then
        value="$(config_get "$key" "$default_value")"
    elif [[ -n "${!key+x}" ]]; then
        value="${!key}"
    fi

    [[ "$value" == "1" ]]
}

system_config_get() {
    local key="${1:-}"
    local default_value="${2:-}"

    if declare -F config_get >/dev/null 2>&1; then
        config_get "$key" "$default_value"
    elif [[ -n "${!key+x}" ]]; then
        printf '%s\n' "${!key}"
    else
        printf '%s\n' "$default_value"
    fi
}

# ---------------------------------------------------------------------------
# Sistema operacional
# ---------------------------------------------------------------------------

system_read_os_release() {
    local destination_name="${1:-}"
    local line
    local key
    local value

    if [[ -z "$destination_name" ]]; then
        return 1
    fi

    local -n destination_ref="$destination_name"

    destination_ref=()

    if [[ ! -r /etc/os-release ]]; then
        return 2
    fi

    while IFS= read -r line; do
        [[ "$line" == *=* ]] || continue
        [[ "$line" == \#* ]] && continue

        key="${line%%=*}"
        value="${line#*=}"

        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"

        destination_ref["$key"]="$value"
    done </etc/os-release

    return 0
}

system_collect_os() {
    local -A os_release=()

    local os_name="desconhecido"
    local os_id="desconhecido"
    local os_version="desconhecido"
    local os_version_id="desconhecido"
    local os_codename="desconhecido"
    local pretty_name="desconhecido"

    if system_read_os_release os_release; then
        os_name="${os_release[NAME]:-desconhecido}"
        os_id="${os_release[ID]:-desconhecido}"
        os_version="${os_release[VERSION]:-desconhecido}"
        os_version_id="${os_release[VERSION_ID]:-desconhecido}"
        os_codename="${os_release[VERSION_CODENAME]:-${os_release[UBUNTU_CODENAME]:-desconhecido}}"
        pretty_name="${os_release[PRETTY_NAME]:-$os_name}"
    fi

    collector_metric_set \
        "system" \
        "operating_system" \
        "pretty_name" \
        "Sistema operacional" \
        "$pretty_name" \
        "$pretty_name" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Nome completo do sistema operacional." \
        "/etc/os-release"

    collector_metric_set \
        "system" \
        "operating_system" \
        "name" \
        "Distribuição" \
        "$os_name" \
        "$os_name" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Nome da distribuição Linux." \
        "/etc/os-release"

    collector_metric_set \
        "system" \
        "operating_system" \
        "id" \
        "Identificador da distribuição" \
        "$os_id" \
        "$os_id" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Identificador normalizado da distribuição." \
        "/etc/os-release"

    collector_metric_set \
        "system" \
        "operating_system" \
        "version" \
        "Versão da distribuição" \
        "$os_version" \
        "$os_version" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Versão completa da distribuição." \
        "/etc/os-release"

    collector_metric_set \
        "system" \
        "operating_system" \
        "version_id" \
        "ID da versão" \
        "$os_version_id" \
        "$os_version_id" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Identificador numérico da versão." \
        "/etc/os-release"

    collector_metric_set \
        "system" \
        "operating_system" \
        "codename" \
        "Codinome" \
        "$os_codename" \
        "$os_codename" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Codinome da versão da distribuição." \
        "/etc/os-release"
}

# ---------------------------------------------------------------------------
# Host
# ---------------------------------------------------------------------------

system_get_hostname() {
    hostname 2>/dev/null || printf 'desconhecido\n'
}

system_get_fqdn() {
    local fqdn=""

    fqdn="$(hostname -f 2>/dev/null || true)"

    if [[ -z "$fqdn" ]]; then
        fqdn="$(system_get_hostname)"
    fi

    printf '%s\n' "$fqdn"
}

system_collect_host() {
    local hostname_value
    local fqdn

    hostname_value="$(system_get_hostname)"
    fqdn="$(system_get_fqdn)"

    collector_metric_set \
        "system" \
        "host" \
        "hostname" \
        "Hostname" \
        "$hostname_value" \
        "$hostname_value" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Nome local do servidor." \
        "hostname"

    collector_metric_set \
        "system" \
        "host" \
        "fqdn" \
        "FQDN" \
        "$fqdn" \
        "$fqdn" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Nome de domínio totalmente qualificado." \
        "hostname -f"
}

# ---------------------------------------------------------------------------
# Kernel e arquitetura
# ---------------------------------------------------------------------------

system_collect_kernel() {
    local kernel
    local architecture
    local machine

    kernel="$(uname -r 2>/dev/null || printf 'desconhecido')"
    architecture="$(uname -m 2>/dev/null || printf 'desconhecido')"
    machine="$(uname -s 2>/dev/null || printf 'Linux')"

    collector_metric_set \
        "system" \
        "kernel" \
        "name" \
        "Kernel" \
        "$machine" \
        "$machine" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Nome do kernel em execução." \
        "uname"

    collector_metric_set \
        "system" \
        "kernel" \
        "release" \
        "Versão do kernel" \
        "$kernel" \
        "$kernel" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Release atual do kernel." \
        "uname -r"

    collector_metric_set \
        "system" \
        "kernel" \
        "architecture" \
        "Arquitetura" \
        "$architecture" \
        "$architecture" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Arquitetura da máquina." \
        "uname -m"
}

# ---------------------------------------------------------------------------
# Uptime e inicialização
# ---------------------------------------------------------------------------

system_get_uptime_seconds() {
    if [[ -r /proc/uptime ]]; then
        awk '{printf "%.0f\n", $1}' /proc/uptime
    else
        printf '0\n'
    fi
}

system_format_duration() {
    local total_seconds="${1:-0}"
    local days
    local hours
    local minutes
    local seconds

    if [[ ! "$total_seconds" =~ ^[0-9]+$ ]]; then
        total_seconds=0
    fi

    days=$((total_seconds / 86400))
    hours=$(((total_seconds % 86400) / 3600))
    minutes=$(((total_seconds % 3600) / 60))
    seconds=$((total_seconds % 60))

    printf '%dd %02dh %02dm %02ds\n' \
        "$days" \
        "$hours" \
        "$minutes" \
        "$seconds"
}

system_get_boot_time() {
    local uptime_seconds
    local now_epoch
    local boot_epoch

    uptime_seconds="$(system_get_uptime_seconds)"
    now_epoch="$(date '+%s')"
    boot_epoch=$((now_epoch - uptime_seconds))

    date \
        --date="@${boot_epoch}" \
        '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null ||
        printf 'desconhecido\n'
}

system_collect_uptime() {
    local uptime_seconds
    local uptime_human
    local boot_time
    local warning_days
    local critical_days
    local warning_seconds
    local critical_seconds
    local status

    uptime_seconds="$(system_get_uptime_seconds)"
    uptime_human="$(system_format_duration "$uptime_seconds")"
    boot_time="$(system_get_boot_time)"

    warning_days="$(
        system_config_get \
            "HC_SYSTEM_UPTIME_WARNING_DAYS" \
            "180"
    )"

    critical_days="$(
        system_config_get \
            "HC_SYSTEM_UPTIME_CRITICAL_DAYS" \
            "365"
    )"

    warning_seconds=$((warning_days * 86400))
    critical_seconds=$((critical_days * 86400))

    status="$(
        utils_status_from_high_usage \
            "$uptime_seconds" \
            "$warning_seconds" \
            "$critical_seconds"
    )"

    collector_metric_set \
        "system" \
        "uptime" \
        "seconds" \
        "Tempo ligado" \
        "$uptime_human" \
        "$uptime_seconds" \
        "duration" \
        "seconds" \
        "$status" \
        "Tempo desde a última inicialização." \
        "/proc/uptime"

    collector_metric_set \
        "system" \
        "uptime" \
        "boot_time" \
        "Data de inicialização" \
        "$boot_time" \
        "$boot_time" \
        "datetime" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Data e hora estimadas da última inicialização." \
        "/proc/uptime"

    if [[ "$status" != "${HC_STATUS_OK:-OK}" ]]; then
        collector_alert_add \
            "system" \
            "$status" \
            "Servidor sem reinicialização há muito tempo" \
            "O servidor está ligado há ${uptime_human}." \
            "Verifique atualizações de kernel pendentes e planeje uma reinicialização controlada."
    fi
}

# ---------------------------------------------------------------------------
# Horário e localidade
# ---------------------------------------------------------------------------

system_collect_time() {
    local timezone
    local current_time
    local locale_value

    timezone="$(
        timedatectl show \
            --property=Timezone \
            --value 2>/dev/null ||
        true
    )"

    if [[ -z "$timezone" ]]; then
        timezone="$(
            readlink /etc/localtime 2>/dev/null |
            sed 's#^.*/zoneinfo/##' ||
            true
        )"
    fi

    current_time="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    locale_value="${LANG:-desconhecido}"

    collector_metric_set \
        "system" \
        "time" \
        "current" \
        "Data e hora atual" \
        "$current_time" \
        "$current_time" \
        "datetime" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Data e hora no servidor." \
        "date"

    collector_metric_set \
        "system" \
        "time" \
        "timezone" \
        "Fuso horário" \
        "${timezone:-desconhecido}" \
        "$timezone" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Fuso horário configurado." \
        "timedatectl"

    collector_metric_set \
        "system" \
        "time" \
        "locale" \
        "Locale" \
        "$locale_value" \
        "$locale_value" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Localidade principal do ambiente." \
        "LANG"
}

# ---------------------------------------------------------------------------
# Virtualização
# ---------------------------------------------------------------------------

system_detect_virtualization() {
    local virtualization="none"

    if command -v systemd-detect-virt >/dev/null 2>&1; then
        virtualization="$(
            systemd-detect-virt 2>/dev/null ||
            printf 'none'
        )"
    elif command -v hostnamectl >/dev/null 2>&1; then
        virtualization="$(
            hostnamectl 2>/dev/null |
            awk -F: '
                /Virtualization/ {
                    sub(/^[[:space:]]+/, "", $2)
                    print $2
                    exit
                }
            '
        )"
    fi

    printf '%s\n' "${virtualization:-none}"
}

system_collect_virtualization() {
    local virtualization
    local is_virtual="false"

    virtualization="$(system_detect_virtualization)"

    if [[ "$virtualization" != "none" &&
        "$virtualization" != "desconhecido" ]]; then

        is_virtual="true"
    fi

    collector_metric_set \
        "system" \
        "virtualization" \
        "type" \
        "Virtualização" \
        "$virtualization" \
        "$virtualization" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Tecnologia de virtualização detectada." \
        "systemd-detect-virt"

    collector_metric_set \
        "system" \
        "virtualization" \
        "is_virtual" \
        "Ambiente virtualizado" \
        "$([[ "$is_virtual" == "true" ]] && printf 'Sim' || printf 'Não')" \
        "$is_virtual" \
        "boolean" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Indica se o servidor está em ambiente virtualizado." \
        "systemd-detect-virt"
}

# ---------------------------------------------------------------------------
# Reinicialização pendente
# ---------------------------------------------------------------------------

system_collect_reboot_required() {
    local required="false"
    local display="Não"
    local status="${HC_STATUS_OK:-OK}"

    if [[ -e /var/run/reboot-required ]]; then
        required="true"
        display="Sim"
        status="$(
            system_config_get \
                "HC_REBOOT_REQUIRED_STATUS" \
                "WARNING"
        )"

        collector_alert_add \
            "system" \
            "$status" \
            "Reinicialização necessária" \
            "O sistema possui uma reinicialização pendente." \
            "Agende uma janela de manutenção e reinicie o servidor."
    fi

    collector_metric_set \
        "system" \
        "maintenance" \
        "reboot_required" \
        "Reinicialização necessária" \
        "$display" \
        "$required" \
        "boolean" \
        "" \
        "$status" \
        "Indica se existe reinicialização pendente." \
        "/var/run/reboot-required"
}

# ---------------------------------------------------------------------------
# Usuário da execução
# ---------------------------------------------------------------------------

system_collect_execution_user() {
    local username
    local user_id
    local privilege="normal"

    username="$(id -un 2>/dev/null || printf 'desconhecido')"
    user_id="$(id -u 2>/dev/null || printf '0')"

    if [[ "$user_id" == "0" ]]; then
        privilege="root"
    elif command -v sudo >/dev/null 2>&1 &&
        sudo -n true 2>/dev/null; then

        privilege="sudo-sem-senha"
    elif command -v sudo >/dev/null 2>&1; then
        privilege="sudo"
    fi

    collector_metric_set \
        "system" \
        "execution" \
        "user" \
        "Usuário da execução" \
        "$username" \
        "$username" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Usuário que executou a auditoria." \
        "id"

    collector_metric_set \
        "system" \
        "execution" \
        "uid" \
        "UID da execução" \
        "$user_id" \
        "$user_id" \
        "integer" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Identificador numérico do usuário." \
        "id -u"

    collector_metric_set \
        "system" \
        "execution" \
        "privilege" \
        "Privilégio" \
        "$privilege" \
        "$privilege" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Nível estimado de privilégio da execução." \
        "id e sudo"
}

# ---------------------------------------------------------------------------
# Execução
# ---------------------------------------------------------------------------

system_run() {
    system_collect_os
    system_collect_host
    system_collect_kernel
    system_collect_uptime
    system_collect_time
    system_collect_virtualization
    system_collect_reboot_required
    system_collect_execution_user

    return 0
}

# ---------------------------------------------------------------------------
# Validação
# ---------------------------------------------------------------------------

system_validate() {
    local failure=0
    local hostname_value=""
    local os_name=""
    local metric_count=0

    if ! declare -F collector_initialize >/dev/null 2>&1; then
        printf 'collector_initialize não está disponível.\n' >&2
        return 1
    fi

    collector_initialize
    collector_module_start "system" "Sistema"

    if ! system_run; then
        printf 'system_run retornou falha.\n' >&2
        failure=1
    fi

    hostname_value="$(
        collector_metric_get \
            "system" \
            "host" \
            "hostname" \
            "raw_value" 2>/dev/null ||
        true
    )"

    os_name="$(
        collector_metric_get \
            "system" \
            "operating_system" \
            "pretty_name" \
            "raw_value" 2>/dev/null ||
        true
    )"

    metric_count="$(collector_metric_count system)"

    if [[ -z "$hostname_value" ]]; then
        printf 'Hostname não coletado.\n' >&2
        failure=1
    fi

    if [[ -z "$os_name" ]]; then
        printf 'Sistema operacional não coletado.\n' >&2
        failure=1
    fi

    if [[ ! "$metric_count" =~ ^[0-9]+$ ]] ||
        ((metric_count < 15)); then

        printf \
            'Quantidade insuficiente de métricas do sistema: %s\n' \
            "$metric_count" >&2

        failure=1
    fi

    collector_module_finish \
        "system" \
        "$(collector_module_get_status system)" \
        "Validação concluída."

    collector_finalize

    return "$failure"
}
