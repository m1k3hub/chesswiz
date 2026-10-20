# ======================================================================
# View > Panes rows are real toggles (VAL-REG-010)
# ======================================================================
# Every posted pane row is a checkbutton bound to one registry action. The
# action asks the layout, never the check mark: a visible pane is hidden, an
# absent but openable pane is created through ::application::openPane, and a
# pane kind this build cannot create is posted disabled with a reason.
# Each id is invoked twice (hide/show or open/hide) by id and by the posted
# row's own -command; the twm leaves and the posted check mark are asserted
# after every call. The five dynamic Game rows are invoked as well.
# A pane hidden while the board still had a delayed rebuild queued for its
# canvas (a window resize) must drop that rebuild with the canvas: the last
# test reproduces the state that made the next file fail.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::pane {}

proc ::scidb::test::pane::Suffixes {} {
	return {board editor games players events sites annotators positions tree analysis media report assistant explorer}
}

proc ::scidb::test::pane::Leaves {} {
	set twm [::menu::PaneTWM]
	if {$twm eq ""} { return {} }
	return [$twm leaves]
}

# Restore the layout a test found. A test must not leave a hidden or an
# extra pane for the files that run after it.
proc ::scidb::test::pane::Restore {initial} {
	set twm [::menu::PaneTWM]
	if {$twm eq ""} { return }
	foreach uid [$twm leaves] {
		if {$uid ni $initial} {
			catch { ::application::twm::ChangeState $twm $uid }
		}
	}
	foreach uid $initial {
		if {$uid ni [$twm leaves]} {
			catch { ::application::openPane $uid }
		}
	}
	update idletasks
}

proc ::scidb::test::pane::PostFill {menu} {
	set pc ""
	catch { set pc [$menu cget -postcommand] }
	if {$pc ne ""} { catch { uplevel #0 $pc } }
	set n [$menu index end]
	if {$n eq "" || $n eq "none"} { return }
	for {set i 0} {$i <= $n} {incr i} {
		if {[$menu type $i] ne "cascade"} { continue }
		set sub ""
		catch { set sub [$menu entrycget $i -menu] }
		if {$sub ne "" && [winfo exists $sub]} {
			::scidb::test::pane::PostFill $sub
		}
	}
}

proc ::scidb::test::pane::FillView {menu} {
	set view $menu.[::menu::WidgetName [::menu::MC View]]
	if {![winfo exists $view]} { return "" }
	::scidb::test::pane::PostFill $view
	return $view
}

proc ::scidb::test::pane::FindRow {menu id} {
	set want "::action::run $id"
	set n [$menu index end]
	if {$n eq "" || $n eq "none"} { return "" }
	for {set i 0} {$i <= $n} {incr i} {
		set cmd ""
		catch { set cmd [string trim [$menu entrycget $i -command]] }
		if {$cmd eq $want} { return $i }
	}
	return ""
}

proc ::scidb::test::pane::RowState {menu index} {
	set type ""
	set state ""
	set var ""
	set checked ""
	catch { set type [$menu type $index] }
	catch { set state [$menu entrycget $index -state] }
	catch { set var [$menu entrycget $index -variable] }
	if {$var ne "" && [info exists $var]} { set checked [set $var] }
	return [list $type $state $var $checked]
}

proc ::scidb::test::pane::Nop {args} { return 0 }

proc ::scidb::test::pane::Base {dir name games} {
	file mkdir $dir
	set file [file join $dir ${name}_[pid].sci]
	file delete {*}[glob -nocomplain [file rootname $file].*]
	set fh [open ${file}.pgn w]
	for {set i 0} {$i < $games} {incr i} {
		puts $fh "\[Event \"Event $i\"\]\n\[White \"W$i\"\]\n\[Black \"B$i\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 2. Nf3 Nc6 *\n"
	}
	close $fh
	::scidb::db::open ${file}.pgn ::scidb::test::pane::Nop {} ::scidb::test::pane::Nop {}
	::scidb::db::new $file Normal [::application::database::lookupType OpeningsWhite]
	::scidb::db::attach $file $file
	::scidb::db::copy ${file}.pgn $file {} ::scidb::test::pane::Nop {} ::scidb::test::pane::Nop {}
	::scidb::db::save $file ::scidb::test::pane::Nop {}
	::scidb::db::close ${file}.pgn
	file delete ${file}.pgn
	return $file
}

proc ::scidb::test::pane::Stash {cmd} {
	return ::scidb::test::pane::Saved[string map {:: _} $cmd]
}

proc ::scidb::test::pane::Capture {cmd body} {
	rename $cmd [::scidb::test::pane::Stash $cmd]
	proc $cmd args $body
}

proc ::scidb::test::pane::Release {cmd} {
	set stash [::scidb::test::pane::Stash $cmd]
	rename $cmd {}
	rename $stash $cmd
}

# Record background errors instead of showing them (a notice card in a
# headless run), and put the application's handler back afterwards.
proc ::scidb::test::pane::CaptureBgErrors {} {
	if {[llength [info commands ::scidb::test::pane::SavedBg]]} { return }
	if {[llength [info commands ::scidb::bgerror]]} {
		rename ::scidb::bgerror ::scidb::test::pane::SavedBg
	}
	proc ::scidb::bgerror {err args} {
		lappend ::scidb::test::pane::errors $err
	}
}

proc ::scidb::test::pane::ReleaseBgErrors {} {
	catch { rename ::scidb::bgerror {} }
	if {[llength [info commands ::scidb::test::pane::SavedBg]]} {
		rename ::scidb::test::pane::SavedBg ::scidb::bgerror
	}
	interp bgerror {} ::scidb::bgerror
}

tcltest::test pane-rows-posted-state {every View > Panes row is a stateful checkbutton} -setup {
	set ::scidb::test::pane::initial [::scidb::test::pane::Leaves]
	catch { destroy .paneMenu }
	menu .paneMenu -tearoff 0
	::menu::BuildDropdown .paneMenu
	set ::scidb::test::pane::view [::scidb::test::pane::FillView .paneMenu]
} -body {
	set panes ""
	catch { set panes [::menu::WidgetName [::menu::MC View]] }
	# Find the Panes cascade inside View.
	set sub ""
	set n [$::scidb::test::pane::view index end]
	for {set i 0} {$i <= $n} {incr i} {
		if {[$::scidb::test::pane::view type $i] ne "cascade"} { continue }
		if {[string trim [$::scidb::test::pane::view entrycget $i -label]] eq "Panes"} {
			set sub [$::scidb::test::pane::view entrycget $i -menu]
			break
		}
	}
	if {$sub eq "" || ![winfo exists $sub]} { return "no Panes cascade" }
	::scidb::test::pane::PostFill $sub
	set dump {}
	set bad {}
	foreach suffix [::scidb::test::pane::Suffixes] {
		set id menu.view.panes.$suffix
		set index [::scidb::test::pane::FindRow $sub $id]
		set openable [::menu::PaneOpenable $suffix]
		set reason [::menu::PaneReason $suffix]
		if {!$openable} {
			# a pane this layout cannot open is not posted (a disabled Tk
			# menu row can never show its reason); the action says why
			if {$index ne ""} { lappend bad [list $suffix posted-unopenable] }
			if {$reason eq ""} { lappend bad [list $suffix no-reason] }
			set msg [::action::run $id]
			if {![string match "*$reason*" $msg] && ![string match "*not enabled*" $msg]} {
				lappend bad [list $suffix run-msg $msg]
			}
			lappend dump [list $suffix not-posted $reason]
			continue
		}
		if {$index eq ""} { lappend bad [list $suffix missing]; continue }
		lassign [::scidb::test::pane::RowState $sub $index] type state var checked
		lappend dump [list $suffix $type $state $checked $openable]
		if {$type ne "checkbutton"} { lappend bad [list $suffix type $type] }
		if {$openable} {
			if {$state ne "normal"} { lappend bad [list $suffix state $state] }
			if {$reason ne ""} { lappend bad [list $suffix reason $reason] }
		}
		set want [expr {[::menu::PaneChecked $suffix] ? 1 : 0}]
		if {$checked ne $want} { lappend bad [list $suffix checked $checked $want] }
	}
	puts "REG-010 pane rows: $dump"
	foreach b $bad { puts "  bad: $b" }
	list [llength $bad] $bad
} -cleanup {
	catch { destroy .paneMenu }
	::scidb::test::pane::Restore $::scidb::test::pane::initial
} -result {0 {}}

tcltest::test pane-toggles-by-id {every pane id toggles twice and leaves follow} -setup {
	set ::scidb::test::pane::initial [::scidb::test::pane::Leaves]
	catch { destroy .paneMenu }
	menu .paneMenu -tearoff 0
	::menu::BuildDropdown .paneMenu
} -body {
	set report {}
	set bad {}
	foreach suffix [::scidb::test::pane::Suffixes] {
		set id menu.view.panes.$suffix
		if {[catch { ::action::get $id }]} { lappend bad [list $suffix unresolved]; continue }
		set uid [::menu::PaneLayoutUid $suffix]
		set openable [::menu::PaneOpenable $suffix]
		set had [expr {$uid ne "" && $uid in [::scidb::test::pane::Leaves]}]
		set rc1 [catch { ::action::run $id } err1]
		update idletasks
		set leaves1 [::scidb::test::pane::Leaves]
		set after1 [expr {$uid ne "" && $uid in $leaves1}]
		set check1 [::menu::PaneChecked $suffix]
		set rc2 [catch { ::action::run $id } err2]
		update idletasks
		set leaves2 [::scidb::test::pane::Leaves]
		set after2 [expr {$uid ne "" && $uid in $leaves2}]
		set check2 [::menu::PaneChecked $suffix]
		lappend report [list $suffix $uid $had $after1 $after2 $check1 $check2 [list $rc1 $rc2]]
		puts "REG-010 id $suffix uid={$uid} had=$had after1=$after1 after2=$after2 check=$check1/$check2 rc={$rc1 $rc2} err={$err1 | $err2}"
		if {$openable} {
			if {$after1 eq $had} { lappend bad [list $suffix first-no-effect] }
			if {$after2 ne $had} { lappend bad [list $suffix second-no-restore $after2 $had] }
			if {$check1 != $after1} { lappend bad [list $suffix check1 $check1 $after1] }
			if {$check2 != $after2} { lappend bad [list $suffix check2 $check2 $after2] }
		} else {
			if {$after1 ne $had || $after2 ne $had} { lappend bad [list $suffix disabled-changed] }
			if {![string match "error:*" $err1] || ![string match "error:*" $err2]} {
				lappend bad [list $suffix disabled-not-explained $err1 $err2]
			}
		}
	}
	list [llength $bad] $bad
} -cleanup {
	catch { destroy .paneMenu }
	::scidb::test::pane::Restore $::scidb::test::pane::initial
} -result {0 {}}

tcltest::test pane-toggles-by-click {posted pane rows toggle twice and the check mark follows} -setup {
	set ::scidb::test::pane::initial [::scidb::test::pane::Leaves]
	catch { destroy .paneMenu }
	menu .paneMenu -tearoff 0
	::menu::BuildDropdown .paneMenu
	set ::scidb::test::pane::view [::scidb::test::pane::FillView .paneMenu]
} -body {
	set sub ""
	set n [$::scidb::test::pane::view index end]
	for {set i 0} {$i <= $n} {incr i} {
		if {[$::scidb::test::pane::view type $i] ne "cascade"} { continue }
		if {[string trim [$::scidb::test::pane::view entrycget $i -label]] eq "Panes"} {
			set sub [$::scidb::test::pane::view entrycget $i -menu]
			break
		}
	}
	if {$sub eq ""} { return "no Panes cascade" }
	::scidb::test::pane::PostFill $sub
	set bad {}
	foreach suffix [::scidb::test::pane::Suffixes] {
		set id menu.view.panes.$suffix
		set index [::scidb::test::pane::FindRow $sub $id]
		if {![::menu::PaneOpenable $suffix]} {
			# not posted: nothing to click (see pane-rows-posted-state)
			if {$index ne ""} { lappend bad [list $suffix posted-unopenable] }
			continue
		}
		if {$index eq ""} { lappend bad [list $suffix missing]; continue }
		set cmd [string trim [$sub entrycget $index -command]]
		set uid [::menu::PaneLayoutUid $suffix]
		set had [expr {$uid ne "" && $uid in [::scidb::test::pane::Leaves]}]
		set rc1 [catch { uplevel #0 $cmd } err1]
		update idletasks
		set after1 [expr {$uid ne "" && $uid in [::scidb::test::pane::Leaves]}]
		set rc2 [catch { uplevel #0 $cmd } err2]
		update idletasks
		set after2 [expr {$uid ne "" && $uid in [::scidb::test::pane::Leaves]}]
		lassign [::scidb::test::pane::RowState $sub $index] type state var checked
		set openable [::menu::PaneOpenable $suffix]
		puts "REG-010 click $suffix had=$had after1=$after1 after2=$after2 row={$type $state $checked} rc={$rc1 $rc2}"
		if {$openable} {
			if {$after1 eq $had} { lappend bad [list $suffix click-no-effect] }
			if {$after2 ne $had} { lappend bad [list $suffix click-no-restore] }
			if {$checked ne [expr {$after2 ? 1 : 0}]} {
				lappend bad [list $suffix click-check $checked $after2]
			}
		} else {
			if {$state ne "disabled"} { lappend bad [list $suffix not-disabled $state] }
			if {$after1 ne $had || $after2 ne $had} { lappend bad [list $suffix click-changed] }
		}
	}
	list [llength $bad] $bad
} -cleanup {
	catch { destroy .paneMenu }
	::scidb::test::pane::Restore $::scidb::test::pane::initial
} -result {0 {}}

tcltest::test dynamic-game-ids-invoke {the five dynamic Game ids dispatch with an effect} -setup {
	set ::scidb::test::pane::initial [::scidb::test::pane::Leaves]
	catch { destroy .paneMenu }
	menu .paneMenu -tearoff 0
	::menu::BuildDropdown .paneMenu
} -body {
	set bad {}
	foreach id {
		menu.game.paste_clip menu.game.paste_tab
		menu.game.merge_clip menu.game.merge_tab
		menu.game.history.recent
	} {
		if {[catch { ::action::get $id }]} { lappend bad [list $id unresolved] }
	}
	# paste_clip copies the remembered games into the open target database.
	set dir [file join [::tcltest::temporaryDirectory] pane-[pid]]
	set ::scidb::test::pane::dir $dir
	catch { ::game::clipboard::clear }
	set src [::scidb::test::pane::Base $dir src 1]
	set dst [::scidb::test::pane::Base $dir dst 1]
	set before [::scidb::db::count games $dst Normal]
	set copied [::game::clipboard::copy $src Normal {0}]
	set rc [::action::run menu.game.paste_clip [dict create base $dst variant Normal]]
	set after [::scidb::db::count games $dst Normal]
	puts "REG-010 paste_clip copied=$copied before=$before after=$after rc={$rc}"
	if {!$copied || $after != $before + 1} { lappend bad [list paste_clip $copied $before $after $rc] }

	# paste_tab reaches the clipboard importer.
	set ::scidb::test::pane::calls 0
	::scidb::test::pane::Capture ::application::pgn::PasteClipboardGame {
		incr ::scidb::test::pane::calls
		return
	}
	set rc [catch { ::action::run menu.game.paste_tab } err]
	::scidb::test::pane::Release ::application::pgn::PasteClipboardGame
	puts "REG-010 paste_tab calls=$::scidb::test::pane::calls rc={$rc $err}"
	if {$::scidb::test::pane::calls != 1} { lappend bad [list paste_tab $::scidb::test::pane::calls $err] }

	# merge_clip and merge_tab reach the merge handler with the application
	# window and the current game slot.
	foreach id {menu.game.merge_clip menu.game.merge_tab} {
		set ::scidb::test::pane::calls {}
		::scidb::test::pane::Capture ::gamebar::mergeGame {
			lappend ::scidb::test::pane::calls $args
			return
		}
		set rc [catch { ::action::run $id } err]
		::scidb::test::pane::Release ::gamebar::mergeGame
		puts "REG-010 $id calls={$::scidb::test::pane::calls} rc={$rc $err}"
		if {$::scidb::test::pane::calls ne {{.application -1}}} {
			lappend bad [list $id $::scidb::test::pane::calls $err]
		}
	}

	# history.recent switches to the first remembered game.
	set ::scidb::test::pane::switched {}
	::scidb::test::pane::Capture ::game::gameList { return {{0 fake}} }
	::scidb::test::pane::Capture ::scidb::game::switch {
		lappend ::scidb::test::pane::switched $args
		return
	}
	set rc [catch { ::action::run menu.game.history.recent } err]
	::scidb::test::pane::Release ::scidb::game::switch
	::scidb::test::pane::Release ::game::gameList
	puts "REG-010 history.recent switched={$::scidb::test::pane::switched} rc={$rc $err}"
	if {$::scidb::test::pane::switched ne {0}} {
		lappend bad [list history.recent $::scidb::test::pane::switched $err]
	}
	list [llength $bad] $bad
} -cleanup {
	::game::clipboard::clear
	catch { file delete -force $::scidb::test::pane::dir }
	catch { destroy .paneMenu }
	::scidb::test::pane::Restore $::scidb::test::pane::initial
} -result {0 {}}

# A window resize reaches the board canvas as <Configure> -> ConfigureWindow,
# which queues the rebuild 50-300 ms later, holding the canvas path. Hiding the
# pane inside that window left the timer behind: it fired in the next test file
# as a background error ("invalid command name ...board.c") -- the notice a
# user gets after resizing the window and then switching View > Panes > Board
# off. The rebuild must go with the canvas it was queued for: the timer is
# cancelled, and nothing fires at a dead widget path. (Other deferred board
# work that a destroyed pane leaves behind is noted in tests/tmp-app/finish/
# menupred.md; only the rebuild is this test's subject.)
tcltest::test pane-hide-drops-queued-board-rebuild {hiding the Board pane cancels the rebuild queued for its canvas} -setup {
	set ::scidb::test::pane::initial [::scidb::test::pane::Leaves]
	set ::scidb::test::pane::errors {}
	::scidb::test::pane::CaptureBgErrors
	# Turn the event loop once while the board is still on screen: the
	# startup timers (Startup2 and friends) belong to the running app, and
	# this test must not be the first to run them against a hidden board.
	# What the drain reports is not this test's business, so start clean.
	::application::openPane board
	update
	set ::scidb::test::pane::errors {}
} -body {
	set frame [set ::application::board::Vars(widget:frame)]
	if {![winfo exists $frame]} { return "no board canvas" }
	set width [expr {[winfo width $frame] + 11}]
	set height [expr {[winfo height $frame] + 7}]
	::application::board::ConfigureWindow $frame $width $height
	set queued [set ::application::board::Vars(after)]
	if {$queued eq ""} { return "no rebuild queued" }
	set rc [catch { ::action::run menu.view.panes.board } err]
	update idletasks
	set hidden [expr {"board" ni [[::menu::PaneTWM] leaves]}]
	set kept 0
	if {![catch { after info $queued } info] && [llength $info]} { set kept 1 }
	# the coalescing delay elapses with nothing for the dead canvas to do
	after 400
	update
	set dead {}
	foreach queuedError $::scidb::test::pane::errors {
		if {[string match {invalid command name*} $queuedError]} {
			lappend dead $queuedError
		}
	}
	puts "REG-010 hide board while rebuilding: rc={$rc $err} hidden=$hidden timer-kept=$kept checked=[::menu::PaneChecked board] dead={$dead} errors={$::scidb::test::pane::errors}"
	list $hidden $kept [::menu::PaneChecked board] $dead
} -cleanup {
	::scidb::test::pane::Restore $::scidb::test::pane::initial
	update idletasks
	::scidb::test::pane::ReleaseBgErrors
} -result {1 0 0 {}}

tcltest::cleanupTests
