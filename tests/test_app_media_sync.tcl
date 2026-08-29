# ======================================================================
# Scidb App Test — media ⇄ board sync state machine (tcl/app-media-sync.tcl)
# ======================================================================
# Regression net for the ::mediasync (UI config) vs ::media::sync (state
# machine) namespace contract, which the GUI startup path depends on:
#   media::build → ::media::sync::configure  (tcl/app-media.tcl)
# Locks the API names so a rename on one side cannot silently kill the
# GUI at startup again (gui-crash-at-startup debug, 2026-08-29).
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::mediasync {

proc reset {} {
	# reset both sides of the sync API to defaults
	::mediasync::set-config 1 0
	::media::sync::set-config 1 0
	::media::sync::onPlaybackStopped
}

tcltest::test mediasync-ui-config-exists {::mediasync UI config API used by app-media.tcl} -body {
	expr { [llength [info commands ::mediasync::config]]
	     && [llength [info commands ::mediasync::set-config]]
	     && [namespace exists ::mediasync] }
} -cleanup {reset} -result 1

tcltest::test mediasync-state-machine-exists {::media::sync::configure exists (used by media::build at GUI startup)} -body {
	expr { [llength [info commands ::media::sync::configure]]
	     && [llength [info commands ::media::sync::autoplay]]
	     && [llength [info commands ::media::sync::step]]
	     && [llength [info commands ::media::sync::drive]]
	     && [llength [info commands ::media::sync::onPlaybackStarted]]
	     && [llength [info commands ::media::sync::onPlaybackStopped]] }
} -cleanup {reset} -result 1

tcltest::test mediasync-configure-unknown-option {configure rejects unknown delegate keys} -body {
	set msg {}
	catch { ::media::sync::configure bogus-cmd foo } msg
	expr {[string match "*unknown option*" $msg]}
} -cleanup {reset} -result 1

tcltest::test mediasync-ui-config-defaults {UI config defaults: transport on, follow off} -body {
	reset
	::mediasync::config
} -cleanup {reset} -result {1 0}

tcltest::test mediasync-transport-autoplay {autoplay 1 -> transport play; autoplay 0 -> pause} -body {
	reset
	set ::syncCalls {}
	::media::sync::configure transport-cmd [list ::apply {what {lappend ::syncCalls $what}}]
	::media::sync::set-config 1 0
	::media::sync::onPlaybackStarted
	::media::sync::autoplay 1
	::media::sync::autoplay 0
	set ::syncCalls
} -cleanup {reset} -result {play pause}

tcltest::test mediasync-transport-manual-pause {manual navigation pauses media} -body {
	reset
	set ::syncCalls {}
	::media::sync::configure transport-cmd [list ::apply {what {lappend ::syncCalls $what}}]
	::media::sync::set-config 1 0
	::media::sync::onPlaybackStarted
	::media::sync::step
	set ::syncCalls
} -cleanup {reset} -result {pause}

tcltest::test mediasync-transport-idle-noop {no transport calls while media stopped} -body {
	reset
	set ::syncCalls {}
	::media::sync::configure transport-cmd [list ::apply {what {lappend ::syncCalls $what}}]
	::media::sync::set-config 1 0
	::media::sync::autoplay 1
	::media::sync::step
	set ::syncCalls
} -cleanup {reset} -result {}

tcltest::test mediasync-step-under-autoplay-keeps-playing {step during autoplay keeps media playing} -body {
	reset
	set ::syncCalls {}
	::media::sync::configure transport-cmd [list ::apply {what {lappend ::syncCalls $what}}]
	::media::sync::set-config 1 0
	::media::sync::onPlaybackStarted
	::media::sync::autoplay 1
	::media::sync::step
	::media::sync::autoplay 0
	set ::syncCalls
} -cleanup {reset} -result {play pause}

tcltest::test mediasync-transport-disabled-inert {transport sync off -> no transport traffic} -body {
	reset
	set ::syncCalls {}
	::media::sync::configure transport-cmd [list ::apply {what {lappend ::syncCalls $what}}]
	::media::sync::set-config 0 0
	::media::sync::onPlaybackStarted
	::media::sync::autoplay 1
	::media::sync::autoplay 0
	::media::sync::step
	set ::syncCalls
} -cleanup {reset} -result {}

tcltest::test mediasync-follow-tick-cap-and-convergence {drive ticks cap at 4 plies each and converge to the mapped goal} -body {
	reset
	set ::syncPly 0
	::media::sync::configure \
		boardforward-cmd {::apply {{} {incr ::syncPly}}} \
		boardstart-cmd   {::apply {{} {set ::syncPly 0}}} \
		boardlength-cmd  {::apply {{} {return 40}}} \
		boardply-cmd     {::apply {{} {return $::syncPly}}}
	::media::sync::set-config 1 1
	::media::sync::onPlaybackStarted
	::media::sync::drive 20000 40000           ;# halfway -> goal 20, first tick
	set capped [expr {$::syncPly <= 4}]
	::media::sync::drive 20000 40000           ;# repeated ticks catch up
	::media::sync::drive 20000 40000
	list $capped [expr {$::syncPly >= 10}]
} -cleanup {reset} -result {1 1}

tcltest::test mediasync-follow-off-drive-ignored {follow mode off -> drive leaves the board alone} -body {
	reset
	set ::syncPly 5
	::media::sync::configure \
		boardforward-cmd {::apply {{} {incr ::syncPly}}} \
		boardstart-cmd   {::apply {{} {set ::syncPly 0}}} \
		boardlength-cmd  {::apply {{} {return 40}}} \
		boardply-cmd     {::apply {{} {return $::syncPly}}}
	::media::sync::set-config 1 0
	::media::sync::onPlaybackStarted
	::media::sync::drive 30000 40000
	set ::syncPly
} -cleanup {reset} -result 5

tcltest::test mediasync-follow-drives-board {drive() maps media time linearly onto plies} -body {
	reset
	set ::syncFwds 0
	::media::sync::configure \
		boardforward-cmd {::apply {{} {incr ::syncFwds}}} \
		boardstart-cmd   {::apply {{} {set ::syncFwds 0}}} \
		boardlength-cmd  {::apply {{} {return 5}}} \
		boardply-cmd     {::apply {{} {return $::syncFwds}}}
	::media::sync::set-config 1 1
	::media::sync::onPlaybackStarted
	::media::sync::drive 600 1000 ;# 60% of 5 plies -> goal 3 -> 3 forwards
	set ::syncFwds
} -cleanup {reset} -result 3

tcltest::test mediasync-follow-rewind-restarts {media rewind below lastgoal -> BoardStart} -body {
	reset
	set ::syncFwds 0
	set ::syncStarts 0
	::media::sync::configure \
		boardforward-cmd {::apply {{} {incr ::syncFwds}}} \
		boardstart-cmd   {::apply {{} {incr ::syncStarts; set ::syncFwds 0}}} \
		boardlength-cmd  {::apply {{} {return 5}}} \
		boardply-cmd     {::apply {{} {return $::syncFwds}}}
	::media::sync::set-config 1 1
	::media::sync::onPlaybackStarted
	::media::sync::drive 800 1000
	::media::sync::drive 100 1000 ;# rewind -> boardstart; ply 0 == goal 0 -> no step
	list $::syncStarts $::syncFwds
} -cleanup {reset} -result {1 0}

tcltest::cleanupTests

} ;# namespace ::scidb::test::mediasync