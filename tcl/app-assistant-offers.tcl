# ======================================================================
# ::application::assistant::offers -- the assistant offers what fits the
# moment (ASSISTANT_COVERAGE_MAP.md P3, phase 4).
#
# A player who does not know what Scidb can do will not ask for it. At
# natural moments -- a database becomes active, a game is loaded -- a row
# of at most three buttons in the assistant pane offers the next steps;
# a click asks the assistant, as if the request were typed. The offers
# come from rules, never from a model, and they never act by themselves.
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
set AskAbout		"Ask about this..."
set AskAboutGame	"About game #%d (%s): "
set AskAboutBoard	"About the position on the board: "

} ;# namespace mc

# {label request ...}; a request ending in "..." is put into the entry for
# the user to finish instead of being sent.
variable Offers {}
variable Frame {}

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
	set Offers $offers
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
	put [list \
		$mc::Summary		"What is in the active database? A short summary, please." \
		$mc::FindPositions	"Find positions where ..." \
		$mc::Duplicates		"Open the duplicate search for the active database."]
}


proc ::application::assistant::offers::GameSwitched {args} {
	variable mc

	set white ""; set black ""
	catch {
		set position [expr {[llength $args] ? [lindex $args end] : [::scidb::game::current]}]
		foreach pair [::scidb::game::tags $position] {
			switch -- [lindex $pair 0] {
				White { set white [lindex $pair 1] }
				Black { set black [lindex $pair 1] }
			}
		}
	}
	if {[Mine $white] || [Mine $black]} {
		put [list \
			$mc::Review		"Annotate the game on the board with the engine." \
			$mc::WentWrong	"Where did I go wrong in the game on the board? Use the engine." \
			$mc::GamesLike	"Find games like the one on the board."]
	} else {
		put [list \
			$mc::Explain		"Explain the position on the board." \
			$mc::SamePosition	"Find games in the active database that reach the position on the board (the same pieces on the same squares)." \
			$mc::PositionsLike	"Find positions like the one on the board, with the same pawn structure."]
	}
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
