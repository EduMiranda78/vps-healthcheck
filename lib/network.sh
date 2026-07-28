#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [[ -n "${VPS_HEALTHCHECK_NETWORK_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

readonly VPS_HEALTHCHECK_NETWORK_LOADED=1

# ---------------------------------------------------------------------------
# Configuração
# ---------------------------------------------------------------------------

network_config_enabled() {
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

network_config_get() {
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
# Interfaces
# ---------------------------------------------------------------------------

network_interface_operstate() {
    local interface="${1:-}"
    local state_file="/sys/class/net/${interface}/operstate"

    if [[ -r "$state_file" ]]; then
        cat "$state_file"
    else
        printf 'unknown\n'
    fi
}

network_interface_mac() {
    local interface="${1:-}"
    local address_file="/sys/class/net/${interface}/address"

    if [[ -r "$address_file" ]]; then
        cat "$address_file"
    else
        printf 'unknown\n'
    fi
}

network_interface_mtu() {
    local interface="${1:-}"
    local mtu_file="/sys/class/net/${interface}/mtu"

    if [[ -r "$mtu_file" ]]; then
        cat "$mtu_file"
    else
        printf '0\n'
    fi
}

network_interface_stat() {
    local interface="${1:-}"
    local stat_name="${2:-}"
    local stat_file="/sys/class/net/${interface}/statistics/${stat_name}"

    if [[ -r "$stat_file" ]]; then
        cat "$stat_file"
    else
        printf '0\n'
    fi
}

network_interface_status() {
    local interface="${1:-}"
    local operstate="${2:-unknown}"
    local rx_errors="${3:-0}"
    local tx_errors="${4:-0}"
    local rx_dropped="${5:-0}"
    local tx_dropped="${6:-0}"

    local error_warning
    local error_critical
    local drop_warning
    local drop_critical
    local error_total
    local drop_total
    local error_status
    local drop_status
    local status="${HC_STATUS_OK:-OK}"

    if [[ "$interface" != "lo" && "$operstate" != "up" ]]; then
        status="${HC_STATUS_WARNING:-WARNING}"
    fi

    error_warning="$(
        network_config_get \
            "HC_NETWORK_INTERFACE_ERROR_WARNING_COUNT" \
            "1"
    )"

    error_critical="$(
        network_config_get \
            "HC_NETWORK_INTERFACE_ERROR_CRITICAL_COUNT" \
            "100"
    )"

    drop_warning="$(
        network_config_get \
            "HC_NETWORK_INTERFACE_DROP_WARNING_COUNT" \
            "1"
    )"

    drop_critical="$(
        network_config_get \
            "HC_NETWORK_INTERFACE_DROP_CRITICAL_COUNT" \
            "100"
    )"

    error_total=$((rx_errors + tx_errors))
    drop_total=$((rx_dropped + tx_dropped))

    error_status="$(
        utils_status_from_high_usage \
            "$error_total" \
            "$error_warning" \
            "$error_critical"
    )"

    drop_status="$(
        utils_status_from_high_usage \
            "$drop_total" \
            "$drop_warning" \
            "$drop_critical"
    )"

    status="$(
        collector_worst_status \
            "$status" \
            "$error_status"
    )"

    status="$(
        collector_worst_status \
            "$status" \
            "$drop_status"
    )"

    printf '%s\n' "$status"
}

network_collect_interfaces() {
    local interface
    local operstate
    local mac
    local mtu
    local rx_bytes
    local tx_bytes
    local rx_packets
    local tx_packets
    local rx_errors
    local tx_errors
    local rx_dropped
    local tx_dropped
    local status
    local interface_count=0
    local up_count=0

    collector_table_create \
        "network" \
        "interfaces" \
        "overview" \
        "Interfaces de rede" \
        $'Interface\tEstado\tMAC\tMTU\tRecebido\tEnviado\tRX pacotes\tTX pacotes\tRX erros\tTX erros\tRX descartados\tTX descartados\tStatus' \
        "Interfaces de rede e contadores do kernel." \
        "${HC_STATUS_OK:-OK}"

    for interface_path in /sys/class/net/*; do
        [[ -e "$interface_path" ]] || continue

        interface="${interface_path##*/}"
        operstate="$(network_interface_operstate "$interface")"
        mac="$(network_interface_mac "$interface")"
        mtu="$(network_interface_mtu "$interface")"

        rx_bytes="$(network_interface_stat "$interface" rx_bytes)"
        tx_bytes="$(network_interface_stat "$interface" tx_bytes)"
        rx_packets="$(network_interface_stat "$interface" rx_packets)"
        tx_packets="$(network_interface_stat "$interface" tx_packets)"
        rx_errors="$(network_interface_stat "$interface" rx_errors)"
        tx_errors="$(network_interface_stat "$interface" tx_errors)"
        rx_dropped="$(network_interface_stat "$interface" rx_dropped)"
        tx_dropped="$(network_interface_stat "$interface" tx_dropped)"

        status="$(
            network_interface_status \
                "$interface" \
                "$operstate" \
                "$rx_errors" \
                "$tx_errors" \
                "$rx_dropped" \
                "$tx_dropped"
        )"

        interface_count=$((interface_count + 1))

        if [[ "$operstate" == "up" ]]; then
            up_count=$((up_count + 1))
        fi

        collector_table_add_row \
            "network" \
            "interfaces" \
            "overview" \
            "$interface" \
            "$operstate" \
            "$mac" \
            "$mtu" \
            "$(utils_bytes_to_human "$rx_bytes" 2)" \
            "$(utils_bytes_to_human "$tx_bytes" 2)" \
            "$rx_packets" \
            "$tx_packets" \
            "$rx_errors" \
            "$tx_errors" \
            "$rx_dropped" \
            "$tx_dropped" \
            "$status"

        if [[ "$status" != "${HC_STATUS_OK:-OK}" ]]; then
            collector_alert_add \
                "network" \
                "$status" \
                "Problema em interface de rede" \
                "A interface ${interface} está com estado ${operstate}, ${rx_errors} erros RX, ${tx_errors} erros TX, ${rx_dropped} descartes RX e ${tx_dropped} descartes TX." \
                "Verifique link, driver, MTU, saturação e configuração da interface."
        fi
    done

    collector_metric_set \
        "network" \
        "interfaces" \
        "total_count" \
        "Interfaces detectadas" \
        "$interface_count" \
        "$interface_count" \
        "integer" \
        "interfaces" \
        "${HC_STATUS_OK:-OK}" \
        "Quantidade total de interfaces de rede." \
        "/sys/class/net"

    collector_metric_set \
        "network" \
        "interfaces" \
        "up_count" \
        "Interfaces ativas" \
        "$up_count" \
        "$up_count" \
        "integer" \
        "interfaces" \
        "${HC_STATUS_OK:-OK}" \
        "Quantidade de interfaces com estado up." \
        "/sys/class/net"
}

# ---------------------------------------------------------------------------
# Endereços IP
# ---------------------------------------------------------------------------

network_collect_addresses() {
    local family
    local interface
    local address
    local scope
    local prefix

    collector_table_create \
        "network" \
        "addresses" \
        "ip_addresses" \
        "Endereços IP" \
        $'Família\tInterface\tEndereço\tPrefixo\tEscopo' \
        "Endereços IPv4 e IPv6 configurados." \
        "${HC_STATUS_OK:-OK}"

    if ! command -v ip >/dev/null 2>&1; then
        collector_table_set_status \
            "network" \
            "addresses" \
            "ip_addresses" \
            "${HC_STATUS_UNKNOWN:-UNKNOWN}"

        return 0
    fi

    while IFS=$'\t' read -r \
        family \
        interface \
        address \
        prefix \
        scope; do

        [[ -n "$interface" ]] || continue

        collector_table_add_row \
            "network" \
            "addresses" \
            "ip_addresses" \
            "$family" \
            "$interface" \
            "$address" \
            "$prefix" \
            "$scope"
    done < <(
        ip -o addr show 2>/dev/null |
        awk '
            {
                family = $3
                interface = $2
                split($4, address_parts, "/")
                address = address_parts[1]
                prefix = address_parts[2]
                scope = ""

                for (i = 5; i <= NF; i++) {
                    if ($i == "scope" && i + 1 <= NF) {
                        scope = $(i + 1)
                        break
                    }
                }

                printf "%s\t%s\t%s\t%s\t%s\n",
                    family,
                    interface,
                    address,
                    prefix,
                    scope
            }
        '
    )
}

# ---------------------------------------------------------------------------
# Gateway e rotas
# ---------------------------------------------------------------------------

network_collect_gateway() {
    local gateway=""
    local interface=""
    local status="${HC_STATUS_OK:-OK}"
    local required

    required="$(network_config_get HC_NETWORK_GATEWAY_REQUIRED 1)"

    if command -v ip >/dev/null 2>&1; then
        read -r gateway interface < <(
            ip route show default 2>/dev/null |
            awk '
                $1 == "default" {
                    gateway = ""
                    interface = ""

                    for (i = 1; i <= NF; i++) {
                        if ($i == "via" && i + 1 <= NF) {
                            gateway = $(i + 1)
                        }

                        if ($i == "dev" && i + 1 <= NF) {
                            interface = $(i + 1)
                        }
                    }

                    print gateway, interface
                    exit
                }
            '
        )
    fi

    if [[ -z "$gateway" ]]; then
        if [[ "$required" == "1" ]]; then
            status="${HC_STATUS_CRITICAL:-CRITICAL}"
        else
            status="${HC_STATUS_UNKNOWN:-UNKNOWN}"
        fi
    fi

    collector_metric_set \
        "network" \
        "routing" \
        "default_gateway" \
        "Gateway padrão" \
        "${gateway:-Não encontrado}" \
        "$gateway" \
        "ip_address" \
        "" \
        "$status" \
        "Gateway padrão da tabela de rotas principal." \
        "ip route"

    collector_metric_set \
        "network" \
        "routing" \
        "default_interface" \
        "Interface do gateway" \
        "${interface:-Não encontrada}" \
        "$interface" \
        "string" \
        "" \
        "$status" \
        "Interface utilizada pela rota padrão." \
        "ip route"

    if [[ "$status" == "${HC_STATUS_CRITICAL:-CRITICAL}" ]]; then
        collector_alert_add \
            "network" \
            "$status" \
            "Gateway padrão ausente" \
            "Nenhuma rota padrão foi encontrada." \
            "Verifique a configuração de rede e a tabela de rotas."
    fi
}

network_collect_routes() {
    local route_type
    local destination
    local gateway
    local interface
    local source
    local metric

    collector_table_create \
        "network" \
        "routing" \
        "routes" \
        "Rotas de rede" \
        $'Tipo\tDestino\tGateway\tInterface\tOrigem\tMétrica' \
        "Tabela principal de rotas IPv4." \
        "${HC_STATUS_OK:-OK}"

    if ! command -v ip >/dev/null 2>&1; then
        collector_table_set_status \
            "network" \
            "routing" \
            "routes" \
            "${HC_STATUS_UNKNOWN:-UNKNOWN}"

        return 0
    fi

    while IFS=$'\t' read -r \
        route_type \
        destination \
        gateway \
        interface \
        source \
        metric; do

        [[ -n "$destination" ]] || continue

        collector_table_add_row \
            "network" \
            "routing" \
            "routes" \
            "$route_type" \
            "$destination" \
            "$gateway" \
            "$interface" \
            "$source" \
            "$metric"
    done < <(
        ip route show table main 2>/dev/null |
        awk '
            {
                route_type = "unicast"
                destination = $1
                gateway = ""
                interface = ""
                source = ""
                metric = ""

                if ($1 == "default") {
                    route_type = "default"
                } else if ($1 == "blackhole" || $1 == "unreachable" || $1 == "prohibit") {
                    route_type = $1
                    destination = $2
                }

                for (i = 1; i <= NF; i++) {
                    if ($i == "via" && i + 1 <= NF) {
                        gateway = $(i + 1)
                    }

                    if ($i == "dev" && i + 1 <= NF) {
                        interface = $(i + 1)
                    }

                    if ($i == "src" && i + 1 <= NF) {
                        source = $(i + 1)
                    }

                    if ($i == "metric" && i + 1 <= NF) {
                        metric = $(i + 1)
                    }
                }

                printf "%s\t%s\t%s\t%s\t%s\t%s\n",
                    route_type,
                    destination,
                    gateway,
                    interface,
                    source,
                    metric
            }
        '
    )
}

# ---------------------------------------------------------------------------
# DNS
# ---------------------------------------------------------------------------

network_collect_dns() {
    local nameserver
    local search_domains=""
    local dns_count=0
    local required
    local status="${HC_STATUS_OK:-OK}"

    required="$(network_config_get HC_NETWORK_DNS_REQUIRED 1)"

    collector_table_create \
        "network" \
        "dns" \
        "servers" \
        "Servidores DNS" \
        $'Servidor' \
        "Servidores DNS configurados no resolvedor local." \
        "${HC_STATUS_OK:-OK}"

    if [[ -r /etc/resolv.conf ]]; then
        while IFS=' ' read -r directive value _; do
            case "$directive" in
                nameserver)
                    [[ -n "$value" ]] || continue

                    dns_count=$((dns_count + 1))

                    collector_table_add_row \
                        "network" \
                        "dns" \
                        "servers" \
                        "$value"
                    ;;
                search | domain)
                    if [[ -z "$search_domains" ]]; then
                        search_domains="$value"
                    else
                        search_domains="${search_domains},${value}"
                    fi
                    ;;
            esac
        done </etc/resolv.conf
    fi

    if ((dns_count == 0)); then
        if [[ "$required" == "1" ]]; then
            status="${HC_STATUS_CRITICAL:-CRITICAL}"
        else
            status="${HC_STATUS_UNKNOWN:-UNKNOWN}"
        fi

        collector_table_set_status \
            "network" \
            "dns" \
            "servers" \
            "$status"
    fi

    collector_metric_set \
        "network" \
        "dns" \
        "server_count" \
        "Servidores DNS configurados" \
        "$dns_count" \
        "$dns_count" \
        "integer" \
        "servers" \
        "$status" \
        "Quantidade de servidores DNS encontrados." \
        "/etc/resolv.conf"

    collector_metric_set \
        "network" \
        "dns" \
        "search_domains" \
        "Domínios de pesquisa" \
        "${search_domains:-Nenhum}" \
        "$search_domains" \
        "string" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Domínios de pesquisa configurados." \
        "/etc/resolv.conf"

    if [[ "$status" == "${HC_STATUS_CRITICAL:-CRITICAL}" ]]; then
        collector_alert_add \
            "network" \
            "$status" \
            "DNS não configurado" \
            "Nenhum servidor DNS foi encontrado em /etc/resolv.conf." \
            "Configure um resolvedor DNS válido."
    fi
}

# ---------------------------------------------------------------------------
# Portas em escuta
# ---------------------------------------------------------------------------

network_collect_listening_ports() {
    local protocol
    local state
    local local_address
    local process
    local port_count=0
    local warning
    local critical
    local status

    warning="$(
        network_config_get \
            "HC_NETWORK_LISTENING_PORT_WARNING_COUNT" \
            "50"
    )"

    critical="$(
        network_config_get \
            "HC_NETWORK_LISTENING_PORT_CRITICAL_COUNT" \
            "100"
    )"

    collector_table_create \
        "network" \
        "ports" \
        "listening" \
        "Portas em escuta" \
        $'Protocolo\tEstado\tEndereço local\tProcesso' \
        "Sockets TCP e UDP em escuta." \
        "${HC_STATUS_OK:-OK}"

    if ! command -v ss >/dev/null 2>&1; then
        collector_table_set_status \
            "network" \
            "ports" \
            "listening" \
            "${HC_STATUS_UNKNOWN:-UNKNOWN}"

        return 0
    fi

    while IFS=$'\t' read -r \
        protocol \
        state \
        local_address \
        process; do

        [[ -n "$protocol" ]] || continue

        port_count=$((port_count + 1))

        collector_table_add_row \
            "network" \
            "ports" \
            "listening" \
            "$protocol" \
            "$state" \
            "$local_address" \
            "$process"
    done < <(
        ss -H -lntup 2>/dev/null |
        awk '
            {
                protocol = $1
                state = $2
                local_address = $5
                process = ""

                for (i = 7; i <= NF; i++) {
                    if (process == "") {
                        process = $i
                    } else {
                        process = process " " $i
                    }
                }

                printf "%s\t%s\t%s\t%s\n",
                    protocol,
                    state,
                    local_address,
                    process
            }
        '
    )

    status="$(
        utils_status_from_high_usage \
            "$port_count" \
            "$warning" \
            "$critical"
    )"

    collector_metric_set \
        "network" \
        "ports" \
        "listening_count" \
        "Portas em escuta" \
        "$port_count" \
        "$port_count" \
        "integer" \
        "sockets" \
        "$status" \
        "Quantidade de sockets em escuta." \
        "ss"

    collector_table_set_status \
        "network" \
        "ports" \
        "listening" \
        "$status"

    if [[ "$status" != "${HC_STATUS_OK:-OK}" ]]; then
        collector_alert_add \
            "network" \
            "$status" \
            "Grande quantidade de portas em escuta" \
            "Foram encontrados ${port_count} sockets em escuta." \
            "Revise serviços expostos e portas desnecessárias."
    fi
}

# ---------------------------------------------------------------------------
# Conexões
# ---------------------------------------------------------------------------

network_collect_connections() {
    local established=0
    local time_wait=0
    local syn_recv=0
    local close_wait=0
    local total=0

    local established_warning
    local established_critical
    local time_wait_warning
    local time_wait_critical
    local syn_recv_warning
    local syn_recv_critical

    local established_status
    local time_wait_status
    local syn_recv_status
    local overall_status

    if command -v ss >/dev/null 2>&1; then
        established="$(
            ss -H -tan state established 2>/dev/null |
            awk 'END { print NR + 0 }'
        )"

        time_wait="$(
            ss -H -tan state time-wait 2>/dev/null |
            awk 'END { print NR + 0 }'
        )"

        syn_recv="$(
            ss -H -tan state syn-recv 2>/dev/null |
            awk 'END { print NR + 0 }'
        )"

        close_wait="$(
            ss -H -tan state close-wait 2>/dev/null |
            awk 'END { print NR + 0 }'
        )"

        total="$(
            ss -H -tan 2>/dev/null |
            awk 'END { print NR + 0 }'
        )"
    fi

    established_warning="$(
        network_config_get \
            "HC_NETWORK_ESTABLISHED_CONNECTION_WARNING_COUNT" \
            "500"
    )"

    established_critical="$(
        network_config_get \
            "HC_NETWORK_ESTABLISHED_CONNECTION_CRITICAL_COUNT" \
            "2000"
    )"

    time_wait_warning="$(
        network_config_get \
            "HC_NETWORK_TIME_WAIT_WARNING_COUNT" \
            "1000"
    )"

    time_wait_critical="$(
        network_config_get \
            "HC_NETWORK_TIME_WAIT_CRITICAL_COUNT" \
            "5000"
    )"

    syn_recv_warning="$(
        network_config_get \
            "HC_NETWORK_SYN_RECV_WARNING_COUNT" \
            "100"
    )"

    syn_recv_critical="$(
        network_config_get \
            "HC_NETWORK_SYN_RECV_CRITICAL_COUNT" \
            "1000"
    )"

    established_status="$(
        utils_status_from_high_usage \
            "$established" \
            "$established_warning" \
            "$established_critical"
    )"

    time_wait_status="$(
        utils_status_from_high_usage \
            "$time_wait" \
            "$time_wait_warning" \
            "$time_wait_critical"
    )"

    syn_recv_status="$(
        utils_status_from_high_usage \
            "$syn_recv" \
            "$syn_recv_warning" \
            "$syn_recv_critical"
    )"

    overall_status="$(
        collector_worst_status \
            "$established_status" \
            "$time_wait_status"
    )"

    overall_status="$(
        collector_worst_status \
            "$overall_status" \
            "$syn_recv_status"
    )"

    collector_metric_set \
        "network" \
        "connections" \
        "total" \
        "Conexões TCP totais" \
        "$total" \
        "$total" \
        "integer" \
        "connections" \
        "$overall_status" \
        "Quantidade total de sockets TCP." \
        "ss"

    collector_metric_set \
        "network" \
        "connections" \
        "established" \
        "Conexões estabelecidas" \
        "$established" \
        "$established" \
        "integer" \
        "connections" \
        "$established_status" \
        "Conexões TCP no estado ESTABLISHED." \
        "ss"

    collector_metric_set \
        "network" \
        "connections" \
        "time_wait" \
        "Conexões TIME_WAIT" \
        "$time_wait" \
        "$time_wait" \
        "integer" \
        "connections" \
        "$time_wait_status" \
        "Conexões TCP no estado TIME_WAIT." \
        "ss"

    collector_metric_set \
        "network" \
        "connections" \
        "syn_recv" \
        "Conexões SYN_RECV" \
        "$syn_recv" \
        "$syn_recv" \
        "integer" \
        "connections" \
        "$syn_recv_status" \
        "Conexões aguardando conclusão do handshake TCP." \
        "ss"

    collector_metric_set \
        "network" \
        "connections" \
        "close_wait" \
        "Conexões CLOSE_WAIT" \
        "$close_wait" \
        "$close_wait" \
        "integer" \
        "connections" \
        "${HC_STATUS_OK:-OK}" \
        "Conexões TCP no estado CLOSE_WAIT." \
        "ss"

    if [[ "$established_status" != "${HC_STATUS_OK:-OK}" ]]; then
        collector_alert_add \
            "network" \
            "$established_status" \
            "Muitas conexões estabelecidas" \
            "Existem ${established} conexões TCP estabelecidas." \
            "Verifique tráfego, serviços e limites de conexão."
    fi

    if [[ "$time_wait_status" != "${HC_STATUS_OK:-OK}" ]]; then
        collector_alert_add \
            "network" \
            "$time_wait_status" \
            "Muitas conexões TIME_WAIT" \
            "Existem ${time_wait} conexões no estado TIME_WAIT." \
            "Revise keep-alive, pools de conexão e taxa de novas conexões."
    fi

    if [[ "$syn_recv_status" != "${HC_STATUS_OK:-OK}" ]]; then
        collector_alert_add \
            "network" \
            "$syn_recv_status" \
            "Muitas conexões SYN_RECV" \
            "Existem ${syn_recv} conexões aguardando handshake." \
            "Verifique ataques SYN flood, backlog e firewall."
    fi
}

# ---------------------------------------------------------------------------
# IP público
# ---------------------------------------------------------------------------

network_collect_public_ip() {
    local services_raw
    local service
    local public_ip=""
    local status="${HC_STATUS_WARNING:-WARNING}"
    local -a services=()

    services_raw="$(
        network_config_get \
            "HC_NETWORK_PUBLIC_IP_SERVICES" \
            "https://api.ipify.org,https://ifconfig.me/ip"
    )"

    IFS=',' read -r -a services <<<"$services_raw"

    if command -v curl >/dev/null 2>&1; then
        for service in "${services[@]}"; do
            public_ip="$(
                curl \
                    --silent \
                    --show-error \
                    --fail \
                    --connect-timeout \
                    "$(network_config_get HC_HTTP_CONNECT_TIMEOUT_SECONDS 5)" \
                    --max-time \
                    "$(network_config_get HC_HTTP_TOTAL_TIMEOUT_SECONDS 10)" \
                    "$service" 2>/dev/null ||
                true
            )"

            public_ip="$(utils_trim "$public_ip")"

            if utils_is_ipv4 "$public_ip" ||
                utils_is_ipv6 "$public_ip"; then

                status="${HC_STATUS_OK:-OK}"
                break
            fi

            public_ip=""
        done
    fi

    collector_metric_set \
        "network" \
        "public" \
        "ip_address" \
        "IP público" \
        "${public_ip:-Não disponível}" \
        "$public_ip" \
        "ip_address" \
        "" \
        "$status" \
        "Endereço IP público obtido por serviço externo." \
        "curl"

    if [[ -z "$public_ip" ]]; then
        collector_alert_add \
            "network" \
            "$status" \
            "IP público não identificado" \
            "Não foi possível consultar o endereço IP público." \
            "Verifique conectividade externa, DNS e acesso HTTPS."
    fi
}

# ---------------------------------------------------------------------------
# Tailscale
# ---------------------------------------------------------------------------

network_collect_tailscale() {
    local installed="false"
    local service_active="false"
    local backend_state=""
    local ipv4=""
    local ipv6=""
    local status="${HC_STATUS_SKIPPED:-SKIPPED}"

    if ! command -v tailscale >/dev/null 2>&1; then
        collector_metric_set \
            "network" \
            "tailscale" \
            "installed" \
            "Tailscale instalado" \
            "Não" \
            "false" \
            "boolean" \
            "" \
            "$status" \
            "O comando tailscale não está instalado." \
            "tailscale"

        return 0
    fi

    installed="true"
    status="${HC_STATUS_OK:-OK}"

    if command -v systemctl >/dev/null 2>&1 &&
        systemctl is-active --quiet tailscaled 2>/dev/null; then

        service_active="true"
    else
        status="$(
            network_config_get \
                "HC_TAILSCALE_SERVICE_INACTIVE_STATUS" \
                "WARNING"
        )"
    fi

    backend_state="$(
        tailscale status --json 2>/dev/null |
        awk '
            match($0, /"BackendState"[[:space:]]*:[[:space:]]*"[^"]+"/) {
                value = substr($0, RSTART, RLENGTH)
                sub(/^.*:[[:space:]]*"/, "", value)
                sub(/"$/, "", value)
                print value
                exit
            }
        '
    )"

    ipv4="$(
        tailscale ip -4 2>/dev/null |
        head -n 1 ||
        true
    )"

    ipv6="$(
        tailscale ip -6 2>/dev/null |
        head -n 1 ||
        true
    )"

    if [[ -n "$backend_state" && "$backend_state" != "Running" ]]; then
        status="$(
            network_config_get \
                "HC_TAILSCALE_BACKEND_NOT_RUNNING_STATUS" \
                "WARNING"
        )"
    fi

    collector_metric_set \
        "network" \
        "tailscale" \
        "installed" \
        "Tailscale instalado" \
        "Sim" \
        "$installed" \
        "boolean" \
        "" \
        "${HC_STATUS_OK:-OK}" \
        "Indica se o cliente Tailscale está instalado." \
        "tailscale"

    collector_metric_set \
        "network" \
        "tailscale" \
        "service_active" \
        "Serviço Tailscale ativo" \
        "$([[ "$service_active" == "true" ]] && printf 'Sim' || printf 'Não')" \
        "$service_active" \
        "boolean" \
        "" \
        "$status" \
        "Estado do serviço tailscaled." \
        "systemctl"

    collector_metric_set \
        "network" \
        "tailscale" \
        "backend_state" \
        "Estado do backend Tailscale" \
        "${backend_state:-Desconhecido}" \
        "$backend_state" \
        "string" \
        "" \
        "$status" \
        "Estado interno informado pelo cliente Tailscale." \
        "tailscale status"

    collector_metric_set \
        "network" \
        "tailscale" \
        "ipv4" \
        "IPv4 Tailscale" \
        "${ipv4:-Não disponível}" \
        "$ipv4" \
        "ip_address" \
        "" \
        "$status" \
        "Endereço IPv4 atribuído pelo Tailscale." \
        "tailscale ip -4"

    collector_metric_set \
        "network" \
        "tailscale" \
        "ipv6" \
        "IPv6 Tailscale" \
        "${ipv6:-Não disponível}" \
        "$ipv6" \
        "ip_address" \
        "" \
        "$status" \
        "Endereço IPv6 atribuído pelo Tailscale." \
        "tailscale ip -6"

    if [[ "$status" != "${HC_STATUS_OK:-OK}" ]]; then
        collector_alert_add \
            "network" \
            "$status" \
            "Tailscale não operacional" \
            "O Tailscale está instalado, mas o serviço ou backend não está em estado operacional." \
            "Verifique tailscaled, autenticação e conectividade com a rede Tailscale."
    fi
}

# ---------------------------------------------------------------------------
# Execução
# ---------------------------------------------------------------------------

network_run() {
    if network_config_enabled "HC_NETWORK_INCLUDE_INTERFACES" 1; then
        network_collect_interfaces
    fi

    if network_config_enabled "HC_NETWORK_INCLUDE_IPV4" 1 ||
        network_config_enabled "HC_NETWORK_INCLUDE_IPV6" 1; then

        network_collect_addresses
    fi

    if network_config_enabled "HC_NETWORK_INCLUDE_GATEWAY" 1; then
        network_collect_gateway
    fi

    if network_config_enabled "HC_NETWORK_INCLUDE_ROUTES" 1; then
        network_collect_routes
    fi

    if network_config_enabled "HC_NETWORK_INCLUDE_DNS" 1; then
        network_collect_dns
    fi

    if network_config_enabled "HC_NETWORK_INCLUDE_LISTENING_PORTS" 1; then
        network_collect_listening_ports
    fi

    if network_config_enabled "HC_NETWORK_INCLUDE_CONNECTIONS" 1; then
        network_collect_connections
    fi

    if network_config_enabled "HC_NETWORK_INCLUDE_PUBLIC_IP" 1; then
        network_collect_public_ip
    fi

    if network_config_enabled "HC_NETWORK_INCLUDE_TAILSCALE" 1; then
        network_collect_tailscale
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Validação interna
# ---------------------------------------------------------------------------

network_validate() {
    local failure=0
    local interface_count=""
    local metric_count=0
    local table_count=0

    if ! declare -F collector_initialize >/dev/null 2>&1; then
        printf 'collector_initialize não está disponível.\n' >&2
        return 1
    fi

    collector_initialize
    collector_module_start "network" "Rede"

    if ! network_run; then
        printf 'network_run retornou falha.\n' >&2
        failure=1
    fi

    interface_count="$(
        collector_metric_get \
            "network" \
            "interfaces" \
            "total_count" \
            "raw_value" 2>/dev/null ||
        true
    )"

    metric_count="$(collector_metric_count network)"
    table_count="$(collector_table_count network)"

    if [[ ! "$interface_count" =~ ^[0-9]+$ ]] ||
        ((interface_count < 1)); then

        printf \
            'Quantidade inválida de interfaces: %s\n' \
            "$interface_count" >&2

        failure=1
    fi

    if [[ ! "$metric_count" =~ ^[0-9]+$ ]] ||
        ((metric_count < 8)); then

        printf \
            'Quantidade insuficiente de métricas de rede: %s\n' \
            "$metric_count" >&2

        failure=1
    fi

    if [[ ! "$table_count" =~ ^[0-9]+$ ]] ||
        ((table_count < 4)); then

        printf \
            'Quantidade insuficiente de tabelas de rede: %s\n' \
            "$table_count" >&2

        failure=1
    fi

    collector_module_finish \
        "network" \
        "$(collector_module_get_status network)" \
        "Validação concluída."

    collector_finalize

    return "$failure"
}
