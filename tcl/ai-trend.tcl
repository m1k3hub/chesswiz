# ======================================================================
# ::ai::trend -- a read-only, grounded narrative of a database's trends.
#
# The numbers come from the database's own bookkeeping (System One style:
# a deterministic rule answers where one can), the language model only
# phrases them, through the ordinary grounded pipeline:
#
#     facts -> fact block -> prompt -> provider -> claim check -> one retry
#
#   ::ai::trend::facts <base> <variant>
#       -> dict {games N eco M white W draws D black B openings ROWS}
#          with ROWS the most played openings, each {eco name games w d b}
#   ::ai::trend::factsText <facts>  -> the deterministic fact block
#   ::ai::trend::narrate <parent> <facts> ?-done CMD? ?-block TEXT? ?-prompt TEXT?
#                        ?-system TEXT? ?-title TEXT? ?-fen FEN?
#       -block/-prompt/-system/-title let another counts-only narrative (the
#       opening-prep one, ai-openingprep) run the same pipeline; the defaults
#       are this module's own. -fen is the position the claim checker judges any
#       named move against (default: none, so a move-like claim fails).
#       -> (returns the fact block) and, when a model is configured, the
#          ordinary grounded pipeline; -done is called with the dict
#          {ok 1 text ... claims {...} grounded 0|1}
#
# Firewall: this only speaks about *counts* (games, openings, results). It
# never reads a board. The claim checker is therefore handed no position:
# any move-like or placement claim in the narrative fails the check, which
# is the strict side. Without a language model, without a report pane and
# on a provider error, the deterministic facts themselves are the report
# (like ::ai::event without its classifier), so the feature always answers
# with something read-only and true.
#
# Nothing is written: the facts are read through ::scidb::db::count and
# ::scidb::db::ecoStats, and the narrative only ends in the report pane.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-trend
}

package require Tcl 8.5

namespace eval ::ai::trend {
	# how many openings the facts carry
	variable Openings 10
	# the report's length cap for the model, as elsewhere (app-ai)
	variable NumPredict 400
}

# Most games first; ties broken by ECO code, so the order never wavers.
proc ::ai::trend::Compare {a b} {
	set n [expr {[lindex $b 2] - [lindex $a 2]}]
	if {$n != 0} { return $n }
	return [string compare [lindex $a 0] [lindex $b 0]]
}


# The opening's name, through the same lookup the assistant's database
# summary uses (app-assistant::EcoName). Nothing must fail over a name: a
# missing one leaves the code alone in the facts.
proc ::ai::trend::ecoName {eco variant} {
	if {[llength [info commands ::application::assistant::EcoName]]} {
		if {![catch { ::application::assistant::EcoName $eco $variant } name]
			&& [string length $name]} {
			return $name
		}
	}
	return ""
}


# The trend facts of one database: the game count (::scidb::db::count) and
# everything ::scidb::db::ecoStats says, that is, every ECO code's games and
# white wins, draws and black wins ("?" stands for the games without one).
# The totals, the openings rows and ::scidb::db::count's total are the
# deterministic facts the model is asked to narrate, and all it may talk about.
proc ::ai::trend::facts {base variant} {
	variable Openings

	set games [::scidb::db::count games $base $variant]

	set coded 0
	set white 0
	set draws 0
	set black 0
	set openings {}

	foreach row [::scidb::db::ecoStats $base $variant] {
		lassign $row eco n w d b
		if {$eco eq "?"} { continue }
		incr coded $n
		incr white $w
		incr draws $d
		incr black $b
		if {$n} { lappend openings [list $eco [ecoName $eco $variant] $n $w $d $b] }
	}

	set openings [lrange [lsort -command Compare $openings] 0 [expr {$Openings - 1}]]

	return [dict create \
		games $games eco $coded white $white draws $draws black $black \
		openings $openings]
}


# The facts as a compact block, one fact or opening per line.
# Deterministic: a caller may quote it where it can be diffed.
proc ::ai::trend::factsText {facts} {
	set lines [list "games: [dict get $facts games]"]
	if {![dict get $facts eco]} {
		lappend lines "no games with an ECO code"
		return [join $lines \n]
	}

	set w [dict get $facts white]
	lappend lines "games with an ECO code: [dict get $facts eco] (white wins $w, draws [dict get $facts draws], black wins [dict get $facts black])"
	lappend lines "most played openings:"

	foreach row [dict get $facts openings] {
		lassign $row eco name n w d b
		lappend lines "  $eco $name: $n games (white wins $w, draws $d, black wins $b)"
	}
	return [join $lines \n]
}


# The instruction handed to the model, with the fact block as its facts.
proc ::ai::trend::prompt {block} {
	return "A chess database reports these trend facts:\n\n$block\n\nWrite a short narrative for the database's owner: which openings are played most, how the results are split, and what the numbers say about the database's character. Use only the numbers, ECO codes and opening names in the facts; repeat counts exactly; invent nothing, and describe no position and name no move."
}


# The system message for a trend: the grounding rules the rest of the
# language layer lives by, phrased for counts only (ai-annotate::rules).
proc ::ai::trend::system {} {
	return "You narrate a chess database's opening trends for its owner. Every number, ECO code and opening name you mention must come from the trend facts you were given: rephrase them, never add to them. Do not name a game, a player, a move or an evaluation, and do not describe any position on the board."
}


# The model is the one chosen in Extras > AI: Choose Model (app-ai), as in
# the annotation and study-plan pipelines.
proc ::ai::trend::configureProvider {} {
	variable NumPredict

	if {[info exists ::application::ai::Config(provider)]} {
		catch {
			::ai::provider::configure -name $::application::ai::Config(provider) \
				-model $::application::ai::Config(model) -timeout 300000 \
				-options [list num_predict $NumPredict]
		}
	}
	return
}


# The ordinary grounded pipeline over the fact block: one model call, the
# claim checker, one retry on problems. The report pane (when this build
# has one) is fed by ::application::ai::showReport/toHtml; the caller's
# -done receives {ok 1 text ... claims {...} grounded ...}. When there is
# no model at all, when the provider is unreachable, or when the model says
# nothing at all, the deterministic facts stand in: they are the report.
#
# Returns the fact block, so a caller that needs no event loop always has
# something to show.
proc ::ai::trend::narrate {parent facts args} {
	array set opts [list -done {} -block {} -prompt {} -system {} -title "AI: database trends" -fen {}]
	array set opts $args

	set block $opts(-block)
	if {![string length $block]} { set block [factsText $facts] }
	if {![string length $opts(-prompt)]} { set opts(-prompt) [prompt $block] }
	if {![string length $opts(-system)]} { set opts(-system) [system] }

	if {[llength [info commands ::ai::provider::completeAsync]] == 0} {
		# no language model: resolve asynchronously, as a caller that
		# registered -done after narrate returned would never hear anything
		after 0 [list ::ai::trend::deliverFacts $parent $block $opts(-done) $opts(-title)]
		return $block
	}

	configureProvider

	set state [dict create \
		parent $parent \
		block $block \
		prompt $opts(-prompt) \
		system $opts(-system) \
		title $opts(-title) \
		fen $opts(-fen) \
		attempt 0 \
		done $opts(-done)]
	attempt $state
	return $block
}


proc ::ai::trend::attempt {state} {
	dict incr state attempt
	::ai::provider::completeAsync [dict get $state prompt] \
		[namespace code [list ::ai::trend::onComplete $state]] -system [dict get $state system]
	return
}


# Any error in a step (a failing provider, a malformed reply) must still
# reach the caller's callback, or the caller would wait forever. Downstream
# of the model the deterministic facts stand in for all of it (ai-generate).
proc ::ai::trend::onComplete {state result} {
	if {[catch {onCompleteImpl $state $result}]} {
		after 0 [list catch [list ::ai::trend::deliverFacts \
			[dict get $state parent] [dict get $state block] [dict get $state done] \
			[dict get $state title]]]
	}
	return
}


proc ::ai::trend::onCompleteImpl {state result} {
	if {![dict get $result ok]} {
		# the provider is unreachable: the facts are the narrative
		deliverFacts [dict get $state parent] [dict get $state block] \
			[dict get $state done] [dict get $state title]
		return
	}

	set text [string trim [dict get $result text]]

	set problems {}
	if {![string length $text]} {
		# an empty reply proves nothing; it is not a grounded report
		# (ai-generate::noAnswer)
		lappend problems "the model returned no narrative"
	} else {
		# no position to verify against: this is a fact block about the
		# database, so the checker can only police board vocabulary, and any
		# move-like or placement claim in the narrative fails it
		catch { set problems [::ai::claims::check [dict get $state fen] $text] }
	}

	# one try, told exactly what contradicted the facts
	if {[llength $problems] == 0 || [dict get $state attempt] > 1} {
		deliver [dict get $state parent] $text $problems \
			[expr {[llength $problems] == 0}] \
			[dict get $state block] [dict get $state done] [dict get $state title]
		return
	}

	dict set state prompt "[dict get $state prompt]\n\nYour previous answer made claims the facts contradict: [join $problems {; }]. Rewrite it using only the facts."
	attempt $state
	return
}


# One ending: the report pane (if this build has one) and the caller's
# -done. An empty narrative leaves the caller with the facts.
proc ::ai::trend::deliver {parent text claims grounded block done {title "AI: database trends"}} {
	if {![string length [string trim $text]]} {
		return [deliverFacts $parent $block $done $title]
	}

	if {[llength [info commands ::application::ai::showReport]]
		&& [llength [info commands ::application::ai::toHtml]]} {
		if {!$grounded} { append title " (unverified)" }
		set html [::application::ai::toHtml $text $claims {} 1 {} $block]
		catch { ::application::ai::showReport $parent $title [::application::ai::htmlData $html] }
	}

	if {[llength $done]} {
		uplevel #0 [list {*}$done [dict create \
			ok 1 text $text claims $claims grounded $grounded]]
	}
	return
}


# The deterministic facts as the report: the ::ai::event-style degrade when
# no model phrase is available.
proc ::ai::trend::deliverFacts {parent block done {title "AI: database trends"}} {
	if {[llength [info commands ::application::ai::showReport]]} {
		set head [regsub {^AI: } $title {}]
		set head "[string toupper [string index $head 0]][string range $head 1 end]"
		set html "<p><b>[::application::ai::escape $head]</b></p><pre>[::application::ai::escape $block]</pre>"
		catch { ::application::ai::showReport $parent $title \
			[::application::ai::htmlData $html] }
	}
	if {[llength $done]} {
		uplevel #0 [list {*}$done [dict create \
			ok 1 text $block claims {} grounded 1]]
	}
	return
}


# ======================================================================
# The report surface: Extras -> AI: Database Trends
# ======================================================================
proc ::ai::trend::Show {parent html} {
	if {[llength [info commands ::application::ai::showReport]]} {
		catch { ::application::ai::showReport $parent "AI: database trends" \
			[::application::ai::htmlData $html] }
	}
	return
}


proc ::ai::trend::report {parent args} {
	array set opts [list -done {}]
	array set opts $args

	if {[llength [info commands ::application::assistant::ActiveBase]] == 0} {
		Show $parent "<p>No database is open.</p>"
		return ""
	}

	lassign [::application::assistant::ActiveBase] base variant
	if {$base eq ""} {
		Show $parent "<p>No database is open.</p>"
		return ""
	}

	if {[catch { set facts [facts $base $variant] } err]} {
		Show $parent "<p>The trends could not be read: [::application::ai::escape $err]</p>"
		return ""
	}

	Show $parent "<p>Reading the openings...</p>"
	narrate $parent $facts -done $opts(-done)
	return ""
}

# vi:set ts=3 sw=3:
