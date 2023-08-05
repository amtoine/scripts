#!/usr/bin/env -S nu --env-config ~/.config/nushell/env.nu
#
# add the path to `nupm/` to `NU_LIB_DIRS` in your `env.nu`.
use nupm

def update [repo: path, --path: string = ""]: nothing -> nothing {
    git -C $repo pull origin main
    nupm install --path ($repo | path join $path)
}

# /home/disc/a.stevan/.local/share/nupm/plugins
# /home/disc/a.stevan/.local/share/nupm/zellij-sessionizer.nu
export def main []: nothing -> nothing {
    let repos_dir = $env.GIT_REPOS_HOME | path join "github.com"
    update ($repos_dir | path join "amtoine" "nu-git-manager")
    update ($repos_dir | path join "goatfiles" "scripts") --path "nu_scripts"
    update ($repos_dir | path join "amtoine" "zellij-layouts") --path "nu-zellij"
    update ($repos_dir | path join "nushell" "nu_scripts")

    null
}
