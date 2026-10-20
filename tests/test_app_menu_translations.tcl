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

# --- the live drop-down label set, per language -----------------------
# The old list above is the moved-label set. This test derives its expected
# labels from the menu that ::menu::BuildDropdown actually builds (and the
# static cascades ::menu::Dump fills), so a label that moves into the new
# ::menu::mc namespace without a translation is counted as English.

set ::scidb::test::trn::untranslatable [file join \
	[file dirname [file normalize [info script]]] fixtures menu-untranslatable.txt]


proc ::scidb::test::trn::Collect {menu var} {
	upvar 1 $var out
	if {[catch {$menu index end} last] || $last eq "none" || $last eq ""} { return }
	for {set i 0} {$i <= $last} {incr i} {
		set type [$menu type $i]
		if {$type eq "separator"} { continue }
		set label ""
		catch { set label [string trim [$menu entrycget $i -label]] }
		lappend out $label
		if {$type eq "cascade"} {
			set sub ""
			catch { set sub [$menu entrycget $i -menu] }
			if {$sub ne "" && [winfo exists $sub]} { ::scidb::test::trn::Collect $sub out }
		}
	}
	return
}

proc ::scidb::test::trn::DropdownLabels {} {
	catch { destroy .trncover }
	menu .trncover -tearoff 0
	::menu::BuildDropdown .trncover
	::menu::Dump .trncover
	set labels {}
	::scidb::test::trn::Collect .trncover labels
	destroy .trncover
	return $labels
}

proc ::scidb::test::trn::Untranslatable {} {
	set exempt {}
	if {![file exists $::scidb::test::trn::untranslatable]} { return $exempt }
	set fh [open $::scidb::test::trn::untranslatable r]
	set data [read $fh]
	close $fh
	foreach line [split $data \n] {
		set line [string trim $line]
		if {$line eq "" || [string index $line 0] eq "#"} { continue }
		lappend exempt [string trim [lindex [split $line \t] 0]]
	}
	return $exempt
}

proc ::scidb::test::trn::AskLabel {} {
	catch { destroy .trnask }
	menu .trnask -tearoff 0
	::context::Build C1 .trnask [dict create]
	set label ""
	catch { set label [string trim [.trnask entrycget 0 -label]] }
	destroy .trnask
	return $label
}

tcltest::test translations-live-dropdown-coverage {at most 5% of the live drop-down stays English per language} -body {
	set exempt [::scidb::test::trn::Untranslatable]
	if {[llength $exempt] > 15} { return "too-many-exemptions [llength $exempt]" }

	::menu::SwitchLanguage en
	set english [::scidb::test::trn::DropdownLabels]
	if {[llength $english] < 100} { return "short-dropdown [llength $english]" }
	set englishAsk [::scidb::test::trn::AskLabel]

	set ok 1
	set report {}
	foreach lang {de es it hu sv} {
		::menu::SwitchLanguage $lang
		set labels [::scidb::test::trn::DropdownLabels]
		set ask [::scidb::test::trn::AskLabel]
		if {$ask eq "" || $ask eq $englishAsk} {
			puts "VAL-BAR-009 $lang: ask row not translated: {$ask}"
			set ok 0
		}
		if {[llength $labels] != [llength $english]} {
			puts "VAL-BAR-009 $lang: label count [llength $labels] != [llength $english]"
			set ok 0
			continue
		}
		set identical {}
		foreach en $english loc $labels {
			if {$en eq $loc && [lsearch -exact $exempt $en] < 0} {
				lappend identical $en
			}
		}
		set count [llength $identical]
		set total [llength $english]
		puts "VAL-BAR-009 $lang: [llength $identical] of $total labels identical to English"
		if {$count} { puts "  IDENTICAL $lang: $identical" }
		if {$count * 20 > $total} { set ok 0 }
		lappend report [list $lang $count $total]
	}

	::menu::SwitchLanguage en
	if {!$ok} { return [list fail $report] }
	return ok
} -result ok

# Put the installed share directory back for the test files that follow.
if {[info exists ::scidb::test::trn::savedShare]} {
	set ::scidb::dir::share $::scidb::test::trn::savedShare
}


# Laptop run 190: View > Language > Deutsch left the app in English because
# the menu row passes the language's name and setLang matched only ids.
tcltest::test translations-language-row-switches {the View > Language row switches the UI language} -body {
	set m [menu .__langtest__ -tearoff 0]
	::menu::FillLanguage $m
	set got {}
	for {set i 0} {$i <= [$m index end]} {incr i} {
		if {[$m type $i] ne "command"} continue
		set label [string trim [$m entrycget $i -label]]
		if {$label ni {Deutsch Español}} continue
		$m invoke $i
		update
		lappend got $label $::mc::langID
	}
	destroy $m
	::menu::SwitchLanguage en
	lappend got $::mc::langID
} -result {Deutsch de Español es en}

tcltest::cleanupTests
