# Import ::BPGN into a new .sci ::BSCI and save it (compare outputs across builds).
proc ::BLog {args} {}
proc ::BProg {args} {return 0}
foreach e {sci scg scn scs} { file delete [file rootname $::BSCI].$e }
::scidb::db::new $::BSCI Normal [::application::database::lookupType Unspecific]
set r [::scidb::db::import $::BSCI $::BPGN ::BLog {} ::BProg {} -encoding utf-8]
::scidb::db::save $::BSCI ::BProg {}
::scidb::db::close $::BSCI
lindex $r 0
