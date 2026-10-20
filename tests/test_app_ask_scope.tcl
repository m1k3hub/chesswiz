# ======================================================================
# Scidb App Test - object-scoped Ask rows (VAL-RULE-005)
# ======================================================================
# Real game states: no game, game start, mid-game, end of line. For each
# state the C2 rows in ::action::labels asklist must equal what the C2
# context menu posts for the current move object, and a row the rule
# hides must not run through ::action::run.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::askscope {
	variable GameId ""
	variable Added {}
}

set ::scidb::test::askscope::Pgn {[Event "Ask scope"]
[Site "?"]
[Date "2026.10.20"]
[Round "?"]
[White "White"]
[Black "Black"]
[Result "*"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 *}

proc ::scidb::test::askscope::Gamebar {} {
	return $::application::pgn::Vars(gamebar)
}

proc ::scidb::test::askscope::NewGame {} {
	variable GameId
	variable Pgn
	variable Added
	set gb [Gamebar]
	::menu::gameNew .application
	update
	set GameId [::gamebar::selected $gb]
	lappend Added $GameId
	set slot [::scidb::game::current]
	::scidb::game::import $slot $Pgn {} {} -encoding utf-8 -variation 0
	update
	return $GameId
}

proc ::scidb::test::askscope::Remove {id} {
	set gb [Gamebar]
	catch { ::gamebar::remove $gb $id }
	update
	return
}

proc ::scidb::test::askscope::NoGame {} {
	set gb [Gamebar]
	while {[::gamebar::size $gb] > 0} {
		catch { ::gamebar::remove $gb [::gamebar::selected $gb] }
		update
	}
	return
}

proc ::scidb::test::askscope::AskContextIds {cid} {
	set ids {}
	foreach row [::action::labels asklist ""] {
		set id [lindex $row 0]
		if {[catch { set rec [::action::get $id] }]} { continue }
		if {$cid in [dict get $rec context]} { lappend ids $id }
	}
	return [lsort -unique $ids]
}

proc ::scidb::test::askscope::AskIds {pattern} {
	set ids {}
	foreach row [::action::labels asklist ""] {
		set id [lindex $row 0]
		if {[string match $pattern $id]} { lappend ids $id }
	}
	return [lsort -unique $ids]
}

proc ::scidb::test::askscope::LabelId {label {cid ""}} {
	regsub { ▸$} $label "" label
	set label [string trim $label]
	set matches {}
	foreach id [array names ::context::Labels] {
		set text [string trim $::context::Labels($id)]
		if {$label eq $text || [string match "$text (*" $label]} {
			lappend matches $id
		}
	}
	if {[llength $matches] <= 1} { return [lindex $matches 0] }
	# Duplicate labels (e.g. Import PGN Game) resolve to the id that
	# belongs to the menu being compared.
	if {$cid ne ""} {
		foreach id $matches {
			if {[catch { set rec [::action::get $id] }]} { continue }
			if {$cid in [dict get $rec context]} { return $id }
		}
	}
	return [lindex $matches 0]
}

proc ::scidb::test::askscope::MenuIds {menu {cid ""}} {
	set ids {}
	set last ""
	catch { set last [$menu index end] }
	if {$last eq "" || $last eq "none"} { return $ids }
	for {set i 0} {$i <= $last} {incr i} {
		set type [$menu type $i]
		if {$type eq "cascade"} {
			set sub ""
			catch { set sub [$menu entrycget $i -menu] }
			set label ""
			catch { set label [$menu entrycget $i -label] }
			set id [LabelId $label $cid]
			if {$id ne ""} { lappend ids $id }
			if {$sub ne ""} { lappend ids {*}[MenuIds $sub $cid] }
			continue
		}
		if {$type ne "command"} { continue }
		set label ""
		catch { set label [$menu entrycget $i -label] }
		set id [LabelId $label $cid]
		if {$id ne ""} { lappend ids $id }
	}
	return [lsort -unique $ids]
}

proc ::scidb::test::askscope::ContextIds {cid} {
	set object [::context::CurrentObject $cid]
	if {![dict size $object] || ![::context::HasObject $cid $object]} {
		return {}
	}
	set menu .askscope[incr ::scidb::test::askscope::Menus]
	catch { destroy $menu }
	menu $menu -tearoff 0
	set built [::context::Build $cid $menu $object]
	set ids [MenuIds $menu $cid]
	destroy $menu
	return $ids
}

proc ::scidb::test::askscope::StateIds {id} {
	return [dict get [::menu::state $id] visible]
}

proc ::scidb::test::askscope::Diff {a b} {
	set missing {}
	foreach id $b { if {[lsearch -exact $a $id] < 0} { lappend missing $id } }
	set extra {}
	foreach id $a { if {[lsearch -exact $b $id] < 0} { lappend extra $id } }
	return [list $missing $extra]
}

namespace eval ::scidb::test::askscope {
	variable Menus 0
}

proc ::scidb::test::askscope::Reset {} {
	variable Added
	foreach id $Added { Remove $id }
	set Added {}
	NoGame
	catch { ::application::ask::HideList }
	set ::application::ask::Query ""
	unset -nocomplain ::application::ask::Priv(filtered)
	return
}

# ----------------------------------------------------------------------
# No game: no C2 rows at all, and a hidden row cannot run.
# ----------------------------------------------------------------------
tcltest::test ask-scope-no-game {without a game no C2 row is listed and truncate is refused} -body {
	::scidb::test::askscope::NoGame
	set ask [::scidb::test::askscope::AskIds c2.*]
	set state [::menu::state c2.strip.truncate]
	set before [::scidb::game::count halfmoves]
	set rc [::action::run c2.strip.truncate]
	set after [::scidb::game::count halfmoves]
	list [llength $ask] [dict get $state visible] $rc [expr {$before == $after}]
} -result {0 0 {error: action 'c2.strip.truncate' is not available here} 1}

# ----------------------------------------------------------------------
# Game start: truncate and comment-before are absent, comment-after is
# present, and the list equals the C2 menu built for the current object.
# ----------------------------------------------------------------------
tcltest::test ask-scope-start {at game start the C2 list equals the context menu} -setup {
	::scidb::test::askscope::Reset
	::scidb::test::askscope::NewGame
	::scidb::game::go start
	update
} -body {
	set ask [::scidb::test::askscope::AskContextIds C2]
	set menu [::scidb::test::askscope::ContextIds C2]
	lassign [::scidb::test::askscope::Diff $ask $menu] missing extra
	set before [::scidb::game::count halfmoves]
	set trunc [::action::run c2.strip.truncate]
	set beforeComment [::action::run c2.comment_before]
	set after [::scidb::game::count halfmoves]
	list [llength $missing] [llength $extra] \
		[expr {[lsearch -exact $ask c2.strip.truncate] < 0}] \
		[expr {[lsearch -exact $ask c2.comment_before] < 0}] \
		[expr {[lsearch -exact $ask c2.comment_after] >= 0}] \
		[expr {[lsearch -exact $ask c2.strip.moves] < 0}] \
		[string match {error: *} $trunc] [string match {error: *} $beforeComment] \
		[expr {$before == $after}]
} -cleanup {
	::scidb::test::askscope::Reset
} -result {0 0 1 1 1 1 1 1 1}

# ----------------------------------------------------------------------
# Mid-game: truncate and comment-before are listed and run on the
# current move; the C2 list still equals the context menu.
# ----------------------------------------------------------------------
tcltest::test ask-scope-mid-game {mid-game lists truncate and runs it on the current move} -setup {
	::scidb::test::askscope::Reset
	::scidb::test::askscope::NewGame
	::scidb::game::go 2
	update
} -body {
	set ask [::scidb::test::askscope::AskContextIds C2]
	set menu [::scidb::test::askscope::ContextIds C2]
	lassign [::scidb::test::askscope::Diff $ask $menu] missing extra
	set before [::scidb::game::count halfmoves]
	set trunc [::action::run c2.strip.truncate]
	update
	set after [::scidb::game::count halfmoves]
	set atEnd [::scidb::game::position atEnd?]
	list [llength $missing] [llength $extra] \
		[expr {[lsearch -exact $ask c2.strip.truncate] >= 0}] \
		[expr {[lsearch -exact $ask c2.comment_before] >= 0}] \
		[string match {error: *} $trunc] [expr {$after < $before}] $atEnd
} -cleanup {
	::scidb::test::askscope::Reset
} -result {0 0 1 1 0 1 1}

# ----------------------------------------------------------------------
# End of line: truncate is absent and cannot run; comment-before stays.
# ----------------------------------------------------------------------
tcltest::test ask-scope-end-of-line {at the end truncate is absent and refused} -setup {
	::scidb::test::askscope::Reset
	::scidb::test::askscope::NewGame
	::scidb::game::go end
	update
} -body {
	set ask [::scidb::test::askscope::AskContextIds C2]
	set menu [::scidb::test::askscope::ContextIds C2]
	lassign [::scidb::test::askscope::Diff $ask $menu] missing extra
	set before [::scidb::game::count halfmoves]
	set trunc [::action::run c2.strip.truncate]
	set after [::scidb::game::count halfmoves]
	list [llength $missing] [llength $extra] \
		[expr {[lsearch -exact $ask c2.strip.truncate] < 0}] \
		[expr {[lsearch -exact $ask c2.comment_before] >= 0}] \
		[expr {$before == $after}] [string match {error: *} $trunc]
} -cleanup {
	::scidb::test::askscope::Reset
} -result {0 0 1 1 1 1}

# ----------------------------------------------------------------------
# Every context-only row that is listed has an object; every row whose
# contexts all have no object is absent.
# ----------------------------------------------------------------------
tcltest::test ask-scope-objects-are-shared {ask rows follow ::context::CurrentObjectFor} -setup {
	::scidb::test::askscope::Reset
	::scidb::test::askscope::NewGame
	::scidb::game::go 2
	update
} -body {
	set listed {}
	foreach row [::action::labels asklist ""] {
		set id [lindex $row 0]
		set rec [::action::get $id]
		if {![llength [dict get $rec context]] || [dict get $rec dropdown] ne ""} {
			continue
		}
		lappend listed $id
	}
	set bad {}
	foreach id $listed {
		if {![llength [::context::CurrentObjectFor $id]]} { lappend bad $id }
	}
	set leaked {}
	foreach id [dict keys $::action::Registry] {
		set rec [::action::get $id]
		if {![llength [dict get $rec context]] || [dict get $rec dropdown] ne ""} {
			continue
		}
		if {[llength [::context::CurrentObjectFor $id]]} { continue }
		if {[lsearch -exact $listed $id] >= 0} { lappend leaked $id }
	}
	list [llength $bad] [llength $leaked]
} -cleanup {
	::scidb::test::askscope::Reset
} -result {0 0}

::tcltest::cleanupTests
