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

::tcltest::cleanupTests
return