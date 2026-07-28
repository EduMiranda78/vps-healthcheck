#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

readonly SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR="/opt/vps-healthcheck"

readonly FILE_MODE="0640"
readonly DIR_MODE="0750"

log() {
    printf '[INFO] %s\n' "$*"
}

error() {
    printf '[ERROR] %s\n' "$*" >&2
}

require_root() {

    if [[ "${EUID}" -ne 0 ]]; then
        error "Este atualizador precisa ser executado como root."
        exit 1
    fi
}

validate_source() {

    if [[ ! -f "${SOURCE_DIR}/healthcheck.sh" ]]; then
        error "healthcheck.sh não encontrado na origem."
        exit 1
    fi

}

validate_installation() {

    if [[ ! -d "$INSTALL_DIR" ]]; then
        error "Instalação não encontrada em ${INSTALL_DIR}."
        exit 1
    fi

}

create_backup() {

    local backup

    backup="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"

    log "Criando backup: ${backup}"

    cp -a \
        "$INSTALL_DIR" \
        "$backup"

}

sync_files() {

    log "Atualizando arquivos."

    rsync \
        -a \
        --delete \
        --exclude "config/*" \
        --exclude "reports/*" \
        --exclude "logs/*" \
        "${SOURCE_DIR}/" \
        "${INSTALL_DIR}/"

}

apply_permissions() {

    find "$INSTALL_DIR" \
        -type f \
        -exec chmod "$FILE_MODE" {} \;

    find "$INSTALL_DIR" \
        -type d \
        -exec chmod "$DIR_MODE" {} \;

    chmod 0750 \
        "${INSTALL_DIR}/healthcheck.sh"

}

validate_update() {

    log "Executando self-test."

    if ! "${INSTALL_DIR}/healthcheck.sh" --self-test; then

        error "Falha após atualização."

        exit 1

    fi

}

cleanup_backups() {

    local count=0
    local backup

    while IFS= read -r backup; do

        [[ -z "$backup" ]] && continue

        count=$((count + 1))

        if ((count > 3)); then

            log "Removendo backup antigo: ${backup}"

            rm -rf "$backup"

        fi

    done < <(
        ls -1dt \
        "${INSTALL_DIR}.backup."* \
        2>/dev/null || true
    )

}

main() {

    require_root

    validate_source

    validate_installation

    create_backup

    sync_files

    apply_permissions

    validate_update

    cleanup_backups

    log "Atualização concluída."

}

main "$@"
