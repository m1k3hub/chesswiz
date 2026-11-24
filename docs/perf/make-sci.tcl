# Build ::BSCI from ::BPGN through the UI import path.
foreach ext {.sci .scg .scn .scs} { file delete -force "[file rootname $::BSCI]$ext" }
::application::database::newBase .application Normal $::BSCI
::import::import .application $::BSCI [list $::BPGN] "Importing" utf-8
update
set n [::scidb::db::count games $::BSCI Normal]
::application::database::closeBase .application $::BSCI
set n
