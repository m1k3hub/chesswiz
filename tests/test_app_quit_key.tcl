# ======================================================================
# Scidb App Test - Ctrl+Q quits with Caps Lock or Shift held (Run 19-24)
# ======================================================================
package require tcltest 2.5

# Check what the binding does: shutdown may be wrapped in uplevel #0.
proc ::scidb::test::app::quitBinding {sequence} {
	rename ::application::shutdown ::scidb::test::app::realShutdown
	proc ::application::shutdown {} { incr ::scidb::test::app::shutdownCalls }
	set ::scidb::test::app::shutdownCalls 0
	set rc [catch {uplevel #0 [bind .application $sequence]}]
	set calls $::scidb::test::app::shutdownCalls
	rename ::application::shutdown {}
	rename ::scidb::test::app::realShutdown ::application::shutdown
	unset ::scidb::test::app::shutdownCalls
	return [list $rc $calls]
}

tcltest::test quit-key-case {Ctrl+Q is bound in both cases} -body {
	list [::scidb::test::app::quitBinding <Control-q>] [::scidb::test::app::quitBinding <Control-Q>]
} -result {{0 1} {0 1}}

tcltest::test quit-key-board-focus {the board's plain-key bindings let Ctrl+key through} -body {
	# The test window is not mapped, so key events cannot be delivered; run the
	# binding script the way Tk would, with %s and %K substituted.
	set canv $::application::board::Vars(widget:frame)
	set script [bind $canv <Key-q>]
	set ctrl [catch {uplevel #0 [string map {%s 4 %K q} $script]}]
	list [expr {".application" in [bindtags $canv]}] $ctrl [::scidb::test::app::quitBinding <Control-q>]
} -result {1 4 {0 1}}

rename ::scidb::test::app::quitBinding {}

tcltest::cleanupTests
