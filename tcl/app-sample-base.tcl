# Bundled first-run content (kimi-review gaps G31 + G11 + G12).
#
# A fresh installation has no database to open, so the opening explorer
# ("No games available"), the repertoire trainer (only "Current game")
# and the insights are dead on day one. The sample database ships in
# share/sample/ beside the other data files (installed via "make
# install"), is built ONLY from TWIC master games
# (scripts/build-sample-db.sh, source PGN included), and the module
# opens it read-only at startup when the profile has none:
#
#   * opened read-only, once, with one line in the log;
#   * the user removes it like every other database, and the choice
#     lives in the options file -- it is never opened automatically
#     again (verified across processes by tests/test_sample_startup.tcl);
#   * with own or remembered databases nothing is opened.
#
# The database module (tcl/application.tcl's Startup2 calls
# ::application::database::preOpen) calls maybeOpen; the removal paths
# funnel through removeRecentFile. Tests override
# ::application::sample::File to point at the repository's sample.
::util::source sample-base

namespace eval application {
namespace eval sample {

variable File	{}		;# overridden by tests; "" = the installed sample location
variable Removed 0		;# persisted; set when the user removes the sample from the list

proc location {} {
	variable File

	if {[info exists File] && [llength $File]} { return $File }
	return [file join $::scidb::dir::share sample "Sample games.sci"]
}

proc maybeOpen {parent} {
	variable Removed

	if {$Removed || [llength [::process::arguments]]} { return }
	# the app-test harness (tests/run_app_tests.tcl) opens no sample
	# automatically: its many in-process test files must not see a
	# surprise database; the tests drive an automatic open themselves
	if {[namespace exist ::scidb::test::app] || [namespace exists ::RequestEval] || [namespace exists ::BoundsEval]} { return }
	set path [location]
	if {![file readable $path] || [::scidb::db::get open? $path]} { return }

	# Respect the user's own open or remembered databases.
	set builtins [list $::scidb::clipbaseName $::scidb::scratchbaseName $::scidb::mergebaseName]
	foreach base [$::application::database::Vars(switcher) bases] {
		if {$base ni $builtins} { return }
	}
	foreach entry [::application::database::recentFiles] {
		set file [lindex $entry 1]
		if {$file ne $path && [file readable $file]} { return }
	}

	if {[::application::database::openBase $parent $path no -readonly 1 -switchToBase 1]} {
		::application::database::LogOpen "Sample games: opened read-only"
	}
}

proc noteRecentFileRemoved {file} {
	variable Removed

	if {[::platform::sys::sameFile $file [location]]} { set Removed 1 }
}

proc WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Removed
}
::options::hookWriter [namespace current]::WriteOptions

} ;# namespace sample
} ;# namespace application
