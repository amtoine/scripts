#!/usr/bin/env nu

# give a nice "*happy day*" message on some particular occasions
export def main []: nothing -> nothing {
    match (date now | format date "%m.%d") {
        "01.01" => { print $'Happy new year!' }
        "03.14" => { print $'Happy (char -i 0x03c0) Day! (char -i 0x1f973)' }
        "06.28" => { print $'Happy (char -i 0x1d70f) Day! (char -i 0x1f973)' }
        "10.31" => { print $'Horrible Halloween!' }
        "12.25" => { print $'Merry Christmas!' }
    }
}
