def downloads_dir [] {
    $env.XDG_DOWNLOAD_DIR? | default (
        $env.HOME | path join "downloads"
    )
}

export def show [] {
    let dir = (downloads_dir)

    if ($dir | path exists) {
        ls $dir
    }
}

export def --env go [] {
    let dir = (downloads_dir)

    if not ($dir | path exists) {
        mkdir $dir
    }

    cd $dir
}

export def clean [--force (-f)] {
    if (show | is-empty) {
        print $"no files in (downloads_dir)..."
        return
    }

    let files = (downloads_dir | path join *)

    if $force {
      rm --trash $files
    } else {
      rm --trash --interactive $files
    }
}

export def main [] {
    show
}
