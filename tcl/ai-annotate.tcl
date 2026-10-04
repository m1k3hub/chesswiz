# ======================================================================
# ::ai::annotate -- annotate a game with engine-grounded comments.
#
# Walks the current game's mainline (::scidb::game::query mainline), asks
# Stockfish to classify every move, and writes a comment for the moves that
# deserve one.  The division of labour is the project's rule, restated:
#
#   Stockfish  decides what the move is (Best ... Blunder, cp loss, the
#              only-move gap).  It is the only authority on move quality.
#   the gate   decides which moves deserve prose.  Deterministic, from the
#              engine's classification alone -- no model call per move,
#              because a 40-move game would otherwise cost 40 model calls
#              for a decision a threshold makes exactly.
#   the model  writes the words, and only for the gated moves, through the
#              ordinary grounded pipeline (fact pack -> prompt -> claim
#              check -> retry).  A comment whose prose makes claims the
#              facts contradict is NOT written; it is counted as skipped.
#
# Two prose modes:
#   -prose 0   the comment is the engine's own verdict in words, built from
#              the classification dict ("Blunder: loses about 3.5 pawns;
#              best was Nf3.").  No model, no tokens, instant.
#   -prose 1   the language model drafts the comment (default), audited.
#
# Writing: comments are APPENDED through the editor's own path
# (::scidb::game::update addcomment <key> after <text>), so nothing the user
# wrote is ever overwritten.  Optional marks (NAGs) are merged with the ones
# already on the move.  The game is left *modified*; saving stays the user's
# decision, exactly as when they edit a comment by hand.
#
#   ::ai::annotate::annotate $parent ?-prose 1? ?-depth 12? ?-marks 0? \
#       ?-maxPlies 60? ?-done CMD?
#   ::ai::annotate::cancel
#   ::ai::annotate::running?
#
# Cost: one engine search per ply (blocking, seconds each at depth 12) plus
# one model call per gated move.  The run yields to the event loop between
# plies, reports progress in the report pane, and can be cancelled.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-annotate
}

package require Tcl 8.5
package require Tk 8.5

namespace eval ai {
namespace eval annotate {
namespace eval mc {

set Title			"Annotating the game"
set NoEngine		"No chess engine is available for annotation."
set NoGame			"No game to annotate."
set Cancelled		"Annotation cancelled after %d move(s)."
set Done			"Annotated %d move(s): %d comment(s) written, %d skipped."
set Progress		"Annotating move %d of %d (%s)..."
set SkippedClaim	"the drafted comment contradicted the facts"
set SkippedEmpty	"no comment was produced"

} ;# namespace mc

# What a run does.  <classes> is the set that always earns a comment;
# <bestOnlyMove> adds the engine's best move when it was also the only one.
variable Settings
array set Settings {
	depth			12
	maxPlies		60
	prose			1
	marks			0
	classes		{Blunder Mistake Inaccuracy}
	bestOnlyMove	1
	minImportance	low
	prefix		""
}

variable Priv
array set Priv {
	running	0
	cancel	0
	plies		{}
	index		0
	rows		{}
	written	0
	skipped	0
	done		{}
	parent	{}
}

} ;# namespace annotate
} ;# namespace ai


proc ::ai::annotate::configure {args} {
	variable Settings

	foreach {key value} $args {
		set key [string trimleft $key -]
		if {![info exists Settings($key)]} { error "unknown annotation setting '$key'" }
		set Settings($key) $value
	}
	return
}


proc ::ai::annotate::running? {} {
	variable Priv
	return $Priv(running)
}


# ======================================================================
# Pure decisions (unit-tested): the gate, the mark, the wording.
# ======================================================================

# Does the engine's verdict earn a comment?
proc ::ai::annotate::worth {classification {onlyMove 0}} {
	variable Settings

	if {$classification in $Settings(classes)} { return 1 }
	if {$Settings(bestOnlyMove) && $classification eq "Best" && $onlyMove} { return 1 }
	return 0
}


proc ::ai::annotate::nagFor {classification} {
	switch -- $classification {
		Blunder		{ return {$4} }
		Mistake		{ return {$2} }
		Inaccuracy	{ return {$6} }
	}
	return {}
}


# The numeric annotations in a "marks" string, as a list of $n.
proc ::ai::annotate::extractNags {marks} {
	set out {}
	foreach {whole number} [regexp -all -inline {\$(\d+)} $marks] {
		lappend out "\$$number"
	}
	return $out
}


# The union of the marks already on a move and the one we want to add.
proc ::ai::annotate::mergeNags {existing nag} {
	set out [extractNags $existing]
	if {[string length $nag] && $nag ni $out} { lappend out $nag }
	return [join $out " "]
}


# The comment the engine itself can justify, without a model.
proc ::ai::annotate::plainComment {san classification result} {
	set parts [list $classification]
	if {[dict exists $result cpLoss] && [dict get $result cpLoss] > 0} {
		set loss [dict get $result cpLoss]
		if {$loss >= 10000} {
			lappend parts "loses to a forced mate"
		} else {
			lappend parts [format "loses about %.1f pawns" [expr {$loss / 100.0}]]
		}
	}
	if {[dict exists $result bestMove] && [dict get $result bestMove] ne ""
	 && [dict get $result bestMove] ne [dict get $result uci]} {
		lappend parts "best was [dict get $result bestMove]"
	}
	if {[dict exists $result onlyMove] && [dict get $result onlyMove]} {
		lappend parts "the only move that keeps the evaluation"
	}
	return "[join $parts {; }]."
}


# The instruction handed to the grounded pipeline for one gated move.
proc ::ai::annotate::prompt {san classification result} {
	set facts ""
	if {![catch { ::scidb::ai::moveFacts $san [dict get $result fen] } f]} { set facts $f }
	set kind [dict get $result classification]
	set out "Annotate the move $san for this game's readers, in one or two sentences.\n"
	append out "The engine's verdict, which you must not contradict: $kind"
	if {[dict exists $result cpLoss] && [dict get $result cpLoss] > 0} {
		if {[dict get $result cpLoss] >= 10000} {
			append out " (it allows a forced mate"
		} else {
			append out [format " (it loses about %.1f pawns" \
				[expr {[dict get $result cpLoss] / 100.0}]]
		}
		if {[dict exists $result bestMove] && [dict get $result bestMove] ne ""} {
			append out ", best was [dict get $result bestMove]"
		}
		append out ")"
	}
	append out ". Give the evaluation in pawns, never in centipawns."
	append out ".\nLead with the verdict. Say what went wrong or right in chess terms, \
and what the better continuation was when there is one."
	if {$facts ne ""} { append out "\nMOVE FACTS (JSON):\n$facts" }
	# what the move does and where it leads, in exact vocabulary (CQL)
	if {[llength [info commands ::ai::cql::themes]]
	 && ![catch { ::ai::cql::themesText [::ai::cql::themes [dict get $result fen] $san] } themes]
	 && $themes ne ""} {
		append out "\n$themes"
	}
	return $out
}


# ======================================================================
# The run
# ======================================================================
proc ::ai::annotate::annotate {parent args} {
	variable Priv
	variable Settings
	variable mc

	array set opts [list -prose $Settings(prose) -depth $Settings(depth) \
		-marks $Settings(marks) -maxPlies $Settings(maxPlies) -done {} -from 0 -to end]
	array set opts $args

	if {$Priv(running)} { return 0 }
	if {[llength [info commands ::ai::engine::available]] == 0
	 || ![::ai::engine::available]} {
		::dialog::info -parent $parent -message $mc::NoEngine
		return 0
	}
	if {[catch { set plies [::scidb::game::query mainline] }] || ![llength $plies]} {
		::dialog::info -parent $parent -message $mc::NoGame
		return 0
	}
	# -from/-to: a range of plies (0-based, inclusive), e.g. moves 20-30
	set plies [lrange $plies $opts(-from) $opts(-to)]
	if {![llength $plies]} {
		::dialog::info -parent $parent -message $mc::NoGame
		return 0
	}
	if {[llength $plies] > $opts(-maxPlies)} {
		set plies [lrange $plies 0 [expr {$opts(-maxPlies) - 1}]]
	}

	# Capture game identity and editor state before any asynchronous work.
	set Priv(owner) [Owner]
	set Priv(running) 1
	set Priv(cancel) 0
	# the comment/mark write path only accepts the game's current key, so the
	# run walks the game and puts the board back where it was at the end
	catch { set Priv(savedKey) [::scidb::game::position key] }
	set Priv(plies) $plies
	set Priv(index) 0
	set Priv(rows) {}
	set Priv(written) 0
	set Priv(skipped) 0
	set Priv(done) $opts(-done)
	set Priv(parent) $parent
	set Priv(prose) $opts(-prose)
	set Priv(marks) $opts(-marks)
	set Priv(depth) $opts(-depth)
	set Priv(total) [llength $plies]

	Report [ProgressReport [dict create]]
	after 50 [namespace code NextPly]
	return 1
}


# The menu entry and the assistant both come through here: start a run, or
# stop the one in progress.
proc ::ai::annotate::toggle {parent} {
	if {[running?]} {
		cancel
		Report [ProgressReport [dict create text "Cancelling after this move..."]]
		return 0
	}
	return [annotate $parent]
}


proc ::ai::annotate::cancel {} {
	variable Priv
	variable mc

	if {!$Priv(running)} { return 0 }
	set Priv(cancel) 1
	return 1
}


proc ::ai::annotate::ProgressReport {state} {
	variable Priv
	variable mc

	set html "<p><b>$mc::Title</b></p>"
	if {[dict exists $state text]} {
		append html "<p>[::application::ai::escape [dict get $state text]]</p>"
	}
	if {[llength $Priv(rows)]} {
		append html "<p><b>So far</b></p><ul>"
		foreach row $Priv(rows) {
			append html "<li>[::application::ai::escape $row]</li>"
		}
		append html "</ul>"
	}
	return $html
}


proc ::ai::annotate::Report {html} {
	variable Priv

	if {[llength [info commands ::application::ai::showReport]] == 0} { return }
	catch { ::application::ai::showReport $Priv(parent) \
		"AI: annotate game" [::application::ai::htmlData $html] }
	return
}


proc ::ai::annotate::NextPly {} {
	variable Priv
	variable Settings
	variable mc

	if {!$Priv(running)} { return }
	if {![SameGame]} { set Priv(cancel) 1 }
	if {$Priv(cancel) || $Priv(index) >= [llength $Priv(plies)]} {
		Finish
		return
	}

	lassign [lindex $Priv(plies) $Priv(index)] key san fen
	incr Priv(index)

	Report [ProgressReport [dict create text \
		[format $mc::Progress $Priv(index) $Priv(total) $san]]]

	# let the interface breathe between engine searches
	update idletasks

	if {[catch { ::ai::engine::classify $fen $san -depth $Priv(depth) } result]} {
		lappend Priv(rows) "$san: the engine failed ($result)"
		after 1 [namespace code NextPly]
		return
	}
	dict set result fen $fen
	dict set result san $san
	dict set result key $key

	set onlyMove [expr {[dict exists $result onlyMove] ? [dict get $result onlyMove] : 0}]
	if {![worth [dict get $result classification] $onlyMove]} {
		after 1 [namespace code NextPly]
		return
	}

	Prioritise $result
	return
}


# A7: how much does this engine-flagged moment deserve a comment?  The score
# orders the run and, with minImportance set, drops the routine moments.  With
# no classifier the fallback is "high", so today's behaviour is unchanged.
proc ::ai::annotate::Rank {level} {
	return [lsearch -exact {low medium high} $level]
}


proc ::ai::annotate::High {} {
	return high
}


proc ::ai::annotate::Prioritise {result} {
	set state "ENGINE VERDICT: [dict get $result classification], losing [dict get $result cpLoss] centipawns."
	set question [dict create type score criteria {low medium high} \
		instructions "How much does this move deserve an explanatory comment? low = routine, medium = instructive, high = a key moment of the game."]
	::ai::decide annotate_priority $state $question \
		[namespace code [list OnPriority $result]] -fallback [namespace code High]
	return
}


proc ::ai::annotate::OnPriority {result decision} {
	variable Priv
	variable Settings
	variable mc

	set level [expr {[dict get $decision ok] ? [dict get $decision label] : "high"}]
	dict set result priority $level

	if {[Rank $level] < [Rank $Settings(minImportance)]} {
		lappend Priv(rows) "[dict get $result san]: $level priority, skipped"
		incr Priv(skipped)
		after 1 [namespace code NextPly]
		return
	}

	set san [dict get $result san]

	if {!$Priv(prose)} {
		Write $result [plainComment $san [dict get $result classification] $result]
		after 1 [namespace code NextPly]
		return
	}

	# the model drafts; the pipeline checks the claims against the facts
	if {[catch { Draft $result } err]} {
		lappend Priv(rows) "$san: [format $mc::SkippedEmpty] ($err)"
		incr Priv(skipped)
		after 1 [namespace code NextPly]
		return
	}
	return
}


# The system message for an annotation: the same grounding rules the rest of
# the language layer lives by, phrased for a single move.
proc ::ai::annotate::rules {} {
	return "You annotate ONE move of a chess game for the game's readers.\
		Write one or two sentences, no headings and no lists.\
		Use only what the ENGINE, MOVE FACTS and THEMES blocks state: the verdict, the\
		loss and the better move are facts you must not contradict.  Speak in\
		pawns, never in centipawns (a loss of 10 pawns or more is simply: loses\
		to a forced mate).\
		Never invent a move, an evaluation or a variation that is not in the facts.\
		If a fact is missing, say less, not more."
}


proc ::ai::annotate::Draft {result} {
	variable Priv
	variable Config

	set Priv(pending) $result ;# the ply being drafted (runs are sequential)
	set Priv(draftFen) [dict get $result fen]
	set Priv(draftAttempt) 0
	set Priv(draftPrompt) [prompt [dict get $result san] [dict get $result classification] $result]

	# the model is the one chosen in Extras > AI: Choose Model
	if {[info exists ::application::ai::Config(provider)]} {
		::ai::provider::configure -name $::application::ai::Config(provider) \
			-model $::application::ai::Config(model) \
			-timeout 300000 -options [list num_predict 240]
	}
	AttemptDraft
	return
}


proc ::ai::annotate::AttemptDraft {} {
	variable Priv

	incr Priv(draftAttempt)
	::ai::provider::completeAsync $Priv(draftPrompt) \
		[namespace code OnDraftText] -system [rules]
	return
}


# The claim checker runs on the draft exactly as it does on a report: a
# comment whose chess claims the facts contradict is never written.
proc ::ai::annotate::OnDraftText {result} {
	variable Priv

	if {![dict get $result ok]} {
		OnDraft [dict create ok 0 error [dict get $result error]]
		return
	}
	set text [string trim [dict get $result text]]
	set problems [::ai::claims::check $Priv(draftFen) $text]

	if {![llength $problems] || $Priv(draftAttempt) > 1} {
		OnDraft [dict create ok 1 text $text claims $problems \
			grounded [expr {[llength $problems] == 0}]]
		return
	}
	# one retry, told exactly what it contradicted
	append Priv(draftPrompt) "\n\nYour previous comment made claims the facts contradict: [join $problems {; }]. Rewrite it using only the facts."
	AttemptDraft
	return
}


proc ::ai::annotate::OnDraft {result} {
	# the generation pipeline hands back {ok 1 text claims grounded} or {ok 0 error}
	if {[catch { OnDraftImpl $result } err]} {
		lappend ::ai::annotate::Priv(rows) "draft failed: $err"
		incr ::ai::annotate::Priv(skipped)
		after 1 [namespace code NextPly]
	}
	return
}


proc ::ai::annotate::OnDraftImpl {result} {
	variable Priv
	variable mc

	set ply $Priv(pending)
	set Priv(pending) {}
	set key [dict get $ply key]
	set san [dict get $ply san]

	if {![dict get $result ok]} {
		lappend Priv(rows) "$san: [format $mc::SkippedEmpty] ([dict get $result error])"
		incr Priv(skipped)
	} elseif {![dict get $result grounded]} {
		# ungrounded prose never reaches the game
		lappend Priv(rows) "$san: $mc::SkippedClaim: [join [dict get $result claims] {; }]"
		incr Priv(skipped)
	} else {
		Write $ply [dict get $result text]
	}
	after 1 [namespace code NextPly]
	return
}


proc ::ai::annotate::Write {result text} {
	variable Priv
	if {![SameGame]} {
		set Priv(cancel) 1
		incr Priv(skipped)
		return
	}

	set key [dict get $result key]
	set san [dict get $result san]
	set text [string trim $text]

	if {![string length $text]} {
		lappend Priv(rows) "$san: no comment"
		incr Priv(skipped)
		return
	}
	lappend Priv(rows) [format "%s %s: %s" $san [dict get $result classification] $text]

	# the editor's own restriction: comments are written at the current key,
	# so step the game there first (the move is restored by Finish)
	if {[catch { ::scidb::game::go key $key } err]} {
		lappend Priv(rows) "$san: could not reach the move ($err)"
		incr Priv(skipped)
		return
	}
	if {![SameGame]} { set Priv(cancel) 1; incr Priv(skipped); return }
	if {[catch {
		::scidb::game::update addcomment $key after $text
	} err]} {
		lappend Priv(rows) "$san: could not write the comment ($err)"
		incr Priv(skipped)
		return
	}

	if {![SameGame]} { set Priv(cancel) 1; incr Priv(written); return }
	if {$Priv(marks)} {
		set nag [nagFor [dict get $result classification]]
		if {[string length $nag]} {
			set existing ""
			catch { set existing [::scidb::game::query marks $key] }
			catch { ::scidb::game::update annotation $key [mergeNags $existing $nag] }
		}
	}
	incr Priv(written)
	return
}


# Bind the run to the selected game and exact mainline. Navigation and
# appended comments are safe; replacing moves during a draft is not.
proc ::ai::annotate::Owner {} {
	return [list [::scidb::game::current] [::scidb::game::link?] \
		[::scidb::game::query mainline]]
}


proc ::ai::annotate::SameGame {} {
	variable Priv
	return [expr {[info exists Priv(owner)] && ![catch {Owner} owner] && $owner eq $Priv(owner)}]
}


proc ::ai::annotate::Finish {} {
	variable Priv
	variable mc

	set Priv(running) 0
	set done $Priv(done)
	set Priv(done) {}
	set cancelled $Priv(cancel)
	set Priv(cancel) 0

	# put the board back where the user left it
	if {[SameGame] && [info exists Priv(savedKey)] && [string length $Priv(savedKey)]} {
		catch { ::scidb::game::go key $Priv(savedKey) }
		set Priv(savedKey) {}
	}

	set summary [expr {$cancelled
		? [format $mc::Cancelled $Priv(written)]
		: [format $mc::Done $Priv(index) $Priv(written) $Priv(skipped)]}]

	Report [ProgressReport [dict create text $summary]]
	if {[llength $done]} { catch { {*}$done [dict create \
		ok 1 written $Priv(written) skipped $Priv(skipped) plies $Priv(index) \
		cancelled $cancelled summary $summary] } }
	return $summary
}

# vi:set ts=3 sw=3:
