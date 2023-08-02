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

def pick-session-with-style [
    message: string, current_session: string, session_color: string, --multi: bool
]: [table -> string, table -> list<string>] { # table<name: string, attached: bool>
    let styled_sessions = $in | each {|it| (
        (if $it.name == $current_session { ansi $session_color } else { ansi default })
        ++ (if $it.attached { "* " } else { "  " })
        ++ $it.name
        ++ (ansi reset)
    )}

    let choices = if $multi {
        $styled_sessions | input list --multi $message
    } else {
        $styled_sessions | input list --fuzzy $message
    }

    $choices | ansi strip | str trim --left --char '*' | str trim
}

def switch-session [session?: string] {
    let session = if $session == null {
        let current_session = ^tmux display-message -p '#S' | str trim

        let prompt = $"(ansi cyan)Choose a session to switch to(ansi reset)"
        let choice = list-sessions | pick-session-with-style $prompt $current_session "yellow"
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

def remove-sessions [] {
    let sessions = list-sessions
    let current_session = ^tmux display-message -p '#S' | str trim

    let prompt = $"(ansi cyan)Please choose sessions to kill(ansi reset)"
    let choices = $sessions | pick-session-with-style --multi $prompt $current_session "red"

    $sessions | where name in $choices | sort-by attached | each {|session|
        if $session.attached {
            new-session
        }
        ^tmux kill-session -t $session.name
    }
}

def main [
    ...paths: path,
    --switch (-s): bool,
    --remove (-r): bool,
    --new (-n): bool,
    --list (-l): bool
] {
    if $list {
        return (list-sessions | to nuon --raw)
    }

    if $new {
        new-session
        return
    }

    if $remove {
        remove-sessions
        return
    }

    if $switch {
        switch-session
        return
    }

    if ($paths | is-empty) {
        error make --unspanned {
            msg: $"(ansi red_bold)missing_argument_error(ansi reset):
            tmux-sessionizer.nu requires paths as positional arguments"
        }
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
