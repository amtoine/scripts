#!/usr/bin/env nu
const STEP = 5
const ID = 123
const ICONS = "/usr/share/icons/amtoine-icons-git/stickers/100x100/audio/"

def main [] { sound-manager.nu --help }

def "main get-volume" [
    sink?: string = "@DEFAULT_SINK@"
] {
    ^pactl get-sink-volume $sink
        | parse "Volume: {left}, {right}"
        | into record
        | str trim
        | update left { parse "front-left: {volume} / {percentage}% / {decibel}dB" | str trim | into value | into record }
        | update right { parse "front-right: {volume} / {percentage}% / {decibel}dB" | str trim | into value | into record }
}

def "math clamp" [min: float, max: float]: float -> float {
    [$in $min] | math max | [$in $max] | math min
}


def "nu-complete directions" [] {
    ["up", "down"]
}

def "main set-volume" [
    direction: string@"nu-complete directions",
    sink?: string = "@DEFAULT_SINK@"
    --notify
] {
    let delta = match $direction {
        "up" => { $STEP },
        "down" => { $STEP * -1 },
        _ => {
            error make {
                msg: $"(ansi red_bold)invalid_direction(ansi reset)"
                label: {
                    text: $"expected one of (nu-complete directions)"
                    start: (metadata $direction).span.start
                    end: (metadata $direction).span.end
                }
            }
        },
    }

    let volume = main get-volume $sink
    let new_volume = ($volume.left.percentage + $volume.right.percentage) / 2 + $delta
        | math clamp 0 100

    ^pactl set-sink-volume $sink $"($new_volume)%"

    if $notify {
        ^notify-send $"Volume: ($new_volume)" --hint $"int:value:($new_volume)" --replace-id $ID
    }
}

def "main toggle-mute" [
    sink?: string = "@DEFAULT_SINK@"
    --notify
] {
    ^pactl set-sink-mute $sink toggle

    if $notify {
        if (^pactl get-sink-mute "@DEFAULT_SINK@") == "Mute: yes" {
            ^notify-send (^pactl get-default-sink) "Mute" --icon ($ICONS | path join "no-audio.png") --hint int:value:0 --replace-id $ID
        } else {
            ^notify-send (^pactl get-default-sink) "Unmute" --icon ($ICONS | path join "audio.png") --hint $"int:value:(main get-volume | get left.percentage)" --replace-id $ID
        }
    }
}
