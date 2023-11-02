# an example usage to import some keys back:
# - copy the keys archive to the system
# ```nushell
# let mount_point = /mnt/
# let key_dump = /tmp/keys/
#
# sudo mount /dev/sdb1 $mount_point
# mkdir $key_dump
# cp ($mount_point | path join "keys.tar.gpg.asc") $key_dump
# sudo umount $mount_point
# ```
#
# - import the keys in the new keyring
# ```nushell
# use nu-goat-scripts gpg
# let keyring = /tmp/gnupg/
#
# cd $key_dump
# gpg --decrypt keys.tar.gpg.asc | save keys.tar
# tar -xf keys.tar
# mkdir $keyring
# with-env [GNUPGHOME $keyring] { gpg -k }
# with-env [GNUPGHOME $keyring] { gpg import --dump_dir ($key_dump | path join "keys/gpg/") }
# ```
#
# - check the new keyring and the SSH keys
# ```nushell
# gpg -k
# with-env [GNUPGHOME $keyring] { gpg -k }
# ssh -i ($key_dump | path join "keys/ssh/keys/github.com") git@github.com
# ```

# TODO: documentation
def poll_gpg [
  key: string = ""
] {
  if ($key == "") {
    gpg --list-keys --with-colons
  } else {
    gpg --list-keys --with-colons $key
  }
}


# TODO: documentation
def get_gpg_tru [] {
  poll_gpg | lines | find --regex "^tru" | split column ":" --collapse-empty a b c d e f g
}


# TODO: documentation
def get_gpg_keys [] {
  poll_gpg | lines | find --regex "^pub" | parse "{pub}:{1}:{2}:{3}:{key}:{rest}" | get key
}


# TODO: documentation
def get_section [
  section: string
  context: int = 1
] {
  grep $"^($section)" -A $context | str trim
}


# TODO: documentation
# FIXME: type annotation
def format_section [
  section: list  # list<string>
] {
  {
    main: ($section | get 0 | split column ":" --collapse-empty a b c d e f g h i j k)
    fpr: ($section | get 1 | split column ":" --collapse-empty a b)
  }
}


# TODO: documentation
def get_gpg_pub [
  key: string
] {
  let pub = (poll_gpg $key | get_section "pub" | lines)
  format_section $pub
}


# TODO: documentation
def get_gpg_sub [
  key: string
] {
  let sub = (poll_gpg $key | get_section "sub" | lines)
  format_section $sub
}


# TODO: documentation
def get_gpg_uid [
  key: string
] {
  poll_gpg $key | get_section "uid" | split column ":" --collapse-empty a b c d name e f g h i j
}


# TODO: documentation
def get_gpg_keys_data [] {
  (get_gpg_keys)
  | each {|key|
    {
      key: $key
      data: {
        pub: (get_gpg_pub $key)
        sub: (get_gpg_sub $key)
        uid: (get_gpg_uid $key)
      }
    }
  }
}


# TODO: documentation
export def list [] {
  {
    tru: (get_gpg_tru)
    keys: (get_gpg_keys_data)
  }
}


# TODO: documentation
export def export [
  pubkeys_file: string = "keys.pub.asc"
  privkeys_file: string = "keys.asc"
  trust_file: string = "trust.txt"
  --dump_dir: string = "/tmp/gpg-keys"
] {
  if not ($dump_dir | path exists) {
    mkdir $dump_dir
  }
  gpg --armor --export-options backup --export | save --force ($dump_dir | path join $pubkeys_file)
  gpg --armor --export-options backup --export-secret-keys | save --force ($dump_dir | path join $privkeys_file)
  gpg --export-ownertrust | save --force ($dump_dir | path join $trust_file)
}


# TODO: documentation
export def import [
  pubkeys_file: string = "keys.pub.asc"
  privkeys_file: string = "keys.asc"
  trust_file: string = "trust.txt"
  --dump_dir: string = "/tmp/gpg-keys"
] {
  gpg --import ($dump_dir | path join $pubkeys_file)
  gpg --import ($dump_dir | path join $privkeys_file)
  gpg --import-ownertrust ($dump_dir | path join $trust_file)
}


# TODO: documentation
export def "make keyring" [keyring?] {
  let keyring = (if ($keyring | is-empty) {
    $env | get -i GNUPGHOME | default "~/.gnupg" | path expand
  } else { $keyring })

  mkdir $keyring
  chmod -R 700 $keyring
}
