# nu-clippy
a linter written in `nu` for the Nushell programming language

## try it out
```nu
./nu_scripts/scripts/nu-clippy/clippy nu_scripts/scripts/nu-clippy/examples/mut-each.nu
```
should not say anything but
```nu
./nu_scripts/scripts/nu-clippy/clippy nu_scripts/scripts/nu-clippy/examples/mut-each.nu --no-mutable
```
should complain about the `mut` keyword
```nu
Error:   × clippy::mutable_not_allowed
   ╭─[<commandline>:1:1]
 1 │ main nu_scripts/scripts/nu-clippy/examples/mut-each.nu --no-mutable
   ·      ────────────────────────┬────────────────────────
   ·                              ╰── found `mut` keyword in the script
   ╰────
```
