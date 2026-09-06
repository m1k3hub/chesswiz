#!/usr/bin/env tkscidb
set ::base /media/michael-g-thomas/sas_mirror/fixt/cbm168/168Endgame.cbh
proc ::myprogress {args} {}

if {[catch { set ret [::scidb::db::load $::base ::myprogress progress -readonly yes] } msg]} {
	puts "LOAD-ERR: $msg"; exit 1
}
puts "LOAD-RET: $ret"

# what keys resolve?
foreach key [list $::base Endgames 168Endgame] {
	set open "?"
	catch { set open [::scidb::db::get open? $key] }
	puts "OPEN?($key): $open"
	if {$open} {
		set n "err"
		catch { set n [::scidb::db::count games $key Normal] }
		puts "COUNT($key): $n"
	}
}

# engine open?/name introspection
catch { puts "DESCR: [::scidb::db::get description $::base]" }
exit 0