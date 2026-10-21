# ======================================================================
# Scidb App Test - the theme chosen in Settings > Theme survives a restart
# (gap G21). Each phase is a fresh app process with its own HOME, so the
# real startup and the real quit path run, not a simulation of them:
#
#   1. pick the theme in the settings menu, quit as the close button does;
#   2. start again - the app must come up with the chosen theme.
#
# The second test covers the same saved setting when it cannot be applied
# (a theme from another platform, or from a build that no longer ships
# it): starting must fall back to the default theme, not fail.
#
# See tests/fixtures/theme-restart/phase.tcl for the child script.
# ======================================================================
package require tcltest 2.5

namespace eval ::themePersistTest {
	variable root	[file dirname $::scidb::test::app::testDir]
	variable phase	[file join $::scidb::test::app::testDir fixtures theme-restart phase.tcl]
	variable theme	clam
}

proc ::themePersistTest::run {home which theme} {
	set limit {timeout 180}
	# macOS ships Perl but no GNU timeout.
	if {[tk windowingsystem] eq "aqua"} {
	    set limit {perl -e {alarm shift; exec @ARGV} 180}
	}
	catch {
		::util::execSafe {*}$limit env \
			HOME=$home \
			TH_ROOT=$::themePersistTest::root \
			TH_PHASE=$which \
			TH_THEME=$theme \
			[info nameofexecutable] $::themePersistTest::phase 2>@1
	} output
	# on a failure exec raises: its message is the child's combined output
	return $output
}

proc ::themePersistTest::home {} {
	set home [file join $::scidb::test::app::testDir tmp-app theme-restart-[pid]]
	file delete -force $home
	file mkdir $home
	return $home
}

tcltest::test theme-persist-restart {a theme picked in Settings > Theme comes back after a restart} -setup {
	set home [::themePersistTest::home]
	set theme $::themePersistTest::theme
} -body {
	set picked [::themePersistTest::run $home set $theme]
	set started [::themePersistTest::run $home get $theme]
	list \
		[regexp "THEME picked $theme $theme" $picked] \
		[regexp "THEME start $theme $theme $theme" $started]
} -cleanup {
	file delete -force $home
} -result {1 1}

tcltest::test theme-persist-stale {a saved theme that cannot be applied falls back to the default} -setup {
	set home [::themePersistTest::home]
} -body {
	set seeded [::themePersistTest::run $home seed-stale no-such-theme]
	set started [::themePersistTest::run $home get no-such-theme]
	list \
		[regexp {THEME seeded no-such-theme 1} $seeded] \
		[regexp {THEME start default default default} $started]
} -cleanup {
	file delete -force $home
} -result {1 1}

tcltest::cleanupTests
