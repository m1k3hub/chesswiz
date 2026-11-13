# Retained from VS-reg-fresh / VU-reg-retry probes (2026-11-12).
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

# Cascades have no command of their own. A dynamic cascade may share its
# label with another object's leaf (C5 Open URL); its actual child commands
# identify the parent without guessing from that ambiguous label.
proc ::scidb::test::askscope::CascadeId {label cid children} {
	regsub { ▸$} $label "" label
	set label [string trim $label]
	foreach id $children {
		if {![catch {::context::L $id} text] && $text eq $label} { return $id }
	}
	return [LabelId $label $cid]
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
			set children [expr {$sub ne "" ? [MenuIds $sub $cid] : {}}]
			set id [CascadeId $label $cid $children]
			if {$id ne ""} { lappend ids $id }
			lappend ids {*}$children
			continue
		}
		if {$type ne "command"} { continue }
		set cmd ""
		catch { set cmd [$menu entrycget $i -command] }
		if {[regexp {::action::run (\S+)} $cmd -> id] && $id ne "context.ask"} {lappend ids $id}
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
        # An unavailable cascade cannot be opened, just like a disabled leaf.
        if {$type ne "separator" && [$menu entrycget $i -state] eq "disabled"} { continue }
		if {$type eq "cascade"} {
			set label ""
			catch { set label [$menu entrycget $i -label] }
			set sub ""
			catch { set sub [$menu entrycget $i -menu] }
			set children [expr {$sub ne "" ? [PostedIds $sub $cid] : {}}]
			set id [CascadeId $label $cid $children]
			if {$id ne "" && $id ne "context.ask"} { lappend ids $id }
			lappend ids {*}$children
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
