#!/usr/bin/env nu

def notify-send [
    title: string, body: string, --urgency: string = "low", --expire-time: int = 10_000
] {
    ^notify-send $title $body --urgency $urgency --expire-time $expire_time
}

def notify-one [notification: record] {
    let title = $"($notification.repository.owner.login)/($notification.repository.name): ($notification.subject.url)"
    let body = $notification.subject.title

    notify-send $title $body
}

def main [--notify]: nothing -> string {
    if $notify {
        notify-send "gh-notifications.nu" "pulling information from the API..."
    }
    let notifications = gh api notifications --jq '.' | from json

    if $notify {
        let n = $notifications | length
        match $n {
            0 => { notify-send "gh-notifications.nu" "no notifications for now..." }
            1 => { notify-one $notifications.0 }
            _ => {
                if $n <= 5 {
                    $notifications | each {|notification| notify-one $notification}
                } else {
                    notify-send "gh-notifications.nu" $"you have ($n) notifications"
                }
            }
        }
    }

    $notifications | to nuon
}
