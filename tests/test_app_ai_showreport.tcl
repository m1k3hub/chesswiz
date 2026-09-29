# ======================================================================
# Scidb App Test — ::application::ai::showReport takes a page or its data
# ======================================================================
# Found by driving the real app: reports whose callers pass the dict that
# ::application::ai::htmlData returns (brief, study plan, annotate, trends,
# CQL reports, ...) were sanitized a second time, so the Report pane showed
# the Tcl text 'html {...} title {} media {} ...' around the page.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::showreport {
	variable Got {}
}

proc ::scidb::test::showreport::record {parent title data} {
	lappend ::scidb::test::showreport::Got $data
	return ""
}

tcltest::test showreport-dict-not-wrapped {an already sanitized page reaches the report pane as it is} -setup {
	set ::scidb::test::showreport::Got {}
	rename ::application::report::showHtmlData ::scidb::test::showreport::realShow
	rename ::scidb::test::showreport::record ::application::report::showHtmlData
} -body {
	set data [::application::ai::htmlData "<p>Trend <b>facts</b></p>"]
	::application::ai::showReport .application "AI: test" $data
	set got [lindex $::scidb::test::showreport::Got 0]
	list [expr {$got eq $data}] \
		[string match {*Trend*facts*} [dict get $got html]] \
		[string match {html *} [dict get $got html]] \
		[string match {*title {}*} [dict get $got html]]
} -cleanup {
	rename ::application::report::showHtmlData ::scidb::test::showreport::record
	rename ::scidb::test::showreport::realShow ::application::report::showHtmlData
} -result {1 1 0 0}

tcltest::test showreport-html-is-sanitized {plain HTML is still sanitized into data} -setup {
	set ::scidb::test::showreport::Got {}
	rename ::application::report::showHtmlData ::scidb::test::showreport::realShow
	rename ::scidb::test::showreport::record ::application::report::showHtmlData
} -body {
	::application::ai::showReport .application "AI: test" "<p>plain page</p>"
	set got [lindex $::scidb::test::showreport::Got 0]
	list [dict exists $got html] [string match {*plain page*} [dict get $got html]] \
		[::application::ai::IsHtmlData $got] [::application::ai::IsHtmlData "<p>plain page</p>"]
} -cleanup {
	rename ::application::report::showHtmlData ::scidb::test::showreport::record
	rename ::scidb::test::showreport::realShow ::application::report::showHtmlData
} -result {1 1 1 0}

::tcltest::cleanupTests
return
