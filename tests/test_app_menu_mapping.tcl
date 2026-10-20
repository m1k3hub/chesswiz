# ======================================================================
# Old -> new mapping for the redesigned drop-down (VAL-BAR-002)
# ======================================================================
# tests/fixtures/menu-mapping-dropdown.txt lists every INVENTORY entry
# whose PROPOSAL section 5 home is a drop-down cascade (sections 5.1,
# 5.3 and 5.6). For each one we check the leaf exists in the built
# drop-down and invoke the registry action behind it with a stubbed
# handler. Dynamic lists are exempt (tests/fixtures/menu-mapping-exempt.txt)
# but their cascade must still exist.
#
# Every curated mapping must resolve without gaps or invocation failures.
# Section 6 removals are checked in the second test.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::map {}

set ::scidb::test::map::dir [file dirname [file normalize [info script]]]
set ::scidb::test::map::fixture [file join $::scidb::test::map::dir fixtures menu-mapping-dropdown.txt]
set ::scidb::test::map::menubar [file join $::scidb::test::map::dir fixtures menubar-expected.txt]

proc ::scidb::test::map::Norm {s} {
	set s [string map {… ...} $s]
	set s [string map {& {}} $s]
	return [string tolower [regsub -all {\s+} [string trim $s] { }]]
}

proc ::scidb::test::map::Rows {} {
	set f [open $::scidb::test::map::fixture r]
	set rows {}
	foreach line [split [read $f] \n] {
		set line [string trim $line]
		if {$line eq "" || [string index $line 0] eq "#"} { continue }
		lappend rows [split $line \t]
	}
	close $f
	return $rows
}

# Parse the frozen structure fixture into {top depth label kind} rows.
proc ::scidb::test::map::Tree {} {
	set f [open $::scidb::test::map::menubar r]
	set tree {}
	set top ""
	foreach line [split [read $f] \n] {
		if {[string match "MENU *" $line]} { set top [string trim [string range $line 5 end]]; continue }
		set line [string trimright $line]
		if {![regexp {^(\s*)(ENTRY|SUBMENU) (.*)$} $line -> indent kind label]} { continue }
		set depth [expr {[string length $indent] / 2}]
		set cascade [expr {[string index [string trim $label] end] eq "▸"}]
		set label [string trim [string map {▸ {}} $label]]
		if {[regexp {^(.*?)\s+(Ctrl|Cmd|Alt|Shift|F[0-9])} $label -> base]} { set label $base }
		if {$cascade} { set kind SUBMENU }
		lappend tree [list $top $depth $label $kind]
	}
	close $f
	return $tree
}

proc ::scidb::test::map::Actions {} {
	set actions {}
	foreach row [::action::labels dropdown] {
		lassign $row id label
		lappend actions [list $id $label [::menu::TopOf $id]]
	}
	return $actions
}

# Call the action with a recorder instead of its real handler, so the
# mapping test never opens a dialog or changes the user's files.
proc ::scidb::test::map::InvokeStubbed {id} {
	set registry $::action::Registry
	if {![dict exists $registry $id]} { return 0 }
	set saved [dict get $registry $id]
	set rec $saved
	dict set rec handler [list ::scidb::test::map::Record $id]
	dict set rec args {}
	dict set rec schema ""
	dict set rec enabled ""
	dict set rec visible ""
	dict set rec confirm 0
	dict set rec bulk 0
	dict set rec object ""
	dict set rec ai 0
	dict set ::action::Registry $id $rec
	set ::scidb::test::map::called ""
	set ::scidb::test::map::lastError ""
	if {[catch { ::action::run $id } err]} {
		set ::scidb::test::map::lastError "$id: threw $err"
	} elseif {$::scidb::test::map::called ne $id} {
		set ::scidb::test::map::lastError "$id: returned [string range $err 0 80] rec=[dict get $rec handler]"
	}
	dict set ::action::Registry $id $saved
	return [expr {$::scidb::test::map::called eq $id}]
}

proc ::scidb::test::map::Record {id args} {
	set ::scidb::test::map::called $id
	return ok
}

proc ::scidb::test::map::Descendants {tree top label} {
	set out {}
	set on 0
	set depth -1
	foreach row $tree {
		lassign $row t d l kind
		if {$t ne $top} continue
		if {!$on} {
			if {$kind eq "SUBMENU" && [Norm $l] eq [Norm $label]} {
				set on 1
				set depth $d
			}
			continue
		}
		if {$d <= $depth} break
		lappend out [list $l $kind]
	}
	return $out
}

proc ::scidb::test::map::FindAction {actions top label} {
	set want [Norm $label]
	foreach a $actions {
		lassign $a id l t
		if {($t eq $top || $t eq "") && [Norm $l] eq $want} { return $id }
	}
	return ""
}

proc ::scidb::test::map::FindCascade {tree top label} {
	set want [Norm $label]
	foreach row $tree {
		lassign $row t d l kind
		if {$t eq $top && $kind eq "SUBMENU" && [Norm $l] eq $want} { return $d }
	}
	return ""
}

# Resolve a mapping row. Returns {status id detail}: status is
# action (invoked), cascade (cascade exists, dynamic children), or gap.
proc ::scidb::test::map::Resolve {actions tree top leaf} {
	foreach alt [split $leaf {||}] {
		set alt [string trim $alt]
		set id [FindAction $actions $top $alt]
		if {$id ne ""} {
			set ok [InvokeStubbed $id]
			return [list [expr {$ok ? "action" : "invoke-failed"}] $id $alt]
		}
		set depth [FindCascade $tree $top $alt]
		if {$depth ne ""} {
			foreach desc [Descendants $tree $top $alt] {
				lassign $desc label kind
				set id [FindAction $actions $top $label]
				if {$id ne ""} {
					set ok [InvokeStubbed $id]
					return [list [expr {$ok ? "action" : "invoke-failed"}] $id "$alt > $label"]
				}
			}
			return [list cascade "" $alt]
		}
	}
	# Dynamic panes have a uid in the fixture, not a label (R-pane rows).
	set slug [string tolower [string map {\  - … {}} $leaf]]
	foreach a $actions {
		lassign $a id l t
		if {($t eq $top || $t eq "") && [string match "*.$slug" $id]} {
			set ok [InvokeStubbed $id]
			return [list [expr {$ok ? "action" : "invoke-failed"}] $id $leaf]
		}
	}
	return [list gap "" $leaf]
}

tcltest::test mapping-dropdown-old-to-new {every moved drop-down entry has a reachable, invokable new home} -body {
	catch { destroy .mapmenu }
	menu .mapmenu -tearoff 0
	::menu::BuildDropdown .mapmenu
	::menu::Dump .mapmenu
	set actions [::scidb::test::map::Actions]
	set tree [::scidb::test::map::Tree]
	set counts [dict create action 0 cascade 0 gap 0 invoke-failed 0]
	set gaps {}
	foreach row [::scidb::test::map::Rows] {
		lassign $row old top leaf
		lassign [::scidb::test::map::Resolve $actions $tree $top $leaf] status id detail
		dict incr counts $status
		if {$status eq "gap"} { lappend gaps [list $old $top $leaf] }
	}
	destroy .mapmenu
	puts "VAL-BAR-002 dropdown: [dict get $counts action] invoked, [dict get $counts cascade] dynamic cascades, [dict get $counts gap] gaps, [dict get $counts invoke-failed] invoke failures"
	foreach g $gaps { puts "  GAP [join $g { | }]" }
	if {$::scidb::test::map::lastError ne ""} { puts "  FIRST ERROR $::scidb::test::map::lastError" }
	list [dict get $counts action] [dict get $counts cascade] [llength $gaps] \
		[dict get $counts invoke-failed]
} -result {70 5 0 0}

tcltest::test mapping-section6-removals {only PROPOSAL section 6 rows are gone, each replacement is present} -body {
	catch { destroy .mapmenu }
	menu .mapmenu -tearoff 0
	::menu::BuildDropdown .mapmenu
	::menu::Dump .mapmenu
	set tops {}
	for {set i 0} {$i <= [.mapmenu index end]} {incr i} {
		lappend tops [string trim [.mapmenu entrycget $i -label]]
	}
	set all {}
	foreach row [::scidb::test::map::Tree] { lappend all [lindex $row 2] }
	set discoveries 0
	set ai 0
	set searchTop [lsearch -exact $tops Search]
	foreach label $all {
		if {[::scidb::test::map::Norm $label] eq [::scidb::test::map::Norm {Discover Databases…}]} { incr discoveries }
		if {[string match "AI:*" $label]} { incr ai }
	}
	destroy .mapmenu
	list $tops $searchTop $discoveries $ai
} -result {{File Edit Game Database Board Analysis Training Tools View Help} -1 1 0}

tcltest::cleanupTests
