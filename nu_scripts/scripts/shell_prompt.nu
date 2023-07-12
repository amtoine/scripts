def spwd [path: path, sep?: string] {
    let sep = $sep | default (char path_sep)

    let tokens = $"!($path)" | str replace $"!($nu.home-path)" "~" | split row $sep
    let last_token_index = ($tokens | length) - 1

    $tokens | enumerate | each {|token|
        if $token.index != $last_token_index {
            $token.item | str substring (
                if ($token.item | str starts-with '.') { 0..2 } else { 0..1 }
            )
        } else {
            $token.item
        }
    } | path join
}

# credit to @Eldyj
# https://discord.com/channels/601130461678272522/615253963645911060/1036274988950487060
def build-prompt [
    separator: string
    segments: table
] {
    let len = ($segments | length)

    let first = {
      fg: ($segments.0.fg),
      bg: ($segments.0.bg),
      text: $" ($segments.0.text) "
    }

    let tokens = (
        seq 1 ($len - 1)
        | each {|i|
          let sep = {
            fg: ($segments | get ($i - 1) | get bg),
            bg: ($segments | get $i | get bg),
            text: $separator
          }
          let text = {
            fg: ($segments | get $i | get fg),
            bg: ($segments | get $i | get bg),
            text: $" ($segments | get $i | get text) "
          }
          $sep | append $text
        }
        | flatten
    )

    let last = {
        fg: ($segments | get ($len - 1) | get bg),
        bg: '',
        text: $separator
    }

    let prompt = (
        $first |
        append $tokens |
        append $last |
        each {
            |it|
            $"(ansi reset)(ansi -e {fg: $it.fg, bg: $it.bg})($it.text)"
        } |
        str join
    )
    $"($prompt)(ansi reset) "
}


# array without nulls and empty strings
#
# credit to @Eldyj
# https://discord.com/channels/601130461678272522/615253963645911060/1055524399933042738
def clean_list [
    list
    --key (-k): string
] {
    $list | each {|el|
        let val = if not ($key in [null, ""]) {
            $el | get $key
        } else {
            $el
        }

        if not ($val in [null, ""]) {
            $el
        }
    }
}


# TODO: documentation
def create_left_prompt [] {
    let path_segment = if (is-admin) {
        $"(ansi red_bold)(spwd)"
    } else {
        $"(ansi green_bold)(spwd)"
    }

    let branch = do --ignore-errors { git branch --show-current } | str trim

    if $branch == '' {
        $path_segment
    } else {
        $path_segment + $" (ansi reset)\((ansi yellow_bold)($branch)(ansi reset)\)"
    }
}

def external-output [command: closure] {
    do --ignore-errors $command | complete | get stdout | str trim
}

# credit to @Eldyj
# https://discord.com/channels/601130461678272522/615253963645911060/1036274988950487060
def create_left_prompt_eldyj [] {
    let common = [
        [bg fg text];

        ["#BF616A", "#D8DEE9", (if $env.LAST_EXIT_CODE != 0 {char failed})]
        ["#2e3440", "#88c0d0", $env.USER]
        ["#3b4252", "#81a1c1", (spwd)]
    ]

    let segments = if (external-output { git rev-parse --is-inside-work-tree }) == "true" {
        let revision = if (git branch --show-current | is-empty) {
            git rev-parse HEAD | str substring 0..7
        } else {
            git branch --show-current
        }

        $common | append {bg: "#434C5E", fg: "#A3BE8C", text: $revision}
    } else {
        $common
    }

    build-prompt (char nf_left_segment) (clean_list $segments --key text)
}


def color [text: string, color: string] {
    [(ansi $color) $text (ansi reset)] | str join
}

def build_colored_string [separator: string = " "] {
    each {|it| color $it.text $it.color} | str join $separator
}


# TODO: documentation
def create_right_prompt [
  --time: bool
  --cwd: bool
  --repo: bool
  --cfg: bool
] {
    mut prompt = ""

    if ($time) {
        let time_segment = ([
            (date now | date format '%m/%d/%Y %r')
        ] | str join)

        $prompt += (color $time_segment red)
    }

    if ($cwd) {
        $prompt += " "
        $prompt += (color (spwd) green)
    }

    if ($repo) {
        if ((do -i { git branch --show-current } | complete | get stderr) == "") {
            let repo_branch = (git branch --show-current | str trim)
            let repo_commit = (git rev-parse --short HEAD | str trim)
            $prompt += ([[text color];
                [':' 'white_dimmed']
                [$repo_branch 'yellow']
                ['@' 'white_dimmed']
                [$repo_commit 'yellow_bold']
            ]
            | build_colored_string)
        }
    }

    if ($cfg) {
        let cfg_branch = (cfg branch --show-current | str trim)
        let cfg_commit = (cfg rev-parse --short HEAD | str trim)
        $prompt += " "
        $prompt += ([[text color];
            ['(cfg:' 'white_dimmed']
            [$cfg_branch 'red']
            ['@' 'white_dimmed']
            [$cfg_commit 'red_bold']
            [')' 'white_dimmed']
         ]
         | build_colored_string)
    }

    $prompt | str trim
}


# set the left and right prompts of Nushell
export def-env main [
    --no-left-prompt: bool  # disable the left prompt completely
    --use-eldyj-prompt: bool  # use the left prompt of @Eldyj
    --use-right-prompt: bool  # use a right prompt
    --indicators  # manually set indicators (defaults to `{plain: "> ", vi: {insert: ": ", normal: "> "}}`)
] {
    $env.PROMPT_COMMAND = if $no_left_prompt {
        ""
    } else if $use_eldyj_prompt {
        { create_left_prompt_eldyj }
    } else {
        { create_left_prompt }
    }

    $env.PROMPT_COMMAND_RIGHT = if $use_right_prompt {
        { create_right_prompt --cwd --repo --cfg }
    } else {
        ""
    }

    let show_prompt_indicator = not $use_eldyj_prompt or $no_left_prompt

    if $show_prompt_indicator {
        $env.PROMPT_INDICATOR = ""
        $env.PROMPT_INDICATOR_VI_INSERT = ""
        $env.PROMPT_INDICATOR_VI_NORMAL = ""
    } else {
        $env.PROMPT_INDICATOR = $indicators.plain? | default "> "
        $env.PROMPT_INDICATOR_VI_INSERT = $indicators.vi.insert? | default ": "
        $env.PROMPT_INDICATOR_VI_NORMAL = $indicators.vi.normal? | default "> "
    }
}
