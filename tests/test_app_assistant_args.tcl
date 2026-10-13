# ======================================================================
# Scidb App Test — closed-set tool-argument filling (tcl/app-assistant-args.tcl)
# ======================================================================
# The classifier is stubbed in-process: correctArgs is exercised for the
# override, the abstention, off, and shadow. No network, no model.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::args {
	variable Picked {}
	variable Calls 0
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app args_[pid]]
}

proc ::scidb::test::args::stub {picked} {
	variable Picked $picked
	variable Calls 0
	rename ::ai::systemone::chooseManySync ::scidb::test::args::realChooseManySync
	proc ::ai::systemone::chooseManySync {feature state questions args} {
		incr ::scidb::test::args::Calls
		return $::scidb::test::args::Picked
	}
}

proc ::scidb::test::args::unstub {} {
	catch { rename ::ai::systemone::chooseManySync {} }
	catch { rename ::scidb::test::args::realChooseManySync ::ai::systemone::chooseManySync }
}

proc ::scidb::test::args::isolated {body} {
	variable Picked
	set mode $::application::assistant::ArgsMode
	set backend $::ai::systemone::Config(backend)
	set messages $::application::assistant::Priv(messages)
	set errlog $::application::assistant::ErrorLogFile
	set Picked {}
	::ai::systemone::configure -backend kev
	if {![llength $::application::assistant::Priv(messages)]} {
		set ::application::assistant::Priv(messages) \
			[list [dict create role user content "switch to the database tab"]]
	}
	set code [catch { uplevel 1 $body } result]
	set ::application::assistant::ArgsMode $mode
	::ai::systemone::configure -backend $backend
	set ::application::assistant::Priv(messages) $messages
	set ::application::assistant::ErrorLogFile $errlog
	::scidb::test::args::unstub
	if {$code} { return -code error $result }
	return $result
}

tcltest::test args-enumargs {closed-set args are read from the tool schemas} -body {
	list [::application::assistant::enumArgs switch_tab] \
		[::application::assistant::enumArgs prepare_against] \
		[::application::assistant::enumArgs new_game] \
		[dict exists [::application::assistant::enumArgs search_games] pattern]
} -result {{tab {board database}} {color {white black}} {} 1}

tcltest::test args-descriptions {the schema's description of an argument is read} -body {
	list [dict get [::application::assistant::argDescriptions prepare_against] color] \
		[dict exists [::application::assistant::argDescriptions switch_tab] tab]
} -result {{the colour the opponent will play} 0}

tcltest::test args-default-shadow {the default mode is shadow, not active} -body {
	set ::application::assistant::ArgsMode
} -result shadow

tcltest::test args-active-overrides {a confident classifier value replaces the model's} -body {
	::scidb::test::args::isolated {
		::scidb::test::args::stub {tab database}
		set ::application::assistant::ArgsMode active
		::application::assistant::correctArgs switch_tab {tab board}
	}
} -result {tab database}

tcltest::test args-abstain-keeps {an abstention keeps the model's value} -body {
	::scidb::test::args::isolated {
		::scidb::test::args::stub {tab none}
		set ::application::assistant::ArgsMode active
		::application::assistant::correctArgs switch_tab {tab board}
	}
} -result {tab board}

tcltest::test args-unknown-ignored {a value outside the enum is never used} -body {
	::scidb::test::args::isolated {
		::scidb::test::args::stub {tab sideways}
		set ::application::assistant::ArgsMode active
		::application::assistant::correctArgs switch_tab {tab board}
	}
} -result {tab board}

tcltest::test args-off-untouched {off never asks and never corrects} -body {
	::scidb::test::args::isolated {
		::scidb::test::args::stub {tab database}
		set ::application::assistant::ArgsMode off
		set r [::application::assistant::correctArgs switch_tab {tab board}]
		list $r $::scidb::test::args::Calls
	}
} -result {{tab board} 0}

tcltest::test args-shadow-logs {shadow keeps the model's value and logs the comparison} -body {
	::scidb::test::args::isolated {
		::scidb::test::args::stub {tab database}
		set dir $::scidb::test::args::Dir
		file delete -force $dir
		set ::application::assistant::ErrorLogFile [file join $dir err.log]
		set ::application::assistant::ArgsMode shadow
		set r [::application::assistant::correctArgs switch_tab {tab board}]
		set file [file join $dir args-shadow.log]
		set text [expr {[file exists $file] ? [read [set c [open $file r]]] : ""}]
		catch { close $c }
		list $r [string match "*switch_tab.tab model=board classifier=database*" $text]
	}
} -result {{tab board} 1}

tcltest::test args-no-enum-no-call {a tool with no closed-set args is untouched} -body {
	::scidb::test::args::isolated {
		::scidb::test::args::stub {x y}
		set ::application::assistant::ArgsMode active
		set r [::application::assistant::correctArgs new_game {}]
		list $r $::scidb::test::args::Calls
	}
} -result {{} 0}

tcltest::cleanupTests
