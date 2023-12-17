#!/usr/bin/env nu

const STEP = 5
const ID = 456

def main [] { monitor-manager.nu --help }

def "main get-brightness" [output: string]: nothing -> float {
    let res = ^xrandr --verbose --current
        | ^rg $output -A5
        | lines
        | last
        | parse --regex '\s*Brightness: (.*)'
    if $res == null {
        error make --unspanned {
            msg: $"($output) not found in the monitors"
        }
    }

    $res | get capture0.0 | into float | $in * 100
}

def "math clamp" [min: float, max: float]: float -> float {
    [$in $min] | math max | [$in $max] | math min
}


def "nu-complete directions" [] {
    ["up", "down"]
}

def "main set-brightness" [
    output: string,
    direction: string@"nu-complete directions",
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

    let brightness = main get-brightness $output
    let new_brightness = $brightness + $delta | math clamp 0 100

    ^xrandr --output $output --brightness ($new_brightness / 100)

    if $notify {
        ^notify-send $"brightness: ($new_brightness | math round --precision 0)" --hint $"int:value:($new_brightness)" --replace-id $ID
    }
}
