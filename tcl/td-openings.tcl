# ======================================================================
# Tournament opening suites: native ECO lookup, explicit SAN moves, or ECO
# ranges filtered from a PGN/open database. No model supplies chess moves.
# ======================================================================

if {[llength [info commands ::util::source]]} { ::util::source td-openings }
package require Tcl 8.6
namespace eval ::td::openings {}
proc ::td::openings::dg {d key {default {}}} { if {[dict exists $d $key]} { return [dict get $d $key] }; return $default }

proc ::td::openings::EcoRange {eco} {
	set eco [string toupper [string map {" " ""} $eco]]
	if {[regexp {^([A-E]\d\d)-([A-E]\d\d)$} $eco -> from to]} {
		if {$to < $from} { error "reversed ECO range '$eco'" }
		return [list $from $to]
	}
	if {[regexp {^[A-E]\d?\d?$} $eco]} { return [list [string range ${eco}00 0 2] [string range ${eco}99 0 2]] }
	error "ECO must be a code, class or range such as A46, A4 or A40-A49"
}

proc ::td::openings::CleanSan {moves} {
	set out {}
	foreach tok $moves {
		regsub {^\d+\.(\.\.)?} $tok {} san
		set san [string trimright $san "!?"]
		if {$san ne "" && $san ni {1-0 0-1 1/2-1/2 *}} { lappend out $san }
	}
	return $out
}

proc ::td::openings::Named {name} {
	set words {}
	foreach word [regexp -all -inline {[^\s,;:()]+} $name] {
		if {[string tolower $word] ni {the a an of system opening variation defence defense}} { lappend words $word }
	}
	if {![llength $words]} { error "empty opening name" }
	if {[catch {::scidb::ai::ecoLines $words} rows]} { error "opening table unavailable: $rows" }
	set exact {}
	set best {}
	set fullWant [string tolower [string trim $name]]
	foreach row $rows {
		lassign $row code label moves
		set parsed [CleanSan [::enginematch::parsePgnMoves $moves 100]]
		if {![llength $parsed]} { continue }
		set item [list [llength $parsed] [string length $label] $code $label $parsed]
		if {[string first $fullWant [string tolower $label]] >= 0} {
			lappend exact $item
		}
		lappend best $item
	}
	if {![llength $best]} { error "Chesswiz's ECO table has no opening named '$name'" }
	if {[llength $exact]} { set best $exact }
	set best [lsort -integer -index 1 [lsort -integer -index 0 $best]]
	return [list [lindex $best 0 end]]
}

proc ::td::openings::Pgn {path from to plies} {
	set chan [open $path r]
	fconfigure $chan -encoding utf-8
	set text [read $chan]
	close $chan
	set games {}
	set current {}
	foreach line [split $text \n] {
		if {[string match {\[*} [string trim $line]] && [string trim $line] ne ""} {
			if {[string first {[Event } $line] == 0 && $current ne ""} { lappend games $current; set current {} }
		}
		append current $line \n
	}
	if {$current ne ""} { lappend games $current }
	set out {}
	set seen {}
	foreach game $games {
		set eco {}
		regexp -nocase {\[ECO\s+"([A-E][0-9][0-9])"\]} $game -> eco
		if {$eco eq "" || $eco < $from || $eco > $to} { continue }
		set movetext {}
		foreach line [split $game \n] { if {![string match {\[*} [string trim $line]]} { append movetext $line \n } }
		set moves [::enginematch::parsePgnMoves $movetext $plies]
		if {![llength $moves] || $moves in $seen} { continue }
		lappend seen $moves
		lappend out $moves
	}
	return $out
}

proc ::td::openings::Database {source from to plies} {
	set imported {}
	if {[catch {::scidb::db::count games $source Normal} count]} {
		set imported TDOpenings[pid]
		catch {::scidb::db::close $imported}
		::scidb::db::new $imported Undetermined [::application::database::lookupType Clipbase]
		if {[catch {::scidb::db::import $imported $source ::enginematch::LogSink {} ::enginematch::LogSink {} -encoding utf-8} err]} {
			catch {::scidb::db::close $imported}
			error $err
		}
		set source $imported
	}
	set view -1
	set made 0
	set rc [catch {
		set view [::scidb::view::new $source Normal unused unused unused unused unused slave]
		::scidb::view::search $source Normal $view null none [list ecorange $from $to]
		set count [::scidb::view::count games $source Normal $view]
		set made [expr {![catch {::scidb::game::new 44}]}]
		set out {}
		set seen {}
		for {set i 0} {$i < $count} {incr i} {
			if {[catch {::scidb::game::load 44 $source Normal $i -view $view}]} { continue }
			set moves {}
			foreach ply [::scidb::game::query 44 mainline] {
				if {[llength $moves] >= $plies} { break }
				lappend moves [lindex $ply 1]
			}
			if {[llength $moves] && $moves ni $seen} { lappend seen $moves; lappend out $moves }
		}
		return $out
	} err opts]
	if {$made} { catch {::scidb::game::release 44} }
	if {$view >= 0} { catch {::scidb::view::close $source Normal $view} }
	if {$imported ne ""} { catch {::scidb::db::close $imported} }
	if {$rc} { return -options $opts $err }
	return $err
}

proc ::td::openings::Resolve {domain} {
	set plies [dg $domain opening_plies 10]
	if {[dict exists $domain moves] && [llength [dict get $domain moves]]} {
		set moves [dict get $domain moves]
		if {[llength $moves] == 1} { set moves [::enginematch::parsePgnMoves [lindex $moves 0] 100] }
		set moves [CleanSan $moves]
		if {![llength $moves]} { error "the opening move list is empty" }
		return [list $moves]
	}
	set eco [dg $domain eco {}]
	set opening [dg $domain opening {}]
	if {$eco eq "" && $opening ne ""} {
		set compact [string map {" " ""} $opening]
		if {[regexp {^[A-Za-z]\d*\d*(?:-[A-Za-z]\d\d)?$} $compact] && [regexp {^[A-Ea-e]} $compact]} { set eco $compact }
	}
	if {$eco ne ""} {
		lassign [EcoRange $eco] from to
		set suite [dg $domain suite {}]
		if {$suite eq ""} { error "an ECO opening range requires suite (PGN or database)" }
		if {[file extension $suite] in {.pgn .PGN}} {
			set out [Pgn $suite $from $to $plies]
		} else {
			set out [Database $suite $from $to $plies]
		}
		if {![llength $out]} { error "no games in ECO range $from-$to" }
		return $out
	}
	if {$opening eq ""} { return {} }
	return [Named $opening]
}

# vi:set ts=3 sw=3:
