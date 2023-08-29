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

# give the revision of the repo given as input
#
# the input repo defaults to the current working directory
#
# in the output, $.type is guaranteed to be one of
# - "branch"
# - "tag"
# - "detached"
#
# # Examples
#     get the revision in another repo
#     > "/some/other/path/" | get-revision
#
#     when on a branch
#     > get-revision, would show the same even if the current branch commit is tagged
#     ╭──────┬────────╮
#     │ name │ main   │
#     │ type │ branch │
#     ╰──────┴────────╯
#
#     when on a tag
#     > get-revision
#     ╭──────┬───────╮
#     │ name │ 0.1.0 │
#     │ type │ tag   │
#     ╰──────┴───────╯
#
#     when the HEAD is detached
#     > get-revision
#     ╭──────┬──────────────────────────────────────────╮
#     │ name │ fa3c06510b3250f4a901db2e9a026a45c971b518 │
#     │ type │ detached                                 │
#     ╰──────┴──────────────────────────────────────────╯
#
#     when the HEAD is detached (short-version)
#     > get-revision --short-hash
#     ╭──────┬──────────╮
#     │ name │ fa3c0651 │
#     │ type │ detached │
#     ╰──────┴──────────╯
#
# true return type: record<name: string, type: string>
def get-revision [
    --short-hash: bool  # print the hash of a detached HEAD in short format
]: path -> record {
    let repo = $in | default $env.PWD

    let tag = do -i {
        git -C $repo describe HEAD --tags
    } | complete
    let is_tag = $tag.exit_code == 0 and (
        $tag.stdout
            | str trim
            | parse --regex '(?<tag>.*)-(?<n>\d+)-(?<hash>[0-9a-fg]+)'
            | is-empty
    )

    let branch = git -C $repo branch --show-current | str trim

    if not ($branch | is-empty) {
        {name: $branch, type: "branch"}
    } else if $is_tag {
        {name: ($tag.stdout | str trim), type: "tag"}
    } else {
        let hash = if $short_hash {
            git -C $repo rev-parse --short HEAD | str trim
        } else {
            git -C $repo rev-parse HEAD | str trim
        }

        {name: $hash, type: "detached"}
    }
}

def "nu-complete pwd modes" [] {
    [
        [value, description];

        ["full", "e.g. ~/path/to/some/directory"]
        ["git", "e.g. ~/path/to/some/directory in a normal directory and directory in a Git repo"],
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
        "git" => {{
            let is_git_repo = not (
                do --ignore-errors { git rev-parse --is-inside-work-tree } | is-empty
            )

            if $is_git_repo {
                $env.PWD | str replace $nu.home-path "~" | path basename
            } else {
                $env.PWD | str replace $nu.home-path "~"
            }
        }},
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
            let revision = get-revision --short-hash
            let color = match $revision.type {
                "branch" => "yellow_bold",
                "tag" => "blue_bold",
                "detached" => "default_dimmed",
            }

            $"\((ansi $color)($revision.name)(ansi reset)\)"
        } else {
            null
        }

        let command_failed_segment = if $env.LAST_EXIT_CODE != 0 {
            $"(ansi red_bold)($env.LAST_EXIT_CODE)(ansi reset)"
        } else {
            null
        }

        [$path_segment $branch_segment $command_failed_segment] | compact | str join " "
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
