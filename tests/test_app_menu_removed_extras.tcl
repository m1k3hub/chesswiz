# ======================================================================
# Scidb App Test - no user string names the removed Extras menu
# (GAP-003; VAL-BAR / VAL-KNOW menu redesign)
# ======================================================================
# The Extras catch-all no longer exists: model configuration moved to
# Tools > Choose Model…, the assistant to Tools > Assistant, rating updates
# to Database > Player Data, and the 3D entries are registry actions.  No
# user-visible Tcl string and no shipped help page may send anyone to the
# removed menu, under any separator the pages use.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::removedExtras {
	variable Root [file normalize [file join [file dirname [info script]] ..]]
}

# Lines which may keep the word: the translation catalogue's label entry
# (VAL-BAR-007 keeps every moved label translated) and identifiers which
# merely contain the letters.  Nothing here is a menu path.
proc ::removedExtras::Allowed {line} {
	if {[string match {set Extras*} [string trimleft $line]]} { return 1 }
	if {[string match {::menu::mc::Extras*} [string trimleft $line]]} { return 1 }
	if {[string match {*RegisterExtras*} $line]} { return 1 }
	if {[string match {*SelectExtra*} $line] || [string match {*DuplicateExtras*} $line]} { return 1 }
	return 0
}

proc ::removedExtras::Scan {file commentAware} {
	set ch [open $file rb]
	set data [read $ch]
	close $ch
	set bad {}
	set lineNo 0
	foreach line [split $data \n] {
		incr lineNo
		if {$commentAware && [string index [string trimleft $line] 0] eq "#"} { continue }
		if {[::removedExtras::Allowed $line]} { continue }
		# The old menu is gone, so any mention of it in a user string or a
		# help page is a stale path, whatever separator follows it.
		if {[string first {Extras} $line] >= 0} { lappend bad [list $file $lineNo Extras] }
	}
	return $bad
}

proc ::removedExtras::Files {} {
	variable Root
	return [lsort [::removedExtras::ProductFiles [file join $Root tcl]]]
}

# Every Tcl source and shipped help page below tcl/ can hold a user string,
# including the language catalogs and widgets. The generated tcl/chesswiz
# bundle is not a source file and is skipped by extension.
proc ::removedExtras::ProductFiles {dir} {
	set files {}
	foreach path [glob -nocomplain -directory $dir -types f *] {
		if {[file extension $path] in {.tcl .txt .html}} { lappend files $path }
	}
	foreach path [glob -nocomplain -directory $dir -types d *] {
		lappend files {*}[::removedExtras::ProductFiles $path]
	}
	return $files
}

tcltest::test menu-no-removed-extras-string {no product string or help page names the removed Extras menu} -body {
	set bad {}
	foreach file [::removedExtras::Files] {
		set commentAware [expr {[file extension $file] eq ".tcl"}]
		lappend bad {*}[::removedExtras::Scan $file $commentAware]
	}
	set bad
} -result {}

tcltest::test menu-removed-extras-none-in-help {every shipped help page is free of Extras} -body {
	set bad {}
	foreach file [::removedExtras::Files] {
		if {[file extension $file] in {.txt .html}} {
			lappend bad {*}[::removedExtras::Scan $file 0]
		}
	}
	set bad
} -result {}

tcltest::test menu-tools-choose-model-path {the replacement path is present in every listed module and English help} -body {
	set targets [list \
		[file join $::removedExtras::Root tcl app-setup-scan.tcl] \
		[file join $::removedExtras::Root tcl app-ai.tcl] \
		[file join $::removedExtras::Root tcl ai-provider.tcl] \
		[file join $::removedExtras::Root tcl player-data.tcl] \
		[file join $::removedExtras::Root tcl help en Welcome.txt]]
	set missing {}
	foreach file $targets {
		set ch [open $file rb]
		set data [read $ch]
		close $ch
		if {[string first {Tools > Choose Model} $data] < 0
			&& [string first {Tools &gt; Choose Model} $data] < 0} {
			lappend missing [file tail $file]
		}
	}
	set missing
} -result {}

tcltest::test menu-replacement-paths {rating updates and the 3D board name their real current route} -body {
	set card [file join $::removedExtras::Root tcl player-card.tcl]
	set ch [open $card rb]
	set cardText [read $ch]
	close $ch
	set bad {}
	if {[string first {Database > Player Data > Update Rating Data} $cardText] < 0} {
		lappend bad player-rating
	}
	foreach lang {en de es hu it} {
		foreach ext {txt html} {
			set file [file join $::removedExtras::Root tcl help $lang Welcome.$ext]
			set ch [open $file rb]
			set text [read $ch]
			close $ch
			if {[string first {Open 3D Board} $text] < 0} { lappend bad 3d-$lang-$ext }
		}
	}
	set bad
} -result {}

::tcltest::cleanupTests
