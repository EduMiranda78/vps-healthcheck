#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_REPORT_JSON_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_REPORT_JSON_LOADED=1

report_json_escape() {
    local value="${1:-}"

    if declare -F utils_json_escape >/dev/null 2>&1; then
        utils_json_escape "$value"
        return
    fi

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"

    printf '%s' "$value"
}

report_json_quote() {
    printf '"%s"' \
        "$(report_json_escape "${1:-}")"
}

report_json_bool() {
    local value="${1:-false}"

    case "$value" in
        true|1|yes|YES)
            printf "true"
            ;;
        *)
            printf "false"
            ;;
    esac
}

report_json_write_modules() {
    local first=1
    local module
    local label
    local status
    local duration
    local message

    printf '"modules":{'

    for module in "${HC_COLLECTOR_MODULE_ORDER[@]}"; do

        label="${HC_COLLECTOR_MODULE_LABELS[$module]:-$module}"
        status="${HC_COLLECTOR_MODULE_STATUS[$module]:-UNKNOWN}"
        duration="${HC_COLLECTOR_MODULE_DURATION_SECONDS[$module]:-0}"
        message="${HC_COLLECTOR_MODULE_MESSAGES[$module]:-}"

        if ((first == 0)); then
            printf ","
        fi

        first=0

        printf '"%s":{' \
            "$(report_json_escape "$module")"

        printf '"label":%s,' \
            "$(report_json_quote "$label")"

        printf '"status":%s,' \
            "$(report_json_quote "$status")"

        printf '"duration_seconds":%s,' \
            "$duration"

        printf '"message":%s' \
            "$(report_json_quote "$message")"

        printf '}'

    done

    printf '}'
}

report_json_write_metrics() {
    local first=1
    local metric
    local module
    local section
    local key

    printf '"metrics":['

    for metric in "${HC_COLLECTOR_METRIC_ORDER[@]}"; do

        module="${HC_COLLECTOR_METRIC_MODULE[$metric]}"
        section="${HC_COLLECTOR_METRIC_SECTION[$metric]}"
        key="${HC_COLLECTOR_METRIC_KEY[$metric]}"

        if ((first == 0)); then
            printf ","
        fi

        first=0

        printf '{'

        printf '"module":%s,' \
            "$(report_json_quote "$module")"

        printf '"section":%s,' \
            "$(report_json_quote "$section")"

        printf '"key":%s,' \
            "$(report_json_quote "$key")"

        printf '"label":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_METRIC_LABEL[$metric]}")"

        printf '"value":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_METRIC_VALUE[$metric]}")"

        printf '"raw_value":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_METRIC_RAW_VALUE[$metric]}")"

        printf '"type":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_METRIC_TYPE[$metric]}")"

        printf '"unit":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_METRIC_UNIT[$metric]}")"

        printf '"status":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_METRIC_STATUS[$metric]}")"

        printf '"description":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_METRIC_DESCRIPTION[$metric]}")"

        printf '"source":%s' \
            "$(report_json_quote "${HC_COLLECTOR_METRIC_SOURCE[$metric]}")"

        printf '}'

    done

    printf ']'
}

report_json_write_tables() {
    local first_table=1
    local table
    local module
    local section
    local key
    local rows
    local index
    local row
    local first_column

    printf '"tables":['

    for table in "${HC_COLLECTOR_TABLE_ORDER[@]}"; do

        module="${HC_COLLECTOR_TABLE_MODULE[$table]}"
        section="${HC_COLLECTOR_TABLE_SECTION[$table]}"
        key="${HC_COLLECTOR_TABLE_KEY[$table]}"
        rows="${HC_COLLECTOR_TABLE_ROW_COUNT[$table]:-0}"

        if ((first_table == 0)); then
            printf ","
        fi

        first_table=0

        printf '{'

        printf '"module":%s,' \
            "$(report_json_quote "$module")"

        printf '"section":%s,' \
            "$(report_json_quote "$section")"

        printf '"key":%s,' \
            "$(report_json_quote "$key")"

        printf '"label":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_TABLE_LABEL[$table]}")"

        printf '"status":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_TABLE_STATUS[$table]}")"

        printf '"columns":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_TABLE_COLUMNS[$table]}")"

        printf '"rows":['

        first_column=1

        for ((index=0; index<rows; index++)); do

            row="$(
                collector_table_get_row \
                    "$module" \
                    "$section" \
                    "$key" \
                    "$index"
            )"

            if ((first_column == 0)); then
                printf ","
            fi

            first_column=0

            printf '%s' \
                "$(report_json_quote "$row")"

        done

        printf ']'

        printf '}'

    done

    printf ']'
}

report_json_write_alerts() {
    local first=1
    local alert

    printf '"alerts":['

    for alert in "${HC_COLLECTOR_ALERT_ORDER[@]}"; do

        if ((first == 0)); then
            printf ","
        fi

        first=0

        printf '{'

        printf '"module":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_ALERT_MODULE[$alert]}")"

        printf '"status":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_ALERT_STATUS[$alert]}")"

        printf '"title":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_ALERT_TITLE[$alert]}")"

        printf '"message":%s,' \
            "$(report_json_quote "${HC_COLLECTOR_ALERT_MESSAGE[$alert]}")"

        printf '"recommendation":%s' \
            "$(report_json_quote "${HC_COLLECTOR_ALERT_RECOMMENDATION[$alert]}")"

        printf '}'

    done

    printf ']'
}

report_json_generate() {
    local output="${1:-}"

    if [[ -z "$output" ]]; then
        printf "Arquivo JSON não informado.\n" >&2
        return 1
    fi

    mkdir -p "$(dirname "$output")"

    {
        printf '{'

        printf '"schema_version":"1.0",'

        printf '"generated_at":%s,' \
            "$(report_json_quote "$(date --iso-8601=seconds)")"

        printf '"execution_id":%s,' \
            "$(report_json_quote "$(collector_meta_get execution_id)")"

        printf '"host":%s,' \
            "$(report_json_quote "$(hostname)")"

        printf '"status":%s,' \
            "$(report_json_quote "$(collector_meta_get overall_status)")"

        report_json_write_modules

        printf ','

        report_json_write_metrics

        printf ','

        report_json_write_tables

        printf ','

        report_json_write_alerts

        printf '}'

    } > "$output"

    printf '%s\n' "$output"
}

report_json_validate() {
    local temp_file="/tmp/vps-healthcheck-json-test.json"

    collector_initialize

    collector_meta_set execution_id TEST_JSON
    collector_meta_set overall_status OK

    report_json_generate "$temp_file"

    if command -v jq >/dev/null 2>&1; then

        jq empty "$temp_file"

    else

        grep -q '"schema_version"' "$temp_file"

    fi
}
