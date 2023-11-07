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

def color [color]: string -> string {
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
#     ╭──────┬──────────────────────────────────────────╮
#     │ name │ main                                     │
#     │ hash │ fa3c06510b3250f4a901db2e9a026a45c971b518 │
#     │ type │ branch                                   │
#     ╰──────┴──────────────────────────────────────────╯
#
#     when on a tag
#     > get-revision
#     ╭──────┬──────────────────────────────────────────╮
#     │ name │ 1.2.3                                    │
#     │ hash │ fa3c06510b3250f4a901db2e9a026a45c971b518 │
#     │ type │ tag                                      │
#     ╰──────┴──────────────────────────────────────────╯
#
#     when the HEAD is detached
#     > get-revision
#     ╭──────┬──────────────────────────────────────────╮
#     │ name │                                          │
#     │ hash │ fa3c06510b3250f4a901db2e9a026a45c971b518 │
#     │ type │ detached                                 │
#     ╰──────┴──────────────────────────────────────────╯
#
#     when the HEAD is detached (short-version)
#     > get-revision --short-hash
#     ╭──────┬──────────╮
#     │ name │          │
#     │ hash │ fa3c0651 │
#     │ type │ detached │
#     ╰──────┴──────────╯
#
# true return type: record<name: string, hash: string, type: string>
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

    let branch = git -C $repo branch --show-current
    let hash = if $short_hash {
        git -C $repo rev-parse --short HEAD | str trim
    } else {
        git -C $repo rev-parse HEAD | str trim
    }

    if not ($branch | is-empty) {
        {name: $branch, hash: $hash, type: "branch"}
    } else if $is_tag {
        {name: ($tag.stdout | str trim), hash: $hash, type: "tag"}
    } else {
        {name: null, hash: $hash, type: "detached"}
    }
}

# https://stackoverflow.com/questions/59603312/git-how-can-i-easily-tell-if-im-in-the-middle-of-a-rebase
def git-action [repo?: path]: nothing -> string {
    let git_dir = ^git -C ($repo | default (pwd)) rev-parse --git-dir | str trim | path expand

    def test-dir [target: string]: nothing -> bool {
        ($git_dir | path join $target | path type) == "dir"
    }

    def test-file [target: string]: nothing -> bool {
        ($git_dir | path join $target | path type) == "file"
    }

    if (test-dir "rebase-merge") {
        if (test-file "rebase-merge/interactive") {
            "REBASE-i" | color blue
        } else {
            "REBASE-m" | color magenta
        }
    } else {
        if (test-dir "rebase-apply") {
            if (test-file "rebase-apply/rebasing") {
                "REBASE" | color cyan
            } else if (test-file "rebase-apply/applying") {
                "AM" | color cyan
            } else {
                "AM/REBASE" | color cyan
            }
        } else if (test-file "MERGE_HEAD") {
            "MERGING" | color dark_gray
        } else if (test-file "CHERRY_PICK_HEAD") {
            "CHERRY-PICKING" | color green
        } else if (test-file "REVERT_HEAD") {
            "REVERTING" | color red
        } else if (test-file "BISECT_LOG") {
            "BISECTING" | color yellow
        } else {
            null
        }
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

export def --env setup [
    --indicators = {
        plain: "> ",
        vi: {insert: ": ", normal: "> "}
    }
    --pwd-mode: string@"nu-complete pwd modes" = "full"  # one of spwd, basename or full
    --duration-threshold: duration = 1sec  # the threshold above which the command duration is shown
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
            let revision = get-revision --short-hash true
            let pretty_branch_tokens = match $revision.type {
                "branch" => [
                    ($revision.name | color {fg: "yellow", attr: "ub"}),
                    ($revision.hash | color "yellow_dimmed")
                ],
                "tag" => [
                    ($revision.name | color {fg: "blue", attr: "ub"}),
                    ($revision.hash | color "blue_dimmed")
                ],
                "detached" => ["_", ($revision.hash | color "default_dimmed")]
            }

            $"\(($pretty_branch_tokens | str join ":")\)"
        } else {
            null
        }

        let git_action_segment = if $is_git_repo {
            let action = (git-action (pwd))
            if $action != null {
                $"\(($action)\)"
            } else {
                null
            }
        } else {
            null
        }

        let command_failed_segment = if $env.LAST_EXIT_CODE != 0 {
            $env.LAST_EXIT_CODE | color "red_bold"
        } else {
            null
        }

        let cmd_duration = $"($env.CMD_DURATION_MS)ms" | into duration
        let duration_segment = if $cmd_duration > $duration_threshold {
            $cmd_duration | color "light_yellow"
        } else {
            null
        }

        let login_segment = if $nu.is-login { "l" | color "cyan" } else { "" }

        [
            $admin_segment
            (do $pwd)
            $branch_segment
            $git_action_segment
            $duration_segment
            $command_failed_segment
            $login_segment
        ]
            | compact
            | str join " "
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
