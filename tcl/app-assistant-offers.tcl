# ======================================================================
# ::application::assistant::offers -- the assistant offers what fits the
# moment (docs/ASSISTANT_COVERAGE_MAP.md P3, phase 4).
#
# A player who does not know what Scidb can do will not ask for it. At
# natural moments -- a database becomes active, a game is loaded -- a row
# of at most three buttons in the assistant pane offers the next steps;
# a click asks the assistant, as if the request were typed. Rules make a
# pool of offers that fit the moment, in their own order; when a System
# One classifier is running it judges each offer against what is on
# screen and the three likeliest are shown. Offers never act by
# themselves, so a classifier's misjudgement costs only a button.
#
# Ways in (C8): F2 opens the assistant pane with the entry focused, and
# "Ask about this..." in the game list's and the board's context menus
# opens it with the entry filled in for the user to finish.
#
#   ::application::assistant::offers::attach <pane>
#   ::application::assistant::offers::put <offers>     {label request ...}
#   ::application::assistant::offers::askAbout <text>  open, prefill
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-assistant-offers
}

namespace eval application {
namespace eval assistant {
namespace eval offers {
namespace eval mc {

set Summary			"What's in this database?"
set FindPositions	"Find positions..."
set Duplicates		"Duplicates?"
set Review			"Review my game"
set WentWrong		"Where did I go wrong?"
set GamesLike		"Games like this"
set Explain			"Explain the position"
set SamePosition	"Games with this position"
set PositionsLike	"Positions like this"
set Compact			"Compact it"
set Trend			"Opening trends"
set Maintenance		"Maintenance report"
set Annotate		"Annotate this game"
set OpeningReport	"Opening report"
set Lesson			"Video lesson"
set AskAbout		"Ask about this..."
set AskAboutGame	"About game #%d (%s): "
set AskAboutBoard	"About the position on the board: "

} ;# namespace mc

# {label request ...}; a request ending in "..." is put into the entry for
# the user to finish instead of being sent.
variable Offers {}
variable Frame {}
variable Shown 3
# a ranking that arrives later than this keeps the rules' order: the
# buttons must not change under the user's mouse
variable RankTimeout 6000
variable RankGen 0

} ;# namespace offers
} ;# namespace assistant
} ;# namespace application


proc ::application::assistant::offers::attach {pane} {
	variable Frame

	set Frame [ttk::frame $pane.offers]
	pack $Frame -side bottom -fill x -before $pane.bottom
	Render
}


proc ::application::assistant::offers::put {offers} {
	variable Offers
	variable RankGen
	incr RankGen ;# a ranking still on its way is for an older moment
	set Offers $offers
	Render
}


# Show the first offers of <pool> ({label request ...}, the rules' order),
# then let the classifier, if one is running, reorder them for <state>.
proc ::application::assistant::offers::offer {pool state} {
	variable Shown
	variable RankGen
	variable RankTimeout

	put [lrange $pool 0 [expr {2 * $Shown - 1}]]
	if {[llength $pool] <= 2 * $Shown} { return }
	if {[llength [info commands ::ai::systemone::enabled]] == 0 || ![::ai::systemone::enabled]} { return }

	set questions {}
	set i 0
	foreach {label request} $pool {
		dict set questions o[incr i] [dict create type noul instructions \
			"The user of Chesswiz, a chess database program, has just opened what the state describes. Is this the next thing they are likely to want: \"$request\"?"]
	}
	set gen $RankGen
	set deadline [expr {[clock milliseconds] + $RankTimeout}]
	if {[catch {
		::ai::systemone::evaluateAsync $state $questions \
			[namespace code [list Ranked $gen $deadline $pool]]
	}]} { return }
}


proc ::application::assistant::offers::Ranked {gen deadline pool result} {
	variable RankGen
	variable Shown

	if {$gen != $RankGen || [clock milliseconds] > $deadline} { return }
	if {![dict get $result ok]} { return }
	set scored {}
	set i 0
	foreach {label request} $pool {
		set p 0.0
		catch { set p [dict get $result answers o[incr i] noul] }
		if {![string is double -strict $p]} { set p 0.0 }
		lappend scored [list $p $label $request]
	}
	set best {}
	foreach row [lrange [lsort -real -decreasing -index 0 $scored] 0 [expr {$Shown - 1}]] {
		lappend best [lindex $row 1] [lindex $row 2]
	}
	variable Offers
	set Offers $best
	Render
}


proc ::application::assistant::offers::Render {} {
	variable Offers
	variable Frame

	if {$Frame eq "" || ![winfo exists $Frame]} { return }
	foreach w [winfo children $Frame] { destroy $w }
	set i 0
	foreach {label request} $Offers {
		ttk::button $Frame.o[incr i] -text $label -style Toolbutton \
			-command [namespace code [list Take $request]]
		pack $Frame.o$i -side left -padx {4 0} -pady {2 0}
	}
}


proc ::application::assistant::offers::Take {request} {
	if {[string match "*..." $request]} {
		askAbout [string range $request 0 end-3]
		return
	}
	::application::assistant::show
	if {![::application::ai::cloudReady .application]} { return }
	::application::assistant::ask $request
}


# Open the pane with <text> in the entry, the cursor at its end.
proc ::application::assistant::offers::askAbout {text} {
	variable ::application::assistant::Priv

	::application::assistant::show
	if {![winfo exists $Priv(entry)]} { return }
	$Priv(entry) delete 0 end
	$Priv(entry) insert 0 $text
	$Priv(entry) icursor end
	focus $Priv(entry)
}


# --- the rules -------------------------------------------------------------

proc ::application::assistant::offers::DatabaseSwitched {base variant} {
	variable mc
	if {[catch { ::scidb::db::count games $base $variant } count] || $count == 0} {
		put {}
		return
	}
	set deleted 0
	catch { set deleted [lindex [::scidb::db::get stats $base] 0] }
	set pool [list \
		$mc::Summary		"What is in the active database? A short summary, please." \
		$mc::FindPositions	"Find positions where ..." \
		$mc::Duplicates		"Open the duplicate search for the active database." \
		$mc::Trend			"What is trending in the openings of the active database?" \
		$mc::Maintenance	"Show the maintenance report of the active database."]
	if {$deleted > 0} {
		lappend pool $mc::Compact "Compact the active database."
	}
	offer $pool [format "database: %s\ngames: %d\ndeleted games: %d" \
		[::util::databaseName $base no] $count $deleted]
}


proc ::application::assistant::offers::GameSwitched {args} {
	variable mc

	set white ""; set black ""; set eco ""; set result ""; set fen ""
	catch { set fen [::scidb::pos::fen] }
	catch {
		set position [expr {[llength $args] ? [lindex $args end] : [::scidb::game::current]}]
		foreach pair [::scidb::game::tags $position] {
			switch -- [lindex $pair 0] {
				White { set white [lindex $pair 1] }
				Black { set black [lindex $pair 1] }
				ECO { set eco [lindex $pair 1] }
				Result { set result [lindex $pair 1] }
			}
		}
	}
	set mine [expr {[Mine $white] || [Mine $black]}]
	if {$mine} {
		set pool [list \
			$mc::Review		"Annotate the game on the board with the engine." \
			$mc::WentWrong	"Where did I go wrong in the game on the board? Use the engine." \
			$mc::GamesLike	"Find games like the one on the board." \
			$mc::Explain		"Explain the position on the board." \
			$mc::OpeningReport	"Show the opening report for the position on the board."]
	} else {
		set pool [list \
			$mc::Explain		"Explain the position on the board." \
			$mc::SamePosition	"Find games in the active database that reach the position on the board (the same pieces on the same squares)." \
			$mc::PositionsLike	"Find positions like the one on the board, with the same pawn structure." \
			$mc::Annotate	"Annotate the game on the board with the engine." \
			$mc::GamesLike	"Find games like the one on the board." \
			$mc::OpeningReport	"Show the opening report for the position on the board."]
	}
	if {[HasLesson]} {
		lappend pool $mc::Lesson "Is there a video lesson for the position on the board? Play it."
	}
	offer $pool [format "game: %s - %s, %s, %s\nthe user's own game: %s\nposition: %s" \
		$white $black $eco $result [expr {$mine ? "yes" : "no"}] $fen]
}


# Whether a video lesson covers the board's position.
proc ::application::assistant::offers::HasLesson {} {
	if {[catch {
		set key [::application::media::FenKey [::scidb::pos::fen]]
		set hit 0
		foreach e [::application::assistant::LessonEntries] {
			if {[::application::media::FenKey [lindex $e 0]] eq $key} { set hit 1; break }
		}
	}]} { return 0 }
	return $hit
}


# Whether a header name is the user's (the name remembered by remember_me;
# compared by surname, as databases write names differently).
proc ::application::assistant::offers::Mine {name} {
	set me ""
	catch { set me [string trim $::application::ai::Settings(me)] }
	if {$me eq "" || $name eq ""} { return 0 }
	set surname [string trim [lindex [split $me ,] 0]]
	if {[llength [split $me ,]] == 1} { set surname [lindex $me end] }
	return [string match -nocase "*$surname*" $name]
}


# --- ways in --------------------------------------------------------------

# "Ask about this..." for game <index> of the game list <path>'s view.
proc ::application::assistant::offers::AskAboutGame {base variant number} {
	variable mc
	set line [::application::assistant::GameLine $number $base $variant]
	askAbout [format $mc::AskAboutGame [expr {$number + 1}] $line]
}


proc ::application::assistant::offers::AskAboutBoard {} {
	variable mc
	askAbout $mc::AskAboutBoard
}


# F2 anywhere: the assistant, ready for a request
bind all <F2> { ::application::assistant::offers::askAbout "" }

if {[llength [info commands ::scidb::db::subscribe]]} {
	::scidb::db::subscribe gameSwitch ::application::assistant::offers::GameSwitched
	::scidb::db::subscribe databaseSwitch ::application::assistant::offers::DatabaseSwitched
}
