#!/usr/bin/env nu
use std log

const ICONS = "/usr/share/icons/goat-icons-git/stickers/100x100"
const DUNST_ID = 5

# set the brightness of XRANDR monitors
def main [
    output: string  # the monitor to change the brightness of
    step: float  # the  brightness step
    --invert (-v) # trigger this option to turn the step into a negative value
    --notify # give a notification
]: nothing -> nothing {
    let monitor = ^xrandr --verbose --current
        | rg $output -A5
        | lines
        | skip 1
        | split column ": "
        | str trim
        | transpose -r
        | into record

    if $monitor == {} {
        let monitors = ^xrandr --query
            | lines
            | find " connected"
            | split column " " monitors
            | get monitors
        let span = metadata $output | get span
        error make {
            msg: $"(ansi red_bold)monitor_not_found(ansi reset)"
            label: {
                text: $"no such monitor reported by xrandr.
        available xrandr monitors: ($monitors | str join ', ')"
                start: $span.start
                end: $span.end
            }
        }
    }

    if $monitor.Brightness? == null {
        let span = metadata $output | get span
        error make {
            msg: $"(ansi red_bold)monitor_not_active(ansi reset)"
            label: {
                text: "looks like this monitor is connected but not active."
                start: $span.start
                end: $span.end
            }
        }
    }

    let brightness = $monitor.Brightness | into float

    let brightness = if $invert {
        $brightness - $step
    } else {
        $brightness + $step
    }
    let brightness = [0.0 $brightness] | math max
    let brightness = [$brightness 1.0] | math min

    log debug $"setting brightness of ($output) to ($brightness | math round --precision 2)"
    xrandr --output $output --brightness $brightness

    if $notify {
        let notification = {
            title: "xrandr-brightness"
            body: $"Brightness ($output)\n($brightness | math round --precision 2)"
            hint: $"int:value:($brightness | math round --precision 2 | $in * 100)"
            icon: ($ICONS | path join "video" "sun.png")
        }
        if not (which dunstify | is-empty) {(
            dunstify $notification.title $notification.body
                --hints $notification.hint
                --urgency low
                --icon $notification.icon
                --replace $DUNST_ID
        )} else {(
            notify-send $notification.title $notification.body
                --hint $notification.hint
                --urgency low
                --icon $notification.icon
        )}
    }
}
