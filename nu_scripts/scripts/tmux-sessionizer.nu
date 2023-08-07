#!/usr/bin/env nu
use std log

# FIXME: complex type annotation, waiting for https://github.com/nushell/nushell/pull/9769
# default: nothing -> table<name: string, windows: int, date: date, attached: bool>
# --expand: nothing -> table<name: string, windows: table<id: string, app: string, panes: string, active: bool>, date: date, attached: bool, pwd: string>
def list-sessions [--expand: bool]: [nothing -> table, nothing -> table] {
    let sessions = ^tmux list-sessions
        | lines
        | parse "{name}: {windows} windows (created {date}){attached}"
        | into int windows
        | into datetime date
        | update attached {|it| $it.attached != ""}

    if not $expand {
        return $sessions
    }

    # FIXME: complex type annotation, waiting for https://github.com/nushell/nushell/pull/9769
    # let pwds: table<name: string, pwd: path> = ...
    let pwds = ^tmux list-sessions -F '#{session_name}:#{pane_current_path}'
        | lines
        | parse "{name}:{pwd}"
        | update pwd { str replace $nu.home-path '~' }

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

# list opened Tmux sessions
#
# > **Note**  
# > `tmux-sessionizer.nu list-sessions` does not return a table but a raw string: the raw NUON
# > table.
# > to use the output, please pipe the output into `from nuon` to complete the pipeline.
# >
# > related to https://github.com/nushell/nushell/issues/9373
#
# # Examples
#     list the names of all opened sessions
#     > tmux-sessionizer.nu list-sessions | from nuon | get name
#
#     the output table shape
#     > tmux-sessionizer.nu list-sessions | from nuon | describe
#     table<name: string, windows: int, date: date, attached: bool>
#
#     the output table shape in *expanded* mode
#     > tmux-sessionizer.nu list-sessions --expand | from nuon | describe
#     table<name: string, windows: table<id: string, app: string, panes: string, active: bool>, date: date, attached: bool, pwd: string>
def "main list-sessions" [
    --expand: bool  # add more information to the output table, note that this will take more time
]: nothing -> string {
    if $expand {
        list-sessions --expand | to nuon --raw
    } else {
        list-sessions | to nuon --raw
    }
}

# FIXME: complex type annotation, waiting for https://github.com/nushell/nushell/pull/9769
# table<name: string, attached: bool, windows: table<app: string>, pwd: path>
def pick-session-with-style [
    message: string,
    current_session: string,
    session_color: string,
    --multi: bool,
    --expand: bool = false
]: [table -> string, table -> list<string>] {
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

    let choices = if $expand {
        $choices | get name
    } else {
        $choices
    }

    $choices | ansi strip | split column " | " | get column1 | str trim --left --char '*' | str trim
}

# switch to another opened Tmux session
#
# # Examples
#     fuzzy search and attach to a session
#     > tmux-sessionizer.nu switch-session
#
#     fuzzy search and attach to a session with more context
#     > tmux-sessionizer.nu switch-session --expand
#
#     attach to another session directly
#     > tmux-sessionizer.nu switch-session "my_other_session"
#
#     try to attach to a session that does not exist
#     > tmux-sessionizer.nu switch-session "not_a_session"
#     Error:   × invalid_session_name:
#       │                 expected one of [my_session, my_other_session], got not_a_session
def "main switch-session" [
    session?: string  # query as session name to switch to without fuzzy search
    --expand: bool  # use the *expanded* list of sessions for more context
]: nothing -> nothing {
    let session = if $session == null {
        let sessions = if $expand {
            list-sessions --expand
        } else {
            list-sessions
        }
        let current_session = ^tmux display-message -p '#{session_name}' | str trim

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

# open a new Tmux session with a random name and attach to it, from $nu.home-path
def "main new-session" [] {
    let session_name = random uuid
    if not ($session_name in (list-sessions | get name)) {
        ^tmux new-session -ds $session_name -c $nu.home-path
    }
    ^tmux switch-client -t $session_name
}

# remove any number of Tmux sessions
#
# `tmux-sessionizer.nu` will attach to another opened session if the currently attached on is
# removed.
# if all sessions are removed and there is no one to attach, a new random session starting in
# $nu.home-path will be created and attached to.
#
# # Examples
#     remove sessions
#     > tmux-sessionizer.nu remove-sessions
#
#     remove sessions with more context
#     > tmux-sessionizer.nu remove-sessions --expand
def "main remove-sessions" [
    --expand: bool  # use the *expanded* list of sessions for more context
]: nothing -> nothing {
    let sessions = if $expand {
        list-sessions --expand
    } else {
        list-sessions
    }
    let current_session = ^tmux display-message -p '#{session_name}' | str trim

    let prompt = $"(ansi cyan)Please choose sessions to kill(ansi reset)"
    let choices = $sessions
        | pick-session-with-style --expand $expand --multi $prompt $current_session "red"

    if ($choices | is-empty) {
        return
    }

    $sessions | where name in $choices | sort-by attached | each {|session|
        log debug $"killing session '($session.name)'"
        if $session.attached {
            let alive_sessions = $sessions | where name not-in $choices
            if ($alive_sessions | is-empty) {
                main new-session
            } else {
                ^tmux switch-client -t $alive_sessions.0.name
            }
        }
        ^tmux kill-session -t $session.name
    }
}

# manage any Tmux session in a single script
#
# # Examples
#     open a session in a Git repository managed by `nu-git-manager`
#     > tmux-sessionizer.nu (gm list --full-path)
def main [
    ...paths: path,  # the list of paths to fuzzy find and jump to in a new session
] {
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

    let name = $choice | path split | last 2 | path join | str replace --all --string "." "_"

    if ($env.TMUX? | is-empty) and (pgrep tmux | is-empty) {
        ^tmux new-session -s $name -c $choice
        return
    }

    if $name not-in (list-sessions | get name) {
        ^tmux new-session -ds $name -c $choice
    }

    ^tmux switch-client -t $name
}
