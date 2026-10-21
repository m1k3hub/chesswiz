# ======================================================================
# Author : $Author$
# Version: $Revision: 1526 $
# Date   : $Date: 2018-09-19 09:32:13 -0400 (Wed, 19 Sep 2018) $
# Url    : $URL$
# ======================================================================

# ======================================================================
#    _/|            __
#   // o\         /    )           ,        /    /
#   || ._)    ----\---------__----------__-/----/__-
#   //__\          \      /   '  /    /   /    /   )
#   )___(     _(____/____(___ __/____(___/____(___/_
# ======================================================================

# ======================================================================
# Copyright: (C) 2009-2017 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source move-handling

namespace eval move {
namespace eval mc {

set Action(replace)		"Replace Move"
set Action(variation)	"Add New Variation"
set Action(mainline)		"New Main Line"
set Action(trial)			"Try Variation"
set Action(exchange)		"Exchange Move"
set Action(append)		"Append move"
set Action(load)			"Load first game with this continuation"

set Accel(trial)			"T" ;# should coincide with ::application::board::mc::Accel(trial-mode)
set Accel(replace)		"R"
set Accel(variation)		"V"
set Accel(append)			"A"
set Accel(load)			"L"

set GameWillBeTruncated	"Game will be truncated. Continue with '%s'?"

} ;# namespace mc


array set Square {
	current		-1
	selected		-1
	suggested	-1
	origin		-1
	hilited		-1
	fresh			0
}

array set Drop {
	piece		" "
	takeBack	-1
}

array set Options {
	addVarWithoutAsking	0
	askToReplaceMoves		1
	defaultAction			replace
	searchDepth				3
	figurineSize			24
}

variable Disabled		0
variable Leave			1
variable Lock			0
variable Variation	0


proc translate {san} {
	return $san	;# TODO
}


proc setup {} {
	::scidb::pos::searchDepth [set [namespace current]::Options(searchDepth)]
}


proc enable {args} {
	variable ::application::board::board
	variable Disabled
	variable Lock

	if {$Lock} { return }

	set Disabled 0

	if {[llength $args]} {
		set square [::board::diagram::getSquare $board {*}$args]
	
		if {$square != -1} {
			enterSquare $square
		}
	}
}


proc disable {} {
	variable ::application::board::board
	variable ::board::hilite
	variable Disabled
	variable Square

	::variation::hide
	set Disabled 1

	if {$Square(selected) != -1} {
		::board::diagram::hilite $board $Square(selected) off
	}

	if {$hilite(show-suggested)} {
		::board::diagram::hilite $board $Square(suggested) off
		::board::diagram::hilite $board $Square(current) off
	}

}


proc reset {} {
	variable ::application::board::board
	variable Square
	variable Drop

	::application::board::deselectInHandPiece
	set Drop(piece) " "

	if {$Square(selected) != -1} {
		::board::diagram::hilite $board $Square(selected) off
		set Square(selected) -1
	}

	if {$Square(suggested) != -1} {
		::board::diagram::hilite $board $Square(suggested) off
		set Square(suggested) -1
	}
}


proc nextGuess {args} {
	variable ::application::board::board
	variable ::board::hilite
	variable Square
	variable Drop
	variable Disabled

	::variation::hide

	if {$Disabled} { return }
	if {$Square(current) == -1} { return }
	if {!$hilite(show-suggested)} { return }
	if {$Square(selected) != -1} { return }

	if {$Drop(piece) ne " "} {
		set Drop(piece) " "
		::application::board::deselectInHandPiece
		::board::diagram::hilite $board $Square(origin) off
		set meth guess
	} else {
		set meth guessNext
	}

	if {[llength $args] == 2} {
		set square [::board::diagram::getSquare $board {*}$args]
		if {$square != $Square(current)} { return }
	}

	set suggested [::scidb::pos::$meth $Square(current)]

	if {$suggested != -1} {
		if {$Square(suggested) != -1} {
			::board::diagram::hilite $board $Square(suggested) off
		}
		::board::diagram::hilite $board $suggested suggested
		::board::diagram::hilite $board $Square(current) suggested
		set Square(suggested) $suggested
	}
}


proc enterSquare {{square {}}} {
	variable ::application::board::board
	variable ::board::hilite
	variable Square
	variable Disabled
	variable Drop

	if {$Disabled} { return }

	if {[string length $square]} {
		set Square(current) $square
	} elseif {$Square(current) == -1} {
		return
	} else {
		set square $Square(current)
	}

	set Square(suggested) -1

	if {$Drop(piece) ne " "} {
		if {$hilite(show-suggested) && [::scidb::pos::legal? $square $square no $Drop(piece)]} {
			set Square(origin) $square
			set Square(suggested) $square
			::board::diagram::hilite $board $Square(suggested) suggested
		}
	} elseif {$Square(selected) == -1} {
		set Square(origin) -1

		if {$hilite(show-suggested)} {
			set suggested [::scidb::pos::guess $square]
			if {$suggested != -1} { set Square(origin) $square }
		} else {
			set suggested -1
		}

		if {$suggested != -1} {
			::board::diagram::hilite $board $square suggested
			::board::diagram::hilite $board $suggested suggested
		}

		if {$hilite(show-suggested)} {
			set Square(suggested) $suggested
		}
	} elseif {$hilite(show-suggested)} {
		::board::diagram::hilite $board $Square(selected) selected
		if {$Square(origin) != -1} {
			::board::diagram::hilite $board $Square(origin) suggested
		}
	}
}


proc leaveSquare {{square {}}} {
	variable ::application::board::board
	variable ::board::hilite
	variable Square
	variable Leave

	if {[::board::diagram::isDragged? $board]} { return }

	if {[string length $square] == 0} {
		if {$Square(current) != -1} {
			::board::diagram::hilite $board $Square(current) off
		}
		if {$Square(suggested) != -1} {
			::board::diagram::hilite $board $Square(suggested) off
			set Square(suggested) -1
		}
		set Square(selected) -1
	} elseif {$Leave <= 0} {
		set Leave [expr {-($square + 1)}]
	} else {
		if {$Square(selected) != -1 && $square != $Square(selected)} {
			::board::diagram::hilite $board $square off
		}

		if {$hilite(show-suggested)} {
			::board::diagram::hilite $board $Square(current) off
			::board::diagram::hilite $board $Square(suggested) off
		}

		set Square(current) -1
	}
}


proc pressSquare {square state} {
	variable ::application::board::board
	variable ::board::hilite
	variable Square
	variable Disabled
	variable Lock

	::variation::hide

	catch { ::debuglog::log board "press $square selected=$Square(selected) disabled=$Disabled" }
	# Disabled means Ctrl is held; a Ctrl release delivered to another window
	# (dialog, other program) never reached <<ControlOff>> and left it set.
	if {$Disabled && !$Lock && !($state & 4)} {
		set Disabled 0
	}
	if {$Disabled} { return }

	if {$Square(selected) == -1} {
		set Square(selected) $square
		::board::diagram::hilite $board $square selected

		# Drag this piece if it is the same color as the side to move:
		set c [::scidb::pos::stm]
		set p [string index [::board::diagram::piece $board $square] 0]
		if {$c eq $p} { ::board::diagram::setDragSquare $board $square }
		set Square(fresh) 1
	} elseif {$hilite(show-suggested) && $square ne $Square(selected)} {
		# second click of a click-click move: releaseSquare makes the move
		set Square(fresh) 0
	} elseif {$hilite(show-suggested)} {
		# click on the selected piece: deselect it. A click on a piece never
		# plays the suggested move, only a click on its target square does.
		::board::diagram::setDragSquare $board
		::board::diagram::hilite $board $Square(selected) off
		::board::diagram::hilite $board $Square(suggested) off
		::board::diagram::hilite $board $square off
		set Square(selected) -1
		enterSquare $square
	} elseif {$square eq $Square(selected)} {
		::board::diagram::hilite $board $Square(selected) off
		set Square(selected) -1
	}
}


proc releaseSquare {x y state} {
	variable ::application::board::board
	variable ::board::hilite
	variable Square
	variable Drop
	variable Disabled

	if {$Disabled} { return }

	set suggested $Square(suggested)
	set selected $Square(selected)
	set dragged [::board::diagram::isDragged? $board]
	set square [::board::diagram::getSquare $board $x $y]

	if {$dragged} {
		::board::diagram::finishDrag $board
	}

	::application::board::setCursor

	# The first click on an own piece selects it and keeps it selected: the
	# next click on a target square makes the move (the suggested one included),
	# a click on the piece again deselects it.
	set clickSelect [expr {
		$hilite(show-suggested) && !$dragged && $square == $selected && $square >= 0
		&& $Square(fresh) && $Drop(piece) eq " "
		&& [string index [::board::diagram::piece $board $square] 0] eq [::scidb::pos::stm]
	}]

	set Square(fresh) 0
	catch { ::debuglog::log board "release $square from $selected dragged=$dragged select=$clickSelect" }

	if {$clickSelect} {
		::board::diagram::setDragSquare $board
		return
	}

	if {$hilite(show-suggested) || $square != $Square(selected)} {
		set Square(selected) -1
	}

	if {$square >= 0} {
		set allowIllegalMove [::util::shiftIsHeldDown? $state]

		if {$square == $selected} {
			::board::diagram::setDragSquare $board
			if {$Drop(piece) ne " "} {
				AddMove $square $selected $allowIllegalMove
				::application::board::deselectInHandPiece
				::board::diagram::hilite $board $selected off
				set Drop(piece) " "
			}
			# else current square is the square user pressed the button on, so we do nothing
			# (a click selects or deselects; the suggested move is played by
			# clicking its target square, never by a click on the piece)
		} else {
			# user has dragged to another square, so try to add this as a move
			set Square(current) -1
			::board::diagram::hilite $board $selected off
			::board::diagram::hilite $board $Square(hilited) off
			set piece [::board::diagram::piece $board $square]
			::board::diagram::animate $board 0
			AddMove $square $selected $allowIllegalMove
			::board::diagram::animate $board 1
		}
	}
	
	if {$hilite(show-suggested) && $suggested != $Square(suggested)} {
		::board::diagram::hilite $board $suggested off
	}

	::board::diagram::setDragSquare $board

	if {$Drop(piece) ne " "} {
		::application::board::deselectInHandPiece
		set Drop(piece) " "
	}
}


proc dragPiece {x y state} {
	variable ::application::board::board
	variable ::board::hilite
	variable Square

	if {[::board::diagram::dragSquare $board] == -1} { return }
	set isDragging [::board::diagram::isDragged? $board]
	::board::diagram::dragPiece $board $x $y

	::application::board::setCursor hand2

	if {$hilite(show-suggested)} {
		set from [::board::diagram::dragSquare $board]

		if {!$isDragging} {
			::board::diagram::hilite $board $Square(suggested) off
			::board::diagram::hilite $board $Square(selected) off
			set Square(hilited) -1
		}

		set square [::board::diagram::getSquare $board $x $y]
		if {$square == $Square(hilited)} { return }
		if {$Square(hilited) ne $from} {
			::board::diagram::hilite $board $Square(hilited) off
		}

		set allowIllegalMove [::util::shiftIsHeldDown? $state]

		if {$square != -1 && [::scidb::pos::legal? $from $square $allowIllegalMove]} {
			::board::diagram::hilite $board $square suggested
			::board::diagram::raisePiece $board $from
		}

		set Square(hilited) $square
	}
}


proc addMove {confirmWindowType san args} {
	variable ::application::board::board
	variable Variation

	# While the repertoire trainer waits for the answer, the board is its
	# input device: the move grades the card instead of entering the game.
	if {[llength [info commands ::reptrainer::active]] && [::reptrainer::active]} {
		::reptrainer::answered $san
		return ""
	}

	array set opts {
		-nomovecmd	{}
		-actions		{}
		-force		no
	}
	array set opts $args

	# A Guess-the-Move round scores the played move instead of changing the
	# game; ::guessmove::guessed steps over the game move itself.
	if {[info exists ::guessmove::active] && $::guessmove::active} {
		return [::guessmove::guessed $san]
	}

	if {[::scidb::game::position atEnd?]} {
		::application::pgn::ensureScratchGame
		set action "append"
	} else {
		if {!$opts(-force)} {
			set moves [::scidb::game::next moves -ascii]

			for {set i 0} {$i < [llength $moves]} {incr i} {
				if {[lindex $moves $i] eq $san} {
					::scidb::game::go variation [expr {$i - 1}]
					::application::board::goto 1
					return ""
				}
			}
		}
		::board::diagram::finishDrag $board
		update idletasks
		if {$Variation} {
			set action "variation"
		} else {
			set action [ConfirmReplaceMove $confirmWindowType $opts(-actions)]
		}
	}

	if {![doAction $action $san $opts(-nomovecmd)]} {
		if {$action in $opts(-actions)} { return $action }
		if {[llength $opts(-nomovecmd)]} { eval $opts(-nomovecmd) }
	}

	set Variation 0
	return ""
}


proc doAction {action san {noMoveCmd {}}} {
	switch $action {
		mainline {
			::scidb::game::variation mainline $san
			::scidb::game::go 1
		}

		variation {
			set varno [::scidb::game::variation new $san]
			EnterVariation $varno
		}

		replace {
			::scidb::game::replace $san
			::scidb::game::go 1
		}

		trial {
			::game::flipTrialMode
			::scidb::game::trial $san
			::scidb::game::go 1
		}

		exchange {
			variable ::application::board::board
			doDestructiveCommand \
				$board \
				$mc::Action(exchange) \
				[list ::scidb::game::exchange $san] \
				[list ::scidb::game::go 1] \
				$noMoveCmd \
				;
		}

		append {
			::application::pgn::ensureScratchGame
			::scidb::game::move $san
			::scidb::game::go 1
		}

		default {
			return 0
		}
	}

	# Auto-timestamp correspondence chess moves with ccsnt.
	set tags {}
	catch { set tags [::scidb::game::tags] }
	if {[IsCorrespondenceGame $tags]} {
		set key [::scidb::game::query current]
		set timestamp [clock format [clock seconds] -format {%Y.%m.%d, %H:%M:%S}]
		if {[catch { ::scidb::game::update moveinfo $key ccsnt $timestamp } err]} { puts stderr "move: ccsnt failed: $err" }

		# Auto-submit to ICCF server if configured and game has ICCFGameID
		if {[info commands ::iccf::xfcc::configured?] ne {} && [::iccf::xfcc::configured?]} {
			set iccfId ""
			foreach pair $tags {
				lassign $pair name value
				if {$name eq "ICCFGameID"} { set iccfId $value; break }
			}
			if {[string length $iccfId]} {
				set movecount [::scidb::game::ply]
				if {[catch { ::iccf::xfcc::submitMove $iccfId $san $movecount } err]} { puts stderr "move: ICCF submit failed: $err" }
			}
		}
	}

	return 1
}


proc IsCorrespondenceGame {{tags {}}} {
	if {[llength $tags] == 0} { if {[catch { set tags [::scidb::game::tags] } err]} { puts stderr "move: $err"; return 0 } }
	foreach pair $tags {
		lassign $pair name value
		if {$name eq "TimeMode" && [string tolower $value] eq "corr"} {
			return 1
		}
	}
	return 0
}


proc addActionsToMenu {m command {extraActions {}}} {
	set i 0
	set atEnd [::scidb::game::position atEnd?]

	set actionList {}
	if {$atEnd} {
		if {"append" in $extraActions} { lappend actionList append }
	} else {
		lappend actionList replace variation mainline
	}
	if {![::scidb::game::query trial] && [::scidb::game::current] < 9} {
		lappend actionList trial
	}
	if {!$atEnd} {
		lappend actionList exchange
	}
	foreach action $extraActions {
		if {$action ni $actionList && ($action ne "append" || $atEnd)} {
			lappend actionList $action
		}
	}

	foreach action $actionList {
		set accel {}
		if {[info exists mc::Accel($action)]} {
			set key $mc::Accel($action)
			lappend accel -accelerator $key
			set cmd [namespace code [list InvokeAction $m $command $action]]
			bind $m <Key-$key> $cmd
			bind $m <Key-[string tolower $key]> $cmd
		}
		$m add command \
			-command [list eval $command $action] \
			-image $icon::16x16::Action($action) \
			-compound left \
			{*}$accel \
			;
		::widget::menuTextvarHook $m $i [namespace current]::mc::Action($action)
		incr i
	}

	return $i
}


proc doDestructiveCommand {parent action cmd yesAction noAction} {
	if {![{*}$cmd]} {
		set rc [;;dialog::question -parent $parent -message [format $mc::GameWillBeTruncated $action]]
		if {$rc eq "no"} {
			if {[llength $noAction]} {
				{*}$noAction
			}
			return
		}
		if {[string match *widget::busyOperation [lindex $cmd 0]]} {
			lassign $cmd cmd args
			set cmd [list $cmd [list {*}$args -force]]
		} else {
			lappend cmd -force
		}
		{*}$cmd
	}

	if {[llength $yesAction]} {
		{*}$yesAction
	}
}


proc inHandSelected {w piece} {
	variable Drop
	set Drop(piece) $piece
}


proc inHandDropPosition {w x y state piece} {
	variable ::application::board::board
	variable ::board::hilite
	variable Square

	if {$hilite(show-suggested)} {
		set square [::board::diagram::getSquare $board $x $y]
		if {$square == $Square(hilited)} { return }
		::board::diagram::hilite $board $Square(hilited) off

		set allowIllegalMove [::util::shiftIsHeldDown? $state]

		if {$square != -1 && [::scidb::pos::legal? $square $square $allowIllegalMove $piece]} {
			::board::diagram::hilite $board $square suggested
			[::board::diagram::canvas $board] raise drag-piece
		}

		set Square(hilited) $square
		set Square(origin) $square
	}
}


proc inHandPieceDrop {w x y state piece} {
	variable ::application::board::board
	variable ::board::hilite
	variable Square
	variable Drop

	if {$hilite(show-suggested)} {
		::board::diagram::hilite $board $Square(hilited) off
		set Square(hilited) -1
	}

	set square [::board::diagram::getSquare $board $x $y]
	set allowIllegalMove [::util::shiftIsHeldDown? $state]

	if {$square == -1} {
		::application::board::finishDrop
	} else {
		::application::board::deselectInHandPiece
		if {[::scidb::pos::legal? $square $square $allowIllegalMove $piece]} {
			::board::diagram::setPiece $board $square $piece
			set Drop(takeBack) $square
			set Drop(piece) $piece
			::board::diagram::animate $board 0
			AddMove $square $square $allowIllegalMove
			::board::diagram::animate $board 1
			set Drop(takeBack) -1
		} else {
			::application::board::finishDrop
		}
	}

	set Drop(piece) " "
}


proc cancelVariation {} {
	variable Variation
	set Variation 0
}


proc nextVariation {} {
	variable Variation

	if {$Variation} {
		::scidb::game::go 1
		set Variation 0
	} elseif {![::scidb::game::position atStart?]} {
		::scidb::game::go -1
		while {[::scidb::game::position atStart?] && ![::scidb::game::position isMainline?]} {
			::scidb::game::variation leave
			::scidb::game::go -1
		}
		set Variation 1
	}
}


proc EnterVariation {varno} {
	::scidb::game::go variation $varno
	::scidb::game::go 1
}


proc AddMove {sq1 sq2 allowIllegalMove} {
	if {![DoAddMove $sq1 $sq2 $allowIllegalMove]} { AfterAddMove }
}


proc DoAddMove {sq1 sq2 allowIllegalMove} {
	variable ::application::board::board
	variable Variation
	variable Options
	variable Leave
	variable Drop

	if {$sq2 == -1} { return 0 }
	if {[::scidb::game::query over?]} { return 0 }
	if {$sq2 == -1} { return 0 }
	set nullmove [expr {$sq1 eq "null" && $sq2 eq "null"}]

	if {$sq1 ne "null"} {
		set c [::scidb::pos::stm]
		set s [string index [::board::diagram::piece $board $sq1] 0]
		set f [string index [::board::diagram::piece $board $sq2] 1]
		if {$s ne $c || $f eq "k"} {
			set tmp $sq1
			set sq1 $sq2
			set sq2 $tmp
		}
	}

	if {![::scidb::pos::valid? $sq1 $sq2]} { return 0 }

	if {!$allowIllegalMove && ![::scidb::pos::legal? $sq1 $sq2 $allowIllegalMove $Drop(piece)]} {
		return 0
	}

	variable _promoted $Drop(piece)
	set Drop(piece) " "

	if {[scidb::pos::promotion? $sq1 $sq2 $allowIllegalMove]} {
		catch { destroy $board.popup_promotion }
		set color [string index [::board::diagram::piece $board $sq1] 0]
		set variant [::scidb::game::query Variant?]
		set m [menu $board.popup_promotion -tearoff false]
		catch { wm attributes $m -type popup_menu }
		switch $variant {
			Antichess	{ set pieces {k r n q b} }
			Losers		{ set pieces {q r n b} }
			default		{ set pieces {q r b n} }
		}
		foreach p $pieces {
			$m add command \
				-image photo_Piece(figurine,1,$color$p,$Options(figurineSize)) \
				-command [namespace code [list set _promoted $p]] \
				;
		}
		set Leave 0
		variable trigger_ 0
		# XXX <<MenuUnpost>> only available under X11.
		bind $board.popup_promotion <<MenuUnpost>> [list set [namespace current]::trigger_ 1]
		tk_popup $board.popup_promotion {*}[winfo pointerxy $board]
		vwait [namespace current]::trigger_
		if {$Leave < 0} { leaveSquare [expr {-($Leave - 1)}] }
		set Leave 1
		if {$_promoted == " "} { return 0 }
#	} elseif {!$nullmove && $sq1 eq $sq2 && $Drop(piece) eq " "} {
#		catch { destroy $board.popup_drop }
#		set color [string range [::scidb::game::query stm] 0 0]
#		set m [menu $board.popup_drop -tearoff false]
#		catch { wm attributes $m -type popup_menu }
#		set pieceCount [::scidb::pos::inHand? -destination $sq1 -stm]
#		set havePieces 0
#		foreach n $pieceCount p {q r b n p} {
#			if {$n} {
#				$m add command \
#					-image photo_Piece(figurine,1,$color$p,$Options(figurineSize)) \
#					-command [namespace code [list set _promoted $p]] \
#					;
#				incr havePieces 1
#				set piece $p
#			}
#		}
#		switch $havePieces {
#			0 { return 0 }
#			1 { set _promoted $piece }
#
#			default {
#				set Leave 0
#				variable trigger_ 0
#				bind $board.popup_drop <<MenuUnpost>> [list set [namespace current]::trigger_ 1]
#				tk_popup $board.popup_drop {*}[winfo pointerxy $board]
#				vwait [namespace current]::trigger_
#				if {$Leave < 0} { leaveSquare [expr {-($Leave - 1)}] }
#				set Leave 1
#				if {$_promoted == " "} { return 0 }
#			}
#		}
	}

	addMove menu [::scidb::pos::san $sq1 $sq2 $_promoted] \
		-nomovecmd [namespace code AfterAddMove] \
		-force [expr {$allowIllegalMove || $Variation}] \
		;

	return 1
}


proc AfterAddMove {} {
	variable ::application::board::board
	variable Drop

	::board::diagram::setDragSquare $board

	if {$Drop(takeBack) != -1} {
		::application::board::finishDrop
		::board::diagram::setPiece $board $Drop(takeBack) .
		set Drop(takeBack) -1
	}

	reset
}


proc InvokeAction {m command action} {
	::tk::MenuUnpost $m
	eval $command $action
}


proc SetAction {action} {
	set [namespace current]::action_ $action
}


proc ConfirmReplaceMove {confirmWindowType extraActions} {
	variable ::application::board::board
	variable Options
	variable Disabled
	variable Leave
	variable Lock

	if {$Options(addVarWithoutAsking)}	{ return "variation" }
	if {[::game::trialMode?]}				{ return "replace" }
	if {!$Options(askToReplaceMoves)}	{ return "replace" }

	set m $board.popup_confirm
	catch { destroy $m }
	variable action_ cancel
	menu $m -tearoff false
	catch { wm attributes $m -type popup_menu }
	set i [addActionsToMenu $m [namespace current]::SetAction $extraActions]
	$m add separator; incr i
	$m add command \
		-image $::icon::16x16::crossHand \
		-compound left \
		-command [namespace code [list set action_ cancel]] \
		-accelerator $::mc::Key(Esc) \
		;
	::widget::menuTextvarHook $m $i ::mc::Cancel
	set entry [lsearch -exact {replace variation} $Options(defaultAction)]
	set Leave 0
	set Disabled 1
	set Lock 1
	variable _wait 1
	bind $m <<MenuUnpost>> [list set [namespace current]::_wait 0]
	tk_popup $m {*}[winfo pointerxy $board]
	# Aqua's native menu tracking can deliver MenuUnpost before tk_popup
	# returns. Wait only while the menu is still open, not for a second event.
	if {$_wait} { tkwait variable [namespace current]::_wait }
	if {$Leave < 0} { leaveSquare [expr {-($Leave - 1)}] }
	set Leave 1
	after idle [namespace code [list Unlock $action_]]
	return $action_
}


proc Unlock {action} {
	variable Lock
	variable Disabled

	set Lock 0

	if {$action eq "cancel"} {
		enable {*}[winfo pointerxy .]
	} else {
		set Disabled 0
	}
}


::board::pieceset::registerFigurines $Options(figurineSize) 1

namespace eval icon {
namespace eval 16x16 {

set Action(trial)		$::icon::16x16::trial
set Action(exchange)	$::icon::16x16::exchange
set Action(append)	$::icon::16x16::plus
set Action(load)		$::icon::16x16::document

set Action(replace) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADtElEQVR4nDWT
	3U9TZxyAf79z3renpacWC9TaUkCysLDbXbgrlyWLW9CgEIpGWNyWZZnZYMYY5cOJcQoqhI1M5zYN
	i3MgrkIUo4ZkWTbvze50G0OgrNBSsXz065z3Pee3i7nnH3gunjwIAEBEwbVM5vXUctrNuGJLIRVf
	SXHW5/U+RMQ4EWlSyjrLskDTtKloNGpEIhFCRJsRUXD4x4lzYxMPGgpGQSNCAiR0aU6jqX7nbSLq
	+msmVnf81MAZl1Oj0Sv9B5qbm39+IUYlk8nvGB2/17yYTOlSWgAIDktaEE+m9OjkVONiItX7acfZ
	03/OxEpXnq/S01h8ezqdbiKiACISTs/MffBe24mvpbTgq/MnesNb/dML8URNe2dfByCw4k26iCdS
	moNzUhXFVFQV9CIX7W+sG3+/teGYwrhiAyFxznl1ReBJIFA2UlkVfsw5cwCATYA2EPwHIgKRvZhM
	OUfH7zWuZTI7FCltFRBUKYT4e27xlUQi1bIQi9cKIQRTVHvwzPH74dCWRDZnoNejpy4NnLy4SS/K
	m6bJUssrOivzlaxxrubSq+uew529nZxzLqSUG9k8K/NtNmtrto19M/jZVHvHhUFVVTDg91mGKR2I
	imojqszr1R99eHDf71ev39peyBeUgmHmARH8pT7R0rx7EgB+qwiFUrYQMWAsBwBF1ZWhVgCwKsPB
	GBLRrnc/7vo2XzCKL/f3XBNSSgLbGfCX/gIAvyJikogC69nsq0tLK26v7nQTwGu62531eNyX2Mxs
	LPTH9GxICGEiUvLQ0dOtUkrPxQvdj6ory5NE5P9+ZGLoxviDvYYpHNKyLGlJ0+1y5ZvqdwYYEdmc
	c4mI9vw/CU82n9cX4slA27Gz/XPzCwQA69d/utuw/CzNPe4ik3PGbVL489U11w837zThxkZu/953
	PhlOLK+4NunuvE2kWpbFDFMoVeHg0ndf9kzuaWk7yFRVHTrX3Rve6p+ejydqjnSf78jlCw5F110P
	DzTtnghuKSsAogJE/1cHAAAVmY2ANuOcV1eEngQCZSPbwsHHnKuciIgh4iIRHd2z643ba+vZlw8d
	OdUeiy/7X6oqX7vyRc9JC2xSVfUjYZriaSxeG0+kWmYXFmuEkAIRHYyIEBETAHCLiN4s2VyMLqcz
	NdTX+Xl1deXV+fl4ve4uEonlZ47DXX0dTFW4lJbM5QsOTXMY+OIqJRqNYiQS0QzDeEtVVWCM3UdE
	g4jKLw/fHLg2dqfeNIWLiAARwKlpuX0Nb9/9F9A464I5YbFzAAAAAElFTkSuQmCC
}]

set Action(variation) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACl0lEQVR4nJWS
	T0hUURjFv3vnvnmMwcSgmX+acUZtFKFFS6GVBgaGuBEXLlKEAv+1MwaJmVIxN0VJixaWSCvXCS0i
	CqqFG4M2/kNnnGx0njOW6Iz33XnvtGgGRJPorA7fOffHx72XASiWUt5JGnvFOTu3rEwLwdqqbSJ6
	xxjLEhEBcBHR9ZW1WJnmdDDBRV3pBU9K1/UXQip1+25ocnRpdYMLB1OHWQm/t/zXzPPxHiKaJyKS
	UjZ1949MR+OJ8+dcOstZ0OovB+ynkyEIw0iVLK1ucCOVJqdT0zQhwBm3MlISY4yIiDJSEmfcsixL
	pH7uc9NURETcMFIlXEpzRQhuOp0alFK4WFp89Hh8eN7jdn8EQADI43Z/eDIRelNeWnKkVA5OpwYh
	uCmlucKVsnBwmHVoQrDqqkvm2nrc1T0w0hqL/egBwAGweHy751Z/6Oby+mZRwFdhakKwg8OsQykL
	vD4YSAR8Fenaau/Oy2djs35fxU7s+07ZwL3xB4aRGjJSe0N9w6MPY/HtsoCvPDk9NTpbW+3dCfgq
	0vXBQIIBcEkpmzJSksft/hTfSnT1D4+PLa1EPVev1GWIiBa/LRfVB/17U49C96u8la/39vevFek6
	6br+nk4KgBbd3Bps7ewzGhrb0NDYhtbOPiO6uTUIQPvbARYGeDgc5gB4fub4vLA409jSZTe2dNlf
	Fr6+AuDIZzwcDvNw/n5OAefm/hSTu+mJ5vZeNLf3IrmbnjieHZc4OejoIDDGSEllAiAiIqWUyRij
	jg7CPwGRSIQAkGmqaC6XAxGReaSiACgSiZza+BSgINuGsm0bBX9W70wAYIucZfGC/29ATY0v4fdW
	Jgv+rN6pZwDAGGPIf7AbRES6rr9ljGUL2fH+b5ZVboGiSxzjAAAAAElFTkSuQmCC
}]

set Action(mainline) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAC/klEQVR4nG1T
	a2hUZxScc+7du5tgSGwetpFWcKnWNNJKbBIfWZtEbVWo9CEEfBRLLQiCKP1RqHQXivhABbU/RAVL
	BNFaUROqYrpBTYjPWERjauKqNRrWjUlFbPd57/SHe9Mozp+P7zADZ+acA/wPAQCSJslCkmb2/8q6
	yx8miQhJVjQePL6iu+euv2zC+AjJvSJyheTUxoNNX9+8FRlfNtF/h+QeEekkKSZJFRGH5Lj1W3dt
	O9wUDsTjCZzK7Zjde+++n+SPwQ07f2g+3V4fTyRxqrUDff3RSSSXish9DYVCAICBoaGq8LmL01Vp
	L5hT0+cxDbv17IWqaOzxknDbpSpVZupmVnSoIv37mfMzYoODlQCgbgC2DSHh2Laj/dHYKJHnHlUF
	AIUO1XaogKhk/QPAcAevF792Yf6cQJehhnT9eXt0PJnS+g+nXSwpKtxfH6huM02Pnr98rTqdThu1
	NZVtJYWFl4fjd5N+8uTpd3ULv3IqZzc4vxw9GSY5xee18GhgcNvcz7/JvFfzWabxUHMnyeqsThUA
	QqGQAJBYbKgvmUrB5/NK7ayqny2P54+bPZHVy1d9v+RR7LGhhurxE61jI/cevk/SC4DDGYyEiMCj
	nmQqnQ6sXbd5/e27D4pN06CK4FrXrTHfrtu4GUCdiNDtgABYVFLwlteyJB5P4ETL2S8BfCCQ2LsT
	/c8sy3Isy2OXv+OP+3J86WQyKa5/zb7jNm3fe2XKrEWsqF1kl01byC0/7btOct+N7p5D0z9enJwx
	b2nmQX90B8m5JHMAwHSnEI0OVJ9saZ/s0IapHsnxWTzw62/lR5pbJmQymdQ//yasN8YUpUfn57WI
	yOkXVhkADMOgKhQARcWmTRVV8XotyzQMqyA/P9Hw6UfHcnNzO92uRYTy0io3Hm4KB0gHALD4i/nX
	16xctqf3Tt/fpaXFiYK8vHYRiY4M3MyKRUT+Irn2zbGlK2509/rLJ70dWdbwyW4RuTpS4B7eK6eX
	JbxwtsFgUIPBoJJUd+FG4j/rqo0r+tvNIAAAAABJRU5ErkJggg==
}]

} ;# namespace 16x16
} ;# namespace icon
} ;# namespace move

# vi:set ts=3 sw=3:
