#!/usr/bin/env nu

# send a notification with the current date and time
def main [
    --timeout: duration = 3.5sec,
    --icons-dir: path = "/usr/share/icons/goat-icons-git/stickers/100x100/"
    --icon: string = "misc/planner.png"
] {
    let now = date now

    notify-send [
        ($now | format date "%A %B %d %Y")
        ($now | format date "%T")
        --icon $"($icons_dir)/($icon)"
        --expire-time ($timeout | into int | $in / 1e6)
    ]
}
