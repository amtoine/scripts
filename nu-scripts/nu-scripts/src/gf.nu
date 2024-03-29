use context.nu


alias FZF = fzf --ansi --color --reverse

def FZF_LOG_PREVIEW [] {"
    hash=$(echo {} | \\
      sd -s '|' '' | \\
      sd -s '\\' '' | \\
      sd -s '/' '' | \\
      sd '^\\s*\\*\\s*' '' | \\
      awk '{print $1}'\\
    )
    [ -z $hash ] || git show --color=always $hash
"}
def FZF_STASH_PREVIEW [] { "git stash show --all --color=always $(echo {1} | sd ':' '')" }

def FZF_CHECKOUT_PREVIEW [] {"
    branch=$(echo {} | \\
      sd -s '*' '' | \\
      sd '^\\s*' '' | \\
      sd ' .*' '' \\
    )
    git log --graph --decorate --oneline --color=always $branch
"}

# TODO
def log_error [message: string] {
  print $"gf: (ansi red_bold)error(ansi reset): ($message)"
}


# TODO
def log_debug [message: string] {
  print $"gf: (ansi yellow_bold)debug(ansi reset): ($message)"
}


# TODO
def ungraph [
  commitish: string = "HEAD"
] {
  str replace --regex -a "|" "" |
  str replace --regex -a '\' "" |
  str replace --regex -a "/" "" |
  str replace --regex "^\\s*\\*\\s*" "* "
}


# TODO
export def log [
  commitish: string = "HEAD"
  --all (-a)
  --debug (-d)
] {
  alias GIT_LOG = git log --graph --oneline --decorate --color=always

  let choice = (
    if ($all) {
      GIT_LOG --branches --remotes=origin
    } else {
      GIT_LOG $commitish
    } |
    FZF --preview (FZF_LOG_PREVIEW) |
    str trim
  )

  # do not try to show the commit if none has been selected!
  if ($choice | is-empty) {
    error make (context user_choose_to_exit)
  }

  let commit = ($choice | ungraph)
  if not ($commit | is-empty) {
    let hash = (
      $commit |
      parse "* {hash} {rest}" |
      get hash
    )
    if ($debug) {
      log_debug $"git show --color=always ($hash)"
    } else {
      git show --color=always $hash
    }
  } else {
    log_error "not a commit"
  }
}


# TODO
export def stash [
  --debug (-d)
] {
  let choice = (
    git stash list --color=always |
    FZF --preview (FZF_STASH_PREVIEW) |
    str trim
  )

  # do not try to show the stash if none has been selected!
  if ($choice | is-empty) {
    error make (context user_choose_to_exit)
  }

  let stash_id = (
    $choice |
    parse "{stash}: {rest}" |
    get stash
  )
  if ($debug) {
    log_debug $"git stash show --all --color=always ($stash_id)"
  } else {
    git stash show --all --color=always $stash_id
  }
}


# TODO
export def checkout [
  --debug (-d)
] {
  let choice = (
    git branch --list --color=always | lines |
    append (
      git branch --remote --color=always | lines
    ) |
    sort -r |
    to text |
    FZF --preview (FZF_CHECKOUT_PREVIEW) |
    str trim
  )

  # do not try to show the checkout to a branch if none has been selected!
  if ($choice | is-empty) {
    error make (context user_choose_to_exit)
  }

  let branch = (
    $choice |
    str replace --regex -a "*" "" |
    str replace --regex "^\\s*" "" |
    str replace --regex " .*" ""
  )

  if ($debug) {
    log_debug $"git checkout ($branch)"
  } else {
    git checkout $branch
  }
}


# TODO
export def branch [] {
  log_error "branch unsupported"
}


# TODO
def "git branch wipe" [
  branch: string
  --remote (-r): string = "origin"
] {
  let res = (do -i {
    git rev-parse --verify $branch
  } | complete)

  if ($res.exit_code != 0) {
    print $"wip: (ansi red_bold)error(ansi reset): '($branch)' does not exist..."
  } else {
    git branch --delete --force $branch
    git push $remote $":($branch)"
  }
}
