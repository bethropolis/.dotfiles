if status is-interactive
    # Commands to run in interactive sessions can go here
end



# config.fish


set -x DOTFILES $HOME/Projects/.dotfiles/

# User specific environment
# Fish handles PATH differently - we use fish_add_path
fish_add_path $HOME/.local/bin
fish_add_path $HOME/bin

# bun
set -x BUN_INSTALL $HOME/.bun
fish_add_path $BUN_INSTALL/bin

# maria db functions
function start_mariadb
    sudo systemctl start mariadb
end

function stop_mariadb
    sudo systemctl stop mariadb
end

function mariadb_status
    sudo systemctl status mariadb
end

function pocketbase
    $HOME/Programs/pocketbase/pocketbase serve
end

# GO Binary
fish_add_path $HOME/go/bin

# Load cargo environment if it exists
if test -d $HOME/.cargo
    fish_add_path $HOME/.cargo/bin
end

# Initialize starship if installed
if command -v starship >/dev/null
    starship init fish | source
end

# My aliases
alias nv="nvim"
alias bashrc="nv ~/.bashrc"
alias brc="bashrc"
alias fishrc="nv ~/.config/fish/config.fish"
alias frc="fishrc"
alias dots="cd $DOTFILES"
alias cls="clear"
alias neofetch="fastfetch"
alias mariadb="mariadb -u bethro -p"
alias docker="podman"
alias proj="cd ~/Projects/"
alias lg='lazygit'
alias yeet='sudo dnf remove'

# Custom function to source fish config (equivalent to source bashrc)
function reload_fish
    source ~/.config/fish/config.fish
end
