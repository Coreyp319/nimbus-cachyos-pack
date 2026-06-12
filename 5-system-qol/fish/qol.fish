# Quality-of-life shell tooling. Each block is guarded with `type -q`, so this
# file is a harmless no-op until the corresponding binary is installed — safe to
# ship before `sudo pacman -S zoxide starship`. (eza/bat aliases + fastfetch
# greeting come from /usr/share/cachyos-fish-config — not duplicated here.)

# zoxide — smarter cd that learns your habits.  `z partial-name`, `zi` = fuzzy pick.
if type -q zoxide
    zoxide init fish | source
end

# starship — fast, informative cross-shell prompt (git status, exit code, etc.).
if type -q starship
    starship init fish | source
end

# fzf — fuzzy finder key bindings:  Ctrl-R history · Ctrl-T files · Alt-C cd.
if type -q fzf
    fzf --fish | source
end

# A couple of safe, non-shadowing conveniences for the already-installed tools.
if type -q fd; and type -q fzf
    set -gx FZF_DEFAULT_COMMAND 'fd --type f --hidden --follow --exclude .git'
    set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
end
if type -q bat
    set -gx FZF_CTRL_T_OPTS "--preview 'bat --style=numbers --color=always {} 2>/dev/null | head -200'"
end
