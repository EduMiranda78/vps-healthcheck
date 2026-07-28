#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_DISK_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_DISK_LOADED=1

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------

disk_config_enabled() {
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

disk_config_get() {
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
# Limites por ponto de montagem
# ---------------------------------------------------------------------------

disk_usage_thresholds() {
    local mount_point="${1:-/}"
    local warning_variable_name="${2:-}"
    local critical_variable_name="${3:-}"

    local calculated_warning=""
    local calculated_critical=""

    if [[ -z "$warning_variable_name" ||
        -z "$critical_variable_name" ]]; then

        return 1
    fi

    if [[ ! "$warning_variable_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
        [[ ! "$critical_variable_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then

        return 2
    fi

    local -n warning_ref="$warning_variable_name"
    local -n critical_ref="$critical_variable_name"

    case "$mount_point" in
        /)
            calculated_warning="$(
                disk_config_get \
                    "HC_DISK_ROOT_WARNING_PERCENT" \
                    "$(disk_config_get HC_DISK_USAGE_WARNING_PERCENT 75)"
            )"

            calculated_critical="$(
                disk_config_get \
                    "HC_DISK_ROOT_CRITICAL_PERCENT" \
                    "$(disk_config_get HC_DISK_USAGE_CRITICAL_PERCENT 90)"
            )"
            ;;
        /boot | /boot/*)
            calculated_warning="$(
                disk_config_get \
                    "HC_DISK_BOOT_WARNING_PERCENT" \
                    "$(disk_config_get HC_DISK_USAGE_WARNING_PERCENT 75)"
            )"

            calculated_critical="$(
                disk_config_get \
                    "HC_DISK_BOOT_CRITICAL_PERCENT" \
                    "$(disk_config_get HC_DISK_USAGE_CRITICAL_PERCENT 90)"
            )"
            ;;
        /var | /var/*)
            calculated_warning="$(
                disk_config_get \
                    "HC_DISK_VAR_WARNING_PERCENT" \
                    "$(disk_config_get HC_DISK_USAGE_WARNING_PERCENT 75)"
            )"

            calculated_critical="$(
                disk_config_get \
                    "HC_DISK_VAR_CRITICAL_PERCENT" \
                    "$(disk_config_get HC_DISK_USAGE_CRITICAL_PERCENT 90)"
            )"
            ;;
        /home | /home/*)
            calculated_warning="$(
                disk_config_get \
                    "HC_DISK_HOME_WARNING_PERCENT" \
                    "$(disk_config_get HC_DISK_USAGE_WARNING_PERCENT 75)"
            )"

            calculated_critical="$(
                disk_config_get \
                    "HC_DISK_HOME_CRITICAL_PERCENT" \
                    "$(disk_config_get HC_DISK_USAGE_CRITICAL_PERCENT 90)"
            )"
            ;;
        *)
            calculated_warning="$(
                disk_config_get \
                    "HC_DISK_USAGE_WARNING_PERCENT" \
                    "75"
            )"

            calculated_critical="$(
                disk_config_get \
                    "HC_DISK_USAGE_CRITICAL_PERCENT" \
                    "90"
            )"
            ;;
    esac

    warning_ref="$calculated_warning"
    critical_ref="$calculated_critical"

    return 0
}

disk_usage_status() {
    local mount_point="${1:-/}"
    local usage_percent="${2:-0}"
    local warning
    local critical

    disk_usage_thresholds \
        "$mount_point" \
        warning \
        critical

    utils_status_from_high_usage \
        "$usage_percent" \
        "$warning" \
        "$critical"
}

disk_inode_status() {
    local usage_percent="${1:-0}"
    local warning
    local critical

    warning="$(disk_config_get HC_DISK_INODE_WARNING_PERCENT 75)"
    critical="$(disk_config_get HC_DISK_INODE_CRITICAL_PERCENT 90)"

    utils_status_from_high_usage \
        "$usage_percent" \
        "$warning" \
        "$critical"
}

# ---------------------------------------------------------------------------
# Filesystems
# ---------------------------------------------------------------------------

disk_collect_filesystems() {
    local filesystem
    local filesystem_type
    local total_blocks
    local used_blocks
    local available_blocks
    local usage
    local mount_point

    local total_bytes
    local used_bytes
    local available_bytes
    local usage_percent
    local status
    local warning
    local critical

    collector_table_create \
        "disk" \
        "filesystems" \
        "usage" \
        "Uso dos sistemas de arquivos" \
        $'Dispositivo\tTipo\tMontagem\tTotal\tUsado\tDisponível\tUso %\tStatus' \
        "Sistemas de arquivos montados e seu espaço utilizado." \
        "${HC_STATUS_OK:-OK}"

    while IFS=$'\t' read -r \
        filesystem \
        filesystem_type \
        total_blocks \
        used_blocks \
        available_blocks \
        usage \
        mount_point; do

        [[ -n "$filesystem" ]] || continue
        [[ "$total_blocks" =~ ^[0-9]+$ ]] || continue

        total_bytes=$((total_blocks * 1024))
        used_bytes=$((used_blocks * 1024))
        available_bytes=$((available_blocks * 1024))
        usage_percent="${usage%\%}"

        if [[ ! "$usage_percent" =~ ^[0-9]+$ ]]; then
            usage_percent=0
        fi

        status="$(disk_usage_status "$mount_point" "$usage_percent")"

        collector_table_add_row \
            "disk" \
            "filesystems" \
            "usage" \
            "$filesystem" \
            "$filesystem_type" \
            "$mount_point" \
            "$(utils_bytes_to_human "$total_bytes" 2)" \
            "$(utils_bytes_to_human "$used_bytes" 2)" \
            "$(utils_bytes_to_human "$available_bytes" 2)" \
            "${usage_percent}%" \
            "$status"

        if [[ "$mount_point" == "/" ]]; then
            collector_metric_set \
                "disk" \
                "root" \
                "total_bytes" \
                "Espaço total da raiz" \
                "$(utils_bytes_to_human "$total_bytes" 2)" \
                "$total_bytes" \
                "bytes" \
                "bytes" \
                "${HC_STATUS_OK:-OK}" \
                "Espaço total da partição raiz." \
                "df"

            collector_metric_set \
                "disk" \
                "root" \
                "used_bytes" \
                "Espaço usado na raiz" \
                "$(utils_bytes_to_human "$used_bytes" 2)" \
                "$used_bytes" \
                "bytes" \
                "bytes" \
                "$status" \
                "Espaço utilizado na partição raiz." \
                "df"

            collector_metric_set \
                "disk" \
                "root" \
                "available_bytes" \
                "Espaço disponível na raiz" \
                "$(utils_bytes_to_human "$available_bytes" 2)" \
                "$available_bytes" \
                "bytes" \
                "bytes" \
                "$status" \
                "Espaço disponível na partição raiz." \
                "df"

            collector_metric_set \
                "disk" \
                "root" \
                "usage_percent" \
                "Uso da partição raiz" \
                "${usage_percent}%" \
                "$usage_percent" \
                "percentage" \
                "%" \
                "$status" \
                "Percentual de uso da partição raiz." \
                "df"
        fi

        if [[ "$status" != "${HC_STATUS_OK:-OK}" ]]; then
            disk_usage_thresholds \
                "$mount_point" \
                warning \
                critical

            collector_alert_add \
                "disk" \
                "$status" \
                "Uso elevado de disco" \
                "O filesystem ${filesystem}, montado em ${mount_point}, está com ${usage_percent}% de uso." \
                "Revise arquivos grandes, logs, caches e dados antigos. Limites: aviso ${warning}%, crítico ${critical}%."
        fi
    done < <(
        LC_ALL=C df \
            -PT \
            -x tmpfs \
            -x devtmpfs \
            -x squashfs \
            -x overlay 2>/dev/null |
        awk '
            NR > 1 {
                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
                    $1,
                    $2,
                    $3,
                    $4,
                    $5,
                    $6,
                    $7
            }
        '
    )

    collector_table_set_status \
        "disk" \
        "filesystems" \
        "usage" \
        "$(collector_module_get_status disk)"
}

# ---------------------------------------------------------------------------
# Inodes
# ---------------------------------------------------------------------------

disk_collect_inodes() {
    local filesystem
    local inode_total
    local inode_used
    local inode_free
    local usage
    local mount_point
    local usage_percent
    local status

    collector_table_create \
        "disk" \
        "inodes" \
        "usage" \
        "Uso de inodes" \
        $'Dispositivo\tMontagem\tTotal\tUsados\tLivres\tUso %\tStatus' \
        "Uso de inodes dos sistemas de arquivos montados." \
        "${HC_STATUS_OK:-OK}"

    while IFS=$'\t' read -r \
        filesystem \
        inode_total \
        inode_used \
        inode_free \
        usage \
        mount_point; do

        [[ -n "$filesystem" ]] || continue
        [[ "$inode_total" =~ ^[0-9]+$ ]] || continue

        usage_percent="${usage%\%}"

        if [[ ! "$usage_percent" =~ ^[0-9]+$ ]]; then
            usage_percent=0
        fi

        status="$(disk_inode_status "$usage_percent")"

        collector_table_add_row \
            "disk" \
            "inodes" \
            "usage" \
            "$filesystem" \
            "$mount_point" \
            "$inode_total" \
            "$inode_used" \
            "$inode_free" \
            "${usage_percent}%" \
            "$status"

        if [[ "$mount_point" == "/" ]]; then
            collector_metric_set \
                "disk" \
                "root" \
                "inode_usage_percent" \
                "Uso de inodes na raiz" \
                "${usage_percent}%" \
                "$usage_percent" \
                "percentage" \
                "%" \
                "$status" \
                "Percentual de inodes utilizados na partição raiz." \
                "df -i"
        fi

        if [[ "$status" != "${HC_STATUS_OK:-OK}" ]]; then
            collector_alert_add \
                "disk" \
                "$status" \
                "Uso elevado de inodes" \
                "O filesystem ${filesystem}, montado em ${mount_point}, está com ${usage_percent}% dos inodes utilizados." \
                "Procure diretórios com grande quantidade de arquivos pequenos."
        fi
    done < <(
        LC_ALL=C df \
            -Pi \
            -x tmpfs \
            -x devtmpfs \
            -x squashfs \
            -x overlay 2>/dev/null |
        awk '
            NR > 1 {
                printf "%s\t%s\t%s\t%s\t%s\t%s\n",
                    $1,
                    $2,
                    $3,
                    $4,
                    $5,
                    $6
            }
        '
    )
}

# ---------------------------------------------------------------------------
# Dispositivos de bloco
# ---------------------------------------------------------------------------

disk_collect_block_devices() {
    local name
    local device_type
    local size
    local filesystem_type
    local mount_point
    local model
    local rotational
    local transport
    local readonly

    collector_table_create \
        "disk" \
        "devices" \
        "block_devices" \
        "Dispositivos de bloco" \
        $'Dispositivo\tTipo\tTamanho\tFilesystem\tMontagem\tModelo\tRotacional\tTransporte\tSomente leitura' \
        "Discos, partições e dispositivos de bloco detectados." \
        "${HC_STATUS_OK:-OK}"

    if ! command -v lsblk >/dev/null 2>&1; then
        collector_table_set_status \
            "disk" \
            "devices" \
            "block_devices" \
            "${HC_STATUS_UNKNOWN:-UNKNOWN}"

        return 0
    fi

    while IFS=$'\t' read -r \
        name \
        device_type \
        size \
        filesystem_type \
        mount_point \
        model \
        rotational \
        transport \
        readonly; do

        [[ -n "$name" ]] || continue

        collector_table_add_row \
            "disk" \
            "devices" \
            "block_devices" \
            "$name" \
            "$device_type" \
            "$size" \
            "${filesystem_type:-}" \
            "${mount_point:-}" \
            "${model:-}" \
            "${rotational:-}" \
            "${transport:-}" \
            "${readonly:-}"
    done < <(
        lsblk \
            -P \
            -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT,MODEL,ROTA,TRAN,RO 2>/dev/null |
        awk '
            {
                delete values

                while (match($0, /[A-Z]+="([^"\\]|\\.)*"/)) {
                    field = substr($0, RSTART, RLENGTH)
                    split(field, parts, "=")

                    key = parts[1]
                    value = substr(field, length(key) + 3, length(field) - length(key) - 3)

                    gsub(/\\"/, "\"", value)
                    values[key] = value

                    $0 = substr($0, RSTART + RLENGTH)
                }

                printf "/dev/%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
                    values["NAME"],
                    values["TYPE"],
                    values["SIZE"],
                    values["FSTYPE"],
                    values["MOUNTPOINT"],
                    values["MODEL"],
                    values["ROTA"],
                    values["TRAN"],
                    values["RO"]
            }
        '
    )
}

# ---------------------------------------------------------------------------
# Mounts
# ---------------------------------------------------------------------------

disk_collect_mounts() {
    local source
    local target
    local filesystem_type
    local options

    collector_table_create \
        "disk" \
        "mounts" \
        "mounted_filesystems" \
        "Pontos de montagem" \
        $'Origem\tDestino\tTipo\tOpções' \
        "Pontos de montagem ativos no sistema." \
        "${HC_STATUS_OK:-OK}"

    if command -v findmnt >/dev/null 2>&1; then
        while IFS=$'\t' read -r \
            source \
            target \
            filesystem_type \
            options; do

            [[ -n "$target" ]] || continue

            collector_table_add_row \
                "disk" \
                "mounts" \
                "mounted_filesystems" \
                "$source" \
                "$target" \
                "$filesystem_type" \
                "$options"
        done < <(
            findmnt \
                --raw \
                --noheadings \
                --output SOURCE,TARGET,FSTYPE,OPTIONS 2>/dev/null |
            awk '
                {
                    source = $1
                    target = $2
                    filesystem = $3

                    $1 = ""
                    $2 = ""
                    $3 = ""

                    sub(/^[[:space:]]+/, "", $0)

                    printf "%s\t%s\t%s\t%s\n",
                        source,
                        target,
                        filesystem,
                        $0
                }
            '
        )

        return 0
    fi

    while IFS=' ' read -r source target filesystem_type options _; do
        collector_table_add_row \
            "disk" \
            "mounts" \
            "mounted_filesystems" \
            "$source" \
            "$target" \
            "$filesystem_type" \
            "$options"
    done </proc/mounts
}

# ---------------------------------------------------------------------------
# Diretórios com maior consumo
# ---------------------------------------------------------------------------

disk_path_is_excluded() {
    local path="${1:-}"
    local excluded_paths
    local excluded
    local -a exclusions=()

    excluded_paths="$(
        disk_config_get \
            "HC_DISK_EXCLUDED_PATHS" \
            "/proc,/sys,/dev,/run"
    )"

    IFS=',' read -r -a exclusions <<<"$excluded_paths"

    for excluded in "${exclusions[@]}"; do
        excluded="${excluded%/}"

        if [[ "$path" == "$excluded" || "$path" == "$excluded/"* ]]; then
            return 0
        fi
    done

    return 1
}

disk_collect_top_directories() {
    local scan_root
    local limit
    local same_filesystem
    local timeout_seconds
    local size_bytes
    local path
    local -a du_arguments=()

    scan_root="$(disk_config_get HC_DISK_SCAN_ROOT /)"
    limit="$(disk_config_get HC_DISK_TOP_DIRECTORIES_LIMIT 50)"
    same_filesystem="$(disk_config_get HC_DISK_SCAN_SAME_FILESYSTEM 0)"
    timeout_seconds="$(disk_config_get HC_LONG_COMMAND_TIMEOUT_SECONDS 300)"

    collector_table_create \
        "disk" \
        "usage_analysis" \
        "top_directories" \
        "Diretórios com maior consumo" \
        $'Diretório\tTamanho' \
        "Diretórios de primeiro nível com maior utilização de espaço." \
        "${HC_STATUS_OK:-OK}"

    [[ -d "$scan_root" ]] || {
        collector_table_set_status \
            "disk" \
            "usage_analysis" \
            "top_directories" \
            "${HC_STATUS_UNKNOWN:-UNKNOWN}"

        return 0
    }

    du_arguments=(-B1 --max-depth=1)

    if [[ "$same_filesystem" == "1" ]]; then
        du_arguments+=(-x)
    fi

    while IFS=$'\t' read -r size_bytes path; do
        [[ "$size_bytes" =~ ^[0-9]+$ ]] || continue
        [[ -n "$path" ]] || continue

        if disk_path_is_excluded "$path"; then
            continue
        fi

        collector_table_add_row \
            "disk" \
            "usage_analysis" \
            "top_directories" \
            "$path" \
            "$(utils_bytes_to_human "$size_bytes" 2)"
    done < <(
        if command -v timeout >/dev/null 2>&1; then
            timeout \
                "$timeout_seconds" \
                du \
                "${du_arguments[@]}" \
                "$scan_root" 2>/dev/null
        else
            du \
                "${du_arguments[@]}" \
                "$scan_root" 2>/dev/null
        fi |
        sort -nr |
        head -n "$limit"
    )
}

# ---------------------------------------------------------------------------
# Arquivos grandes
# ---------------------------------------------------------------------------

disk_collect_large_files() {
    local scan_root
    local limit
    local minimum_size
    local timeout_seconds
    local size_bytes
    local path
    local status
    local warning
    local critical

    scan_root="$(disk_config_get HC_DISK_SCAN_ROOT /)"
    limit="$(disk_config_get HC_DISK_TOP_FILES_LIMIT 50)"
    warning="$(disk_config_get HC_DISK_LARGE_FILE_WARNING_BYTES 1073741824)"
    critical="$(disk_config_get HC_DISK_LARGE_FILE_CRITICAL_BYTES 5368709120)"
    minimum_size="$warning"
    timeout_seconds="$(disk_config_get HC_LONG_COMMAND_TIMEOUT_SECONDS 300)"

    collector_table_create \
        "disk" \
        "usage_analysis" \
        "large_files" \
        "Arquivos grandes" \
        $'Arquivo\tTamanho\tStatus' \
        "Maiores arquivos encontrados a partir do diretório configurado." \
        "${HC_STATUS_OK:-OK}"

    [[ -d "$scan_root" ]] || return 0

    while IFS=$'\t' read -r size_bytes path; do
        [[ "$size_bytes" =~ ^[0-9]+$ ]] || continue
        [[ -n "$path" ]] || continue

        if disk_path_is_excluded "$path"; then
            continue
        fi

        status="$(
            utils_status_from_high_usage \
                "$size_bytes" \
                "$warning" \
                "$critical"
        )"

        collector_table_add_row \
            "disk" \
            "usage_analysis" \
            "large_files" \
            "$path" \
            "$(utils_bytes_to_human "$size_bytes" 2)" \
            "$status"
    done < <(
        if command -v timeout >/dev/null 2>&1; then
            timeout \
                "$timeout_seconds" \
                find \
                "$scan_root" \
                -xdev \
                -type f \
                -size +"${minimum_size}c" \
                -printf '%s\t%p\n' 2>/dev/null
        else
            find \
                "$scan_root" \
                -xdev \
                -type f \
                -size +"${minimum_size}c" \
                -printf '%s\t%p\n' 2>/dev/null
        fi |
        sort -nr |
        head -n "$limit"
    )
}

# ---------------------------------------------------------------------------
# Logs grandes
# ---------------------------------------------------------------------------

disk_collect_large_logs() {
    local warning
    local critical
    local limit
    local size_bytes
    local path
    local status

    warning="$(disk_config_get HC_DISK_LARGE_LOG_WARNING_BYTES 104857600)"
    critical="$(disk_config_get HC_DISK_LARGE_LOG_CRITICAL_BYTES 1073741824)"
    limit="$(disk_config_get HC_DISK_TOP_FILES_LIMIT 50)"

    collector_table_create \
        "disk" \
        "logs" \
        "large_logs" \
        "Arquivos de log grandes" \
        $'Arquivo\tTamanho\tStatus' \
        "Arquivos grandes encontrados em /var/log." \
        "${HC_STATUS_OK:-OK}"

    [[ -d /var/log ]] || return 0

    while IFS=$'\t' read -r size_bytes path; do
        [[ "$size_bytes" =~ ^[0-9]+$ ]] || continue

        status="$(
            utils_status_from_high_usage \
                "$size_bytes" \
                "$warning" \
                "$critical"
        )"

        collector_table_add_row \
            "disk" \
            "logs" \
            "large_logs" \
            "$path" \
            "$(utils_bytes_to_human "$size_bytes" 2)" \
            "$status"

        if [[ "$status" == "${HC_STATUS_CRITICAL:-CRITICAL}" ]]; then
            collector_alert_add \
                "disk" \
                "$status" \
                "Arquivo de log muito grande" \
                "O arquivo ${path} ocupa $(utils_bytes_to_human "$size_bytes" 2)." \
                "Revise rotação de logs, retenção e origem do crescimento."
        fi
    done < <(
        find \
            /var/log \
            -xdev \
            -type f \
            -size +"${warning}c" \
            -printf '%s\t%p\n' 2>/dev/null |
        sort -nr |
        head -n "$limit"
    )
}

# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------

disk_collect_docker_usage() {
    local docker_root=""
    local docker_bytes=0
    local status="${HC_STATUS_UNKNOWN:-UNKNOWN}"
    local warning
    local critical

    warning="$(disk_config_get HC_DOCKER_TOTAL_USAGE_WARNING_BYTES 53687091200)"
    critical="$(disk_config_get HC_DOCKER_TOTAL_USAGE_CRITICAL_BYTES 107374182400)"

    if ! command -v docker >/dev/null 2>&1; then
        collector_metric_set \
            "disk" \
            "applications" \
            "docker_usage" \
            "Uso de disco do Docker" \
            "Docker não instalado" \
            "" \
            "bytes" \
            "bytes" \
            "${HC_STATUS_SKIPPED:-SKIPPED}" \
            "O comando Docker não está disponível." \
            "docker"

        return 0
    fi

    docker_root="$(
        docker info \
            --format '{{.DockerRootDir}}' 2>/dev/null ||
        true
    )"

    if [[ -n "$docker_root" && -d "$docker_root" ]]; then
        docker_bytes="$(
            du -s -B1 "$docker_root" 2>/dev/null |
            awk '{print $1 + 0}'
        )"

        status="$(
            utils_status_from_high_usage \
                "$docker_bytes" \
                "$warning" \
                "$critical"
        )"
    fi

    collector_metric_set \
        "disk" \
        "applications" \
        "docker_usage" \
        "Uso de disco do Docker" \
        "$(utils_bytes_to_human "$docker_bytes" 2)" \
        "$docker_bytes" \
        "bytes" \
        "bytes" \
        "$status" \
        "Espaço utilizado pelo diretório de dados do Docker." \
        "${docker_root:-docker info}"
}

# ---------------------------------------------------------------------------
# Ollama
# ---------------------------------------------------------------------------

disk_collect_ollama_usage() {
    local configured_paths
    local path
    local size_bytes
    local total_bytes=0
    local warning
    local critical
    local status="${HC_STATUS_SKIPPED:-SKIPPED}"
    local -a paths=()

    configured_paths="$(
        disk_config_get \
            "HC_OLLAMA_MODELS_PATHS" \
            "/usr/share/ollama/.ollama/models,/var/lib/ollama/.ollama/models,/root/.ollama/models"
    )"

    warning="$(disk_config_get HC_DISK_OLLAMA_WARNING_PERCENT 80)"
    critical="$(disk_config_get HC_DISK_OLLAMA_CRITICAL_PERCENT 92)"

    collector_table_create \
        "disk" \
        "applications" \
        "ollama_paths" \
        "Diretórios do Ollama" \
        $'Diretório\tTamanho' \
        "Espaço utilizado pelos diretórios de modelos do Ollama." \
        "${HC_STATUS_OK:-OK}"

    IFS=',' read -r -a paths <<<"$configured_paths"

    for path in "${paths[@]}"; do
        [[ -d "$path" ]] || continue

        size_bytes="$(
            du -s -B1 "$path" 2>/dev/null |
            awk '{print $1 + 0}'
        )"

        total_bytes=$((total_bytes + size_bytes))

        collector_table_add_row \
            "disk" \
            "applications" \
            "ollama_paths" \
            "$path" \
            "$(utils_bytes_to_human "$size_bytes" 2)"
    done

    if ((total_bytes > 0)); then
        status="${HC_STATUS_OK:-OK}"
    fi

    collector_metric_set \
        "disk" \
        "applications" \
        "ollama_usage" \
        "Uso de disco do Ollama" \
        "$(utils_bytes_to_human "$total_bytes" 2)" \
        "$total_bytes" \
        "bytes" \
        "bytes" \
        "$status" \
        "Espaço total utilizado pelos diretórios de modelos do Ollama." \
        "du"
}

# ---------------------------------------------------------------------------
# Execução
# ---------------------------------------------------------------------------

disk_run() {
    if disk_config_enabled "HC_DISK_INCLUDE_FILESYSTEMS" 1; then
        disk_collect_filesystems
    fi

    if disk_config_enabled "HC_DISK_INCLUDE_INODES" 1; then
        disk_collect_inodes
    fi

    if disk_config_enabled "HC_DISK_INCLUDE_BLOCK_DEVICES" 1; then
        disk_collect_block_devices
    fi

    if disk_config_enabled "HC_DISK_INCLUDE_MOUNTS" 1; then
        disk_collect_mounts
    fi

    if disk_config_enabled "HC_DISK_INCLUDE_TOP_DIRECTORIES" 1; then
        disk_collect_top_directories
    fi

    if disk_config_enabled "HC_DISK_INCLUDE_TOP_FILES" 1; then
        disk_collect_large_files
    fi

    if disk_config_enabled "HC_DISK_INCLUDE_LARGE_LOGS" 1; then
        disk_collect_large_logs
    fi

    if disk_config_enabled "HC_DISK_INCLUDE_DOCKER_USAGE" 1; then
        disk_collect_docker_usage
    fi

    if disk_config_enabled "HC_DISK_INCLUDE_OLLAMA_USAGE" 1; then
        disk_collect_ollama_usage
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Validação interna
# ---------------------------------------------------------------------------

disk_validate() {
    local failure=0
    local root_total=""
    local root_usage=""
    local metric_count=0
    local table_count=0

    if ! declare -F collector_initialize >/dev/null 2>&1; then
        printf 'collector_initialize não está disponível.\n' >&2
        return 1
    fi

    collector_initialize
    collector_module_start "disk" "Disco"

    if ! disk_run; then
        printf 'disk_run retornou falha.\n' >&2
        failure=1
    fi

    root_total="$(
        collector_metric_get \
            "disk" \
            "root" \
            "total_bytes" \
            "raw_value" 2>/dev/null ||
        true
    )"

    root_usage="$(
        collector_metric_get \
            "disk" \
            "root" \
            "usage_percent" \
            "raw_value" 2>/dev/null ||
        true
    )"

    metric_count="$(collector_metric_count disk)"
    table_count="$(collector_table_count disk)"

    if [[ ! "$root_total" =~ ^[0-9]+$ ]] || ((root_total <= 0)); then
        printf 'Espaço total da raiz inválido: %s\n' "$root_total" >&2
        failure=1
    fi

    if ! utils_is_percentage "$root_usage"; then
        printf 'Uso da raiz inválido: %s\n' "$root_usage" >&2
        failure=1
    fi

    if [[ ! "$metric_count" =~ ^[0-9]+$ ]] ||
        ((metric_count < 4)); then

        printf \
            'Quantidade insuficiente de métricas de disco: %s\n' \
            "$metric_count" >&2

        failure=1
    fi

    if [[ ! "$table_count" =~ ^[0-9]+$ ]] ||
        ((table_count < 4)); then

        printf \
            'Quantidade insuficiente de tabelas de disco: %s\n' \
            "$table_count" >&2

        failure=1
    fi

    collector_module_finish \
        "disk" \
        "$(collector_module_get_status disk)" \
        "Validação concluída."

    collector_finalize

    return "$failure"
}
