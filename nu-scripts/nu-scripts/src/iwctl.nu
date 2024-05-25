const IWCTL_HEADER_SIZE = 4
const ANSI_MARKER = 0x[1b]

def get-table-without-header []: string -> list<string> {
    lines
        | skip $IWCTL_HEADER_SIZE
        | where not ($it | is-empty)
        | str replace --all --regex '\s+' ' '
        | each { str trim }
}

def get-devices []: nothing -> list<string> {
    iwctl device list
        | ansi strip
        | get-table-without-header
        | parse "{name} {address} {powered} {adapter} {mode}"
        | each {{
            value: $in.name,
            description: $"($in.address) ($in.powered) ($in.adapter) ($in.mode)",
        }}
}

# list available networks for a given station
#
# # Example
# ```nushell
# # list all networks for station wlan0
# iwctl list-networks --station wlan0
# ```
#
# ```nushell
# # list networks whose name match 'foo' for station wlan0
# iwctl list-networks --station wlan0 --pattern foo
# ```
#
# ```nushell
# # list networks whose signal are greater or equal to 3 for station wlan0
# iwctl list-networks --station wlan0 --signal 3
# ```
export def list-networks [
    --station: string@get-devices # the station to connect to a network
    --pattern: string # a pattern to filter networks by name
    --signal: int = 1 # a minimum signal level that the network should have, from 1 to 4
]: [nothing -> record<
    station: string,
    networks: table<name: string, security: string, signal: int, connected: bool>
>] {
    if $station == null {
        error make --unspanned { msg: "please provide `--station`" }
    }
    if $signal < 0 or $signal > 4 {
        error make {
            msg: $"(ansi red_bold)invalid signal(ansi reset)",
            label: {
                text: $"should be between 0 and 4, found ($signal)",
                span: (metadata $signal).span,
            },
        }
    }

    print $"scanning station (ansi cyan)($station)(ansi reset)"
    iwctl station $station scan

    let networks = iwctl station $station get-networks
        | get-table-without-header
        | wrap x
        | insert signal {|it|
            let pos =  $it.x | into binary | bytes index-of $ANSI_MARKER
            let y = if $pos > 0 {
                $it.x | into binary | bytes at 0..<$pos | decode
            } else {
                $it.x
            }
            $y | split chars | uniq --count | transpose --header-row | into record | get *?
        }
        | update x { ansi strip | str trim | str replace --regex '\s*\*+$' '' }
        | insert connected { get x | str starts-with '>' }
        | update x { str replace '>' '' | str trim }
        | update x { parse --regex '(?<name>.*) (?<security>\w+)' | into record }
        | flatten
        | where name =~ ($pattern | default "") and signal >= $signal

    {
        station: $station,
        networks: $networks,
    }
}

# connect to a network
#
# > **Note**
# > this command is best used in conjunction with [`iwctl list-networks`]
#
# # Example
# ```nushell
# # use `iwctl list-networks` for station wlan0
# iwctl list-networks --station wlan0 | iwctl connect
# ```
export def connect []: [
    record<
        station: string,
        networks: table<name: string, security: string, signal: int, connected: bool>
    > -> nothing
] {
    let input = $in
    let choice = $input.networks | input list --fuzzy "please choose a network to connect to"
    if $choice == null {
        return
    }

    let network = $choice.name

    print $"connecting to (ansi yellow)($network)(ansi reset) on (ansi cyan)($input.station)(ansi reset)..."
    iwctl station $input.station connect $network
}
