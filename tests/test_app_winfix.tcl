# ======================================================================
# Scidb App Test — Windows findings: help contents filter, embedded file box
# ======================================================================
# On Windows the help contents are filtered (Unix-only pages dropped); the
# filter recursed on the whole contents instead of the nested group, so F1
# ended in "too many nested evaluations". The export dialog embeds the Tk
# file box; on Windows/macOS ::dialog::saveFile opened the native dialog
# instead and handed back a file name as the widget.
# ======================================================================

package require tcltest 2.5
tcltest::test winfix-help-filter {nested contents are filtered, not recursed on for ever} -body {
	set c {
		{ {{{A} {A.html}}} }
		{ {{{B} {B.html}}} {{{{C} {C.html}}} {{{D} {Unix.html}}}} }
	}
	::help::contents::FilterContents $c {Unix.html}
} -result {{{{{A} {A.html}}}} {{{{B} {B.html}}} {{{{C} {C.html}}}}}}
tcltest::test winfix-help-open {F1 opens the help window without a background error} -body {
	set ::winfixErr {}
	proc ::bgerror {msg} { set ::winfixErr $msg }
	::help::open .
	update
	after 1500 {set ::winfixWait 1}; vwait ::winfixWait
	list [winfo exists .help] $::winfixErr
} -result {1 {}}
tcltest::test winfix-embed {an embedded save box is a widget, not a native dialog} -body {
	toplevel .wf; ttk::notebook .wf.nb; pack .wf.nb
	set w [::dialog::saveFile -parent .wf.nb -embed 1 -initialfile x.pgn \
		-filetypes {{dummy .___}} -okcommand {list} -cancelcommand {list} -class export]
	set r [winfo exists $w]
	destroy .wf
	set r
} -result 1
tcltest::cleanupTests
