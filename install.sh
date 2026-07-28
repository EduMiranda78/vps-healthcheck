#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "$0")"
readonly SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly INSTALL_DIR="/opt/vps-healthcheck"
readonly BIN_PATH="/usr/local/bin/vps-healthcheck"

readonly DIRECTORY_MODE="0750"
readonly FILE_MODE="0640"

log() {
    printf '[INFO] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

error() {
    printf '[ERROR] %s\n' "$*" >&2
}

require_root() {

    if [[ "${EUID}" -ne 0 ]]; then
        error "Este instalador precisa ser executado como root."
        exit 1
    fi
}

check_source_structure() {

    local file

    local required_files=(
        "healthcheck.sh"
        "VERSION"
        "lib/constants.sh"
        "lib/collector.sh"
        "config/healthcheck.conf"
        "config/thresholds.conf"
    )

    for file in "${required_files[@]}"; do

        if [[ ! -e "${SOURCE_DIR}/${file}" ]]; then

            error \
                "Arquivo obrigatório ausente: ${file}"

            exit 1
        fi

    done
}

install_dependencies() {

    if ! command -v apt-get >/dev/null 2>&1; then

        warn \
            "apt-get não encontrado. Dependências ignoradas."

        return 0

    fi

    log "Verificando dependências."

    apt-get update -qq

    apt-get install -y \
        bash \
        coreutils \
        mawk \
        sed \
        grep \
        findutils \
        procps \
        iproute2 \
        util-linux \
        jq \
        curl \
        rsync
}

backup_existing_installation() {

    local backup

    if [[ ! -d "$INSTALL_DIR" ]]; then
        return 0
    fi

    backup="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"

    log "Criando backup: ${backup}"

    cp -a \
        "$INSTALL_DIR" \
        "$backup"
}

cleanup_old_backups() {

    local count=0
    local backup

    while IFS= read -r backup; do

        [[ -z "$backup" ]] && continue

        count=$((count + 1))

        if ((count > 3)); then

            log "Removendo backup antigo: ${backup}"

            rm -rf -- "$backup"

        fi

    done < <(
        ls -1dt \
        "${INSTALL_DIR}.backup."* \
        2>/dev/null || true
    )
}

create_directories() {

    mkdir -p \
        "$INSTALL_DIR"

    chmod \
        "$DIRECTORY_MODE" \
        "$INSTALL_DIR"
}

copy_project() {

    log "Copiando arquivos."

    rsync \
        -a \
        --exclude ".git" \
        --exclude "reports/*" \
        --exclude "logs/*" \
        "${SOURCE_DIR}/" \
        "${INSTALL_DIR}/"
}

create_runtime_directories() {

    mkdir -p \
        "${INSTALL_DIR}/reports" \
        "${INSTALL_DIR}/logs"

    chmod \
        "$DIRECTORY_MODE" \
        "${INSTALL_DIR}/reports" \
        "${INSTALL_DIR}/logs"
}

apply_permissions() {

    find "$INSTALL_DIR" \
        -type f \
        -exec chmod "$FILE_MODE" {} \;

    find "$INSTALL_DIR" \
        -type d \
        -exec chmod "$DIRECTORY_MODE" {} \;

    chmod 0750 \
        "${INSTALL_DIR}/healthcheck.sh"
}

create_symlink() {

    log "Criando comando global."

    ln -sfn \
        "${INSTALL_DIR}/healthcheck.sh" \
        "${BIN_PATH}"
}

run_validation() {

    log "Executando self-test."

    if ! "${INSTALL_DIR}/healthcheck.sh" --self-test; then

        error \
            "Falha no self-test após instalação."

        exit 1

    fi
}

print_summary() {

    printf '\n'
    printf '========================================\n'
    printf ' vps-healthcheck instalado\n'
    printf '========================================\n'
    printf '\n'

    printf 'Diretório: %s\n' \
        "$INSTALL_DIR"

    printf 'Comando:   %s\n' \
        "$BIN_PATH"

    printf 'Versão:    %s\n' \
        "$(cat "${INSTALL_DIR}/VERSION")"

    printf '\n'
}

main() {

    require_root

    check_source_structure

    install_dependencies

    backup_existing_installation

    cleanup_old_backups

    create_directories

    copy_project

    create_runtime_directories

    apply_permissions

    create_symlink

    run_validation

    print_summary
}

main "$@"
