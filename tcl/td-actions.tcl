# ======================================================================
# Tournament Director registry actions. One command surface for UI and Ask.
# ======================================================================

if {[llength [info commands ::util::source]]} { ::util::source td-actions }
package require Tcl 8.6
namespace eval ::td::actions {}

proc ::td::actions::Controls {} {
	return {{path {type string default {}}} {event {type string default {}}} {commit {type boolean default 0}} {expected_revision {type integer required 1 range {0 1000000000}}} {idempotency {type string required 1}}}
}
proc ::td::actions::MutationSpec {specific} { return [concat $specific [Controls]] }
proc ::td::actions::QuerySpec {} { return {{path {type string default {}}} {event {type string default {}}}} }

proc ::td::actions::Create {arguments} {
	if {[dict get $arguments path] eq ""} {
		dict set arguments path [::td::store::DefaultPath [dict get $arguments name] [dict get $arguments idempotency]]
	}
	set result [::td::event::Execute create $arguments]
	return [::td::event::WaitForAssistant [dict get $result path] $result]
}
proc ::td::actions::Run {command arguments} {
	set result [::td::event::Execute $command $arguments]
	if {$command eq "start" && [dict exists $result path]} { return [::td::event::WaitForAssistant [dict get $result path] $result] }
	return $result
}
proc ::td::actions::Undo {arguments} { return [Run undo $arguments] }
proc ::td::actions::Redo {arguments} { return [Run redo $arguments] }

proc ::td::actions::LookupPlayer {arguments} { return [::td::registration::Lookup $arguments] }

proc ::td::actions::Status {arguments} {
	set path [::td::store::Resolve $arguments]
	set state [dict get [::td::store::Read $path] state]
	::td::store::Register $state $path
	return [::td::event::Status $path]
}
proc ::td::actions::CheckPairings {arguments} {
	set path [::td::store::Resolve $arguments]
	set state [dict get [::td::store::Read $path] state]
	return [::td::swiss::CheckRound $state [dg $arguments round 0]]
}
proc ::td::actions::Standings {arguments} {
	set path [::td::store::Resolve $arguments]
	set state [dict get [::td::store::Read $path] state]
	set rows [::td::score::Compute $state]
	return [dict create event [dict get $state id] revision [dict get $state revision] rows $rows text [::td::score::StandingsText $rows]]
}
proc ::td::actions::Crosstable {arguments} {
	set path [::td::store::Resolve $arguments]
	set state [dict get [::td::store::Read $path] state]
	set rows [::td::score::Compute $state]
	set window {}
	if {[dg $arguments open 0]} { set window [::crosstable::OpenTD .application $path] }
	return [dict create event [dict get $state id] revision [dict get $state revision] window $window text [::td::score::CrosstableText $state $rows]]
}
proc ::td::actions::Audit {arguments} {
	set path [::td::store::Resolve $arguments]
	return [::td::store::Audit $path]
}
proc ::td::actions::Export {arguments} {
	set path [::td::store::Resolve $arguments]
	set filename [dict get $arguments filename]
	if {[file exists $filename] && ![dict get $arguments overwrite]} { error "file exists: $filename" }
	file mkdir [file dirname $filename]
	set format [dict get $arguments format]
	if {$format eq "pgn"} { return [::td::event::ExportPGN $path $filename] }
	set state [dict get [::td::store::Read $path] state]
	set rows [::td::score::Compute $state]
	set html [::td::score::CrosstableHTML $state $rows]
	set temp "$filename.[pid].tmp"
	set out [open $temp w]
	fconfigure $out -encoding utf-8 -translation lf
	puts -nonewline $out $html
	close $out
	file rename -force $temp $filename
	return [dict create filename $filename format html]
}
proc ::td::actions::Workspace {arguments} {
	set operation [dict get $arguments operation]
	set path [dict get $arguments path]
	if {$path eq ""} { set path [::td::store::CurrentPath] }
	switch -- $operation {
		open { return [::td::ui::Open $path [dict get $arguments tab]] }
		close { return [::td::ui::Close] }
		select { return [::td::ui::Select [dict get $arguments tab]] }
	}
}
proc ::td::actions::dg {d key {default {}}} { if {[dict exists $d $key]} { return [dict get $d $key] }; return $default }

proc ::td::actions::Register {} {
	set controls [Controls]
	set query [QuerySpec]
	set createSpec [MutationSpec [list \
		{name {type string default Tournament}} {system {type enum default double-round-robin enum {round-robin double-round-robin swiss}}} \
		{rounds {type integer default 5 range {1 99}}} {players {type array default {}}} {engines {type array default {}}} {kind {type enum default engine enum {human engine}}} \
		{engine_count {type integer default 0 range {0 64}}} {time_control {type string default 3+2}} \
		{opening {type string default {}}} {eco {type string default {}}} {moves {type array default {}}} {suite {type string default {}}} \
		{opening_plies {type integer default 10 range {1 40}}} {overhead_ms {type integer default 100 range {0 10000}}} \
		{concurrency {type integer default 2 range {1 16}}} {max_plies {type integer default 0 range {0 1000}}} \
		{tablebase {type boolean default 1}} {colour_lot {type enum default white enum {white black}}} \
		{unrated_policy {type enum default drop enum {drop exclude}}} {start {type boolean default 1}}]]
	set registerSpec [MutationSpec {{players {type array required 1}} {kind {type enum default human enum {human engine}}}}]
	set pairSpec [MutationSpec {{round {type integer default 0 range {0 1000}}}}]
	set resultSpec [MutationSpec [list {pairing {type string default {}}} {round {type integer default 0 range {0 1000}}} \
		{board {type integer default -1 range {-1 10000}}} {result {type enum required 1 enum {1-0 0-1 1/2-1/2 0-0 *}}} \
		{category {type enum default played enum {played forfeit forfeit-loss double-forfeit adjourned}}} {signed_by {type string default {}}} {reason {type string default {}}}]]
	foreach {id label doc spec handler effect} [list \
		td.create {Create tournament} {Create a C.05 round robin for humans or engines. Preview with commit false, then commit at the supplied revision. For an engine event it can also pair and play every round from a named opening, an opening code range or a list of moves.} $createSpec Create change \
        td.lookup_player {Find FIDE player} {Find a player by exact name or FIDE number in the installed rating list.} {{fide_id {type string default {}}} {name {type string default {}}}} LookupPlayer query \
        td.register_fide {Register FIDE player} {Copy a player's identity and rating into this event, keeping a dated record for later review.} [MutationSpec {{fide_id {type string required 1}}}] [list Run register_fide] change \
		td.register {Register players} {Register human or configured engine players before pairings are published.} $registerSpec [list Run register] change \
		td.pair_round {Pair round} {Preview or commit Berger pairings for one round, or all rounds when round is zero.} $pairSpec [list Run pair_round] change \
		td.start {Start tournament} {Start or resume an event and schedule engine games with bounded concurrency.} $pairSpec [list Run start] change \
		td.stop {Stop tournament} {Stop all event engine processes and preserve completed games; running attempts become pending.} $controls [list Run stop] change \
		td.enter_result {Enter result} {Enter a played or forfeit result for a pending human pairing.} $resultSpec [list Run enter_result] change \
		td.correct_result {Correct result} {Correct a completed result without rewriting audit history; published standings gain a new publication revision.} $resultSpec [list Run correct_result] change \
		td.override_pairing {Override pairing} {Change seats in a pending pairing with a required reason and C.04.3 checker report; prohibited overrides require a human TD ruling and stay marked non-compliant.} [MutationSpec {{pairing {type string default {}}} {round {type integer default 0 range {0 1000}}} {board {type integer default -1 range {-1 10000}}} {white {type string required 1}} {black {type string required 1}} {reason {type string required 1}} {ruling {type string default {}}}}] [list Run override_pairing] change \
		td.check_pairings {Check pairings} {Check a round's pairings against C.04.3 criteria and the Dutch pairing helper without changing tournament state.} [concat $query {{round {type integer default 0 range {0 1000}}}}] CheckPairings query \
		td.withdraw {Withdraw player} {Withdraw a player before or after pairing; applies C.05 annulment or forfeits in round robins, and Swiss withdrawal handling.} [MutationSpec {{player {type string required 1}} {round {type integer default 0 range {0 1000}}} {policy {type enum default forfeit-win enum {forfeit-win double-forfeit}}}}] [list Run withdraw] change \
		td.bye {Record bye} {Record a requested, zero-point, full-point or pairing-allocated bye with explicit points and category.} [MutationSpec {{player {type string required 1}} {round {type integer default 0 range {0 1000}}} {category {type enum default requested-bye enum {requested-bye zero-point-bye full-point-bye pairing-bye}}} {points {type integer default -1 range {-1 2}}}}] [list Run bye] change \
		td.ruling {Record arbiter ruling} {Evaluate and record a human TD or arbiter ruling under Laws of Chess 2023 with setting, supervision regime, clock penalty and optional appeal status.} [MutationSpec {{pairing {type string default {}}} {round {type integer default 0 range {0 1000}}} {setting {type enum default otb enum {otb local engine platform}}} {pace {type enum default standard enum {standard rapid blitz}}} {regime {type enum default standard enum {standard A4 A5 B2 B3}}} {incident {type enum default illegal-move enum {illegal-move gui-illegal-attempt flag-fall draw-claim-3fold draw-claim-50move 75-move fivefold late-arrival}}} {offence_count {type integer default 1 range {1 10}}} {opponent_can_mate {type boolean default 1}} {claimed_in_time {type boolean default 1}} {claim_valid {type boolean default 1}} {checkmate_on_board {type boolean default 0}} {default_time_minutes {type integer default 0 range {0 240}}} {late_minutes {type integer default 1 range {0 240}}} {arbiter {type string required 1}} {decision {type string default {}}} {apply_result {type string default {}}} {appeal_status {type enum default none enum {none provisional-pending-appeal upheld overturned}}} {appeal_committee {type string default {}}} {appeal_deadline {type integer default 0 range {0 2000000000}}} {appeal_deposit {type string default {}}}}] [list Run ruling] change \
		td.publish {Publish standings} {Append an immutable publication snapshot; later corrections create another publication revision.} $controls [list Run publish] change \
		td.finish {Finish tournament} {Finish an event when every non-bye game is complete and return the final standings.} $controls [list Run finish] change \
		td.undo {Undo tournament command} {Undo the latest reversible domain command at the current revision without deleting audit history.} $controls Undo change \
		td.redo {Redo tournament command} {Redo an undone domain command at the current revision without deleting audit history.} $controls Redo change \
		td.status {Tournament status} {Show the event's revision, current round, how many players and pairings it has, how it is saved, and whether undo or redo is available.} $query Status query \
		td.standings {Tournament standings} {Compute exact C.07 standings and every tiebreak breakdown.} $query Standings query \
		td.crosstable {Tournament crosstable} {Return the event crosstable as text, or open its journal-backed HTML view.} [concat $query {{open {type boolean default 0}}}] Crosstable change \
		td.audit {Tournament audit} {Return immutable journal records, including commands, revisions, idempotency keys and before/after state.} $query Audit query \
		td.export {Export tournament} {Save the tournament's games, or its crosstable as a web page, to a file you name.} [concat $query {{filename {type string required 1}} {format {type enum default pgn enum {pgn html}}} {overwrite {type boolean default 0}}}] Export change \
		td.workspace {Tournament Director workspace} {Open the Event, Players, Pairings, Results and Standings workspace, close it, or select a tab.} [concat $query {{operation {type enum default open enum {open close select}}} {tab {type enum default event enum {event players pairings results standings}}}}] Workspace change \
	] {
		if {[dict exists $::action::Registry $id]} { continue }
		::action::register $id [dict create label $label what $label doc $doc purpose $doc \
			when "When managing a chess tournament through the Tournament Director." \
			examples [list "Tournament Director: [string tolower $label]" "Please [string tolower $label] in my tournament"] \
			related {td.workspace td.status td.standings} keywords {tournament director event round robin players pairings results standings} \
			object {} ai 0 operator 1 confirm 0 args $spec effect $effect handler ::td::actions::$handler]
	}
	if {[info exists ::knowledge::Topics]} {
		set found 0
		foreach topic $::knowledge::Topics { if {[dict get $topic id] eq "topic:tournament-director"} { set found 1 } }
		if {!$found} {
			lappend ::knowledge::Topics [dict create id topic:tournament-director title "Tournament Director" \
				purpose "Create and run a human or engine round robin with audited pairings, results and exact standings." \
				keywords {tournament director round robin engine thematic london players pairings results standings} \
				steps [list [dict create action td.create args {name {<event>} engine_count 4 system double-round-robin time_control 3+2 opening {London System} start 1 commit 1 expected_revision 0 idempotency {<unique-key>}} label "create and run the event"] \
					[dict create action td.standings args {} label "read exact standings and tiebreaks"] \
					[dict create action td.workspace args {operation open tab standings} label "open the TD workspace"]]]
		}
	}
}

# vi:set ts=3 sw=3:
