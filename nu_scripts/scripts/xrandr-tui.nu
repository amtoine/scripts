#!/usr/bin/env nu
const CTRL_C = {code: "c", modifiers: ["control"]}
const CTRL_D = {code: "d", modifiers: ["control"]}

def menu-help [] {
    print ""
    print $"| (ansi blue)decrease(ansi reset) / (ansi red)increase(ansi reset) the brightness by (ansi yellow_bold).1(ansi reset) by hitting (ansi blue)j(ansi reset) / (ansi red)k(ansi reset)"
    print $"| (ansi blue)decrease(ansi reset) / (ansi red)increase(ansi reset) the brightness by (ansi yellow_dimmed).05(ansi reset) by hitting (ansi blue)j(ansi reset) / (ansi red)k(ansi reset) and (ansi yellow_dimmed)control(ansi reset)"
    print $"| (ansi grey)quit(ansi reset) the TUI with (ansi grey)ESC(ansi reset), (ansi grey)ctrl+C(ansi reset) or (ansi grey)ctrl+D(ansi reset)"
    print $"| (ansi green)show this help(ansi reset) with (ansi green)?(ansi reset)"
    print ""
}

export def main [output: string] {
    print ""
    print $"        Welcome to (ansi cyan_bold)Xrandr TUI(ansi reset)"
    print ""
    menu-help

    loop {
        match (input listen --types ["key"]) {
            {code: "?", modifiers: []} => { menu-help },
            {code: "j", modifiers: []} => {
                print $"    (ansi blue)decreasing(ansi reset) brightness of (ansi default_dimmed)($output)(ansi reset) by (ansi yellow_bold).1(ansi reset)"
                xrandr-brightness.nu $output --notify --invert .1
            },
            {code: "j", modifiers: ["control"]} => {
                print $"    (ansi blue)decreasing(ansi reset) brightness of (ansi default_dimmed)($output)(ansi reset) by (ansi yellow_dimmed).05(ansi reset)"
                xrandr-brightness.nu $output --notify --invert .05
            },
            {code: "k", modifiers: []} => {
                print $"    (ansi red)increasing(ansi reset) brightness of (ansi default_dimmed)($output)(ansi reset) by (ansi yellow_bold).1(ansi reset)"
                xrandr-brightness.nu $output --notify .1
            },
            {code: "k", modifiers: ["control"]} => {
                print $"    (ansi red)increasing(ansi reset) brightness of (ansi default_dimmed)($output)(ansi reset) by (ansi yellow_dimmed).05(ansi reset)"
                xrandr-brightness.nu $output --notify .05
            },
            {code: "esc"} | $CTRL_C | $CTRL_D => { break },
            _ => {},
        }
    }

    print ""
    print $"        Bye Bye from (ansi cyan_bold)Xrandr TUI(ansi reset)"
    print ""
}
