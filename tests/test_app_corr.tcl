# ======================================================================
# Scidb App Test - the correspondence games window and the ICCF settings
# dialog (tcl/app-corr-games.tcl, tcl/iccf-xfcc.tcl)
# ======================================================================
# Gap G33: the correspondence windows had no app test at all. They are
# opened as Tools > Correspondence Games and Tools > ICCF Settings open
# them, on a generated .sci database with two correspondence games (their
# TimeMode is "corr") and one ordinary game. The tests read the treeview's
# rows, the detail area's labels and the settings entries, and they press
# the same buttons the user presses. Nothing is sent over the network: the
# only server call is stubbed, and with no credentials the Sync button must
# open the settings dialog instead of calling it.
#
# The games are invented; no database of the user's is opened.
# ======================================================================

package require Tcl 8.6
package require tcltest 2.5

namespace eval ::scidb::test::corr {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app corr-[pid]]
	variable SavedConfig {}
	variable Games 0
	variable SyncCalled 0
}

proc ::scidb::test::corr::nop {args} { return 0 }

# Games as a PGN export carries them: the correspondence ones say so with
# TimeMode. Their Site stays "ICCF" but the ordinary game's does not: the PGN
# reader infers a correspondence time mode from an event or site name like
# "Correspondence" or "ICCF" (db_reader.cpp getEventMode), so the third game
# must not carry either.
proc ::scidb::test::corr::writePgn {file {corrGames 2} {normalGames 1}} {
	set chan [open $file w]
	fconfigure $chan -encoding utf-8
	set games [list \
		[list {Alpha, Ann} {Beta, Bob} * corr 2024.02.01 ICCF] \
		[list {Gamma, Gil} {Delta, Dan} 1-0 corr 2023.11.05 ICCF] \
		[list {Epsilon, Eve} {Zeta, Zoe} 1-0 normal 2024.02.01 {Probe City}]]
	set n 0
	set written 0
	foreach game $games {
		lassign $game white black result timeMode date site
		if {$timeMode eq "corr" && $written >= $corrGames} { continue }
		if {$timeMode eq "normal" && $written >= $corrGames + $normalGames} { continue }
		incr written
		incr n
		puts $chan "\[Event \"Probe Open 2024\"\]"
		puts $chan "\[Site \"$site\"\]"
		puts $chan "\[Date \"$date\"\]"
		puts $chan "\[Round \"$n\"\]"
		puts $chan "\[White \"$white\"\]"
		puts $chan "\[Black \"$black\"\]"
		puts $chan "\[Result \"$result\"\]"
		if {$timeMode eq "corr"} { puts $chan "\[TimeMode \"corr\"\]" }
		puts $chan ""
		puts $chan "1. e4 e5 2. Nf3 $result"
		puts $chan ""
	}
	close $chan
}

# A generated .sci database (what a correspondence player's own base is),
# made the active base as File > Open does it. No games when $corrGames is 0.
proc ::scidb::test::corr::makeBase {{corrGames 2} {name base} {normalGames 1}} {
	variable Dir
	variable Games

	file delete -force $Dir
	file mkdir $Dir
	set pgn [file join $Dir $name.pgn]
	writePgn $pgn $corrGames $normalGames
	set base [file join $Dir $name.sci]
	::scidb::db::open $pgn nop {} nop {}
	set Games [::scidb::db::count games $pgn Normal]
	::scidb::db::new $base Normal [::application::database::lookupType Unspecific]
	::scidb::db::attach $base $base
	if {$Games > 0} { ::scidb::db::copy $pgn $base {} nop {} nop {} }
	::scidb::db::save $base nop {}
	::scidb::db::close $base
	::scidb::db::close $pgn
	::scidb::db::load $base nop {} -readonly 1
	$::application::database::Vars(switcher) add $base [::scidb::db::get type $base] 1 {}
	::application::database::switchToBase $base
	update
	return $base
}

proc ::scidb::test::corr::openWindow {} {
	set dlg [::application::corr::games::open .application]
	update
	if {![winfo exists $dlg]} { error "the correspondence window did not open" }
	return $dlg
}

proc ::scidb::test::corr::closeWindow {dlg base} {
	catch { destroy $dlg }
	update
	catch { $::application::database::Vars(switcher) remove $base }
	catch { ::scidb::db::close $base }
	variable Dir
	catch { file delete -force $Dir }
}

# The rows the treeview shows, in order.
proc ::scidb::test::corr::rows {dlg} {
	set rows {}
	foreach row [$dlg.tree children {}] {
		lappend rows [$dlg.tree item $row -values]
	}
	return $rows
}

# A user's choice in the status filter.
proc ::scidb::test::corr::filter {dlg value} {
	$dlg.tb.filter set $value
	event generate $dlg.tb.filter <<ComboboxSelected>>
	update
}

# Any game slot the window filled (Open Game loads the game into one).
proc ::scidb::test::corr::releaseGames {} {
	for {set i 0} {$i < 9} {incr i} {
		catch { ::application::pgn::release $i }
		catch { ::game::release $i }
	}
	update
}

proc ::scidb::test::corr::saveConfig {} {
	variable SavedConfig [array get ::iccf::xfcc::Config]
}

proc ::scidb::test::corr::restoreConfig {} {
	variable SavedConfig
	array set ::iccf::xfcc::Config $SavedConfig
	update
}

file mkdir $::scidb::test::corr::Dir

tcltest::test corr-no-games {a database without games says so instead of listing rows} -setup {
	set base [::scidb::test::corr::makeBase 0 empty 0]
	set dlg [::scidb::test::corr::openWindow]
} -body {
	set rows [::scidb::test::corr::rows $dlg]
	list \
		[winfo exists $dlg] \
		[expr {[llength [$dlg.tree cget -columns]] == 10}] \
		[llength $rows] \
		[lindex [lindex $rows 0] 4] \
		[$dlg.tb.filter get]
} -cleanup {
	::scidb::test::corr::closeWindow $dlg $base
} -result {1 1 1 {No correspondence games found} All}

tcltest::test corr-lists-correspondence-games {only the correspondence games are listed, with their details} -setup {
	set base [::scidb::test::corr::makeBase 2 base]
	set dlg [::scidb::test::corr::openWindow]
} -body {
	set rows [::scidb::test::corr::rows $dlg]
	lassign [lindex $rows 0] number white black iccf status whiteTime blackTime lastMove event result
	list \
		[llength $rows] \
		[expr {$white eq {Alpha, Ann} && $black eq {Beta, Bob}}] \
		[expr {$event eq {Probe Open 2024} && $result eq "*"}] \
		[string match "*ongoing*" $status] \
		[expr {![string match "*Epsilon*" [join [concat {*}$rows]]]}] \
		$whiteTime
} -cleanup {
	::scidb::test::corr::closeWindow $dlg $base
} -result {2 1 1 1 1 —}

tcltest::test corr-status-filter {the status filter keeps the ongoing games and hides them as finished} -setup {
	set base [::scidb::test::corr::makeBase 2 base]
	set dlg [::scidb::test::corr::openWindow]
} -body {
	set all [llength [::scidb::test::corr::rows $dlg]]
	::scidb::test::corr::filter $dlg Finished
	set finished [llength [::scidb::test::corr::rows $dlg]]
	::scidb::test::corr::filter $dlg Ongoing
	set ongoing [llength [::scidb::test::corr::rows $dlg]]
	::scidb::test::corr::filter $dlg All
	set back [llength [::scidb::test::corr::rows $dlg]]
	list $all $finished $ongoing $back \
		[$dlg.tb.filter cget -state] \
		[llength [$dlg.tb.filter cget -values]]
} -cleanup {
	::scidb::test::corr::closeWindow $dlg $base
} -result {2 0 2 2 readonly 3}

tcltest::test corr-detail-shows-selected-game {selecting a game fills the detail area} -setup {
	set base [::scidb::test::corr::makeBase 2 base]
	set dlg [::scidb::test::corr::openWindow]
} -body {
	set row [lindex [$dlg.tree children {}] 0]
	$dlg.tree selection set $row
	update
	set detail [$dlg.detail.status cget -text]
	$dlg.tree selection remove $row
	update
	list \
		[string match "*ongoing*" $detail] \
		[$dlg.detail.whitetime cget -text] \
		[$dlg.detail.status cget -text]
} -cleanup {
	::scidb::test::corr::closeWindow $dlg $base
} -result {1 — {}}

tcltest::test corr-open-game {Open Game loads the selected game into a game slot} -setup {
	::scidb::test::corr::releaseGames
	set base [::scidb::test::corr::makeBase 2 base]
	set dlg [::scidb::test::corr::openWindow]
} -body {
	set row [lindex [$dlg.tree children {}] 0]
	$dlg.tree selection set $row
	update
	$dlg.tb.open invoke
	update
	set loaded {}
	set position 0
	foreach entry [::game::gameList] {
		if {[lindex $entry 0] eq $base} { set loaded $position }
		incr position
	}
	list \
		[expr {$loaded ne ""}] \
		[::scidb::game::query $loaded open?] \
		[lindex [lindex [::game::gameList] $loaded] 2]
} -cleanup {
	::scidb::test::corr::releaseGames
	::scidb::test::corr::closeWindow $dlg $base
} -result {1 1 0}

tcltest::test corr-sync-without-credentials {Sync opens the settings instead of calling the server} -setup {
	::scidb::test::corr::saveConfig
	set ::iccf::xfcc::Config(username) ""
	set ::iccf::xfcc::Config(password) ""
	set ::iccf::xfcc::Config(configured) 0
	set ::scidb::test::corr::SyncCalled 0
	rename ::iccf::xfcc::getGames ::iccf::xfcc::getGames.__saved
	proc ::iccf::xfcc::getGames {} { incr ::scidb::test::corr::SyncCalled; error "the test must not reach the network" }
	catch { destroy .application.corrGames.iccfSettings }
	catch { destroy .application.iccfSettings }
	set base [::scidb::test::corr::makeBase 2 base]
	set dlg [::scidb::test::corr::openWindow]
} -body {
	$dlg.tb.sync invoke
	update
	list \
		[winfo exists $dlg.iccfSettings] \
		$::scidb::test::corr::SyncCalled
} -cleanup {
	catch { destroy .application.corrGames.iccfSettings }
	catch { destroy .application.iccfSettings }
	catch { rename ::iccf::xfcc::getGames {} }
	catch { rename ::iccf::xfcc::getGames.__saved ::iccf::xfcc::getGames }
	::scidb::test::corr::restoreConfig
	::scidb::test::corr::closeWindow $dlg $base
} -result {1 0}

tcltest::test corr-settings-dialog {the ICCF settings hold the account, mask the password and save it} -setup {
	::scidb::test::corr::saveConfig
	set ::iccf::xfcc::Config(username) ""
	set ::iccf::xfcc::Config(password) ""
	set ::iccf::xfcc::Config(configured) 0
	set dlg [::iccf::xfcc::openSettings .application]
	update
} -body {
	set userVar [$dlg.f.user cget -textvariable]
	set endpoint [$dlg.f.endpt get]
	$dlg.f.user insert 0 tester
	$dlg.f.pass insert 0 secret
	set typed [list [set ::iccf::xfcc::Config(username)] [string length [set ::iccf::xfcc::Config(password)]]]
	set before [::iccf::xfcc::configured?]
	set mask [$dlg.f.pass cget -show]
	$dlg.btns.ok invoke
	update
	list \
		[expr {$userVar eq "::iccf::xfcc::Config(username)"}] \
		$mask \
		[expr {[string length $endpoint] > 0}] \
		$typed \
		$before \
		[expr {![winfo exists $dlg]}] \
		[::iccf::xfcc::configured?]
} -cleanup {
	catch { destroy $dlg }
	::scidb::test::corr::restoreConfig
} -result {1 * 1 {tester 6} 0 1 1}

tcltest::test corr-reopen-shows-games {closing with a filter set and opening again lists the games again} -setup {
	set base [::scidb::test::corr::makeBase 2 base]
	set dlg [::scidb::test::corr::openWindow]
} -body {
	::scidb::test::corr::filter $dlg Finished
	set filtered [llength [::scidb::test::corr::rows $dlg]]
	$dlg.tb.close invoke
	update
	set dlg [::scidb::test::corr::openWindow]
	list \
		$filtered \
		[$dlg.tb.filter get] \
		[llength [::scidb::test::corr::rows $dlg]] \
		[winfo exists $dlg]
} -cleanup {
	::scidb::test::corr::closeWindow $dlg $base
} -result {0 All 2 1}

foreach _id [after info] { catch { after cancel $_id } }

::tcltest::cleanupTests
