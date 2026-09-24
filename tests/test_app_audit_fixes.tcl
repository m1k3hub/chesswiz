# ======================================================================
# Scidb App Test — runtime regressions from the 2026-09-24 Tcl audit
#
# Each case exercises a code path that used to raise only when reached
# (undefined variable, invalid subcommand, wrong option name).
# ======================================================================

package require tcltest 2.5

tcltest::test audit-log-exists {::log::exists sees the namespace Log variable} -body {
	expr {[::log::exists] in {0 1}}
} -result 1

tcltest::test audit-twm-frozen-named {frozen? with a twm argument reads Frozen, not frozen} -body {
	::twm::frozen? .no-such-twm
} -result 0

tcltest::test audit-choosefont-geometry {-geometry is stored in the parsed options} -body {
	dict get [::dialog::choosefont::ParseArguments yes -geometry 300x200] geometry
} -result 300x200

tcltest::test audit-choosecolor-usercolors {-usercolors is accepted and normalised to rows of six} -body {
	set ::auditUserColors {red}
	::dialog::choosecolor::ParseArguments -usercolors ::auditUserColors
	llength $::auditUserColors
} -cleanup {
	unset -nocomplain ::auditUserColors
} -result 6

tcltest::test audit-choosecolor-bad-usercolor {an invalid user colour reports the option name} -body {
	set ::auditUserColors {no-such-colour}
	list [catch {::dialog::choosecolor::ParseArguments -usercolors ::auditUserColors} msg] $msg
} -cleanup {
	unset -nocomplain ::auditUserColors
} -result {1 {option "-usercolors": invalid color "no-such-colour"}}

tcltest::test audit-openingreport-fonts {opening-report text tags can be (re)created} -body {
	set t [text .auditOpeningReport]
	# force the create path, including deleting fonts left by earlier calls
	set ::application::tree::openingreport::Fonts {}
	::application::tree::openingreport::setupTextTags $t
	set ::application::tree::openingreport::Fonts {}
	::application::tree::openingreport::setupTextTags $t
	expr {[llength $::application::tree::openingreport::Fonts] > 0}
} -cleanup {
	destroy .auditOpeningReport
} -result 1

tcltest::cleanupTests
