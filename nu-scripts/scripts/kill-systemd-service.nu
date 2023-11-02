#!/usr/bin/env nu

def main [name: string, --no-confirm (-y)]: nothing -> nothing {
    let services = systemctl --type=service --state=running
        | detect columns
        | compact UNIT
        | where UNIT =~ '\.service$'
        | update LOAD {|it| $it.LOAD == "loaded"}
        | update ACTIVE {|it| $it.ACTIVE == "active"}
        | select UNIT LOAD ACTIVE SUB DESCRIPTION
        | rename service loaded active state description
        | where service =~ $name # filter only the services to kill

    if ($services | is-empty) {
        let span = (metadata $name | get span)
        error make {
            msg: $"(ansi red_bold)systemctl::no_service_matching(ansi reset)"
            label: {
                text: "no systemd matching this name has been found"
                start: $span.start
                end: $span.end
            }
        }
    }

    let answer = if $no_confirm {
        "yes"
    } else {
        print "you are about to stop the following services:"
        print $services
        ["no" "yes"] | input list "proceed? "
    }

    match $answer {
        "yes" => {},
        "no" | '' => {
            print "aborting!"
            return
        },
        _ => { error make --unspanned {msg: $"unexpected answer '($answer)'"}},
    }

    $services | each {|service|
        print $service.service
        sudo systemctl stop $service.service
    }

    null
}
