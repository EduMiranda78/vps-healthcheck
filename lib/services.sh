#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_SERVICES_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_SERVICES_LOADED=1

services_config_enabled() {
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

services_config_get() {
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

services_systemd_available() {
    command -v systemctl >/dev/null 2>&1 &&
        [[ -d /run/systemd/system ]]
}

services_normalize_unit_name() {
    local unit="${1:-}"

    if [[ -z "$unit" ]]; then
        return 1
    fi

    if [[ "$unit" != *.* ]]; then
        unit="${unit}.service"
    fi

    printf '%s\n' "$unit"
}

services_collect_running() {
    local limit
    local unit
    local load_state
    local active_state
    local sub_state
    local description
    local count=0

    limit="$(services_config_get HC_SERVICES_MAX_RESULTS 200)"

    collector_table_create \
        "services" \
        "units" \
        "running" \
        "Serviços em execução" \
        $'Unidade\tCarregamento\tEstado\tSubestado\tDescrição' \
        "Serviços systemd atualmente ativos." \
        "${HC_STATUS_OK:-OK}"

    while IFS=$'\t' read -r \
        unit \
        load_state \
        active_state \
        sub_state \
        description; do

        [[ -n "$unit" ]] || continue

        count=$((count + 1))

        collector_table_add_row \
            "services" \
            "units" \
            "running" \
            "$unit" \
            "$load_state" \
            "$active_state" \
            "$sub_state" \
            "$description"
    done < <(
        LC_ALL=C systemctl list-units \
            --type=service \
            --state=running \
            --all \
            --no-legend \
            --no-pager 2>/dev/null |
        awk -v limit="$limit" '
            NR <= limit {
                unit = $1
                load_state = $2
                active_state = $3
                sub_state = $4

                $1 = ""
                $2 = ""
                $3 = ""
                $4 = ""

                sub(/^[[:space:]]+/, "", $0)

                printf "%s\t%s\t%s\t%s\t%s\n",
                    unit,
                    load_state,
                    active_state,
                    sub_state,
                    $0
            }
        '
    )

    collector_metric_set \
        "services" \
        "summary" \
        "running_count" \
        "Serviços em execução" \
        "$count" \
        "$count" \
        "integer" \
        "services" \
        "${HC_STATUS_OK:-OK}" \
        "Quantidade de serviços systemd em execução." \
        "systemctl"
}

services_collect_failed() {
    local warning
    local critical
    local unit
    local load_state
    local active_state
    local sub_state
    local description
    local count=0
    local status

    warning="$(services_config_get HC_SERVICES_FAILED_WARNING_COUNT 1)"
    critical="$(services_config_get HC_SERVICES_FAILED_CRITICAL_COUNT 3)"

    collector_table_create \
        "services" \
        "units" \
        "failed" \
        "Serviços com falha" \
        $'Unidade\tCarregamento\tEstado\tSubestado\tDescrição' \
        "Serviços systemd no estado failed." \
        "${HC_STATUS_OK:-OK}"

    while IFS=$'\t' read -r \
        unit \
        load_state \
        active_state \
        sub_state \
        description; do

        [[ -n "$unit" ]] || continue

        count=$((count + 1))

        collector_table_add_row \
            "services" \
            "units" \
            "failed" \
            "$unit" \
            "$load_state" \
            "$active_state" \
            "$sub_state" \
            "$description"
    done < <(
        LC_ALL=C systemctl list-units \
            --type=service \
            --state=failed \
            --all \
            --no-legend \
            --no-pager 2>/dev/null |
        awk '
            {
                unit = $1
                load_state = $2
                active_state = $3
                sub_state = $4

                $1 = ""
                $2 = ""
                $3 = ""
                $4 = ""

                sub(/^[[:space:]]+/, "", $0)

                printf "%s\t%s\t%s\t%s\t%s\n",
                    unit,
                    load_state,
                    active_state,
                    sub_state,
                    $0
            }
        '
    )

    status="$(
        utils_status_from_high_usage \
            "$count" \
            "$warning" \
            "$critical"
    )"

    collector_metric_set \
        "services" \
        "summary" \
        "failed_count" \
        "Serviços com falha" \
        "$count" \
        "$count" \
        "integer" \
        "services" \
        "$status" \
        "Quantidade de serviços systemd com falha." \
        "systemctl"

    collector_table_set_status \
        "services" \
        "units" \
        "failed" \
        "$status"

    if ((count > 0)); then
        collector_alert_add \
            "services" \
            "$status" \
            "Serviços systemd com falha" \
            "Foram encontrados ${count} serviços no estado failed." \
            "Execute systemctl --failed e consulte journalctl para identificar as causas."
    fi
}

services_collect_enabled() {
    local limit
    local unit
    local state
    local preset
    local count=0

    limit="$(services_config_get HC_SERVICES_MAX_RESULTS 200)"

    collector_table_create \
        "services" \
        "configuration" \
        "enabled" \
        "Serviços habilitados" \
        $'Unidade\tEstado\tPreset' \
        "Serviços configurados para inicialização automática." \
        "${HC_STATUS_OK:-OK}"

    while IFS=$'\t' read -r unit state preset; do
        [[ -n "$unit" ]] || continue

        count=$((count + 1))

        collector_table_add_row \
            "services" \
            "configuration" \
            "enabled" \
            "$unit" \
            "$state" \
            "$preset"
    done < <(
        LC_ALL=C systemctl list-unit-files \
            --type=service \
            --state=enabled \
            --no-legend \
            --no-pager 2>/dev/null |
        awk -v limit="$limit" '
            NR <= limit {
                printf "%s\t%s\t%s\n",
                    $1,
                    $2,
                    $3
            }
        '
    )

    collector_metric_set \
        "services" \
        "summary" \
        "enabled_count" \
        "Serviços habilitados" \
        "$count" \
        "$count" \
        "integer" \
        "services" \
        "${HC_STATUS_OK:-OK}" \
        "Quantidade de serviços habilitados no boot." \
        "systemctl"
}

services_collect_disabled() {
    local limit
    local unit
    local state
    local preset
    local count=0

    limit="$(services_config_get HC_SERVICES_MAX_RESULTS 200)"

    collector_table_create \
        "services" \
        "configuration" \
        "disabled" \
        "Serviços desabilitados" \
        $'Unidade\tEstado\tPreset' \
        "Serviços desabilitados para inicialização automática." \
        "${HC_STATUS_OK:-OK}"

    while IFS=$'\t' read -r unit state preset; do
        [[ -n "$unit" ]] || continue

        count=$((count + 1))

        collector_table_add_row \
            "services" \
            "configuration" \
            "disabled" \
            "$unit" \
            "$state" \
            "$preset"
    done < <(
        LC_ALL=C systemctl list-unit-files \
            --type=service \
            --state=disabled \
            --no-legend \
            --no-pager 2>/dev/null |
        awk -v limit="$limit" '
            NR <= limit {
                printf "%s\t%s\t%s\n",
                    $1,
                    $2,
                    $3
            }
        '
    )

    collector_metric_set \
        "services" \
        "summary" \
        "disabled_count" \
        "Serviços desabilitados" \
        "$count" \
        "$count" \
        "integer" \
        "services" \
        "${HC_STATUS_OK:-OK}" \
        "Quantidade de serviços desabilitados." \
        "systemctl"
}

services_collect_expected() {
    local expected_raw
    local ignored_raw
    local item
    local unit
    local load_state
    local active_state
    local sub_state
    local unit_file_state
    local status
    local required_status
    local -a expected_services=()
    local -a ignored_services=()

    expected_raw="$(services_config_get HC_SERVICES_EXPECTED "ssh,cron")"
    ignored_raw="$(services_config_get HC_SERVICES_IGNORED "")"

    required_status="$(
        services_config_get \
            HC_SERVICES_REQUIRED_INACTIVE_STATUS \
            CRITICAL
    )"

    IFS=',' read -r -a expected_services <<<"$expected_raw"
    IFS=',' read -r -a ignored_services <<<"$ignored_raw"

    collector_table_create \
        "services" \
        "expected" \
        "required_services" \
        "Serviços esperados" \
        $'Serviço\tCarregamento\tEstado\tSubestado\tInicialização\tStatus' \
        "Serviços considerados necessários para o servidor." \
        "${HC_STATUS_OK:-OK}"

    for item in "${expected_services[@]}"; do
        item="$(utils_trim "$item")"

        [[ -n "$item" ]] || continue

        if utils_array_contains "$item" "${ignored_services[@]}"; then
            continue
        fi

        unit="$(services_normalize_unit_name "$item")"

        load_state="$(
            systemctl show "$unit" \
                --property=LoadState \
                --value 2>/dev/null ||
            printf 'not-found'
        )"

        active_state="$(
            systemctl show "$unit" \
                --property=ActiveState \
                --value 2>/dev/null ||
            printf 'inactive'
        )"

        sub_state="$(
            systemctl show "$unit" \
                --property=SubState \
                --value 2>/dev/null ||
            printf 'unknown'
        )"

        unit_file_state="$(
            systemctl is-enabled "$unit" 2>/dev/null ||
            printf 'not-found'
        )"

        status="${HC_STATUS_OK:-OK}"

        if [[ "$load_state" == "not-found" ||
            "$active_state" != "active" ]]; then

            status="$required_status"

            collector_alert_add \
                "services" \
                "$status" \
                "Serviço esperado indisponível" \
                "O serviço ${unit} possui estado ${active_state}/${sub_state}." \
                "Verifique instalação, configuração e logs do serviço."
        elif [[ "$unit_file_state" == "disabled" ]]; then
            status="$(
                services_config_get \
                    HC_SERVICES_REQUIRED_DISABLED_STATUS \
                    WARNING
            )"
        fi

        collector_table_add_row \
            "services" \
            "expected" \
            "required_services" \
            "$unit" \
            "$load_state" \
            "$active_state" \
            "$sub_state" \
            "$unit_file_state" \
            "$status"
    done
}

services_collect_timers() {
    local timer
    local next
    local left
    local last
    local passed
    local activates

    collector_table_create \
        "services" \
        "timers" \
        "active_timers" \
        "Timers systemd" \
        $'Timer\tPróxima execução\tRestante\tÚltima execução\tDecorrido\tAtiva' \
        "Timers systemd configurados no servidor." \
        "${HC_STATUS_OK:-OK}"

    while IFS=$'\t' read -r \
        timer \
        next \
        left \
        last \
        passed \
        activates; do

        [[ -n "$timer" ]] || continue

        collector_table_add_row \
            "services" \
            "timers" \
            "active_timers" \
            "$timer" \
            "$next" \
            "$left" \
            "$last" \
            "$passed" \
            "$activates"
    done < <(
        LC_ALL=C systemctl list-timers \
            --all \
            --no-legend \
            --no-pager 2>/dev/null |
        awk '
            {
                next_run = $1 " " $2 " " $3 " " $4
                left = $5
                last_run = $6 " " $7 " " $8 " " $9
                passed = $10
                timer = $11
                activates = $12

                printf "%s\t%s\t%s\t%s\t%s\t%s\n",
                    timer,
                    next_run,
                    left,
                    last_run,
                    passed,
                    activates
            }
        '
    )
}

services_collect_sockets() {
    local unit
    local load_state
    local active_state
    local sub_state
    local description

    collector_table_create \
        "services" \
        "sockets" \
        "active_sockets" \
        "Sockets systemd" \
        $'Unidade\tCarregamento\tEstado\tSubestado\tDescrição' \
        "Unidades socket gerenciadas pelo systemd." \
        "${HC_STATUS_OK:-OK}"

    while IFS=$'\t' read -r \
        unit \
        load_state \
        active_state \
        sub_state \
        description; do

        [[ -n "$unit" ]] || continue

        collector_table_add_row \
            "services" \
            "sockets" \
            "active_sockets" \
            "$unit" \
            "$load_state" \
            "$active_state" \
            "$sub_state" \
            "$description"
    done < <(
        LC_ALL=C systemctl list-units \
            --type=socket \
            --all \
            --no-legend \
            --no-pager 2>/dev/null |
        awk '
            {
                unit = $1
                load_state = $2
                active_state = $3
                sub_state = $4

                $1 = ""
                $2 = ""
                $3 = ""
                $4 = ""

                sub(/^[[:space:]]+/, "", $0)

                printf "%s\t%s\t%s\t%s\t%s\n",
                    unit,
                    load_state,
                    active_state,
                    sub_state,
                    $0
            }
        '
    )
}

services_run() {
    if ! services_systemd_available; then
        collector_metric_set \
            "services" \
            "systemd" \
            "available" \
            "Systemd disponível" \
            "Não" \
            "false" \
            "boolean" \
            "" \
            "${HC_STATUS_CRITICAL:-CRITICAL}" \
            "Systemd não está disponível no ambiente atual." \
            "systemctl"

        collector_alert_add \
            "services" \
            "${HC_STATUS_CRITICAL:-CRITICAL}" \
            "Systemd indisponível" \
            "Não foi possível consultar os serviços do sistema." \
            "Verifique se o ambiente utiliza systemd."

        return 0
    fi

    collector_metric_set \
        "services" \
        "systemd" \
        "available" \
        "Systemd disponível" \
        "Sim" \
        "true" \
        "boolean" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Systemd está disponível para consulta." \
        "systemctl"

    if services_config_enabled HC_SERVICES_INCLUDE_RUNNING 1; then
        services_collect_running
    fi

    if services_config_enabled HC_SERVICES_INCLUDE_FAILED 1; then
        services_collect_failed
    fi

    if services_config_enabled HC_SERVICES_INCLUDE_ENABLED 1; then
        services_collect_enabled
    fi

    if services_config_enabled HC_SERVICES_INCLUDE_DISABLED 0; then
        services_collect_disabled
    fi

    services_collect_expected

    if services_config_enabled HC_SERVICES_INCLUDE_TIMERS 1; then
        services_collect_timers
    fi

    if services_config_enabled HC_SERVICES_INCLUDE_SOCKETS 1; then
        services_collect_sockets
    fi

    return 0
}

services_validate() {
    local failure=0
    local systemd_available=""
    local metric_count=0
    local table_count=0

    collector_initialize
    collector_module_start "services" "Serviços"

    if ! services_run; then
        printf 'services_run retornou falha.\n' >&2
        failure=1
    fi

    systemd_available="$(
        collector_metric_get \
            "services" \
            "systemd" \
            "available" \
            "raw_value" 2>/dev/null ||
        true
    )"

    metric_count="$(collector_metric_count services)"
    table_count="$(collector_table_count services)"

    if [[ "$systemd_available" != "true" ]]; then
        printf 'Systemd não foi detectado como disponível.\n' >&2
        failure=1
    fi

    if [[ ! "$metric_count" =~ ^[0-9]+$ ]] ||
        ((metric_count < 3)); then

        printf \
            'Quantidade insuficiente de métricas de serviços: %s\n' \
            "$metric_count" >&2

        failure=1
    fi

    if [[ ! "$table_count" =~ ^[0-9]+$ ]] ||
        ((table_count < 4)); then

        printf \
            'Quantidade insuficiente de tabelas de serviços: %s\n' \
            "$table_count" >&2

        failure=1
    fi

    collector_module_finish \
        "services" \
        "$(collector_module_get_status services)" \
        "Validação concluída."

    collector_finalize

    return "$failure"
}
