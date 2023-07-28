#!/usr/bin/env nu

use std log

def error-or-warning [
    error: string,
    message: string,
    --error-level: string,
    --cursor: int,
    --file: path,
    --span: record<start: int, end: int>
] {
    if $error_level == "warnings" {
        error make {
            msg: $"(ansi red_bold)($error)(ansi reset)"
            label: {
                text: $"($message) at cursor position ($cursor)"
                start: $span.start
                end: $span.end
            }
        }
    }

    log warning $"(ansi red_bold)($error)(ansi reset): ($message) in ($file) at cursor position ($cursor)"
}

# check a file for common mistakes
def main [
    file: path  # the path to the script to check
    --no-mutable: bool  # disallow the use of the `mut` keyword
    --error (-D): string = "errors"  # transform warnings into errors
] {
    let ast = nu --ide-ast $file | from json

    if $no_mutable {
        let muts = $ast | where shape == shape_internalcall and content == mut
        if not ($muts | is-empty) {(
            error-or-warning "clippy::mutable_not_allowed" "found `mut` keyword"
                --error-level $error
                --cursor $muts.0.span.start
                --file $file
                --span (metadata $file | get span)
        )}
    }

    for token in ($ast | enumerate) {
        if $token.item.shape == "shape_vardecl" {
            let next = $ast | get ($token.index + 1)
            if $next.shape == "shape_block" and ($next.content | str trim) == "(" {(
                error-or-warning "clippy::useless_parentheses" "useless parentheses"
                    --error-level $error
                    --cursor $next.span.start
                    --file $file
                    --span (metadata $file | get span)
            )}
        }

        if $token.item.shape == "shape_internalcall" and $token.item.content == "while" {
            let next = $ast | get ($token.index + 1)
            if $next.shape == "shape_bool" and $next.content == "true" {(
                error-or-warning "clippy::use_of_while_true" "`while true` can be collapsed into `loop`"
                    --error-level $error
                    --cursor $next.span.start
                    --file $file
                    --span (metadata $file | get span)
            )}
        }
    }
}
