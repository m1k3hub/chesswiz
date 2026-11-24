#!/bin/bash
# PGN import / open benchmark (3 runs each). usage: bench-import.sh PGN [DISPLAY]
# Prints quiet C++ import ms and direct PGN open ms. Needs a running X display.
PGN=$(readlink -f "$1"); export DISPLAY=${2:-:77}
W=$(mktemp -d); export HOME=$W PULSE_SINK=cwtests SCIDB_AI_UNCALIBRATED=1 CHESSWIZ_NO_SETUP_SCAN=1
src/tkchesswiz -encoding utf-8 tcl/chesswiz --single-process >$W/app.log 2>&1 &
PID=$!
wish <<EOF
wm withdraw .
for {set i 0} {\$i < 300} {incr i} {
	if {"Chesswiz" in [winfo interps]} {
		catch { send Chesswiz { if {[winfo exists .application.lang.top.en]} { .application.lang.top.en invoke } } }
		if {![catch {send Chesswiz {expr {[winfo ismapped .application] && ![winfo exists .application.lang]}}} ok] && \$ok} break
	}
	after 100
}
after 3000
if {[catch {send Chesswiz {
	set out {}
	for {set r 0} {\$r < 3} {incr r} {
		set sci $W/imp\$r.sci
		::application::database::newBase .application Normal \$sci
		update
		set t0 [clock microseconds]
		::scidb::db::import \$sci $PGN ::import::Log log ::application::database::QuietLoadProgress {} -encoding utf-8 -illegal 1
		set n [::scidb::db::count games \$sci]
		lappend out "import [expr {([clock microseconds]-\$t0)/1000}] ms games=\$n"
		::application::database::CloseBase .application \$sci
		update
	}
	for {set r 0} {\$r < 3} {incr r} {
		set t0 [clock microseconds]
		::application::database::openBase .application $PGN no
		update
		lappend out "open [expr {([clock microseconds]-\$t0)/1000}] ms games=[::scidb::db::count games $PGN]"
		::application::database::CloseBase .application $PGN
		update
	}
	join \$out \n
}} r]} { puts "ERR: $r" } else { puts $r }
catch {send Chesswiz {after 10 exit}}
exit
EOF
sleep 1; kill $PID 2>/dev/null; rm -rf $W
