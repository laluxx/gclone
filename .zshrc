# MSH ZSH Configuration

# History Configuration
HISTFILE=${HOME}/.cache/emacs/msh/history
HISTSIZE=10000
SAVEHIST=10000
mkdir -p ${HOME}/.cache/emacs/msh

# Emacs key bindings
bindkey -e

# Shell Options
setopt EXTENDED_HISTORY       # Save timestamp in history
setopt HIST_EXPIRE_DUPS_FIRST # Expire duplicate entries first when trimming history
setopt HIST_IGNORE_DUPS       # Don't record an entry that was just recorded again
setopt HIST_IGNORE_SPACE      # Don't record entries starting with a space
setopt HIST_VERIFY            # Show command with history expansion before running it
setopt HIST_REDUCE_BLANKS     # Remove superfluous blanks before recording entry
setopt INTERACTIVE_COMMENTS    # Allow comments in interactive shells
setopt AUTO_CD                # Directory names that are commands get cd'd to
setopt AUTO_PUSHD             # Push the old directory onto the stack on cd
setopt PUSHD_IGNORE_DUPS      # Do not store duplicates in the stack
setopt PUSHD_SILENT           # Do not print directory stack after pushd/popd

# Basic Completion System
autoload -Uz compinit
compinit

# Prompt Configuration
setopt PROMPT_SUBST
autoload -Uz colors && colors
PS1='%F{green}%n@%m%f:%F{blue}%~%f%# '

# Useful Aliases
alias ls='ls --color=always'
alias ll='ls -lah'
alias grep='grep --color=always'
alias ..='cd ..'
alias ...='cd ../..'

# Additional Key Bindings
bindkey '^[[A' up-line-or-search     # Up arrow for history search
bindkey '^[[B' down-line-or-search   # Down arrow for history search
bindkey '^[[H' beginning-of-line     # Home key
bindkey '^[[F' end-of-line          # End key
bindkey '^[[3~' delete-char         # Delete key
bindkey '^[[1;5C' forward-word      # Ctrl-Right
bindkey '^[[1;5D' backward-word     # Ctrl-Left
