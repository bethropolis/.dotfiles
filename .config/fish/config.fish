if status is-interactive
    # Commands to run in interactive sessions can go here
end

set fish_greeting "Hiii $USER"

set -x DOTFILES $HOME/Projects/.dotfiles/

# User specific environment
# Fish handles PATH differently - we use fish_add_path
fish_add_path $HOME/.local/bin
fish_add_path $HOME/go/bin

# some apps are just spitting their configs at home
set -gx XDG_CONFIG_HOME $HOME/.config

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

# Load cargo environment if it exists
if test -d $HOME/.cargo
    fish_add_path $HOME/.cargo/bin
end

# Initialize starship if installed
if command -v starship >/dev/null
    starship init fish | source
end

if command -v fzf >/dev/null
    fzf --fish | source
end

if command -v zoxide >/dev/null
    zoxide init fish | source
end

function mkcd
    mkdir -p $argv[1]
    cd $argv[1]
end

function dump
    bash "$HOME/scripts/flatpaks.sh"
    bash "$HOME/scripts/gextensions.sh"
end

# My aliases
alias cd="z"
alias b="cd -"
alias ls="lsd"
alias lsh="ls -lh"
alias cat="bat"
alias du="erd"
alias cat="bat"
alias grep="rg"
alias find="fd"
alias op="xdg-open"
alias fzb="fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'"
alias nv="nvim"
alias docker="podman"
alias bashrc="nv $HOME/.bashrc"
alias brc="bashrc"
alias fishrc="nv $HOME/.config/fish/config.fish"
alias frc="fishrc"
alias src="source $HOME/.config/fish/config.fish"
alias gs="git status"
alias cr="cargo run"
alias cb="cargo build"
alias cc="cargo check"
alias ccl="cargo clippy"
alias dots="cd $DOTFILES"
alias cls="clear"
alias neofetch="fastfetch"
alias mariadb="mariadb -u bethro -p"
alias lg='lazygit'
alias grab='grab --output ./codebase.md'
alias vlc="flatpak run org.videolan.VLC"
alias clap="flatpak run com.github.rafostar.Clapper"
alias zed="flatpak run dev.zed.Zed"
alias anime="bash $HOME/.config/anime/anime.sh -t 8 -T 300 -o eng -r 1080 -a"
alias animez="bash $HOME/.config/anime/zen-dl.sh -t 8 -T 300 -o dub -r 1080 -a"
alias yeet='sudo dnf remove'
alias install="sudo dnf install -y"
alias update='sudo dnf update -y'
alias fupdate='flatpak update -y'
alias tx="toolbox enter"
alias q="exit"

# Custom function to source fish config (equivalent to source bashrc)
function reload_fish
    source ~/.config/fish/config.fish
end

# initial scripts and patches

# bun
# set -gx BUN_INSTALL "$HOME/.bun"
fish_add_path $HOME/.bun/bin
