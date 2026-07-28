#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_CPU_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_CPU_LOADED=1

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------

cpu_config_enabled() {
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

cpu_config_get() {
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
# Informações estáticas
# ---------------------------------------------------------------------------

cpu_get_model() {
    local model=""

    if command -v lscpu >/dev/null 2>&1; then
        model="$(
            LC_ALL=C lscpu 2>/dev/null |
            awk -F: '
                $1 ~ /^Model name/ {
                    sub(/^[[:space:]]+/, "", $2)
                    print $2
                    exit
                }
            '
        )"
    fi

    if [[ -z "$model" && -r /proc/cpuinfo ]]; then
        model="$(
            awk -F: '
                $1 ~ /^model name/ {
                    sub(/^[[:space:]]+/, "", $2)
                    print $2
                    exit
                }
            ' /proc/cpuinfo
        )"
    fi

    printf '%s\n' "${model:-desconhecido}"
}

cpu_get_vendor() {
    local vendor=""

    if [[ -r /proc/cpuinfo ]]; then
        vendor="$(
            awk -F: '
                $1 ~ /^vendor_id/ {
                    sub(/^[[:space:]]+/, "", $2)
                    print $2
                    exit
                }
            ' /proc/cpuinfo
        )"
    fi

    printf '%s\n' "${vendor:-desconhecido}"
}

cpu_get_architecture() {
    uname -m 2>/dev/null || printf 'desconhecido\n'
}

cpu_get_threads() {
    local threads=""

    if command -v nproc >/dev/null 2>&1; then
        threads="$(nproc --all 2>/dev/null || true)"
    fi

    if [[ -z "$threads" && -r /proc/cpuinfo ]]; then
        threads="$(
            awk '
                /^processor[[:space:]]*:/ {
                    count++
                }
                END {
                    print count + 0
                }
            ' /proc/cpuinfo
        )"
    fi

    printf '%s\n' "${threads:-0}"
}

cpu_get_sockets() {
    local sockets=""

    if command -v lscpu >/dev/null 2>&1; then
        sockets="$(
            LC_ALL=C lscpu 2>/dev/null |
            awk -F: '
                $1 ~ /^Socket\(s\)/ {
                    gsub(/[[:space:]]/, "", $2)
                    print $2
                    exit
                }
            '
        )"
    fi

    printf '%s\n' "${sockets:-1}"
}

cpu_get_cores_per_socket() {
    local cores=""

    if command -v lscpu >/dev/null 2>&1; then
        cores="$(
            LC_ALL=C lscpu 2>/dev/null |
            awk -F: '
                $1 ~ /^Core\(s\) per socket/ {
                    gsub(/[[:space:]]/, "", $2)
                    print $2
                    exit
                }
            '
        )"
    fi

    printf '%s\n' "${cores:-0}"
}

cpu_get_physical_cores() {
    local sockets
    local cores_per_socket
    local physical_cores=0
    local unique_cores=""

    sockets="$(cpu_get_sockets)"
    cores_per_socket="$(cpu_get_cores_per_socket)"

    if [[ "$sockets" =~ ^[0-9]+$ ]] &&
        [[ "$cores_per_socket" =~ ^[0-9]+$ ]] &&
        ((sockets > 0 && cores_per_socket > 0)); then

        physical_cores=$((sockets * cores_per_socket))
        printf '%s\n' "$physical_cores"
        return 0
    fi

    if [[ -r /proc/cpuinfo ]]; then
        unique_cores="$(
            awk -F: '
                /^physical id/ {
                    physical = $2
                    gsub(/[[:space:]]/, "", physical)
                }

                /^core id/ {
                    core = $2
                    gsub(/[[:space:]]/, "", core)
                    seen[physical ":" core] = 1
                }

                END {
                    for (item in seen) {
                        count++
                    }

                    print count + 0
                }
            ' /proc/cpuinfo
        )"
    fi

    if [[ "$unique_cores" =~ ^[0-9]+$ ]] && ((unique_cores > 0)); then
        printf '%s\n' "$unique_cores"
    else
        cpu_get_threads
    fi
}

cpu_get_frequency_mhz() {
    local frequency=""

    if command -v lscpu >/dev/null 2>&1; then
        frequency="$(
            LC_ALL=C lscpu 2>/dev/null |
            awk -F: '
                $1 ~ /^CPU MHz/ {
                    gsub(/^[[:space:]]+/, "", $2)
                    printf "%.0f\n", $2
                    exit
                }
            '
        )"
    fi

    if [[ -z "$frequency" && -r /proc/cpuinfo ]]; then
        frequency="$(
            awk -F: '
                /^cpu MHz/ {
                    total += $2
                    count++
                }

                END {
                    if (count > 0) {
                        printf "%.0f\n", total / count
                    }
                }
            ' /proc/cpuinfo
        )"
    fi

    printf '%s\n' "${frequency:-0}"
}

cpu_collect_hardware() {
    local model
    local vendor
    local architecture
    local physical_cores
    local threads
    local sockets
    local frequency

    model="$(cpu_get_model)"
    vendor="$(cpu_get_vendor)"
    architecture="$(cpu_get_architecture)"
    physical_cores="$(cpu_get_physical_cores)"
    threads="$(cpu_get_threads)"
    sockets="$(cpu_get_sockets)"
    frequency="$(cpu_get_frequency_mhz)"

    collector_metric_set \
        "cpu" \
        "hardware" \
        "model" \
        "Modelo da CPU" \
        "$model" \
        "$model" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Modelo informado pelo processador." \
        "lscpu ou /proc/cpuinfo"

    collector_metric_set \
        "cpu" \
        "hardware" \
        "vendor" \
        "Fabricante" \
        "$vendor" \
        "$vendor" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Identificador do fabricante da CPU." \
        "/proc/cpuinfo"

    collector_metric_set \
        "cpu" \
        "hardware" \
        "architecture" \
        "Arquitetura" \
        "$architecture" \
        "$architecture" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Arquitetura do processador." \
        "uname -m"

    collector_metric_set \
        "cpu" \
        "hardware" \
        "physical_cores" \
        "Núcleos físicos" \
        "$physical_cores" \
        "$physical_cores" \
        "integer" \
        "cores" \
        "${HC_STATUS_OK:-OK}" \
        "Quantidade estimada de núcleos físicos." \
        "lscpu ou /proc/cpuinfo"

    collector_metric_set \
        "cpu" \
        "hardware" \
        "logical_threads" \
        "Threads lógicas" \
        "$threads" \
        "$threads" \
        "integer" \
        "threads" \
        "${HC_STATUS_OK:-OK}" \
        "Quantidade de processadores lógicos disponíveis." \
        "nproc"

    collector_metric_set \
        "cpu" \
        "hardware" \
        "sockets" \
        "Soquetes" \
        "$sockets" \
        "$sockets" \
        "integer" \
        "sockets" \
        "${HC_STATUS_OK:-OK}" \
        "Quantidade de soquetes de CPU detectados." \
        "lscpu"

    collector_metric_set \
        "cpu" \
        "hardware" \
        "frequency_mhz" \
        "Frequência média" \
        "${frequency} MHz" \
        "$frequency" \
        "decimal" \
        "MHz" \
        "${HC_STATUS_OK:-OK}" \
        "Frequência média informada no momento da coleta." \
        "lscpu ou /proc/cpuinfo"
}

# ---------------------------------------------------------------------------
# Carga
# ---------------------------------------------------------------------------

cpu_collect_load_average() {
    local load_1m="0"
    local load_5m="0"
    local load_15m="0"
    local threads
    local warning_factor
    local critical_factor
    local warning_threshold
    local critical_threshold
    local status_1m
    local status_5m
    local status_15m

    if [[ -r /proc/loadavg ]]; then
        read -r load_1m load_5m load_15m _ </proc/loadavg
    fi

    threads="$(cpu_get_threads)"
    warning_factor="$(cpu_config_get "HC_CPU_LOAD_WARNING_FACTOR" "1.00")"
    critical_factor="$(cpu_config_get "HC_CPU_LOAD_CRITICAL_FACTOR" "1.50")"

    warning_threshold="$(
        awk \
            -v threads="$threads" \
            -v factor="$warning_factor" \
            'BEGIN { printf "%.2f\n", threads * factor }'
    )"

    critical_threshold="$(
        awk \
            -v threads="$threads" \
            -v factor="$critical_factor" \
            'BEGIN { printf "%.2f\n", threads * factor }'
    )"

    status_1m="$(
        utils_status_from_high_usage \
            "$load_1m" \
            "$warning_threshold" \
            "$critical_threshold"
    )"

    status_5m="$(
        utils_status_from_high_usage \
            "$load_5m" \
            "$warning_threshold" \
            "$critical_threshold"
    )"

    status_15m="$(
        utils_status_from_high_usage \
            "$load_15m" \
            "$warning_threshold" \
            "$critical_threshold"
    )"

    collector_metric_set \
        "cpu" \
        "load" \
        "load_1m" \
        "Carga em 1 minuto" \
        "$load_1m" \
        "$load_1m" \
        "decimal" \
        "" \
        "$status_1m" \
        "Carga média do sistema no último minuto." \
        "/proc/loadavg"

    collector_metric_set \
        "cpu" \
        "load" \
        "load_5m" \
        "Carga em 5 minutos" \
        "$load_5m" \
        "$load_5m" \
        "decimal" \
        "" \
        "$status_5m" \
        "Carga média do sistema nos últimos cinco minutos." \
        "/proc/loadavg"

    collector_metric_set \
        "cpu" \
        "load" \
        "load_15m" \
        "Carga em 15 minutos" \
        "$load_15m" \
        "$load_15m" \
        "decimal" \
        "" \
        "$status_15m" \
        "Carga média do sistema nos últimos quinze minutos." \
        "/proc/loadavg"

    if [[ "$status_1m" == "${HC_STATUS_CRITICAL:-CRITICAL}" ]]; then
        collector_alert_add \
            "cpu" \
            "$status_1m" \
            "Carga de CPU crítica" \
            "A carga média de 1 minuto está em ${load_1m}, acima do limite ${critical_threshold}." \
            "Identifique processos com alto consumo e verifique contenção de CPU."
    elif [[ "$status_1m" == "${HC_STATUS_WARNING:-WARNING}" ]]; then
        collector_alert_add \
            "cpu" \
            "$status_1m" \
            "Carga de CPU elevada" \
            "A carga média de 1 minuto está em ${load_1m}, acima do limite ${warning_threshold}." \
            "Acompanhe os processos com maior uso de CPU."
    fi
}

# ---------------------------------------------------------------------------
# Uso da CPU
# ---------------------------------------------------------------------------

cpu_read_stat_snapshot() {
    local destination_name="${1:-}"

    local cpu_label=""
    local user="0"
    local nice="0"
    local system="0"
    local idle="0"
    local iowait="0"
    local irq="0"
    local softirq="0"
    local steal="0"
    local guest="0"
    local guest_nice="0"

    if [[ -z "$destination_name" || ! -r /proc/stat ]]; then
        return 1
    fi

    local -n destination_ref="$destination_name"

    IFS=' ' read -r \
        cpu_label \
        user \
        nice \
        system \
        idle \
        iowait \
        irq \
        softirq \
        steal \
        guest \
        guest_nice < /proc/stat

    if [[ "$cpu_label" != "cpu" ]]; then
        return 2
    fi

    destination_ref=(
        "${user:-0}"
        "${nice:-0}"
        "${system:-0}"
        "${idle:-0}"
        "${iowait:-0}"
        "${irq:-0}"
        "${softirq:-0}"
        "${steal:-0}"
        "${guest:-0}"
        "${guest_nice:-0}"
    )

    return 0
}

cpu_calculate_usage() {
    local first_name="${1:-}"
    local second_name="${2:-}"
    local result_name="${3:-}"

    if [[ -z "$first_name" || -z "$second_name" || -z "$result_name" ]]; then
        return 1
    fi

    local -n first_ref="$first_name"
    local -n second_ref="$second_name"
    local -n result_ref="$result_name"

    local first_idle=0
    local second_idle=0
    local first_non_idle=0
    local second_non_idle=0
    local first_total=0
    local second_total=0
    local total_delta=0
    local idle_delta=0
    local user_delta=0
    local system_delta=0
    local iowait_delta=0
    local steal_delta=0

    if ((${#first_ref[@]} < 8 || ${#second_ref[@]} < 8)); then
        return 2
    fi

    first_idle=$((first_ref[3] + first_ref[4]))
    second_idle=$((second_ref[3] + second_ref[4]))

    first_non_idle=$((
        first_ref[0] +
        first_ref[1] +
        first_ref[2] +
        first_ref[5] +
        first_ref[6] +
        first_ref[7]
    ))

    second_non_idle=$((
        second_ref[0] +
        second_ref[1] +
        second_ref[2] +
        second_ref[5] +
        second_ref[6] +
        second_ref[7]
    ))

    first_total=$((first_idle + first_non_idle))
    second_total=$((second_idle + second_non_idle))

    total_delta=$((second_total - first_total))
    idle_delta=$((second_idle - first_idle))

    if ((total_delta <= 0)); then
        return 3
    fi

    user_delta=$((second_ref[0] - first_ref[0]))
    system_delta=$((second_ref[2] - first_ref[2]))
    iowait_delta=$((second_ref[4] - first_ref[4]))
    steal_delta=$((second_ref[7] - first_ref[7]))

    result_ref["usage"]="$(
        awk \
            -v total="$total_delta" \
            -v idle="$idle_delta" \
            'BEGIN {
                printf "%.2f\n", ((total - idle) / total) * 100
            }'
    )"

    result_ref["user"]="$(
        awk \
            -v delta="$user_delta" \
            -v total="$total_delta" \
            'BEGIN {
                printf "%.2f\n", (delta / total) * 100
            }'
    )"

    result_ref["system"]="$(
        awk \
            -v delta="$system_delta" \
            -v total="$total_delta" \
            'BEGIN {
                printf "%.2f\n", (delta / total) * 100
            }'
    )"

    result_ref["iowait"]="$(
        awk \
            -v delta="$iowait_delta" \
            -v total="$total_delta" \
            'BEGIN {
                printf "%.2f\n", (delta / total) * 100
            }'
    )"

    result_ref["steal"]="$(
        awk \
            -v delta="$steal_delta" \
            -v total="$total_delta" \
            'BEGIN {
                printf "%.2f\n", (delta / total) * 100
            }'
    )"

    result_ref["idle"]="$(
        awk \
            -v idle="$idle_delta" \
            -v total="$total_delta" \
            'BEGIN {
                printf "%.2f\n", (idle / total) * 100
            }'
    )"

    return 0
}

cpu_collect_usage() {
    local sample_seconds
    local usage_warning
    local usage_critical
    local iowait_warning
    local iowait_critical
    local steal_warning
    local steal_critical

    local -a first_snapshot=()
    local -a second_snapshot=()
    local -A usage_result=()

    local usage_status="${HC_STATUS_UNKNOWN:-UNKNOWN}"
    local iowait_status="${HC_STATUS_UNKNOWN:-UNKNOWN}"
    local steal_status="${HC_STATUS_UNKNOWN:-UNKNOWN}"

    sample_seconds="$(cpu_config_get "HC_CPU_SAMPLE_SECONDS" "1")"
    usage_warning="$(cpu_config_get "HC_CPU_USAGE_WARNING_PERCENT" "75")"
    usage_critical="$(cpu_config_get "HC_CPU_USAGE_CRITICAL_PERCENT" "90")"
    iowait_warning="$(cpu_config_get "HC_CPU_IOWAIT_WARNING_PERCENT" "10")"
    iowait_critical="$(cpu_config_get "HC_CPU_IOWAIT_CRITICAL_PERCENT" "25")"
    steal_warning="$(cpu_config_get "HC_CPU_STEAL_WARNING_PERCENT" "5")"
    steal_critical="$(cpu_config_get "HC_CPU_STEAL_CRITICAL_PERCENT" "15")"

    if ! cpu_read_stat_snapshot first_snapshot; then
        collector_metric_set \
            "cpu" \
            "usage" \
            "total_percent" \
            "Uso total da CPU" \
            "Não disponível" \
            "" \
            "percentage" \
            "%" \
            "${HC_STATUS_UNKNOWN:-UNKNOWN}" \
            "Não foi possível ler o primeiro snapshot de CPU." \
            "/proc/stat"

        return 0
    fi

    sleep "$sample_seconds"

    if ! cpu_read_stat_snapshot second_snapshot; then
        collector_metric_set \
            "cpu" \
            "usage" \
            "total_percent" \
            "Uso total da CPU" \
            "Não disponível" \
            "" \
            "percentage" \
            "%" \
            "${HC_STATUS_UNKNOWN:-UNKNOWN}" \
            "Não foi possível ler o segundo snapshot de CPU." \
            "/proc/stat"

        return 0
    fi

    if ! cpu_calculate_usage \
        first_snapshot \
        second_snapshot \
        usage_result; then

        collector_metric_set \
            "cpu" \
            "usage" \
            "total_percent" \
            "Uso total da CPU" \
            "Não disponível" \
            "" \
            "percentage" \
            "%" \
            "${HC_STATUS_UNKNOWN:-UNKNOWN}" \
            "Não foi possível calcular o uso da CPU." \
            "/proc/stat"

        return 0
    fi

    if [[ -z "${usage_result[usage]+x}" ||
        -z "${usage_result[user]+x}" ||
        -z "${usage_result[system]+x}" ||
        -z "${usage_result[iowait]+x}" ||
        -z "${usage_result[steal]+x}" ||
        -z "${usage_result[idle]+x}" ]]; then

        collector_metric_set \
            "cpu" \
            "usage" \
            "total_percent" \
            "Uso total da CPU" \
            "Não disponível" \
            "" \
            "percentage" \
            "%" \
            "${HC_STATUS_UNKNOWN:-UNKNOWN}" \
            "O cálculo de CPU não retornou todos os campos esperados." \
            "/proc/stat"

        return 0
    fi

    usage_status="$(
        utils_status_from_high_usage \
            "${usage_result[usage]}" \
            "$usage_warning" \
            "$usage_critical"
    )"

    iowait_status="$(
        utils_status_from_high_usage \
            "${usage_result[iowait]}" \
            "$iowait_warning" \
            "$iowait_critical"
    )"

    steal_status="$(
        utils_status_from_high_usage \
            "${usage_result[steal]}" \
            "$steal_warning" \
            "$steal_critical"
    )"

    collector_metric_set \
        "cpu" \
        "usage" \
        "total_percent" \
        "Uso total da CPU" \
        "${usage_result[usage]}%" \
        "${usage_result[usage]}" \
        "percentage" \
        "%" \
        "$usage_status" \
        "Uso total da CPU durante o intervalo de amostragem." \
        "/proc/stat"

    collector_metric_set \
        "cpu" \
        "usage" \
        "user_percent" \
        "Uso por processos de usuário" \
        "${usage_result[user]}%" \
        "${usage_result[user]}" \
        "percentage" \
        "%" \
        "${HC_STATUS_OK:-OK}" \
        "Tempo de CPU consumido por processos de usuário." \
        "/proc/stat"

    collector_metric_set \
        "cpu" \
        "usage" \
        "system_percent" \
        "Uso pelo kernel" \
        "${usage_result[system]}%" \
        "${usage_result[system]}" \
        "percentage" \
        "%" \
        "${HC_STATUS_OK:-OK}" \
        "Tempo de CPU consumido pelo kernel." \
        "/proc/stat"

    collector_metric_set \
        "cpu" \
        "usage" \
        "iowait_percent" \
        "Espera por I/O" \
        "${usage_result[iowait]}%" \
        "${usage_result[iowait]}" \
        "percentage" \
        "%" \
        "$iowait_status" \
        "Tempo em que a CPU aguardou operações de entrada e saída." \
        "/proc/stat"

    collector_metric_set \
        "cpu" \
        "usage" \
        "steal_percent" \
        "CPU roubada pelo hipervisor" \
        "${usage_result[steal]}%" \
        "${usage_result[steal]}" \
        "percentage" \
        "%" \
        "$steal_status" \
        "Tempo de CPU retirado da máquina virtual pelo hipervisor." \
        "/proc/stat"

    collector_metric_set \
        "cpu" \
        "usage" \
        "idle_percent" \
        "CPU ociosa" \
        "${usage_result[idle]}%" \
        "${usage_result[idle]}" \
        "percentage" \
        "%" \
        "${HC_STATUS_OK:-OK}" \
        "Percentual de tempo ocioso da CPU." \
        "/proc/stat"

    if [[ "$usage_status" == "${HC_STATUS_CRITICAL:-CRITICAL}" ]]; then
        collector_alert_add \
            "cpu" \
            "$usage_status" \
            "Uso crítico de CPU" \
            "O uso total da CPU atingiu ${usage_result[usage]}%." \
            "Revise os processos com maior consumo de CPU."
    elif [[ "$usage_status" == "${HC_STATUS_WARNING:-WARNING}" ]]; then
        collector_alert_add \
            "cpu" \
            "$usage_status" \
            "Uso elevado de CPU" \
            "O uso total da CPU atingiu ${usage_result[usage]}%." \
            "Acompanhe a utilização e identifique processos pesados."
    fi

    if [[ "$iowait_status" != "${HC_STATUS_OK:-OK}" ]]; then
        collector_alert_add \
            "cpu" \
            "$iowait_status" \
            "Espera elevada por I/O" \
            "O iowait da CPU está em ${usage_result[iowait]}%." \
            "Verifique latência, carga e saturação dos discos."
    fi

    if [[ "$steal_status" != "${HC_STATUS_OK:-OK}" ]]; then
        collector_alert_add \
            "cpu" \
            "$steal_status" \
            "Steal time elevado" \
            "O steal time está em ${usage_result[steal]}%." \
            "Verifique contenção de CPU no provedor da VPS."
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Temperatura
# ---------------------------------------------------------------------------

cpu_temperature_status() {
    local temperature="${1:-0}"
    local warning
    local critical

    warning="$(cpu_config_get "HC_CPU_TEMPERATURE_WARNING_CELSIUS" "75")"
    critical="$(cpu_config_get "HC_CPU_TEMPERATURE_CRITICAL_CELSIUS" "90")"

    utils_status_from_high_usage \
        "$temperature" \
        "$warning" \
        "$critical"
}

cpu_collect_temperature() {
    local thermal_file
    local raw_temperature
    local temperature
    local highest_temperature=""
    local status="${HC_STATUS_UNKNOWN:-UNKNOWN}"

    for thermal_file in /sys/class/thermal/thermal_zone*/temp; do
        [[ -r "$thermal_file" ]] || continue

        raw_temperature="$(cat "$thermal_file" 2>/dev/null || true)"

        if [[ ! "$raw_temperature" =~ ^[0-9]+$ ]]; then
            continue
        fi

        temperature="$(
            awk \
                -v value="$raw_temperature" \
                'BEGIN {
                    if (value > 1000) {
                        value = value / 1000
                    }

                    printf "%.1f\n", value
                }'
        )"

        if [[ -z "$highest_temperature" ]] ||
            awk \
                -v current="$temperature" \
                -v highest="$highest_temperature" \
                'BEGIN { exit !(current > highest) }'; then

            highest_temperature="$temperature"
        fi
    done

    if [[ -z "$highest_temperature" ]] &&
        command -v sensors >/dev/null 2>&1; then

        highest_temperature="$(
            sensors 2>/dev/null |
            awk '
                match($0, /[+][0-9]+([.][0-9]+)?°C/) {
                    value = substr($0, RSTART + 1, RLENGTH - 3)

                    if (value > highest) {
                        highest = value
                    }
                }

                END {
                    if (highest > 0) {
                        printf "%.1f\n", highest
                    }
                }
            '
        )"
    fi

    if [[ -z "$highest_temperature" ]]; then
        collector_metric_set \
            "cpu" \
            "temperature" \
            "maximum_celsius" \
            "Temperatura máxima" \
            "Não disponível" \
            "" \
            "decimal" \
            "°C" \
            "${HC_STATUS_UNKNOWN:-UNKNOWN}" \
            "Temperatura máxima não disponibilizada pelo ambiente." \
            "/sys/class/thermal ou sensors"

        return 0
    fi

    status="$(cpu_temperature_status "$highest_temperature")"

    collector_metric_set \
        "cpu" \
        "temperature" \
        "maximum_celsius" \
        "Temperatura máxima" \
        "${highest_temperature} °C" \
        "$highest_temperature" \
        "decimal" \
        "°C" \
        "$status" \
        "Maior temperatura detectada entre as zonas térmicas." \
        "/sys/class/thermal ou sensors"

    if [[ "$status" == "${HC_STATUS_CRITICAL:-CRITICAL}" ]]; then
        collector_alert_add \
            "cpu" \
            "$status" \
            "Temperatura crítica da CPU" \
            "A temperatura máxima detectada foi ${highest_temperature} °C." \
            "Verifique ventilação, refrigeração e carga do servidor."
    elif [[ "$status" == "${HC_STATUS_WARNING:-WARNING}" ]]; then
        collector_alert_add \
            "cpu" \
            "$status" \
            "Temperatura elevada da CPU" \
            "A temperatura máxima detectada foi ${highest_temperature} °C." \
            "Acompanhe a temperatura e a carga do servidor."
    fi
}

# ---------------------------------------------------------------------------
# Processos
# ---------------------------------------------------------------------------

cpu_collect_top_processes() {
    local limit
    local pid
    local user
    local cpu
    local memory
    local elapsed
    local command_name
    local command_line

    limit="$(cpu_config_get "HC_CPU_TOP_PROCESSES_LIMIT" "20")"

    collector_table_create \
        "cpu" \
        "processes" \
        "top_cpu" \
        "Processos com maior uso de CPU" \
        $'PID\tUsuário\tCPU %\tMemória %\tTempo\tProcesso\tComando' \
        "Processos ordenados por consumo atual de CPU." \
        "${HC_STATUS_OK:-OK}"

    while IFS=$'\t' read -r \
        pid \
        user \
        cpu \
        memory \
        elapsed \
        command_name \
        command_line; do

        [[ -n "$pid" ]] || continue

        collector_table_add_row \
            "cpu" \
            "processes" \
            "top_cpu" \
            "$pid" \
            "$user" \
            "$cpu" \
            "$memory" \
            "$elapsed" \
            "$command_name" \
            "$command_line"
    done < <(
        ps \
            -eo pid=,user=,%cpu=,%mem=,etime=,comm=,args= \
            --sort=-%cpu 2>/dev/null |
        awk \
            -v limit="$limit" '
            NR <= limit {
                pid = $1
                user = $2
                cpu = $3
                memory = $4
                elapsed = $5
                command_name = $6

                $1 = ""
                $2 = ""
                $3 = ""
                $4 = ""
                $5 = ""
                $6 = ""

                sub(/^[[:space:]]+/, "", $0)

                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
                    pid,
                    user,
                    cpu,
                    memory,
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

cpu_run() {
    if cpu_config_enabled "HC_CPU_INCLUDE_MODEL" "1" ||
        cpu_config_enabled "HC_CPU_INCLUDE_ARCHITECTURE" "1" ||
        cpu_config_enabled "HC_CPU_INCLUDE_CORES" "1" ||
        cpu_config_enabled "HC_CPU_INCLUDE_THREADS" "1" ||
        cpu_config_enabled "HC_CPU_INCLUDE_FREQUENCY" "1"; then

        cpu_collect_hardware
    fi

    if cpu_config_enabled "HC_CPU_INCLUDE_LOAD_AVERAGE" "1"; then
        cpu_collect_load_average
    fi

    if cpu_config_enabled "HC_CPU_INCLUDE_USAGE" "1"; then
        cpu_collect_usage
    fi

    if cpu_config_enabled "HC_CPU_INCLUDE_TEMPERATURE" "1"; then
        cpu_collect_temperature
    fi

    if cpu_config_enabled "HC_CPU_INCLUDE_TOP_PROCESSES" "1"; then
        cpu_collect_top_processes
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Validação interna
# ---------------------------------------------------------------------------

cpu_validate() {
    local failure=0
    local model=""
    local threads=""
    local metric_count=0
    local table_count=0

    if ! declare -F collector_initialize >/dev/null 2>&1; then
        printf 'collector_initialize não está disponível.\n' >&2
        return 1
    fi

    collector_initialize
    collector_module_start "cpu" "CPU"

    if ! cpu_run; then
        printf 'cpu_run retornou falha.\n' >&2
        failure=1
    fi

    model="$(
        collector_metric_get \
            "cpu" \
            "hardware" \
            "model" \
            "value" 2>/dev/null ||
        true
    )"

    threads="$(
        collector_metric_get \
            "cpu" \
            "hardware" \
            "logical_threads" \
            "raw_value" 2>/dev/null ||
        true
    )"

    metric_count="$(collector_metric_count "cpu")"
    table_count="$(collector_table_count "cpu")"

    if [[ -z "$model" ]]; then
        printf 'Modelo da CPU não coletado.\n' >&2
        failure=1
    fi

    if [[ ! "$threads" =~ ^[0-9]+$ ]] || ((threads < 1)); then
        printf 'Quantidade inválida de threads: %s\n' "$threads" >&2
        failure=1
    fi

    if [[ ! "$metric_count" =~ ^[0-9]+$ ]] ||
        ((metric_count < 10)); then

        printf \
            'Quantidade insuficiente de métricas de CPU: %s\n' \
            "$metric_count" >&2

        failure=1
    fi

    if [[ ! "$table_count" =~ ^[0-9]+$ ]] ||
        ((table_count < 1)); then

        printf 'Tabela de processos não foi criada.\n' >&2
        failure=1
    fi

    collector_module_finish \
        "cpu" \
        "$(collector_module_get_status "cpu")" \
        "Validação concluída."

    collector_finalize

    return "$failure"
}
