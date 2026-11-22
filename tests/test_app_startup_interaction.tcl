# ======================================================================
# Scidb App Test - deferred startup keeps a live view (GAP-001)
# ======================================================================
# Startup sets Vars(ready) and schedules Startup2.  Dictionary loading can
# yield across event-loop turns, so the user or an action can switch tabs,
# open a base/game, or move focus before Startup2 finishes.  Deferred
# startup must then leave the tab and keyboard alone.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::startupInteraction {
	# display:after is installed only when Startup2 finishes, so its absence
	# means the deferred call is still ahead of us (ready may already be 1).
	variable Natural [expr {![info exists ::application::Vars(display:after)]}]
	variable Interacted 0
	variable Expected {}
	variable GameSlot ""
}

puts [list STARTUP_INTERACTION natural $::startupInteraction::Natural]

if {$::startupInteraction::Natural} {
	# A fresh process: intercept the first deferred Startup2 before its body
	# runs and do what a user would do on the live window.
	proc ::startupInteraction::BeforeStartup2 {cmd op} {
		variable Natural
		variable Interacted
		variable Expected
		variable GameSlot

		if {!$Natural || $Interacted} { return }
		if {![info exists ::application::Vars(ready)] || !$::application::Vars(ready)} { return }
		set Interacted 1
		# A user action opens a game (which switches to the board), then the
		# user moves the keyboard to the board.
		::menu::gameNew .application
		set GameSlot [::scidb::game::current]
		set deadline [expr {[clock milliseconds] + 2000}]
		while {![winfo viewable .application.nb.board] && [clock milliseconds] < $deadline} {
			update
		}
		focus -force $::application::board::Vars(widget:frame)
		update idletasks
		set Expected [focus]
	}
	trace add execution ::application::Startup2 enter ::startupInteraction::BeforeStartup2
}

proc ::startupInteraction::Tick {{ms 10}} {
	variable tick
	set tick 0
	after $ms [list set [namespace current]::tick 1]
	vwait [namespace current]::tick
}

proc ::startupInteraction::WaitStartup2 {{timeout 30000}} {
	variable Interacted

	set deadline [expr {[clock milliseconds] + $timeout}]
	while {1} {
		update
		if {$Interacted && [info exists ::application::Vars(display:after)]} { return 1 }
		if {[clock milliseconds] > $deadline} { error {deferred startup did not finish} }
		::startupInteraction::Tick
	}
}

proc ::startupInteraction::CancelDeferredPanes {} {
	foreach id [after info] {
		if {[string match *DeferredStartup* [after info $id]]} { after cancel $id }
	}
}

proc ::startupInteraction::ReleaseGame {} {
	variable GameSlot

	if {$GameSlot eq ""} { return }
	catch { ::application::pgn::release $GameSlot }
	catch { ::game::release $GameSlot }
	set GameSlot ""
}

# In the combined single-process suite the app is already past its first
# Startup2.  Recreate the same deferred decision with the real Startup2:
# default view, ready bookkeeping, an interaction, then the after-1 call.
proc ::startupInteraction::Simulate {} {
	variable Expected

	set savedTab [::application::activeTab]
	set savedFocus [focus]
	set savedInteracted $::application::Vars(startup:interacted)
	set savedOpening $::application::Vars(startup:opening)
	set savedApplying $::application::Vars(startup:applyingView)
	set savedOwnFocus $::application::Vars(startup:ownFocus)
	set savedStartupTab $::application::Vars(startup:tab)

	::application::switchTab information
	set entry [::application::ask::Entry]
	if {$entry ne "" && [winfo exists $entry]} { focus -force $entry }
	update idletasks
	set ::application::Vars(startup:interacted) 0
	set ::application::Vars(startup:opening) 0
	set ::application::Vars(startup:applyingView) 0
	set ::application::Vars(startup:ownFocus) [focus]
	set ::application::Vars(startup:tab) [::application::activeTab]
	unset -nocomplain ::application::Vars(display:after)
	after 1 [namespace code ::application::Startup2]

	# The user acts before the deferred call runs.
	::menu::gameNew .application
	set ::startupInteraction::GameSlot [::scidb::game::current]
	set deadline [expr {[clock milliseconds] + 2000}]
	while {![winfo viewable .application.nb.board] && [clock milliseconds] < $deadline} {
		update
	}
	focus -force $::application::board::Vars(widget:frame)
	update idletasks
	set Expected [focus]
	set ::startupInteraction::Interacted 1
	::startupInteraction::WaitStartup2
	::startupInteraction::CancelDeferredPanes

	set result [list [::application::activeTab] [expr {[focus] eq $Expected}] \
		[expr {[focus] eq $entry}]]
	::startupInteraction::ReleaseGame

	set ::application::Vars(startup:interacted) $savedInteracted
	set ::application::Vars(startup:opening) $savedOpening
	set ::application::Vars(startup:applyingView) $savedApplying
	set ::application::Vars(startup:ownFocus) $savedOwnFocus
	set ::application::Vars(startup:tab) $savedStartupTab
	if {$savedTab ne "" && $savedTab ne [::application::activeTab]} {
		::application::switchTab $savedTab
	}
	if {$savedFocus ne "" && [winfo exists $savedFocus]} { focus -force $savedFocus }
	update idletasks
	return $result
}

tcltest::test startup-deferred-interaction-keeps-tab-and-focus {a tab switch and focus move before deferred Startup2 survive it} -body {
	if {$::startupInteraction::Natural} {
		::startupInteraction::WaitStartup2
		::startupInteraction::CancelDeferredPanes
		catch { destroy .tipoftheday }
		update idletasks
		set entry [::application::ask::Entry]
		list [::application::activeTab] [expr {[focus] eq $::startupInteraction::Expected}] \
			[expr {[focus] eq $entry}]
	} else {
		::startupInteraction::Simulate
	}
} -cleanup {
	::startupInteraction::ReleaseGame
	catch { destroy .tipoftheday }
} -result {board 1 0}

tcltest::test startup-bgstatus-shows-and-clears {background activity banner explains active tasks and hides when idle} -body {
	::application::bgstatus::show test-a "Loading player & rating index..."
	set t1 [::application::bgstatus::text]
	set vis1 [expr {[winfo exists .application.__bgstatus__]
		&& [winfo manager .application.__bgstatus__] eq "place"}]
	::application::bgstatus::show test-b "Saving player cache..."
	set t2 [::application::bgstatus::text]
	::application::bgstatus::clear test-b
	set t3 [::application::bgstatus::text]
	::application::bgstatus::clear test-a
	set t4 [::application::bgstatus::text]
	set vis4 [expr {[winfo exists .application.__bgstatus__]
		&& [winfo manager .application.__bgstatus__] eq "place"}]
	list $t1 $vis1 $t2 $t3 $t4 $vis4
} -cleanup {
	::application::bgstatus::clear test-a
	::application::bgstatus::clear test-b
} -result {{Background: Loading player & rating index...} 1 {Background (2): Saving player cache...} {Background: Loading player & rating index...} {} 0}

::tcltest::cleanupTests
