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

tcltest::test mediasync-fenkey {FenKey normalizes '/' to 'z', board+side only} -body {
	list [::application::media::FenKey "r1bq2k1/ppp2r2/3p1n1b/3n4/P1pP1N2/2N1P2P/2Q2PP1/1R1R2K1 b - - 0 12"] \
	     [::application::media::FenKey "r1bq2k1/ppp2r2/3p1n1b/3n4/P1pP1N2/2N1P2P/2Q2PP1/1R1R2K1 b"]
} -result {{r1bq2k1zppp2r2z3p1n1bz3n4zP1pP1N2z2N1P2Pz2Q2PP1z1R1R2K1 b} {r1bq2k1zppp2r2z3p1n1bz3n4zP1pP1N2z2N1P2Pz2Q2PP1z1R1R2K1 b}}

tcltest::test mediasync-imatch-side-strict {InteractiveMatch ignores counters, respects side to move} -body {
	set fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b - e3 0 2"
	set entries [list \
		[list "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b" fileA 5 9 black] \
		[list "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w" fileB {} {} white]]
	list [::application::media::InteractiveMatch $entries $fen] \
	     [::application::media::InteractiveMatch $entries "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1"]
} -cleanup {reset} -result {{{rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b} fileA 5 9 black} {{rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w} fileB {} {} white}}

tcltest::test mediasync-smv-parse {SmvEntries parses clip + range sections} -body {
	set d [file join $::scidb::test::appdb::tmpDir smv-test]
	file mkdir [file join $d videos]
	set fh [open [file join $d videos lecture.mp4] w]; puts $fh x; close $fh
	set fh [open [file join $d videos hot.wmv] w]; puts $fh x; close $fh
	set fh [open [file join $d test.smv] w]
	puts $fh "\# scidb media manifest"
	puts $fh "\[Media \"V01\"\]"
	puts $fh "Type: video"
	puts $fh "Path: videos/lecture.mp4"
	puts $fh "\[Interactive \"V02\"\]"
	puts $fh "Media: V01"
	puts $fh "Fen: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b"
	puts $fh "Kind: range"
	puts $fh "Start: 5"
	puts $fh "End: 9"
	puts $fh "\[Interactive \"V03\"\]"
	puts $fh "Fen: 2r1r1k1/p2b1pp1/1pPq3p/3n4/P1pP1N2/2N1P2P/2Q2PP1/1R1R2K1 b"
	puts $fh "Kind: clip"
	puts $fh "Clip: videos/hot.wmv"
	puts $fh "Label: \"hotspot\""
	close $fh
	set res [::application::media::SmvEntries [file join $d test.smv]]
	set baseline [dict get $res baseline]
	set entries [dict get $res entries]
	list $baseline [llength $entries] [lindex $entries 0 1] [lindex $entries 0 2] [lindex $entries 1 1] [lindex $entries 1 4]
} -cleanup {reset} -result [list {} 2 [file join $::scidb::test::appdb::tmpDir smv-test videos lecture.mp4] 5 [file join $::scidb::test::appdb::tmpDir smv-test videos hot.wmv] hotspot]

set zboard "r1bq2k1zppp2r2z3p1n1bz2PPp1ppz4Pn2z2NNBPR1zPP2B2Pz2RQ3K"

tcltest::test mediasync-smv-missing-ok {SmvEntries tolerates a missing manifest (the .cms fallback path)} -body {
	dict size [::application::media::SmvEntries [file join $::scidb::test::appdb::tmpDir nope-does-not-exist.smv]]
} -cleanup {reset} -result 2

tcltest::test mediasync-cms-parse {CmsEntries finds base video + hotspot entries} -body {
	set d [file join $::scidb::test::appdb::tmpDir cms-test html "TestBase"]
	file mkdir $d
	set name "$zboard w - - 0 1x7y2v1u3"
	set fh [open [file join $d $name.wmv] w]; puts $fh x; close $fh
	set fh [open [file join $d TestBase000.wmv] w]; puts $fh x; close $fh
	set fh [open [file join [file dirname $d] "TestBase.cms"] w]
	fconfigure $fh -translation binary
	puts -nonewline $fh "\x00\x00\x02fJ"
	puts -nonewline $fh "$name"
	close $fh
	set res [::application::media::CmsEntries [file join [file dirname $d] "TestBase.cms"]]
	set base [dict get $res baseline]
	set entries [dict get $res entries]
	list [file tail $base] [llength $entries] \
	    [expr {[string match "*x7y2v1u3.wmv" [lindex $entries 0 1]] ? "clip-ok" : "clip-bad"}] \
	    [::application::media::FenKey [lindex $entries 0 0]]
} -cleanup {reset} -result [list TestBase000.wmv 1 clip-ok "$zboard w"]

tcltest::test mediasync-resolveindex-base {ResolveIndex without a game falls back to the .cms base video} -body {
	set d [file join $::scidb::test::appdb::tmpDir cms-test html "TestBase"]
	set res [::application::media::ResolveIndex [file join [file dirname $d] "TestBase.cms"] 9]
	lassign $res video interactive startMs endMs
	list $interactive [file tail $video] $startMs $endMs
} -cleanup {reset} -result {0 TestBase000.wmv {} {}}

tcltest::test mediasync-timeline-drives-board {drive() advances one step per elapsed transition mark} -body {
	reset
	set ::syncFwds 0
	::media::sync::configure \
		boardforward-cmd {::apply {{} {incr ::syncFwds}}} \
		boardstart-cmd   {::apply {{} {set ::syncFwds 0}}} \
		boardlength-cmd  {::apply {{} {return 5}}} \
		boardply-cmd     {::apply {{} {return $::syncFwds}}}
	::media::sync::set-config 1 1
	::media::sync::load-timeline {600 1200 1800}
	::media::sync::onPlaybackStarted
	::media::sync::drive 700 1000   ;# one mark elapsed -> 1 forward
	set a $::syncFwds
	::media::sync::drive 1500 1000  ;# two marks elapsed -> 2 total
	list $a $::syncFwds
} -cleanup {reset} -result {1 2}

tcltest::test mediasync-timeline-clamps {timeline goal clamps to the board length} -body {
	reset
	set ::syncFwds 0
	::media::sync::configure \
		boardforward-cmd {::apply {{} {incr ::syncFwds}}} \
		boardstart-cmd   {::apply {{} {set ::syncFwds 0}}} \
		boardlength-cmd  {::apply {{} {return 3}}} \
		boardply-cmd     {::apply {{} {return $::syncFwds}}}
	::media::sync::set-config 1 1
	::media::sync::load-timeline {100 200 300 400 500 600}
	::media::sync::onPlaybackStarted
	::media::sync::drive 5000 10000
	set ::syncFwds
} -cleanup {reset} -result 2

tcltest::test mediasync-timeline-rewind-restarts {timeline rewind restarts the board and the cursor} -body {
	reset
	set ::syncFwds 0
	set ::syncStarts 0
	::media::sync::configure \
		boardforward-cmd {::apply {{} {incr ::syncFwds}}} \
		boardstart-cmd   {::apply {{} {incr ::syncStarts; set ::syncFwds 0}}} \
		boardlength-cmd  {::apply {{} {return 4}}} \
		boardply-cmd     {::apply {{} {return $::syncFwds}}}
	::media::sync::set-config 1 1
	::media::sync::load-timeline {100 200 300 400}
	::media::sync::onPlaybackStarted
	::media::sync::drive 350 1000   ;# goal 3
	::media::sync::drive 250 1000   ;# rewind below goal 3 -> restart, goal 2
	list $::syncStarts $::syncFwds
} -cleanup {reset} -result {1 2}

tcltest::test mediasync-timeline-empty-falls-back-linear {empty timeline falls back to the linear mapping} -body {
	reset
	set ::syncFwds 0
	::media::sync::configure \
		boardforward-cmd {::apply {{} {incr ::syncFwds}}} \
		boardlength-cmd  {::apply {{} {return 5}}} \
		boardply-cmd     {::apply {{} {return $::syncFwds}}}
	::media::sync::set-config 1 1
	::media::sync::load-timeline {}
	::media::sync::onPlaybackStarted
	::media::sync::drive 600 1000   ;# 60% of 5 plies -> 3 (linear)
	set ::syncFwds
} -cleanup {reset} -result 3

tcltest::test mediasync-events-fire {load-events fires arrow/mark/comment in time order} -body {
	reset
	set ::anns {}
	::media::sync::configure \
		boardforward-cmd {::apply {{} {incr ::syncFwds}}} \
		boardlength-cmd  {::apply {{} {return 5}}} \
		boardply-cmd     {::apply {{} {return $::syncFwds}}} \
		annotate-cmd     {::apply {{kind data} {lappend ::anns [list $kind $data]}}}
	::media::sync::set-config 1 1
	::media::sync::load-timeline {600 1200 1800}
	::media::sync::load-events {
		{700 arrow {c8 e6 green}}
		{1100 mark {a4 green}}
		{1300 comment {en "shirov game"}}
	}
	::media::sync::onPlaybackStarted
	::media::sync::drive 800 1000  ;# arrow fires only
	set a [llength $::anns]
	::media::sync::drive 1400 1000 ;# mark + comment fire
	list $a [llength $::anns] \
		[lindex $::anns 0 0] \
		[lindex $::anns 1 0] \
		[lindex $::anns 2 0]
} -cleanup {reset} -result {1 3 arrow mark comment}

tcltest::test mediasync-events-reset {reset events clear the annotation list} -body {
	reset
	set ::anns {}
	::media::sync::configure \
		annotate-cmd {::apply {{kind data} {lappend ::anns $kind}}} \
		clearann-cmd {::apply {{} {set ::anns {}; incr ::syncClears}}}
	::media::sync::set-config 1 1
	::media::sync::load-timeline {}
	::media::sync::load-events {
		{500 arrow {c8 e6 green}}
		{800 reset {}}
		{1000 mark {a4 green}}
	}
	::media::sync::onPlaybackStarted
	::media::sync::drive 900 1000   ;# +1 reset (canns=1) +1 mark
	::media::sync::drive 1100 1000  ;# +1 mark (total 2 anns since reset)
	list $::syncClears [llength $::anns]
} -cleanup {reset} -result {1 1}

tcltest::test mediasync-events-rewind-clears {rewind restarts annotation state} -body {
	reset
	set ::syncStarts 0
	set ::syncAnn {}
	::media::sync::configure \
		boardforward-cmd {::apply {{} {incr ::syncFwds}}} \
		boardstart-cmd   {::apply {{} {incr ::syncStarts; set ::syncFwds 0; set ::syncAnn {}}}} \
		boardlength-cmd  {::apply {{} {return 5}}} \
		boardply-cmd     {::apply {{} {return $::syncFwds}}} \
		annotate-cmd     {::apply {{kind data} {lappend ::syncAnn [list $kind $data]}}} \
		clearann-cmd     {::apply {{} {set ::syncAnn {}}}}
	::media::sync::set-config 1 1
	::media::sync::load-timeline {600 1200 1800}
	::media::sync::load-events {
		{700 arrow {c8 e6 green}}
		{1300 mark {a4 green}}
	}
	::media::sync::onPlaybackStarted
	::media::sync::drive 800 1000    ;# arrow fires, board advances
	set pre [llength $::syncAnn]     ;# 1
	::media::sync::drive 300 1000    ;# rewind -> restart + clear annotations
	list $pre $::syncStarts [llength $::syncAnn]
} -cleanup {reset} -result {1 1 0}

tcltest::cleanupTests



} ;# namespace ::scidb::test::mediasync



