# scripts
A collection of scripts for my daily use on ArchLinux.

## Installation
### with Nushell
- install [Nupm] (**recommended**) by following the [Nupm instructions]
- download the `scripts` repository
```shell
git clone https://github.com/amtoine/scripts
```
- activate the `nupm` module with `use nupm`
- install the packages
```nushell
[
    nu-clippy, nu-logout, nu-scripts, nu-sound-manager, nu-monitor-manager
] | each { nupm install --path --force $in }
```

[Nupm]: https://github.com/nushell/nupm
[Nupm instructions]: https://github.com/nushell/nupm#-installation
