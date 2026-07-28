#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

readonly INSTALL_DIR="/opt/vps-healthcheck"
readonly BIN_PATH="/usr/local/bin/vps-healthcheck"

log() {
    printf '[INFO] %s\n' "$*"
}

error() {
    printf '[ERROR] %s\n' "$*" >&2
}

require_root() {

    if [[ "${EUID}" -ne 0 ]]; then
        error "Este desinstalador precisa ser executado como root."
        exit 1
    fi
}

confirm_remove() {

    local answer

    printf '\n'
    printf 'Será removido:\n'
    printf '  %s\n' "$INSTALL_DIR"
    printf '  %s\n' "$BIN_PATH"
    printf '\n'

    read -r -p "Continuar? [s/N] " answer

    case "$answer" in
        s|S|sim|SIM)
            return 0
            ;;
        *)
            printf "Cancelado.\n"
            exit 0
            ;;
    esac
}

remove_symlink() {

    if [[ -L "$BIN_PATH" ]]; then

        log "Removendo comando global."

        rm -f "$BIN_PATH"

    fi
}

remove_installation() {

    if [[ -d "$INSTALL_DIR" ]]; then

        log "Removendo instalação."

        rm -rf "$INSTALL_DIR"

    else

        log "Instalação não encontrada."

    fi
}

main() {

    require_root

    confirm_remove

    remove_symlink

    remove_installation

    printf '\n'
    printf 'vps-healthcheck removido.\n'
}

main "$@"
