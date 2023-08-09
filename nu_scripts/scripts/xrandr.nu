#!/usr/bin/env nu

# FIXME: complex type annotation
# nothing -> table<name: string, type: string>
def list []: nothing -> table {
    ^xrandr | lines | find ' connected' | split column " " name foo type | reject foo
}

def "nu-complete xrandr list" [] {
    list | where type != "primary" | rename value description
}

export def main [
    external: string@"nu-complete xrandr list"
    --mode: string = "1920x1080"
    --rate: int = 60
]: nothing -> nothing {
    let primary = list | where type == "primary" | get 0.name

    ^xrandr --output $primary --off --output $external --auto --mode $mode --rate $rate
}
