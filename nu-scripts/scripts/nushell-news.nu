#!/usr/bin/env nu
use std log

# give a report of Nushell news
#
# this command uses a *cache* state file:
# - when the file does not exist, it is created and the 5 last posts are listed
# - if the news being pulled down are more than the cached ones, the file is updated and the new ones are listed
# - otherwise, nothing happens
#
# the news will be pulled down only once a day.
#
# # Examples
#     > the first time Nushell starts with the news enabled
#     2023-07-27T10:40:25.286|INF|Pulling down the Nushell news...
#     Have you seen these blog posts? :)
#     ╭───┬─────────────────────┬──────────────┬──────────────────────────────────────────────────────────╮
#     │ # │        date         │    title     │                           url                            │
#     ├───┼─────────────────────┼──────────────┼──────────────────────────────────────────────────────────┤
#     │ 0 │ 2023-05-16 00:00:00 │ nushell_0_80 │ https://www.nushell.sh/blog/2023-05-16-nushell_0_80.html │
#     │ 1 │ 2023-06-06 00:00:00 │ nushell_0_81 │ https://www.nushell.sh/blog/2023-06-06-nushell_0_81.html │
#     │ 2 │ 2023-06-27 00:00:00 │ nushell_0_82 │ https://www.nushell.sh/blog/2023-06-27-nushell_0_82.html │
#     │ 3 │ 2023-06-27 00:00:00 │ road-to-1_0  │ https://www.nushell.sh/blog/2023-06-27-road-to-1_0.html  │
#     │ 4 │ 2023-07-25 00:00:00 │ nushell_0_83 │ https://www.nushell.sh/blog/2023-07-25-nushell_0_83.html │
#     ╰───┴─────────────────────┴──────────────┴──────────────────────────────────────────────────────────╯
#
#     > when some more recent news have been released on the website
#     2023-07-27T10:40:33.685|INF|Pulling down the Nushell news...
#     There are new posts on the website!!
#     ╭───┬─────────────────────┬──────────────┬──────────────────────────────────────────────────────────╮
#     │ # │        date         │    title     │                           url                            │
#     ├───┼─────────────────────┼──────────────┼──────────────────────────────────────────────────────────┤
#     │ 0 │ 2023-06-27 00:00:00 │ nushell_0_82 │ https://www.nushell.sh/blog/2023-06-27-nushell_0_82.html │
#     │ 1 │ 2023-06-27 00:00:00 │ road-to-1_0  │ https://www.nushell.sh/blog/2023-06-27-road-to-1_0.html  │
#     │ 2 │ 2023-07-25 00:00:00 │ nushell_0_83 │ https://www.nushell.sh/blog/2023-07-25-nushell_0_83.html │
#     ╰───┴─────────────────────┴──────────────┴──────────────────────────────────────────────────────────╯
#
#     > when there is no new post
#     2023-07-27T10:40:39.015|INF|Pulling down the Nushell news...
#     2023-07-27T10:40:40.507|INF|No news for Nushell today!
export def main [
    --force # pull the news even if they have been today
]: nothing -> nothing {
    if not $force {
        let last = $nu.home-path | path join ".local" "state" "nushell" "latest"
        if ($last | path exists) and ((open $last) == (date now | date format "%F")) {
            return
        }

        date now | date format "%F" | save --force $last
    }

    log info "Pulling down the Nushell news..."
    let news = http get https://api.github.com/repos/nushell/nushell.github.io/contents/blog
        | where name != "README.md"
        | select path
        | update path { path parse | reject extension | path join }
        | insert url {|it| {
            scheme: "https"
            host: "www.nushell.sh"
            path: ($it.path | path parse | upsert extension "html" | path join)
        } | url join}
        | update path { parse --regex '\w+/(?<date>\d{4}-\d{2}-\d{2})-(?<title>.*)' }
        | flatten --all
        | into datetime date
        | sort-by date

    let news_file = $nu.home-path | path join ".local" "state" "nushell" "news.nuon"

    if not ($news_file | path exists) {
        mkdir ($news_file | path dirname)
        $news | save $news_file

        print "Have you seen these blog posts? :)"
        print ($news | last 5)
        return
    }

    let new_blog_posts =  ($news | length) - (open $news_file | length)
    if $new_blog_posts > 0 {
        $news | save --force $news_file

        print "There are new posts on the website!!"
        print ($news | reverse | take $new_blog_posts | reverse)
        return
    }

    log info "No news for Nushell today!"
}
