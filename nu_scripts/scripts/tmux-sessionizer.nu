#!/usr/bin/env nu
use std log

const TMUX_SESSION_FILE = "/tmp/tmux-session"

$env.LOG_FORMAT = "%ANSI_START%%DATE%|%LEVEL%|%MSG%%ANSI_STOP%"

def save-tmux-session-name [--new-session: string]: nothing -> nothing {
    mkdir ($TMUX_SESSION_FILE | path dirname)

    let current_session = ^tmux display-message -p '#{session_name}' | str trim
    if $current_session != $new_session {
        log debug $"changing session: ($current_session) -> ($new_session)"
        $current_session | save --force $TMUX_SESSION_FILE
    }
}

def switch-to-or-create-session [session: record<name: string, path: path>]: nothing -> nothing {
    save-tmux-session-name --new-session $session.name

    if $session.name not-in (list-sessions | get name) {
        log debug $"creating session ($session.name) at ($session.path)"
        ^tmux new-session -ds $session.name -c $session.path
    }

    log debug $"switching to ($session.name)"
    ^tmux switch-client -t $session.name
}

def spwd []: path -> path {
    str replace --regex $nu.home-path '~' | path split | reverse | enumerate | each {|it|
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

# alternate between the current session and the last one
#
# commands that change the "last session"
# - the sessionizer itself
# - `new-session`
# - `switch-session`
# - `remove-sessions`: this one might not be able to get a valid "last session" if it's getting removed
def "main alternate" []: nothing -> nothing {
    if not ($TMUX_SESSION_FILE | path exists) {
        log debug "no session to alternate with found"
        return
    }

    let previous_session = open $TMUX_SESSION_FILE | str trim
    if $previous_session in (list-sessions | get name) {
        log debug $"alternating ($previous_session)"
        main switch-session $previous_session
    }
}

const TMUX_HARPOON_FILE = "~/.local/state/tmux/harpoon"
const TMUX_HARPOON_SESSION_FORMAT = "{name} {path}"

def clean-lines [] {
    str trim | lines --skip-empty
}

# # Configuration
# ```shell
# TMUX_SESSIONIZER="~/.local/bin/tmux-sessionizer.nu"
# NUSHELL_WITH_ENV="nu --env-config ~/.config/nushell/env.nu --commands"
#
# bind-key -r e display-popup -E "$NUSHELL_WITH_ENV '\
#     $TMUX_SESSIONIZER harpoon edit\
# '"
# bind-key -r j display-popup -E "$TMUX_SESSIONIZER harpoon entries"
# bind-key -r a run-shell "$TMUX_SESSIONIZER harpoon add"
# bind-key -r 1 run-shell "$TMUX_SESSIONIZER harpoon jump 0"
# bind-key -r 2 run-shell "$TMUX_SESSIONIZER harpoon jump 1"
# bind-key -r 3 run-shell "$TMUX_SESSIONIZER harpoon jump 2"
# bind-key -r 4 run-shell "$TMUX_SESSIONIZER harpoon jump 3"
# ```
def "main harpoon" []: nothing -> nothing {
}

# add the current session to the list of harpoons
#
# a session is identified by a name and a path.
# two identical sessions won't be duplicated by `harpoon add`
def "main harpoon add" []: nothing -> nothing {
    let harpoon_file = $TMUX_HARPOON_FILE | path expand

    mkdir ($harpoon_file | path dirname)
    if not ($harpoon_file | path exists) {
        log debug $"creating harpoon file at ($harpoon_file)"
        touch $harpoon_file
    }

    let current_session = [
        (^tmux display-message -p '#{session_name}' | str trim)
        (^tmux display-message -p '#{pane_current_path}' | str trim)
    ] | str join " "

    log debug $"adding ($current_session) to ($harpoon_file)"
    open $harpoon_file | clean-lines | append $current_session | uniq | save --force $harpoon_file
}

# edit the list of sessions with `$env.EDITOR`
def "main harpoon edit" []: nothing -> nothing {
    let harpoon_file = $TMUX_HARPOON_FILE | path expand

    mkdir ($harpoon_file | path dirname)
    if not ($harpoon_file | path exists) {
        log debug $"creating harpoon file at ($harpoon_file)"
        touch $harpoon_file
    }

    log debug $"opening ($harpoon_file) with '($env.EDITOR? | default "")'"
    ^$env.EDITOR $harpoon_file
}

# jump to a harpoon entry without knowing it's index
#
# - if there are no harpoon, an error is thrown
# - if there is a single harpoon, it asks for confirmation and jumps to it
# - if there is more, a fuzzy selector is presented to the user
def "main harpoon entries" []: nothing -> nothing {
    let harpoon_file = $TMUX_HARPOON_FILE | path expand
    if not ($harpoon_file | path exists) {
        log debug $"($harpoon_file) not found, aborting `harpoon entries`"
        return
    }

    let harpoons = open $harpoon_file | clean-lines

    match ($harpoons | length) {
        0 => {
            error make --unspanned { msg: $"(ansi red_bold)no harpoon to jump to(ansi reset)" }
        },
        1 => {
            log debug "harpoon entries: there is a single harpoon"
            let session = $harpoons.0 | parse $TMUX_HARPOON_SESSION_FORMAT | get 0

            let prompt = $"(ansi cyan)Do you want to jump to ($session.name)?(ansi reset)"
            match (["no" "yes"] | input list $prompt) {
                "yes" => { switch-to-or-create-session $session },
                _ => { return },
            }
        },
        _ => {
            log debug "harpoon entries: there are multiple harpoons"
            let options = $harpoons
                | parse $TMUX_HARPOON_SESSION_FORMAT
                | insert pwd {|it| $it.path | spwd}

            let session = $options
                | select name pwd
                | input list $"(ansi cyan)Choose a harpoon to jump to(ansi reset)"

            if ($session | is-empty) {
                return
            }

            switch-to-or-create-session ($options | where name == $session.name | get 0)
        },
    }
}

# jump to a harpoon by id
#
# the $id needs to be between *0* and *#harpoons - 1*
def "main harpoon jump" [
    id: int  # the 0-indexed id of the harpoon to jump to
]: nothing -> nothing {
    let harpoon_file = $TMUX_HARPOON_FILE | path expand
    if not ($harpoon_file | path exists) {
        log debug $"($harpoon_file) not found, aborting `harpoon entries`"
        return
    }

    let harpoons = open $harpoon_file | clean-lines

    if $id < 0 {
        error make --unspanned {
            msg: $"(ansi red_bold)invalid_argument(ansi reset): $id is negative"
        }
    } else if $id > ($harpoons | length) {
        error make --unspanned {
            msg: $"(ansi red_bold)invalid_argument(ansi reset): $id is bigger than the number of harpoons
            expected $id to be between 0 and (($harpoons | length) - 1), found ($id)"
        }
    }

    switch-to-or-create-session ($harpoons | get $id | parse $TMUX_HARPOON_SESSION_FORMAT | get 0)
}

# FIXME: complex type annotation, waiting for https://github.com/nushell/nushell/pull/9769
# default: nothing -> table<name: string, windows: int, date: date, attached: bool>
# --more: nothing -> table<name: string, windows: table<id: string, app: string, panes: string, active: bool>, date: date, attached: bool, pwd: string>
def list-sessions [--more: bool = false]: [nothing -> table, nothing -> table] {
    log debug "listing sessions"
    let sessions = ^tmux list-sessions
        | lines
        | parse "{name}: {windows} windows (created {date}){attached}"
        | into int windows
        | into datetime date
        | update attached {|it| $it.attached != ""}

    if not $more {
        return $sessions
    }

    log debug "adding extra information to the session list"
    # FIXME: complex type annotation, waiting for https://github.com/nushell/nushell/pull/9769
    # let pwds: table<name: string, pwd: path> = ...
    let pwds = ^tmux list-sessions -F '#{session_name}:#{pane_current_path}'
        | lines
        | parse "{name}:{pwd}"

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
    list-sessions --more $more | to nuon --raw
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
            | update pwd { spwd }
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

    let result = $choices
        | ansi strip
        | split column " | "
        | get column1
        | str trim --left --char '*'
        | str trim

    if $multi {
        $result
    } else {
        $result | get 0
    }
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
        let sessions = list-sessions --more $more_context
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

    switch-to-or-create-session { name: $session, path: "" }
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
    switch-to-or-create-session {
        name: ($name | default (random uuid))
        path: ($working_directory | default $nu.home-path)
    }
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
    let sessions = list-sessions --more $more_context
    let current_session = ^tmux display-message -p '#{session_name}' | str trim

    let prompt = $"(ansi cyan)Please choose sessions to kill(ansi reset)"
    let choices = $sessions
        | pick-session-with-style --more $more_context --multi true $prompt $current_session "red"

    if ($choices | is-empty) {
        return
    }

    $sessions | where name in $choices | sort-by attached | each {|session|
        if $session.attached {
            let alive_sessions = $sessions | where name not-in $choices
            if ($alive_sessions | is-empty) {
                main new-session
            } else {
                (tmux display-message
                    -d 5000
                    $"($current_session) has been removed, falling back to ($alive_sessions.0.name)"
                )
                switch-to-or-create-session { name: $alive_sessions.0.name, path: "" }
            }
        }

        log debug $"killing session '($session.name)'"
        ^tmux kill-session -t $session.name
    }

    null
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
            | input list --fuzzy $"(ansi cyan)Choose a project to open a session in(ansi reset)"

        if ($choice | is-empty) {
            return
        }

        {
            name: ($choice | str replace --all "." "_")
            path: ($options | where key == $choice | get 0.path)
        }
    } else {
        let choice = $paths
            | input list --fuzzy $"(ansi cyan)Choose a directory to open a session in(ansi reset)"

        if ($choice | is-empty) {
            return
        }

        {
            name: ($choice | path split | last 2 | path join | str replace --all "." "_")
            path: $choice
        }
    }

    if ($env.TMUX? | is-empty) and (pgrep tmux | is-empty) {
        ^tmux new-session -s $result.name -c $result.path
        return
    }

    switch-to-or-create-session $result
}
