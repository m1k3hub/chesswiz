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

proc ::scidb::test::askscope::PaneUid {kind} {
	set twm ""
	catch { set twm [::application::twm board] }
	if {$twm eq ""} { return $kind }
	if {$kind eq "analysis"} {
		foreach uid [$twm leaves] {
			if {[string match {analysis:*} $uid]} { return $uid }
		}
		return analysis:1
	}
	return $kind
}

proc ::scidb::test::askscope::FocusPane {kind} {
	set twm ""
	catch { set twm [::application::twm board] }
	if {$twm eq ""} { return "" }
	set uid [PaneUid $kind]
	catch { ::application::openPane $uid }
	update
	set leaf ""
	catch { set leaf [$twm leaf $uid] }
	if {$leaf eq "" || ![winfo exists $leaf]} { return "" }
	focus -force $leaf
	update
	return [dict get [::context::CurrentObject C9] paneUid]
}

# Ids a built menu really posts: command rows by their own ::action::run
# argument (no label guessing), cascades by their label. The Ask opener is
# not a menu row for parity purposes.
proc ::scidb::test::askscope::PostedIds {menu {cid ""}} {
	set ids {}
	set last ""
	catch { set last [$menu index end] }
	if {$last eq "" || $last eq "none"} { return $ids }
	for {set i 0} {$i <= $last} {incr i} {
		set type [$menu type $i]
		if {$type eq "cascade"} {
			set label ""
			catch { set label [$menu entrycget $i -label] }
			set id [LabelId $label $cid]
			if {$id ne "" && $id ne "context.ask"} { lappend ids $id }
			set sub ""
			catch { set sub [$menu entrycget $i -menu] }
			if {$sub ne ""} { lappend ids {*}[PostedIds $sub $cid] }
			continue
		}
		if {$type ne "command"} { continue }
		# Ask lists only runnable rows, so a row the menu shows greyed out
		# (a docked pane's Stay On Top, an idle engine's toggles) is not a gap.
		set state normal
		catch { set state [$menu entrycget $i -state] }
		if {$state eq "disabled"} { continue }
		set cmd ""
		catch { set cmd [$menu entrycget $i -command] }
		if {![regexp {::action::run (\S+)} $cmd -> id]} { continue }
		if {$id ne "context.ask"} { lappend ids $id }
	}
	return [lsort -unique $ids]
}

proc ::scidb::test::askscope::C9MenuIds {} {
	set object [::context::CurrentObject C9]
	if {![dict size $object]} { return {} }
	set menu .askscopec9[incr ::scidb::test::askscope::Menus]
	catch { destroy $menu }
	menu $menu -tearoff 0
	set built [::context::Build C9 $menu $object]
	set ids {}
	if {$built} { set ids [PostedIds $menu C9] }
	destroy $menu
	return $ids
}

proc ::scidb::test::askscope::C9Diff {} {
	set posted [C9MenuIds]
	set askC9 [AskContextIds C9]
	set askAll {}
	foreach row [::action::labels asklist ""] { lappend askAll [lindex $row 0] }
	set missing {}
	foreach id $posted {
		if {$id ni $askAll} { lappend missing $id }
	}
	set extra {}
	foreach id $askC9 {
		if {$id ni $posted} { lappend extra $id }
	}
	return [list $missing $extra]
}

proc ::scidb::test::askscope::Present {suffix} {
	set twm ""
	catch { set twm [::application::twm board] }
	if {$twm eq ""} { return 0 }
	foreach uid [$twm leaves] {
		if {$uid eq $suffix || [string match "$suffix:*" $uid]} { return 1 }
	}
	return 0
}

proc ::scidb::test::askscope::InitialLeaves {} {
	set twm ""
	catch { set twm [::application::twm board] }
	if {$twm eq ""} { return {} }
	return [$twm leaves]
}

proc ::scidb::test::askscope::RestoreLayout {initial} {
	set twm ""
	catch { set twm [::application::twm board] }
	if {$twm eq ""} { return }
	foreach uid [$twm leaves] {
		if {$uid ni $initial} { catch { ::application::twm::ChangeState $twm $uid } }
	}
	foreach uid $initial {
		if {$uid ni [$twm leaves]} { catch { ::application::openPane $uid } }
	}
	update idletasks
	# Let deferred board rebuilds settle while the panes still exist, so a
	# later NoGame reset cannot run one against a removed game.
	after 450
	update
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
} -result {0 0 {error: precondition: select an item before running c2.strip.truncate} 1}

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

# ----------------------------------------------------------------------
# C9 parity: the Ask rows equal the current pane's own header menu, for
# the board, notation, games and analysis panes in every game state.
# ----------------------------------------------------------------------
tcltest::test ask-scope-c9-pane-parity {C9 rows follow the current pane's own menu in every state} -setup {
	::scidb::test::askscope::Reset
} -body {
	set initial [::scidb::test::askscope::InitialLeaves]
	set totalMissing 0
	set totalExtra 0
	set detail {}
	foreach state {nogame start mid end} {
		::scidb::test::askscope::Reset
		switch -- $state {
			nogame {}
			start {
				::scidb::test::askscope::NewGame
				::scidb::game::go start
			}
			mid {
				::scidb::test::askscope::NewGame
				::scidb::game::go 2
			}
			end {
				::scidb::test::askscope::NewGame
				::scidb::game::go end
			}
		}
		update
		foreach pane {board editor games analysis} {
			set seen [::scidb::test::askscope::FocusPane $pane]
			if {$seen eq ""} {
				lappend detail [list $state $pane missing extra]
				incr totalMissing
				continue
			}
			lassign [::scidb::test::askscope::C9Diff] missing extra
			incr totalMissing [llength $missing]
			incr totalExtra [llength $extra]
			lappend detail [list $state $seen [llength $missing] [llength $extra]]
		}
	}
	::scidb::test::askscope::Reset
	::scidb::test::askscope::RestoreLayout $initial
	puts "C9PARITY $detail"
	list $totalMissing $totalExtra [llength $detail]
} -cleanup {
	::scidb::test::askscope::Reset
} -result {0 0 16}

# The ten c9.pane.* rows no menu posts are not listed, and each one has a
# real effect (the same toggle as its menu.view.panes.* row).
tcltest::test ask-scope-c9-pane-rows {unposted c9.pane.* rows are absent from Ask and still act} -setup {
	::scidb::test::askscope::Reset
	# Panes are toggled with a game open: that is the state the board's
	# deferred rebuild expects.
	::scidb::test::askscope::NewGame
	set ::scidb::test::askscope::savedLeaves [::scidb::test::askscope::InitialLeaves]
} -body {
	set listed {}
	foreach row [::action::labels asklist ""] {
		if {[string match {c9.pane.*} [lindex $row 0]]} { lappend listed [lindex $row 0] }
	}
	set effects {}
	foreach {id suffix} {
		c9.pane.board board
		c9.pane.notation editor
		c9.pane.games games
		c9.pane.people players
		c9.pane.tree tree
		c9.pane.analysis analysis
		c9.pane.media media
		c9.pane.report report
		c9.pane.assistant assistant
		c9.pane.explorer explorer
	} {
		set before [::scidb::test::askscope::Present $suffix]
		set rc [catch { ::action::run $id } err]
		update
		set after [::scidb::test::askscope::Present $suffix]
		catch { ::action::run $id }
		update
		set back [::scidb::test::askscope::Present $suffix]
		set sameBefore [::scidb::test::askscope::Present $suffix]
		set mrc [catch { ::menu::TogglePaneId $suffix } merr]
		update
		set menuAfter [::scidb::test::askscope::Present $suffix]
		catch { ::menu::TogglePaneId $suffix }
		update
		set menuBack [::scidb::test::askscope::Present $suffix]
		set openable [expr {[llength [info commands ::menu::PaneOpenable]] \
			&& [::menu::PaneOpenable $suffix]}]
		set acted [expr {$rc == 0 && $back == $before \
			&& $after == $menuAfter && $sameBefore == $before \
			&& $menuBack == $before && (!$openable || $after != $before)}]
		lappend effects [list $id $before $after $back $menuAfter $menuBack $openable $acted $mrc $merr]
	}
	set failed {}
	foreach effect $effects {
		if {![lindex $effect 7]} { lappend failed $effect }
	}
	puts "C9EFFECTS $effects"
	list [llength $listed] [llength $failed] [llength $effects]
} -cleanup {
	::scidb::test::askscope::RestoreLayout $::scidb::test::askscope::savedLeaves
	::scidb::test::askscope::Reset
} -result {0 0 10}

::tcltest::cleanupTests
