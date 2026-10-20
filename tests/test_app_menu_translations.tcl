# ======================================================================
# Translation coverage for the redesigned menus (VAL-BAR-007)
# ======================================================================
# tests/fixtures/menu-moved-labels.txt lists the moved drop-down and
# context-menu labels. Every language file must define each one with a
# value that differs from English, and switching the language must
# relabel both surfaces. New labels that were never translated before are
# not required here; the point is that nothing moved lost its translation.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::trn {}

set ::scidb::test::trn::fixture [file join [file dirname [file normalize [info script]]] \
	fixtures menu-moved-labels.txt]

# The app bundle bakes in the installed share directory. Read the language
# files of this worktree instead, so the test verifies what we are about to
# commit rather than a stale system install.
set ::scidb::test::trn::savedShare $::scidb::dir::share
set ::scidb::test::trn::worktreeShare [file normalize [file join \
	[file dirname [file normalize [info script]]] .. tcl]]
if {[file isdirectory [file join $::scidb::test::trn::worktreeShare lang]]} {
	set ::scidb::dir::share $::scidb::test::trn::worktreeShare
}

proc ::scidb::test::trn::Rows {} {
	set f [open $::scidb::test::trn::fixture r]
	set rows {}
	foreach line [split [read $f] \n] {
		set line [string trim $line]
		if {$line eq "" || [string index $line 0] eq "#"} { continue }
		lappend rows $line
	}
	close $f
	return $rows
}

proc ::scidb::test::trn::Get {var} {
	if {![info exists ::$var]} { return "" }
	return [set ::$var]
}

proc ::scidb::test::trn::Set {var value} {
	set ::$var $value
}

# Snapshot the English values from this worktree's files.
set ::scidb::test::trn::rows [::scidb::test::trn::Rows]
::mc::setLang en
set ::scidb::test::trn::english [dict create]
foreach row $::scidb::test::trn::rows {
	lassign $row kind var
	dict set ::scidb::test::trn::english $var [::scidb::test::trn::Get $var]
}

proc ::scidb::test::trn::Check {lang} {
	set old $::mc::langID
	::mc::setLang $lang
	set missing {}
	set same {}
	foreach row $::scidb::test::trn::rows {
		lassign $row kind var
		set value [::scidb::test::trn::Get $var]
		if {$value eq ""} {
			lappend missing $var
		} elseif {$value eq [dict get $::scidb::test::trn::english $var]} {
			# A handful of words are spelled the same in a language
			# (German "Training"); those are translations, not fallbacks.
			set ok [dict exists $::scidb::test::trn::sameOK $var]
			if {$ok} { set ok [expr {[lsearch -exact [dict get $::scidb::test::trn::sameOK $var] $lang] >= 0}] }
			if {!$ok} { lappend same $var }
		}
	}
	::mc::setLang $old
	list $missing $same
}

set ::scidb::test::trn::sameOK [dict create \
	menu::mc::Training {de} \
]

# Labels of a menu, without separators (they carry no -label).
proc ::scidb::test::trn::MenuLabels {menu} {
	set labels {}
	if {[catch {$menu index end} last] || $last eq "none" || $last eq ""} {
		return $labels
	}
	for {set i 0} {$i <= $last} {incr i} {
		if {[catch {$menu type $i} type] || $type eq "separator"} { continue }
		if {![catch {$menu entrycget $i -label} label]} {
			lappend labels [string trim $label]
		}
	}
	return $labels
}

tcltest::test translations-moved-coverage {every moved label keeps a real translation in all five languages} -body {
	set out {}
	foreach lang {de es it hu sv} {
		lassign [::scidb::test::trn::Check $lang] missing same
		lappend out [list $lang [llength $missing] [llength $same] $missing $same]
	}
	# restore the English defaults the snapshot was taken from
	::mc::setLang en
	foreach row $::scidb::test::trn::rows {
		lassign $row kind var
		::scidb::test::trn::Set $var [dict get $::scidb::test::trn::english $var]
	}
	puts "VAL-BAR-007: [llength $::scidb::test::trn::rows] moved labels"
	foreach row $out { puts "  [lindex $row 0]: missing=[lindex $row 1] english=[lindex $row 2]" }
	foreach row $out {
		if {[lindex $row 1] != 0 || [lindex $row 2] != 0} {
			puts "  MISSING [lindex $row 0]: [lindex $row 3]"
			puts "  ENGLISH [lindex $row 0]: [lindex $row 4]"
		}
	}
	set ok 1
	foreach row $out {
		if {[lindex $row 1] != 0 || [lindex $row 2] != 0} { set ok 0 }
	}
	list $ok [llength $out]
} -result {1 5}

tcltest::test translations-switch-relabels-menus {a language switch relabels the drop-down and a context menu} -body {
	set saved $::mc::langID
	# clear leftovers of the coverage test (English defaults live in code)
	foreach row $::scidb::test::trn::rows {
		lassign $row kind var
		::scidb::test::trn::Set $var [dict get $::scidb::test::trn::english $var]
	}
	::mc::setLang en
	::menu::RegisterTree
	set beforeDrop [::menu::MC Tools]
	set beforeCtxLabel [::context::L c4.close]
	catch { destroy .trnctx }
	menu .trnctx -tearoff 0
	::context::Build C4 .trnctx [dict create base testbase]
	set beforeCtx [expr {[lsearch -exact [::scidb::test::trn::MenuLabels .trnctx] $beforeCtxLabel] >= 0}]
	destroy .trnctx

	::mc::setLang de
	::menu::RegisterTree
	set afterDrop [::menu::MC Tools]
	set afterCtxLabel [::context::L c4.close]
	catch { destroy .trnctx }
	menu .trnctx -tearoff 0
	::context::Build C4 .trnctx [dict create base testbase]
	set afterCtx [expr {[lsearch -exact [::scidb::test::trn::MenuLabels .trnctx] $afterCtxLabel] >= 0}]
	destroy .trnctx

	::mc::setLang $saved
	::menu::RegisterTree
	# restore English moved labels (the language loader only overrides)
	foreach row $::scidb::test::trn::rows {
		lassign $row kind var
		::scidb::test::trn::Set $var [dict get $::scidb::test::trn::english $var]
	}
	list [expr {$beforeDrop ne $afterDrop}] [expr {$beforeCtx && $afterCtx}] \
		$beforeDrop $afterDrop $beforeCtxLabel $afterCtxLabel
} -result {1 1 &Tools &Werkzeuge Close Schliessen}

# Put the installed share directory back for the test files that follow.
if {[info exists ::scidb::test::trn::savedShare]} {
	set ::scidb::dir::share $::scidb::test::trn::savedShare
}

tcltest::cleanupTests
