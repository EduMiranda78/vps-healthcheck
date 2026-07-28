#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_REPORT_HTML_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_REPORT_HTML_LOADED=1

report_html_escape() {
    local value="${1:-}"

    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    value="${value//\"/&quot;}"
    value="${value//\'/&#39;}"

    printf '%s' "$value"
}

report_html_status_class() {
    local status="${1:-UNKNOWN}"

    case "$status" in
        OK)
            printf "ok"
            ;;
        WARNING)
            printf "warning"
            ;;
        CRITICAL)
            printf "critical"
            ;;
        SKIPPED)
            printf "skipped"
            ;;
        *)
            printf "unknown"
            ;;
    esac
}

report_html_header() {

cat <<'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">

<title>vps-healthcheck</title>

<style>

body {
    font-family: Arial, Helvetica, sans-serif;
    background: #111827;
    color: #e5e7eb;
    margin: 0;
    padding: 20px;
}

h1, h2, h3 {
    margin-top: 0;
}

.card {
    background: #1f2937;
    border-radius: 8px;
    padding: 18px;
    margin-bottom: 20px;
}

.grid {
    display: grid;
    grid-template-columns: repeat(auto-fit,minmax(250px,1fr));
    gap: 15px;
}

.status {
    padding: 8px 12px;
    border-radius: 5px;
    font-weight: bold;
    display: inline-block;
}

.ok {
    background:#166534;
    color:#dcfce7;
}

.warning {
    background:#854d0e;
    color:#fef9c3;
}

.critical {
    background:#991b1b;
    color:#fee2e2;
}

.skipped {
    background:#374151;
    color:#d1d5db;
}

.unknown {
    background:#374151;
    color:#d1d5db;
}

table {
    width:100%;
    border-collapse:collapse;
    margin-top:10px;
}

th {
    background:#374151;
    text-align:left;
}

td, th {
    padding:8px;
    border-bottom:1px solid #374151;
}

.small {
    color:#9ca3af;
    font-size:12px;
}

.alert {
    border-left:5px solid #ef4444;
    padding:12px;
    margin-bottom:10px;
    background:#1f2937;
}

</style>

</head>

<body>
EOF

}

report_html_footer() {

cat <<'EOF'
</body>
</html>
EOF

}

report_html_write_header() {

cat <<EOF

<div class="card">

<h1>
vps-healthcheck
</h1>

<p>
<b>Execução:</b>
$(report_html_escape "$(collector_meta_get execution_id)")
</p>

<p>
<b>Host:</b>
$(report_html_escape "$(hostname)")
</p>

<p>
<b>Início:</b>
$(report_html_escape "$(collector_meta_get started_at)")
</p>

<p>
<b>Duração:</b>
$(report_html_escape "$(collector_meta_get duration_seconds)") segundos
</p>

<p>
Status geral:

<span class="status $(report_html_status_class "$(collector_meta_get overall_status)")">
$(report_html_escape "$(collector_meta_get overall_status)")
</span>

</p>

</div>

EOF

}

report_html_write_modules() {

cat <<EOF

<div class="card">

<h2>
Módulos
</h2>

<div class="grid">

EOF

local module
local label
local status
local duration

for module in "${HC_COLLECTOR_MODULE_ORDER[@]}"; do

    label="${HC_COLLECTOR_MODULE_LABELS[$module]:-$module}"
    status="${HC_COLLECTOR_MODULE_STATUS[$module]:-UNKNOWN}"
    duration="${HC_COLLECTOR_MODULE_DURATION_SECONDS[$module]:-0}"

cat <<EOF

<div class="card">

<h3>
$(report_html_escape "$label")
</h3>

<p>
<span class="status $(report_html_status_class "$status")">
$(report_html_escape "$status")
</span>
</p>

<p class="small">
Tempo: ${duration}s
</p>

</div>

EOF

done

cat <<EOF

</div>

</div>

EOF

}

report_html_write_metrics() {

cat <<EOF

<div class="card">

<h2>
Métricas
</h2>

<table>

<tr>
<th>Módulo</th>
<th>Nome</th>
<th>Valor</th>
<th>Status</th>
</tr>

EOF

local metric
local status

for metric in "${HC_COLLECTOR_METRIC_ORDER[@]}"; do

status="${HC_COLLECTOR_METRIC_STATUS[$metric]:-UNKNOWN}"

cat <<EOF

<tr>

<td>
$(report_html_escape "${HC_COLLECTOR_METRIC_MODULE[$metric]}")
</td>

<td>
$(report_html_escape "${HC_COLLECTOR_METRIC_LABEL[$metric]}")
</td>

<td>
$(report_html_escape "${HC_COLLECTOR_METRIC_VALUE[$metric]}")
$(report_html_escape "${HC_COLLECTOR_METRIC_UNIT[$metric]}")
</td>

<td>

<span class="status $(report_html_status_class "$status")">

$(report_html_escape "$status")

</span>

</td>

</tr>

EOF

done

cat <<EOF

</table>

</div>

EOF

}

report_html_write_tables() {

local table
local module
local section
local key
local rows
local index
local row

for table in "${HC_COLLECTOR_TABLE_ORDER[@]}"; do


module="${HC_COLLECTOR_TABLE_MODULE[$table]}"
section="${HC_COLLECTOR_TABLE_SECTION[$table]}"
key="${HC_COLLECTOR_TABLE_KEY[$table]}"
rows="${HC_COLLECTOR_TABLE_ROW_COUNT[$table]:-0}"


cat <<EOF

<div class="card">

<h2>
$(report_html_escape "${HC_COLLECTOR_TABLE_LABEL[$table]}")
</h2>

<p class="small">
Módulo: ${module}
</p>

<table>

<tr>
<th>
Dados
</th>
</tr>

EOF


for ((index=0; index<rows; index++)); do

row="$(
collector_table_get_row \
"$module" \
"$section" \
"$key" \
"$index"
)"

cat <<EOF

<tr>
<td>
$(report_html_escape "$row")
</td>
</tr>

EOF

done


cat <<EOF

</table>

</div>

EOF


done

}

report_html_write_alerts() {


cat <<EOF

<div class="card">

<h2>
Alertas
</h2>

EOF


local alert

if [[ "${#HC_COLLECTOR_ALERT_ORDER[@]}" -eq 0 ]]; then

cat <<EOF

<p>
Nenhum alerta encontrado.
</p>

EOF

else

for alert in "${HC_COLLECTOR_ALERT_ORDER[@]}"; do


cat <<EOF

<div class="alert">

<h3>

$(report_html_escape "${HC_COLLECTOR_ALERT_TITLE[$alert]}")

</h3>


<p>

$(report_html_escape "${HC_COLLECTOR_ALERT_MESSAGE[$alert]}")

</p>


<p class="small">

$(report_html_escape "${HC_COLLECTOR_ALERT_RECOMMENDATION[$alert]}")

</p>


</div>

EOF


done

fi


cat <<EOF

</div>

EOF

}

report_html_generate() {

local output="${1:-}"

if [[ -z "$output" ]]; then
    printf "Arquivo HTML não informado.\n" >&2
    return 1
fi


mkdir -p "$(dirname "$output")"


{

report_html_header

report_html_write_header

report_html_write_modules

report_html_write_metrics

report_html_write_tables

report_html_write_alerts

report_html_footer


} > "$output"


printf '%s\n' "$output"

}

report_html_validate() {

local file="/tmp/vps-healthcheck-test.html"

collector_initialize

collector_meta_set execution_id TEST_HTML
collector_meta_set overall_status OK

report_html_generate "$file"


grep -q "vps-healthcheck" "$file"

}
