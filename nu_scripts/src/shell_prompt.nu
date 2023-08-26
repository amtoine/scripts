# credit to @Eldyj
# https://discord.com/channels/601130461678272522/615253963645911060/1036225475288252446
# revised by @eldyj in
# https://discord.com/channels/601130461678272522/615253963645911060/1037327061481701468
# revised by @fdncred in
# https://discord.com/channels/601130461678272522/615253963645911060/1037354164147200050
#
# i've fixed a bug when outside `$env.HOME` and refactored the source to use `str`
# subcommands
def spwd [sep?: string] {
    let sep = (if ($sep | is-empty) {
        char path_sep
    } else { $sep })

    let tokens = (
        ["!" $env.PWD] | str join
        | str replace --regex (["!" $nu.home-path] | str join) "~"
        | split row $sep
    )

    $tokens
    | enumerate
    | each {|it|
        $it.item
        | if ($it.index != (($tokens | length) - 1)) {
            str substring (
                if ($it.item | str starts-with '.') { 0..2 } else { 0..1 }
            )
        } else { $it.item }
    }
    | path join
}

def "nu-complete pwd modes" [] {
    [
        [value, description];

        ["full", "e.g. ~/path/to/some/directory"]
        ["spwd", "e.g. ~/p/t/s/directory"],
        ["basename", "e.g. directory"],
    ]
}

export def-env setup [
    --indicators = {}
    --pwd-mode: string@"nu-complete pwd modes" = "full"  # one of spwd, basename or full
] {
    let pwd = match $pwd_mode {
        "spwd" => {{ spwd | str trim }},
        "basename" => {{ $env.PWD | str replace $nu.home-path "~" | path basename }},
        "full" => {{ $env.PWD | str replace $nu.home-path "~" }},
        _ => {
            let span = (metadata $pwd_mode | get span)
            error make {
                msg: $"invalid PWD mode"
                label: {
                    text: $"should be one of (nu-complete pwd modes)"
                    start: $span.start
                    end: $span.end
                }
            }
        },
    }

    $env.PROMPT_COMMAND = {
        let path_segment = if (is-admin) {
            $"(ansi red_bold)(do $pwd)(ansi reset)"
        } else {
            $"(ansi green_bold)(do $pwd)(ansi reset)"
        }

        let is_git_repo = not (
            do --ignore-errors { git rev-parse --is-inside-work-tree } | is-empty
        )
        let branch_segment = if $is_git_repo {
            $"\((ansi yellow_bold)(git branch --show-current | str trim)(ansi reset)\)"
        } else {
            null
        }

        [$path_segment $branch_segment] | compact | str join " "
    }
    $env.PROMPT_COMMAND_RIGHT = ""

    let indicators = {
        plain: "> ",
        vi: {insert: ": ", normal: "> "}
    }
    | merge $indicators

    $env.PROMPT_INDICATOR = $indicators.plain
    $env.PROMPT_INDICATOR_VI_INSERT = $indicators.vi.insert
    $env.PROMPT_INDICATOR_VI_NORMAL = $indicators.vi.normal
}
