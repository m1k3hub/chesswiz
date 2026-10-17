# ======================================================================
# Scidb App Test - Ctrl+Q quits with Caps Lock or Shift held (Run 19-24)
# ======================================================================
package require tcltest 2.5

tcltest::test quit-key-case {Ctrl+Q is bound in both cases} -body {
	list [bind .application <Control-q>] [bind .application <Control-Q>]
} -result {::application::shutdown ::application::shutdown}

tcltest::cleanupTests
