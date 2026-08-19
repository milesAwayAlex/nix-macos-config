# Two-line prompt: time [exit] user@host arch [branch] cwd / [jobs] $
prompt() {
    local exitstatus=$?
    local txtrst='\[\e[0m\]' txtred='\[\e[0;31m\]' txtylw='\[\e[0;33m\]' txtcyn='\[\e[0;36m\]'
    local brblk='\[\e[1;30m\]' brred='\[\e[1;31m\]' brgrn='\[\e[1;32m\]'
    local brylw='\[\e[1;33m\]' brblu='\[\e[1;34m\]' brpur='\[\e[1;35m\]' brcyn='\[\e[1;36m\]'

    local git branch=' '
    git=$(git branch --show-current 2>/dev/null)
    [ -n "$git" ] && branch=" ${brblk}[${brpur}${git}${brblk}]${txtrst} "

    local jobs=''
    [ -n "$(jobs -p)" ] && jobs="${brblk}[${txtylw}\j${brblk}]${txtrst} "

    local status=' '
    [ "$exitstatus" -ne 0 ] && status=" ${brred}[${txtred}${exitstatus}${brred}]${txtrst} "

    local arch=" ${txtcyn}$(uname -m)"

    PS1="${brylw}\t${txtrst}${status}${brcyn}\u${brblk}@${brcyn}\h${txtrst}${arch}${branch}${brblu}\w${txtrst}\n${jobs}${brgrn}\$${txtrst} "

    # Flush each command to the history file: tmux panes share history
    # instead of last-pane-exits-wins.
    history -a
}
PROMPT_COMMAND=prompt
