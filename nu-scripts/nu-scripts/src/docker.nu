# TODO: docstring
export def enter [
  name: string  # TODO: arg
  --shell (-s): string = "sh"  # TODO: arg
] {
  let id = (
    docker container ls
    | detect columns
    | where NAMES =~ $name
    | get CONTAINER
  )
  docker exec -it $id $shell
}


# TODO: docstring
export def prune [
  --system (-s)  # TODO: arg
  --images (-i)  # TODO: arg
  --processes (-p)  # TODO: arg
  --all (-a)  # TODO: arg
] {
  if ($system or $all) {
    print $"(ansi red)docker system prune(ansi reset):"
    docker system prune --force
  }

  if ($images or $all) {
    print $"(ansi red)docker image rm(ansi reset):"
    docker image ls -aq
    | lines
    | each {|| docker image rm --force $in}
  }

  if ($processes or $all) {
    print $"(ansi red)docker rm(ansi reset):"
    docker ps -aq
    | lines
    | each {|| docker rm --force $in}
  }
}

