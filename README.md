# Overview
forge is a command tool to mirror & setup the current macos configuration, so that it can be restored in another macos. It reads a configuraiton file to support backup & restore resources for MacOS  


Currently it can be configured to manage below resource in MacOS computer
- brew installed softwares
   use `brew bundle dump` & `brew bundle restore` to backup to target backup folder and restore via brewfile 
- tmux & its plugins 
   - TMUX plugins are managed via tpm. 
   - Backup: this tool use `stow` to syslink the `.tmux.conf` to target stow folder
   - Restore: Use `stow` to syslink the `.tmux.conf`, first ensure tmp plugin is installed, then automatically install all the plugins 
- vim & its plugins 
   - Vim plugins are managed via `Vundle` 
   - Backup: this tool use `stow` to syslink the `.vimrc` to target stow folder
   - Restore: use stow to syslink the `.vimrc`, first ensure Vundle plugin is installed, then use vundle to install all the plugins
- zsh & its plugins
   - zsh plugins are managed via `zplug`
   - Backup: this tool use `stow` to syslink the .zshrc to target stow folder
   - Restore: use stow to syslink the .zshrc. Do below 2 tasks 1) Ensure oh-my-zsh is installed 2) Ensure zplug is installed by brew. 
     For plugin installation, zplug should already configured in zshrc to install all plugins so nothing to do 
    
[#](#) Backup Folder Structure
Below is a example backup folder structure , this folder can be version controlled via git and backuped to remote git repo

```
ROOT/
  -- STOW/: contains all syslink managed configuration files
    -- tmux/.tmux.conf
    -- vim/.vimrc
  -- Brewfile: this is the generated brewfile via `brew bundle dump`
```
# Options

-f/--config target configuration file, default to .bumpx.conf

# Sample configuration file

```
BackupFolder: /path/to/configuration/files
Enabled
  - vim
  - brew
Disabled
  - tmux
```
