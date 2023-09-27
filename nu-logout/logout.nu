#!/usr/bin/env nu
use std log

let OPTIONS = [
    $"(ansi cyan)Lock screen(ansi reset)"
    $"(ansi yellow)Logout(ansi reset)"
    $"(ansi red)Reboot(ansi reset)"
    $"(ansi red)Shutdown(ansi reset)"
    $"(ansi yellow)Suspend(ansi yellow)"
    $"(ansi green)Quit(ansi reset)"
]

def user-confirmation [cmd: closure, prompt: string]: nothing -> bool {
    (["no" "yes"] | do $cmd $prompt | default "no") == "yes"
}

# a menu to quit the system interactively
def main [
    --lock: string # the application to lock the screen
    --launcher: string  # the app launcher to use as a menu
    --no-confirm (-y) # do not ask for confirmation
    --no-ansi # do not use ANSI colors in the prompts and options
] {
    let cmd: closure = match ($launcher | default "builtin") {
        "builtin" => {{|prompt| input list --fuzzy $prompt }},
        "dmenu" => {{|prompt|  str join "\n" | ^dmenu -p $prompt -l 10 -bw 5 -i | str trim }},
        "fzf" => {{|prompt|  str join "\n" | ^fzf --prompt $prompt | str trim }},
        "rofi" => {{|prompt|  str join "\n" | ^rofi -dmenu -p $prompt | str trim }},
        _ => {
            error make --unspanned {
                msg: $"(ansi red_bold)unknown_app_launcher(ansi reset):
            expected one of ['builtin', 'dmenu', 'fzf', 'rofi], found '($launcher)'"
            }
        }
    }

    let options = if $no_ansi {
        $OPTIONS | ansi strip
    } else {
        $OPTIONS
    }

    let choice = $options | do $cmd $"Please choose an (ansi default_underline)option to run(ansi reset): "
    if ($choice | is-empty) {
        return
    }

    let confirmation_prompt = $"($choice)? "

    match ($choice | ansi strip) {
        "Lock screen" => {
            if $lock == null {
                error make --unspanned {
                    msg: $"(ansi red_bold)`nu-logout` requires `--lock` when trying to lock the screen(ansi reset)"
                }
            }

            if (not $no_confirm) and (not (user-confirmation $cmd $confirmation_prompt)) {
                log debug "User chose not to lock the screen."
                return
            }

            nu --commands $lock
        },
        "Logout" => {
            if (not $no_confirm) and (not (user-confirmation $cmd $confirmation_prompt)) {
                log debug "User chose not to logout."
                return
            }
            pkill -kill -u $env.USER
        },
        "Reboot" => {
            if (not $no_confirm) and (not (user-confirmation $cmd $confirmation_prompt)) {
                log debug "User chose not to reboot."
                return
            }
            systemctl reboot
        },
        "Shutdown" => {
            if (not $no_confirm) and (not (user-confirmation $cmd $confirmation_prompt)) {
                log debug "User chose not to shutdown."
                return
            }
            systemctl poweroff
        },
        "Suspend" => {
            if (not $no_confirm) and (not (user-confirmation $cmd $confirmation_prompt)) {
                log debug "User chose not to suspend."
                return
            }
            systemctl suspend
        },
        "Quit" => { return },
        _ => {
            error make --unspanned {
                msg: $"Unknown choice '($choice)'"
            }
        }
    }
}
