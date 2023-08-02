#!/usr/bin/env nu

def run [cmd: closure]: nothing -> record { # record<stdout: string, stderr: string, exit_code: int>
    do --ignore-errors $cmd | complete
}

def list-sessions [] {
    ^tmux list-sessions
        | lines
        | parse "{name}: {windows} windows (created {date}){attached}"
        | into int windows
        | into datetime date
        | update attached {|it| $it.attached != ""}
}

def switch-session [session?: string] {
    let session = if $session == null {
        let choice = list-sessions
            | each {|it| (if $it.attached { "* " } else { "  " }) ++ $it.name}
            | input list --fuzzy $"(ansi cyan)Choose a session to switch to(ansi reset)"
            | str trim --left --char '*'
            | str trim
        if ($choice | is-empty) {
            return
        }

        $choice
    } else {
        let sessions = list-sessions | get name

        if not ($session in $sessions) {
            error make --unspanned {
                msg: $"(ansi red_bold)invalid_session_name(ansi reset):
                expected one of ($sessions), got ($session)"
            }
        }

        $session
    }


    ^tmux switch-client -t $session
}

def new-session [] {
    let session_name = random uuid
    if not ($session_name in (list-sessions | get name)) {
        ^tmux new-session -ds $session_name
    }
    ^tmux switch-client -t $session_name
}

def main [...paths: path, --switch (-s): bool, --new (-n): bool, --list (-l): bool] {
    if $list {
        return (list-sessions | to nuon --raw)
    }

    if $new {
        new-session
        return
    }

    if $switch {
        switch-session
        return
    }

    let choice = $paths
        | input list --fuzzy $"(ansi cyan)Choose a directory to open a session in(ansi reset)"
    if ($choice | is-empty) {
        return
    }

    let name = $choice | path basename | str replace --all --string '.' '_'

    if ($env.TMUX? | is-empty) and (pgrep tmux | is-empty) {
        ^tmux new-session -s $name -c $choice
        return
    }

    if (run { ^tmux has-session -t $name }).exit_code == 1 {
        ^tmux new-session -ds $name -c $choice
    }

    ^tmux switch-client -t $name
}
