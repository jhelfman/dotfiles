# To be sourced within dotfiles script.

MODS_ON="$APP_ROOT/mods-enabled"
MODS_ALL="$APP_ROOT/mods-available"
readonly APP_ROOT MODS_ON MODS_ALL

# Exit if any command returns nonzero or unset variable referenced.
set -o errexit -o pipefail -o nounset

# Allow aliases for functions in this script, such as 'alias info'.
shopt -s expand_aliases

# Make patterns that match nothing disappear instead of treated as string
# Alternative is put just inside for loop: [[ -f $file ]] || continue
shopt -s nullglob


print_usage () {
  echo "Usage: $0 [ install | test ]"
  return 1
}

#######################################
# Format text for fancy display.
# Globals:
#   None
# Arguments:
#   format  (string) Must be one of: bold, under (for underline), red, green,
#     yellow, blue, magenta, cyan, white, red, purple
#   text[]  (string) One or more texts to be concatenated and formatted
# Returns:
#   Echos string(s) wrapped in escape codes for given format
#######################################
fmt() {
  local reset=$(tput sgr0)
  local bold=$(tput bold)
  local under=$(tput smul)
  local red=$(tput setaf 1)
  local green=$(tput setaf 2)
  local yellow=$(tput setaf 3)
  local blue=$(tput setaf 4)
  local magenta=$(tput setaf 5)
  local cyan=$(tput setaf 6)
  local white=$(tput setaf 7)
  local red=$(tput setaf 9)
  local purple=$(tput setaf 13)
  echo "${!1}${@:2}${reset}"
}

#######################################
# Print wrappers for customized status output.
# Inspired by similar in @holman/dotfiles
# Globals:
#   fmt  (function) Text formatting
# Arguments:
#   type  (string) Notice type: (i|info)|(u|user)|(o|okay)|(f|fail)
#   text  (string) Text to be wrapped
# Returns:
#   Prints given text prepended by 'info', ' >> ', 'pass' or 'FAIL'
#######################################
print_wrap () {
  local color= text=
  case $1 in
    i | info ) color=blue    text='info' ;;
    u | user ) color=magenta text=' >> ' ;;
    o | okay ) color=green   text='pass' ;;
    f | fail ) color=red     text='FAIL' ;;
    * ) return 1 ;;
  esac
  shift
  printf " %b" "\r  [$(fmt $color "$text")] $@\n"
}
alias info='print_wrap i'
alias user='print_wrap u'
alias okay='print_wrap o'
alias fail='print_wrap f'

#######################################
# Try to put file or directory in trash, otherwise delete.
# Globals:
#   None
# Arguments:
#   item    (string) File or directory to trash
#   indent  (string) Optional text to prepend to messages
# Returns:
#   None
#######################################
trash_file () {
  local item=$1
  local indent=${2:-} # empty string unless second param set
  if [[ -d $item || -f $item ]]; then
    info "${indent}Trashing $(fmt bold $item)."
    if test ! $(which trash); then
      if brew install trash; then
        trash "$item"
        brew uninstall trash
      else
        info "${indent}Unable to install trash. Deleting $(fmt bold $item)."
        rm -rf "$item"
      fi
    else
      trash "$item"
    fi
  fi
}

#######################################
# Install a module.
# Globals:
#   MODS_ALL (string) Path to all modules that can be installed.
#   MODS_ON   (string) Path to symlinks indicating installed modules.
# Arguments:
#   module  (string) Name of module
#   indent  (string) Optional text to prepend to messages
# Returns:
#   None
#######################################
module_install () {
  local module=$1
  local indent=${2:-} # '| ' unless second param set
  local outer=$indent
  local inner="$indent| "
  local nice_name=$(fmt bold $module)

  if [[ ! -d "$MODS_ALL/$module" ]]; then
    if [[ -h "$MODS_ON/$module" ]]; then
      info "${outer}Module $nice_name is already installed," \
        "but it cannot be reinstalled because it is unavailable."
    else
      fail "${outer}Cannot find module $nice_name."
    fi
    return 1
  fi

  if [[ -h "$MODS_ON/$module" ]]; then
    info "${outer}Module $nice_name is already installed, but reinstalling."
  else
    info "${outer}Installing module $nice_name."
  fi
  trap_term_signal () {
    fail "${inner}Termination signal received. Uninstalling."
    module_remove "$module" "$inner"
    rm -f "$MODS_ON/$module"
    exit
  }
  trap_fail () {
    fail "${inner}Installation failed. Fix problem and repeat:"
    user "${inner}$(fmt bold dotfiles install \"$module\")"
    rm -f "$MODS_ON/$module"
    exit
  }
  trap trap_term_signal INT TERM
  trap trap_fail EXIT
  link_file "../${MODS_ALL##*/}/$module" "$MODS_ON" "$inner"
  #ln -s "../${MODS_ALL##*/}/$module" "$MODS_ON"
  scripts_execute "$MODS_ON/$module" 'install' "$inner"
  module_upgrade "$module" "$inner"
  trap - INT TERM EXIT
  okay "${outer}Done."
}


#######################################
# Upgrade one or all enabled modules.
# Globals:
#   MODS_ON   (string) Path to symlinks indicating installed modules.
# Arguments:
#   module  (string) Name of module or "--all"
#   indent  (string) Optional text to prepend to messages
# Returns:
#   None
#######################################
module_upgrade () {
  local module=$1
  local indent=${2:-} # '| ' unless second param set
  local outer=$indent
  local inner="$indent| "

  # If -all flag, recurse
  if [[ $module == --all ]]; then
    info "${outer}Upgrading all installed modules."
    for module in "$MODS_ON"/*; do
      module_upgrade "${module##*/}" "$inner"
    done
    okay "${outer}Done."
    return 0
  fi

  local count=0
  local nice_name=$(fmt bold $module)
  local path=$MODS_ON/$module

  if [[ ! -h $path ]]; then
    fail "${outer}Module $nice_name is not installed."
    return 1
  fi

  info "${outer}Upgrading module $nice_name."
  scripts_execute "$path" 'upgrade' "$inner"
  packages_upgrade "$path/Brewfile" "$inner"
  dotfiles_install "$path" "$inner"
  okay "${outer}Done."
}


#######################################
# Install or upgrade any packages listed in a manifest.
# Globals:
#   MODS_ON   (string) Path to symlinks indicating installed modules
# Arguments:
#   manifest  (string) Path of manifest which need not exist
#   indent    (string) Optional text to prepend to messages
# Returns:
#   None
#######################################
packages_upgrade () {
  local manifest=$1
  local indent=${2:-} # empty string unless second param set
  local outer=$indent
  local inner="$indent| "
  local line
  info "${outer}Checking for packages to install or upgrade."
  if [[ -f $manifest ]]; then
    if [[ ! -h "$MODS_ON/brew" ]]; then
      fail "${inner}Need module $(fmt bold brew) to process manifest."
      user "${inner}Retry after running: $(fmt bold dotfiles install brew)"
      return 1
    fi
    if ! brew bundle check --file="$manifest" > /dev/null; then

      # run update command and fix any "already app" errors
      if ! command_log=$(brew bundle --file="$manifest"); then
        # disabling version that outputs by default. let's hide unless cannot resolve
        # /dev/tty idea from http://stackoverflow.com/a/12451419/172602 comment
        #if ! command_log=$(brew bundle --file="$manifest" | tee /dev/tty); then
        info "${inner}Updates failed. Attempting resolution."
        command_log=$(echo "$command_log" | grep 'It seems there is already an App')
        local resolution=0 # return 1 if we couldn't resolve errors
        local line
        while read -r line; do
          line=${line#*already an App at \'}
          line=${line%\'.}
          trash_file "$line" "$inner| " || resolution=1
        done <<< "$command_log"
        if (( resolution == 1 )); then
          fail "${inner}Could not resolve. Here is the log of what failed."
          echo "$command_log"
          return resolution
        fi
        info "${inner}Resolved some errors. Updating again."
        command_log=$(brew bundle --file="$manifest") || {
          fail "${inner}Updates failed again. Resolve manually."
          echo "$command_log"
          return 1
        }
      fi

    fi
  fi
  okay "${outer}Done."
}

#######################################
# Uninstall a module.
# Globals:
#   MODS_ALL (string) Path to all modules that can be installed.
#   MODS_ON   (string) Path to symlinks indicating installed modules.
# Arguments:
#   module  (string) Name of module
#   indent  (string) Optional text to prepend to messages
# Returns:
#   None
#######################################
module_remove () {
  local module=$1
  local indent=${2:-} # '| ' unless second param set
  local outer=$indent
  local inner="$indent| "
  local nice_name=$(fmt bold $module)

  if [[ ! -h "$MODS_ON/$module" ]]; then
    if [[ -d "$MODS_ALL/$module" ]]; then
      info "${outer}Module $nice_name is not installed."
    else
      info "${outer}Module $nice_name is neither installed nor available."
    fi
    return 0
  fi

  info "${outer}Removing module $nice_name."
  scripts_execute "$MODS_ON/$module" 'remove' "$inner"
  packages_remove "$MODS_ON/$module/Brewfile" "$inner"
  rm -f "$MODS_ON/$module"
  if [[ ! -d "$MODS_ALL/$module" ]]; then
    info "${inner}Module $nice_name is now removed," \
      "but it cannot be reinstalled because it is unavailable."
  fi
  #info "${inner}Module $nice_name is now removed and can be reinstalled" \
  #  "with $(fmt bold dotfiles install \"$module\")."
  okay "${outer}Done."
}


#######################################
# Run scripts matching type and path.
# Globals:
#   None
# Arguments:
#   path (string) Directory to search
#   name (string) Find scripts starting with this and ending in .bash or .sh
# Returns:
#   None
#######################################
scripts_execute () {
  local path=$1
  local name=$2
  local indent=${3:-} # empty string unless second param set
  local outer=$indent
  local inner="$indent| "
  local count=0

  if [[ ! -h $path ]]; then
    fail "${outer}Invalid path $(fmt bold $path)."
    return 1
  fi

  info "${outer}Checking for $name scripts."
  for file in "$path/$name"*; do
    case $file in
      *.sh | *.bash )
        info "${inner}Executing $(fmt bold $file)."
        (( count++ ))
        source "$file"
        ;;
      * )
        fail "${inner}Found $(fmt bold $file), but scripts must" \
          "end in $(fmt bold .sh) or $(fmt bold .bash)."
        return 1
        ;;
    esac
  done
  (( count == 0 )) && info "${inner}No $name scripts found."
  okay "${outer}Done."
}

#######################################
# Symlink files named *.symlink to ~/.*
# Globals:
#   HOME   (string) Path to symlinks indicating installed modules.
# Arguments:
#   path (string) Directory to search
#   indent  (string) Optional text to prepend to messages
# Returns:
#   None
#######################################
dotfiles_install () {
  local path=$1
  local indent=${2:-} # empty string unless second param set
  local outer=$indent
  local inner="$indent| "
  local count=0

  if [[ ! -h $path ]]; then
    fail "${outer}Invalid path $(fmt bold $path)."
    return 1
  fi

  info "${outer}Checking for configuration files to link."
  for src in "$path"/*.symlink; do
    dst="$HOME/.$(basename "${src%.*}")"
    link_file "$src" "$dst" "$inner"
    (( count++ ))
  done
  (( count > 0 )) || info "${inner}No configuration files found."
  okay "${outer}Done."
}

#######################################
# Remove any packages listed in a manifest.
# Globals:
#   None
# Arguments:
#   manifest  (string) Path of manifest which need not exist
#   indent    (string) Optional text to prepend to messages
# Returns:
#   None
#######################################
packages_remove () {
  local manifest=$1
  local indent=${2:-} # empty string unless second param set
  local outer=$indent
  local inner="$indent| "
  local line
  info "${outer}Checking for packages to remove."
  if [[ -f $manifest ]]; then
    if [[ ! -h $MODS_ON/brew ]]; then
      fail "${inner}Need module $(fmt bold brew) to process manifest."
      user "${inner}Retry after running: $(fmt bold dotfiles install brew)"
      return 1
    fi
    cat "$manifest" | tr -s " " | # squash spaces and pass to loop
    {
      while read -r line; do
        line=${line%,*} # keep up to first comma
        line=${line//\'/} # hope package names don't contain single quotes
        line=${line//\"/} # hope package names don't contain double quotes
        case $line in
          '#'* ) ;; # ignore comments
          'brew '* )
            brew uninstall "${line#brew }"
            ;;
          'cask '* )
            brew cask uninstall "${line#cask }"
            ;;
          'mas '*  )
            trash_file "/Applications/${line#mas }.app" "$inner| "
            ;;
          *  )
            info "${inner}Unsure how to handle line:"
            info "${inner}| $(fmt bold $line)"
            ;;
        esac
      done
    }
  fi
  okay "${outer}Done."
}

#######################################
# Create symlinks and prompt on conflict to skip, overwrite or backup.
# Based on @holman/dotfiles but largely changed logic.
# Globals:
#   overwrite_all (bool) Optional flag
#   backup_all    (bool) Optional flag
#   skip_all      (bool) Optional flag
# Arguments:
#   src (file) Source file
#   dst (file) Directory to put link
# Returns:
#   Prints actions taken.
#######################################
link_file () {
  # set global vars to defaults if not set
  overwrite_all=${overwrite_all:-false}
  backup_all=${backup_all:-false}
  skip_all=${skip_all:-false}

  local src=$1 dst=$2
  [[ $src = ..* ]] && src=$( cd "$dst/$src" && pwd -P ) # resolve relative path
  [[ -d $dst ]] && dst=$dst/$(basename "$src") # aid detection of existing link
  local indent=${3:-} # emptry string unless second param set
  local outer=$indent
  local inner="$indent| "
  local nicesrc=$(fmt bold $src)
  local nicedst=$(fmt bold $dst)
  local overwrite= backup= skip= # var=false breaks var=${var:-$var_all}
  local action=

  info "${outer}Attempting to link to $(fmt bold $(basename "$src"))."

  if ! [[ -f $src || -d $src || -L $src ]]; then
    fail "${outer}Source file $nicesrc does not exist."
    return 1
  fi

  if [[ -f $dst || -d $dst || -L $dst ]]; then
    local currentSrc=$(readlink $dst)
    if [[ $currentSrc = $src ]]; then
      # okay "${outer}$nicedst already points to $nicesrc"
      return 0
    fi

    if [[ $overwrite_all = false && $backup_all = false && $skip_all = false ]]; then
      user "${inner}File $nicedst already exists. What do you want to do?"
      user "${inner}[s]kip, [S]kip all," \
        '[o]verwrite, [O]verwrite all, [b]ackup, [B]ackup all'
      read -n 1 action
      case $action in
        o ) overwrite=true ;;
        O ) overwrite_all=true ;;
        b ) backup=true ;;
        B ) backup_all=true ;;
        s ) skip=true ;;
        S ) skip_all=true ;;
        * ) ;;
      esac
    fi

    # assumes initialized with 'var=' not 'var=false'
    overwrite=${overwrite:-$overwrite_all}
    backup=${backup:-$backup_all}
    skip=${skip:-$skip_all}

    if [[ $skip = true ]]; then
      okay "${inner}Skipped $nicesrc."
      return 0
    else
      if [[ $overwrite = true ]]; then
        rm -rf "$dst" &&
        info "${inner}Removed $nicedst."
      elif [[ $backup = true ]]; then
        local bck="${dst}.$(date "+%Y%m%d_%H%M%S").backup"
        mv "$dst" "$bck" &&
        info "${inner}Moved $nicedst to $(fmt bold $bck)."
      fi
    fi
  fi

  ln -s "$1" "$2" &&
  okay "${outer}Linked $(fmt bold $1) to $(fmt bold $2)."
}

#######################################
# Remove Homebrew installed programs that are not in the cumulative Brewfiles.
# Globals:
#   APP_ROOT  (string) Application directory.
# Arguments:
#   indent  (string) Optional text to prepend to messages
# Returns:
#   None
#######################################
packages_cleanup () {
  local indent=${1:-} # empty string unless second param set
  local outer=$indent
  local inner="$indent| "
  local brewcommand="find -H \"$APP_ROOT\" -not \( -path available -prune \) -name Brewfile -print0 | xargs -0 cat | brew bundle cleanup --file=-"
  local result
  local action
  eval "result=\$($brewcommand)"
  if [[ $result =~ 'Would uninstall formulae' ]]; then
    info "${outer}The following Homebrew programs were manually installed:"
    result=$(echo "$result" | tail -n +2 | tr '\n' ',')
    result=${result%,}
    info "${outer}$(fmt bold ${result//,/, })"
    user "${outer}Uninstall?  $(fmt bold 'n/Y')"
    while read -n 1 action; do
      case $action in
        n ) info "${inner}All right, they will be left alone." break ;;
        Y )
          info "${inner}Uninstalling."
          eval "$brewcommand --force" > /dev/null
          if (( $? != 0 )); then
            fail "${inner}Error uninstalling."
            return 1
          else
            okay "${inner}Done."
          fi
          break
          ;;
        * )
          fail "${inner}$(fmt bold "$action") is not valid." \
            "Enter $(fmt bold n) or $(fmt bold Y)."
          ;;
      esac
    done
  fi
}
