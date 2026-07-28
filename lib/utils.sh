#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_UTILS_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_UTILS_LOADED=1

# ---------------------------------------------------------------------------
# Validação básica
# ---------------------------------------------------------------------------

utils_is_integer() {
    local value="${1:-}"

    [[ "$value" =~ ^-?[0-9]+$ ]]
}

utils_is_unsigned_integer() {
    local value="${1:-}"

    [[ "$value" =~ ^[0-9]+$ ]]
}

utils_is_decimal() {
    local value="${1:-}"

    [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

utils_is_percentage() {
    local value="${1:-}"

    if ! utils_is_decimal "$value"; then
        return 1
    fi

    awk -v value="$value" 'BEGIN {
        exit !(value >= 0 && value <= 100)
    }'
}

utils_is_boolean() {
    local value="${1:-}"

    case "${value,,}" in
        1 | 0 | true | false | yes | no | sim | nao | não | on | off | enabled | disabled)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

utils_is_ipv4() {
    local address="${1:-}"
    local octet
    local -a octets=()

    if [[ ! "$address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi

    IFS='.' read -r -a octets <<<"$address"

    if ((${#octets[@]} != 4)); then
        return 1
    fi

    for octet in "${octets[@]}"; do
        if ! utils_is_unsigned_integer "$octet"; then
            return 1
        fi

        if ((10#$octet < 0 || 10#$octet > 255)); then
            return 1
        fi
    done

    return 0
}

utils_is_ipv6() {
    local address="${1:-}"

    [[ -n "$address" && "$address" == *:* && "$address" =~ ^[0-9A-Fa-f:.%]+$ ]]
}

utils_is_port() {
    local port="${1:-}"

    if ! utils_is_unsigned_integer "$port"; then
        return 1
    fi

    ((port >= 1 && port <= 65535))
}

utils_is_domain() {
    local domain="${1:-}"

    domain="${domain%.}"

    if [[ -z "$domain" || ${#domain} -gt 253 ]]; then
        return 1
    fi

    [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

utils_is_url() {
    local url="${1:-}"

    [[ "$url" =~ ^https?://[^[:space:]]+$ ]]
}

utils_is_systemd_unit() {
    local unit="${1:-}"

    [[ "$unit" =~ ^[A-Za-z0-9_.@:-]+\.(service|socket|timer|target|mount|path)$ ]]
}

# ---------------------------------------------------------------------------
# Strings
# ---------------------------------------------------------------------------

utils_trim() {
    local value="${1:-}"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s' "$value"
}

utils_ltrim() {
    local value="${1:-}"

    value="${value#"${value%%[![:space:]]*}"}"

    printf '%s' "$value"
}

utils_rtrim() {
    local value="${1:-}"

    value="${value%"${value##*[![:space:]]}"}"

    printf '%s' "$value"
}

utils_to_lower() {
    local value="${1:-}"

    printf '%s' "${value,,}"
}

utils_to_upper() {
    local value="${1:-}"

    printf '%s' "${value^^}"
}

utils_capitalize() {
    local value="${1:-}"

    if [[ -z "$value" ]]; then
        return 0
    fi

    printf '%s%s' "${value:0:1}" "${value:1}" |
        awk '{
            first = substr($0, 1, 1)
            rest = substr($0, 2)
            printf "%s%s", toupper(first), rest
        }'
}

utils_starts_with() {
    local value="${1:-}"
    local prefix="${2:-}"

    [[ "$value" == "$prefix"* ]]
}

utils_ends_with() {
    local value="${1:-}"
    local suffix="${2:-}"

    [[ "$value" == *"$suffix" ]]
}

utils_contains() {
    local value="${1:-}"
    local fragment="${2:-}"

    [[ "$value" == *"$fragment"* ]]
}

utils_repeat() {
    local character="${1:- }"
    local count="${2:-0}"
    local result=""

    if ! utils_is_unsigned_integer "$count"; then
        return 1
    fi

    if ((count == 0)); then
        return 0
    fi

    printf -v result '%*s' "$count" ''
    result="${result// /$character}"

    printf '%s' "$result"
}

utils_truncate() {
    local value="${1:-}"
    local maximum_length="${2:-80}"
    local suffix="${3:-...}"
    local retained_length

    if ! utils_is_unsigned_integer "$maximum_length"; then
        return 1
    fi

    if ((${#value} <= maximum_length)); then
        printf '%s' "$value"
        return 0
    fi

    if ((maximum_length <= ${#suffix})); then
        printf '%s' "${value:0:maximum_length}"
        return 0
    fi

    retained_length=$((maximum_length - ${#suffix}))

    printf '%s%s' "${value:0:retained_length}" "$suffix"
}

utils_sanitize_single_line() {
    local value="${1:-}"

    value="${value//$'\r'/ }"
    value="${value//$'\n'/ }"
    value="${value//$'\t'/ }"

    while [[ "$value" == *"  "* ]]; do
        value="${value//  / }"
    done

    utils_trim "$value"
}

utils_slugify() {
    local value="${1:-}"

    value="$(utils_to_lower "$value")"

    if command -v iconv >/dev/null 2>&1; then
        value="$(printf '%s' "$value" |
            iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$value")"
    fi

    value="$(printf '%s' "$value" |
        sed -E \
            -e 's/[^a-z0-9]+/-/g' \
            -e 's/^-+//' \
            -e 's/-+$//' \
            -e 's/-+/-/g')"

    printf '%s' "$value"
}

utils_join_by() {
    local delimiter="${1:-}"
    shift || true

    local first=1
    local item

    for item in "$@"; do
        if ((first == 1)); then
            printf '%s' "$item"
            first=0
        else
            printf '%s%s' "$delimiter" "$item"
        fi
    done
}

utils_split_lines() {
    local value="${1:-}"
    local output_array_name="${2:-}"

    if [[ -z "$output_array_name" ]]; then
        return 1
    fi

    local -n output_array_ref="$output_array_name"

    output_array_ref=()

    while IFS= read -r line; do
        output_array_ref+=("$line")
    done <<<"$value"
}

utils_strip_quotes() {
    local value="${1:-}"

    if [[ ${#value} -ge 2 ]]; then
        if [[ "$value" == \"*\" && "$value" == *\" ]]; then
            value="${value:1:${#value}-2}"
        elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
            value="${value:1:${#value}-2}"
        fi
    fi

    printf '%s' "$value"
}

utils_mask_secret() {
    local value="${1:-}"
    local visible_start="${2:-2}"
    local visible_end="${3:-2}"
    local hidden_length

    if ! utils_is_unsigned_integer "$visible_start" ||
        ! utils_is_unsigned_integer "$visible_end"; then
        return 1
    fi

    if ((${#value} <= visible_start + visible_end)); then
        utils_repeat "*" "${#value}"
        return 0
    fi

    hidden_length=$((
        ${#value} - visible_start - visible_end
    ))

    printf '%s' "${value:0:visible_start}"
    utils_repeat "*" "$hidden_length"
    printf '%s' "${value: -visible_end}"
}

# ---------------------------------------------------------------------------
# Booleanos
# ---------------------------------------------------------------------------

utils_boolean_normalize() {
    local value="${1:-}"

    case "${value,,}" in
        1 | true | yes | sim | on | enabled)
            printf 'true\n'
            ;;
        0 | false | no | nao | não | off | disabled)
            printf 'false\n'
            ;;
        *)
            printf 'false\n'
            return 1
            ;;
    esac
}

utils_boolean_to_integer() {
    local normalized

    if normalized="$(utils_boolean_normalize "${1:-}")"; then
        if [[ "$normalized" == "true" ]]; then
            printf '1\n'
        else
            printf '0\n'
        fi

        return 0
    fi

    printf '0\n'
    return 1
}

# ---------------------------------------------------------------------------
# Números
# ---------------------------------------------------------------------------

utils_min() {
    local first="${1:-0}"
    local second="${2:-0}"

    awk -v first="$first" -v second="$second" 'BEGIN {
        if (first < second) {
            print first
        } else {
            print second
        }
    }'
}

utils_max() {
    local first="${1:-0}"
    local second="${2:-0}"

    awk -v first="$first" -v second="$second" 'BEGIN {
        if (first > second) {
            print first
        } else {
            print second
        }
    }'
}

utils_clamp() {
    local value="${1:-0}"
    local minimum="${2:-0}"
    local maximum="${3:-100}"

    awk \
        -v value="$value" \
        -v minimum="$minimum" \
        -v maximum="$maximum" \
        'BEGIN {
            if (value < minimum) {
                print minimum
            } else if (value > maximum) {
                print maximum
            } else {
                print value
            }
        }'
}

utils_round() {
    local value="${1:-}"
    local precision="${2:-0}"

    if ! utils_is_decimal "$value"; then
        return 1
    fi

    if ! utils_is_unsigned_integer "$precision"; then
        return 2
    fi

    awk \
        -v value="$value" \
        -v precision="$precision" '
        BEGIN {
            factor = 10 ^ precision

            if (value >= 0) {
                rounded = int((value * factor) + 0.5)
            } else {
                rounded = int((value * factor) - 0.5)
            }

            format = "%." precision "f\n"
            printf format, rounded / factor
        }
        '
}

utils_safe_divide() {
    local numerator="${1:-0}"
    local denominator="${2:-0}"
    local precision="${3:-2}"

    if ! utils_is_decimal "$numerator" ||
        ! utils_is_decimal "$denominator" ||
        ! utils_is_unsigned_integer "$precision"; then
        return 1
    fi

    awk \
        -v numerator="$numerator" \
        -v denominator="$denominator" \
        -v precision="$precision" \
        'BEGIN {
            if (denominator == 0) {
                printf "%.*f\n", precision, 0
                exit 1
            }

            printf "%.*f\n", precision, numerator / denominator
        }'
}

utils_percentage() {
    local part="${1:-0}"
    local total="${2:-0}"
    local precision="${3:-2}"

    if ! utils_is_decimal "$part" ||
        ! utils_is_decimal "$total" ||
        ! utils_is_unsigned_integer "$precision"; then
        return 1
    fi

    awk \
        -v part="$part" \
        -v total="$total" \
        -v precision="$precision" \
        'BEGIN {
            if (total == 0) {
                printf "%.*f\n", precision, 0
                exit 1
            }

            printf "%.*f\n", precision, (part / total) * 100
        }'
}

utils_compare_numbers() {
    local first="${1:-0}"
    local operator="${2:-eq}"
    local second="${3:-0}"

    case "$operator" in
        eq | "==")
            awk -v first="$first" -v second="$second" 'BEGIN {
                exit !(first == second)
            }'
            ;;
        ne | "!=")
            awk -v first="$first" -v second="$second" 'BEGIN {
                exit !(first != second)
            }'
            ;;
        gt | ">")
            awk -v first="$first" -v second="$second" 'BEGIN {
                exit !(first > second)
            }'
            ;;
        ge | ">=")
            awk -v first="$first" -v second="$second" 'BEGIN {
                exit !(first >= second)
            }'
            ;;
        lt | "<")
            awk -v first="$first" -v second="$second" 'BEGIN {
                exit !(first < second)
            }'
            ;;
        le | "<=")
            awk -v first="$first" -v second="$second" 'BEGIN {
                exit !(first <= second)
            }'
            ;;
        *)
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Formatação de bytes
# ---------------------------------------------------------------------------

utils_bytes_to_human() {
    local bytes="${1:-0}"
    local precision="${2:-2}"

    if ! utils_is_unsigned_integer "$bytes" ||
        ! utils_is_unsigned_integer "$precision"; then
        return 1
    fi

    awk \
        -v bytes="$bytes" \
        -v precision="$precision" \
        'BEGIN {
            split("B KiB MiB GiB TiB PiB EiB", units, " ")
            unit_index = 1
            value = bytes + 0

            while (value >= 1024 && unit_index < 7) {
                value /= 1024
                unit_index++
            }

            if (unit_index == 1) {
                printf "%.0f %s\n", value, units[unit_index]
            } else {
                printf "%.*f %s\n", precision, value, units[unit_index]
            }
        }'
}

utils_kib_to_bytes() {
    local kib="${1:-0}"

    if ! utils_is_unsigned_integer "$kib"; then
        return 1
    fi

    printf '%s\n' "$((kib * 1024))"
}

utils_mib_to_bytes() {
    local mib="${1:-0}"

    if ! utils_is_unsigned_integer "$mib"; then
        return 1
    fi

    printf '%s\n' "$((mib * 1024 * 1024))"
}

utils_gib_to_bytes() {
    local gib="${1:-0}"

    if ! utils_is_unsigned_integer "$gib"; then
        return 1
    fi

    printf '%s\n' "$((gib * 1024 * 1024 * 1024))"
}

utils_human_to_bytes() {
    local input="${1:-}"
    local number
    local unit
    local multiplier=1

    input="$(utils_trim "$input")"
    input="${input// /}"

    if [[ ! "$input" =~ ^([0-9]+([.][0-9]+)?)([A-Za-z]+)?$ ]]; then
        return 1
    fi

    number="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[3]:-B}"
    unit="${unit^^}"

    case "$unit" in
        B)
            multiplier=1
            ;;
        K | KB | KIB)
            multiplier=1024
            ;;
        M | MB | MIB)
            multiplier=$((1024 * 1024))
            ;;
        G | GB | GIB)
            multiplier=$((1024 * 1024 * 1024))
            ;;
        T | TB | TIB)
            multiplier=$((1024 * 1024 * 1024 * 1024))
            ;;
        *)
            return 1
            ;;
    esac

    awk \
        -v number="$number" \
        -v multiplier="$multiplier" \
        'BEGIN {
            printf "%.0f\n", number * multiplier
        }'
}

# ---------------------------------------------------------------------------
# Tempo e duração
# ---------------------------------------------------------------------------

utils_now_iso8601() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

utils_now_datetime() {
    date '+%Y-%m-%d %H:%M:%S'
}

utils_now_epoch() {
    date '+%s'
}

utils_timestamp_filename() {
    date '+%Y%m%d_%H%M%S'
}

utils_seconds_to_duration() {
    local total_seconds="${1:-0}"
    local days
    local hours
    local minutes
    local seconds
    local output=""

    if ! utils_is_unsigned_integer "$total_seconds"; then
        return 1
    fi

    days=$((total_seconds / 86400))
    hours=$(((total_seconds % 86400) / 3600))
    minutes=$(((total_seconds % 3600) / 60))
    seconds=$((total_seconds % 60))

    if ((days > 0)); then
        output+="${days}d "
    fi

    if ((hours > 0 || days > 0)); then
        output+="${hours}h "
    fi

    if ((minutes > 0 || hours > 0 || days > 0)); then
        output+="${minutes}m "
    fi

    output+="${seconds}s"

    printf '%s\n' "$output"
}

utils_milliseconds_to_duration() {
    local milliseconds="${1:-0}"

    if ! utils_is_unsigned_integer "$milliseconds"; then
        return 1
    fi

    if ((milliseconds < 1000)); then
        printf '%s ms\n' "$milliseconds"
    elif ((milliseconds < 60000)); then
        awk -v value="$milliseconds" 'BEGIN {
            printf "%.2f s\n", value / 1000
        }'
    else
        awk -v value="$milliseconds" 'BEGIN {
            printf "%.2f min\n", value / 60000
        }'
    fi
}

utils_elapsed_seconds() {
    local start_epoch="${1:-0}"
    local end_epoch="${2:-$(date '+%s')}"

    if ! utils_is_unsigned_integer "$start_epoch" ||
        ! utils_is_unsigned_integer "$end_epoch"; then
        return 1
    fi

    if ((end_epoch < start_epoch)); then
        printf '0\n'
        return 1
    fi

    printf '%s\n' "$((end_epoch - start_epoch))"
}

# ---------------------------------------------------------------------------
# Caminhos e arquivos
# ---------------------------------------------------------------------------

utils_absolute_path() {
    local path="${1:-}"

    if [[ -z "$path" ]]; then
        return 1
    fi

    if [[ "$path" == /* ]]; then
        printf '%s\n' "$path"
    else
        printf '%s/%s\n' "$PWD" "$path"
    fi
}

utils_realpath() {
    local path="${1:-}"

    if [[ -z "$path" ]]; then
        return 1
    fi

    if command -v realpath >/dev/null 2>&1; then
        realpath -m -- "$path"
        return
    fi

    if [[ -d "$path" ]]; then
        (
            cd -- "$path" >/dev/null 2>&1
            pwd -P
        )
        return
    fi

    local directory
    local basename_value

    directory="$(dirname -- "$path")"
    basename_value="$(basename -- "$path")"

    (
        cd -- "$directory" >/dev/null 2>&1
        printf '%s/%s\n' "$(pwd -P)" "$basename_value"
    )
}

utils_path_exists() {
    local path="${1:-}"

    [[ -n "$path" && -e "$path" ]]
}

utils_file_exists() {
    local path="${1:-}"

    [[ -n "$path" && -f "$path" ]]
}

utils_directory_exists() {
    local path="${1:-}"

    [[ -n "$path" && -d "$path" ]]
}

utils_is_readable() {
    local path="${1:-}"

    [[ -n "$path" && -r "$path" ]]
}

utils_is_writable() {
    local path="${1:-}"

    [[ -n "$path" && -w "$path" ]]
}

utils_is_executable() {
    local path="${1:-}"

    [[ -n "$path" && -x "$path" ]]
}

utils_ensure_directory() {
    local directory="${1:-}"
    local mode="${2:-0750}"

    if [[ -z "$directory" ]]; then
        return 1
    fi

    if [[ -e "$directory" && ! -d "$directory" ]]; then
        return 1
    fi

    mkdir -p -- "$directory"
    chmod "$mode" "$directory" 2>/dev/null || true
}

utils_ensure_file() {
    local file_path="${1:-}"
    local mode="${2:-0640}"
    local parent_directory

    if [[ -z "$file_path" ]]; then
        return 1
    fi

    parent_directory="$(dirname -- "$file_path")"

    utils_ensure_directory "$parent_directory"
    touch -- "$file_path"
    chmod "$mode" "$file_path" 2>/dev/null || true
}

utils_file_size_bytes() {
    local file_path="${1:-}"

    if [[ ! -f "$file_path" ]]; then
        return 1
    fi

    stat -c '%s' -- "$file_path"
}

utils_directory_size_bytes() {
    local directory="${1:-}"

    if [[ ! -d "$directory" ]]; then
        return 1
    fi

    du -sb -- "$directory" 2>/dev/null |
        awk '{print $1}'
}

utils_file_mtime_epoch() {
    local file_path="${1:-}"

    if [[ ! -e "$file_path" ]]; then
        return 1
    fi

    stat -c '%Y' -- "$file_path"
}

utils_file_age_seconds() {
    local file_path="${1:-}"
    local modified_epoch
    local current_epoch

    if [[ ! -e "$file_path" ]]; then
        return 1
    fi

    modified_epoch="$(utils_file_mtime_epoch "$file_path")"
    current_epoch="$(date '+%s')"

    printf '%s\n' "$((current_epoch - modified_epoch))"
}

utils_create_temp_file() {
    local prefix="${1:-vps-healthcheck}"
    local temp_directory="${TEMP_ROOT:-${TMPDIR:-/tmp}}"

    mkdir -p -- "$temp_directory"

    mktemp "${temp_directory}/${prefix}.XXXXXX"
}

utils_create_temp_directory() {
    local prefix="${1:-vps-healthcheck}"
    local temp_directory="${TEMP_ROOT:-${TMPDIR:-/tmp}}"

    mkdir -p -- "$temp_directory"

    mktemp -d "${temp_directory}/${prefix}.XXXXXX"
}

utils_atomic_write() {
    local destination="${1:-}"
    local mode="${2:-0640}"
    local destination_directory
    local temporary_file

    if [[ -z "$destination" ]]; then
        return 1
    fi

    destination_directory="$(dirname -- "$destination")"
    utils_ensure_directory "$destination_directory"

    temporary_file="$(mktemp "${destination_directory}/.$(basename -- "$destination").XXXXXX")"

    if ! cat >"$temporary_file"; then
        rm -f -- "$temporary_file"
        return 1
    fi

    chmod "$mode" "$temporary_file" 2>/dev/null || true
    mv -f -- "$temporary_file" "$destination"
}

utils_copy_file_atomic() {
    local source="${1:-}"
    local destination="${2:-}"
    local mode="${3:-0640}"

    if [[ ! -f "$source" || -z "$destination" ]]; then
        return 1
    fi

    utils_atomic_write "$destination" "$mode" <"$source"
}

utils_read_file() {
    local file_path="${1:-}"

    if [[ ! -r "$file_path" ]]; then
        return 1
    fi

    cat -- "$file_path"
}

utils_read_first_line() {
    local file_path="${1:-}"

    if [[ ! -r "$file_path" ]]; then
        return 1
    fi

    IFS= read -r line <"$file_path" || true
    printf '%s\n' "${line:-}"
}

utils_read_key_value_file() {
    local file_path="${1:-}"
    local output_array_name="${2:-}"
    local line
    local key
    local value

    if [[ ! -r "$file_path" || -z "$output_array_name" ]]; then
        return 1
    fi

    local -n output_array_ref="$output_array_name"

    output_array_ref=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(utils_trim "$line")"

        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi

        if [[ "$line" != *=* ]]; then
            continue
        fi

        key="${line%%=*}"
        value="${line#*=}"

        key="$(utils_trim "$key")"
        value="$(utils_trim "$value")"
        value="$(utils_strip_quotes "$value")"

        if [[ -n "$key" ]]; then
            output_array_ref["$key"]="$value"
        fi
    done <"$file_path"
}

# ---------------------------------------------------------------------------
# Comandos
# ---------------------------------------------------------------------------

utils_command_exists() {
    local command_name="${1:-}"

    [[ -n "$command_name" ]] &&
        command -v "$command_name" >/dev/null 2>&1
}

utils_command_path() {
    local command_name="${1:-}"

    if ! utils_command_exists "$command_name"; then
        return 1
    fi

    command -v "$command_name"
}

utils_command_version() {
    local command_name="${1:-}"
    local output=""

    if ! utils_command_exists "$command_name"; then
        return 1
    fi

    output="$(
        "$command_name" --version 2>&1 |
            head -n 1 ||
            true
    )"

    utils_sanitize_single_line "$output"
}

utils_quote_command() {
    local quoted=""
    local argument

    for argument in "$@"; do
        printf -v argument '%q' "$argument"

        if [[ -z "$quoted" ]]; then
            quoted="$argument"
        else
            quoted+=" ${argument}"
        fi
    done

    printf '%s' "$quoted"
}

utils_run_with_timeout() {
    local timeout_seconds="${1:-30}"
    shift || true

    if ! utils_is_unsigned_integer "$timeout_seconds" || (($# == 0)); then
        return 2
    fi

    if command -v timeout >/dev/null 2>&1; then
        timeout \
            --signal=TERM \
            --kill-after=5 \
            "$timeout_seconds" \
            "$@"
    else
        "$@"
    fi
}

utils_capture_command() {
    local output_variable_name="${1:-}"
    local error_variable_name="${2:-}"
    local exit_code_variable_name="${3:-}"
    shift 3 || true

    local stdout_file
    local stderr_file
    local exit_code=0
    local stdout_value=""
    local stderr_value=""

    if [[ -z "$output_variable_name" ||
        -z "$error_variable_name" ||
        -z "$exit_code_variable_name" ||
        $# -eq 0 ]]; then
        return 2
    fi

    stdout_file="$(utils_create_temp_file "stdout")"
    stderr_file="$(utils_create_temp_file "stderr")"

    if "$@" >"$stdout_file" 2>"$stderr_file"; then
        exit_code=0
    else
        exit_code=$?
    fi

    stdout_value="$(cat -- "$stdout_file")"
    stderr_value="$(cat -- "$stderr_file")"

    rm -f -- "$stdout_file" "$stderr_file"

    printf -v "$output_variable_name" '%s' "$stdout_value"
    printf -v "$error_variable_name" '%s' "$stderr_value"
    printf -v "$exit_code_variable_name" '%s' "$exit_code"

    return 0
}

utils_run_as_root() {
    if (($# == 0)); then
        return 2
    fi

    if ((EUID == 0)); then
        "$@"
        return
    fi

    if [[ "${USE_SUDO:-1}" != "1" ]]; then
        return "${EXIT_PERMISSION_ERROR:-4}"
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        return "${EXIT_DEPENDENCY_ERROR:-3}"
    fi

    if [[ "${NON_INTERACTIVE:-0}" == "1" ]]; then
        sudo -n "$@"
    else
        sudo "$@"
    fi
}

utils_can_use_sudo() {
    if ((EUID == 0)); then
        return 0
    fi

    if [[ "${USE_SUDO:-1}" != "1" ]] ||
        ! command -v sudo >/dev/null 2>&1; then
        return 1
    fi

    sudo -n true >/dev/null 2>&1
}

utils_process_exists() {
    local pid="${1:-}"

    if ! utils_is_unsigned_integer "$pid" || ((pid <= 0)); then
        return 1
    fi

    kill -0 "$pid" >/dev/null 2>&1
}

utils_process_command() {
    local pid="${1:-}"

    if ! utils_process_exists "$pid"; then
        return 1
    fi

    if [[ -r "/proc/${pid}/cmdline" ]]; then
        tr '\0' ' ' <"/proc/${pid}/cmdline" |
            sed -E 's/[[:space:]]+$//'
        return
    fi

    ps -p "$pid" -o args= 2>/dev/null
}

utils_process_cwd() {
    local pid="${1:-}"

    if ! utils_process_exists "$pid"; then
        return 1
    fi

    readlink -f -- "/proc/${pid}/cwd" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Arrays
# ---------------------------------------------------------------------------

utils_array_contains() {
    local needle="${1:-}"
    shift || true

    local item

    for item in "$@"; do
        if [[ "$item" == "$needle" ]]; then
            return 0
        fi
    done

    return 1
}

utils_array_unique() {
    local input_array_name="${1:-}"
    local output_array_name="${2:-}"
    local item
    local -A seen=()

    if [[ -z "$input_array_name" || -z "$output_array_name" ]]; then
        return 1
    fi

    local -n input_array_ref="$input_array_name"
    local -n output_array_ref="$output_array_name"

    output_array_ref=()

    for item in "${input_array_ref[@]}"; do
        if [[ -z "${seen[$item]+x}" ]]; then
            output_array_ref+=("$item")
            seen["$item"]=1
        fi
    done
}

utils_array_sort() {
    local input_array_name="${1:-}"
    local output_array_name="${2:-}"

    if [[ -z "$input_array_name" || -z "$output_array_name" ]]; then
        return 1
    fi

    local -n input_array_ref="$input_array_name"
    local -n output_array_ref="$output_array_name"

    output_array_ref=()

    if ((${#input_array_ref[@]} == 0)); then
        return 0
    fi

    mapfile -t output_array_ref < <(
        printf '%s\n' "${input_array_ref[@]}" |
            LC_ALL=C sort
    )
}

utils_array_sort_numeric() {
    local input_array_name="${1:-}"
    local output_array_name="${2:-}"

    if [[ -z "$input_array_name" || -z "$output_array_name" ]]; then
        return 1
    fi

    local -n input_array_ref="$input_array_name"
    local -n output_array_ref="$output_array_name"

    output_array_ref=()

    if ((${#input_array_ref[@]} == 0)); then
        return 0
    fi

    mapfile -t output_array_ref < <(
        printf '%s\n' "${input_array_ref[@]}" |
            sort -n
    )
}

# ---------------------------------------------------------------------------
# JSON
# ---------------------------------------------------------------------------

utils_json_escape() {
    local value="${1:-}"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\b'/\\b}"
    value="${value//$'\f'/\\f}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"

    printf '%s' "$value"
}

utils_json_string() {
    local value="${1:-}"

    printf '"%s"' "$(utils_json_escape "$value")"
}

utils_json_boolean() {
    local value="${1:-false}"
    local normalized

    if normalized="$(utils_boolean_normalize "$value")"; then
        printf '%s' "$normalized"
    else
        printf 'false'
        return 1
    fi
}

utils_json_number_or_null() {
    local value="${1:-}"

    if utils_is_decimal "$value"; then
        printf '%s' "$value"
    else
        printf 'null'
    fi
}

utils_json_value() {
    local value="${1:-}"
    local data_type="${2:-string}"

    case "$data_type" in
        string)
            utils_json_string "$value"
            ;;
        integer | float | number | percentage | bytes | seconds)
            utils_json_number_or_null "$value"
            ;;
        boolean)
            utils_json_boolean "$value"
            ;;
        null)
            printf 'null'
            ;;
        raw)
            printf '%s' "$value"
            ;;
        *)
            utils_json_string "$value"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# HTML
# ---------------------------------------------------------------------------

utils_html_escape() {
    local value="${1:-}"

    printf '%s' "$value" |
        sed \
            -e 's/&/\&amp;/g' \
            -e 's/</\&lt;/g' \
            -e 's/>/\&gt;/g' \
            -e 's/"/\&quot;/g' \
            -e "s/'/\&#39;/g"
}

utils_html_attribute_escape() {
    local value="${1:-}"

    value="$(utils_html_escape "$value")"
    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\t'/ }"

    printf '%s' "$value"
}

# ---------------------------------------------------------------------------
# Sistema
# ---------------------------------------------------------------------------

utils_hostname() {
    hostname -f 2>/dev/null ||
        hostname 2>/dev/null ||
        printf 'desconhecido\n'
}

utils_architecture() {
    uname -m 2>/dev/null ||
        printf 'desconhecida\n'
}

utils_kernel_version() {
    uname -r 2>/dev/null ||
        printf 'desconhecido\n'
}

utils_current_user() {
    id -un 2>/dev/null ||
        printf '%s\n' "${USER:-desconhecido}"
}

utils_current_uid() {
    id -u 2>/dev/null ||
        printf '0\n'
}

utils_is_root() {
    ((EUID == 0))
}

utils_os_release_value() {
    local key="${1:-}"
    local file_path="${2:-/etc/os-release}"
    local line
    local value

    if [[ -z "$key" || ! -r "$file_path" ]]; then
        return 1
    fi

    line="$(
        grep -E "^${key}=" "$file_path" 2>/dev/null |
            head -n 1 ||
            true
    )"

    if [[ -z "$line" ]]; then
        return 1
    fi

    value="${line#*=}"
    value="$(utils_strip_quotes "$value")"

    printf '%s\n' "$value"
}

utils_detect_os_id() {
    local os_id

    os_id="$(utils_os_release_value "ID" 2>/dev/null || true)"
    os_id="${os_id,,}"

    case "$os_id" in
        debian | ubuntu)
            printf '%s\n' "$os_id"
            ;;
        *)
            printf 'unknown\n'
            return 1
            ;;
    esac
}

utils_detect_os_version() {
    utils_os_release_value "VERSION_ID" 2>/dev/null ||
        printf 'desconhecida\n'
}

utils_detect_os_pretty_name() {
    utils_os_release_value "PRETTY_NAME" 2>/dev/null ||
        printf 'Linux desconhecido\n'
}

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------

utils_parse_config_line() {
    local line="${1:-}"
    local key_variable_name="${2:-}"
    local value_variable_name="${3:-}"
    local key
    local value

    if [[ -z "$key_variable_name" || -z "$value_variable_name" ]]; then
        return 2
    fi

    line="$(utils_trim "$line")"

    if [[ -z "$line" || "$line" == \#* ]]; then
        return 1
    fi

    if [[ "$line" != *=* ]]; then
        return 1
    fi

    key="${line%%=*}"
    value="${line#*=}"

    key="$(utils_trim "$key")"
    value="$(utils_trim "$value")"
    value="$(utils_strip_quotes "$value")"

    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        return 1
    fi

    printf -v "$key_variable_name" '%s' "$key"
    printf -v "$value_variable_name" '%s' "$value"

    return 0
}

utils_load_safe_config() {
    local file_path="${1:-}"
    local prefix="${2:-}"
    local line
    local key
    local value
    local target_variable

    if [[ ! -r "$file_path" ]]; then
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        key=""
        value=""

        if ! utils_parse_config_line \
            "$line" \
            key \
            value; then
            continue
        fi

        target_variable="${prefix}${key}"

        printf -v "$target_variable" '%s' "$value"
        export "$target_variable"
    done <"$file_path"
}

# ---------------------------------------------------------------------------
# Estados de saúde
# ---------------------------------------------------------------------------

utils_status_from_high_usage() {
    local value="${1:-0}"
    local warning_threshold="${2:-75}"
    local critical_threshold="${3:-90}"

    if ! utils_is_decimal "$value" ||
        ! utils_is_decimal "$warning_threshold" ||
        ! utils_is_decimal "$critical_threshold"; then
        printf '%s\n' "${HC_STATUS_UNKNOWN:-UNKNOWN}"
        return 1
    fi

    if utils_compare_numbers "$warning_threshold" ge "$critical_threshold"; then
        printf '%s\n' "${HC_STATUS_UNKNOWN:-UNKNOWN}"
        return 1
    fi

    if utils_compare_numbers "$value" ge "$critical_threshold"; then
        printf '%s\n' "${HC_STATUS_CRITICAL:-CRITICAL}"
    elif utils_compare_numbers "$value" ge "$warning_threshold"; then
        printf '%s\n' "${HC_STATUS_WARNING:-WARNING}"
    else
        printf '%s\n' "${HC_STATUS_OK:-OK}"
    fi
}

utils_status_from_low_remaining() {
    local value="${1:-0}"
    local warning_threshold="${2:-30}"
    local critical_threshold="${3:-15}"

    if ! utils_is_decimal "$value" ||
        ! utils_is_decimal "$warning_threshold" ||
        ! utils_is_decimal "$critical_threshold"; then
        printf '%s\n' "${HC_STATUS_UNKNOWN:-UNKNOWN}"
        return 1
    fi

    if utils_compare_numbers "$warning_threshold" le "$critical_threshold"; then
        printf '%s\n' "${HC_STATUS_UNKNOWN:-UNKNOWN}"
        return 1
    fi

    if utils_compare_numbers "$value" le "$critical_threshold"; then
        printf '%s\n' "${HC_STATUS_CRITICAL:-CRITICAL}"
    elif utils_compare_numbers "$value" le "$warning_threshold"; then
        printf '%s\n' "${HC_STATUS_WARNING:-WARNING}"
    else
        printf '%s\n' "${HC_STATUS_OK:-OK}"
    fi
}

utils_status_from_count() {
    local value="${1:-0}"
    local warning_threshold="${2:-1}"
    local critical_threshold="${3:-10}"

    utils_status_from_high_usage \
        "$value" \
        "$warning_threshold" \
        "$critical_threshold"
}

# ---------------------------------------------------------------------------
# Locks
# ---------------------------------------------------------------------------

utils_acquire_lock() {
    local lock_file="${1:-}"
    local file_descriptor_variable="${2:-}"
    local wait_seconds="${3:-0}"
    local file_descriptor

    if [[ -z "$lock_file" || -z "$file_descriptor_variable" ]]; then
        return 2
    fi

    if ! command -v flock >/dev/null 2>&1; then
        return 127
    fi

    utils_ensure_directory "$(dirname -- "$lock_file")"

    exec {file_descriptor}>"$lock_file"

    if ! flock -w "$wait_seconds" "$file_descriptor"; then
        eval "exec ${file_descriptor}>&-"
        return 1
    fi

    printf -v "$file_descriptor_variable" '%s' "$file_descriptor"
}

utils_release_lock() {
    local file_descriptor="${1:-}"

    if ! utils_is_unsigned_integer "$file_descriptor"; then
        return 1
    fi

    flock -u "$file_descriptor" 2>/dev/null || true
    eval "exec ${file_descriptor}>&-"
}

# ---------------------------------------------------------------------------
# Validação do módulo
# ---------------------------------------------------------------------------

utils_validate() {
    local failure=0
    local temporary_directory
    local temporary_file
    local parsed_key=""
    local parsed_value=""
    local -a input_array=("docker" "nginx" "docker" "ollama")
    local -a unique_array=()

    if [[ "$(utils_trim "  teste  ")" != "teste" ]]; then
        printf 'Falha em utils_trim.\n' >&2
        failure=1
    fi

    if [[ "$(utils_to_lower "TESTE")" != "teste" ]]; then
        printf 'Falha em utils_to_lower.\n' >&2
        failure=1
    fi

    if [[ "$(utils_to_upper "teste")" != "TESTE" ]]; then
        printf 'Falha em utils_to_upper.\n' >&2
        failure=1
    fi

    if ! utils_is_integer "-10"; then
        printf 'Falha em utils_is_integer.\n' >&2
        failure=1
    fi

    if utils_is_integer "10.5"; then
        printf 'Falha ao rejeitar decimal como inteiro.\n' >&2
        failure=1
    fi

    if ! utils_is_percentage "99.5"; then
        printf 'Falha em utils_is_percentage.\n' >&2
        failure=1
    fi

    if utils_is_percentage "101"; then
        printf 'Falha ao rejeitar percentual acima de 100.\n' >&2
        failure=1
    fi

    if ! utils_is_ipv4 "127.0.0.1"; then
        printf 'Falha em utils_is_ipv4.\n' >&2
        failure=1
    fi

    if utils_is_ipv4 "999.1.1.1"; then
        printf 'Falha ao rejeitar IPv4 inválido.\n' >&2
        failure=1
    fi

    if ! utils_is_port "443"; then
        printf 'Falha em utils_is_port.\n' >&2
        failure=1
    fi

    if utils_is_port "70000"; then
        printf 'Falha ao rejeitar porta inválida.\n' >&2
        failure=1
    fi

    if [[ "$(utils_bytes_to_human 1024 2)" != "1.00 KiB" ]]; then
        printf 'Falha em utils_bytes_to_human.\n' >&2
        failure=1
    fi

    if [[ "$(utils_seconds_to_duration 3661)" != "1h 1m 1s" ]]; then
        printf 'Falha em utils_seconds_to_duration.\n' >&2
        failure=1
    fi

    if [[ "$(utils_json_escape $'a"b\nc')" != 'a\"b\nc' ]]; then
        printf 'Falha em utils_json_escape.\n' >&2
        failure=1
    fi

    if [[ "$(utils_html_escape '<teste>')" != '&lt;teste&gt;' ]]; then
        printf 'Falha em utils_html_escape.\n' >&2
        failure=1
    fi

    if ! utils_parse_config_line \
        'TESTE="valor"' \
        parsed_key \
        parsed_value; then
        printf 'Falha em utils_parse_config_line.\n' >&2
        failure=1
    elif [[ "$parsed_key" != "TESTE" || "$parsed_value" != "valor" ]]; then
        printf 'Resultado incorreto em utils_parse_config_line.\n' >&2
        failure=1
    fi

    utils_array_unique input_array unique_array

    if ((${#unique_array[@]} != 3)); then
        printf 'Falha em utils_array_unique.\n' >&2
        failure=1
    fi

    temporary_directory="$(utils_create_temp_directory "utils-test")"
    temporary_file="${temporary_directory}/arquivo.txt"

    if ! printf 'teste\n' |
        utils_atomic_write "$temporary_file" "0640"; then
        printf 'Falha em utils_atomic_write.\n' >&2
        failure=1
    elif [[ "$(cat -- "$temporary_file")" != "teste" ]]; then
        printf 'Conteúdo incorreto em utils_atomic_write.\n' >&2
        failure=1
    fi

    rm -rf -- "$temporary_directory"

    if [[ "$(utils_status_from_high_usage 80 75 90)" != "${HC_STATUS_WARNING:-WARNING}" ]]; then
        printf 'Falha em utils_status_from_high_usage.\n' >&2
        failure=1
    fi

    if [[ "$(utils_status_from_low_remaining 10 30 15)" != "${HC_STATUS_CRITICAL:-CRITICAL}" ]]; then
        printf 'Falha em utils_status_from_low_remaining.\n' >&2
        failure=1
    fi

    return "$failure"
}

utils_initialize() {
    return 0
}

utils_initialize
