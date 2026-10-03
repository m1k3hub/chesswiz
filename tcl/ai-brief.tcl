# ======================================================================
# ::ai::brief -- one click from a name to a preparation brief.
#
# The pieces all exist: the downloader refreshes the database, the app's
# own preparation report reads the opponent out of it (their openings with
# both colours, how they score in each, their weakest lines, their latest
# games), and the language layer writes prose from facts.  This module is
# the chain, plus one bounded decision:
#
#   the stance  a System One `choice` over a fixed set of strategic
#               stances (punish their weak line, avoid their theory, out-
#               prepare them, stay neutral), decided from the preparation
#               facts.  Confidence-gated; below the threshold, or with no
#               classifier, a deterministic rule over the same facts picks
#               it.  The classifier chooses *how to approach the game*, not
#               what is true about the opponent.
#
#   the prose   written by the model from the preparation text and the
#               stance only, instructed to restate numbers rather than
#               invent them.  (Database statistics are not claims about a
#               position, so the positional claim checker does not apply
#               here; the guard is that the facts are the app's own.)
#
#   ::ai::brief::build $parent <opponent> ?-colour white|black? ?-download 0?
#       ?-prose 1? ?-done CMD?
#
# The brief lands in the Report pane.  Nothing about the opponent is
# inferred by a model: every number comes from the preparation report,
# which comes from the database.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-brief
}

package require Tcl 8.5
package require Tk 8.5

namespace eval ai {
namespace eval brief {
namespace eval mc {

set Title			"Opponent brief"
set NoPlayer		"No games of '%s' are in the active database."
set Downloading	"Fetching the latest games before the brief..."
set Preparing		"Reading %s out of the database..."
set NoBrief		"The language model gave no brief (%s); the database facts above stand."
set Stances {
	punish_weakness	"play the line they score worst in"
	avoid_theory		"keep away from their sharpest theory"
	outprepare		"go deeper than they do in their main line"
	neutral				"play the game, not the opponent"
}
set Advice(punish_weakness)	"Aim for the opening where they score worst; the report quotes the score."
set Advice(avoid_theory)		"Stay out of their main line; a quiet, less analysed continuation takes their preparation away."
set Advice(outprepare)		"Meet them in their own line, one move further than they have shown."
set Advice(neutral)			"No clear weakness: play your own repertoire."
set NoPrep			"the database has no games of this player"

} ;# namespace mc

variable Settings
array set Settings {
	download	0
	prose		1
	stance	auto
}

} ;# namespace brief
} ;# namespace ai


proc ::ai::brief::configure {args} {
	variable Settings

	foreach {key value} $args {
		set key [string trimleft $key -]
		if {![info exists Settings($key)]} { error "unknown brief setting '$key'" }
		set Settings($key) $value
	}
	return
}


# ======================================================================
# The stance
# ======================================================================

# The deterministic reading of the preparation text, used when the
# classifier is off, unsure, or unavailable.
proc ::ai::brief::ruleStance {prep} {
	set lower [string tolower $prep]

	if {[string match {*weakest*} $lower] || [string match {*below average*} $lower]} {
		return punish_weakness
	}
	if {[string match {*novelt*} $lower] || [string match {*rarely*} $lower]
	 || [string match {*not covered*} $lower]} {
		return outprepare
	}
	if {[string match {*sharp*} $lower] || [string match {*main line*} $lower]} {
		return avoid_theory
	}
	return neutral
}


# The classifier's opinion, gated, with the rules as the fallback.
proc ::ai::brief::chooseStance {prep script} {
	variable Settings

	if {$Settings(stance) ne "auto"} {
		after 0 [list {*}$script [list ok 1 stance $Settings(stance) source setting]]
		return
	}
	set question [dict create type choice \
		instructions "Which stance should a player take against this opponent, given the preparation facts?" \
		criteria $mc::Stances]
	::ai::decide stance "PREPARATION FACTS:\n[string range $prep 0 3000]" $question \
		[namespace code [list OnStanceChosen $script]] \
		-fallback [namespace code [list ruleStance $prep]]
	return
}


proc ::ai::brief::OnStanceChosen {script decision} {
	uplevel #0 [list {*}$script [list ok 1 stance [dict get $decision label] \
		source [dict get $decision source]]]
}


# ======================================================================
# The chain
# ======================================================================
proc ::ai::brief::build {parent opponent args} {
	variable Settings
	variable mc

	array set opts [list -colour "" -download $Settings(download) -prose $Settings(prose) -done {}]
	array set opts $args

	set opponent [string trim $opponent]
	if {![string length $opponent]} { return 0 }

	if {[llength [info commands ::application::ai::showReport]]} {
		catch { ::application::ai::showReport $parent "$mc::Title: $opponent" \
			[::application::ai::htmlData "<p>[::application::ai::escape [format $mc::Preparing $opponent]]</p>"] }
	}

	if {$opts(-download) > 0} {
		Refresh $parent $opponent $opts(-download) $opts(-colour) $opts(-prose) $opts(-done)
	} else {
		Prepare $parent $opponent $opts(-colour) $opts(-prose) $opts(-done)
	}
	return 1
}


# Refresh the database first, then build the brief from what is there.
# The downloader is asynchronous and reports when it is done; the brief
# hangs off that report rather than waiting for it, so nothing blocks.
proc ::ai::brief::Refresh {parent opponent issues colour prose done} {
	variable mc

	if {[llength [info commands ::application::download::run]] == 0} {
		Prepare $parent $opponent $colour $prose $done
		return
	}
	if {[llength [info commands ::application::assistant::ActiveBase]]} {
		lassign [::application::assistant::ActiveBase] base variant
	} else {
		set base [::scidb::db::get name]
	}
	Report $parent $mc::Downloading

	set continuation [list ::ai::brief::Prepare $parent $opponent $colour $prose $done]
	if {[catch {
		::application::download::run $base [list -source twic -issues $issues] \
			[list apply [list r $continuation]]
	}]} {
		# a download that did not even start must not lose the brief
		Prepare $parent $opponent $colour $prose $done
	}
	return
}


proc ::ai::brief::Prepare {parent opponent colour prose done} {
	variable mc

	set prep ""
	if {[llength [info commands ::application::assistant::DoPrepareAgainst]]} {
		catch { set prep [::application::assistant::DoPrepareAgainst $opponent $colour] }
	}
	if {![string length $prep]} {
		Report $parent [format $mc::NoPlayer $opponent]
		if {[llength $done]} { catch { {*}$done [dict create ok 0 error [format $mc::NoPlayer $opponent]] } }
		return
	}
	# the kinds of position they reach and how they score there (CQL, exact);
	# part of the facts before the stance is chosen
	append prep [StructureFacts $opponent $colour]
	chooseStance $prep [namespace code [list OnStance $parent $opponent $prep $prose $done]]
	return
}


proc ::ai::brief::StructureFacts {opponent colour} {
	if {[llength [info commands ::ai::cql::profile]] == 0} { return "" }
	if {[catch {
		lassign [::application::assistant::ActiveBase] base variant
		set text [::ai::cql::profileText [::ai::cql::profile $base $variant $opponent -colour $colour]]
	}]} {
		return ""
	}
	return [expr {$text eq "" ? "" : "\n\n$text"}]
}


proc ::ai::brief::OnStance {parent opponent prep prose done result} {
	variable mc

	set stance [dict get $result stance]
	set source [dict get $result source]
	set advice $mc::Advice($stance)

	set head "<p><b>$mc::Title: [::application::ai::escape $opponent]</b></p>"
	append head "<p><b>Stance</b> ($source): [::application::ai::escape [dict get $mc::Stances $stance]] -- [::application::ai::escape $advice]</p>"
	set facts "<p><b>What the database says</b></p><pre>[::application::ai::escape $prep]</pre>"
	# the model's brief goes between the two (OnNarrate), so keep the parts
	set Page [dict create head $head facts $facts]
	Report $parent $head$facts

	if {$prose && [llength [info commands ::ai::provider::completeAsync]]} {
		Narrate $parent $opponent $prep $stance $advice $Page
	} elseif {[llength $done]} {
		catch { {*}$done [dict create ok 1 opponent $opponent stance $stance source $source] }
	}
	return
}


proc ::ai::brief::Narrate {parent opponent prep stance advice {page {}}} {
	set prompt "Preparation facts about $opponent, read from the database:\n\n$prep\n\n\
		The stance chosen for the game: $advice\n\n\
		Write a short brief for the player: what $opponent likes to play, where they are \
		weak, what to prepare, and how the stance applies. Restate the numbers from the \
		facts; invent nothing, and do not name a move or a game that is not in them."
	configureProvider
	::ai::provider::completeAsync $prompt [namespace code [list OnNarrate $parent $opponent $page]] \
		-system "You write short chess preparation briefs. Every number, opening and game you \
			mention must come from the preparation facts you were given."
	return
}


proc ::ai::brief::OnNarrate {parent opponent page result} {
	variable mc

	set head ""
	set facts ""
	if {[llength $page]} {
		set head [dict get $page head]
		set facts [dict get $page facts]
	}

	if {![dict get $result ok]} {
		# say so instead of leaving the facts page as if nothing was asked
		set why [expr {[dict exists $result error] ? [dict get $result error] : "no answer"}]
		Report $parent "$head<p><i>[::application::ai::escape [format $mc::NoBrief $why]]</i></p>$facts"
		return
	}
	set text [string trim [dict get $result text]]
	if {![string length $text]} {
		Report $parent "$head<p><i>[::application::ai::escape [format $mc::NoBrief "empty answer"]]</i></p>$facts"
		return
	}
	Report $parent "$head<p><b>Brief</b></p><p>[::application::ai::escape $text]</p>$facts"
	return
}


# The model is the one chosen in Extras > AI: Choose Model, as in the trend,
# annotation and study-plan pipelines; without this a brief run before any
# other AI feature went to an unconfigured provider ("Missing host part").
proc ::ai::brief::configureProvider {} {
	if {[info exists ::application::ai::Config(provider)]} {
		catch {
			::ai::provider::configure -name $::application::ai::Config(provider) \
				-model $::application::ai::Config(model) -timeout 300000 \
				-options [list num_predict 400]
		}
	}
	return
}


proc ::ai::brief::Report {parent html} {
	if {[llength [info commands ::application::ai::showReport]]} {
		catch { ::application::ai::showReport $parent "AI: opponent brief" \
			[::application::ai::htmlData $html] }
	}
	return
}


# A small prompt for the menu entry: the name, then the brief.
proc ::ai::brief::ask {parent} {
	variable mc

	set dlg $parent.__briefask__
	if {[winfo exists $dlg]} { destroy $dlg }
	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	ttk::label $dlg.label -text "Opponent name or part of it:"
	ttk::entry $dlg.name
	ttk::frame $dlg.buttons
	ttk::button $dlg.buttons.ok -text "Brief" -command [namespace code [list OnAsk $parent $dlg]]
	ttk::button $dlg.buttons.cancel -text "Cancel" -command [list destroy $dlg]
	pack $dlg.buttons.ok -side right -padx 2
	pack $dlg.buttons.cancel -side right -padx 2
	pack $dlg.label -anchor w -padx 8 -pady {8 2}
	pack $dlg.name -fill x -padx 8
	pack $dlg.buttons -fill x -pady 8
	bind $dlg.name <Return> [namespace code [list OnAsk $parent $dlg]]
	focus $dlg.name
	return $dlg
}


proc ::ai::brief::OnAsk {parent dlg} {
	set name [string trim [$dlg.name get]]
	if {![string length $name]} { return }
	destroy $dlg
	build $parent $name
	return
}

# vi:set ts=3 sw=3:
