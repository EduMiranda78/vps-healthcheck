#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_UPDATES_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_UPDATES_LOADED=1

updates_config_enabled() {
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

updates_config_get() {
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

updates_apt_available() {
    command -v apt-get >/dev/null 2>&1 &&
        command -v apt-cache >/dev/null 2>&1 &&
        command -v dpkg-query >/dev/null 2>&1
}

updates_collect_available() {
    local package
    local current_version
    local candidate_version
    local repository
    local architecture
    local count=0
    local security_count=0
    local warning
    local critical
    local security_warning
    local security_critical
    local status
    local security_status

    warning="$(
        updates_config_get \
            HC_UPDATES_AVAILABLE_WARNING_COUNT \
            20
    )"

    critical="$(
        updates_config_get \
            HC_UPDATES_AVAILABLE_CRITICAL_COUNT \
            50
    )"

    security_warning="$(
        updates_config_get \
            HC_SECURITY_UPDATES_WARNING_COUNT \
            1
    )"

    security_critical="$(
        updates_config_get \
            HC_SECURITY_UPDATES_CRITICAL_COUNT \
            10
    )"

    collector_table_create \
        "updates" \
        "packages" \
        "available" \
        "Atualizações disponíveis" \
        $'Pacote\tVersão instalada\tNova versão\tArquitetura\tOrigem\tSegurança' \
        "Pacotes com atualização disponível." \
        "${HC_STATUS_OK:-OK}"

    while IFS=$'\t' read -r \
        package \
        current_version \
        candidate_version \
        architecture \
        repository; do

        [[ -n "$package" ]] || continue

        count=$((count + 1))

        local is_security="Não"

        if [[ "$repository" == *security* ]] ||
            [[ "$candidate_version" == *security* ]]; then

            is_security="Sim"
            security_count=$((security_count + 1))
        fi

        collector_table_add_row \
            "updates" \
            "packages" \
            "available" \
            "$package" \
            "$current_version" \
            "$candidate_version" \
            "$architecture" \
            "$repository" \
            "$is_security"
    done < <(
        LC_ALL=C apt list --upgradable 2>/dev/null |
        awk '
            NR > 1 {
                package_field = $1
                candidate = $2
                repository = $3

                split(package_field, package_parts, "/")
                package = package_parts[1]
                source = package_parts[2]

                installed = ""
                architecture = ""

                for (i = 4; i <= NF; i++) {
                    if ($i ~ /^from:/) {
                        installed = $(i + 1)
                    }

                    if ($i ~ /^\[/) {
                        architecture = $i
                        gsub(/[\[\],]/, "", architecture)
                    }
                }

                printf "%s\t%s\t%s\t%s\t%s\n",
                    package,
                    installed,
                    candidate,
                    architecture,
                    source " " repository
            }
        '
    )

    status="$(
        utils_status_from_high_usage \
            "$count" \
            "$warning" \
            "$critical"
    )"

    security_status="$(
        utils_status_from_high_usage \
            "$security_count" \
            "$security_warning" \
            "$security_critical"
    )"

    collector_metric_set \
        "updates" \
        "summary" \
        "available_count" \
        "Atualizações disponíveis" \
        "$count" \
        "$count" \
        "integer" \
        "packages" \
        "$status" \
        "Quantidade total de pacotes atualizáveis." \
        "apt list --upgradable"

    collector_metric_set \
        "updates" \
        "summary" \
        "security_count" \
        "Atualizações de segurança" \
        "$security_count" \
        "$security_count" \
        "integer" \
        "packages" \
        "$security_status" \
        "Quantidade estimada de atualizações de segurança." \
        "apt list --upgradable"

    collector_table_set_status \
        "updates" \
        "packages" \
        "available" \
        "$(collector_worst_status "$status" "$security_status")"

    if ((security_count > 0)); then
        collector_alert_add \
            "updates" \
            "$security_status" \
            "Atualizações de segurança disponíveis" \
            "Foram encontradas ${security_count} atualizações relacionadas à segurança." \
            "Planeje a atualização dos pacotes e valide a necessidade de reinicialização."
    elif ((count > 0)); then
        collector_alert_add \
            "updates" \
            "$status" \
            "Atualizações disponíveis" \
            "Foram encontrados ${count} pacotes com atualização disponível." \
            "Revise as atualizações e aplique-as em uma janela de manutenção."
    fi
}

updates_collect_held_packages() {
    local package
    local count=0
    local warning
    local critical
    local status

    warning="$(
        updates_config_get \
            HC_HELD_PACKAGES_WARNING_COUNT \
            1
    )"

    critical="$(
        updates_config_get \
            HC_HELD_PACKAGES_CRITICAL_COUNT \
            10
    )"

    collector_table_create \
        "updates" \
        "packages" \
        "held" \
        "Pacotes retidos" \
        $'Pacote' \
        "Pacotes marcados como hold pelo APT." \
        "${HC_STATUS_OK:-OK}"

    while IFS= read -r package; do
        package="$(utils_trim "$package")"

        [[ -n "$package" ]] || continue

        count=$((count + 1))

        collector_table_add_row \
            "updates" \
            "packages" \
            "held" \
            "$package"
    done < <(
        apt-mark showhold 2>/dev/null || true
    )

    status="$(
        utils_status_from_high_usage \
            "$count" \
            "$warning" \
            "$critical"
    )"

    collector_metric_set \
        "updates" \
        "summary" \
        "held_count" \
        "Pacotes retidos" \
        "$count" \
        "$count" \
        "integer" \
        "packages" \
        "$status" \
        "Quantidade de pacotes marcados como hold." \
        "apt-mark showhold"

    collector_table_set_status \
        "updates" \
        "packages" \
        "held" \
        "$status"

    if ((count > 0)); then
        collector_alert_add \
            "updates" \
            "$status" \
            "Pacotes retidos pelo APT" \
            "Existem ${count} pacotes marcados como hold." \
            "Confirme se a retenção é intencional e se impede correções importantes."
    fi
}

updates_collect_reboot_required() {
    local required="false"
    local display="Não"
    local count=0
    local status="${HC_STATUS_OK:-OK}"
    local package

    collector_table_create \
        "updates" \
        "reboot" \
        "packages" \
        "Pacotes aguardando reinicialização" \
        $'Pacote' \
        "Pacotes relacionados à necessidade de reinicialização." \
        "${HC_STATUS_OK:-OK}"

    if [[ -e /var/run/reboot-required ]]; then
        required="true"
        display="Sim"
        status="$(
            updates_config_get \
                HC_REBOOT_REQUIRED_STATUS \
                WARNING
        )"
    fi

    if [[ -r /var/run/reboot-required.pkgs ]]; then
        while IFS= read -r package; do
            package="$(utils_trim "$package")"

            [[ -n "$package" ]] || continue

            count=$((count + 1))

            collector_table_add_row \
                "updates" \
                "reboot" \
                "packages" \
                "$package"
        done </var/run/reboot-required.pkgs
    fi

    collector_metric_set \
        "updates" \
        "reboot" \
        "required" \
        "Reinicialização necessária" \
        "$display" \
        "$required" \
        "boolean" \
        "" \
        "$status" \
        "Indica se o sistema solicita reinicialização." \
        "/var/run/reboot-required"

    collector_metric_set \
        "updates" \
        "reboot" \
        "package_count" \
        "Pacotes aguardando reinicialização" \
        "$count" \
        "$count" \
        "integer" \
        "packages" \
        "$status" \
        "Quantidade de pacotes ligados à reinicialização pendente." \
        "/var/run/reboot-required.pkgs"

    collector_table_set_status \
        "updates" \
        "reboot" \
        "packages" \
        "$status"

    if [[ "$required" == "true" ]]; then
        collector_alert_add \
            "updates" \
            "$status" \
            "Reinicialização pendente" \
            "O sistema solicita reinicialização após atualizações." \
            "Agende uma janela de manutenção e reinicie a VPS."
    fi
}

updates_collect_package_index_age() {
    local newest_file=""
    local modified_epoch=0
    local current_epoch
    local age_seconds=0
    local age_hours=0
    local warning
    local critical
    local status="${HC_STATUS_UNKNOWN:-UNKNOWN}"

    warning="$(
        updates_config_get \
            HC_PACKAGE_INDEX_WARNING_AGE_HOURS \
            48
    )"

    critical="$(
        updates_config_get \
            HC_PACKAGE_INDEX_CRITICAL_AGE_HOURS \
            168
    )"

    if [[ -d /var/lib/apt/lists ]]; then
        newest_file="$(
            find /var/lib/apt/lists \
                -maxdepth 1 \
                -type f \
                -printf '%T@\t%p\n' 2>/dev/null |
            sort -nr |
            head -n 1 |
            cut -f2-
        )"
    fi

    if [[ -n "$newest_file" && -e "$newest_file" ]]; then
        modified_epoch="$(
            stat -c '%Y' "$newest_file" 2>/dev/null ||
            printf '0'
        )"

        current_epoch="$(date '+%s')"

        if [[ "$modified_epoch" =~ ^[0-9]+$ ]] &&
            ((modified_epoch > 0 && current_epoch >= modified_epoch)); then

            age_seconds=$((current_epoch - modified_epoch))
            age_hours=$((age_seconds / 3600))

            status="$(
                utils_status_from_high_usage \
                    "$age_hours" \
                    "$warning" \
                    "$critical"
            )"
        fi
    fi

    collector_metric_set \
        "updates" \
        "apt" \
        "index_age_hours" \
        "Idade do índice APT" \
        "${age_hours} horas" \
        "$age_hours" \
        "integer" \
        "hours" \
        "$status" \
        "Tempo desde a atualização mais recente do índice APT." \
        "/var/lib/apt/lists"

    if [[ "$status" != "${HC_STATUS_OK:-OK}" &&
        "$status" != "${HC_STATUS_UNKNOWN:-UNKNOWN}" ]]; then

        collector_alert_add \
            "updates" \
            "$status" \
            "Índice APT desatualizado" \
            "O índice de pacotes tem aproximadamente ${age_hours} horas." \
            "Execute apt-get update antes de avaliar ou instalar atualizações."
    fi
}

updates_run() {
    if ! updates_apt_available; then
        collector_metric_set \
            "updates" \
            "apt" \
            "available" \
            "APT disponível" \
            "Não" \
            "false" \
            "boolean" \
            "" \
            "${HC_STATUS_CRITICAL:-CRITICAL}" \
            "O gerenciador APT não está disponível." \
            "apt-get"

        return 0
    fi

    collector_metric_set \
        "updates" \
        "apt" \
        "available" \
        "APT disponível" \
        "Sim" \
        "true" \
        "boolean" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "O gerenciador APT está disponível." \
        "apt-get"

    updates_collect_package_index_age

    if updates_config_enabled HC_UPDATES_INCLUDE_AVAILABLE 1; then
        updates_collect_available
    fi

    if updates_config_enabled HC_UPDATES_INCLUDE_HELD_PACKAGES 1; then
        updates_collect_held_packages
    fi

    if updates_config_enabled HC_UPDATES_INCLUDE_REBOOT_REQUIRED 1; then
        updates_collect_reboot_required
    fi

    return 0
}

updates_validate() {
    local failure=0
    local apt_available=""
    local metric_count=0
    local table_count=0

    collector_initialize
    collector_module_start "updates" "Atualizações"

    if ! updates_run; then
        printf 'updates_run retornou falha.\n' >&2
        failure=1
    fi

    apt_available="$(
        collector_metric_get \
            "updates" \
            "apt" \
            "available" \
            "raw_value" 2>/dev/null ||
        true
    )"

    metric_count="$(collector_metric_count updates)"
    table_count="$(collector_table_count updates)"

    if [[ "$apt_available" != "true" ]]; then
        printf 'APT não foi detectado como disponível.\n' >&2
        failure=1
    fi

    if [[ ! "$metric_count" =~ ^[0-9]+$ ]] ||
        ((metric_count < 5)); then

        printf \
            'Quantidade insuficiente de métricas de atualizações: %s\n' \
            "$metric_count" >&2

        failure=1
    fi

    if [[ ! "$table_count" =~ ^[0-9]+$ ]] ||
        ((table_count < 3)); then

        printf \
            'Quantidade insuficiente de tabelas de atualizações: %s\n' \
            "$table_count" >&2

        failure=1
    fi

    collector_module_finish \
        "updates" \
        "$(collector_module_get_status updates)" \
        "Validação concluída."

    collector_finalize

    return "$failure"
}
