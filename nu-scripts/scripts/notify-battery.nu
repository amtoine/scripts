#!/usr/bin/env nu

const POWER_SUPPLIES = "/sys/class/power_supply/"
const MS_IN_NS = 1e6
const ID = 1000

def "nu-complete batteries" []: nothing -> list<string> {
    ls $POWER_SUPPLIES --short-names | get name
}

# report the status of the battery in a notification
export def main [
    battery: string@"nu-complete batteries" = "BAT0", # the name of the battery
    --min: int = 10, # the minimal value allowed when discharging
    --max: int = 90, # the maximum value allowed when charging
    --timeout: duration = 5sec, # the time before the notification goes away
    --report, # always report, not only when the state of the battery is bad
]: nothing -> nothing {
    let battery_file = $POWER_SUPPLIES | path join $battery

    let status = open ($battery_file | path join "status") | str trim | str downcase
    let level = open ($battery_file | path join "capacity") | str trim | into int

    let args = [
        --urgency critical
        --expire-time ($timeout | into int | $in / $MS_IN_NS)
        --replace-id $ID
    ]

    if ($status == "discharging") and ($level <= $min) {
        ^notify-send $"($battery) is discharging" $level $args
    } else if ($status == "charging") and ($level >= $max) {
        ^notify-send $"($battery) is charging" $level $args
    } else if ($status == "not charging") and ($level >= $max) {
        ^notify-send $"($battery) is full" $level $args
    } else if $report {
        ^notify-send $"($battery) is ($status)" $level ($args | update 1 "normal")
    }
}
