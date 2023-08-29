def simplify-path []: path -> string {
    str replace $nu.home-path "~" | str replace --regex '^/' "!/"
}

def spwd [] {
    $env.PWD
        | simplify-path
        | path split
        | reverse
        | enumerate
        | each {|it|
            if $it.index != 0 {
                $it.item | str substring (
                    if ($it.item | str starts-with '.') { 0..2 } else { 0..1 }
                )
            } else {
                $it.item
            }
        }
        | reverse
        | path join
}

def color [color: string]: string -> string {
    $"(ansi $color)($in)(ansi reset)"
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
    --indicators = {
        plain: "> ",
        vi: {insert: ": ", normal: "> "}
    }
    --pwd-mode: string@"nu-complete pwd modes" = "full"  # one of spwd, basename or full
] {
    let pwd = match $pwd_mode {
        "spwd" => {{ spwd | color "green" }},
        "git" => {{
            let is_git_repo = not (
                do --ignore-errors { git rev-parse --is-inside-work-tree } | is-empty
            )

            let pwd = $env.PWD | simplify-path

            if $is_git_repo {
                $pwd | path basename | color "magenta_bold"
            } else {
                $pwd | color "green"
            }
        }},
        "basename" => {{ $env.PWD | simplify-path | path basename | color "green" }},
        "full" => {{ $env.PWD | simplify-path | color "green" }},
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
        let admin_segment = if (is-admin) {
            "!!" | color "red_bold"
        } else {
            null
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

            $"\(($revision.name | color $color)\)"
        } else {
            null
        }

        let command_failed_segment = if $env.LAST_EXIT_CODE != 0 {
            $env.LAST_EXIT_CODE | color "red_bold"
        } else {
            null
        }

        [$admin_segment (do $pwd) $branch_segment $command_failed_segment] | compact | str join " "
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
