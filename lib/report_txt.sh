#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_REPORT_TXT_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_REPORT_TXT_LOADED=1

report_txt_escape() {
    local value="${1:-}"

    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"

    printf '%s' "$value"
}

report_txt_line() {
    printf '%s\n' \
        "================================================================================"
}

report_txt_title() {
    local title="${1:-}"

    report_txt_line
    printf "%s\n" "$title"
    report_txt_line
}

report_txt_status_icon() {
    local status="${1:-UNKNOWN}"

    case "$status" in
        OK)
            printf "[OK]"
            ;;
        WARNING)
            printf "[WARN]"
            ;;
        CRITICAL)
            printf "[CRIT]"
            ;;
        SKIPPED)
            printf "[SKIP]"
            ;;
        *)
            printf "[INFO]"
            ;;
    esac
}

report_txt_write_header() {
    local output="${1:-}"

    {
        report_txt_line

        printf "vps-healthcheck\n"
        printf "Versão: %s\n" \
            "${HC_VERSION:-desconhecida}"

        printf "Host: %s\n" \
            "$(hostname 2>/dev/null || printf 'unknown')"

        printf "Execução: %s\n" \
            "$(collector_meta_get execution_id)"

        printf "Início: %s\n" \
            "$(collector_meta_get started_at)"

        printf "Fim: %s\n" \
            "$(collector_meta_get finished_at)"

        printf "Duração: %s segundos\n" \
            "$(collector_meta_get duration_seconds)"

        report_txt_line

        printf "\n"
    } > "$output"
}

report_txt_write_modules() {
    local output="${1:-}"
    local module
    local label
    local status
    local duration
    local message

    {
        printf "RESUMO DOS MÓDULOS\n"
        printf "%-20s %-12s %-10s %s\n" \
            "Módulo" \
            "Status" \
            "Tempo" \
            "Mensagem"

        printf "%-20s %-12s %-10s %s\n" \
            "--------------------" \
            "------------" \
            "----------" \
            "----------------"

        for module in "${HC_COLLECTOR_MODULE_ORDER[@]}"; do

            label="${HC_COLLECTOR_MODULE_LABELS[$module]:-$module}"
            status="${HC_COLLECTOR_MODULE_STATUS[$module]:-UNKNOWN}"
            duration="${HC_COLLECTOR_MODULE_DURATION_SECONDS[$module]:-0}"
            message="${HC_COLLECTOR_MODULE_MESSAGES[$module]:-}"

            printf "%-20s %-12s %-10s %s\n" \
                "$label" \
                "$status" \
                "${duration}s" \
                "$(report_txt_escape "$message")"

        done

        printf "\n"

    } >> "$output"
}

report_txt_write_metrics() {
    local output="${1:-}"
    local metric
    local module
    local label
    local value
    local status
    local unit

    {
        printf "MÉTRICAS\n\n"

        for metric in "${HC_COLLECTOR_METRIC_ORDER[@]}"; do

            module="${HC_COLLECTOR_METRIC_MODULE[$metric]}"
            label="${HC_COLLECTOR_METRIC_LABEL[$metric]}"
            value="${HC_COLLECTOR_METRIC_VALUE[$metric]}"
            unit="${HC_COLLECTOR_METRIC_UNIT[$metric]}"
            status="${HC_COLLECTOR_METRIC_STATUS[$metric]}"

            printf "%-15s %-35s %s %s %s\n" \
                "$module" \
                "$label" \
                "$value" \
                "$unit" \
                "[$status]"

        done

        printf "\n"

    } >> "$output"
}

report_txt_write_tables() {
    local output="${1:-}"
    local table
    local module
    local section
    local key
    local label
    local columns
    local rows
    local row
    local index

    {
        printf "TABELAS\n\n"

        for table in "${HC_COLLECTOR_TABLE_ORDER[@]}"; do

            module="${HC_COLLECTOR_TABLE_MODULE[$table]}"
            section="${HC_COLLECTOR_TABLE_SECTION[$table]}"
            key="${HC_COLLECTOR_TABLE_KEY[$table]}"
            label="${HC_COLLECTOR_TABLE_LABEL[$table]}"
            columns="${HC_COLLECTOR_TABLE_COLUMNS[$table]}"
            rows="${HC_COLLECTOR_TABLE_ROW_COUNT[$table]:-0}"

            printf "%s\n" "$label"
            printf "Módulo: %s\n" "$module"
            printf "Seção: %s\n" "$section"
            printf "Registros: %s\n" "$rows"

            printf "%s\n" \
                "$columns"

            for ((index=0; index<rows; index++)); do

                row="$(
                    collector_table_get_row \
                        "$module" \
                        "$section" \
                        "$key" \
                        "$index"
                )"

                printf "%s\n" "$row"

            done

            printf "\n"

        done

    } >> "$output"
}

report_txt_write_alerts() {
    local output="${1:-}"
    local alert
    local status
    local title
    local message
    local recommendation

    {
        printf "ALERTAS\n\n"

        if [[ "${#HC_COLLECTOR_ALERT_ORDER[@]}" -eq 0 ]]; then
            printf "Nenhum alerta encontrado.\n"
            printf "\n"
            return
        fi

        for alert in "${HC_COLLECTOR_ALERT_ORDER[@]}"; do

            status="${HC_COLLECTOR_ALERT_STATUS[$alert]}"
            title="${HC_COLLECTOR_ALERT_TITLE[$alert]}"
            message="${HC_COLLECTOR_ALERT_MESSAGE[$alert]}"
            recommendation="${HC_COLLECTOR_ALERT_RECOMMENDATION[$alert]}"

            printf "%s %s\n" \
                "$(report_txt_status_icon "$status")" \
                "$title"

            printf "Mensagem: %s\n" \
                "$(report_txt_escape "$message")"

            printf "Recomendação: %s\n\n" \
                "$(report_txt_escape "$recommendation")"

        done

    } >> "$output"
}

report_txt_generate() {
    local output="${1:-}"

    if [[ -z "$output" ]]; then
        printf "Arquivo de saída não informado.\n" >&2
        return 1
    fi

    mkdir -p "$(dirname "$output")"

    report_txt_write_header "$output"
    report_txt_write_modules "$output"
    report_txt_write_metrics "$output"
    report_txt_write_tables "$output"
    report_txt_write_alerts "$output"

    printf '%s\n' "$output"
}
