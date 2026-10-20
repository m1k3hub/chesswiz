# ======================================================================
# Scidb App Test — AI assistant pane (tcl/app-assistant.tcl)
# ======================================================================
# The model is replaced by the stub provider, whose scripted replies
# drive the tool loop; confirmations are answered by a test hook.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

# the "menu:" lines tools add are tested on their own (assistant-menu-line);
# the replies below are checked without them
set ::scidb::test::assistantToolMenu $::application::assistant::ToolMenu
set ::application::assistant::ToolMenu {}
# bulk and confirm share one gate command on the assistant path
set ::scidb::test::assistantOrgBulkHook $::action::BulkHook

namespace eval ::scidb::test::assistant {
	variable Answer 1
	variable Asked {}
}

proc ::scidb::test::assistant::confirm {what} {
	variable Answer
	variable Asked
	lappend Asked $what
	return $Answer
}

proc ::scidb::test::assistant::setup {answer} {
	variable Answer $answer
	variable Asked {}
	set ::application::assistant::Priv(confirm) ::scidb::test::assistant::confirm
	set ::action::BulkHook ::scidb::test::assistant::confirm
}

proc ::scidb::test::assistant::call {name {arguments {}}} {
	return [dict create role assistant content "" tool_calls \
		[list [dict create function [dict create name $name arguments $arguments]]]]
}

# Run one request against scripted replies; returns the transcript text.
proc ::scidb::test::assistant::run {request replies} {
	set cfg ::application::ai::Config
	set saved [array get $cfg provider]
	set ${cfg}(provider) stub
	::ai::provider::configure -name stub -chatResponses $replies
	::application::assistant::ask $request
	if {$::application::assistant::Priv(busy)} {
		vwait ::application::assistant::Priv(busy)
	}
	array set $cfg $saved
	return [$::application::assistant::Priv(text) get 1.0 end-1c]
}

tcltest::test assistant-pane-is-dockable {the assistant is an undockable pane of the board layout} -body {
	::application::assistant::show
	set twm [::application::twm board]
	list [expr {"assistant" in [$twm leaves]}] [expr {!![$twm isundockable assistant]}]
} -result {1 1}

tcltest::test assistant-download-games-tool {the assistant can download games; the reply comes when it is done} -setup {
	set savedConfirm $::application::assistant::Priv(confirm)
	::scidb::test::assistant::setup 1
	rename ::application::download::run ::scidb::test::assistant::realDownloadRun
	proc ::application::download::run {base spec doneCmd} {
		# a real download answers later; report the finished import after the
		# assistant has parked the pending tool call
		after 0 [list {*}$doneCmd [list ok 1 files 2 base $base]]
	}
} -body {
	set transcript [::scidb::test::assistant::run \
		"download the latest twic games" \
		[list [::scidb::test::assistant::call download_games {source twic issues 1}]]]
	list [string match {*imported 2 file*} $transcript] \
		[string match {*download the latest twic games*} $transcript]
} -cleanup {
	rename ::application::download::run {}
	rename ::scidb::test::assistant::realDownloadRun ::application::download::run
	set ::application::assistant::Priv(confirm) $savedConfirm
} -result {1 1}

tcltest::test assistant-download-games-args {download_games checks its arguments} -body {
	list [::application::assistant::runTool download_games {source dropbox}] \
		[::application::assistant::runTool download_games {source url}] \
		[::application::assistant::runTool download_games {source twic issues 99}] \
		[::application::assistant::runTool download_games {source player}] \
		[::application::assistant::runTool download_games {source player player hikaru site ICC}] \
		[::application::assistant::runTool download_games {source player player hikaru months 30}]
} -result {{error: source must be 'twic', 'lichess', 'player' or 'url'} {error: source 'url' needs the 'url' argument} {error: issues must be an integer between 1 and 12} {error: source 'player' needs the 'player' argument with a user name} {error: site must be 'Chess.com' or 'Lichess'} {error: months must be an integer between 1 and 24}}

tcltest::test assistant-classifier-status-tool {the assistant reports the classifier status} -body {
	set text [::application::assistant::runTool classifier_status {}]
	list [string match {*System One decision model*} $text] \
		[string match {*assistant routing*} $text] \
		[string match {*error triage*} $text]
} -result {1 1 1}

tcltest::test assistant-unknown-tool {an unknown tool is reported to the model, not raised} -body {
	::application::assistant::runTool run_shell {command {rm -rf ~}}
} -result {error: unknown tool 'run_shell'}

tcltest::test assistant-bad-arguments {tool arguments are checked before running} -body {
	list [::application::assistant::runTool switch_tab {tab settings}] \
		[::application::assistant::runTool open_database {path /nonexistent/x.sci}] \
		[::application::assistant::runTool open_database {}]
} -result {{error: tab must be 'board' or 'database'} {error: no such file: /nonexistent/x.sci} {error: missing argument 'path'}}

tcltest::test assistant-read-only-needs-no-confirm {a read-only tool runs without asking} -body {
	::scidb::test::assistant::setup 0
	set reply [::application::assistant::runTool list_open_databases {}]
	list [expr {[string first (active) $reply] >= 0}] $::scidb::test::assistant::Asked
} -result {1 {}}

tcltest::test assistant-denied-action {a changing action does not run when the user denies it} -body {
	::scidb::test::assistant::setup 0
	set called 0
	set hadProc [llength [info procs ::font::installChessBaseFonts]]
	if {$hadProc} { rename ::font::installChessBaseFonts ::scidb::test::assistant::realInstallFonts }
	proc ::font::installChessBaseFonts {args} { set ::called 1 }
	set ::called 0
	set reply [::application::assistant::runTool install_chessbase_fonts {}]
	rename ::font::installChessBaseFonts {}
	if {$hadProc} { rename ::scidb::test::assistant::realInstallFonts ::font::installChessBaseFonts }
	list $reply $::called $::scidb::test::assistant::Asked
} -result {{The user declined: the action was NOT performed and no dialog was opened.} 0 {{install the ChessBase fonts}}}

tcltest::test assistant-allowed-action {a changing action runs once the user allows it} -body {
	::scidb::test::assistant::setup 1
	set hadProc [llength [info procs ::font::installChessBaseFonts]]
	if {$hadProc} { rename ::font::installChessBaseFonts ::scidb::test::assistant::realInstallFonts }
	proc ::font::installChessBaseFonts {args} { set ::called 1 }
	set ::called 0
	set reply [::application::assistant::runTool install_chessbase_fonts {}]
	rename ::font::installChessBaseFonts {}
	if {$hadProc} { rename ::scidb::test::assistant::realInstallFonts ::font::installChessBaseFonts }
	list $::called [string match "*font installer ran*" $reply]
} -result {1 1}

tcltest::test assistant-tool-loop {a tool call is executed and the answer shown} -body {
	::application::assistant::clear
	set text [::scidb::test::assistant::run "which databases are open?" [list \
		[::scidb::test::assistant::call list_open_databases] \
		[dict create role assistant content "Only the Clipbase is open."]]]
	list [string match "*> which databases are open?*" $text] \
		[string match "*list_open_databases: *(active)*" $text] \
		[string match "*Only the Clipbase is open.*" $text] \
		$::application::assistant::Priv(busy)
} -result {1 1 1 0}

tcltest::test assistant-keeps-history {the conversation carries into the next request} -body {
	::scidb::test::assistant::run "thanks" [list [dict create role assistant content "You're welcome."]]
	lmap m $::application::assistant::Priv(messages) { dict get $m role }
} -result {system user assistant tool assistant user assistant}

tcltest::test assistant-deferred-tool {a tool that answers later holds the loop, then it goes on in order} -body {
	::application::assistant::clear
	rename ::application::assistant::DoAppState ::scidb::test::assistant::realAppState
	proc ::application::assistant::DoAppState {} {
		set token [::application::assistant::Later]
		after 50 [list ::application::assistant::Resolve $token "late state"]
		return $token
	}
	set both [dict create role assistant content "" tool_calls [list \
		[dict create function [dict create name app_state arguments {}]] \
		[dict create function [dict create name list_open_databases arguments {}]]]]
	set text [::scidb::test::assistant::run "state?" [list $both [dict create role assistant content "Done."]]]
	rename ::application::assistant::DoAppState {}
	rename ::scidb::test::assistant::realAppState ::application::assistant::DoAppState
	set roles [lmap m $::application::assistant::Priv(messages) { dict get $m role }]
	set messages $::application::assistant::Priv(messages)
	::application::assistant::clear
	list [regexp {app_state: \(working...\)\napp_state: late state\nlist_open_databases: .*\nDone\.} $text] \
		$roles [dict get [lindex $messages 3] content] \
		[string match "*app_state {}: ok -- late state*" [::application::assistant::runTool tool_log {count 3}]]
} -result {1 {system user assistant tool tool assistant} {late state} 1}

tcltest::test assistant-resolve-stale {a late answer nobody waits for is dropped} -body {
	::application::assistant::Resolve "\x00later:999999" "too late"
} -result 0

tcltest::test assistant-provider-error {a failing provider releases the pane} -body {
	set cfg ::application::ai::Config
	set saved [array get $cfg provider]
	set ${cfg}(provider) nosuchprovider
	::application::assistant::ask "hello"
	if {$::application::assistant::Priv(busy)} {
		vwait ::application::assistant::Priv(busy)
	}
	array set $cfg $saved
	list $::application::assistant::Priv(busy) \
		[string match "*Error:*" [$::application::assistant::Priv(text) get 1.0 end]]
} -result {0 1}

tcltest::test assistant-clear {clear drops the conversation} -body {
	::application::assistant::clear
	llength $::application::assistant::Priv(messages)
} -result 0

# Replace <proc> by a recorder for the duration of <body>; returns the
# recorded calls (each a list of arguments).
proc ::scidb::test::assistant::stubbed {proc body} {
	variable Calls {}
	rename $proc ${proc}__real
	proc $proc {args} { lappend ::scidb::test::assistant::Calls $args }
	set rc [catch { uplevel 1 $body } result]
	rename $proc {}
	rename ${proc}__real $proc
	if {$rc} { return -code error $result }
	return $Calls
}

tcltest::test assistant-new-game-confirms {new_game is harmless: it starts a game without asking} -body {
	::scidb::test::assistant::setup 0
	set denied [::scidb::test::assistant::stubbed ::menu::gameNew {
		::application::assistant::runTool new_game {}
	}]
	::scidb::test::assistant::setup 1
	set allowed [::scidb::test::assistant::stubbed ::menu::gameNew {
		::application::assistant::runTool new_game {}
	}]
	list [llength $denied] [llength $allowed] [lindex $allowed 0 1]
} -result {1 1 Normal}

tcltest::test assistant-open-search {open_search opens the requested dialog on the active base} -body {
	set calls [::scidb::test::assistant::stubbed ::application::database::OpenRatingSearch {
		::application::assistant::runTool open_search {kind rating}
	}]
	list [llength $calls] [lindex $calls 0 1] [lindex $calls 0 2] \
		[::application::assistant::runTool open_search {kind players}]
} -result [list 1 [::scidb::db::get name] Normal {error: kind must be 'advanced', 'material' or 'rating'}]

tcltest::test assistant-export {export_database opens the export dialog for the active base} -body {
	set calls [::scidb::test::assistant::stubbed ::export::open {
		::application::assistant::runTool export_database {}
	}]
	set exportOpts [lrange [lindex $calls 0] 1 end]
	list [llength $calls] [expr {[dict get $exportOpts -base] eq [::scidb::db::get name]}] \
		[dict get $exportOpts -variant]
} -result {1 1 Normal}

tcltest::test assistant-import-games {import_games asks, checks the files, then imports into the active base} -setup {
	set dir [file join [file dirname [file normalize [info script]]] tmp-app import_[pid]]
	file mkdir $dir
	set pgn [file join $dir games.pgn]
	set fh [open $pgn w]; puts $fh {[Event "?"]}; puts $fh ""; puts $fh "1. e4 *"; close $fh
} -body {
	::scidb::test::assistant::setup 0
	set denied [::scidb::test::assistant::stubbed ::import::import {
		::application::assistant::runTool import_games [list files [list $pgn]]
	}]
	::scidb::test::assistant::setup 1
	set calls [::scidb::test::assistant::stubbed ::import::import {
		set bad [list \
			[::application::assistant::runTool import_games [list files [list [file join $dir x.txt]]]] \
			[::application::assistant::runTool import_games [list files [list [file join $dir missing.pgn]]]]]
		set ok [::application::assistant::runTool import_games [list files [list $pgn]]]
	}]
	list [llength $denied] [lmap r $bad { string match "error:*" $r }] [string match "imported 1 file*" $ok] \
		[llength $calls] [expr {[lindex $calls 0 1] eq [::scidb::db::get name]}] [expr {[lindex $calls 0 2] eq [list $pgn]}]
} -cleanup {
	file delete -force $dir
} -result {0 {1 1} 1 1 1 1}

tcltest::test assistant-maintenance {compact, convert and the maintenance report go to Scidb's own dialogs} -body {
	set compact [::scidb::test::assistant::stubbed ::application::database::Compact {
		::application::assistant::runTool compact_database {}
	}]
	set convert [::scidb::test::assistant::stubbed ::application::database::ConvertDatabase {
		::application::assistant::runTool convert_database {}
	}]
	set report [::scidb::test::assistant::stubbed ::application::database::OpenMaintenanceReport {
		::application::assistant::runTool maintenance_report {tab duplicates}
	}]
	set missing [::application::assistant::runTool maintenance_report {}]
	set base [::scidb::db::get name]
	list [expr {[lindex $compact 0 1] eq $base}] [expr {[lindex $convert 0 1] eq $base}] \
		[lindex $report 0 3] $missing
} -result {1 1 duplicates {error: missing argument 'tab'}}

tcltest::test assistant-correspondence {correspondence_games lists whose move it is and never sends one} -body {
	rename ::iccf::xfcc::configured? ::scidb::test::assistant::realConfigured
	rename ::iccf::xfcc::getGames ::scidb::test::assistant::realGetGames
	rename ::iccf::xfcc::submitMove ::scidb::test::assistant::realSubmit
	proc ::iccf::xfcc::submitMove {args} { set ::scidb::test::assistant::Submitted 1 }
	set ::scidb::test::assistant::Submitted 0
	set missing [::application::assistant::runTool correspondence_games {}]
	proc ::iccf::xfcc::configured? {} { return 0 }
	set none [::application::assistant::runTool correspondence_games {action status}]
	proc ::iccf::xfcc::configured? {} { return 1 }
	proc ::iccf::xfcc::getGames {} {
		set base {white "" black "" event "WS/2026" result "" daysPlayer 3 hoursPlayer 4 daysOpponent 9 hoursOpponent 1}
		list [dict merge $base {id 11 hasWhite true black "Smith, A" myTurn false}] \
			[dict merge $base {id 12 hasWhite false white "Jones, B" myTurn true}]
	}
	set status [::application::assistant::runTool correspondence_games {action status}]
	set bad [::application::assistant::runTool correspondence_games {action send}]
	foreach p {configured? getGames submitMove} {
		rename ::iccf::xfcc::$p {}
	}
	rename ::scidb::test::assistant::realConfigured ::iccf::xfcc::configured?
	rename ::scidb::test::assistant::realGetGames ::iccf::xfcc::getGames
	rename ::scidb::test::assistant::realSubmit ::iccf::xfcc::submitMove
	set lines [split $status \n]
	list $missing [string match "error: no ICCF account*" $none] [lindex $lines 0] \
		[string match "game 12: you are Black against Jones, B*YOUR MOVE, 3d 4h left" [lindex $lines 1]] \
		[string match "game 11: you are White against Smith, A*opponent to move*" [lindex $lines 2]] \
		[string match "error:*" $bad] $::scidb::test::assistant::Submitted
} -result {{error: missing argument 'action'} 1 {1 of 2 game(s) need your move} 1 1 1 0}

tcltest::test assistant-find-lesson {find_lesson matches the board against interactive clips and can play one} -body {
	set saved [array get ::application::media::Priv *Interactive]
	set start [::scidb::pos::fen]
	set ::application::media::Priv(dbInteractive) [list \
		[list $start /lessons/opening.wmv 10 20 "the starting position"] \
		[list {8/8/8/8/8/8/8/K6k w - - 0 1} /lessons/endgame.wmv {} {} ""]]
	set ::application::media::Priv(userInteractive) {}
	set calls [::scidb::test::assistant::stubbed ::application::media::PlayMedia {
		set found [::application::assistant::runTool find_lesson {}]
		set played [::application::assistant::runTool find_lesson {play true}]
	}]
	set ::application::media::Priv(dbInteractive) {}
	set none [::application::assistant::runTool find_lesson {}]
	array set ::application::media::Priv $saved
	list [lindex [split $found \n] 0] [lindex [split $found \n] 1] [llength $calls] [lindex $calls 0] \
		[string match "no video lesson*" $none]
} -result {{1 lesson clip(s) cover this position:} {opening.wmv (the starting position)} 1 {/lessons/opening.wmv 10 20} 1}

tcltest::test assistant-app-state {app_state reports versions, database and position} -body {
	set reply [::application::assistant::runTool app_state {}]
	list [string match "*tcl 8.*" $reply] [string match "*active database: *" $reply] \
		[string match "*current position: *" $reply] [string match "*current game (slot *" $reply]
} -result {1 1 1 1}

# Run <body> with an empty error record and a scratch error log; returns
# {recent_errors-reply log-file-contents}.
proc ::scidb::test::assistant::capture {body} {
	set saved [list $::application::assistant::Errors $::application::assistant::ErrorLogFile]
	set file [file join [file dirname [file normalize [info script]]] tmp-app capture_[pid].log]
	file delete $file
	set ::application::assistant::Errors {}
	set ::application::assistant::ErrorLogFile $file
	set rc [catch { uplevel 1 $body } result]
	set reply [::application::assistant::runTool recent_errors {count 5}]
	set text ""
	if {[file exists $file]} {
		set fh [open $file]; set text [read $fh]; close $fh
		file delete $file
	}
	lassign $saved ::application::assistant::Errors ::application::assistant::ErrorLogFile
	if {$rc} { return -code error $result }
	return [list $reply $text]
}

tcltest::test assistant-errors-traced {every error channel is traced from startup} -body {
	lmap {command handler} {::scidb::bgerror TraceBgError ::log::Print TraceLog ::dialog::alert TraceAlert} {
		expr {"enter ::application::assistant::$handler" in [trace info execution $command]}
	}
} -result {1 1 1}

tcltest::test assistant-background-error {background errors are recorded with their stack} -body {
	lassign [::scidb::test::assistant::capture {
		::application::assistant::TraceBgError \
			[list ::scidb::bgerror "boom" {-errorinfo "boom\n    while executing x"}] enter
		::application::assistant::TraceBgError \
			[list ::scidb::bgerror "selection doesn't exist" {}] enter
	}] reply text
	list [string match "*background: boom\nboom\n    while executing x" $reply] \
		[regexp {^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d \[background\] boom\n    boom\n        while executing x\n$} $text]
} -result {1 1}

tcltest::test assistant-log-and-dialog-errors {errors of the log window and of error dialogs are recorded} -body {
	lassign [::scidb::test::assistant::capture {
		::log::error Import "cannot read game 7"
		::log::info "just information"
		::log::error {{"bad " {}} {"header" {bold}}}
		# the modal dialog itself would block the test
		::application::assistant::TraceAlert \
			{::dialog::alert -parent . -message "Disk full" -detail "while saving x.sci" -type error} enter
		::application::assistant::TraceAlert \
			{::dialog::alert -parent . -message "Saved." -type info} enter
	}] reply text
	list [expr {[string first {log: [Import] cannot read game 7} $reply] >= 0}] \
		[string match "*log: bad header*" $reply] \
		[string match "*just information*" $reply] \
		[string match "*dialog: Disk full\nwhile saving x.sci*" $reply] \
		[string match "*Saved.*" $reply] \
		[regexp -all -line {^\d{4}-\S+ \S+ \[(log|dialog)\]} $text]
} -cleanup {
	catch { ::log::close }
	catch { wm withdraw .application.log }
} -result {1 1 0 1 0 3}

tcltest::test assistant-tool-failure-recorded {a tool that fails is recorded as an error} -body {
	lassign [::scidb::test::assistant::capture {
		rename ::application::assistant::DoAppState ::scidb::test::assistant::realAppState
		proc ::application::assistant::DoAppState {} { error "state broke" }
		set reply [::application::assistant::runTool app_state {}]
		rename ::application::assistant::DoAppState {}
		rename ::scidb::test::assistant::realAppState ::application::assistant::DoAppState
		set reply
	}] errors text
	list [string match "*assistant: app_state: state broke\nstate broke*" $errors] \
		[expr {[string first {[assistant] app_state: state broke} $text] >= 0}]
} -result {1 1}

tcltest::test assistant-error-log-rotates {a full error log moves aside} -body {
	set saved [list $::application::assistant::ErrorLogFile $::application::assistant::MaxErrorLogSize]
	set file [file join [file dirname [file normalize [info script]]] tmp-app rotate_[pid].log]
	file delete $file $file.1
	set ::application::assistant::ErrorLogFile $file
	set ::application::assistant::MaxErrorLogSize 100
	# the size is checked before each entry: 2 entries pass 100 bytes, the 3rd starts anew
	for {set i 0} {$i < 3} {incr i} { ::application::assistant::RecordError test [string repeat x 40] }
	set result [list [file exists $file.1] [expr {[file size $file] <= 100}]]
	file delete $file $file.1
	lassign $saved ::application::assistant::ErrorLogFile ::application::assistant::MaxErrorLogSize
	set result
} -result {1 1}

tcltest::test assistant-error-log-disabled {an empty log file name keeps the record but writes nothing} -body {
	set saved $::application::assistant::ErrorLogFile
	set ::application::assistant::ErrorLogFile ""
	::application::assistant::RecordError test "not written"
	set ::application::assistant::ErrorLogFile $saved
	lrange [lindex $::application::assistant::Errors end] 1 2
} -result {test {not written}}

tcltest::test assistant-debug-tools-gated {debug tools are hidden and refused outside debug mode} -body {
	package require json
	set ::application::assistant::Priv(debug) 0
	set names [lmap t [json::json2dict [::application::assistant::toolsJson]] { dict get $t function name }]
	list [expr {"eval_tcl" in $names}] [expr {"app_state" in $names}] \
		[::application::assistant::runTool proc_source {name ::application::openPane}]
} -result {0 1 {error: 'proc_source' is only available in debug mode (--ai-debug or SCIDB_AI_DEBUG=1)}}

tcltest::test assistant-debug-inspection {in debug mode the model can read procs and variables} -body {
	set ::application::assistant::Priv(debug) 1
	set src [::application::assistant::runTool proc_source {name ::application::openPane}]
	set var [::application::assistant::runTool read_variable {name ::application::assistant::Priv pattern maxRounds}]
	set procs [::application::assistant::runTool list_procs {pattern ::application::report::show*}]
	set ::application::assistant::Priv(debug) 0
	list [string match "proc ::application::openPane {uid {explicit true}} *" $src] $var [llength [split $procs \n]]
} -result {1 {maxRounds = 8} 3}

tcltest::test assistant-eval-needs-confirm {eval_tcl runs only the script the user allowed} -body {
	set ::application::assistant::Priv(debug) 1
	::scidb::test::assistant::setup 0
	set ::scidb::test::assistant::x 0
	set denied [::application::assistant::runTool eval_tcl {script {set ::scidb::test::assistant::x 1}}]
	set asked $::scidb::test::assistant::Asked
	::scidb::test::assistant::setup 1
	set allowed [::application::assistant::runTool eval_tcl {script {incr ::scidb::test::assistant::x 5}}]
	set ::application::assistant::Priv(debug) 0
	list [string match "*NOT performed*" $denied] [string match "*set ::scidb::test::assistant::x 1*" $asked] \
		$allowed $::scidb::test::assistant::x
} -result {1 1 {result: 5} 5}

tcltest::test assistant-long-replies-truncated {a huge tool reply is cut} -body {
	set ::application::assistant::Priv(debug) 1
	set ::scidb::test::assistant::big [string repeat x 20000]
	set reply [::application::assistant::runTool read_variable {name ::scidb::test::assistant::big}]
	set ::application::assistant::Priv(debug) 0
	list [expr {[string length $reply] < 7000}] [string match "*(truncated)" $reply]
} -result {1 1}

# --- read-only queries over a small database ----------------------------

proc ::scidb::test::assistant::openFixture {} {
	variable Fixture
	set dir [file join [file dirname [file normalize [info script]]] tmp-app]
	file mkdir $dir
	set Fixture [file join $dir assistant_[pid].pgn]
	set fh [open $Fixture w]
	fconfigure $fh -encoding utf-8
	foreach {round white black result eco moves} {
		1 {Carlsen, Magnus} {Anand, Viswanathan} 1-0 B90 {1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6}
		2 {Anand, Viswanathan} {Carlsen, Magnus} 1/2-1/2 B92 {1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Be2}
		3 {Carlsen, Henrik} {Carlsen, Magnus} 0-1 C60 {1. e4 e5 2. Nf3 Nc6 3. Bb5}
	} {
		puts $fh "\[Event \"Assistant\"\]\n\[Site \"X\"\]\n\[Date \"202$round.01.01\"\]\n\[Round \"$round\"\]"
		puts $fh "\[White \"$white\"\]\n\[Black \"$black\"\]\n\[Result \"$result\"\]\n\[ECO \"$eco\"\]\n"
		puts $fh "$moves $result\n"
	}
	close $fh
	::scidb::db::open $Fixture ::scidb::test::assistant::nop {} ::scidb::test::assistant::nop {}
	# the queries read this base; switching the app to it would drag the GUI along
	rename ::application::assistant::ActiveBase ::scidb::test::assistant::realActiveBase
	proc ::application::assistant::ActiveBase {} { list $::scidb::test::assistant::Fixture Normal }
}

proc ::scidb::test::assistant::closeFixture {} {
	variable Fixture
	rename ::application::assistant::ActiveBase {}
	rename ::scidb::test::assistant::realActiveBase ::application::assistant::ActiveBase
	catch { ::scidb::db::close $Fixture }
	file delete $Fixture
}

proc ::scidb::test::assistant::nop {args} { return 0 }

::scidb::test::assistant::openFixture

tcltest::test assistant-player-stats {player_stats finds a player by part of the name} -body {
	::scidb::test::assistant::setup 0
	set reply [::application::assistant::runTool player_stats {name {carlsen, m}}]
	list [string match "Carlsen, Magnus: 3 games, 2021.01.01 to 2023.01.01*" $reply] \
		[string match "*White: 1 wins, 0 draws, 0 losses, score 100.0%*" $reply] \
		[string match "*Black: 1 wins, 1 draws, 0 losses, score 75.0%*" $reply] \
		[string match "*B92 Sicilian*1.e4 c5 2.Nf3*" $reply] \
		$::scidb::test::assistant::Asked
} -result {1 1 1 1 {}}

tcltest::test assistant-player-ambiguous {an ambiguous name lists the candidates, most games first} -body {
	list [::application::assistant::runTool player_stats {name carlsen}] \
		[::application::assistant::runTool player_stats {name kasparov}]
} -match glob -result {{error: several players match 'carlsen', call again with one exact name: Carlsen, Magnus (3 games); Carlsen, Henrik (1 games)} {error: no player matching 'kasparov' in *}}

tcltest::test assistant-opening-score {opening_score reports results by ECO code or range} -body {
	list [::application::assistant::runTool opening_score {eco b9}] \
		[::application::assistant::runTool opening_score {eco B90}] \
		[::application::assistant::runTool opening_score {eco A00-A99}] \
		[::application::assistant::runTool opening_score {eco Najdorf}]
} -result {{B90-B99: 2 games -- white wins 1, draws 1, black wins 0 (white scores 75.0%)} {B90 Sicilian Defence, Najdorf Variation: 1 games -- white wins 1, draws 0, black wins 0 (white scores 100.0%)} {no games with A00-A99} {error: eco must be like 'B90', 'B9', 'B' or 'B90-B99'}}

tcltest::test assistant-opening-score-player {opening_score with a player scores from that side} -body {
	::application::assistant::runTool opening_score {eco B player {Carlsen, Magnus}}
} -result "Carlsen, Magnus with B00-B99: 2 games\nwith White: 1 wins, 0 draws, 0 losses, score 100.0%\nwith Black: 0 wins, 1 draws, 0 losses, score 50.0%"

tcltest::test assistant-database-summary {database_summary counts games and ranks the openings} -body {
	set reply [::application::assistant::runTool database_summary {}]
	list [string match "*games: 3, players: 3*" $reply] \
		[string match "*games with an ECO code: 3 -- white wins 1, draws 1, black wins 1*" $reply] \
		[string match "*most played openings:\n  B9* games*" $reply] \
		[string match "*C60 Spanish Opening (Ruy L\u00f3pez): 1 games*" $reply]
} -result {1 1 1 1}

tcltest::test assistant-player-question-loop {the model resolves an ambiguous player in a second call} -body {
	::application::assistant::clear
	set text [::scidb::test::assistant::run "how does Carlsen do?" [list \
		[::scidb::test::assistant::call player_stats {name carlsen}] \
		[::scidb::test::assistant::call player_stats {name {Carlsen, Magnus}}] \
		[dict create role assistant content "Magnus Carlsen scored 83.3% in 3 games."]]]
	list [string match "*several players match*" $text] \
		[string match "*total: 2 wins, 1 draws, 0 losses, score 83.3%*" $text] \
		[string match "*scored 83.3% in 3 games.*" $text]
} -result {1 1 1}


tcltest::test assistant-prepare-against {prepare_against shows an opponent's lines, weak spots and latest games} -body {
	set saved $::application::assistant::PrepWeakGames
	set ::application::assistant::PrepWeakGames 1
	set reply [::application::assistant::runTool prepare_against {name {carlsen, m} color black}]
	set ::application::assistant::PrepWeakGames $saved
	set reply
} -result "Preparing against Carlsen, Magnus

As Black: 2 games, +1 =1 -0, score 75.0%
most played:
  B92 Sicilian Defence, Najdorf Variation, Opocensky Variation: 1 games, +0 =1 -0, score 50.0%
  C60 Spanish Opening (Ruy L\u00f3pez): 1 games, +1 =0 -0, score 100.0%
weakest (at least 1 games, below their average):
  B92 Sicilian Defence, Najdorf Variation, Opocensky Variation: 1 games, +0 =1 -0, score 50.0%

latest games:
  2023.01.01 as black vs Carlsen, Henrik: 0-1 C60, Assistant
  2022.01.01 as black vs Anand, Viswanathan: 1/2-1/2 B92, Assistant
  2021.01.01 as white vs Anand, Viswanathan: 1-0 B90, Assistant"

tcltest::test assistant-prepare-both-colours {without a colour both are shown; bad arguments are refused} -body {
	set reply [::application::assistant::runTool prepare_against {name {Anand, Viswanathan}}]
	list [string match "*As White: 1 games, +0 =1 -0, score 50.0%*" $reply] \
		[string match "*As Black: 1 games, +0 =0 -1, score 0.0%*" $reply] \
		[string match "*weakest*" $reply] \
		[::application::assistant::runTool prepare_against {name anand color red}] \
		[::application::assistant::runTool prepare_against {name carlsen}]
} -match glob -result {1 1 0 {error: color must be 'white' or 'black'} {error: several players match 'carlsen'*}}


tcltest::test assistant-position-moves {position_moves reports the tree of the board position; without a tree base the active one becomes it} -setup {
	# the Clipbase stands in for a Scidb base; the tree needs a saved one
	::scidb::db::copy $::scidb::test::assistant::Fixture Clipbase {} \
		::scidb::test::assistant::nop {} ::scidb::test::assistant::nop {}
	::scidb::db::save Clipbase ::scidb::test::assistant::nop {}
	set savedTree [::scidb::tree::get]
	catch { ::scidb::tree::set "" }
	proc ::application::assistant::ActiveBase {} { list Clipbase Normal }
	set fen [::scidb::pos::fen]
	set errors [llength $::application::assistant::Errors]
} -body {
	::application::assistant::clear
	set text [::scidb::test::assistant::run "what is played here?" [list \
		[::scidb::test::assistant::call position_moves] \
		[dict create role assistant content "Only 1.e4."]]]
	set reply [dict get [lindex $::application::assistant::Priv(messages) 3] content]
	# the tree pane's own search, started by the switch, must find its base
	after 500 { set ::scidb::test::assistant::settled 1 }
	vwait ::scidb::test::assistant::settled
	list [string match "3 games in * reach this position; White to move.\n  e4: 3 games (100%), White scores 50%, draws 33%, last played 2023, best player *" $reply] \
		[string match "*position_moves: (working...)*position_moves: 3 games*Only 1.e4.*" $text] \
		[::scidb::tree::get] [expr {[::scidb::pos::fen] eq $fen}] \
		$::application::assistant::Tree(token) \
		[lrange $::application::assistant::Errors $errors end]
} -cleanup {
	proc ::application::assistant::ActiveBase {} { list $::scidb::test::assistant::Fixture Normal }
	catch { ::scidb::tree::set $savedTree }
	::scidb::db::clear Clipbase
} -result {1 1 Clipbase 1 {} {}}

tcltest::test assistant-position-moves-refused {position_moves refuses a second search and a bad limit} -body {
	set ::application::assistant::Tree(token) busy
	set busy [::application::assistant::runTool position_moves {}]
	set ::application::assistant::Tree(token) {}
	list $busy [::application::assistant::runTool position_moves {limit 0}]
} -result {{error: a position search is already running} {error: limit must be a positive integer}}


# A White repertoire of two lines: the Najdorf (B90) and the Ruy Lopez (C60).
proc ::scidb::test::assistant::makeRepertoire {} {
	variable Fixture
	set dir [file dirname $Fixture]
	set pgn [file join $dir repertoire_[pid].pgn]
	set sci [file join $dir repertoire_[pid].sci]
	file delete {*}[glob -nocomplain [file rootname $sci].*]
	set fh [open $pgn w]
	foreach {eco moves} {
		B90 {1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6}
		C60 {1. e4 e5 2. Nf3 Nc6 3. Bb5}
	} {
		puts $fh "\[Event \"Repertoire\"\]\n\[White \"?\"\]\n\[Black \"?\"\]\n\[Result \"*\"\]\n\[ECO \"$eco\"\]\n\n$moves *\n"
	}
	close $fh
	::scidb::db::open $pgn ::scidb::test::assistant::nop {} ::scidb::test::assistant::nop {}
	::scidb::db::new $sci Normal [::application::database::lookupType OpeningsWhite]
	::scidb::db::attach $sci $sci
	::scidb::db::copy $pgn $sci {} ::scidb::test::assistant::nop {} ::scidb::test::assistant::nop {}
	::scidb::db::save $sci ::scidb::test::assistant::nop {}
	::scidb::db::close $pgn
	file delete $pgn
	return $sci
}

tcltest::test assistant-repertoire-check {repertoire_check finds weak lines, gaps and unused lines by ECO code} -setup {
	set saved $::application::assistant::PrepWeakGames
	set ::application::assistant::PrepWeakGames 1
	set sci [::scidb::test::assistant::makeRepertoire]
} -body {
	set all [::application::assistant::runTool repertoire_check {}]
	set own [::application::assistant::runTool repertoire_check {player {Carlsen, Magnus}}]
	list [string match "Repertoire repertoire_* (White): 2 ECO codes
Checked against all games, from White's side in assistant_*: 3 games, +1 =1 -1, score 50.0%

Covered, but scoring below the average of 50.0%:
  C60 Spanish Opening (Ruy López): 1 games, +0 =0 -1, score 0.0%

Not covered, but reached in at least 1 games:
  B92 Sicilian Defence, Najdorf Variation, Opocensky Variation: 1 games, +0 =1 -0, score 50.0%

In the repertoire, never reached:
  none

(ECO codes only:*" $all] \
		[string match "*Checked against Carlsen, Magnus's games as White in *: 1 games, +1 =0 -0, score 100.0%*below the average*\n  none*Not covered*\n  none*never reached:\n  C60 Spanish Opening*" $own] \
		[::application::assistant::runTool repertoire_check {color red}] \
		[::application::assistant::runTool repertoire_check {repertoire nosuch}]
} -cleanup {
	set ::application::assistant::PrepWeakGames $saved
	catch { ::scidb::db::close $sci }
	file delete {*}[glob -nocomplain [file rootname $sci].*]
} -result {1 1 {error: color must be 'white' or 'black'} {error: no open repertoire matches 'nosuch'}}

tcltest::test assistant-repertoire-none {without an open repertoire the tool says how to get one} -body {
	::application::assistant::runTool repertoire_check {}
} -result {error: no repertoire is open: open a database of type Openings, Openings White or Openings Black}


proc ::scidb::test::assistant::search {criteria} {
	set reply [::application::assistant::runTool search_games $criteria]
	set lines [split $reply \n]
	# the game number in front of each game ("#12 ...") is checked separately
	return [list [lindex $lines 1] [lmap line [lrange $lines 3 end] { regsub {^#\d+ } [string trim $line] {} }]]
}

tcltest::test assistant-search-games {search_games combines player, colour, result, ECO and dates} -body {
	list [::scidb::test::assistant::search {player {carlsen, m} result win}] \
		[::scidb::test::assistant::search {player {Carlsen, Magnus} color black result draw}] \
		[::scidb::test::assistant::search {player {Carlsen, Magnus} opponent anand}] \
		[::scidb::test::assistant::search {eco B9 from 2022}] \
		[lindex [split [::application::assistant::runTool search_games {eco B9 from 2022 to 2023.06}] \n] 0] \
		[::scidb::test::assistant::search {result 1-0}] \
		[::scidb::test::assistant::search {to 2021.06}] \
		[lindex [split [::application::assistant::runTool search_games {player {carlsen, m} color white result loss}] \n] 0]
} -match glob -result {{{2 games found} {{2021.01.01 Carlsen, Magnus - Anand, Viswanathan 1-0 B90, Assistant} {2023.01.01 Carlsen, Henrik - Carlsen, Magnus 0-1 C60, Assistant}}} {{1 games found} {{2022.01.01 Anand, Viswanathan - Carlsen, Magnus 1/2-1/2 B92, Assistant}}} {{2 games found} *} {{1 games found} {{2022.01.01 Anand*B92*}}} {searched * for: ECO B90-B99; from 2022 to 2023.06} {{1 games found} {{2021.01.01 Carlsen, Magnus*}}} {{1 games found} {{2021.01.01*}}} {searched * for: games of Carlsen, Magnus with white, lost}}

tcltest::test assistant-search-refused {search_games checks its criteria} -body {
	list [::application::assistant::runTool search_games {}] \
		[::application::assistant::runTool search_games {color white}] \
		[::application::assistant::runTool search_games {player carlsen result 1-0}] \
		[::application::assistant::runTool search_games {from {last year}}] \
		[::application::assistant::runTool search_games {min_elo 9000}]
} -result {{error: give at least one criterion} {error: color, opponent and a win/draw/loss result need a player} {error: with a player, give the result as win, draw or loss} {error: from must be YYYY, YYYY.MM or YYYY.MM.DD} {error: min_elo must be a number up to 4000}}

tcltest::test assistant-search-terms {the new search terms reject bad arguments} -body {
	set base $::scidb::test::assistant::Fixture
	set view [::scidb::view::new $base Normal unused unused unused unused master slave]
	set result {}
	foreach query {{ecorange B99 B90} {date 2020 x} {result 2-0} {date 2021 2022} {ecorange C00 C99}} {
		if {[catch { ::scidb::view::search $base Normal $view null none $query } err]} {
			lappend result error
		} else {
			lappend result [::scidb::view::count games $base Normal $view]
		}
	}
	::scidb::view::close $base Normal $view
	set result
} -result {error error error 2 1}

tcltest::test assistant-show-search {show_search filters the game list without asking: it changes nothing stored} -body {
	# a user who would refuse every confirmation
	::scidb::test::assistant::setup 0
	set base $::scidb::test::assistant::Fixture
	::application::assistant::runTool search_games {player {Carlsen, Magnus} result win}
	set before [::scidb::view::count games $base Normal 0]
	set calls [::scidb::test::assistant::stubbed ::application::switchTab {
		set shown [::application::assistant::runTool show_search {}]
	}]
	set filtered [::scidb::view::count games $base Normal 0]
	set cleared [::application::assistant::runTool clear_search {}]
	list $before $shown $calls $filtered $cleared [::scidb::view::count games $base Normal 0]
} -result {3 {the game list shows the 2 games of: games of Carlsen, Magnus, won} database 2 {the game list shows all 3 games again} 3}

tcltest::test assistant-game-numbers {search results name each game's number} -body {
	set reply [::application::assistant::runTool search_games {player {carlsen, m} result win}]
	regexp -all -line {^  #\d+ } $reply
} -result 2

tcltest::test assistant-menu-line {a tool with a menu equivalent says where it lives; errors do not} -body {
	set ::application::assistant::ToolMenu $::scidb::test::assistantToolMenu
	set ok [::application::assistant::runTool search_games {player {carlsen, m} result win}]
	set bad [::application::assistant::runTool search_games {}]
	set ::application::assistant::ToolMenu {}
	list [string match "*\nmenu: Database tab > right-click the database > Maintenance > Advanced Search" $ok] \
		[string match "*menu:*" $bad]
} -result {1 0}

tcltest::test assistant-open-game {open_game puts a game on the board at a move} -body {
	set calls [::scidb::test::assistant::stubbed ::application::switchTab {
		set start [::application::assistant::runTool open_game {number 1}]
		set after [::application::assistant::runTool open_game {number 1 move 2 after black}]
		set fen [lindex [::scidb::pos::fen] 0]
		set tooFar [::application::assistant::runTool open_game {number 1 move 400}]
	}]
	list [string match "game 1 (*) is on the board, at the start" $start] \
		[string match "game 1 (*) is on the board, after Black's move 2" $after] \
		[expr {$fen ne "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"}] \
		[string match "error: game 1 has only * moves*" $tooFar] \
		[::application::assistant::runTool open_game {number 9999}] \
		[catch { ::application::assistant::CheckArgs open_game {number 1 after white} } e] $e
} -cleanup {
	# later files expect an empty game on the board
	::scidb::test::assistant::stubbed ::application::switchTab { ::menu::gameNew .application }
} -match glob -result {1 1 1 1 {error: * has 3 games} 1 {after needs a move}}

# Run <body> with the dialog openers replaced by recorders.
proc ::scidb::test::assistant::recording {body} {
	set cmds {::playercard::show ::application::database::player::OpenPrepReport ::crosstable::open
		::application::database::ShowOpeningReport ::application::database::ShowEcoStats
		::application::database::ShowDuplicates}
	foreach cmd $cmds {
		rename $cmd ${cmd}__rec
		proc $cmd {args} "lappend ::scidb::test::assistant::Opened \[concat [list [namespace tail $cmd]] \$args\]"
	}
	set ::scidb::test::assistant::Opened {}
	set rc [catch { uplevel 1 $body } result opts]
	foreach cmd $cmds { rename $cmd {}; rename ${cmd}__rec $cmd }
	return -options $opts $result
}

tcltest::test assistant-open-view {open_view opens the report or dialog for a player, an event or the board} -body {
	::scidb::test::assistant::recording {
		set replies [list \
			[::application::assistant::runTool open_view {kind player_card name {Carlsen, Magnus}}] \
			[::application::assistant::runTool open_view {kind prep_report name anand}] \
			[::application::assistant::runTool open_view {kind crosstable event assist}] \
			[::application::assistant::runTool open_view {kind opening_report}] \
			[::application::assistant::runTool open_view {kind duplicates}]]
	}
	set opened $::scidb::test::assistant::Opened
	list [lmap r $replies { string match "error:*" $r }] \
		[lindex $opened 0] [lindex $opened 1 0] [lindex $opened 2 0] [lindex $opened 3 0] [lindex $opened 4 0] \
		[lindex $opened 0 4] [lindex $opened 2 6]
} -match glob -result {{0 0 0 0 0} {show * Normal * white} OpenPrepReport open ShowOpeningReport ShowDuplicates white game}

tcltest::test assistant-add-to-repertoire {the line goes to the one repertoire named; none or several are explained} -body {
	rename ::application::database::repertoireBases ::scidb::test::assistant::realBases
	rename ::application::database::saveCurrentLineToRepertoire ::scidb::test::assistant::realSave
	proc ::application::database::repertoireBases {args} { return $::scidb::test::assistant::Bases }
	proc ::application::database::saveCurrentLineToRepertoire {parent base args} { lappend ::scidb::test::assistant::Saved $base }
	set ::scidb::test::assistant::Saved {}
	::scidb::test::assistant::setup 1
	set ::scidb::test::assistant::Bases {}
	set none [::application::assistant::runTool add_to_repertoire {}]
	set ::scidb::test::assistant::Bases {/r/White-Rep.sci /r/Black-Rep.sci}
	set several [::application::assistant::runTool add_to_repertoire {}]
	set named [::application::assistant::runTool add_to_repertoire {repertoire black}]
	::scidb::test::assistant::setup 0
	set declined [::application::assistant::runTool add_to_repertoire {repertoire white}]
	rename ::application::database::repertoireBases {}
	rename ::application::database::saveCurrentLineToRepertoire {}
	rename ::scidb::test::assistant::realBases ::application::database::repertoireBases
	rename ::scidb::test::assistant::realSave ::application::database::saveCurrentLineToRepertoire
	list [string match "error: no writable repertoire database is open*" $none] \
		[string match "error: several repertoires are open*say which" $several] \
		[string match "the line is being added to Black-Rep*" $named] \
		[string match "the line is being added to White-Rep*" $declined] $::scidb::test::assistant::Saved
} -result {1 1 1 1 {/r/Black-Rep.sci /r/White-Rep.sci}}

tcltest::test assistant-brief-download-asks {the brief's download asks first; refused, the brief is built without it} -body {
	rename ::ai::brief::build ::scidb::test::assistant::realBrief
	proc ::ai::brief::build {parent name args} { set ::scidb::test::assistant::BriefArgs $args }
	::scidb::test::assistant::setup 0
	set reply [::application::assistant::DoOpponentBrief carlsen white 1 0]
	set refused [dict get $::scidb::test::assistant::BriefArgs -download]
	::scidb::test::assistant::setup 1
	::application::assistant::DoOpponentBrief carlsen white 1 0
	set allowed [dict get $::scidb::test::assistant::BriefArgs -download]
	rename ::ai::brief::build {}
	rename ::scidb::test::assistant::realBrief ::ai::brief::build
	list [string match "*without downloading: the user declined*" $reply] $refused $allowed
} -result {1 0 1}

tcltest::test assistant-save-working-set {the game list's games become a working set, after confirmation} -body {
	rename ::application::database::SaveFilteredViewAsWorkingSet ::scidb::test::assistant::realWs
	proc ::application::database::SaveFilteredViewAsWorkingSet {args} { set ::scidb::test::assistant::Ws $args; return 1 }
	set ::scidb::test::assistant::Ws {}
	::scidb::test::assistant::setup 0
	set declined [::application::assistant::runTool save_working_set {name forks}]
	set none $::scidb::test::assistant::Ws
	::scidb::test::assistant::setup 1
	set saved [::application::assistant::runTool save_working_set {name forks}]
	rename ::application::database::SaveFilteredViewAsWorkingSet {}
	rename ::scidb::test::assistant::realWs ::application::database::SaveFilteredViewAsWorkingSet
	list [string match "*NOT performed*" $declined] $none [string match "the working set is saved*" $saved] \
		[lrange $::scidb::test::assistant::Ws 3 5]
} -result {1 {} 1 {0 assistant forks}}

tcltest::test assistant-event-pattern {event names with spaces are found} -body {
	list [::application::assistant::EventPattern "Karvina 5th"] [::application::assistant::EventPattern " Assistant "]
} -result {{*Karvina 5th*} *Assistant*}

tcltest::test assistant-open-view-errors {open_view says what is missing} -body {
	list [::application::assistant::runTool open_view {kind player_card}] \
		[::application::assistant::runTool open_view {kind crosstable event nosuchevent}] \
		[::application::assistant::runTool open_view {kind magic}]
} -match glob -result {{error: player_card needs a player name} {error: no event matching 'nosuchevent' in *} {error: kind must be one of: *}}

::scidb::test::assistant::closeFixture

tcltest::test assistant-current-game {current_game gives the board game as PGN with the position} -body {
	set reply [::application::assistant::runTool current_game {}]
	list [string match {*\[Event *} $reply] [string match "*current position: * w *" $reply]
} -result {1 1}

tcltest::test assistant-tool-log {every tool call is logged with its outcome} -body {
	set saved $::application::assistant::ToolLog
	set ::application::assistant::ToolLog {}
	::scidb::test::assistant::setup 0
	::application::assistant::runTool run_shell {command ls}
	::application::assistant::runTool switch_tab {tab settings}
	::scidb::test::assistant::stubbed ::menu::gameNew {
		::application::assistant::runTool new_game {}
	}
	::application::assistant::runTool list_open_databases {}
	set reply [::application::assistant::runTool tool_log {count 4}]
	set ::application::assistant::ToolLog $saved
	lmap line [split $reply \n] { regsub {^\[[0-9:]+\] } $line "" }
} -match glob -result {{run_shell {command ls}: error -- error: unknown tool 'run_shell'} {switch_tab {tab settings}: error -- error: tab must be*} {new_game {}: ok -- *} {list_open_databases {}: ok -- *(active)*}}

tcltest::test assistant-tool-log-bounded {the log keeps only the latest calls} -body {
	set saved $::application::assistant::ToolLog
	set ::application::assistant::ToolLog {}
	for {set i 0} {$i < 60} {incr i} { ::application::assistant::runTool list_open_databases {} }
	set n [llength $::application::assistant::ToolLog]
	set ::application::assistant::ToolLog $saved
	set n
} -result 50

set ::application::assistant::Priv(confirm) ::application::assistant::ConfirmDialog
set ::action::BulkHook $::scidb::test::assistantOrgBulkHook

# ----------------------------------------------------------------------

set ::application::assistant::ToolMenu $::scidb::test::assistantToolMenu
::tcltest::cleanupTests
return
