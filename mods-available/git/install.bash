#######################################
# Create local Git config file based on user input.
# Basically lifted from @holman/dotfiles.
# Globals:
#   MODS_ALL (string) Path to all modules that can be installed.
#   lvl      (int)    Indentation level.
# Arguments:
#   None
# Returns:
#   Prints actions taken.
#######################################
create_local_config() {
  local path=$MODS_ALL/git
  local target_file=$path/gitconfig.local.symlink
  if [[ ! -f $target_file ]]; then
    info $lvl2 'Creating local Git config.'

    local git_credential='cache'
    if [[ $(uname -s) = 'Darwin' ]]; then
      git_credential='osxkeychain'
    fi

    #local git_authorname git_authoremail
    user $lvl2 "$(fmt bold What is your Github author name?)"
    read -e git_authorname
    user $lvl2 "$(fmt bold What is your Github author email?)"
    read -e git_authoremail

    sed -e "s/AUTHORNAME/$git_authorname/g" -e "s/AUTHOREMAIL/$git_authoremail/g" -e "s/GIT_CREDENTIAL_HELPER/$git_credential/g" "$target_file.example" > "$target_file"

    okay $lvl2 'Local Git config created and will be installed on next update.'
  fi
}

create_local_config