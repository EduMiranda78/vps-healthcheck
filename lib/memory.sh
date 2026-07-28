#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_MEMORY_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_MEMORY_LOADED=1

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------

memory_config_enabled() {
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

memory_config_get() {
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
# Leitura de /proc/meminfo
# ---------------------------------------------------------------------------

memory_read_meminfo() {
    local destination_name="${1:-}"
    local key
    local value
    local unit

    if [[ -z "$destination_name" || ! -r /proc/meminfo ]]; then
        return 1
    fi

    local -n destination_ref="$destination_name"

    destination_ref=()

    while IFS=' :' read -r key value unit; do
        [[ -n "$key" ]] || continue

        value="${value:-0}"

        if [[ ! "$value" =~ ^[0-9]+$ ]]; then
            value=0
        fi

        if [[ "${unit:-}" == "kB" ]]; then
            destination_ref["$key"]=$((value * 1024))
        else
            destination_ref["$key"]="$value"
        fi
    done </proc/meminfo

    return 0
}

memory_value_or_zero() {
    local array_name="${1:-}"
    local key="${2:-}"

    local -n array_ref="$array_name"

    printf '%s\n' "${array_ref[$key]:-0}"
}

# ---------------------------------------------------------------------------
# Cálculos
# ---------------------------------------------------------------------------

memory_calculate_metrics() {
    local meminfo_name="${1:-}"
    local result_name="${2:-}"

    if [[ -z "$meminfo_name" || -z "$result_name" ]]; then
        return 1
    fi

    local -n meminfo_ref="$meminfo_name"
    local -n result_ref="$result_name"

    local total
    local free
    local available
    local buffers
    local cached
    local sreclaimable
    local shmem
    local swap_total
    local swap_free

    total="${meminfo_ref[MemTotal]:-0}"
    free="${meminfo_ref[MemFree]:-0}"
    available="${meminfo_ref[MemAvailable]:-0}"
    buffers="${meminfo_ref[Buffers]:-0}"
    cached="${meminfo_ref[Cached]:-0}"
    sreclaimable="${meminfo_ref[SReclaimable]:-0}"
    shmem="${meminfo_ref[Shmem]:-0}"
    swap_total="${meminfo_ref[SwapTotal]:-0}"
    swap_free="${meminfo_ref[SwapFree]:-0}"

    if ((available <= 0)); then
        available=$(
            (
                free +
                buffers +
                cached +
                sreclaimable -
                shmem
            )
        )

        if ((available < 0)); then
            available=0
        fi
    fi

    result_ref["total_bytes"]="$total"
    result_ref["free_bytes"]="$free"
    result_ref["available_bytes"]="$available"
    result_ref["buffers_bytes"]="$buffers"
    result_ref["cached_bytes"]="$cached"
    result_ref["reclaimable_bytes"]="$sreclaimable"
    result_ref["shared_bytes"]="$shmem"

    result_ref["used_bytes"]=$((total - available))

    if ((result_ref[used_bytes] < 0)); then
        result_ref["used_bytes"]=0
    fi

    result_ref["swap_total_bytes"]="$swap_total"
    result_ref["swap_free_bytes"]="$swap_free"
    result_ref["swap_used_bytes"]=$((swap_total - swap_free))

    if ((result_ref[swap_used_bytes] < 0)); then
        result_ref["swap_used_bytes"]=0
    fi

    if ((total > 0)); then
        result_ref["usage_percent"]="$(
            awk \
                -v used="${result_ref[used_bytes]}" \
                -v total="$total" \
                'BEGIN {
                    printf "%.2f\n", (used / total) * 100
                }'
        )"

        result_ref["available_percent"]="$(
            awk \
                -v available="$available" \
                -v total="$total" \
                'BEGIN {
                    printf "%.2f\n", (available / total) * 100
                }'
        )"
    else
        result_ref["usage_percent"]="0.00"
        result_ref["available_percent"]="0.00"
    fi

    if ((swap_total > 0)); then
        result_ref["swap_usage_percent"]="$(
            awk \
                -v used="${result_ref[swap_used_bytes]}" \
                -v total="$swap_total" \
                'BEGIN {
                    printf "%.2f\n", (used / total) * 100
                }'
        )"
    else
        result_ref["swap_usage_percent"]="0.00"
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Memória principal
# ---------------------------------------------------------------------------

memory_collect_main() {
    local -A meminfo=()
    local -A metrics=()

    local usage_warning
    local usage_critical
    local available_warning
    local available_critical

    local usage_status
    local available_status
    local overall_status

    memory_read_meminfo meminfo
    memory_calculate_metrics meminfo metrics

    usage_warning="$(
        memory_config_get \
            "HC_MEMORY_USAGE_WARNING_PERCENT" \
            "80"
    )"

    usage_critical="$(
        memory_config_get \
            "HC_MEMORY_USAGE_CRITICAL_PERCENT" \
            "92"
    )"

    available_warning="$(
        memory_config_get \
            "HC_MEMORY_AVAILABLE_WARNING_PERCENT" \
            "20"
    )"

    available_critical="$(
        memory_config_get \
            "HC_MEMORY_AVAILABLE_CRITICAL_PERCENT" \
            "8"
    )"

    usage_status="$(
        utils_status_from_high_usage \
            "${metrics[usage_percent]}" \
            "$usage_warning" \
            "$usage_critical"
    )"

    available_status="$(
        utils_status_from_low_remaining \
            "${metrics[available_percent]}" \
            "$available_warning" \
            "$available_critical"
    )"

    overall_status="$(
        collector_worst_status \
            "$usage_status" \
            "$available_status"
    )"

    collector_metric_set \
        "memory" \
        "physical" \
        "total" \
        "Memória total" \
        "$(utils_bytes_to_human "${metrics[total_bytes]}" "2")" \
        "${metrics[total_bytes]}" \
        "bytes" \
        "bytes" \
        "${HC_STATUS_OK:-OK}" \
        "Quantidade total de memória física." \
        "/proc/meminfo"

    collector_metric_set \
        "memory" \
        "physical" \
        "used" \
        "Memória usada" \
        "$(utils_bytes_to_human "${metrics[used_bytes]}" "2")" \
        "${metrics[used_bytes]}" \
        "bytes" \
        "bytes" \
        "$usage_status" \
        "Memória efetivamente utilizada, considerando MemAvailable." \
        "/proc/meminfo"

    collector_metric_set \
        "memory" \
        "physical" \
        "available" \
        "Memória disponível" \
        "$(utils_bytes_to_human "${metrics[available_bytes]}" "2")" \
        "${metrics[available_bytes]}" \
        "bytes" \
        "bytes" \
        "$available_status" \
        "Memória estimada como disponível para novas aplicações." \
        "/proc/meminfo"

    collector_metric_set \
        "memory" \
        "physical" \
        "free" \
        "Memória livre" \
        "$(utils_bytes_to_human "${metrics[free_bytes]}" "2")" \
        "${metrics[free_bytes]}" \
        "bytes" \
        "bytes" \
        "${HC_STATUS_OK:-OK}" \
        "Memória completamente livre." \
        "/proc/meminfo"

    collector_metric_set \
        "memory" \
        "physical" \
        "usage_percent" \
        "Uso de memória" \
        "${metrics[usage_percent]}%" \
        "${metrics[usage_percent]}" \
        "percentage" \
        "%" \
        "$usage_status" \
        "Percentual de memória física em uso." \
        "/proc/meminfo"

    collector_metric_set \
        "memory" \
        "physical" \
        "available_percent" \
        "Memória disponível" \
        "${metrics[available_percent]}%" \
        "${metrics[available_percent]}" \
        "percentage" \
        "%" \
        "$available_status" \
        "Percentual de memória disponível." \
        "/proc/meminfo"

    collector_metric_set \
        "memory" \
        "cache" \
        "cached" \
        "Cache de páginas" \
        "$(utils_bytes_to_human "${metrics[cached_bytes]}" "2")" \
        "${metrics[cached_bytes]}" \
        "bytes" \
        "bytes" \
        "${HC_STATUS_OK:-OK}" \
        "Memória usada para cache de páginas." \
        "/proc/meminfo"

    collector_metric_set \
        "memory" \
        "cache" \
        "buffers" \
        "Buffers" \
        "$(utils_bytes_to_human "${metrics[buffers_bytes]}" "2")" \
        "${metrics[buffers_bytes]}" \
        "bytes" \
        "bytes" \
        "${HC_STATUS_OK:-OK}" \
        "Memória usada em buffers de bloco." \
        "/proc/meminfo"

    collector_metric_set \
        "memory" \
        "cache" \
        "reclaimable" \
        "Cache recuperável" \
        "$(utils_bytes_to_human "${metrics[reclaimable_bytes]}" "2")" \
        "${metrics[reclaimable_bytes]}" \
        "bytes" \
        "bytes" \
        "${HC_STATUS_OK:-OK}" \
        "Memória de slab potencialmente recuperável." \
        "/proc/meminfo"

    collector_metric_set \
        "memory" \
        "cache" \
        "shared" \
        "Memória compartilhada" \
        "$(utils_bytes_to_human "${metrics[shared_bytes]}" "2")" \
        "${metrics[shared_bytes]}" \
        "bytes" \
        "bytes" \
        "${HC_STATUS_OK:-OK}" \
        "Memória compartilhada e tmpfs." \
        "/proc/meminfo"

    if [[ "$overall_status" == "${HC_STATUS_CRITICAL:-CRITICAL}" ]]; then
        collector_alert_add \
            "memory" \
            "$overall_status" \
            "Memória em nível crítico" \
            "O uso de memória está em ${metrics[usage_percent]}%, com ${metrics[available_percent]}% disponível." \
            "Identifique processos pesados, vazamentos de memória ou limite insuficiente da VPS."
    elif [[ "$overall_status" == "${HC_STATUS_WARNING:-WARNING}" ]]; then
        collector_alert_add \
            "memory" \
            "$overall_status" \
            "Uso elevado de memória" \
            "O uso de memória está em ${metrics[usage_percent]}%, com ${metrics[available_percent]}% disponível." \
            "Acompanhe os processos com maior consumo e a evolução do uso."
    fi
}

# ---------------------------------------------------------------------------
# Swap
# ---------------------------------------------------------------------------

memory_collect_swap() {
    local -A meminfo=()
    local -A metrics=()

    local warning
    local critical
    local status
    local display_status

    memory_read_meminfo meminfo
    memory_calculate_metrics meminfo metrics

    warning="$(
        memory_config_get \
            "HC_SWAP_USAGE_WARNING_PERCENT" \
            "50"
    )"

    critical="$(
        memory_config_get \
            "HC_SWAP_USAGE_CRITICAL_PERCENT" \
            "80"
    )"

    if ((metrics[swap_total_bytes] <= 0)); then
        status="${HC_STATUS_UNKNOWN:-UNKNOWN}"
        display_status="Não configurada"
    else
        status="$(
            utils_status_from_high_usage \
                "${metrics[swap_usage_percent]}" \
                "$warning" \
                "$critical"
        )"

        display_status="${metrics[swap_usage_percent]}%"
    fi

    collector_metric_set \
        "memory" \
        "swap" \
        "total" \
        "Swap total" \
        "$(utils_bytes_to_human "${metrics[swap_total_bytes]}" "2")" \
        "${metrics[swap_total_bytes]}" \
        "bytes" \
        "bytes" \
        "$status" \
        "Quantidade total de swap configurada." \
        "/proc/meminfo"

    collector_metric_set \
        "memory" \
        "swap" \
        "used" \
        "Swap usada" \
        "$(utils_bytes_to_human "${metrics[swap_used_bytes]}" "2")" \
        "${metrics[swap_used_bytes]}" \
        "bytes" \
        "bytes" \
        "$status" \
        "Quantidade de swap atualmente utilizada." \
        "/proc/meminfo"

    collector_metric_set \
        "memory" \
        "swap" \
        "free" \
        "Swap livre" \
        "$(utils_bytes_to_human "${metrics[swap_free_bytes]}" "2")" \
        "${metrics[swap_free_bytes]}" \
        "bytes" \
        "bytes" \
        "$status" \
        "Quantidade de swap disponível." \
        "/proc/meminfo"

    collector_metric_set \
        "memory" \
        "swap" \
        "usage_percent" \
        "Uso de swap" \
        "$display_status" \
        "${metrics[swap_usage_percent]}" \
        "percentage" \
        "%" \
        "$status" \
        "Percentual de uso da swap." \
        "/proc/meminfo"

    if [[ "$status" == "${HC_STATUS_CRITICAL:-CRITICAL}" ]]; then
        collector_alert_add \
            "memory" \
            "$status" \
            "Uso crítico de swap" \
            "O uso de swap atingiu ${metrics[swap_usage_percent]}%." \
            "Verifique pressão de memória e processos com consumo elevado."
    elif [[ "$status" == "${HC_STATUS_WARNING:-WARNING}" ]]; then
        collector_alert_add \
            "memory" \
            "$status" \
            "Uso elevado de swap" \
            "O uso de swap atingiu ${metrics[swap_usage_percent]}%." \
            "Acompanhe paginação, memória disponível e desempenho."
    fi
}

# ---------------------------------------------------------------------------
# Atividade de swap
# ---------------------------------------------------------------------------

memory_read_vmstat_snapshot() {
    local destination_name="${1:-}"
    local key
    local value

    if [[ -z "$destination_name" || ! -r /proc/vmstat ]]; then
        return 1
    fi

    local -n destination_ref="$destination_name"

    destination_ref=()

    while IFS=' ' read -r key value; do
        case "$key" in
            pswpin | pswpout)
                destination_ref["$key"]="${value:-0}"
                ;;
        esac
    done </proc/vmstat

    destination_ref["pswpin"]="${destination_ref[pswpin]:-0}"
    destination_ref["pswpout"]="${destination_ref[pswpout]:-0}"

    return 0
}

memory_collect_swap_activity() {
    local -A first=()
    local -A second=()

    local sample_seconds=1
    local pages_in
    local pages_out
    local total_pages
    local warning
    local critical
    local status

    memory_read_vmstat_snapshot first
    sleep "$sample_seconds"
    memory_read_vmstat_snapshot second

    pages_in=$((second[pswpin] - first[pswpin]))
    pages_out=$((second[pswpout] - first[pswpout]))

    if ((pages_in < 0)); then
        pages_in=0
    fi

    if ((pages_out < 0)); then
        pages_out=0
    fi

    total_pages=$((pages_in + pages_out))

    warning="$(
        memory_config_get \
            "HC_SWAP_ACTIVITY_WARNING_PAGES_PER_SECOND" \
            "100"
    )"

    critical="$(
        memory_config_get \
            "HC_SWAP_ACTIVITY_CRITICAL_PAGES_PER_SECOND" \
            "1000"
    )"

    status="$(
        utils_status_from_high_usage \
            "$total_pages" \
            "$warning" \
            "$critical"
    )"

    collector_metric_set \
        "memory" \
        "swap_activity" \
        "pages_in_per_second" \
        "Páginas lidas da swap" \
        "$pages_in páginas/s" \
        "$pages_in" \
        "integer" \
        "pages/s" \
        "$status" \
        "Páginas recuperadas da swap durante a amostragem." \
        "/proc/vmstat"

    collector_metric_set \
        "memory" \
        "swap_activity" \
        "pages_out_per_second" \
        "Páginas gravadas na swap" \
        "$pages_out páginas/s" \
        "$pages_out" \
        "integer" \
        "pages/s" \
        "$status" \
        "Páginas enviadas para swap durante a amostragem." \
        "/proc/vmstat"

    collector_metric_set \
        "memory" \
        "swap_activity" \
        "total_pages_per_second" \
        "Atividade total de swap" \
        "$total_pages páginas/s" \
        "$total_pages" \
        "integer" \
        "pages/s" \
        "$status" \
        "Soma das leituras e gravações de páginas em swap." \
        "/proc/vmstat"

    if [[ "$status" != "${HC_STATUS_OK:-OK}" ]]; then
        collector_alert_add \
            "memory" \
            "$status" \
            "Atividade elevada de swap" \
            "Foram detectadas ${total_pages} páginas por segundo em atividade de swap." \
            "Verifique pressão de memória e possíveis gargalos de armazenamento."
    fi
}

# ---------------------------------------------------------------------------
# Eventos OOM
# ---------------------------------------------------------------------------

memory_collect_oom_events() {
    local count=0
    local warning
    local critical
    local status

    if command -v journalctl >/dev/null 2>&1; then
        count="$(
            journalctl \
                --no-pager \
                --since "-24 hours" \
                -k 2>/dev/null |
            grep -Eic \
                'out of memory|oom-killer|killed process' ||
            true
        )"
    elif command -v dmesg >/dev/null 2>&1; then
        count="$(
            dmesg 2>/dev/null |
            grep -Eic \
                'out of memory|oom-killer|killed process' ||
            true
        )"
    fi

    warning="$(
        memory_config_get \
            "HC_OOM_KILL_WARNING_COUNT" \
            "1"
    )"

    critical="$(
        memory_config_get \
            "HC_OOM_KILL_CRITICAL_COUNT" \
            "3"
    )"

    status="$(
        utils_status_from_high_usage \
            "$count" \
            "$warning" \
            "$critical"
    )"

    collector_metric_set \
        "memory" \
        "events" \
        "oom_kills_24h" \
        "Eventos OOM nas últimas 24h" \
        "$count" \
        "$count" \
        "integer" \
        "events" \
        "$status" \
        "Eventos relacionados ao OOM Killer nas últimas 24 horas." \
        "journalctl ou dmesg"

    if [[ "$status" != "${HC_STATUS_OK:-OK}" ]]; then
        collector_alert_add \
            "memory" \
            "$status" \
            "Eventos de falta de memória" \
            "Foram detectados ${count} eventos relacionados ao OOM Killer." \
            "Verifique processos encerrados, limites de memória e dimensionamento da VPS."
    fi
}

# ---------------------------------------------------------------------------
# Processos com maior uso de memória
# ---------------------------------------------------------------------------

memory_collect_top_processes() {
    local limit
    local pid
    local user
    local memory_percent
    local rss_kib
    local rss_bytes
    local virtual_kib
    local virtual_bytes
    local elapsed
    local command_name
    local command_line

    limit="$(
        memory_config_get \
            "HC_MEMORY_TOP_PROCESSES_LIMIT" \
            "20"
    )"

    collector_table_create \
        "memory" \
        "processes" \
        "top_memory" \
        "Processos com maior uso de memória" \
        $'PID\tUsuário\tMemória %\tRSS\tMemória virtual\tTempo\tProcesso\tComando' \
        "Processos ordenados pelo percentual de memória física utilizada." \
        "${HC_STATUS_OK:-OK}"

    while IFS=$'\t' read -r \
        pid \
        user \
        memory_percent \
        rss_kib \
        virtual_kib \
        elapsed \
        command_name \
        command_line; do

        [[ -n "$pid" ]] || continue

        rss_bytes=$((rss_kib * 1024))
        virtual_bytes=$((virtual_kib * 1024))

        collector_table_add_row \
            "memory" \
            "processes" \
            "top_memory" \
            "$pid" \
            "$user" \
            "$memory_percent" \
            "$(utils_bytes_to_human "$rss_bytes" "2")" \
            "$(utils_bytes_to_human "$virtual_bytes" "2")" \
            "$elapsed" \
            "$command_name" \
            "$command_line"
    done < <(
        ps \
            -eo pid=,user=,%mem=,rss=,vsz=,etime=,comm=,args= \
            --sort=-%mem 2>/dev/null |
        awk \
            -v limit="$limit" '
            NR <= limit {
                pid = $1
                user = $2
                memory = $3
                rss = $4
                virtual = $5
                elapsed = $6
                command_name = $7

                $1 = ""
                $2 = ""
                $3 = ""
                $4 = ""
                $5 = ""
                $6 = ""
                $7 = ""

                sub(/^[[:space:]]+/, "", $0)

                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
                    pid,
                    user,
                    memory,
                    rss,
                    virtual,
                    elapsed,
                    command_name,
                    $0
            }
            '
    )
}

# ---------------------------------------------------------------------------
# Execução
# ---------------------------------------------------------------------------

memory_run() {
    if memory_config_enabled "HC_MEMORY_INCLUDE_TOTAL" "1" ||
        memory_config_enabled "HC_MEMORY_INCLUDE_AVAILABLE" "1" ||
        memory_config_enabled "HC_MEMORY_INCLUDE_USED" "1" ||
        memory_config_enabled "HC_MEMORY_INCLUDE_CACHE" "1"; then

        memory_collect_main
    fi

    if memory_config_enabled "HC_MEMORY_INCLUDE_SWAP" "1"; then
        memory_collect_swap
        memory_collect_swap_activity
    fi

    memory_collect_oom_events

    if memory_config_enabled "HC_MEMORY_INCLUDE_TOP_PROCESSES" "1"; then
        memory_collect_top_processes
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Validação interna
# ---------------------------------------------------------------------------

memory_validate() {
    local failure=0
    local total=""
    local usage=""
    local metric_count=0
    local table_count=0

    if ! declare -F collector_initialize >/dev/null 2>&1; then
        printf 'collector_initialize não está disponível.\n' >&2
        return 1
    fi

    collector_initialize
    collector_module_start "memory" "Memória"

    if ! memory_run; then
        printf 'memory_run retornou falha.\n' >&2
        failure=1
    fi

    total="$(
        collector_metric_get \
            "memory" \
            "physical" \
            "total" \
            "raw_value" 2>/dev/null ||
        true
    )"

    usage="$(
        collector_metric_get \
            "memory" \
            "physical" \
            "usage_percent" \
            "raw_value" 2>/dev/null ||
        true
    )"

    metric_count="$(collector_metric_count "memory")"
    table_count="$(collector_table_count "memory")"

    if [[ ! "$total" =~ ^[0-9]+$ ]] || ((total <= 0)); then
        printf 'Memória total inválida: %s\n' "$total" >&2
        failure=1
    fi

    if ! utils_is_percentage "$usage"; then
        printf 'Percentual de memória inválido: %s\n' "$usage" >&2
        failure=1
    fi

    if [[ ! "$metric_count" =~ ^[0-9]+$ ]] ||
        ((metric_count < 10)); then

        printf \
            'Quantidade insuficiente de métricas de memória: %s\n' \
            "$metric_count" >&2

        failure=1
    fi

    if [[ ! "$table_count" =~ ^[0-9]+$ ]] ||
        ((table_count < 1)); then

        printf 'Tabela de processos não foi criada.\n' >&2
        failure=1
    fi

    collector_module_finish \
        "memory" \
        "$(collector_module_get_status "memory")" \
        "Validação concluída."

    collector_finalize

    return "$failure"
}
