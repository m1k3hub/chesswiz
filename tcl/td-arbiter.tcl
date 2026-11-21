# ======================================================================
# Tournament Director arbiter rules (Laws of Chess 2023) and rulings.
# Rulings and appeals stay accountable to the human TD; rule penalties
# depend on setting (otb, local, engine, platform) and supervision regime.
# ======================================================================

if {[llength [info commands ::util::source]]} { ::util::source td-arbiter }
package require Tcl 8.6

namespace eval ::td::arbiter {}

proc ::td::arbiter::dg {d key {default {}}} { if {[dict exists $d $key]} { return [dict get $d $key] }; return $default }

# Laws of Chess 2023 Article 7.5 and Appendices A/B:
# - Ordinary play (standard) or Blitz supervised (B.2): +120s for first completed OTB illegal move, loss on second (unless opponent cannot mate by any legal sequence -> draw).
# - Rapid supervised (A.4): +60s for first completed OTB illegal move, loss on second.
# - Rapid unsupervised (A.5) or Blitz unsupervised (B.3): +60s for first completed OTB illegal move, loss on second, ONLY if observed by arbiter or claimed before opponent's next move; otherwise the illegal move stands.
# - An illegal GUI attempt rejected before completion is NOT an OTB Article 7.5 offence.
# - Checkmate (Article 5.1.1) takes precedence over 75-move (9.6.2) and fivefold repetition (9.6.1).
proc ::td::arbiter::EvaluateIncident {domain} {
	set setting [dg $domain setting otb]
	set pace [dg $domain pace standard]
	set regime [dg $domain regime standard]
	set incident [dg $domain incident illegal-move]
	set offence [dg $domain offence_count 1]
	set opponentCanMate [dg $domain opponent_can_mate 1]
	set claimedBeforeNextMove [dg $domain claimed_in_time 1]
	set checkmateOnBoard [dg $domain checkmate_on_board 0]

	if {$checkmateOnBoard} {
		return [dict create article "Laws 2023 Art. 5.1.1 / 9.6" penalty_seconds 0 game_result decisive \
			ruling_summary "Checkmate immediately ends the game and takes precedence over 75-move or fivefold repetition claims." \
			uncertainty "Verify that the move producing checkmate was legal."]
	}

	switch -- $incident {
		gui-illegal-attempt {
			return [dict create article "Laws 2023 Art. 7.5 (digital boundary)" penalty_seconds 0 game_result continue \
				ruling_summary "An illegal GUI attempt rejected before move completion and clock press is not an OTB Article 7.5 illegal-move offence." \
				uncertainty "None for rejected GUI input."]
		}
		illegal-move {
			if {$setting eq "local" || $setting eq "platform"} {
				return [dict create article "Laws 2023 Art. 7.5 (digital)" penalty_seconds 0 game_result continue \
					ruling_summary "Digital interface prevents illegal moves before completion; no OTB clock penalty applies." \
					uncertainty "Confirm whether a physical clock was used."]
			}
			if {$setting eq "engine"} {
				return [dict create article "Competition Rules (Engine)" penalty_seconds 0 game_result forfeit-loss \
					ruling_summary "Engine protocol or illegal move violation forfeits the game under engine event rules." \
					uncertainty "Check engine log for UCI output."]
			}
			if {$regime in {A5 B3} && !$claimedBeforeNextMove} {
				return [dict create article "Laws 2023 App. A.5.2 / B.3" penalty_seconds 0 game_result continue \
					ruling_summary "In unsupervised Rapid (A.5) or Blitz (B.3), an illegal move neither observed by the arbiter nor claimed before the opponent's next move stands." \
					uncertainty "Verify whether the opponent touched a piece or completed a reply."]
			}
			set bonus 120
			set cite "Laws 2023 Art. 7.5.5"
			if {$pace eq "rapid" || $regime in {A4 A5 B3}} {
				set bonus 60
				set cite "Laws 2023 Art. 7.5.5 + App. A.3"
				if {$regime eq "B3"} { set cite "Laws 2023 Art. 7.5.5 + App. B.3 / A.3" }
			} elseif {$pace eq "blitz" && $regime eq "B2"} {
				set bonus 120
				set cite "Laws 2023 Art. 7.5.5 + App. B.2"
			}
			if {$offence >= 2} {
				set res [expr {$opponentCanMate ? "loss" : "draw"}]
				return [dict create article $cite penalty_seconds 0 game_result $res \
					ruling_summary "Second completed illegal move by the same player loses the game (or draws if the opponent cannot mate by any legal sequence)." \
					uncertainty "Confirm the first illegal move was previously penalised and recorded."]
			}
			return [dict create article $cite penalty_seconds $bonus game_result continue \
				ruling_summary "First completed OTB illegal move: reinstate position and add $bonus seconds to the opponent's clock." \
				uncertainty "Confirm the clock was pressed after the illegal move."]
		}
		flag-fall {
			set res [expr {$opponentCanMate ? "loss" : "draw"}]
			return [dict create article "Laws 2023 Art. 6.9" penalty_seconds 0 game_result $res \
				ruling_summary [expr {$opponentCanMate ? "Flag fall loses the game because the opponent can mate by a legal sequence." : "Flag fall is a draw (dead position: opponent cannot mate by any legal sequence, Art. 6.9)."}] \
				uncertainty "Dead position depends on whether any series of legal moves can lead to mate, not a simple material count."]
		}
		draw-claim-3fold - draw-claim-50move {
			set valid [dg $domain claim_valid 1]
			if {$valid} {
				return [dict create article "Laws 2023 Art. 9.2 / 9.3" penalty_seconds 0 game_result draw \
					ruling_summary "Correct intended-move or position draw claim under Article 9.2/9.3: game is drawn." \
					uncertainty "Verify the intended move was written on the scoresheet and not played on the board."]
			}
			set bonus [expr {$pace eq "rapid" || $regime in {A4 A5 B3} ? 60 : 120}]
			return [dict create article "Laws 2023 Art. 9.5.b" penalty_seconds $bonus game_result continue \
				ruling_summary "Incorrect draw claim: game continues with the intended move and the opponent receives $bonus extra seconds." \
				uncertainty "Confirm remaining time and intended move."]
		}
		75-move - fivefold {
			return [dict create article "Laws 2023 Art. 9.6" penalty_seconds 0 game_result draw \
				ruling_summary "Mandatory draw by 75 moves or fivefold repetition (unless the last move delivered checkmate)." \
				uncertainty "Verify no capture/pawn move occurred for 75 consecutive moves by each player, or exact position occurred five times."]
		}
		late-arrival {
			set defaultMin [dg $domain default_time_minutes 0]
			set lateMin [dg $domain late_minutes 1]
			set forfeit [expr {$lateMin > $defaultMin}]
			return [dict create article "Laws 2023 Art. 6.7" penalty_seconds 0 game_result [expr {$forfeit ? "forfeit-loss" : "continue"}] \
				ruling_summary [expr {$forfeit ? "Player arrived after published default time ($defaultMin min) and forfeits the game." : "Player arrived within published default time ($defaultMin min); game continues."}] \
				uncertainty "Default time is zero unless the competition regulations specify otherwise."]
		}
		default {
			error "unknown arbiter incident '$incident'"
		}
	}
}

proc ::td::arbiter::Record {state domain} {
	set arbiter [string trim [dg $domain arbiter {}]]
	if {$arbiter eq ""} { error "an arbiter ruling requires the human TD or arbiter name" }
	set summary [string trim [dg $domain decision {}]]
	set eval [EvaluateIncident $domain]
	if {$summary eq ""} { set summary [dict get $eval ruling_summary] }
	set appealStatus [dg $domain appeal_status none]
	if {$appealStatus ni {none provisional-pending-appeal upheld overturned}} { error "invalid appeal status '$appealStatus'" }
	set pairingId [dg $domain pairing {}]
	set entry [dict create id "rul-[expr {[llength [dg $state rulings {}]] + 1}]" \
		pairing $pairingId round [dg $domain round [dg $state current_round 1]] \
		setting [dg $domain setting otb] pace [dg $domain pace standard] regime [dg $domain regime standard] \
		incident [dg $domain incident illegal-move] article [dict get $eval article] \
		penalty_seconds [dict get $eval penalty_seconds] game_result [dict get $eval game_result] \
		decision $summary uncertainty [dict get $eval uncertainty] arbiter $arbiter \
		appeal_status $appealStatus appeal_committee [dg $domain appeal_committee {}] \
		appeal_deadline [dg $domain appeal_deadline 0] appeal_deposit [dg $domain appeal_deposit {}] \
		created [clock seconds]]
	if {$pairingId ne ""} {
		set index [::td::model::FindPairing $state [dict create pairing $pairingId]]
		set pairings [dg $state pairings {}]
		set p [lindex $pairings $index]
		dict lappend p rulings $entry
		if {[dict get $eval penalty_seconds] > 0} {
			dict lappend p clock_adjustments [dict create seconds [dict get $eval penalty_seconds] article [dict get $eval article] arbiter $arbiter created [clock seconds]]
		}
		set applyResult [dg $domain apply_result {}]
		if {$applyResult ne ""} {
			if {$applyResult ni {1-0 0-1 1/2-1/2 0-0}} { error "invalid ruling result '$applyResult'" }
			if {[dg $p result *] ni {* {}}} {
				dict lappend p result_history [dict create result [dict get $p result] category [dg $p category played] ruling [dict get $entry id] corrected [clock seconds]]
			}
			dict set p result $applyResult
			dict set p status [expr {$appealStatus eq "provisional-pending-appeal" ? "provisional" : "complete"}]
			dict set p category [expr {[dict get $eval game_result] eq "forfeit-loss" ? "forfeit" : "played"}]
			dict set p played [expr {[dict get $eval game_result] ne "forfeit-loss"}]
			dict set p count_standings 1
			dict set p rating [dict get $p played]
			dict set p signed_by $arbiter
			dict set p result_reason $summary
		}
		lset pairings $index $p
		dict set state pairings $pairings
		set state [::td::model::PublishCorrection $state]
	}
	dict lappend state rulings $entry
	return [list $state [dict merge $entry [dict create recorded 1]] {} 1]
}

# vi:set ts=3 sw=3:
