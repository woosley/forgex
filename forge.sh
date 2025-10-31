#!/usr/bin/env sh
#
# High-level function of the script.
# forge is a tool to mirror & setup the current macos configuration, so that it can be restored in another macos.
#
# Disclaimer - no warranties for correct function.
#
# Last-modified date: 2025-10-30 [2025-10-30]
#
# Which operating systems the script was written for.
# MacOS
#
# Written by: Mostly Gemini CLI with some human modifications
#
# Variable names are uppercased if the variable is read-only or if it is an external variable.
#

set -o errexit  # abort on nonzero exitstatus
set -o nounset  # abort on unbound variable
set -o pipefail # don't hide errors within pipes

# Global variables
# CONFIG_FILE: The configuration file for forge.
# BACKUP_FOLDER: The folder where the backup will be stored.
# ENABLED_MODULES: A list of modules to be backed up or restored.
# DISABLED_MODULES: A list of modules to be disabled.
CONFIG_FILE=".forge.conf"
BACKUP_FOLDER=""
ENABLED_MODULES=""
DISABLED_MODULES=""
LOG_FILE="forge.log"

#######################################
# Prints usage information.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Writes usage information to stdout.
# Returns:
#   0 if successful, non-zero on error.
#######################################
function usage() {
  echo "Usage: $0 [ -f/--config <config_file> ] [ backup | restore ]"
  echo "  -f/--config: The configuration file to use. Defaults to .forge.conf"
  echo "  backup: Backup the configuration."
  echo "  restore: Restore the configuration."
}

#######################################
# Parses the command line arguments.
# Globals:
#   CONFIG_FILE
# Arguments:
#   $@
# Outputs:
#   None
# Returns:
#   0 if successful, non-zero on error.
#######################################
function parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--config)
        CONFIG_FILE="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done
}

#######################################
# Parses the configuration file.
# Globals:
#   CONFIG_FILE
#   BACKUP_FOLDER
#   ENABLED_MODULES
#   DISABLED_MODULES
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   0 if successful, non-zero on error.
#######################################
function parse_config() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Configuration file not found: ${CONFIG_FILE}"
    exit 1
  fi

  local current_section=""
  while IFS= read -r line; do
    case "$line" in
      BackupFolder:*)
        BACKUP_FOLDER=$(echo "$line" | cut -d: -f2- | sed 's/^[ \t]*//;s/[ \t]*$//')
        current_section=""
        ;;
      Enabled:*)
        current_section="enabled"
        ;;
      Disabled:*)
        current_section="disabled"
        ;;
      *)
        if [[ -n "$line" ]]; then
          if [[ "$current_section" == "enabled" ]]; then
            local module=$(echo "$line" | cut -d '-' -f 2 | sed $'s/^[ \t]*//;s/[ \t]*$//')
            ENABLED_MODULES="${ENABLED_MODULES} ${module}"
          elif [[ "$current_section" == "disabled" ]]; then
            local module=$(echo "$line" | cut -d '-' -f 2 | sed $'s/^[ \t]*//;s/[ \t]*$//')
            DISABLED_MODULES="${DISABLED_MODULES} ${module}"
          fi
        fi
        ;;
    esac
  done < "${CONFIG_FILE}"
}

#######################################
# Backs up the brew configuration.
# Globals:
#   BACKUP_FOLDER
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   0 if successful, non-zero on error.
#######################################
function backup_brew() {
  echo "Backing up brew..."
  brew bundle dump --file "${BACKUP_FOLDER}/Brewfile" --force
}

#######################################
# Restores the brew configuration.
# Globals:
#   BACKUP_FOLDER
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   0 if successful, non-zero on error.
#######################################
function restore_brew() {
  echo "Restoring brew configuration..."
  brew bundle --file "${BACKUP_FOLDER}/Brewfile" >> "${LOG_FILE}" 2>&1
}

#######################################
# Backs up the tmux configuration.
# Globals:
#   BACKUP_FOLDER
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   0 if successful, non-zero on error.
#######################################
function backup_tmux() {
    echo "Backing up tmux..."
    local stow_dir="${BACKUP_FOLDER}/STOW"
    local package="tmux"
    local target_home_dir=~
    local config_file=".tmux.conf"
    local target_file_path="${target_home_dir}/${config_file}"
    local stow_package_dir="${stow_dir}/${package}"
    local stow_target_file_path="${stow_package_dir}/${config_file}"

    if [[ -L "${target_file_path}" ]]; then
        # It's a symlink. Let's see where it points.
        local link_destination
        link_destination=$(readlink "${target_file_path}")

        # Let's resolve the absolute path of the link destination
        local abs_link_destination
        if [[ "${link_destination}" == /* ]]; then
            # Absolute path
            abs_link_destination="${link_destination}"
        else
            # Relative path
            abs_link_destination="$(cd "${target_home_dir}" && cd "$(dirname "${link_destination}")" && pwd)/$(basename "${link_destination}")"
        fi

        if [[ "${abs_link_destination}" == "${stow_target_file_path}" ]]; then
            echo "${config_file} is already managed by stow. Skipping."
            return 0
        else
            echo "WARNING: ${config_file} is a symlink but does not point to the expected stow location."
            echo "  Symlink points to: ${abs_link_destination}"
            echo "  Expected location: ${stow_target_file_path}"
            echo "  Please resolve this manually."
            return 1
        fi
    fi

    if [[ -f "${target_file_path}" ]]; then
        echo "Found ${config_file}. Moving it to stow directory and creating symlink."
        mkdir -p "${stow_package_dir}"
        mv "${target_file_path}" "${stow_target_file_path}"
        stow -d "${stow_dir}" -t "${target_home_dir}" "${package}"
        echo "Done."
    else
        echo "${config_file} not found, nothing to back up."
    fi
}

#######################################
# Restores the tmux configuration.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   0 if successful, non-zero on error.
#######################################
function restore_tmux() {
    echo "Restoring tmux configuration..."
    if [[ ! -d ~/.tmux/plugins/tpm ]]; then
        echo "tpm not found, installing..."
        git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm >> "${LOG_FILE}" 2>&1
    fi
    stow -R -d "${BACKUP_FOLDER}/STOW" -t ~ tmux >> "${LOG_FILE}" 2>&1
    ~/.tmux/plugins/tpm/bin/install_plugins >> "${LOG_FILE}" 2>&1
}

#######################################
# Backs up the vim configuration.
# Globals:
#   BACKUP_FOLDER
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   0 if successful, non-zero on error.
#######################################
function backup_vim() {
    echo "Backing up vim..."
    local stow_dir="${BACKUP_FOLDER}/STOW"
    local package="vim"
    local target_home_dir=~
    local config_file=".vimrc"
    local target_file_path="${target_home_dir}/${config_file}"
    local stow_package_dir="${stow_dir}/${package}"
    local stow_target_file_path="${stow_package_dir}/${config_file}"

    if [[ -L "${target_file_path}" ]]; then
        # It's a symlink. Let's see where it points.
        local link_destination
        link_destination=$(readlink "${target_file_path}")

        # Let's resolve the absolute path of the link destination
        local abs_link_destination
        if [[ "${link_destination}" == /* ]]; then
            # Absolute path
            abs_link_destination="${link_destination}"
        else
            # Relative path
            abs_link_destination="$(cd "${target_home_dir}" && cd "$(dirname "${link_destination}")" && pwd)/$(basename "${link_destination}")"
        fi

        if [[ "${abs_link_destination}" == "${stow_target_file_path}" ]]; then
            echo "${config_file} is already managed by stow. Skipping."
            return 0
        else
            echo "WARNING: ${config_file} is a symlink but does not point to the expected stow location."
            echo "  Symlink points to: ${abs_link_destination}"
            echo "  Expected location: ${stow_target_file_path}"
            echo "  Please resolve this manually."
            return 1
        fi
    fi

    if [[ -f "${target_file_path}" ]]; then
        echo "Found ${config_file}. Moving it to stow directory and creating symlink."
        mkdir -p "${stow_package_dir}"
        mv "${target_file_path}" "${stow_target_file_path}"
        stow -d "${stow_dir}" -t "${target_home_dir}" "${package}"
        echo "Done."
    else
        echo "${config_file} not found, nothing to back up."
    fi
}

#######################################
# Restores the vim configuration.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   0 if successful, non-zero on error.
#######################################
function restore_vim() {
    echo "Restoring vim configuration..."
    if [[ ! -d ~/.vim/bundle/Vundle.vim ]]; then
        echo "Vundle not found, installing..."
        git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim >> "${LOG_FILE}" 2>&1
    fi
    stow -R -d "${BACKUP_FOLDER}/STOW" -t ~ vim >> "${LOG_FILE}" 2>&1
    vim +PluginInstall +qall >> "${LOG_FILE}" 2>&1
}

#######################################
# Main function.
# Globals:
#   ENABLED_MODULES
#   DISABLED_MODULES
# Arguments:
#   $@
# Outputs:
#   None
# Returns:
#   0 if successful, non-zero on error.
#######################################
function main() {
  parse_args "$@"
  parse_config

  local action=""
  if [[ $# -gt 0 ]]; then
    action="$1"
  fi

  if [[ -z "${action}" ]]; then
    usage
    exit 1
  fi

  for module in ${ENABLED_MODULES}; do
    if [[ " ${DISABLED_MODULES} " =~ " ${module} " ]]; then
      continue
    fi

    case "${module}" in
      brew)
        if [[ "${action}" == "backup" ]]; then
          backup_brew
        elif [[ "${action}" == "restore" ]]; then
          restore_brew
        fi
        ;;
      tmux)
        if [[ "${action}" == "backup" ]]; then
          backup_tmux
        elif [[ "${action}" == "restore" ]]; then
          restore_tmux
        fi
        ;;
      vim)
        if [[ "${action}" == "backup" ]]; then
          backup_vim
        elif [[ "${action}" == "restore" ]]; then
          restore_vim
        fi
        ;;
      *)
        echo "Unknown module: ${module}"
        ;;
    esac
  done
}

main "$@"
