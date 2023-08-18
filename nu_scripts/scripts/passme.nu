#!/usr/bin/env nu

# a dmenu wrapper around the pass password-manager
#
# > **Warning**  
# > the `--type` option from the Bash implementation is not supported
#
# from https://git.zx2c4.com/password-store/tree/contrib/dmenu/passmenu
# > `passmenu` is a [dmenu][]-based interface to [pass][], the standard Unix
# > password manager. This design allows you to quickly copy a password to the
# > clipboard without having to open up a terminal window if you don't already have
# > one open. If `--type` is specified, the password is typed using [xdotool][]
# > instead of copied to the clipboard.
# >
# > On wayland [dmenu-wl][] is used to replace dmenu and [ydotool][] to replace xdotool.
# > Note that the latter requires access to the [uinput][] device, so you'll probably
# > need to add an extra udev rule or similar to give certain non-root users permission.
# >
# > # Usage
# >
# >     passmenu [--type] [dmenu arguments...]
# >
# > [dmenu]: http://tools.suckless.org/dmenu/
# > [xdotool]: http://www.semicomplete.com/projects/xdotool/
# > [pass]: http://www.zx2c4.com/projects/password-store/
# > [dmenu-wl]: https://github.com/nyyManni/dmenu-wayland
# > [ydotool]: https://github.com/ReimuNotMoe/ydotool
# > [uinput]: https://www.kernel.org/doc/html/v4.12/input/uinput.html
extern-wrapped main [
    --help (-h): bool  # Display the help message for this command
    --notify: bool  # Throw a notification once an entry has been pasted
    ...dmenu_args: string  # The arguments to dmenu
] {
    let password_store = $env.PASSWORD_STORE_DIR? | default "~/.password-store/"

    let dmenu = if $env.WAYLAND_DISPLAY? != null {
        "dmenu-wl"
    } else if $env.DISPLAY? != null {
        "dmenu"
    } else {
        error make --unspanned {
            msg: $"(ansi red_bold)No Wayland or X11 display detected(ansi reset)"
        }
    }

    let choice = ls ($password_store | path join "**" "*.gpg")
        | get name
        | path parse
        | update extension ""
        | path join
        | str replace --regex $password_store ""
        | str replace --regex '^/' ""
        | to text
        | ^$dmenu $dmenu_args
        | str trim

    if ($choice | is-empty) {
        print "User chose to exit"
        return
    }

    pass show --clip $choice

    if $notify {
        notify-send "passmenu" $"($choice) has been copied"
    }
}
