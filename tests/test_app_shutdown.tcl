# G01: closing auxiliary windows must not request an application shutdown.
package require tcltest 2.5

namespace eval ::scidb::test::app::shutdown {
	variable calls {}
	proc guard {command op} {
		variable calls
		lappend calls $command
		error "unexpected application termination: $command"
	}
	proc alive {} {
		variable calls
		list [winfo exists .application] [winfo exists .application.shutdown] $calls
	}
	proc closeWindow {w mode} {
		if {![winfo exists $w]} { error "dialog was not created: $w" }
		if {$mode eq "wm"} {
			set script [wm protocol $w WM_DELETE_WINDOW]
			if {$script eq ""} { set script [list destroy $w] }
			uplevel #0 $script
		} else {
			destroy $w
		}
		update idletasks
	}
}
set shutdownGuard ::scidb::test::app::shutdown::guard
foreach command {::application::shutdown ::application::prepareExit ::exit} {
	trace add execution $command enter $shutdownGuard
}

# Exercise both constructors, all dialog classes, root children and nested
# toplevels. Descendants explicitly carry the main bindtag, as app panes do.
foreach constructor {::toplevel ::tk::toplevel} {
	foreach class {Scidb Dialog Toplevel} {
		foreach parent {. .application} {
			foreach mode {wm destroy} {
				tcltest::test shutdown-child-$constructor-$class-$parent-$mode {auxiliary destruction never exits through the main Destroy binding} -body {
					set w [expr {$parent eq "." ? ".g01" : "$parent.g01"}]
					$constructor $w -class $class
					ttk::frame $w.child
					bindtags $w.child [linsert [bindtags $w.child] 0 .application]
					destroy $w.child
					::scidb::test::app::shutdown::closeWindow $w $mode
					::scidb::test::app::shutdown::alive
				} -cleanup { catch {destroy $w} } -result {1 0 {}}
			}
		}
	}
}

# Actual constructors with explicit close callbacks and Destroy cleanup.
# These cover a nested editor, an engine/pipe dialog, a separate help window,
# the shared trace window, a no-button messagebox and progress dialogs.
foreach {type w open} {
	book .application.__book__ {::book::openEditor .application}
	engine .application.playengine {::playengine::open .application}
	help .help {::help::open .application}
	tips .tipoftheday {::tips::open .application}
	trace .application.g01trace {::widget::showTrace .application.g01trace test 0 {destroy .application.g01trace}}
	message .application.g01message {set w [::dialog::alert -parent .application -message test -buttons {}]}
	progress .application.g01progress {::dialog::progressbar::open .application.g01progress -parent .application}
} {
	foreach mode {wm destroy} {
		tcltest::test shutdown-dialog-$type-$mode {real auxiliary close callbacks leave the app running} -body {
			set ::scidb::test::app::shutdown::calls {}
			eval $open
			::scidb::test::app::shutdown::closeWindow $w $mode
			# Progress windows deliberately ignore the close protocol while busy.
			if {[winfo exists $w]} { destroy $w }
			::scidb::test::app::shutdown::alive
		} -cleanup { catch {destroy $w} } -result {1 0 {}}
	}
}

foreach command {::application::shutdown ::application::prepareExit ::exit} {
	trace remove execution $command enter $shutdownGuard
}

tcltest::testConstraint shutdownLogging $::debuglog::enabled
tcltest::test shutdown-entry-log {real shutdown entry logs a stack even when a modal window prevents quitting} -constraints shutdownLogging -body {
	set w .application.g01grab
	tk::toplevel $w -class Dialog
	grab $w
	::application::shutdown
	grab release $w
	destroy $w
	set fd [open $::debuglog::file]
	set text [read $fd]
	close $fd
	list [::scidb::test::app::shutdown::alive] \
		[regexp {\[shutdown\] enter ::application::shutdown depth=[0-9]+ stack=} $text]
} -cleanup {
	catch {grab release $w}
	catch {destroy $w}
} -result {{1 0 {}} 1}

unset shutdownGuard
namespace delete ::scidb::test::app::shutdown
tcltest::cleanupTests
