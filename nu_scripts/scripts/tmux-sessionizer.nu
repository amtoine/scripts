#!/usr/bin/env nu
use std log

def run [cmd: closure]: nothing -> record { # record<stdout: string, stderr: string, exit_code: int>
    do --ignore-errors $cmd | complete
}

def list-sessions [--expand: bool] {
    let sessions = ^tmux list-sessions
        | lines
        | parse "{name}: {windows} windows (created {date}){attached}"
        | into int windows
        | into datetime date
        | update attached {|it| $it.attached != ""}

    if not $expand {
        return $sessions
    }

    # : table<name: string, pwd: path>
    let pwds = ^tmux list-sessions -F '#S:#{pane_current_path}' | lines | parse "{name}:{pwd}"

    $sessions | join --outer $pwds name | update windows {|session|
        ^tmux list-windows -t $session.name
            | lines
            | parse "{id}: {app} ({panes} panes) {rest}"
            | str trim --right --char '*' app
            | str trim --right --char '-' app
            | insert active {|it| not ($it.rest | find '(active)' | is-empty)}
            | reject rest
    }
}

def pick-session-with-style [
    message: string,
    current_session: string,
    session_color: string,
    --multi: bool,
    --expand: bool = false
]: [table -> string, table -> list<string>] { # table<name: string, attached: bool, windows: table<app: string>, pwd: path>
    let named_sessions = $in | update name {|it| (
            (if $it.name == $current_session { ansi $session_color } else { ansi default })
            ++ (if $it.attached { "* " } else { "  " })
            ++ $it.name
            ++ (ansi reset)
        )}

    let styled_sessions = if $expand {
        $named_sessions
            | select name windows.app pwd
            | rename name apps pwd
            | update apps { str join ", " }
    } else {
        $named_sessions | get name
    }

    let choices = if $multi {
        $styled_sessions | input list --multi $message
    } else {
        $styled_sessions | input list --fuzzy $message
    }

    if ($choices | is-empty) {
        return
    }

    $choices
        | get name
        | ansi strip
        | split column " | "
        | get column1
        | str trim --left --char '*'
        | str trim
}

def switch-session [session?: string, --expand: bool = false] {
    let session = if $session == null {
        let sessions = if $expand {
            list-sessions --expand
        } else {
            list-sessions
        }
        let current_session = ^tmux display-message -p '#S' | str trim

        let prompt = $"(ansi cyan)Choose a session to switch to(ansi reset)"
        let choice = $sessions
            | pick-session-with-style --expand $expand $prompt $current_session "yellow"
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
        ^tmux new-session -ds $session_name -c $nu.home-path
    }
    ^tmux switch-client -t $session_name
}

def remove-sessions [--expand: bool = false] {
    let sessions = if $expand {
        list-sessions --expand
    } else {
        list-sessions
    }
    let current_session = ^tmux display-message -p '#S' | str trim

    let prompt = $"(ansi cyan)Please choose sessions to kill(ansi reset)"
    let choices = $sessions
        | pick-session-with-style --expand $expand --multi $prompt $current_session "red"

    if ($choices | is-empty) {
        return
    }

    $sessions | where name in $choices | sort-by attached | each {|session|
        log debug $"killing session '($session.name)'"
        if $session.attached {
            new-session
        }
        ^tmux kill-session -t $session.name
    }
}

# manage any Tmux session in a single script
#
# > **Note**  
# > in the following the options are in reverse order of priority, meaning the
# > the further down the list, the more it will be executed first and overrides
# > previous options when both set.
#
# # Examples
#     open a session in a Git repository managed by `nu-git-manager`
#     > tmux-sessionizer.nu (gm list --full-path)
#
#     list open sessions
#     > tmux-sessionizer.nu | from nuon
def main [
    ...paths: path,  # the list of paths to fuzzy find and jump to in a new session
    --switch (-s): bool,  # switch to another open session
    --remove (-r): bool,  # remove any amount of open sessions (creates a new random one if current is deleted)
    --new (-n): bool,  # create a new random session
    --list (-l): bool,  # list all open sessions, in raw NUON format
    --expand: bool
] {
    if $list {
        if $expand {
            return (list-sessions --expand | to nuon --raw)
        }

        return (list-sessions | to nuon --raw)
    }

    if $new {
        new-session
        return
    }

    if $remove {
        remove-sessions --expand $expand
        return
    }

    if $switch {
        switch-session --expand $expand
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
