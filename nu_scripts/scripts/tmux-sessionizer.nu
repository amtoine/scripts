#!/usr/bin/env nu
use std log

# FIXME: complex type annotation, waiting for https://github.com/nushell/nushell/pull/9769
# default: nothing -> table<name: string, windows: int, date: date, attached: bool>
# --more: nothing -> table<name: string, windows: table<id: string, app: string, panes: string, active: bool>, date: date, attached: bool, pwd: string>
def list-sessions [--more: bool]: [nothing -> table, nothing -> table] {
    let sessions = ^tmux list-sessions
        | lines
        | parse "{name}: {windows} windows (created {date}){attached}"
        | into int windows
        | into datetime date
        | update attached {|it| $it.attached != ""}

    if not $more {
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
#     > tmux-sessionizer.nu list-sessions --more | from nuon | describe
#     table<name: string, windows: table<id: string, app: string, panes: string, active: bool>, date: date, attached: bool, pwd: string>
def "main list-sessions" [
    --more (-m): bool  # add more information to the output table, note that this will take more time
]: nothing -> string {
    if $more {
        list-sessions --more | to nuon --raw
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
    --more: bool = false
]: [table -> string, table -> list<string>] {
    let named_sessions = $in | update name {|it| (
            (if $it.name == $current_session { ansi $session_color } else { ansi default })
            ++ (if $it.attached { "* " } else { "  " })
            ++ $it.name
            ++ (ansi reset)
        )}

    let styled_sessions = if $more {
        $named_sessions
            | select name windows.app pwd
            | rename name apps pwd
            | update apps { str join ", " }
            | update pwd {|session|
                $session.pwd | path split | reverse | enumerate | each {|it|
                    if $it.index >= 2 {
                        if ($it.item | str starts-with '.') {
                            $it.item | str substring ..2
                        } else {
                            $it.item | str substring ..1
                        }
                    } else {
                        $it.item
                    }
                } | reverse | path join
            }
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

    let choices = if $more {
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
#     > tmux-sessionizer.nu switch-session --more
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
    --more-context: bool  # use the *expanded* list of sessions for more context
]: nothing -> nothing {
    let session = if $session == null {
        let sessions = if $more_context {
            list-sessions --more
        } else {
            list-sessions
        }
        let current_session = ^tmux display-message -p '#{session_name}' | str trim

        let prompt = $"(ansi cyan)Choose a session to switch to(ansi reset)"
        let choice = $sessions
            | pick-session-with-style --more $more_context $prompt $current_session "yellow"
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

# open a new Tmux session and attach to it
#
# # Examples
#     start a new session with a random name starting in $nu.home-path
#     > tmux-sessionizer.nu new-session
#
#     or equivalently and more explicit
#     > tmux-sessionizer.nu new-session (random uuid) --working-directory $nu.home-path
def "main new-session" [
    name?: string  # the name of the new session, only attach to it if the session already exists (defaults to a random UUID)
    --working-directory (-d): path  # the working directory to start the session in (defaults to $nu.home-path)
]: nothing -> nothing {
    let session_name = $name | default (random uuid)
    if not ($session_name in (list-sessions | get name)) {
        ^tmux new-session -ds $session_name -c ($working_directory | default $nu.home-path)
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
#     > tmux-sessionizer.nu remove-sessions --more-context
def "main remove-sessions" [
    --more-context (-m): bool  # use the *expanded* list of sessions for more context
]: nothing -> nothing {
    let sessions = if $more_context {
        list-sessions --more
    } else {
        list-sessions
    }
    let current_session = ^tmux display-message -p '#{session_name}' | str trim

    let prompt = $"(ansi cyan)Please choose sessions to kill(ansi reset)"
    let choices = $sessions
        | pick-session-with-style --more $more_context --multi $prompt $current_session "red"

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
#
# # Configuration
# - recommended when using a fullscreen window
# `tmux-sessionizer.nu` can be used in a Tmux config as follows:
# ```shell
# TMUX_SESSIONIZER="~/.local/bin/tmux-sessionizer.nu"
# NUSHELL_WITH_ENV="nu --env-config ~/.config/nushell/env.nu --commands"
#
# bind-key -r H new-window "$NUSHELL_WITH_ENV '\
#     use nu-git-manager gm;\
#     $TMUX_SESSIONIZER (gm list --full-path)\
# '"
# bind-key -r N new-window "$TMUX_SESSIONIZER new-session"
# bind-key -r G new-window "$TMUX_SESSIONIZER switch-session --more-context"
# bind-key -r R new-window "$TMUX_SESSIONIZER remove-sessions --more-context"
# ```
#
# - recommended when using a smaller window or a popup
# ```shell
# bind-key -r H display-popup -E "$NUSHELL_WITH_ENV '\
#     use nu-git-manager gm;\
#     $TMUX_SESSIONIZER (gm list --full-path) --short\
# '"
# bind-key -r N run-shell "$TMUX_SESSIONIZER new-session"
# bind-key -r G display-popup -E "$TMUX_SESSIONIZER switch-session"
# bind-key -r R display-popup -E "$TMUX_SESSIONIZER remove-sessions"
# ```
def main [
    ...paths: path,  # the list of paths to fuzzy find and jump to in a new session
    --short (-s): bool  # only show the short session names instead of the full paths
]: nothing -> nothing {
    if ($paths | is-empty) {
        error make --unspanned {
            msg: $"(ansi red_bold)missing_argument_error(ansi reset):
            tmux-sessionizer.nu requires paths as positional arguments"
        }
    }

    let result = if $short {
        let options = $paths
            | wrap path
            | insert key {|it| $it.path | path split | last 2 | path join}

        let choice = $options
            | get key
            | input list --fuzzy $"(ansi cyan)Choose a directory to open a session in(ansi reset)"

        if ($choice | is-empty) {
            return
        }

        {
            name: ($choice | str replace --all --string "." "_")
            path: ($options | where key == $choice | get 0.path)
        }
    } else {
        let choice = $paths
            | input list --fuzzy $"(ansi cyan)Choose a directory to open a session in(ansi reset)"

        if ($choice | is-empty) {
            return
        }

        {
            name: ($choice | path split | last 2 | path join | str replace --all --string "." "_")
            path: $choice
        }
    }

    if ($env.TMUX? | is-empty) and (pgrep tmux | is-empty) {
        ^tmux new-session -s $result.name -c $result.path
        return
    }

    if $result.name not-in (list-sessions | get name) {
        ^tmux new-session -ds $result.name -c $result.path
    }

    ^tmux switch-client -t $result.name
}
