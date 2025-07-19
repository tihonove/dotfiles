# Fish shell configuration

# Set PATH
set -gx PATH /Users/tihonove/bin $PATH
set -gx PATH /opt/homebrew/opt/openjdk@21/bin $PATH

# Load Homebrew environment first
eval (/opt/homebrew/bin/brew shellenv)

# Source OrbStack integration if available
if test -f ~/.orbstack/shell/init.fish
    source ~/.orbstack/shell/init.fish
end

# For bash/zsh scripts, we'll handle them differently
# Add Nebius CLI paths directly
if test -f '/Users/tihonove/.config/newbius/path.zsh.inc'
    set -gx PATH /Users/tihonove/.config/newbius/bin $PATH
end

if test -f '/Users/tihonove/nebius-cloud/path.bash.inc'
    set -gx PATH /Users/tihonove/nebius-cloud/bin $PATH
end
