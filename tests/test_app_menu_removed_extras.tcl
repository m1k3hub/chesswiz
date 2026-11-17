# ======================================================================
# Scidb App Test - no user string names the removed Extras > AI menu
# (GAP-003; VAL-BAR / VAL-KNOW menu redesign)
# ======================================================================
# Model configuration moved to Tools > Choose Model… and the assistant to
# Tools > Assistant.  User-visible Tcl strings and the shipped help pages
# must not send anyone to a menu that no longer exists.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::removedExtras {
	variable Root [file normalize [file join [file dirname [info script]] ..]]
	variable Patterns {
		{Extras > AI}
		{Extras &gt; AI}
		{Extras&#x27a2;AI}
		{Extras &#x27a2; AI}
		{AI: Choose Model}
		{AI: Choose &Model}
	}
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
		foreach pattern $::removedExtras::Patterns {
			if {[string first $pattern $line] >= 0} {
				lappend bad [list $file $lineNo $pattern]
				break
			}
		}
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

tcltest::test menu-no-removed-extras-ai-string {no product or help string names Extras > AI or AI: Choose Model} -body {
	set bad {}
	foreach file [::removedExtras::Files] {
		set commentAware [expr {[file extension $file] eq ".tcl"}]
		lappend bad {*}[::removedExtras::Scan $file $commentAware]
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

::tcltest::cleanupTests
