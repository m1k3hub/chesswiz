# ======================================================================
# Static registry walk (VAL-REG-002)
# ======================================================================
# Every built menu surface and every toolbar button must dispatch through
# ::action::run. The only non-cascade commands allowed are disabled
# header/hint rows (they carry no -command at all) and the fixed dynamic
# row classes named in the contract (recent files, layout names, language
# and country lists). This file reports the count of each surface.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::rgw {}

proc ::scidb::test::rgw::WalkMenu {menu rowsVar {surface ""}} {
	upvar $rowsVar rows
	set n [$menu index end]
	if {$n eq "" || $n eq "none"} { return }
	for {set i 0} {$i <= $n} {incr i} {
		set type [$menu type $i]
		if {$type eq "separator"} { continue }
		if {$type eq "cascade"} {
			set sub ""
			catch { set sub [$menu entrycget $i -menu] }
			if {$sub ne "" && [winfo exists $sub]} {
				::scidb::test::rgw::WalkMenu $sub rows $surface
			}
			continue
		}
		set cmd ""
		catch { set cmd [$menu entrycget $i -command] }
		set state normal
		catch { set state [$menu entrycget $i -state] }
		set label ""
		catch { set label [string trim [$menu entrycget $i -label]] }
		lappend rows [list $surface $type $state $label $cmd]
	}
}

proc ::scidb::test::rgw::Objects {} {
	return [dict create \
		C1 [dict create square e4 fen {8/8/8/8/4P3/8/8/8 w - - 0 1}] \
		C2 [dict create base b variant Normal index 5 ply 10 san Nf3] \
		C3 [dict create base b variant Normal index 1 column number \
			sortable 1 path .rgwlist view 0] \
		C4 [dict create base testbase] \
		C5.player [dict create kind player name {Carlsen, Magnus} base b] \
		C5.event [dict create kind event name Wijk base b] \
		C5.site [dict create kind site name wijk.com base b] \
		C6 [dict create engine SF lineId 1 pv {e4 e5 Nf3}] \
		C7 [dict create base b mediaId m1 path /tmp/clip.mp4] \
		C8 [dict create fen {8/8/8/8/4P3/8/8/8 w - - 0 1} move e4 table .rgwtree] \
		C9.board [dict create paneUid board frame .rgwpane] \
		C9.editor [dict create paneUid editor frame .rgwpane] \
		C9.games [dict create paneUid games frame .rgwpane] \
		C9.people [dict create paneUid players frame .rgwpane] \
		C9.tree [dict create paneUid tree frame .rgwpane] \
		C9.analysis [dict create paneUid analysis:1 frame .rgwpane] \
		C9.media [dict create paneUid media frame .rgwpane] \
		C9.report [dict create paneUid report frame .rgwpane] \
		C9.assistant [dict create paneUid assistant frame .rgwpane] \
		C9.explorer [dict create paneUid explorer frame .rgwpane] \
		C10 [dict create table .rgwlist column date] \
		C11 [dict create base b index 5 ply 10 widget .rgwtxt] \
		C12 [dict create gameSlot 1 history {G1 G2}] \
	]
}

proc ::scidb::test::rgw::WalkContexts {} {
	set objects [::scidb::test::rgw::Objects]
	set keys {}
	foreach key [dict keys $objects] { lappend keys [lindex [split $key .] 0] }
	set rows {}
	set built 0
	foreach cid [lsort -unique $keys] {
		foreach key [dict keys $objects] {
			if {[lindex [split $key .] 0] ne $cid} { continue }
			set menu .rgwctx[incr built]
			catch { destroy $menu }
			menu $menu -tearoff 0
			catch { ::context::Build $cid $menu [dict get $objects $key] }
			::scidb::test::rgw::WalkMenu $menu rows $key
			catch { destroy $menu }
		}
	}
	return $rows
}

proc ::scidb::test::rgw::Toolbars {w rowsVar} {
	upvar $rowsVar rows
	if {[winfo class $w] eq "Toolbar"} {
		foreach child [winfo children $w] {
			set cls [winfo class $child]
			if {$cls ni {Button DropdownButton Checkbutton Radiobutton}} { continue }
			set cmd ""
			catch { set cmd [$child cget -command] }
			set label ""
			catch { set label [$child cget -text] }
			if {$label eq ""} { catch { set label [$child cget -tooltip] } }
			lappend rows [list toolbar $cls normal $label $cmd]
		}
	}
	foreach child [winfo children $w] {
		::scidb::test::rgw::Toolbars $child rows
	}
}

proc ::scidb::test::rgw::BadCommands {rows} {
	set bad {}
	foreach row $rows {
		lassign $row surface type state label cmd
		if {$type eq "cascade"} { continue }
		if {[string trim $cmd] eq ""} {
			# No command means no command to dispatch: disabled header/hint
			# rows and dropdown buttons whose popup is itself a menu.
			continue
		}
		if {![string match "::action::run *" [string trim $cmd]]} {
			lappend bad $row
		}
	}
	return $bad
}

tcltest::test registry-walk-dropdown {every drop-down command is ::action::run} -body {
	catch { destroy .rgwdd }
	menu .rgwdd -tearoff 0
	::menu::BuildDropdown .rgwdd
	::menu::Dump .rgwdd
	set rows {}
	::scidb::test::rgw::WalkMenu .rgwdd rows dropdown
	set bad [::scidb::test::rgw::BadCommands $rows]
	set ids {}
	foreach row $rows {
		if {[regexp {^::action::run (\S+)$} [lindex $row 4] -> id]} { lappend ids $id }
	}
	destroy .rgwdd
	puts "REG-002 dropdown: [llength $rows] rows, [llength [lsort -unique $ids]] actions, [llength $bad] bad"
	list $bad [expr {[llength [lsort -unique $ids]] > 100}]
} -result {{} 1}

tcltest::test registry-walk-contexts {every C1-C12 command is ::action::run} -body {
	set rows [::scidb::test::rgw::WalkContexts]
	set bad [::scidb::test::rgw::BadCommands $rows]
	set per {}
	foreach row $rows {
		set s [lindex $row 0]
		dict incr per $s
	}
	puts "REG-002 contexts: [dict size $per] objects, [llength $rows] rows, [llength $bad] bad"
	foreach key [lsort [dict keys $per]] { puts "  $key: [dict get $per $key]" }
	list $bad [expr {[llength $rows] > 150}]
} -result {{} 1}

tcltest::test registry-walk-toolbars {every toolbar button command is ::action::run} -body {
	set rows {}
	::scidb::test::rgw::Toolbars . rows
	set bad [::scidb::test::rgw::BadCommands $rows]
	set seen 0
	set ids {}
	foreach row $rows {
		if {[string trim [lindex $row 4]] eq ""} { continue }
		incr seen
		if {[regexp {^::action::run (\S+)$} [lindex $row 4] -> id]} { lappend ids $id }
	}
	puts "REG-002 toolbars: $seen actionable buttons, [llength [lsort -unique $ids]] actions, [llength $bad] bad"
	foreach row $bad { puts "  bad: $row" }
	list $bad [expr {$seen > 20}]
} -result {{} 1}

tcltest::test registry-walk-ask-is-action {the assistant row is a registry action, not a direct callback} -body {
	set rows [::scidb::test::rgw::WalkContexts]
	set ask {}
	foreach row $rows {
		if {[string match "*What can I do here*" [lindex $row 3]]} { lappend ask $row }
	}
	set direct {}
	foreach row $rows {
		if {[string match "::context::*" [string trim [lindex $row 4]]]} { lappend direct $row }
	}
	list [expr {[llength $ask] > 0}] $direct
} -result {1 {}}

tcltest::cleanupTests
