# Import ::BPGN in memory and return an md5-ish digest of every game's dump.
proc ::BLog {args} {}
proc ::BProg {args} {return 0}
catch {::scidb::db::close VRef}
::scidb::db::new VRef Undetermined [::application::database::lookupType Clipbase]
set n [lindex [::scidb::db::import VRef $::BPGN ::BLog {} ::BProg {} -encoding utf-8] 0]
after 2000 {set ::w 1}; vwait ::w; update; set all {}; set ::bad 0; set ::lasterr {}
for {set i 0} {$i < $n} {incr i} { if {[catch {append all [::scidb::game::dump VRef Normal 0 $i] \n} e]} { incr ::bad; set ::lasterr "$e $::errorCode [string range $::errorInfo 0 300]" } }
::scidb::db::close VRef
list err=[string range $::lasterr 0 200] bad=$::bad $n [string length $all] [zlib crc32 [encoding convertto utf-8 $all]]
