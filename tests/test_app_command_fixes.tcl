# Regression tests for the independent review of branch cmdline (FIX-BRIEF).
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::fix {
 variable Notices {}
 variable Assistant {}
 variable Calls {}
 variable Dir [file join $::env(HOME) command-fixes]
}
file mkdir $::fix::Dir

proc ::fix::run {text id} {
 set ::fix::Calls {}
 set ::application::ask::Mode command
 set ::application::ask::Query $text
 unset -nocomplain ::application::ask::Priv(filtered)
 ::application::ask::Typed
 set i 0; set chosen -1
 foreach row $::application::ask::Priv(commands) {
  if {[dict get $row id] == $id && ![llength [dict get $row missing]]} {set chosen $i; break}
  incr i
 }
 if {$chosen < 0} {error "no runnable suggestion for $text: $::application::ask::Priv(commands)"}
 if {[llength $::fix::Calls]} {error {typing executed an action}}
 set ::application::ask::Priv(index) $chosen
 ::application::ask::ShowList
 ::application::ask::Choose
 return $::fix::Calls
}

proc ::fix::trace {command op} {lappend ::fix::Calls [lrange $command 1 end]}
trace add execution ::action::run enter ::fix::trace

proc ::fix::callArgs {calls name} {
 foreach call $calls {
  if {[lindex $call 0] eq $name} {return [lindex $call 1]}
 }
 return {}
}

set ::fix::Base [file join $::fix::Dir Main.pgn]
set f [open $::fix::Base w]
puts $f {[Event "Karvina 5th"]
[Site "Karvina"]
[Date "2020.01.01"]
[Round "1"]
[White "Kasparov, Garry"]
[Black "Carlsen, Magnus"]
[Result "1-0"]
[ECO "B90"]

1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Bg5 1-0

[Event "Biel"]
[Site "Biel"]
[Date "2021.01.01"]
[Round "2"]
[White "Carlsen, Magnus"]
[Black "Kasparov, Garry"]
[Result "1/2-1/2"]
[ECO "D02"]

1. d4 d5 1/2-1/2}
close $f
::action::run open_database [dict create path $::fix::Base]

# ----------------------------------------------------------------------
# F-01: query replies and dispatch errors must be visible on screen.
# ----------------------------------------------------------------------
::tcltest::test F-01-query-output-visible {query output is posted as a visible notice, not only written to the hidden log} -setup {
 set ::fix::Notices {}
 rename ::dialog::notice::post ::fix::realPost
 proc ::dialog::notice::post {kind message args} {lappend ::fix::Notices [list $kind $message]}
} -body {
 set calls [::fix::run {database summary} 4]
 set text [lindex $::fix::Notices 0 1]
 list [llength $::fix::Notices] [expr {[string first "Main" $text] >= 0}] [lindex $::fix::Notices 0 0] $calls
} -cleanup {
 catch {rename ::dialog::notice::post {}}
 rename ::fix::realPost ::dialog::notice::post
} -result {1 1 info {{database_summary {}}}}

::tcltest::test F-01-error-visible {dispatch errors are posted as error notices} -setup {
 set ::fix::Notices {}
 rename ::dialog::notice::post ::fix::realPost
 proc ::dialog::notice::post {kind message args} {lappend ::fix::Notices [list $kind $message]}
 rename ::commandline::Run ::fix::realRun
 proc ::commandline::Run {row} {return "error:handler exploded"}
} -body {
 ::fix::run {database summary} 4
 list [llength $::fix::Notices] [lindex $::fix::Notices 0 0] [lindex $::fix::Notices 0 1]
} -cleanup {
 catch {rename ::dialog::notice::post {}}
 rename ::fix::realPost ::dialog::notice::post
 catch {rename ::commandline::Run {}}
 rename ::fix::realRun ::commandline::Run
} -result {1 error {error:handler exploded}}

# ----------------------------------------------------------------------
# F-02: async handlers answer later through Resolve; the token must not
# leak to the user and the reply must reach them.
# ----------------------------------------------------------------------
::tcltest::test F-02-async-completion {a later token is hidden and its reply is shown when resolved} -setup {
 set ::fix::Notices {}
 set ::fix::Picked 0
 rename ::dialog::notice::post ::fix::realPost
 proc ::dialog::notice::post {kind message args} {lappend ::fix::Notices [list $kind $message]}
 rename ::action::run ::fix::realActionRun
 proc ::action::run {action args} {return "\x00later:77"}
 rename ::commandline::RecordPick ::fix::realRecordPick
 proc ::commandline::RecordPick {row} {incr ::fix::Picked}
} -body {
 set row [lindex [::commandline::Suggest tablebase] 0]
 set result [::commandline::Run $row]
 set pickedBefore $::fix::Picked
 set resolved [::application::assistant::Resolve "\x00later:77" "Tablebase verdict: draw"]
 list [string match "\x00later:*" $result] $pickedBefore $resolved $::fix::Picked [llength $::fix::Notices] [lindex $::fix::Notices 0 1]
} -cleanup {
 catch {rename ::dialog::notice::post {}}
 rename ::fix::realPost ::dialog::notice::post
 catch {rename ::action::run {}}
 rename ::fix::realActionRun ::action::run
 catch {rename ::commandline::RecordPick {}}
 rename ::fix::realRecordPick ::commandline::RecordPick
} -result {0 0 1 1 1 {Tablebase verdict: draw}}

# ----------------------------------------------------------------------
# F-03: find games / find motif filter the visible game list, so exports
# and saves act on the found games rather than the whole database.
# ----------------------------------------------------------------------
::tcltest::test F-03-find-games-filters {find games narrows view 0} -body {
 set before [::scidb::view::count games $::fix::Base Normal 0]
 ::fix::run {find games player Kasparov wins white} 15
 list $before [::scidb::view::count games $::fix::Base Normal 0]
} -result {2 1}

::tcltest::test F-03-find-motif-filters {find motif narrows view 0} -body {
 ::fix::run {clear filter} 6
 set before [::scidb::view::count games $::fix::Base Normal 0]
 ::fix::run {find motif checkmate} 19
 list $before [::scidb::view::count games $::fix::Base Normal 0]
} -result {2 0}

# ----------------------------------------------------------------------
# F-04: an opening name resolves to its whole ECO family, an explicit code
# stays exact.
# ----------------------------------------------------------------------
::tcltest::test R2F-02-eco-names {real suggestions resolve common opening names without cross-volume ranges} -body {
 set actual {}
 foreach name {Sicilian Najdorf {King's Indian} English Dutch Reti London Sveshnikov} {
  set rows [::commandline::Suggest "find games opening $name"]
  lappend actual [dict get [lindex $rows 0] args eco]
 }
 set safe 1
 foreach name {{Queen's Pawn} Indian} {
  foreach row [::commandline::Suggest "find games opening $name"] {
   set range [dict get $row args eco]
   if {[regexp {^([A-E])[0-9]+-([A-E])[0-9]+$} $range -> a b] && $a ne $b} {set safe 0}
  }
 }
 ::fix::run {find games opening London} 15
 list $actual $safe [::scidb::view::count games $::fix::Base Normal 0]
} -result {{B20-B99 B90-B99 E60-E99 A10-A39 A80-A99 A04-A09 D02 B33} 1 1}

::tcltest::test R2F-02-eco-latency {every warm Sicilian keystroke stays below 25ms through Suggest} -body {
 ::commandline::Suggest {score of Sicilian for Kasparov}
 set worst 0
 foreach opening {Sicil Sicilia Sicilian} {
  set start [clock microseconds]
  ::commandline::Suggest "score of $opening for Kasparov"
  set elapsed [expr {([clock microseconds]-$start)/1000.0}]
  set worst [expr {max($worst,$elapsed)}]
 }
 puts "R2F-02 maximum keystroke latency: $worst ms"
 expr {$worst < 25.0}
} -result 1

::tcltest::test F-04-eco-family {opening names resolve to their ECO family range} -body {
 list \
  [lindex [::commandline::EcoLookup eco Sicilian] 0] \
  [lindex [::commandline::EcoLookup eco Najdorf] 0] \
  [lindex [::commandline::EcoLookup eco {King's Indian}] 0] \
  [lindex [::commandline::EcoLookup eco B90] 0]
} -result {B20-B99 B90-B99 E60-E99 B90}

::tcltest::test F-04-eco-score {a Sicilian query counts the B90 game} -setup {
 set ::fix::Notices {}
 rename ::dialog::notice::post ::fix::realPost
 proc ::dialog::notice::post {kind message args} {lappend ::fix::Notices [list $kind $message]}
} -body {
 ::fix::run {score of Sicilian for Kasparov} 24
 set text [lindex $::fix::Notices 0 1]
 list [string match {*1 games*} $text] [string match {*B20-B99*} $text]
} -cleanup {
 catch {rename ::dialog::notice::post {}}
 rename ::fix::realPost ::dialog::notice::post
} -result {1 1}

# ----------------------------------------------------------------------
# F-06: suggestion never makes a synchronous classifier call, even when a
# cloud reranker is configured; ordering stays the deterministic Match order.
# ----------------------------------------------------------------------
::tcltest::test F-06-no-sync-rerank {Suggest is purely deterministic and never calls the classifier} -setup {
 set ::fix::ClassifierCalls 0
 rename ::ai::systemone::enabled ::fix::realEnabled
 rename ::ai::systemone::qualified ::fix::realQualified
 rename ::ai::systemone::chooseSync ::fix::realChooseSync
 proc ::ai::systemone::enabled {} {return 1}
 proc ::ai::systemone::qualified {feature} {return 1}
 proc ::ai::systemone::chooseSync {args} {incr ::fix::ClassifierCalls; return c1}
} -body {
 set baseline [::commandline::Match repertoire]
 set rows [::commandline::Suggest repertoire]
 list $::fix::ClassifierCalls \
  [expr {[lmap r $rows {dict get $r label}] eq [lmap r $baseline {dict get $r label}]}]
} -cleanup {
 catch {rename ::ai::systemone::enabled {}}
 rename ::fix::realEnabled ::ai::systemone::enabled
 catch {rename ::ai::systemone::qualified {}}
 rename ::fix::realQualified ::ai::systemone::qualified
 catch {rename ::ai::systemone::chooseSync {}}
 rename ::fix::realChooseSync ::ai::systemone::chooseSync
} -result {0 1}

# ----------------------------------------------------------------------
# F-08: "repertoire check against my games" checks the user's games, not
# everybody's, and is not runnable when the user has not said who they are.
# ----------------------------------------------------------------------
proc ::fix::repertoireRow {} {
 foreach row [::commandline::Match {repertoire check against my games}] {
  if {[dict get $row id] == 27 && [dict get $row action] eq "command.repertoire_check"} {return $row}
 }
 return {}
}
::tcltest::test F-08-repertoire-my-games {repertoire check injects the remembered player and refuses without one} -setup {
 set ::fix::SavedMe [expr {[info exists ::application::ai::Settings(me)] ? $::application::ai::Settings(me) : ""}]
 set ::fix::RepertoireCalls {}
 set ::fix::SavedRepertoire [::action::get repertoire_check]
 proc ::fix::stubRepertoire {args} {lappend ::fix::RepertoireCalls $args; return checked}
 dict set ::action::Registry repertoire_check handler ::fix::stubRepertoire
 set ::fix::Notices {}
 rename ::dialog::notice::post ::fix::realPost
 proc ::dialog::notice::post {kind message args} {lappend ::fix::Notices [list $kind $message]}
} -body {
 set ::application::ai::Settings(me) {Thomas, Michael}
 set withCalls [::fix::run {repertoire check against my games} 27]
 unset ::application::ai::Settings(me)
 set withoutCalls [::fix::run {repertoire check against my games} 27]
 set message [lindex $::fix::Notices end 1]
 list \
  [expr {[lsearch -exact $withCalls {command.repertoire_check {player {Thomas, Michael}}}] >= 0}] \
  [expr {[lsearch -exact $withCalls {repertoire_check {player {Thomas, Michael}}}] >= 0}] \
  [expr {[lsearch -exact $withoutCalls {repertoire_check {player {Thomas, Michael}}}] < 0}] \
  [string match {*I am <player>*} $message]
} -cleanup {
 catch {rename ::dialog::notice::post {}}
 rename ::fix::realPost ::dialog::notice::post
 set ::action::Registry [dict replace $::action::Registry repertoire_check $::fix::SavedRepertoire]
 if {$::fix::SavedMe eq ""} {catch {unset ::application::ai::Settings(me)}} else {set ::application::ai::Settings(me) $::fix::SavedMe}
} -result {1 1 1 1}

# ----------------------------------------------------------------------
# F-11: question mode marks itself busy, scrubs the facts it sends, and
# supplies the read-only annotation fact-check needed to answer.
# ----------------------------------------------------------------------
::tcltest::test F-11-question-busy-scrubbed-facts {a question is busy, scrubbed and grounded in the fact-check} -setup {
 set ::fix::QuestionMessages {}
 rename ::ai::provider::chatAsync ::fix::realChatAsync
 proc ::ai::provider::chatAsync {messages observer done} {set ::fix::QuestionMessages $messages}
 rename ::application::assistant::DoCurrentGame ::fix::realCurrentGame
 proc ::application::assistant::DoCurrentGame {} {return "Game record from /home/user/game.pgn secret=$::env(SCIDB_TEST_SECRET)"}
 rename ::ai::factcheck::game ::fix::realFactCheckGame
 proc ::ai::factcheck::game {args} {
  return {game 2 checked 1 flagged 1 findings {{move 5.Nf3 text {White is lost} problems {{the queen is still on d1}}}}}
 }
 set ::application::assistant::Priv(busy) 0
} -body {
 set ::env(SCIDB_TEST_SECRET) topsecret-value
 set started [::application::assistant::Question {Please check the annotations of this game}]
 set busyAfter $::application::assistant::Priv(busy)
 set overlap [::application::assistant::Question {second question}]
 set system [dict get [lindex $::fix::QuestionMessages 0] content]
 set noSecret [expr {[string first {topsecret-value} $system] < 0}]
 set redacted [string match {*<redacted:SCIDB_TEST_SECRET>*} $system]
 set hasFact [string match {*Stored-annotation fact-check*} $system]
 set hasFinding [string match {*the queen is still on d1*} $system]
 ::application::assistant::QuestionReply [dict create ok 1 message [dict create content answer]]
 list $started $busyAfter $overlap $noSecret $redacted $hasFact $hasFinding $::application::assistant::Priv(busy)
} -cleanup {
 unset -nocomplain ::env(SCIDB_TEST_SECRET)
 catch {rename ::ai::provider::chatAsync {}}
 rename ::fix::realChatAsync ::ai::provider::chatAsync
 catch {rename ::application::assistant::DoCurrentGame {}}
 rename ::fix::realCurrentGame ::application::assistant::DoCurrentGame
 catch {rename ::ai::factcheck::game {}}
 rename ::fix::realFactCheckGame ::ai::factcheck::game
 set ::application::assistant::Priv(busy) 0
} -result {1 1 0 1 1 1 1 0}

# ----------------------------------------------------------------------
# F-10: completing a missing free-form slot keeps the typed text and never
# corrupts Query; the prepare-against colour is shown as the user's side.
# ----------------------------------------------------------------------
proc ::fix::row {text id} {
 foreach row [::commandline::Match $text] {
  if {[dict get $row id] == $id} {return $row}
 }
 error "no row $id for '$text'"
}
proc ::fix::enterMissing {text id} {
 set ::application::ask::Mode command
 set ::application::ask::Query $text
 unset -nocomplain ::application::ask::Priv(filtered)
 ::application::ask::Typed
 set index 0
 foreach row $::application::ask::Priv(commands) {
  if {[dict get $row id] eq $id && [llength [dict get $row missing]]} {
   set ::application::ask::Priv(index) $index
   ::application::ask::ShowList
   ::application::ask::Choose
   return $::application::ask::Query
  }
  incr index
 }
 error "no incomplete row for $text"
}
::tcltest::test R2F-04-draw-completion {Enter completes draw criteria and the resulting query executes a real search} -body {
 set results {}
 foreach {slot value} {event Biel from 2020} {
  ::fix::run {clear filter} 6
  set query [::fix::enterMissing "find games draws $slot" 15]
  set query [string map [list <$slot> $value] $query]
  set calls [::fix::run $query 15]
  set args [::fix::callArgs $calls search_games]
  lappend results [dict get $args result] [::scidb::view::count games $::fix::Base Normal 0]
 }
 set results
} -result {1/2-1/2 1 1/2-1/2 1}

::tcltest::test F-10-missing-slot {completing an event slot keeps the text and inserts its marker} -body {
 set row [::fix::row {find games event} 15]
 set ::application::ask::Query {find games event}
 ::application::ask::MissingSlot $row
 set q $::application::ask::Query
 list [string match {*<event>*} $q] [string match {find games*} $q] [string first Bielames $q]
} -result {1 1 -1}

::tcltest::test F-10-criteria-complete {a filled criteria tail is runnable and names its slot} -body {
 set row [::fix::row {find games min elo 2600 wins} 15]
 set completed [::commandline::CompleteText [dict get $row template] [dict get $row args] [dict get $row missing]]
 set calls [::fix::run {find games min elo 2600 wins Kasparov} 15]
 list [expr {"player" in [dict get $row missing]}] \
  [dict get [dict get $row args] min_elo] [dict get [dict get $row args] result] \
  [string match {*min elo 2600*} $completed] [string match {*player <player>*} $completed] \
  [expr {[lsearch -exact $calls {command.find {min_elo 2600 result win player {Kasparov, Garry}}}] >= 0}]
} -result {1 2600 win 1 1 1}

::tcltest::test F-10-colour-completion {completed prepare-against text keeps the user's colour} -body {
 set row [::fix::row {prepare against Carlsen i have white} 28]
 set text [::commandline::CompleteText [dict get $row template] [dict get $row args] [dict get $row missing]]
 list [string match {*i have white*} $text] [dict get [dict get $row args] colour]
} -result {1 black}

# ----------------------------------------------------------------------
# RF-01: every find-games query that Enter can run goes through the real
# search_games validation, so colour, ECO ranges and results are normalized.
# ----------------------------------------------------------------------
::tcltest::test RF-01-find-games-normalization {player, opening and draw searches run from Enter and narrow the list} -setup {
 set ::fix::Notices {}
 rename ::dialog::notice::post ::fix::realPost
 proc ::dialog::notice::post {kind message args} {lappend ::fix::Notices [list $kind $message]}
} -body {
 ::fix::run {clear filter} 6
 set playerCalls [::fix::run {find games player Kasparov} 15]
 set playerCount [::scidb::view::count games $::fix::Base Normal 0]
 ::fix::run {clear filter} 6
 set openingCalls [::fix::run {find games opening Sicilian} 15]
 set openingCount [::scidb::view::count games $::fix::Base Normal 0]
 ::fix::run {clear filter} 6
 set drawRow [::fix::row {find games draws from 2020} 15]
 set drawCalls [::fix::run {find games draws from 2020} 15]
 set drawCount [::scidb::view::count games $::fix::Base Normal 0]
 set minRow [::fix::row {find games min elo 2600 wins} 15]
 set kinds [lmap n $::fix::Notices {lindex $n 0}]
 set playerArgs [::fix::callArgs $playerCalls search_games]
 set openingArgs [::fix::callArgs $openingCalls search_games]
 set drawArgs [::fix::callArgs $drawCalls search_games]
 list $playerCount $openingCount $drawCount \
  [expr {[dict get $playerArgs player] eq {Kasparov, Garry}}] \
  [expr {[dict get $openingArgs eco] eq {B20-B99}}] \
  [expr {[dict get [dict get $drawRow args] result] eq {1/2-1/2}}] \
  [expr {[dict get $drawArgs result] eq {1/2-1/2} && [dict get $drawArgs from] eq {2020}}] \
  [expr {"player" in [dict get $minRow missing]}] \
  [expr {[lsearch -exact $kinds error] < 0}]
} -cleanup {
 catch {rename ::dialog::notice::post {}}
 rename ::fix::realPost ::dialog::notice::post
} -result {2 1 1 1 1 1 1 1 1}

# ----------------------------------------------------------------------
# F-07: "set <engine> threads <n>" changes the saved engine option and does
# not start analysis or a second engine process.
# ----------------------------------------------------------------------
proc ::fix::uciTrace {command op} {lappend ::fix::UciLines [lindex $command 1]}
::tcltest::test R2F-03-running-engine-threads {real best-move Enter reapplies threads to a live Stockfish pipe} -setup {
 set ::fix::SavedEngines $::engine::Engines
 set ::fix::EngineConfig [array get ::ai::engine::Config]
 set ::fix::EngineChoice $::ai::engine::Options(engine)
 set ::fix::Cores [array get ::engine::Options *:cores]
 set executable [lindex [auto_execok stockfish] 0]
 if {$executable eq ""} {error {Stockfish is required for the running-engine regression}}
 set ::engine::Engines [list [dict merge $::engine::EmptyEngine [dict create \
  Name Stockfish Command $executable Protocol UCI Features:UCI {threads {1 128}}]]]
 set ::fix::UciLines {}
 trace add execution ::ai::engine::send enter ::fix::uciTrace
 ::ai::engine::kill
 ::fix::run {new game} 43
} -body {
 set answers {}
 foreach named {0 1} {
  ::ai::engine::kill
  ::ai::engine::configure -engine [expr {$named ? "auto" : $executable}]
  ::ai::engine::choose [expr {$named ? "Stockfish" : ""}]
  ::fix::run {set Stockfish threads 1} 40
  ::fix::run {best move with Stockfish} 36
  if {$::ai::engine::Proc eq ""} {error {best move did not start the real engine}}
  set ::fix::UciLines {}
  ::fix::run {set Stockfish threads 2} 40
  ::fix::run {best move with Stockfish} 36
  lappend answers [expr {{setoption name Threads value 2} in $::fix::UciLines}]
  set ::fix::UciLines {}
  # SetThreads arrives while evaluate is pumping Tk's event loop. The
  # in-flight search finishes; the next evaluation applies the new value.
  set ::fix::ThreadTimer [after 0 {::fix::run {set Stockfish threads 3} 40}]
  ::fix::run {best move with Stockfish} 36
  ::fix::run {best move with Stockfish} 36
  lappend answers [expr {{setoption name Threads value 3} in $::fix::UciLines}]
 }
 set answers
} -cleanup {
 catch {after cancel $::fix::ThreadTimer}
 catch {::ai::engine::shutdown}
 trace remove execution ::ai::engine::send enter ::fix::uciTrace
 array set ::ai::engine::Config $::fix::EngineConfig
 set ::ai::engine::Options(engine) $::fix::EngineChoice
 set ::engine::Engines $::fix::SavedEngines
 array unset ::engine::Options *:cores
 array set ::engine::Options $::fix::Cores
} -result {1 1 1 1}

::tcltest::test F-07-set-threads {set engine threads saves the count without starting analysis} -setup {
 set ::fix::SavedEngines $::engine::Engines
 set ::engine::Engines [list [dict merge $::engine::EmptyEngine {
  Name {Stub Engine} Command /bin/true Protocol UCI
  Features:UCI {analyze true threads {1 128}}
  Profiles:UCI {Default {{Threads spin 4 4 1 128} {Hash spin 16 16 1 1024}}}
 }]]
} -body {
 set before [::engine::DefaultThreads {Stub Engine}]
 set panesBefore [llength [::application::assistant::RunningPanes]]
 ::fix::run {set Stub Engine threads 8} 40
 set after [::engine::DefaultThreads {Stub Engine}]
 list $before $after $panesBefore [llength [::application::assistant::RunningPanes]]
} -cleanup {
 foreach number [::application::assistant::RunningPanes] {
  catch {::application::analysis::stopEngine $number}
 }
 set ::engine::Engines $::fix::SavedEngines
} -result {{} 8 0 0}

::tcltest::test F-07-play-threads {the play engine sends the stored thread count} -setup {
 set ::fix::SavedEngines $::engine::Engines
 set ::engine::Engines [list [dict merge $::engine::EmptyEngine {
  Name {Stub Engine} Command /bin/true Protocol UCI
  Features:UCI {limitStrength {0 2000} skillLevel {0 20} threads {1 128}}
 }]]
 set ::fix::StubName {Stub Engine}
 set ::fix::HadCores [info exists ::engine::Options(${::fix::StubName}:cores)]
 set ::fix::OldCores [expr {$::fix::HadCores ? $::engine::Options(${::fix::StubName}:cores) : ""}]
 set ::engine::Options(${::fix::StubName}:cores) 6
 set ::fix::HadFull [info exists ::playengine::Priv(full)]
 set ::fix::OldFull [expr {$::fix::HadFull ? $::playengine::Priv(full) : 0}]
 set ::playengine::Priv(engine) {Stub Engine}
 set ::playengine::Priv(full) 1
 set ::fix::Sent {}
 rename ::playengine::Send ::fix::realPlaySend
 proc ::playengine::Send {line} {lappend ::fix::Sent $line}
} -body {
 ::playengine::SendOptions
 expr {[lsearch -exact $::fix::Sent {setoption name Threads value 6}] >= 0}
} -cleanup {
 catch {rename ::playengine::Send {}}
 rename ::fix::realPlaySend ::playengine::Send
 set ::engine::Engines $::fix::SavedEngines
 if {$::fix::HadCores} {set ::engine::Options(${::fix::StubName}:cores) $::fix::OldCores} else {unset -nocomplain ::engine::Options(${::fix::StubName}:cores)}
 if {$::fix::HadFull} {set ::playengine::Priv(full) $::fix::OldFull} else {unset -nocomplain ::playengine::Priv(full)}
 unset -nocomplain ::playengine::Priv(engine)
} -result 1

::tcltest::test F-07-ai-engine-threads {analysis, best move and annotation engines send the stored thread count} -setup {
 set ::fix::FakeEngine [file join $::fix::Dir fake-uci.sh]
 set ::fix::FakeLog [file join $::fix::Dir fake-uci.log]
 file delete -force $::fix::FakeLog
 set f [open $::fix::FakeEngine w]
 puts $f {#!/bin/sh}
 puts $f {while IFS= read -r line; do}
 puts $f {printf '%s\n' "$line" >> "$FAKE_UCI_LOG"}
 puts $f {case "$line" in}
 puts $f {uci) echo "id name Fake"; echo uciok;;}
 puts $f {isready) echo readyok;;}
 puts $f {quit) exit 0;;}
 puts $f {esac}
 puts $f {done}
 close $f
 file attributes $::fix::FakeEngine -permissions 0755
 set ::fix::OldConfigEngine $::ai::engine::Config(engine)
 set ::fix::HadEngineCores [info exists ::engine::Options(Stockfish:cores)]
 set ::fix::OldEngineCores [expr {$::fix::HadEngineCores ? $::engine::Options(Stockfish:cores) : ""}]
 set ::engine::Options(Stockfish:cores) 7
 set ::env(FAKE_UCI_LOG) $::fix::FakeLog
 ::ai::engine::configure -engine $::fix::FakeEngine
} -body {
 ::ai::engine::ensure
 ::ai::engine::kill
 set f [open $::fix::FakeLog r]; set options [read $f]; close $f
 expr {[string first {setoption name Threads value 7} $options] >= 0}
} -cleanup {
 catch {::ai::engine::kill}
 ::ai::engine::configure -engine $::fix::OldConfigEngine
 if {$::fix::HadEngineCores} {set ::engine::Options(Stockfish:cores) $::fix::OldEngineCores} else {unset -nocomplain ::engine::Options(Stockfish:cores)}
 unset -nocomplain ::env(FAKE_UCI_LOG)
 catch {file delete -force $::fix::FakeEngine $::fix::FakeLog}
} -result 1

# ----------------------------------------------------------------------
# F-05: the registry palette stays reachable beside the typed commands.
# ----------------------------------------------------------------------
::tcltest::test R2F-01-hidden-adapters {real Ask suggestions never expose argumentless internal adapters} -body {
 set leaked {}
 foreach text {{Replace exported file} {Go to tab} {Switch database} {Open search result} {Set engine threads} {Create puzzles} {Play engine} {Run tournament}} {
  set ::application::ask::Mode command
  set ::application::ask::Query $text
  unset -nocomplain ::application::ask::Priv(filtered)
  ::application::ask::Typed
  foreach row $::application::ask::Priv(commands) {
   if {[dict exists $row palette] && [string match command.* [dict get $row action]]} {
    lappend leaked [dict get $row action]
   }
  }
 }
 foreach row [::action::labels asklist {}] {
  if {[string match command.* [lindex $row 0]]} {lappend leaked [lindex $row 0]}
 }
 set row [::fix::row {set} 40]
 list [lsort -unique $leaked] [expr {[llength [dict get $row missing]] > 0}]
} -result {{} 1}

proc ::fix::noop {args} {return {}}
::tcltest::test F-05-palette {registry actions still appear in the Ask list} -setup {
 ::action::register fix.palette [dict create label "Zebra Palette Action" object {} \
  handler ::fix::noop what {} doc {}]
} -body {
 set ::application::ask::Mode command
 set ::application::ask::Query {zebra palette}
 unset -nocomplain ::application::ask::Priv(filtered)
 ::application::ask::Typed
 set palette 0
 foreach row $::application::ask::Priv(rows) {
  if {[lindex $row 1] eq "Zebra Palette Action"} {set palette 1}
 }
 set ::application::ask::Query {database summary}
 unset -nocomplain ::application::ask::Priv(filtered)
 ::application::ask::Typed
 set grammar 0
 foreach row $::application::ask::Priv(rows) {
  if {[lindex $row 0] eq "database_summary"} {set grammar 1}
 }
 list $palette $grammar
} -cleanup {
 catch {dict unset ::action::Registry fix.palette}
} -result {1 1}

# ----------------------------------------------------------------------
# RF-06: the trailing "Ask the assistant" row is reachable with <Down>.
# ----------------------------------------------------------------------
::tcltest::test RF-06-assistant-row-reachable {keyboard navigation reaches the assistant row of a non-empty list} -setup {
 set ::fix::Sent 0
 rename ::application::ask::SendToAssistant ::fix::realSendToAssistant
 proc ::application::ask::SendToAssistant {} {incr ::fix::Sent; return break}
} -body {
 set ::application::ask::Mode command
 set ::application::ask::Query {database summary}
 unset -nocomplain ::application::ask::Priv(filtered)
 ::application::ask::Typed
 set rows [llength $::application::ask::Priv(rows)]
 for {set i 0} {$i <= $rows} {incr i} {::application::ask::Move 1}
 set index $::application::ask::Priv(index)
 ::application::ask::Choose
 list [expr {$rows >= 1}] [expr {$index == $rows}] $::fix::Sent
} -cleanup {
 catch {rename ::application::ask::SendToAssistant {}}
 rename ::fix::realSendToAssistant ::application::ask::SendToAssistant
 set ::application::ask::Query {}
 ::application::ask::HideList
} -result {1 1 1}

# ----------------------------------------------------------------------
# F-12: the last result list is a typed slot, file slots use the platform
# picker, and a quoted path with spaces is one word.
# ----------------------------------------------------------------------
::tcltest::test F-12-open-result {open result N opens the Nth game of the visible list and is bounded by it} -body {
 ::application::assistant::DoClearSearch
 set count [::scidb::view::count games $::fix::Base Normal 0]
 set calls [::fix::run {open result 2} 51]
 update idletasks
 set index [lindex [::scidb::game::sink? [::scidb::game::current]] 2]
 set over [expr {[::commandline::Values result_index 3] eq ""}]
 list $count $index $calls $over
} -result {2 1 {{command.open_result {result_index 2}}} 1}

::tcltest::test F-12-quoted-path {a quoted file name with spaces stays one word and matches} -body {
 set path [file join $::fix::Dir "my games.pgn"]
 set f [open $path w]
 puts $f {[Event "Quoted"]
[White "A"]
[Black "B"]
[Result "1-0"]

1. e4 1-0}
 close $f
 set words [::commandline::Words "\"$path\""]
 set row {}
 foreach r [::commandline::Match "import \"$path\" into Main"] {
  if {[dict get $r id] == 7} {set row $r; break}
 }
 list [llength $words] [expr {[lindex $words 0] eq $path}] [expr {$row ne {}}] \
  [expr {$row ne {} && [dict get $row args files] eq $path && ![llength [dict get $row missing]]}]
} -result {1 1 1 1}

::tcltest::test F-12-file-picker {Enter on a missing file slot unpacks the X11 picker pair and completes the sentence} -setup {
 set ::fix::Picked [file join $::fix::Dir "picked database.pgn"]
 set ::fix::DialogCalls {}
 rename ::dialog::openFile ::fix::realOpenFile
 rename ::dialog::saveFile ::fix::realSaveFile
 proc ::dialog::openFile {args} {lappend ::fix::DialogCalls [list open $args]; return [list $::fix::Picked {}]}
 proc ::dialog::saveFile {args} {lappend ::fix::DialogCalls [list save $args]; return [list [file join $::fix::Dir New.si4] {}]}
} -body {
 set row [::fix::row {open database} 1]
 set ::application::ask::Query {open database}
 ::application::ask::MissingSlot $row
 set query $::application::ask::Query
 set openTypes [lindex $::fix::DialogCalls 0 1]
 set saveRow [::fix::row {save list as new database} 10]
 set ::application::ask::Query {save list as new database}
 ::application::ask::MissingSlot $saveRow
 set saveQuery $::application::ask::Query
 set saveTypes [lindex $::fix::DialogCalls 1 1]
 set playerRow [::fix::row {find games player} 15]
 set ::application::ask::Query {find games player}
 ::application::ask::MissingSlot $playerRow
 list \
  [string match {open database "*} $query] [string match {*picked database.pgn*} $query] \
  [expr {[string first "{}" $query] < 0}] \
  [expr {[string first .sci $openTypes] >= 0}] [expr {[string first .sci $saveTypes] >= 0}] \
  [string match {save list as new database *New.si4*} $saveQuery] \
  [expr {[::commandline::Values result_index 1] ne {}}]
} -cleanup {
 catch {rename ::dialog::openFile {}}
 rename ::fix::realOpenFile ::dialog::openFile
 catch {rename ::dialog::saveFile {}}
 rename ::fix::realSaveFile ::dialog::saveFile
 set ::application::ask::Query {}
 ::application::ask::HideList
} -result {1 1 1 1 1 1 1}

# ----------------------------------------------------------------------
# F-13: the field's own words, including the new buttons and the Aliases
# dialog, follow the language; English no longer invites prose.
# ----------------------------------------------------------------------
::tcltest::test F-13-language {the placeholder and new controls are translated and relabel live} -body {
 set ::fix::savedShare $::scidb::dir::share
 set wt [file normalize [file join [file dirname [file normalize [info script]]] .. tcl]]
 if {[file isdirectory [file join $wt lang]]} { set ::scidb::dir::share $wt }
 set frame [winfo parent [::application::ask::Entry]]
 ::menu::SwitchLanguage English
 update idletasks
 set en [list [set ::application::ask::mc::Placeholder] \
  [$frame.mode cget -text] [$frame.alias cget -text]]
 ::menu::SwitchLanguage Deutsch
 update idletasks
 set de [list [set ::application::ask::mc::Placeholder] \
  [$frame.mode cget -text] [$frame.alias cget -text] \
  [set ::application::ask::mc::AskQuestion] [set ::application::ask::mc::Aliases]]
 ::application::ask::Aliases
 update idletasks
 set w .application.commandAliases
 set dlg [list [wm title $w] [$w.help cget -text] [$w.save cget -text] [$w.remove cget -text]]
 set dlgDe [list [set ::application::ask::mc::AliasesTitle]   [set ::application::ask::mc::AliasesHelp] [set ::application::ask::mc::AliasesSave]   [set ::application::ask::mc::AliasesRemove]]
 destroy $w
 ::menu::SwitchLanguage English
 update idletasks
 set back [list [set ::application::ask::mc::Placeholder] \
  [$frame.mode cget -text] [$frame.alias cget -text]]
 set savedAssistant [set ::application::ask::mc::AskAssistant]
 unset ::application::ask::mc::AskAssistant
 ::application::ask::ResetMC
 set fallback [set ::application::ask::mc::AskAssistant]
 set ::application::ask::mc::AskAssistant $savedAssistant
 list \
  [expr {[lindex $en 0] eq {Type a command (Ctrl+K)}}] \
  [expr {[lindex $en 1] eq {Ask a question}}] \
  [expr {[lindex $de 0] ne [lindex $en 0] && [string match {Befehl*} [lindex $de 0]]}] \
  [expr {[lindex $de 1] eq [lindex $de 3] && [lindex $de 1] ne [lindex $en 1]}] \
  [expr {[lindex $de 2] eq [lindex $de 4] && [lindex $de 2] ne [lindex $en 2]}] \
  [expr {[lindex $dlg 0] eq [lindex $dlgDe 0]}] \
  [expr {[lindex $dlg 1] eq [lindex $dlgDe 1]}] \
  [expr {[lindex $dlg 2] eq [lindex $dlgDe 2]}] \
  [expr {[lindex $dlg 3] eq [lindex $dlgDe 3]}] \
  [expr {$back eq $en}] \
  [expr {$fallback eq {Ask the assistant}}]
} -cleanup {
 catch { destroy .application.commandAliases }
 catch { ::menu::SwitchLanguage English }
 if {[info exists ::fix::savedShare]} {
  set ::scidb::dir::share $::fix::savedShare
  unset ::fix::savedShare
 }
 set ::application::ask::Query {}
 ::application::ask::HideList
} -result {1 1 1 1 1 1 1 1 1 1 1}

::tcltest::test F-13-placeholder-languages {every language placeholder invites a command, not prose} -body {
 set ::fix::savedShare2 $::scidb::dir::share
 set wt [file normalize [file join [file dirname [file normalize [info script]]] .. tcl]]
 if {[file isdirectory [file join $wt lang]]} { set ::scidb::dir::share $wt }
 set bad {}
 foreach lang {Español Italiano Magyar Svenska} {
  ::menu::SwitchLanguage $lang
  update idletasks
  set text [set ::application::ask::mc::Placeholder]
  if {[string first {Ctrl+K} $text] < 0 || [string match {*Chesswiz*} $text]} {
   lappend bad $lang
  }
 }
 ::menu::SwitchLanguage English
 update idletasks
 list $bad
} -cleanup {
 catch { ::menu::SwitchLanguage English }
 if {[info exists ::fix::savedShare2]} {
  set ::scidb::dir::share $::fix::savedShare2
  unset ::fix::savedShare2
 }
} -result {{}}


# ----------------------------------------------------------------------
# F-14: the command contracts match the plan.
# ----------------------------------------------------------------------
::tcltest::test F-14-confirm-before-switch {a declined import or compact never switches the active database} -setup {
 set ::fix::Switches 0
 rename ::application::database::switchToBase ::fix::realSwitchToBase
 proc ::application::database::switchToBase {base} {incr ::fix::Switches}
 set ::fix::SavedBulkHook $::action::BulkHook
 proc ::fix::decline {what} {return 0}
 set ::action::BulkHook ::fix::decline
} -body {
 set imported [::commandline::Action import [dict create files x.pgn database Main]]
 set afterImport $::fix::Switches
 set compacted [::commandline::Action compact [dict create database Main]]
 list $afterImport [string match declined* $imported] $::fix::Switches [string match declined* $compacted]
} -cleanup {
 catch {rename ::application::database::switchToBase {}}
 rename ::fix::realSwitchToBase ::application::database::switchToBase
 set ::action::BulkHook $::fix::SavedBulkHook
} -result {0 1 0 1}

::tcltest::test F-14-convert-format {convert passes the requested format instead of opening the format picker} -setup {
 set ::fix::Switches 0
 set ::fix::ConvertArgs {}
 rename ::application::database::switchToBase ::fix::realSwitchToBase
 proc ::application::database::switchToBase {base} {incr ::fix::Switches}
 rename ::application::assistant::DoConvertDatabase ::fix::realConvert
 proc ::application::assistant::DoConvertDatabase {args} {set ::fix::ConvertArgs $args; return converted}
 set ::fix::SavedBulkHook $::action::BulkHook
 proc ::fix::accept {what} {return 1}
 set ::action::BulkHook ::fix::accept
} -body {
 set calls [::fix::run {convert Main to sci} 13]
 set cbh [::fix::row {convert Main to cbh} 13]
 list $::fix::ConvertArgs $::fix::Switches \
  [expr {[lsearch -exact $calls [list command.convert [dict create database $::fix::Base format sci]]] >= 0}] \
  [expr {[dict get $cbh args] eq [dict create database $::fix::Base format cbh]}]
} -cleanup {
 catch {rename ::application::database::switchToBase {}}
 rename ::fix::realSwitchToBase ::application::database::switchToBase
 catch {rename ::application::assistant::DoConvertDatabase {}}
 rename ::fix::realConvert ::application::assistant::DoConvertDatabase
 set ::action::BulkHook $::fix::SavedBulkHook
} -result {sci 1 1 1}

::tcltest::test F-14-open-game-optional-after {open game at a move does not require white or black} -body {
 set row [::fix::row {open game 1 at move 20} 16]
 set args [dict get $row args]
 list [llength [dict get $row missing]] [dict get $args move] [dict exists $args after]
} -result {0 20 0}

::tcltest::test F-14-black-opening-move {Black move numbers resolve to Black's move, not White's} -body {
 set dotted [::commandline::OpeningMoves [dict create opening Najdorf after 5...a6]]
 set compact [::commandline::OpeningMoves [dict create opening Najdorf after 5.a6]]
 set row [::fix::row {set up Najdorf after 5...a6} 22]
 list [lindex [split $dotted] 9] [expr {$dotted eq $compact}] [llength [dict get $row missing]]
} -result {a6 1 0}

::tcltest::test F-14-trend-view {opening trends opens the trend report instead of returning hidden text} -setup {
 set ::fix::Trends 0
 rename ::ai::trend::report ::fix::realTrend
 proc ::ai::trend::report {args} {incr ::fix::Trends; return {}}
} -body {
 set row [::fix::row {opening trends} 26]
 set action [dict get $row action]
 set kind [expr {[dict exists [dict get $row args] kind] ? [dict get [dict get $row args] kind] : {}}]
 ::action::run $action [dict get $row args]
 list $action $kind $::fix::Trends
} -cleanup {
 catch {rename ::ai::trend::report {}}
 rename ::fix::realTrend ::ai::trend::report
} -result {open_view trend 1}

::tcltest::test F-14-player-reports {player stats and structures open Report tabs instead of returning text} -setup {
 set ::fix::Reports {}
 rename ::application::ai::showReport ::fix::realShowReport
 proc ::application::ai::showReport {parent title html} {lappend ::fix::Reports $title}
 rename ::application::assistant::DoPlayerStats ::fix::realPlayerStats
 proc ::application::assistant::DoPlayerStats {name} {return "stats for $name"}
 rename ::application::assistant::DoStructureProfile ::fix::realStructure
 proc ::application::assistant::DoStructureProfile {player colour games} {return "structures for $player"}
} -body {
 set stats [::fix::row {player Kasparov stats} 30]
 set structures [::fix::row {player Kasparov structures} 30]
 set a [dict get $stats action]
 set b [dict get $structures action]
 ::action::run $a [dict get $stats args]
 ::action::run $b [dict get $structures args]
 list $a $b [llength $::fix::Reports] \
  [string match {*Player statistics*} [lindex $::fix::Reports 0]] \
  [string match {*Player structures*} [lindex $::fix::Reports 1]]
} -cleanup {
 catch {rename ::application::ai::showReport {}}
 rename ::fix::realShowReport ::application::ai::showReport
 catch {rename ::application::assistant::DoPlayerStats {}}
 rename ::fix::realPlayerStats ::application::assistant::DoPlayerStats
 catch {rename ::application::assistant::DoStructureProfile {}}
 rename ::fix::realStructure ::application::assistant::DoStructureProfile
} -result {command.player_stats command.structure_profile 2 1 1}

::tcltest::test F-14-site-criterion {the site criterion is parsed and narrows the search} -body {
 set row [::fix::row {find games site Karvina} 15]
 set args [dict get $row args]
 set calls [::fix::run {find games site Karvina} 15]
 list [dict get $args site] [llength [dict get $row missing]] \
  [expr {[lsearch -exact $calls {command.find {site Karvina}}] >= 0}] \
  [::scidb::view::count games $::fix::Base Normal 0]
} -result {Karvina 0 1 1}

trace remove execution ::action::run enter ::fix::trace
foreach position [::game::usedPositions?] {catch {::game::release $position}}
catch {::application::database::closeBase .application $::fix::Base}
set ::application::ask::Query {}
::application::ask::HideList
::tcltest::cleanupTests
