#!/usr/bin/env nu

def main [--notify: bool]: [nothing -> nothing, nothing -> table] {
    if $notify {
        notify-send "gh-notifications.nu" "pulling information from the API..." --expire-time 10000
    }
    let notifications = gh api notifications --jq '.' | from json

    if ($notifications | is-empty) {
        if $notify {
            notify-send "gh-notifications.nu" "no notifications for now..." --urgency low --expire-time 10000
        } else {
        }
        return
    }

    $notifications | each {|notification|
        let title = $"($notification.repository.owner.login)/($notification.repository.name): ($notification.subject.url)"
        let body = $notification.subject.title

        if $notify {
            notify-send $title $body --urgency low --expire-time 10000
        }
    }

    if not $notify {
        $notifications
    }
}
