use prompt.nu

# TODO
export def yt-dl-names [
    --id (-i): string  # the id of the playlist
    --channel (-c): string  # the id of the channel
    --path (-p): string = .  # the path where to store to final `.csv` file
    --all (-a)  # download all the playlists from the channel when raised
] {
    let format = '"%(playlist)s",%(playlist_id)s,%(playlist_index)s,"%(uploader)s","%(title)s",%(id)s'

    let url = if $all {
        $"https://www.youtube.com/channel/($channel)/playlists"
      } else {
        $"https://www.youtube.com/playlist?list=($id)"
    }

    if (ls | find $path | is-empty) {
        mkdir $path
    }
    let file = ($path | path join $"($id).csv")

    print $"Downloading from '($url)' to ($file)..."

    (youtube-dl
        -o $format
        $url
        --get-filename
        --skip-download
        --verbose
    ) |
    from csv --noheaders |
    rename playlist "playlist id" "playlist index" uploader title id |
    insert url {
        |it|
        $'https://www.youtube.com/watch?v=($it.id)&list=($it."playlist id")'
    } |
    save $file
}


# Asks for an entry name in a password store and opens the store.
#
# Uses $env.PASSWORD_STORE_DIR as the store location, asks for
# a passphrase with pinentry-gtk and copies the credentials to
# the system clipboard..
export def pass-menu [
    --path (-p): string = "/usr/share/rofi/themes/"  # the path to the themes (default to '/usr/share/rofi/themes/')
    --theme (-t): string = "sidebar"  # the theme to apply (defaults to 'sidebar')
    --list-themes (-l)  # list all available themes in --path
] {
    if ($list_themes) {
        ls $path |
            select name |
            rename theme |
            str replace --regex $"^($path)" "" theme |
            str replace --regex ".rasi$" "" theme
    } else {
        let entry = (
            ls $"($env.PASSWORD_STORE_DIR)/**/*" |
            where type == file |
            select name |
            str replace --regex $"^($env.PASSWORD_STORE_DIR)/" "" name |
            str replace --regex ".gpg$" "" name |
            to csv |
            rofi -config $"($path)($theme).rasi" -show -dmenu |
            str trim
        )

        if not ($entry | is-empty) {
            pass show $entry -c
            dunstify $entry "Copied to clipboard for 45 seconds."
        } else {
            print "User choose to exit..."
        }
    }
}


# TODO
export def alarm [
    time: string
    message: string
] {
    termdown -e $time --title $message
    dunstify "termdown" $message --urgency critical --timeout 0
    print $message
}


# TODO
def get-aoc-header [
  login: string
] {
  let aoc_login = (
    gpg --quiet --decrypt ($login | path expand)
    | from toml
  )
  let header = [
    Cookie $'session=($aoc_login.cookie)'
    User-Agent $'email: ($aoc_login.mail)'
  ]

  $header
}


# TODO
#
# encryption:
# ```bash
# > gpg --symmetric --armor --cipher-algo <algo> <file>
# ```
#
# example login file:
# ```toml
# cookie = "my-cookie: see https://github.com/wimglenn/advent-of-code-wim/issues/1"
# mail = "my_mail@domain.foo"
# ```
#
export def "aoc fetch input" [
  day: int
  login: string
] {
  let url = $'https://adventofcode.com/2022/day/($day)/input'

  http get -H (get-aoc-header $login) $url
}


# TODO
export def "aoc fetch answers" [
  day: int
  login: string
] {
  let url = $'https://adventofcode.com/2022/day/($day)'

  let result = (http get -H (get-aoc-header $login) $url)
  let answers = (
    $result
    | lines
    | parse "<p>Your puzzle answer was <code>{answer}</code>{rest}"
  )

  if ($answers | is-empty) {
    $result | str trim
  } else {
    {
      silver: $answers.answer.0
      gold: $answers.answer.1
    }
  }
}


# TODO: docstring
export def --env back [] { cd - }


# TODO: docstring
export def "get ldd deps" [exec: string] {
    let bin = (which $exec)
    if ($bin | is-empty) {
        print $"could not find ($exec) in PATH..."
        return
    }

    ldd ($bin | get path)
    | lines
    | parse '{lib} ({addr})'
    | str trim
    | update lib {|it|
        let tokens = ($it.lib | parse "{lib} => {symlink}")
        if ($tokens | is-empty) {
            {
                lib: $it.lib
                symlink: null
            }
        } else {
            $tokens
        }
    }
    | flatten --all
}


# TODO: docstring
export def "open pdf" [
    ...from: path
    --launcher: string = "okular"
    --no-swallow
    --swallower: string = "devour"
] {
    let from = if $from == [] {
        [$env.XDG_DOCUMENTS_DIR $env.XDG_DOWNLOAD_DIR]
    } else {
        $from
    }

    let choices = $from
        | each { try { ls ($in | path join "**" "*.pdf") } }
        | flatten
        | get name

    if ($choices | is-empty) {
        error make --unspanned {
            msg: $"no PDF file found in ($from | str join ', ')"
        }
    }

    let choice = $choices | input list --fuzzy "What PDF to open? "
    if ($choice | is-empty) {
        print "user chose to exit..."
        return
    }

    if $no_swallow {
        ^$launcher $choice
    } else {
        ^$swallower $launcher $choice
    }
}


# TODO: docstring
# credit to @fdncred
# https://discord.com/channels/601130461678272522/615253963645911060/1071893062864863293
export def "history stats" [
    --summary (-s): int = 5
    --last-cmds (-l): int
    --verbose (-v)
] {
    let top_commands = (
        history
        | if ($last_cmds != null) { last $last_cmds } else { $in }
        | get command
        | split column ' ' command
        | uniq -c
        | flatten
        | sort-by --reverse count
        | first $summary
    )

    if ($verbose) {
        let total_cmds = (history | length)
        let unique_cmds = (history | get command | uniq | length)

        print $"(ansi green)Total commands in history:(ansi reset) ($total_cmds)"
        print $"(ansi green)Unique commands:(ansi reset) ($unique_cmds)"
        print ""
        print $"(ansi green)Top ($top_commands | length)(ansi reset) most used commands:"
    }

    $top_commands
}


# TODO
# credit to @fdncred
# https://discord.com/channels/601130461678272522/615253963645911060/1072286261873741854
export def "history search" [
    str: string = '' # search string
    --cwd(-c) # Filter search result by directory
    --exit(-e): int = 0 # Filter search result by exit code
    --before(-b): datetime = 2100-01-01 #  Only include results added before this date
    --after(-a): datetime = 1970-01-01 # Only include results after this date
    --limit(-l): int = 25 # How many entries to return at most
] {
    history
    | where start_timestamp != ""
    | update start_timestamp {|r| $r.start_timestamp | into datetime}
    | where command =~ $str and exit_status == $exit and start_timestamp > $after and start_timestamp < $before
    | if $cwd { where cwd == $env.PWD } else { $in }
    | first $limit
}


# TODO: docstring
export def "get wallpapers" [
  nb_wallpapers: int
  --shuffle (-s)
] {
    [
        /usr/share/backgrounds
        ($env.GIT_REPOS_HOME | path join "github.com/amtoine/wallpapers/wallpapers")
    ]
    | each {||
        let glob_path = ($in | path join "*")
        glob --no-dir $glob_path
    }
    | flatten
    | if ($shuffle) { shuffle } else { $in }
    | take $nb_wallpapers
}

# TODO: docstring
export def "glow wide" [file: string] {
    ^glow --pager --width (term size | get columns) $file
}


# TODO: docstring
export def "youtube share" [
    url: string
    --pretty
    --clip (-c)
] {
    let video = (
        http get $url
        | str replace --regex --all "<" "\n<"  # separate all HTML blocks into `<...> ...` chunks without the closing `</...>`
        | str replace --regex --all "</.*>" ""
        | lines
        | find "var ytInitialPlayerResponse = "  # all the data is located in this JSON structure...
        | parse --regex 'var ytInitialPlayerResponse = (?<data>.*);'
        | get data.0
        | from json
        | get microformat.playerMicroformatRenderer  # ...and more specifically in this subfield
        | select embed.iframeUrl uploadDate ownerChannelName lengthSeconds title.simpleText  # select the most usefull fields
        | rename url date author length title
        | update length {|it| [$it.length "sec"] | str join | into duration}  # udpate some of the fields for clarity
        | update date {|it| $it.date | into datetime}
        | update url {|it|
            $it.url
            | url parse
            | reject query params
            | update path {|it| $it.path | str replace --regex "/embed/" ""}
            | update host youtu.be
            | url join
        }
    )

    if $pretty {
        let link = $"[*($video.title)*](char lparen)($video.url)(char rparen)"

        if not $clip {
            return $link
        }

        $link | clip
        return
    }

    if not $clip {
        return $video
    }

    $video.url | clip

}


# TODO: docstring
export def "list todos" [] {
    ^rg "//.? ?TODO" . -n
    | lines
    | parse "{file}:{line}:{match}"
    | try {
        group-by file
        | transpose
        | reject column1.file
        | transpose -rid
    } catch {
        "no TODOs found in this directory"
    }
}

# TODO: docstring
export def "cargo list" [] {
    ^cargo install --list
        | lines
        | str replace --regex '^(\w)' "\n${1}"
        | str join
        | lines | skip 1
        | parse --regex '(?<pkg>.*) v(?<version>\d+\.\d+\.\d+)(?<path>.*):(?<bins>.*)'
        | str trim
        | update bins {|it| $it.bins | str replace --regex '\s+' ' ' | split row ' '}
        | update path {|it| $it.path | str replace '(' '' | str replace --regex '\)' ''}
}


# TODO: docstring
export def "watch cpu" [nb_loops = -1] {
    let name = $in

    mut i = 0
    loop {
        ps | where name == $name | try { math sum | get cpu }

        $i += 1
        if ($nb_loops > 0) and ($i >= $nb_loops) {
            break
        }
    }
}


# TODO: docstring
export def "cargo info full" [
    crate: string
] {
    cargo info $crate
    | lines
    | parse "{key}: {value}"
    | str trim
    | transpose -r
    | into record
    | merge ({
        versions: (
            cargo info $crate -VV
            | lines -s
            | skip 1
            | parse --regex '(?<version>\d+\.\d+\.\d+)\s+(?<released>.* ago)\s+(?<downloads>\d+)'
            | into int downloads
        )
    })
}


def "qutebrowser list sessions" [] {
    ls ($env.XDG_DATA_HOME | path join "qutebrowser" "sessions")
    | get name
    | path parse
    | where extension == "yml"
    | get stem
}


# TODO: docstring
export def "qutebrowser open" [session: string = ""] {
    let session = if ($session | is-empty) {
        qutebrowser list sessions
        | to text
        | fzf
        | str trim
    } else {
        $session
    }

    if ($session | is-empty) {
        return
    }

    qutebrowser $":session-load ($session)" --target window
}


# TODO: docstring
export def "qutebrowser import" [] {
    let session = $in

    $session
    | open --raw
    | save --force ($env.XDG_DATA_HOME
    | path join "qutebrowser" "sessions" $session)
}


# TODO: docstring
export def "qutebrowser export" [session: string = ""] {
    let session = if ($session | is-empty) {
        qutebrowser list sessions
        | to text
        | fzf
        | str trim
    } else {
        $session
    }

    if ($session | is-empty) {
        return
    }

    $env.XDG_DATA_HOME
    | path join "qutebrowser" "sessions" $session
    | path parse
    | update extension yml
    | path join
    | open --raw
}


# TODO: docstring
export def "into hex" [] {
    fmt | get lowerhex
}


# Execute conditional pipelines depending on the previous command output.
#
# see https://discord.com/channels/601130461678272522/615253963645911060/1086437351598870689
#
# Examples:
#     >_ 1 == 1 | pipeif true | "OMG 1 is equal to 1"
#     OMG 1 is equal to 1
#
#     >_ 1 != 1 | pipeif true | "This message will never be printed"
#     Error:
#       × Breaking pipeline: conditional execution aborted
#
#     >_ [7 3 4 9] | find 7 3 | pipeif [7 3] | "Found numbers 7 and 3"
#     Found numbers 7 and 3
#
#     >_ [7 3 4 9] | find 3 5 | pipeif [3 5] | "This message will never be printed"
#     Error:
#       × Breaking pipeline: conditional execution aborted
export def pipeif [
    expected: any  # Expected value to not break the pipeline
    --invert (-v)
] {
    let value = $in

    let condition = (if $invert {
        ($value | sort) == ($expected | sort)
    } else {
        ($value | sort) != ($expected | sort)
    })

    if $condition {
        error make --unspanned {
            msg: "Breaking pipeline: conditional execution aborted"
        }
    }

    return $value
}


# TODO
def "nu-complete list-images" [] {
    ls ($env.XDG_PICTURES_HOME | path join "**" "*") | get name
}

def get-image [
    image: path
] {
    let image = (if ($image | is-empty) {
         nu-complete list-images | to text | fzf | str trim
    } else { $image })

    if ($image | is-empty) {
        error make --unspanned {
            msg: "no image selected"
        }
    }

    return $image
}

# TODO
export def "images edit" [
    image?: path@"nu-complete list-images"
    --editor: string = kolourpaint
    --devour (-d)
] {
    let image = (get-image $image)

    if $devour {
        devour $editor $image
    } else {
        ^$editor $image
    }
}

# TODO
export def "images view" [
    image?: path@"nu-complete list-images"
    --viewer: string = feh
] {
    ^$viewer (get-image $image)
}


def _throw-not-a-list-of-strings [files: any] {
    error make --unspanned {
        msg: $'please give a list of strings to `(ansi default_dimmed)(ansi default_italic)edit(ansi reset)`
=> found `(ansi default_dimmed)(ansi default_italic)($files | describe)(ansi reset)`
    ($files | table | lines | each {|file| $"($file)" } | str join "\n    ")'
    }
}

export def edit [
    ...rest: path
    --no-auto-cmd (-n)
    --auto-cmd: string
    --projects (-p)
] {
    let files = $in | default []
    if (not ($files | is-empty)) and (($files | describe) != "list<string>") {
        _throw-not-a-list-of-strings $files
    }

    let files = $rest | append $files | uniq

    if ($files | is-empty) {
        ^$env.EDITOR -c (
            if $no_auto_cmd {
                ""
            } else if $projects {
                "lua require('telescope').extensions.projects.projects{}"
            } else {
                $auto_cmd | default (
                    if (".git/" | path exists) {
                        "lua require('telescope.builtin').git_files()"
                    } else {
                        "lua require('telescope.builtin').find_files()"
                    }
                )
            }
        )

        return
    }

    ^$env.EDITOR $files
}

export def rg [
    pattern: string
    path?: path
    --files
] {
    let matches = (
        ^rg $pattern ($path | default "." | path expand)
        | lines
        | parse "{file}:{match}"
    )

    if $files {
        return ($matches | get file | uniq)
    }

    $matches
}

export def "hash dir" [directory: path] {
    if ($directory | path type) != "dir" {
        let span = (metadata $directory | get span)
        error make {
            msg: $"(ansi red_bold)not_a_directory(ansi reset)"
            label: {
                text: $"expected a directory, found a ($directory | path type)"
                start: $span.start
                end: $span.end
            }
        }
    }

    ls ($directory | path join "**" "*") | where type == file | each {
        get name | open --raw | hash sha256
    }
    | str join
    | hash sha256
}

# compute the merkle tree of a sequence of tokens
export def "hash merkle" [
    --last
    --pretty
] {
    let tokens = $in

    let nb_steps = ($tokens | length | math log 2)
    if $nb_steps mod 1 != 0 {
        error make --unspanned {
            msg: $"(ansi red_bold)invalid_argument(ansi reset): there should be a power of 2 tokens, found ($tokens | length)"
        }
    }

    let all_hashes = (
        seq 1 $nb_steps | reduce -f [($tokens | each { hash sha256 })] {|it, acc|
            [($acc | first | group 2 | each { str join | hash sha256 })] | append $acc
        }
    )

    if $last {
        return ($all_hashes.0.0)
    }

    $all_hashes | if $pretty { each { each { str substring 0..7 } } } else { $in } | reverse
}

# test
def hash-merkle [] {
    use std assert

    assert equal ([foo bar baz foooo] | hash merkle) [
        [
            2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae,
            fcde2b2edba56bf408601fb721fe9b5c338d10ee429ea04fae5511b68fbf8fb9,
            baa5a0964d3320fbc0c6a922140453c8513ea24ab8fd0577034804a967248096,
            440d25b8ad0abf5db0f9940dd749434f9267c0f699b57f0c68d4134ad90d4ae9
        ],
        [
            ec321de56af3b66fb49e89cfe346562388af387db689165d6f662a3950286a57,
            eb8744e2fc92ff512d96a5cf731412c254b895ae85f31c75cd08511de3a4a2d8
        ],
        [
            63ab1f8440bd551f46f58651d3390650fdeb1c63c70957ee529dc17f087638be
        ]
    ]

    assert error {|| [foo bar baz] | hash merkle}
}

# downloads reveal.js in a local directory
export def "reveal.js download" [
    destination: path  # the path to the local project
] {
    let dump_dir = ($nu.temp-path | path join "reveal.js" (random uuid))
    let archive = ($dump_dir | path join "master.zip")

    mkdir $dump_dir
    http get https://github.com/hakimel/reveal.js/archive/master.zip | save $archive

    unzip $archive -d $dump_dir

    mkdir $destination
    cp --recursive --progress ($dump_dir | path join "reveal*" "*") $destination
}

# a wrapper around `nmap` to scan a local network for hosts
#
# # Example:
#     > scan lan 192.***.***
#     Scanning hosts connected locally to 192.168.***.0/24...
#     ╭─────────┬──────────────────────────────────────────────────────────────────╮
#     │ header  │ Starting Nmap 7.80 ( https://nmap.org ) at 2023-07-25 15:43 CEST │
#     │         │ ╭───┬────────────────────────────────┬───────┬──────────╮        │
#     │ scans   │ │ # │               ip               │ state │ latency  │        │
#     │         │ ├───┼────────────────────────────────┼───────┼──────────┤        │
#     │         │ │ 0 │ ************* (192.168.***.**) │ up    │ 0.00017s │        │
#     │         │ │ 1 │ ******** (192.168.***.***)     │ up    │ 0.015s   │        │
#     │         │ ╰───┴────────────────────────────────┴───────┴──────────╯        │
#     │ summary │ Nmap done: 256 IP addresses (2 hosts up) scanned in 6.91 seconds │
#     ╰─────────┴──────────────────────────────────────────────────────────────────╯
#
# FIXME:
# true return type (should be addressed by https://github.com/nushell/nushell/pull/9769):
# record<
#     header: string,
#     scans: table<ip: string, state: string, latency: string>,
#     summary: string
# >
def "scan lan" [
    base_ip: string = "192.168.1"  # the base IP to look for host, ($base_ip).0/24
]: nothing -> record {
    print $"Scanning hosts connected locally to (ansi default_italic)($base_ip).0/24(ansi reset)..."
    let results = ^nmap -sP $"($base_ip).0/24" | lines

    {
        header: ($results | first 1 | to text | str trim)
        scans: (
            $results
            | skip 1
            | reverse
            | skip 1
            | reverse
            | group 2
            | each {|host| {
                ip: ($host.0 | parse "Nmap scan report for {ip}" | get ip.0)
                state: ($host.1 | parse "Host is {state} ({latency} latency).")
            }}
            | flatten --all
        )
        summary: ($results | last 1 | to text | str trim)
    }
}

# FIXME: waiting for https://github.com/nushell/nushell/pull/9769
# record<variables: record, profiles: table>
export def "ssh profiles" [--config: path = "~/.ssh/config"]: nothing -> record {
    let groups = open --raw $config
        | str replace --regex --all 'Host ' "\nHost "
        | lines
        | split list ""

    let variables = $groups
        | where {|group| not ($group.0 | str starts-with "Host ")}
        | flatten
        | parse "{key} {value}"
        | transpose --header-row
        | into record

    let profiles = $groups
        | where {|group| $group.0 | str starts-with "Host "}
        | each {|group|
            $group
                | skip 1
                | str trim
                | parse "{key} {value}"
                | transpose --header-row
                | into record
                | merge ($group.0 | parse "Host {Host}" | get 0)
        }

    {
        variables: $variables
        profiles: $profiles
    }
}

# show the tree structure of a directory
#
# # Examples
# ```nushell
# # compute the tree with a max depth of 2
# tree . --depth 2
# ```
# ---
# ```
# ───────────────────┬───────────────────
# CODE_OF_CONDUCT.md │CODE_OF_CONDUCT.md
# CONTRIBUTING.md    │CONTRIBUTING.md
# Cargo.lock         │Cargo.lock
# Cargo.toml         │Cargo.toml
# Cross.toml         │Cross.toml
# LICENSE            │LICENSE
# README.md          │README.md
# assets             │{record 3 fields}
# benches            │{record 2 fields}
# crates             │{record 39 fields}
# devdocs            │{record 5 fields}
# docker             │{record 1 field}
# rust-toolchain.toml│rust-toolchain.toml
# scripts            │{record 12 fields}
# src                │{record 10 fields}
# target             │{record 4 fields}
# tests              │{record 15 fields}
# toolkit.nu         │toolkit.nu
# typos.toml         │typos.toml
# wix                │{record 3 fields}
# ───────────────────┴───────────────────
# ```
export def tree [
    p: path = '.', # the root of the tree
    --full-path (-f), # show the path as absolute instead of relative to the root of the tree
    --depth (-d): int, # the depth at which to step building the tree, defaults to bottom of filesystem
]: [ nothing -> record ] {
    def aux [c: path, r: path, d: int]: [ nothing -> record ] {
        if $depth != null and $d == $depth {
            return
        }

        let level = ls $c | insert . { |it|
            if $it.type == file {
                if $full_path {
                    $it.name
                } else {
                    $it.name | str replace $"($r)(char path_sep)" ''
                }
            } else {
                aux $it.name $r ($d + 1)
            }
        }

        $level
            | select name .
            | update name { path parse | update parent '' | path join }
            | transpose --header-row
            | into record
    }

    if not ($p | path exists) {
        error make {
            msg: $"(ansi red_bold)no_such_file_or_directory(ansi reset)",
            label: {
                text: "no such file or directory",
                span: (metadata $p).span,
            },
        }
    }

    # NOTE: expand to remove potential trailing path separator
    let p = $p | path expand

    aux $p $p 0
}
