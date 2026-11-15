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
  if {[dict get $row id] == 27 && [dict get $row action] eq "repertoire_check"} {return $row}
 }
 return {}
}
::tcltest::test F-08-repertoire-my-games {repertoire check injects the remembered player and refuses without one} -setup {
 set ::fix::SavedMe [expr {[info exists ::application::ai::Settings(me)] ? $::application::ai::Settings(me) : ""}]
} -body {
 set ::application::ai::Settings(me) {Thomas, Michael}
 set row [::fix::repertoireRow]
 set args [dict get $row args]
 set withPlayer [list [dict exists $args player] [dict get $args player] [llength [dict get $row missing]]]
 unset ::application::ai::Settings(me)
 set row [::fix::repertoireRow]
 set missing [dict get $row missing]
 list {*}$withPlayer [expr {"player" in $missing}] [dict exists [dict get $row args] player]
} -cleanup {
 if {$::fix::SavedMe eq ""} {catch {unset ::application::ai::Settings(me)}} else {set ::application::ai::Settings(me) $::fix::SavedMe}
} -result {1 {Thomas, Michael} 0 1 0}

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
::tcltest::test F-10-missing-slot {completing an event slot keeps the text and inserts its marker} -body {
 set row [::fix::row {find games event} 15]
 set ::application::ask::Query {find games event}
 ::application::ask::MissingSlot $row
 set q $::application::ask::Query
 list [string match {*<event>*} $q] [string match {find games*} $q] [string first Bielames $q]
} -result {1 1 -1}

::tcltest::test F-10-criteria-complete {a filled criteria tail is runnable and names its slot} -body {
 set row [::fix::row {find games min elo 2600 wins} 15]
 list [llength [dict get $row missing]] [dict get [dict get $row args] min_elo] [dict get [dict get $row args] result]
} -result {0 2600 win}

::tcltest::test F-10-colour-completion {completed prepare-against text keeps the user's colour} -body {
 set row [::fix::row {prepare against Carlsen i have white} 28]
 set text [::commandline::CompleteText [dict get $row template] [dict get $row args] [dict get $row missing]]
 list [string match {*i have white*} $text] [dict get [dict get $row args] colour]
} -result {1 black}

# ----------------------------------------------------------------------
# F-07: "set <engine> threads <n>" changes the saved engine option and does
# not start analysis or a second engine process.
# ----------------------------------------------------------------------
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

# ----------------------------------------------------------------------
# F-05: the registry palette stays reachable beside the typed commands.
# ----------------------------------------------------------------------
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

trace remove execution ::action::run enter ::fix::trace
foreach position [::game::usedPositions?] {catch {::game::release $position}}
catch {::application::database::closeBase .application $::fix::Base}
set ::application::ask::Query {}
::application::ask::HideList
::tcltest::cleanupTests
