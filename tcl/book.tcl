# ======================================================================
# ::book -- the opening book editor (polyglot).
#
# The Tools menu's "Opening Book Editor..." opens a window that shows the
# moves of the open polyglot book at the current board position, with
# their weights and their share of the position's total weight:
#
#   book moves can be added (typed as SAN, or the move just played in the
#   game), deleted, and reweighted; Save writes the book back to its
#   file. "Create Book from Database..." walks the games of the open
#   database (all of them, or the current view), takes the first N plies
#   of each game, drops moves that were played in too few games, and
#   writes the aggregated book with ::scidb::book::write.
#
# The book itself is read and written in C++ (src/app/app_polyglot_book.cpp,
# the standard polyglot format: the reader's Zobrist keys, 16-byte
# entries key/move/weight/learn sorted by key). The commands live in
# ::scidb::book::*:
#
#   open, close, probe, add, remove, reweight, save, count, modified,
#   readonly, write
#
# The editor follows the board position: ::application::board::update
# calls ::book::positionChanged.
#
# Pure helpers (sharePercent, weightFromCounts, entriesFromGames,
# gameNumbers) are covered by tests/test_app_book.tcl.
# ======================================================================

::util::source book

package require Tcl 8.5
package require Tk 8.5

namespace eval ::book {
namespace eval mc {

set Title				"Opening Book Editor"
set Book				"Book:"
set Open				"Open Book..."
set New					"New Book..."
set Save				"Save"
set Close				"Close"
set Moves				"Moves at the current position"
set Move				"Move:"
set Add					"Add Move"
set AddLast				"Add the Move Just Played"
set Delete				"Delete Move"
set Weight				"Weight:"
set SetWeight			"Set Weight"
set Create				"Create Book from Database..."
set Share				"Share"
set Entries				"%d entr%s"
set ModifiedSuffix		" (unsaved edits)"
set NoBook				"no book open"
set NoPosition			"no position (open a game)"
set Readonly			"the book is read only"
set Saved				"saved %d entr%s"
set NoMove				"enter a move (SAN)"
set MoveAdded			"%s added with weight %d"
set MoveDeleted			"%s deleted"
set WeightSet			"weight of %s set to %d"
set NoSuchMove			"%s is not in the book"
set FileType			"Polyglot books"

set CreateTitle			"Create Book from Database"
set BookFile			"Book file:"
set Choose				"Choose..."
set Games				"Games:"
set AllGames			"All games of the database"
set CurrentView			"The current view (tree filter)"
set MaxPlies			"Plies:"
set MinGames			"Min. games per move:"
set WeightSource		"Weight from:"
set WeightFrequency		"Move frequency"
set WeightScore			"Score (wins + half the draws)"
set CreateBtn			"Create"
set Cancel				"Cancel"
set NoDatabase			"no database open"
set NoFile				"choose a book file"
set Created				"%d entr%s from %d game(s) written to %s"

set Plural				"ies"
set Singular			"y"

} ;# namespace mc

array set Options {
	file	""
}

array set Priv {
	dialog			{}
	handle			{}
	file			{}
	fen				{}
	addMove			{}
	weight			1
	selected		{}
	tree			{}
	status			{}
}

variable Slot 33		;# the private game slot the book creation reads with

} ;# namespace book


proc ::book::EntriesText {count} {
	variable mc

	return [format $mc::Entries $count [expr {$count == 1 ? $mc::Singular : $mc::Plural}]]
}


# ----------------------------------------------------------------------
# The editor window.
# ----------------------------------------------------------------------

proc ::book::openEditor {parent} {
	variable Priv
	variable mc
	variable Options

	set dlg $parent.__book__
	if {[winfo exists $dlg]} {
		::widget::dialogRaise $dlg
		return $dlg
	}

	set Priv(dialog) $dlg
	set Priv(fen) ""
	set Priv(selected) {}

	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm protocol $dlg WM_DELETE_WINDOW [namespace code Close]
	bind $dlg <Escape> [namespace code Close]

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	### the book file ################################################
	set file [ttk::frame $top.file]
	ttk::label $file.label -text $mc::Book
	ttk::entry $file.name -state readonly -textvariable [namespace current]::Priv(file)
	ttk::button $file.open -text $mc::Open -command [namespace code OpenBook]
	ttk::button $file.new -text $mc::New -command [namespace code NewBook]
	ttk::button $file.save -text $mc::Save -command [namespace code Save]
	pack $file.label -side left
	pack $file.name -side left -fill x -expand yes -padx [list $::theme::padx 0]
	pack $file.open -side left -padx [list 0 $::theme::padx]
	pack $file.new -side left
	pack $file.save -side left -padx [list $::theme::padx 0]
	pack $file -fill x -pady [list 0 $::theme::pady]

	### the moves of the position ####################################
	ttk::labelframe $top.moves -text " $mc::Moves " -padding $::theme::padx

	set list [ttk::frame $top.moves.list]
	set tree [ttk::treeview $list.tree \
					-columns {move weight share} \
					-show headings \
					-selectmode browse \
					-height 8 \
					]
	$tree heading move -text $mc::Move -anchor w
	$tree heading weight -text $mc::Weight -anchor e
	$tree heading share -text $mc::Share -anchor e
	$tree column move -width 140 -stretch yes
	$tree column weight -width 80 -stretch no -anchor e
	$tree column share -width 80 -stretch no -anchor e
	ttk::scrollbar $list.vs -orient vertical -command [list $tree yview]
	$tree configure -yscrollcommand [list $list.vs set]
	pack $list.vs -side right -fill y
	pack $tree -side left -fill both -expand yes
	pack $list -fill both -expand yes

	set edits [ttk::frame $top.moves.edits]
	ttk::label $edits.moveLabel -text $mc::Move
	ttk::entry $edits.move -width 8 -textvariable [namespace current]::Priv(addMove)
	ttk::button $edits.add -text $mc::Add -command [namespace code AddMove]
	ttk::button $edits.addLast -text $mc::AddLast -command [namespace code AddLastMove]
	ttk::button $edits.delete -text $mc::Delete -state disabled -command [namespace code DeleteMove]
	ttk::label $edits.weightLabel -text $mc::Weight
	ttk::spinbox $edits.weight -from 0 -to 65535 -width 6 \
		-textvariable [namespace current]::Priv(weight)
	ttk::button $edits.setWeight -text $mc::SetWeight -state disabled \
		-command [namespace code SetWeight]
	grid $edits.moveLabel $edits.move $edits.add $edits.addLast -sticky w -padx [list 0 $::theme::padx]
	grid $edits.delete - - - -sticky w -padx [list 0 $::theme::padx] -pady [list $::theme::pady 0]
	grid $edits.weightLabel $edits.weight $edits.setWeight - -sticky w -padx [list 0 $::theme::padx]
	grid columnconfigure $edits 3 -weight 1
	pack $edits -fill x -pady [list $::theme::pady 0]

	pack $top.moves -fill both -expand yes

	### create + status ##############################################
	set actions [ttk::frame $top.actions]
	ttk::button $actions.create -text $mc::Create \
		-command [namespace code [list CreateDialog $dlg]]
	pack $actions.create -side left
	pack $actions -fill x -pady [list $::theme::pady 0]
	ttk::label $top.status -wraplength 420 -justify left
	pack $top.status -fill x

	::widget::dialogButtons $dlg {close}
	$dlg.close configure -text $mc::Close -command [namespace code Close]

	set Priv(tree) $tree
	set Priv(status) $top.status
	set Priv(deleteButton) $edits.delete
	set Priv(setWeightButton) $edits.setWeight
	set Priv(moveEntry) $edits.move

	# only now that the buttons exist can selection changes update them
	bind $tree <<TreeviewSelect>> [namespace code SelectionChanged]

	# the last book again, when it is still there
	if {$Priv(handle) ne ""} {
		set Priv(file) $Options(file)
	} elseif {$Options(file) ne "" && [file readable $Options(file)]} {
		OpenHandle $Options(file)
	} else {
		set Options(file) ""
	}

	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	Refresh

	return $dlg
}


proc ::book::Close {} {
	variable Priv

	if {$Priv(dialog) ne "" && [winfo exists $Priv(dialog)]} {
		destroy $Priv(dialog)
	}
	set Priv(dialog) {}
	if {$Priv(handle) ne ""} {
		catch { ::scidb::book::close $Priv(handle) }
		set Priv(handle) {}
	}
}


# The board position changed (from ::application::board::update).
proc ::book::positionChanged {} {
	variable Priv

	if {$Priv(dialog) ne "" && [winfo exists $Priv(dialog)]} {
		Refresh
	}
}


# ----------------------------------------------------------------------
# Opening, creating and saving books.
# ----------------------------------------------------------------------

proc ::book::OpenBook {} {
	variable Priv
	variable mc

	set result [::dialog::openFile \
		-parent $Priv(dialog) \
		-class book \
		-filetypes [list [list $mc::FileType {.bin} {.BIN}]] \
		-defaultextension .bin \
		-geometry last \
		-title $mc::Open \
		]
	if {[llength $result] == 0} { return }
	OpenHandle [lindex $result 0]
}


proc ::book::NewBook {} {
	variable Priv
	variable mc

	set result [::dialog::saveFile \
		-parent $Priv(dialog) \
		-class book \
		-filetypes [list [list $mc::FileType {.bin} {.BIN}]] \
		-defaultextension .bin \
		-geometry last \
		-title $mc::New \
		]
	if {[llength $result] == 0} { return }
	set file [lindex $result 0]
	if {[catch { ::scidb::book::write $file {} } msg]} {
		Status $msg
		return
	}
	OpenHandle $file
}


proc ::book::OpenHandle {file} {
	variable Priv
	variable Options

	if {[catch { set handle [::scidb::book::open $file] } msg]} {
		Status $msg
		return
	}
	if {$Priv(handle) ne ""} {
		catch { ::scidb::book::close $Priv(handle) }
	}
	set Priv(handle) $handle
	set Options(file) $file
	set Priv(file) [file normalize $file]
	Refresh
}


proc ::book::Save {} {
	variable Priv
	variable mc

	if {$Priv(handle) eq ""} {
		Status $mc::NoBook
		return
	}
	if {![::scidb::book::save $Priv(handle)]} {
		Status $mc::Readonly
		return
	}
	set entries [::scidb::book::count $Priv(handle)]
	Status [format $mc::Saved $entries [expr {$entries == 1 ? $mc::Singular : $mc::Plural}]]
	Refresh
}


# ----------------------------------------------------------------------
# The moves of the current position.
# ----------------------------------------------------------------------

# The position to look up: the current board position of a game of the
# Normal variant, "" when there is none.
proc ::book::Fen {} {
	if {[catch { ::scidb::game::query variant? } variant] == 0 && $variant ni {Normal {}}} {
		return ""
	}
	if {[catch { ::scidb::pos::fen } fen]} { return "" }
	return $fen
}


proc ::book::Refresh {} {
	variable Priv
	variable mc

	if {$Priv(dialog) eq "" || ![winfo exists $Priv(dialog)]} { return }
	set tree $Priv(tree)
	$tree delete [$tree children {}]
	set Priv(selected) {}
	$Priv(deleteButton) state disabled
	$Priv(setWeightButton) state disabled

	set fen [Fen]
	set Priv(fen) $fen

	if {$fen eq ""} {
		Status $mc::NoPosition
		return
	}
	if {$Priv(handle) eq ""} {
		Status $mc::NoBook
		return
	}

	set total 0
	foreach move [::scidb::book::probe $Priv(handle) $fen] {
		# each move is {san <S> uci <U> weight <W> learn <L>}
		set san [dict get $move san]
		set weight [dict get $move weight]
		incr total $weight
		$tree insert {} end -id $san -values [list $san $weight 0]
	}
	foreach id [$tree children {}] {
		set weight [$tree set $id weight]
		$tree set $id share [sharePercent $weight $total]
	}

	set entries [::scidb::book::count $Priv(handle)]
	set text [EntriesText $entries]
	if {[::scidb::book::modified $Priv(handle)]} {
		append text $mc::ModifiedSuffix
	}
	Status $text
}


proc ::book::SelectionChanged {} {
	variable Priv

	set selection [$Priv(tree) selection]
	if {[llength $selection]} {
		set Priv(selected) [lindex $selection 0]
		$Priv(deleteButton) state !disabled
		$Priv(setWeightButton) state !disabled
	} else {
		set Priv(selected) {}
		$Priv(deleteButton) state disabled
		$Priv(setWeightButton) state disabled
	}
}


# A typed SAN move at the current position.
proc ::book::AddMove {} {
	variable Priv
	variable mc

	if {$Priv(handle) eq ""} {
		Status $mc::NoBook
		return
	}
	set fen [Fen]
	if {$fen eq ""} {
		Status $mc::NoPosition
		return
	}
	set san [string trim $Priv(addMove)]
	if {$san eq ""} {
		Status $mc::NoMove
		return
	}
	if {[catch { ::scidb::book::add $Priv(handle) $fen $san $Priv(weight) } msg]} {
		Status $msg
		return
	}
	Status [format $mc::MoveAdded $san $Priv(weight)]
	set Priv(addMove) ""
	Refresh
}


# The move that led to the current position, at the position it was
# played from; it books the last move of the game, also in variations.
proc ::book::AddLastMove {} {
	variable Priv
	variable mc

	if {$Priv(handle) eq ""} {
		Status $mc::NoBook
		return
	}
	set last [LastMove]
	if {[llength $last] == 0} {
		Status $mc::NoMove
		return
	}
	lassign $last san fen
	if {[catch { ::scidb::book::add $Priv(handle) $fen $san $Priv(weight) } msg]} {
		Status $msg
		return
	}
	Status [format $mc::MoveAdded $san $Priv(weight)]
	Refresh
}


proc ::book::LastMove {} {
	if {[catch { set key [::scidb::game::query current?] }] || [string length $key] == 0} {
		return {}
	}
	if {[catch { set san [::scidb::game::query move $key] }]} { return {} }
	if {[string length $san] == 0} { return {} }
	if {[catch { set fen [::scidb::game::query movefen $key] }]} { return {} }
	if {[string length $fen] == 0} { return {} }
	return [list $san $fen]
}


proc ::book::DeleteMove {} {
	variable Priv
	variable mc

	if {$Priv(handle) eq ""} {
		Status $mc::NoBook
		return
	}
	if {$Priv(selected) eq ""} { return }
	if {![::scidb::book::remove $Priv(handle) $Priv(fen) $Priv(selected)]} {
		Status [format $mc::NoSuchMove $Priv(selected)]
		return
	}
	Status [format $mc::MoveDeleted $Priv(selected)]
	Refresh
}


proc ::book::SetWeight {} {
	variable Priv
	variable mc

	if {$Priv(handle) eq ""} {
		Status $mc::NoBook
		return
	}
	if {$Priv(selected) eq ""} { return }
	if {![::scidb::book::reweight $Priv(handle) $Priv(fen) $Priv(selected) $Priv(weight)]} {
		Status [format $mc::NoSuchMove $Priv(selected)]
		return
	}
	Status [format $mc::WeightSet $Priv(selected) $Priv(weight)]
	Refresh
}


proc ::book::Status {text} {
	variable Priv

	if {$Priv(dialog) ne "" && [winfo exists $Priv(dialog)]} {
		$Priv(status) configure -text $text
	}
}


# ----------------------------------------------------------------------
# "Create Book from Database..."
# ----------------------------------------------------------------------

proc ::book::CreateDialog {parent} {
	variable Priv
	variable mc

	set dlg $parent.__bookCreate__
	if {[winfo exists $dlg]} {
		raise $dlg
		return $dlg
	}

	if {[catch { set base [::scidb::db::get name] }]} { set base "" }
	if {$base eq ""} {
		::dialog::error -parent $parent -message $mc::NoDatabase
		return
	}
	set variant [::scidb::app::variant]

	toplevel $dlg -class Scidb
	wm title $dlg $mc::CreateTitle
	wm transient $dlg [winfo toplevel $parent]
	wm protocol $dlg WM_DELETE_WINDOW [namespace code [list CreateClose $dlg]]
	bind $dlg <Escape> [namespace code [list CreateClose $dlg]]

	namespace eval [namespace current]::${dlg} {}
	variable ${dlg}::Vars
	set Vars(base) $base
	set Vars(variant) $variant
	set Vars(file) [file rootname $base].bin
	set Vars(games) all
	set Vars(plies) 20
	set Vars(minGames) 1
	set Vars(weightMode) frequency
	set Vars(haveView) [expr {[::scidb::tree::view] >= 0}]

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	set file [ttk::frame $top.file]
	ttk::label $file.label -text $mc::BookFile
	ttk::entry $file.name -textvariable [namespace current]::${dlg}::Vars(file)
	ttk::button $file.choose -text $mc::Choose -command [namespace code [list CreateChooseFile $dlg]]
	pack $file.label -side left
	pack $file.name -side left -fill x -expand yes -padx [list $::theme::padx 0]
	pack $file.choose -side left
	pack $file -fill x -pady [list 0 $::theme::pady]

	set games [ttk::labelframe $top.games -text " $mc::Games " -padding $::theme::padx]
	ttk::radiobutton $games.all \
		-text $mc::AllGames -value all -variable [namespace current]::${dlg}::Vars(games)
	ttk::radiobutton $games.view \
		-text $mc::CurrentView -value view -variable [namespace current]::${dlg}::Vars(games) \
		-state [expr {$Vars(haveView) ? "normal" : "disabled"}]
	pack $games.all -anchor w
	pack $games.view -anchor w
	pack $games -fill x -pady [list 0 $::theme::pady]

	set limits [ttk::frame $top.limits]
	ttk::label $limits.pliesLabel -text $mc::MaxPlies
	ttk::spinbox $limits.plies -from 1 -to 200 -width 4 \
		-textvariable [namespace current]::${dlg}::Vars(plies)
	ttk::label $limits.minGamesLabel -text $mc::MinGames
	ttk::spinbox $limits.minGames -from 1 -to 1000 -width 4 \
		-textvariable [namespace current]::${dlg}::Vars(minGames)
	pack $limits.pliesLabel -side left
	pack $limits.plies -side left -padx [list 0 $::theme::padx]
	pack $limits.minGamesLabel -side left
	pack $limits.minGames -side left
	pack $limits -fill x -pady [list 0 $::theme::pady]

	set weights [ttk::labelframe $top.weights -text " $mc::WeightSource " -padding $::theme::padx]
	ttk::radiobutton $weights.frequency \
		-text $mc::WeightFrequency -value frequency \
		-variable [namespace current]::${dlg}::Vars(weightMode)
	ttk::radiobutton $weights.score \
		-text $mc::WeightScore -value score \
		-variable [namespace current]::${dlg}::Vars(weightMode)
	pack $weights.frequency -anchor w
	pack $weights.score -anchor w
	pack $weights -fill x -pady [list 0 $::theme::pady]

	::widget::dialogButtons $dlg {ok cancel}
	$dlg.ok configure -text $mc::CreateBtn -command [namespace code [list CreateStart $dlg]]
	$dlg.cancel configure -text $mc::Cancel -command [namespace code [list CreateClose $dlg]]

	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	return $dlg
}


proc ::book::CreateChooseFile {dlg} {
	variable ${dlg}::Vars
	variable mc

	set result [::dialog::saveFile \
		-parent $dlg \
		-class book \
		-filetypes [list [list $mc::FileType {.bin} {.BIN}]] \
		-defaultextension .bin \
		-geometry last \
		]
	if {[llength $result]} { set Vars(file) [lindex $result 0] }
}


proc ::book::CreateClose {dlg} {
	destroy $dlg
}


proc ::book::CreateStart {dlg} {
	variable Priv
	variable ${dlg}::Vars
	variable mc

	set file [string trim $Vars(file)]
	if {$file eq ""} {
		::dialog::error -parent $dlg -message $mc::NoFile
		return
	}
	set view ""
	if {$Vars(games) eq "view" && $Vars(haveView)} {
		set view [::scidb::tree::view]
	}

	set numbers [gameNumbers $Vars(base) $Vars(variant) $view]
	set entries [collectEntries $Vars(base) $Vars(variant) $numbers $Vars(plies) $Vars(minGames) $Vars(weightMode)]

	::scidb::book::write $file $entries
	CreateClose $dlg
	if {$Priv(dialog) ne "" && [winfo exists $Priv(dialog)]} {
		OpenHandle $file
		Status [format $mc::Created [llength $entries] [expr {[llength $entries] == 1 ? $mc::Singular : $mc::Plural}] [llength $numbers] $file]
	}
	return
}


# ----------------------------------------------------------------------
# Pure helpers (the book creation).
# ----------------------------------------------------------------------

# The game numbers to read: all of the database, or the rows of a view.
proc ::book::gameNumbers {base variant view} {
	set numbers {}
	if {$view eq ""} {
		set count [::scidb::db::count games $base $variant]
		for {set number 0} {$number < $count} {incr number} {
			lappend numbers $number
		}
	} else {
		set count [::scidb::view::count games $base $variant $view]
		for {set row 0} {$row < $count} {incr row} {
			lappend numbers [::scidb::db::get gameNumber $base $variant $row $view]
		}
	}
	return $numbers
}


# The book entries of the games: {fen san weight learn} groups, one per
# position and move, the moves of fewer than <minGames> games dropped.
proc ::book::collectEntries {base variant numbers plies minGames weightMode} {
	variable Slot

	# position -> move -> {count wins draws}
	set table [dict create]

	if {[llength $numbers] == 0} { return {} }
	if {[::scidb::game::query $Slot open?]} { error "book creation: reader slot in use" }

	set code [catch {
		::scidb::game::new $Slot
		foreach number $numbers {
			if {[catch { ::scidb::game::load $Slot $base $variant $number }]} { continue }
			set result [GameResult $base $variant $number]
			set line [::scidb::game::query $Slot mainline]
			set ply 0
			foreach entry $line {
				if {$ply >= $plies} { break }
				lassign $entry key san fenBefore
				set score [MoveScore $result [SideToMove $fenBefore]]
				if {![dict exists $table $fenBefore $san]} {
					dict set table $fenBefore $san {0 0 0}
				}
				lassign [dict get $table $fenBefore $san] count wins draws
				incr count
				if {$score eq "win"} {
					incr wins
				} elseif {$score eq "draw"} {
					incr draws
				}
				dict set table $fenBefore $san [list $count $wins $draws]
				incr ply
			}
		}
	} msg opts]
	catch { ::scidb::game::release $Slot }
	if {$code} { return -options $opts $msg }

	return [entriesFromGames $table $minGames $weightMode]
}


# The book entries of an aggregation table position -> move -> {count
# wins draws}: the moves of fewer than <minGames> games are dropped.
proc ::book::entriesFromGames {table minGames weightMode} {
	set entries {}
	dict for {fen moves} $table {
		dict for {san counts} $moves {
			lassign $counts count wins draws
			if {$count < $minGames} { continue }
			lappend entries [list $fen $san [weightFromCounts $count $wins $draws $weightMode] 0]
		}
	}
	return $entries
}


# The game result: 1-0, 0-1, 1/2-1/2 or "".
proc ::book::GameResult {base variant number} {
	foreach pair [::scidb::db::get tags $number $base $variant] {
		lassign $pair tag value
		if {$tag eq "Result"} { return $value }
	}
	return ""
}


# What the move meant for the mover: win, loss, draw or "".
proc ::book::MoveScore {result stm} {
	switch -- $result {
		1-0		{ return [expr {$stm eq "w" ? "win" : "loss"}] }
		0-1		{ return [expr {$stm eq "b" ? "win" : "loss"}] }
		1/2-1/2	{ return "draw" }
	}
	return ""
}


# The side to move of a FEN ("w" or "b").
proc ::book::SideToMove {fen} {
	return [expr {[lindex $fen 1] eq "b" ? "b" : "w"}]
}


# The share of a weight of the total, as a percentage text ("37%").
proc ::book::sharePercent {weight total} {
	if {$total <= 0} { return "0%" }
	return [format %.0f%% [expr {100.0*$weight/$total}]]
}


# The weight of a move out of its counts, per the chosen mode: the
# frequency (how often it was played), or the score it scored (wins plus
# half the draws, rounded). At least 1, at most 65535 (the polyglot limit).
proc ::book::weightFromCounts {count wins draws mode} {
	if {$mode eq "score"} {
		set weight [expr {round((2.0*$wins + $draws)/2.0)}]
	} else {
		set weight $count
	}
	if {$weight < 1} { set weight 1 }
	if {$weight > 65535} { set weight 65535 }
	return $weight
}


proc ::book::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter ::book::WriteOptions

# vi:set ts=3 sw=3:
