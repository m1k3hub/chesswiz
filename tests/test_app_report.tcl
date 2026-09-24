# ======================================================================
# Scidb App Test — HTML report stack (phase 2 render layer)
# ======================================================================
# Locks the ::scidb::db::guidingText / ::scidb::db::gameAnchor command
# contracts and the ::application::report viewer API (tcl/app-report.tcl)
# so a rename on either side cannot silently kill the report feature.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::appreport {}

tcltest::test report-guidingtext-command-exists {::scidb::db::guidingText is registered} -body {
	llength [info commands ::scidb::db::guidingText]
} -result 1

tcltest::test report-gameanchor-command-exists {::scidb::db::gameAnchor exists} -body {
	llength [info commands ::scidb::db::gameAnchor]
} -result 1

tcltest::test report-viewer-namespace-exists {::application::report::show is the entry point} -body {
	expr { [llength [info commands ::application::report::show]]
	     && [llength [info commands ::application::report::Load]]
	     && [llength [info commands ::application::report::LinkClick]] }
} -result 1

tcltest::test report-guidingtext-bad-index {guidingText rejects a negative game index} -body {
	set rc [catch { ::scidb::db::guidingText [::scidb::db::get clipbase name] Normal -1 } msg]
	expr { $rc == 1 }
} -result 1

tcltest::test report-guidingtext-nonreport-index {guidingText returns isGuiding=0 for out-of-range} -body {
	set data [::scidb::db::guidingText [::scidb::db::get clipbase name] Normal 999999]
	list [dict get $data isGuiding] [dict get $data html]
} -result {0 {}}

tcltest::test report-gameanchor-out-of-range {gameAnchor returns -1 for garbage args} -body {
	::scidb::db::gameAnchor [::scidb::db::get clipbase name] Normal \
		{Nobody,First,Nobody2,Second,NoEvent,NoSite,0,0}
} -result -1

tcltest::test report-viewer-image-fallback {Image returns {} for missing files} -body {
	llength [::application::report::Image /nonexistent/file.jpg]
} -result 0

# ----------------------------------------------------------------------
# Regression: scrolledframe's TScrollbar press binds are brace-quoted, so
# [namespace current] was evaluated when the button was pressed (at global
# scope). It built the bogus variable ::::(sbset:orient) instead of the
# widget's own, which raised "can't set ::::(sbset:orient): variable isn't
# array" on clicking any scrollbar -- including the report pane's.
# ----------------------------------------------------------------------

tcltest::test widget-scrollbar-press-bind-targets-namespace {the press bind names ::scrolledframe} -body {
	set script [bind TScrollbar <ButtonPress-1>]
	expr { [string match {*::scrolledframe*} $script]
	     && ![string match {*namespace current*} $script] }
} -result 1

tcltest::test widget-scrollbar-press-sets-namespace-var {the press bind writes scrolledframe's own orient var} -body {
	set sb [ttk::scrollbar .sbregtest -orient vertical]
	set bound [bind TScrollbar <ButtonPress-1>]
	# the ttk class prologue needs %x/%y; the appended (scrolledframe) part is last
	eval [string map [list %W $sb] [lindex [split $bound "\n"] end]]
	set value [set ::scrolledframe::(sbset:orient)]
	destroy $sb
	set value
} -result vertical

# ----------------------------------------------------------------------
# Regression: tkhtml lays a document out at -fixedwidth. Left unset, the
# widget wrapper falls back to the document's minbbox (the widest single
# WORD), so every line wrapped after a few characters -- the report text
# appeared in a ~90px column inside a ~715px pane.
# ----------------------------------------------------------------------

proc ::scidb::test::appreport::inner {} {
	return $::application::report::Priv(html).sub.html
}

tcltest::test report-pane-sets-document-width {the report pane lays the document out at the pane width} -body {
	set data [::scidb::html::sanitize \
		"<p>Hello world, this is a sentence of ordinary length used to probe the layout.</p>" ""]
	::application::report::showHtmlData .application "width probe" $data
	update idletasks
	set inner [::scidb::test::appreport::inner]
	if {![winfo exists $inner]} { return unavailable }
	# a real document width, not the widest-word fallback
	expr { [$inner cget -fixedwidth] > 100 }
} -result 1

tcltest::test report-pane-width-tracks-the-widget {the document width does not exceed the widget} -body {
	set inner [::scidb::test::appreport::inner]
	if {![winfo exists $inner]} { return unavailable }
	expr { [$inner cget -fixedwidth] <= [winfo width $inner] }
} -result 1

# ----------------------------------------------------------------------
# The report (and with it "AI: Explain Position") is a pane of the board
# layout, not a free toplevel, so it can be docked and undocked.
# ----------------------------------------------------------------------

tcltest::test report-is-a-dockable-pane {the report lives in the board twm and is undockable} -body {
	set twm [::application::twm board]
	list [expr {"report" in [$twm leaves]}] [expr {!![$twm isundockable report]}] [winfo exists .report]
} -result {1 1 0}

tcltest::test report-reuses-its-pane {showing a second document reuses the open pane} -body {
	set w1 $::application::report::Priv(window)
	set data [::scidb::html::sanitize "<p>second</p>" ""]
	set w2 [::application::report::showHtmlData .application "second" $data]
	list [expr {$w1 eq $w2}] $::application::report::PaneTitle
} -result {1 {Report (second)}}

tcltest::test report-pane-reopens-after-close {closing the pane and showing again rebuilds it} -body {
	set twm [::application::twm board]
	destroy [$twm leaf report]
	update idletasks
	set gone [expr {"report" ni [$twm leaves]}]
	set data [::scidb::html::sanitize "<p>third</p>" ""]
	set w [::application::report::showHtmlData .application "third" $data]
	list $gone [winfo exists $w] [expr {"report" in [$twm leaves]}]
} -result {1 1 1}


tcltest::test report-pane-survives-undock {undocking floats the pane and keeps the document} -body {
	set twm [::application::twm board]
	set w $::application::report::Priv(window)
	::twm::Undock $twm [$twm leaf report]
	update idletasks
	set top [$twm toplevel [$twm leaf report]]
	set data [::scidb::html::sanitize "<p>floating</p>" ""]
	set w2 [::application::report::showHtmlData .application "floating" $data]
	list [$twm isfloat $top] [expr {$w eq $w2}] [winfo exists [::scidb::test::appreport::inner]]
} -result {1 1 1}


# ----------------------------------------------------------------------

::tcltest::cleanupTests
return
