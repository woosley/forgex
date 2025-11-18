#!/bin/bash
#
# Script: forge.sh
#
# This script manages backing up and restoring MacOS configuration for various tools.
# It reads a configuration file to determine which components to manage.
#
# Disclaimer: This script is provided as-is, with no warranties of any kind.
# Last-modified: 2025-11-17
# OS: MacOS
# Variable names are uppercased if the variable is read-only or if it is an external variable.

set -o errexit  # abort on nonzero exitstatus
set -o nounset  # abort on unbound variable
set -o pipefail # don't hide errors within pipes

# Global variables
declare CONFIG_FILE=".forge.conf"
declare BACKUP_FOLDER=""
declare -a ENABLED_MODULES=()

#
# Function: usage
#
# Description: Displays the usage information for the script.
# Input: None
# Output: Usage message to stdout.
#
function usage() {
    echo "Usage: $0 <backup|restore> [-f|--config <config_file>] [-h|--help]"
    echo ""
    echo "Arguments:"
    echo "  backup                Backup the configuration."
    echo "  restore               Restore the configuration."
    echo ""
    echo "Options:"
    echo "  -f, --config <file>   Specify a configuration file. Defaults to .forge.conf."
    echo "  -h, --help            Display this help message."
}

#
# Function: parse_args
#
# Description: Parses the command-line arguments.
# Input: Command-line arguments.
# Output: Sets global variables based on the arguments.
#
function parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            backup|restore)
                ACTION="$1"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    if [[ -z "${ACTION:-}" ]]; then
        echo "Error: Missing action (backup or restore)."
        usage
        exit 1
    fi
}

#
# Function: read_config
#
# Description: Reads the configuration file.
# Input: None
# Output: Sets global variables based on the config file.
#
function read_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "Error: Configuration file not found: ${CONFIG_FILE}"
        exit 1
    fi

    local parsing_enabled=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^BackupFolder:* ]]; then
            BACKUP_FOLDER=$(echo "$line" | cut -d' ' -f2-)
            parsing_enabled=false
        elif [[ "$line" == "Enabled" ]]; then
            parsing_enabled=true
        elif [[ "$line" == "Disabled" ]]; then
            parsing_enabled=false
        elif [[ "$parsing_enabled" == "true" ]]; then
            local module=$(echo "$line" | sed 's/^[[:space:]]*- *//' | xargs)
            if [[ -n "$module" ]]; then
                ENABLED_MODULES+=("$module")
            fi
        fi
    done < "${CONFIG_FILE}"

    if [[ -z "${BACKUP_FOLDER}" ]]; then
        echo "Error: BackupFolder not set in ${CONFIG_FILE}"
        exit 1
    fi
}

#
# Function: backup_brew
#
# Description: Backs up brew packages.
# Input: None
# Output: Creates a Brewfile in the backup folder.
#
function backup_brew() {
    echo "Backing up brew packages..."
    brew bundle dump --file="${BACKUP_FOLDER}/Brewfile" --force
}

#
# Function: restore_brew
#
# Description: Restores brew packages.
# Input: None
# Output: Installs packages from the Brewfile.
#
function restore_brew() {
    echo "Restoring brew packages..."
    brew bundle --file="${BACKUP_FOLDER}/Brewfile"
}

#
# Function: backup_stow
#
# Description: Backs up a module using stow.
# Input: $1 - module name (e.g., vim, tmux)
# Output: Creates symlinks in the stow directory.
#
function backup_stow() {
    local module="$1"
    local dotfile=""
    if [[ "$module" == "tmux" ]]; then
        dotfile=".tmux.conf"
    elif [[ "$module" == "vim" ]]; then
        dotfile=".vimrc"
    elif [[ "$module" == "zsh" ]]; then
        dotfile=".zshrc"
    else
        echo "Error: Unknown module for stow backup: $module"
        return 1
    fi

    echo "Backing up ${module}..."
    mkdir -p "${BACKUP_FOLDER}/STOW/${module}"

    # Move the original dotfile to the STOW directory
    if [[ -f "${HOME}/${dotfile}" ]]; then
        mv "${HOME}/${dotfile}" "${BACKUP_FOLDER}/STOW/${module}/${dotfile}"
    fi

    # Create symlink from STOW directory to home directory
    stow -d "${BACKUP_FOLDER}/STOW" -t "${HOME}" -S "${module}"
}

#
# Function: restore_stow
#
# Description: Restores a module using stow.
# Input: $1 - module name (e.g., vim, tmux)
# Output: Creates symlinks in the home directory.
#
function restore_stow() {
    local module="$1"
    local dotfile=""
    if [[ "$module" == "tmux" ]]; then
        dotfile=".tmux.conf"
    elif [[ "$module" == "vim" ]]; then
        dotfile=".vimrc"
    elif [[ "$module" == "zsh" ]]; then
        dotfile=".zshrc"
    else
        echo "Error: Unknown module for stow restore: $module"
        return 1
    fi

    if [[ -f "${HOME}/${dotfile}" && ! -L "${HOME}/${dotfile}" ]]; then
        echo "Error: ${HOME}/${dotfile} already exists and is not a symlink. Please remove it first."
        exit 1
    fi

    echo "Restoring ${module}..."
    stow -d "${BACKUP_FOLDER}/STOW" -t "${HOME}" -R "${module}"
}

#
# Function: restore_zsh
#
# Description: Restores zsh configuration and dependencies.
# Input: None
# Output: Installs zsh dependencies and restores config.
#
function restore_zsh() {
    echo "Restoring zsh..."

    # Ensure oh-my-zsh is installed
    if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
        echo "Installing oh-my-zsh..."
        # The install script for oh-my-zsh can be interactive.
        # Using --unattended to avoid interaction.
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        # oh-my-zsh installer creates a default .zshrc, which we need to remove
        # before stow can create a symlink to our custom .zshrc.
        if [[ -f "${HOME}/.zshrc" && ! -L "${HOME}/.zshrc" ]]; then
            echo "Removing oh-my-zsh generated ~/.zshrc to allow stow to create symlink."
            rm "${HOME}/.zshrc"
        fi
    else
        echo "oh-my-zsh is already installed."
    fi

    # Ensure zplug is installed
    if ! brew list zplug &>/dev/null; then
        echo "Installing zplug..."
        brew install zplug
    else
        echo "zplug is already installed."
    fi

    restore_stow "zsh"
}

#
# Function: main
#
# Description: The main function of the script.
# Input: Command-line arguments.
# Output: None
#
function main() {
    parse_args "$@"
    read_config

    mkdir -p "${BACKUP_FOLDER}"

    for module in "${ENABLED_MODULES[@]}"; do
        case "$module" in
            brew)
                if [[ "$ACTION" == "backup" ]]; then
                    backup_brew
                elif [[ "$ACTION" == "restore" ]]; then
                    restore_brew
                fi
                ;;
            vim|tmux)
                if [[ "$ACTION" == "backup" ]]; then
                    backup_stow "$module"
                elif [[ "$ACTION" == "restore" ]]; then
                    restore_stow "$module"
                fi
                ;;
            zsh)
                if [[ "$ACTION" == "backup" ]]; then
                    backup_stow "$module"
                elif [[ "$ACTION" == "restore" ]]; then
                    restore_zsh
                fi
                ;;
            *)
                echo "Unknown module: $module"
                ;;
        esac
    done

    echo "Done."
}

main "$@"
