# ======================================================================
# Scidb App Test - Ctrl+Q quits with Caps Lock or Shift held (Run 19-24)
# ======================================================================
package require tcltest 2.5

tcltest::test quit-key-case {Ctrl+Q is bound in both cases} -body {
	list [bind .application <Control-q>] [bind .application <Control-Q>]
} -result {::application::shutdown ::application::shutdown}

tcltest::test quit-key-board-focus {the board's plain-key bindings let Ctrl+key through} -body {
	# The test window is not mapped, so key events cannot be delivered; run the
	# binding script the way Tk would, with %s and %K substituted.
	set canv $::application::board::Vars(widget:frame)
	set script [bind $canv <Key-q>]
	set ctrl [catch {uplevel #0 [string map {%s 4 %K q} $script]}]
	list [expr {".application" in [bindtags $canv]}] $ctrl [bind .application <Control-q>]
} -result {1 4 ::application::shutdown}

tcltest::cleanupTests
