set ::RC 0
foreach c [info commands ::pgn::*::refresh] { rename $c ${c}_o; proc $c args "incr ::RC; ${c}_o {*}\$args" }
