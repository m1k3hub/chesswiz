# ======================================================================
# ::application::ai -- AI position assessment wired into the report pane.
#
# Extras > "AI: Explain Position" runs grounded generation on the current
# board and renders the result (and any ungrounded claims) in the HTML report
# pane.  Generation is asynchronous so the interface never blocks.
#
#   ::application::ai::configure -provider ollama -model granite4.2:3b
#   ::application::ai::analyze .application
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-ai
}

package require Tcl 8.5
package require Tk 8.5

namespace eval application {
namespace eval ai {

variable Config
array set Config {
	provider   ollama
	model      "deepseek-v4.1-flash:cloud"
	depth      12
	retries    1
	numPredict 400
}

# The provider and model chosen in Extras > AI: Choose Model, saved in the
# options file. The System One classifier backend of the same dialog is saved
# here too (Settings(classifier)). Config holds the values in effect, which
# are overridden (for the session only) by, in this order:
#   --ai-model=NAME / --ai-provider=NAME / --ai-classifier=NAME   command line
#   SCIDB_AI_MODEL / SCIDB_AI_PROVIDER / SCIDB_AI_CLASSIFIER      environment
variable Settings
array set Settings [list provider $Config(provider) model $Config(model) classifier auto]

} ;# namespace ai
} ;# namespace application


# Where the value of <key> (provider|model|classifier) in effect comes from,
# and it: {option|environment|settings value}.
proc ::application::ai::setting {key} {
	variable Settings

	set value [::process::optionValue ai-$key]
	if {[string length $value]} { return [list option $value] }
	set env SCIDB_AI_[string toupper $key]
	if {[info exists ::env($env)] && [string length $::env($env)]} {
		return [list environment $::env($env)]
	}
	return [list settings $Settings($key)]
}


proc ::application::ai::applySettings {} {
	variable Config
	variable Settings

	foreach key {provider model} {
		set Config($key) [lindex [setting $key] 1]
	}
	if {[llength [info commands ::ai::systemone::configure]]} {
		lassign [setting classifier] source backend
		if {[catch { ::ai::systemone::configure -backend $backend }]} {
			# A corrupt saved choice must not break startup: fall back to
			# the default backend and heal the setting, so the bad value
			# is not written back to the options file on exit.
			catch { ::ai::systemone::configure -backend kev }
			if {$source eq "settings"} { set Settings(classifier) kev }
		}
		# In auto mode this finds a local server; an explicit choice is a no-op.
		if {[llength [info commands ::ai::systemone::autostart]]} {
			::ai::systemone::autostart
		}
	}
}


# Save a new choice; it takes effect unless overridden.
proc ::application::ai::choose {provider model} {
	variable Settings

	set Settings(provider) $provider
	set Settings(model) $model
	applySettings
}


# Save a new classifier backend; it takes effect unless overridden.
proc ::application::ai::chooseClassifier {backend} {
	variable Settings

	set Settings(classifier) [expr {$backend eq "off" ? "" : $backend}]
	applySettings
}


proc ::application::ai::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Settings
}
if {[llength [info commands ::options::hookWriter]]} {
	::options::hookWriter ::application::ai::WriteOptions
}

if {[llength [info commands ::process::optionValue]]} {
	::application::ai::applySettings
}


proc ::application::ai::configure {args} {
	variable Config

	foreach {key value} $args {
		switch -- $key {
			-provider { set Config(provider) $value }
			-model    { set Config(model) $value }
			-depth    { set Config(depth) $value }
			-retries  { set Config(retries) $value }
			default   { error "unknown option $key" }
		}
	}
	return
}


proc ::application::ai::escape {s} {
	return [string map {& &amp; < &lt; > &gt;} $s]
}


# The report pane is fed a sanitized-document dict (keys html/media/anchors/
# unresolved), not a raw string -- `Load` does `dict get $data html`. Build one
# from generated markup so the pane renders it instead of failing.
proc ::application::ai::htmlData {html} {
	if {[catch {::scidb::html::sanitize $html ""} data]} {
		set data [dict create html $html title "AI assessment" media {} \
			anchors {} warnings {} unresolved 0 converted 0]
	}
	return $data
}


proc ::application::ai::showReport {parent title html} {
	return [::application::report::showHtmlData $parent $title [htmlData $html]]
}


# <verdict> is shown only for a finished generation; status and error
# messages have no claims to vouch for. <notices> are advisory second-opinion
# labels from the System One classifier (rhetoric / coverage): they never
# affect `grounded` or the claim-check verdict, only add a fixed caution.
proc ::application::ai::toHtml {text claims {evidence {}} {verdict 1} {notices {}}} {
	set html ""

	if {[llength $evidence]} {
		append html "<p><b>Evidence</b></p><ul>"
		foreach line $evidence {
			append html "<li>[escape $line]</li>"
		}
		append html "</ul>"
	}

	set body [escape $text]
	set body [string map {\n <br>} $body]
	append html "<p><b>Assessment</b></p><p>$body</p>"

	if {[llength $claims]} {
		append html "<p><b>Ungrounded claims</b> (contradicted by the facts):</p><ul>"
		foreach claim $claims {
			append html "<li>[escape $claim]</li>"
		}
		append html "</ul>"
	} elseif {$verdict} {
		append html "<p><i>All claims verified against the facts.</i></p>"
	}

	if {[llength $notices]} {
		append html "<p><b>Advisory</b></p><ul>"
		foreach notice $notices {
			append html "<li><i>[escape $notice]</i></li>"
		}
		append html "</ul>"
	}
	return $html
}


# One generation at a time: the prompt build runs a nested engine search, and
# a second request would re-enter it.  Every entry point (analyze, explain
# selection, ...) shares this gate and the placeholder/result rendering, so
# they all route through the same fact-pack -> prompt -> claim-check -> retry
# pipeline (the plan's "one grounding path").
proc ::application::ai::busy? {} {
	variable Busy
	return [expr {[info exists Busy] && $Busy}]
}


proc ::application::ai::begin {parent title placeholder} {
	variable Busy

	if {[busy?]} { return 0 }
	set Busy 1
	::application::ai::showReport $parent $title [toHtml $placeholder {} {} 0]
	return 1
}


# Run the grounded generation for <fen> and render the result in the report
# pane.  <title> names the report; <placeholder> is shown immediately so the
# pane never blocks (latency honesty).
proc ::application::ai::generate {parent title placeholder fen args} {
	variable Config

	if {![begin $parent $title $placeholder]} { return }

	if {[catch {
		::ai::provider::configure -name $Config(provider) -model $Config(model) \
			-timeout 300000 -options [list num_predict $Config(numPredict)]
		::ai::generate::positionToolsAsync $fen \
			[namespace code [list ::application::ai::onResult $parent $title]] \
			-depth $Config(depth) -retries $Config(retries) {*}$args
	} err]} {
		# prompt construction is synchronous (facts, engine); report its
		# failure in the pane rather than leaving the placeholder up
		onResult $parent $title [dict create ok 0 error $err]
	}
	return
}


proc ::application::ai::analyze {parent} {
	if {[catch {::scidb::pos::fen} fen]} {
		::dialog::info -parent $parent -message "No position available: $fen"
		return
	}
	generate $parent "AI assessment" "Analyzing the current position..." $fen
	return
}


proc ::application::ai::onResult {parent title result} {
	variable Busy
	set Busy 0

	if {![dict get $result ok]} {
		::application::ai::showReport $parent "$title (error)" \
			[toHtml "Generation failed: [dict get $result error]" {} {} 0]
		return
	}

	set state [expr {[dict get $result grounded] ? "grounded" : "unverified"}]
	set evidence [expr {[dict exists $result evidence] ? [dict get $result evidence] : {}}]
	set notices [expr {[dict exists $result notices] ? [dict get $result notices] : {}}]
	::application::ai::showReport $parent "$title ($state)" \
		[toHtml [dict get $result text] [dict get $result claims] $evidence $notices]
	return
}


# ----------------------------------------------------------------------
# C1 -- selection -> explanation.
#
# A right-click "Explain" on a move, a game row or a comment produces a
# grounded explanation of *that thing* in the report pane, using the
# selection as context.  The move case reuses the engine classifier and the
# move facts; the game case reuses the current game's PGN; the comment case
# explains the stored text.  All three render through toHtml/showReport.
# ----------------------------------------------------------------------

# The facts for a single move, as a compact block for the prompt.  Returns
# the empty string when the move cannot be resolved.
proc ::application::ai::moveFacts {san fen} {
	if {[catch {::scidb::ai::moveFacts $san $fen} facts]} { return "" }
	return $facts
}


# A one-line classification of <san> in <fen>, or "" when no engine is
# available (the explanation then falls back to the move facts alone).
proc ::application::ai::moveClass {san fen} {
	if {[llength [info commands ::ai::engine::classify]] == 0} { return "" }
	if {[catch {::ai::engine::classify $san $fen} c]} { return "" }
	return "classification=[dict get $c classification] cpLoss=[dict get $c cpLoss] best=[dict get $c bestMove]"
}


# Explain the move <san> played in <fen>.  The prompt carries the move facts
# and, when an engine is available, the classification; the claim checker
# then verifies the narration against the same position.
proc ::application::ai::explainMove {parent san fen} {
	set facts [moveFacts $san $fen]
	if {$facts eq ""} {
		::dialog::info -parent $parent -message "Cannot explain '$san': not a legal move in this position."
		return
	}
	set class [moveClass $san $fen]
	set context "Explain the move $san in this position.\nMOVE FACTS (JSON):\n$facts\n"
	if {$class ne ""} { append context "MOVE CLASSIFICATION: $class\n" }
	generate $parent "Explain $san" "Explaining $san..." $fen -context $context
	return
}


# Explain the game currently on the board (its header, moves and comments).
proc ::application::ai::explainGame {parent} {
	set source [expr {[::scidb::game::query modified?] ? "modified" : "original"}]
	set pgn [string trim [::scidb::game::toPGN $source]]
	if {$pgn eq ""} {
		::dialog::info -parent $parent -message "No game to explain."
		return
	}
	set fen [::scidb::pos::fen]
	set context "Explain this game to a club player: its opening, the character of the play and the result.\nGAME (PGN):\n$pgn\n"
	generate $parent "Explain game" "Explaining the game..." $fen -context $context
	return
}


# Explain the comment stored at <pos> of the current game.
proc ::application::ai::explainComment {parent pos} {
	if {[catch {::scidb::game::query comment $pos} comment]} {
		::dialog::info -parent $parent -message "No comment at this position."
		return
	}
	set comment [string trim [::scidb::misc::xml toText $comment]]
	if {$comment eq ""} {
		::dialog::info -parent $parent -message "No comment at this position."
		return
	}
	set fen [::scidb::pos::fen]
	set context "Expand this annotation into a fuller explanation for a club player. Do not invent moves or evaluations.\nCOMMENT:\n$comment\n"
	generate $parent "Explain comment" "Explaining the comment..." $fen -context $context
	return
}


# C3: explain the engine's principal variation.  The line is the context and
# is also handed to the claim checker, so a move the model names from the line
# is grounded even when it is not legal in the current position.
proc ::application::ai::explainLine {parent pv fen} {
	set pv [string trim $pv]
	if {$pv eq ""} { return }
	if {$fen eq ""} { set fen [::scidb::pos::fen] }
	set context "Explain the engine's principal variation from this position to a club player.\nENGINE LINE: $pv\nDescribe what the first move achieves and how the idea unfolds. Every move you name must come from this line; do not invent moves or evaluations."
	generate $parent "Explain the engine's line" "Explaining the engine's line..." $fen \
		-context $context -line [split $pv]
	return
}


# Dispatch on the selection kind: {move san fen} | {game} | {comment pos}.
proc ::application::ai::explainSelection {parent kind payload} {
	switch -- $kind {
		move {
			lassign $payload san fen
			if {$fen eq ""} { set fen [::scidb::pos::fen] }
			explainMove $parent $san $fen
		}
		game {
			explainGame $parent
		}
		comment {
			lassign $payload pos
			explainComment $parent $pos
		}
		default {
			error "unknown selection kind '$kind'"
		}
	}
	return
}
