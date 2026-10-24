# ======================================================================
# Author : $Author$
# Version: $Revision: 1528 $
# Date   : $Date: 2018-10-28 10:02:07 -0400 (Sun, 28 Oct 2018) $
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
# Copyright: (C) 2009-2018 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source game-bar

namespace eval gamebar {
namespace eval mc {

set StartPosition						"Start Position"
set Players								"Players"
set Event								"Event"
set Site									"Site"
set SeparateHeader					"Separate header"
set ShowActiveAtBottom				"Show active game at bottom"
set ShowPlayersOnSeparateLines	"Show players on separate lines"
set DiscardChanges					"This game has altered.\n\nDo you really want to discard the changes made to it?"
set DiscardNewGame					"Do you really want to throw away this game?"
set NewGameFstPart					"New"
set NewGameSndPart					"Game"
set EnterGameNumber					"Enter game number"

set CopyThisGameToClipbase			"Copy this game to Clipbase"
set CopyThisGameToClipboard		"Copy this game to Clipboard (PGN format)"
set ExportThisGame					"Export this game"
set PasteLastClipbaseGame			"Paste last Clipbase game"
set PasteClipboardContent			"Paste content from Clipbpard"
set PasteGameFrom						"Paste game"
set LoadGameNumber					"Load game number"
set ReloadCurrentGame				"Re-load current game"
set OriginalVersion					"Original version from database"
set ModifiedVersion					"Modified version in game editor"
set WillCopyModifiedGame			"This operation will copy the modified game in editor. The original version cannot be copied because the associated database is not open."

set CopyGame							"Copy Game"
set ExportGame							"Export Game"
set ExplainGame						"Explain this game"
set LockGame							"Lock Game"
set UnlockGame							"Unlock Game"
set CloseGame							"Close Game"

set GameNew								"New Game"
set AddNewGame							"Add New Game to %s..."
set ReplaceGame						"Replace Game in %s..."
set ReplaceMoves						"Replace Moves Only in Game..."

set Tip(Antichess)					"There is no check, no castling, the king\nis captured like an ordinary piece."
set Tip(Suicide)						"In case of stalemate the side with fewer\npieces will win (according to FICS rules)."
set Tip(Giveaway)						"In case of stalemate the side which is\nstalemate wins (according to international rules)."
set Tip(Losers)						"The king is like in normal chess, and you can also\nwin by getting checkmated or stalemated."

} ;# namespace mc

array set Defaults {
	background:normal		gamebar,background:normal
	foreground:normal		gamebar,foreground:normal
	background:selected	gamebar,background:selected
	background:emphasize	gamebar,background:emphasize
	background:active		gamebar,background:active
	background:darker		gamebar,background:darker
	background:shadow		gamebar,background:shadow
	background:lighter	gamebar,background:lighter
	background:hilite		gamebar,background:hilite
	foreground:hilite		gamebar,foreground:hilite
	background:hilite2	gamebar,background:hilite2
	foreground:hilite2	gamebar,foreground:hilite2
	foreground:elo			gamebar,foreground:elo
	width						18
	padx						5
	pady						3
}

array set Options {
	alignment			center
	separateLines		0
	selectedAtBottom	1
	separateColumn		1
}

array set Specs {
	counter:game 0
}


proc gamebar {path} {
	variable Specs
	variable Defaults

	set gamebar [tk::canvas $path -borderwidth 0]

	$gamebar bind header <ButtonPress-3> [namespace code [list PopupMenu $gamebar]]

	bind $gamebar <Destroy> [namespace code [list array unset Specs *:$gamebar]]
	bind $gamebar <Configure> [namespace code { Configure %W %w }]
	bind $gamebar <<LanguageChanged>> [namespace code [list update $gamebar]]
	bind $gamebar <<ThemeChanged>> [namespace code [list ThemeChanged $gamebar]]

	set Specs(height:$gamebar) 0
	set Specs(width:$gamebar) 0
	set Specs(selected:$gamebar) {}
	set Specs(size:$gamebar) 0
	set Specs(line:$gamebar) 0
	set Specs(number:$gamebar) 1
	set Specs(width:$gamebar) $Defaults(width)
	set Specs(receiver:$gamebar) {}
	set Specs(adjustment:$gamebar) {1 0 0 0}
	set Specs(linewidth:$gamebar) 0
	set Specs(player:locked) 0
	set Specs(event:locked) 0
	set Specs(site:locked) 0

	insert $gamebar -1 -1 {}
	::tooltip::tooltip exclude $gamebar input-1
#	::tooltip::tooltip exclude $gamebar close:input-1

	::scidb::db::subscribe gameInfo [list [namespace current]::Update $gamebar]

	return $path
}


proc ThemeChanged {gamebar} {
	if {![winfo exists $gamebar]} { return }
	variable Defaults
	variable Specs

	$gamebar configure -background [::ttk::style lookup [::theme::currentTheme] -background]

	set fg [::colors::lookup $Defaults(foreground:normal)]
	set elofg [::colors::lookup $Defaults(foreground:elo)]
	set normal [::colors::lookup $Defaults(background:normal)]
	set lighter [::colors::lookup $Defaults(background:lighter)]
	set darker [::colors::lookup $Defaults(background:darker)]

	set allIds [concat -1 [getIdList $gamebar]]
	foreach id $allIds {
		foreach tag {white black hyphen line1 line2 line3} {
			catch { $gamebar itemconfigure ${tag}${id} -fill $fg }
		}
		foreach tag {whiteElo blackElo} {
			catch { $gamebar itemconfigure ${tag}${id} -fill $elofg }
		}
		catch { $gamebar itemconfigure close:lighter$id -fill $lighter -outline $lighter }
		catch { $gamebar itemconfigure close:darker$id -fill $darker -outline $darker }
		catch { $gamebar itemconfigure close:bg$id -fill $normal -outline $normal }
	}

	set sel $Specs(selected:$gamebar)
	foreach id [getIdList $gamebar] {
		if {$id ne $sel} {
			PrepareAsButton $gamebar $id
		}
	}
	if {[llength $sel]} {
		if {[UseSeparateColumn $gamebar]} {
			PrepareAsSunkenButton $gamebar $sel
			PrepareSeparateColumn $gamebar $sel
			PrepareAsHeader $gamebar -1
		} else {
			PrepareAsHeader $gamebar $sel
		}
	}
	Layout $gamebar
}


proc update {gamebar} {
	foreach id [getIdList $gamebar] {
		Update $gamebar $id no
	}
}


proc add {gamebar id tags} {
	if {[winfo exists $gamebar]} { insert $gamebar end $id $tags }
}


proc insert {gamebar at id tags} {
	variable Specs
	variable Defaults
	variable Options
	variable icon::15x15::close
	variable icon::15x15::digit	;# alternative: or U+2776, U+2777, ... (or U+278A, U+278B)

	if {$at eq "end"} { set at $Specs(size:$gamebar) }
	set normal [::colors::lookup $Defaults(background:normal)]
	set lighter [::colors::lookup $Defaults(background:lighter)]
	set darker [::colors::lookup $Defaults(background:darker)]
	set foreground [::colors::lookup $Defaults(foreground:normal)]

	if {$at >= 0} {
		set data [MakeData $gamebar $id $tags]
		set state normal
	} else {
		set data {}
		set state hidden
	}

	$gamebar create rectangle 0 0 0 0 \
		-tags [list lighter$id all$id] \
		-fill $lighter \
		-outline $lighter \
		-state $state \
		;
	$gamebar create rectangle 0 0 0 0 \
		-tags [list darker$id all$id] \
		-fill $darker \
		-outline $darker \
		-state $state \
		;
	$gamebar create rectangle 0 0 0 0 \
		-tags [list bg$id all$id] \
		-fill $normal \
		-outline $normal \
		-state $state \
		;
	$gamebar create image 0 0 \
		-anchor nw \
		-tags [list whiteCountry$id all$id] \
		-state hidden \
		;
	$gamebar create rectangle 0 0 0 0 \
		-tags [list whiteCountryInput$id all$id] \
		-fill {} \
		-outline {} \
		-state hidden \
		;
	$gamebar create image 0 0 \
		-anchor nw \
		-tags [list blackCountry$id all$id] \
		-state hidden \
		;
	$gamebar create rectangle 0 0 0 0 \
		-tags [list blackCountryInput$id all$id] \
		-fill {} \
		-outline {} \
		-state hidden \
		;
#	$gamebar create image 0 0 \
#		-anchor nw \
#		-tags [list eventCountry$id all$id] \
#		-state hidden \
#		;
#	$gamebar create rectangle 0 0 0 0 \
#		-tags [list eventCountryInput$id all$id] \
#		-fill {} \
#		-outline {} \
#		-state hidden \
#		;
	$gamebar create text 0 0 \
		-anchor nw \
		-font $::font::text(text:normal) \
		-fill [::colors::lookup $Defaults(foreground:elo)] \
		-tags [list whiteElo$id all$id] \
		-state hidden \
		;
	$gamebar create text 0 0 \
		-anchor nw \
		-font $::font::text(text:normal) \
		-fill [::colors::lookup $Defaults(foreground:elo)] \
		-tags [list blackElo$id all$id] \
		-state hidden \
		;
	$gamebar create text 0 0 \
		-anchor nw \
		-justify left \
		-font $::font::text(text:normal) \
		-tags [list hyphen$id all$id] \
		-text " \u2013 " \
		-fill $foreground \
		-state $state \
		;
	$gamebar create rectangle 0 0 0 0 \
		-fill $normal \
		-outline $normal \
		-tags [list whitebg$id bg$id all$id] \
		-state $state \
		;
	$gamebar create text 0 0 -anchor nw \
		-justify left \
		-font $::font::text(text:normal) \
		-tags [list white$id all$id] \
		-text [lindex $data 0] \
		-fill $foreground \
		-state $state \
		;
	$gamebar create rectangle 0 0 0 0 \
		-fill {} \
		-outline {} \
		-tags [list whiteInput$id all$id] \
		-state $state \
		;
	$gamebar create rectangle 0 0 0 0 \
		-fill $normal \
		-outline $normal \
		-tags [list blackbg$id bg$id all$id] \
		-state $state \
		;
	$gamebar create text 0 0 \
		-anchor nw \
		-justify left \
		-font $::font::text(text:normal) \
		-tags [list black$id all$id] \
		-text [lindex $data 1] \
		-fill $foreground \
		-state $state \
		;
	$gamebar create rectangle 0 0 0 0 \
		-fill {} \
		-outline {} \
		-tags [list blackInput$id all$id] \
		-state $state \
		;
	$gamebar create image 0 0 \
		-anchor nw \
		-tags [list digit$id all$id] \
		-image $digit([expr {$at < 0 ? 1 : $at + 1}]) \
		-state $state \
		;
	$gamebar create text 0 0 \
		-anchor nw \
		-justify left \
		-font $::font::text(text:normal) \
		-tags [list line1$id all$id] \
		-text [lindex $data 2] \
		-fill $foreground \
		-state hidden \
		;
	$gamebar create rectangle 0 0 0 0 \
		-fill {} \
		-outline {} \
		-tags [list line1bg$id bg$id all$id] \
		-state $state \
		;
	$gamebar create rectangle 0 0 0 0 \
		-fill {} \
		-outline {} \
		-tags [list line1Input$id all$id] \
		-state $state \
		;
	$gamebar create text 0 0 \
		-anchor nw \
		-justify left \
		-font $::font::text(text:normal) \
		-tags [list line2$id all$id] \
		-text [lindex $data 3] \
		-fill $foreground \
		-state hidden \
		;
	$gamebar create rectangle 0 0 0 0 \
		-fill {} \
		-outline {} \
		-tags [list line2bg$id bg$id all$id] \
		-state $state \
		;
	$gamebar create rectangle 0 0 0 0 \
		-fill {} \
		-outline {} \
		-tags [list line2Input$id all$id] \
		-state $state \
		;
	$gamebar create text 0 0 \
		-anchor nw \
		-justify left \
		-font $::font::text(text:normal) \
		-tags [list line3$id all$id] \
		-text [lindex $data 4] \
		-fill $foreground \
		-state hidden \
		;
	$gamebar create rectangle 0 0 0 0 \
		-fill {} \
		-outline {} \
		-tags [list input$id all$id] \
		-state $state \
		;
	$gamebar create rectangle 0 0 0 0 \
		-tags [list close:lighter$id all$id close$id] \
		-fill $lighter \
		-outline $lighter \
		-state $state \
		;
	$gamebar create rectangle 0 0 0 0 \
		-tags [list close:darker$id all$id close$id] \
		-fill $darker \
		-outline $darker \
		-state $state \
		;
	$gamebar create rectangle 0 0 0 0 \
		-tags [list close:bg$id all$id close$id] \
		-fill $normal \
		-outline $normal \
		-state $state \
		;
	$gamebar create image 0 0 \
		-anchor nw \
		-tags [list close:icon$id all$id close$id] \
		-image $close(unlocked) \
		-state $state \
		;
	$gamebar create rectangle 0 0 0 0 \
		-fill {} \
		-outline {} \
		-tags [list close:input$id all$id close$id] \
		-state $state \
		;

	set tag line1Input$id

	$gamebar bind $tag <ButtonPress-1>		[namespace code [list ShowCrossTable $gamebar $id]]
	$gamebar bind $tag <ButtonPress-2>		[namespace code [list ShowEvent $gamebar $id]]
	$gamebar bind $tag <ButtonRelease-2>	[namespace code [list HideEvent $gamebar $id]]
	$gamebar bind $tag <ButtonPress-3>		[namespace code [list PopupEventMenu $gamebar $id]]

	$gamebar bind $tag <Enter>	[namespace code [list EnterEvent $gamebar $id]]
	$gamebar bind $tag <Leave>	[namespace code [list LeaveEvent $gamebar $id]]

	set tag line2Input$id

	$gamebar bind $tag <ButtonPress-1> [namespace code [list VisitURL $gamebar $id]]
	$gamebar bind $tag <ButtonPress-3> [namespace code [list PopupSiteMenu $gamebar $id]]

	$gamebar bind $tag <Enter>	[namespace code [list EnterSite $gamebar $id]]
	$gamebar bind $tag <Leave>	[namespace code [list LeaveSite $gamebar $id]]

	foreach side {white black} {
		set tag ${side}Input${id}

		$gamebar bind $tag <ButtonPress-1>		[namespace code [list ShowPlayerCard $gamebar $id $side]]
		$gamebar bind $tag <ButtonPress-2>		[namespace code [list ShowPlayerInfo $gamebar $id $side]]
		$gamebar bind $tag <ButtonRelease-2>	[namespace code [list HidePlayerInfo $gamebar $id $side]]
		$gamebar bind $tag <ButtonPress-3>		[namespace code [list PopupPlayerMenu $gamebar $id $side]]

		$gamebar bind $tag <Enter>	[namespace code [list EnterPlayer $gamebar $id $side]]
		$gamebar bind $tag <Leave>	[namespace code [list LeavePlayer $gamebar $id $side]]

		set tag ${side}CountryInput${id}

		$gamebar bind $tag <Enter>					[namespace code [list EnterFlag $gamebar $id $side]]
		$gamebar bind $tag <Leave>					[namespace code [list LeaveFlag $gamebar $id]]
		$gamebar bind $tag <ButtonPress-2>		[namespace code [list ShowTags $gamebar $id]]
		$gamebar bind $tag <ButtonRelease-2>	[namespace code [list HideTags $gamebar]]
		$gamebar bind $tag <ButtonPress-3>		[namespace code [list PopupMenu $gamebar $id]]
	}

	$gamebar bind close:input$id <ButtonPress-1> [namespace code [list Press $gamebar $id close:]]
	$gamebar bind close:input$id <ButtonRelease-1> [namespace code [list Release $gamebar $id close:]]
	$gamebar bind close:input$id <ButtonPress-2> [namespace code [list ShowTags $gamebar $id]]
	$gamebar bind close:input$id <ButtonRelease-2> [namespace code [list HideTags $gamebar]]

	if {$id ne "-1"} {
		$gamebar bind close:input$id <Enter> [namespace code [list Enter $gamebar $id close:]]
		$gamebar bind close:input$id <Leave> [namespace code [list Leave $gamebar $id close:]]
	}

	$gamebar bind input$id <ButtonPress-2> [namespace code [list ShowTags $gamebar $id]]
	$gamebar bind input$id <ButtonRelease-2> [namespace code [list HideTags $gamebar]]

	foreach type {input white black} {
		$gamebar bind $type$id <ButtonPress-1> [namespace code [list Press $gamebar $id]]
		$gamebar bind $type$id <ButtonRelease-1> [namespace code [list Release $gamebar $id]]
		$gamebar bind $type$id <ButtonPress-3> [namespace code [list PopupMenu $gamebar $id]]

		if {$id ne "-1"} {
			$gamebar bind $type$id <Enter> [namespace code [list Enter $gamebar $id]]
			$gamebar bind $type$id <Leave> [namespace code [list Leave $gamebar $id]]
		}
	}

	if {$Specs(size:$gamebar) == 1 && $Options(separateColumn)} {
		PrepareAsHeader $gamebar -1
	}

	if {$at >= 0} {
		set n $at
		while {$n < $Specs(size:$gamebar)} {
			set i $Specs(lookup:$n:$gamebar)
			set Specs(lookup:[incr n]:$gamebar) $i
			$gamebar itemconfigure digit$i -image $digit([expr {$n + 1}])
		}
	}

	set Specs(lookup:$at:$gamebar) $id
	set Specs(emphasize:$id:$gamebar) 0
	if {$at >= 0} {
		incr Specs(size:$gamebar)
		Setup $gamebar $at $id $tags $data
	}

	foreach recv $Specs(receiver:$gamebar) {
		eval $recv inserted $id
	}
}


proc replace {gamebar id tags} {
	variable Specs

	Reset $gamebar $id
	Setup $gamebar [getIndex $gamebar $id] $id $tags [MakeData $gamebar $id $tags]
	$gamebar itemconfigure close:icon$id -image $icon::15x15::close(unlocked)
	if {$Specs(selected:$gamebar) == $id} {
		setEmphasized $gamebar no
	}
	Update $gamebar $id no
}


proc remove {gamebar id {update yes}} {
	variable Specs
	variable Options
	variable icon::15x15::digit

	set at [getIndex $gamebar $id]
	set succ [expr {$at + 1}]
	set pred $at

	for {} {$succ < $Specs(size:$gamebar)} {incr pred; incr succ} {
		set Specs(lookup:$pred:$gamebar) $Specs(lookup:$succ:$gamebar)
	}

	incr Specs(size:$gamebar) -1
	for {set i 0} {$i < $Specs(size:$gamebar)} {incr i} {
		$gamebar itemconfigure digit$Specs(lookup:$i:$gamebar) -image $digit([expr {$i + 1}])
	}

	$gamebar delete all$id
	array unset Specs lookup:$Specs(size:$gamebar):$gamebar
	Reset $gamebar $id

	if {$Specs(size:$gamebar) == 1 && $Options(separateColumn)} {
		foreach item [$gamebar find withtag all-1] {
			$gamebar itemconfigure $item -state hidden
		}
	}

	switch $Specs(size:$gamebar) {
		0 { set Specs(selected:$gamebar) {} }
		1 { $gamebar itemconfigure digit$Specs(lookup:0:$gamebar) -state hidden }
	}

	if {$update} {
		if {$id eq $Specs(selected:$gamebar) && $Specs(size:$gamebar)} {
			if {$at == $Specs(size:$gamebar)} { set at 0 }
			SetSelected $gamebar $Specs(lookup:$at:$gamebar)
		} else {
			set sid $Specs(selected:$gamebar)
			set Specs(selected:$gamebar) {}
			SetSelected $gamebar $sid
		}

		foreach recv $Specs(receiver:$gamebar) {
			eval $recv removed $id
		}
	}
}


proc setState {gamebar id modified} {
	variable Specs

	if {$Specs(modified:$id:$gamebar) != $modified} {
		variable icon::15x15::close

		if {$modified} {
			set state modified
		} elseif {$Specs(locked:$id:$gamebar)} {
			set state locked
		} else {
			set state unlocked
		}

		$gamebar itemconfigure close:icon$id -image $close($state)
		set Specs(modified:$id:$gamebar) $modified
		set Specs(state:$id:$gamebar) $state
		SetTooltip $gamebar $id
	}
}


proc setEmphasized {gamebar flag} {
	variable Specs

	set id $Specs(selected:$gamebar)
	set Specs(emphasize:$id:$gamebar) $flag

	if {[UseSeparateColumn $gamebar]} {
		set Specs(emphasize:-1:$gamebar) $flag
		PrepareAsHeader $gamebar -1
	} else {
		PrepareAsHeader $gamebar $id
	}
}


proc setFrozen {gamebar id flag {tooltipvar ""}} {
	variable icon::15x15::close
	variable icon::15x15::frozen
	variable Specs

	set Specs(frozen:$id:$gamebar) $flag

	if {$flag} {
		set img $frozen
		if {[llength $tooltipvar]} { ::tooltip::tooltip $gamebar -item close:input$id $tooltipvar }
	} else {
		set img $close($Specs(state:$id:$gamebar))
		SetTooltip $gamebar $id
	}

	$gamebar itemconfigure close:icon$id -image $img
}


proc lock {gamebar id} {
	variable Specs

	if {$Specs(locked:$id:$gamebar)} { return 0 }
	if {$Specs(modified:$id:$gamebar)} { set state modified } else { set state locked }
	set Specs(locked:$id:$gamebar) 1
	SetState $gamebar $id $state
	return 1
}


proc unlock {gamebar id} {
	variable Specs

	if {$Specs(modified:$id:$gamebar)} { return 0 }
	if {$Specs(size:$gamebar) > 1} { return 0 }
	set Specs(locked:$id:$gamebar) 0
	SetState $gamebar $id unlocked
	return 1
}


proc activate {gamebar id} {
	variable Specs

	if {$id ne $Specs(selected:$gamebar)} {
		SetSelected $gamebar $id
	}
}


proc selected {gamebar} {
	return [set [namespace current]::Specs(selected:$gamebar)]
}


proc getId {gamebar at} {
	return [set [namespace current]::Specs(lookup:$at:$gamebar)]
}


proc getIndex {gamebar id} {
	variable Specs

	set at 0
	while {$Specs(lookup:$at:$gamebar) != $id} { incr at }
	return $at
}


proc locked? {gamebar id} {
	return [set [namespace current]::Specs(locked:$id:$gamebar)]
}


proc unlocked? {gamebar id} {
	variable Specs
	return [expr {$Specs(state:$id:$gamebar) eq "unlocked"}]
}


proc empty? {gamebar} {
	variable Specs
	return [expr {![winfo exists $gamebar] || $Specs(size:$gamebar) == 0}]
}


proc size {gamebar} {
	return [set [namespace current]::Specs(size:$gamebar)]
}


proc addReceiver {gamebar recv} {
	lappend [namespace current]::Specs(receiver:$gamebar) $recv
}


proc removeReceiver {gamebar recv} {
	variable Specs

	set n [lsearch -exact $Specs(receiver:$gamebar) $recv]
	if {$n >= 0} {
		set Specs(receiver:$gamebar) [lreplace $Specs(receiver:$gamebar) $n $n]
	}
}


proc getText {gamebar {id {}}} {
	variable Specs

	if {[llength $id] == 0} { set id $Specs(selected:$gamebar) }
	return $Specs(data:$id:$gamebar)
}


proc setAlignment {gamebar amounts} {
	variable Specs

	if {$amounts ne $Specs(adjustment:$gamebar)} {
		set Specs(adjustment:$gamebar) $amounts
		Layout $gamebar
	}
}


proc getIdList {gamebar} {
	variable Specs

	set result {}
	foreach key [array names Specs -glob lookup:*:$gamebar] {
		set id $Specs($key)
		if {$id != -1} {lappend result $id }

	}

	return $result
}


proc normalizePlayer {player} {
	set player [string trim $player]
	set player [regsub -all { ,} $player ", "]
	set player [regsub -all {  } $player " "]
	set player [regsub -all {,,} $player ","]
	set player [regsub -all {,([^ ])} $player {, \1}]
	set player [::figurines::mapToLocal $player $::mc::langID]

	return $player
}


proc popupMenu {gamebar parent {addGameHistory 1} {remove -1}} {
	set menu $parent._gamebar_menu_
	catch { destroy $menu }
	menu $menu -tearoff 0
	AddGameMenuEntries $gamebar $menu 0 $addGameHistory 2 $remove
	tk_popup $menu {*}[winfo pointerxy .]
}


# C1: explain the game currently on the board (the selected game list row).
proc ExplainGame {parent} {
	::application::ai::explainSelection $parent game {}
}


proc addDestinationsForSaveToMenu {parent m {discardActualBase 0}} {
	variable ::scidb::clipbaseName

	set actual [::scidb::db::get name]
	set variant [::scidb::game::query Variant?]
	set position [::scidb::game::current]
	set result {}

	foreach base [::scidb::tree::list] {
		if {	(!$discardActualBase || $base ne $actual)
			&& ![::scidb::db::get readonly? $base]
			&& $variant in [::scidb::db::get variants $base]} {
			lappend result $base
		}
	}

	lappend result $clipbaseName

	foreach base [lsort $result] {
		$m add command \
			-label [::util::databaseName $base] \
			-command [list ::application::pgn::saveGame add $base] \
			;
	}

	return [llength $result]
}


proc addVariantsToMenu {parent m {excludeNormal 0}} {
	set variants {}
	if {!$excludeNormal} { lappend variants Normal }
	lappend variants ThreeCheck Crazyhouse
	set count 0

	foreach variant $variants {
		$m add command \
			-label " $::mc::VariantName($variant)" \
			-image $::icon::16x16::variant($variant) \
			-compound left \
			-command [list ::menu::gameNew $parent $variant] \
			;
		incr count
	}
	foreach variant {Losers Suicide Giveaway} {
		set lbl " $::mc::VariantName(Antichess) - $::mc::VariantName($variant)"
		$m add command \
			-label $lbl \
			-command [list ::menu::gameNew $parent $variant] \
			-image $::icon::16x16::variant($variant) \
			-compound left \
			;
		incr count
		set tip ""
		if {$variant ne "Losers"} { append tip $mc::Tip(Antichess) "\n" }
		append tip $mc::Tip($variant)
		::tooltip::tooltip $m -index $lbl $tip
	}

	return $count
}


proc mergeGame {parent position} {
	::merge::openDialog $parent [::scidb::game::current] $position
}


proc exportGame {parent {position -1}} {
	variable ::scidb::scratchbaseName

	if {$position == -1} { set position [::scidb::game::current] }
	lassign [::scidb::game::sink? $position] base variant index
	set sink [lindex [::scidb::game::sink? $position] 0]
	set mode original

	if {[::scidb::game::query $position modified?]} {
		if {$base ne $scratchbaseName} {
			if {$sink eq $scratchbaseName} {
				set mode modified
			} else {
				set mode [WhichVersion $parent $mc::ExportGame]
			}
		} else {
			set mode modified
		}
	}

	set mainVariant [::util::toMainVariant $variant]
	foreach side {white black} {
		set info [scidb::db::fetch ${side}PlayerInfo $index $base $mainVariant]
		set $side [lindex [split [lindex $info 0] ","] 0]
	}
	if {[string length $white] && [string length $black]} {
		set title "$white-$black"
	} else {
		set title [lindex [::scidb::game::sink? $position] 2]
	}

	::export::open $parent \
		-base $base \
		-variant $variant \
		-index $index \
		-title $title \
		-extension [string range [::util::fileExtension $base] 1 end] \
		-languages [::scidb::game::query langSet $position] \
		-preferred [::application::pgn::languages] \
		;
}


proc UseSeparateColumn {gamebar} {
	variable Specs
	variable Options

	return [expr {$Options(separateColumn) && $Specs(size:$gamebar) > 1}]
}


proc Reset {gamebar id} {
	variable Specs

	foreach item {data tags state atclose locked modified count} {
		array unset Specs $item:$id:$gamebar
	}
	set Specs(emphasize:$id:$gamebar) 0
}


proc SetState {gamebar id state} {
	variable Specs
	variable icon::15x15::close

	set locked $Specs(locked:$id:$gamebar)
	$gamebar itemconfigure close:icon$id -image $close($state)
	set Specs(state:$id:$gamebar) $state
	set Specs(locked:$id:$gamebar) [expr {$state eq "locked"}]
	SetTooltip $gamebar $id

	if {$locked != $Specs(locked:$id:$gamebar)} {
		foreach recv $Specs(receiver:$gamebar) {
			eval $recv lock $id
		}
	}
}


proc SetTooltip {gamebar id} {
	variable Specs

	if {$Specs(frozen:$id:$gamebar)} { return }

	switch $Specs(state:$id:$gamebar) {
		unlocked				{ set var LockGame  }
		modified - locked	{ set var CloseGame }
	}

	::tooltip::tooltip $gamebar -item close:input$id [namespace current]::mc::$var
}


proc Enter {gamebar id {pref {}}} {
	variable Specs
	variable Defaults

	if {[llength $pref] == 0 && $id eq $Specs(selected:$gamebar)} { return }
	if {$pref eq "close:" && $Specs(frozen:$id:$gamebar)} { return }

	# Due to a bug in Tk which sometimes triggers invalid <Enter> events,
	# we have to check whether the mouse pointer is inside the canvas.
	lassign [winfo pointerxy $gamebar] x y
	set x0 [winfo rootx $gamebar]
	set y0 [winfo rooty $gamebar]
	set x1 [expr {$x0 + [winfo width $gamebar]}]
	set y1 [expr {$y0 + [winfo height $gamebar]}]

	if {$x0 > $x || $x > $x1 || $y0 > $y || $y > $y1} { return }

	if {$Specs(buttonstate:$id:$gamebar) eq "raised"} {
		$gamebar itemconfigure ${pref}lighter${id} \
			-fill [::colors::lookup $Defaults(background:darker)] \
			-outline [::colors::lookup $Defaults(background:darker)] \
			;
		$gamebar itemconfigure ${pref}darker${id} \
			-fill [::colors::lookup $Defaults(background:lighter)] \
			-outline [::colors::lookup $Defaults(background:lighter)] \
			;
		set Specs(buttonstate:$id:$gamebar) "sunken"
	} else {
		foreach item {bg whitebg blackbg} {
			$gamebar itemconfigure $pref$item$id \
				-fill [::colors::lookup $Defaults(background:active)] \
				-outline [::colors::lookup $Defaults(background:active)] \
				;
		}
	}
}


proc Leave {gamebar id {pref {}}} {
	variable Specs
	variable Defaults

	if {[llength $pref] == 0 && $id eq $Specs(selected:$gamebar)} { return }
	if {$pref eq "close:" && $Specs(frozen:$id:$gamebar)} { return }

	if {$Specs(buttonstate:$id:$gamebar) eq "sunken"} {
		$gamebar itemconfigure ${pref}lighter${id} \
			-fill [::colors::lookup $Defaults(background:lighter)] \
			-outline [::colors::lookup $Defaults(background:lighter)] \
			;
		$gamebar itemconfigure ${pref}darker${id} \
			-fill [::colors::lookup $Defaults(background:darker)] \
			-outline [::colors::lookup $Defaults(background:darker)] \
			;
		set Specs(buttonstate:$id:$gamebar) "raised"
	} else {
		foreach item {bg whitebg blackbg} {
			$gamebar itemconfigure $pref$item$id \
				-fill [::colors::lookup $Defaults(background:normal)] \
				-outline [::colors::lookup $Defaults(background:normal)] \
				;
		}
	}
}


proc Press {gamebar id {pref {}}} {
	variable Defaults
	variable Specs

	::tooltip::tooltip off
	if {$pref eq "close:" && $Specs(frozen:$id:$gamebar)} { return }

	HideTags $gamebar
	if {[llength $pref] == 0 && ($id eq "-1" || $id eq $Specs(selected:$gamebar))} { return }

	$gamebar itemconfigure ${pref}lighter${id} \
		-fill [::colors::lookup $Defaults(background:darker)] \
		-outline [::colors::lookup $Defaults(background:darker)] \
		;
	$gamebar itemconfigure ${pref}darker${id} \
		-fill [::colors::lookup $Defaults(background:lighter)] \
		-outline [::colors::lookup $Defaults(background:lighter)] \
		;
	set Specs(buttonstate:$id:$gamebar) "sunken"
}


proc Release {gamebar id {pref {}}} {
	variable ::scidb::scratchbaseName
	variable Specs

	if {[llength $pref] == 0 && ($id eq "-1" || $id eq $Specs(selected:$gamebar))} { return }
	if {$pref eq "close:" && $Specs(frozen:$id:$gamebar)} { return }

	if {$Specs(buttonstate:$id:$gamebar) eq "sunken"} {
		Leave $gamebar $id $pref
		if {$pref ne "close:"} {
			SetSelected $gamebar $id
		} elseif {$Specs(state:$id:$gamebar) eq "unlocked"} {
			SetState $gamebar $id locked
		} else {
			if {[lindex [::scidb::game::link? $id] 0] eq $scratchbaseName} {
				set question $mc::DiscardNewGame
			} else {
				set question $mc::DiscardChanges
			}
			set reply yes
			if {$Specs(modified:$id:$gamebar)} {
				set reply [::dialog::question -parent $gamebar -message $question]
			}
			if {$reply eq "yes"} {
				remove $gamebar $id
			}
		}
	}

	::tooltip::tooltip clear input$id
#	::tooltip::tooltip clear close:input$id
	::tooltip::tooltip on

	set Specs(buttonstate:$id:$gamebar) normal
}


proc ShowTags {gamebar id} {
	variable ::application::database::mc::T_Clipbase
	variable ::scidb::scratchbaseName
	variable ::scidb::clipbaseName
	variable Specs

	if {$id eq "-1"} { set id $Specs(selected:$gamebar) }
	if {[llength $Specs(tags:$id:$gamebar)] == 0} { return }

	set dlg $gamebar.tags
	set f [::util::makePopup $dlg]
	set bg [$f cget -background]

	lassign [::scidb::game::link? $id] base variant number
	set sink [lindex [::scidb::game::sink? $id] 0]

	if {$base ne $scratchbaseName} {
		tk::frame $f.fram -background $bg
		ttk::separator $f.sep
		if {$base eq $clipbaseName} {
			set name $T_Clipbase
		} else {
			set name [::util::databaseName $base]
		}
		append name " (#[expr {$number + 1}])"
		if {[::scidb::game::query $id modified?]} {
			set fg [::colors::lookup darkred]
		} else {
			set fg [::colors::lookup gamebar,foreground:normal]
		}
		if {$sink eq $scratchbaseName} {
			tk::label $f.fram.link -text "\uf08e" -background $bg -foreground $fg
			set size [font configure [$f.fram.link cget -font] -size]
			$f.fram.link configure -font [list FontAwesome $size bold]
			grid $f.fram.link -row 1 -column 1 -sticky e
		}
		tk::label $f.fram.nhdr -text $name -background $bg -foreground $fg -font $::font::text(text:bold)
		grid $f.fram.nhdr -row 1 -column 2 -sticky e
		grid $f.fram -row 1 -column 1 -columnspan 3 -sticky ew
		grid $f.sep  -row 2 -column 1 -columnspan 3 -sticky ew
	}

	set row 3
	foreach pair $Specs(tags:$id:$gamebar) {
		lassign $pair name value
		tk::label $f.n$name -text $name -background $bg
		tk::label $f.v$name -text $value -background $bg

		grid $f.n$name -row $row -column 1 -sticky wn
		grid $f.v$name -row $row -column 3 -sticky wn
		incr row
	}

	grid columnconfigure $f 2 -minsize $::theme::padding
	grid columnconfigure $f {0 4} -minsize 2
	grid rowconfigure $f [list 0 $row] -minsize 2

	::tooltip::popup $gamebar $dlg cursor
}


proc HideTags {gamebar} {
	::tooltip::popdown $gamebar.tags
	catch { destroy $gamebar.tags }
}


proc Setup {gamebar at id tags data} {
	variable Options
	variable Specs

	set Specs(data:$id:$gamebar) $data
	set Specs(tags:$id:$gamebar) $tags
	set Specs(buttonstate:$id:$gamebar) normal
	set Specs(atclose:$id:$gamebar) {}
	set Specs(locked:$id:$gamebar) 0
	set Specs(modified:$id:$gamebar) 0
	set Specs(state:$id:$gamebar) unlocked
	set Specs(emphasize:$id:$gamebar) 0
	set Specs(frozen:$id:$gamebar) 0

	SetTooltip $gamebar $id
	SetCountryFlag $gamebar $id $data white
	SetCountryFlag $gamebar $id $data black
	ConfigureElo $gamebar $id

	set tooltip [lindex $data 0]
	append tooltip " - "
	append tooltip [lindex $data 1]
	foreach i {2 3} {
		set item [lindex $data $i]
		if {$item ne "" && $item ne "?"} {
			if {[string length $tooltip]} { append tooltip "\n" }
			append tooltip $item
		}
	}

	::tooltip::tooltip $gamebar -item input$id $tooltip
#	::tooltip::tooltip $gamebar -item close:input$id $tooltip
	set Specs(tooltip:$id:$gamebar) $tooltip

	if {[llength $Specs(selected:$gamebar)] == 0} {
		SetSelected $gamebar $id
	} else {
		# may be set hidden in proc remove
		if {$Specs(size:$gamebar) > 1} {
			$gamebar itemconfigure digit$Specs(lookup:0:$gamebar) -state normal
		}
		if {$Options(separateColumn) && $Specs(size:$gamebar) == 2} {
			SetSelected $gamebar $id
		} else {
			Update $gamebar $id no
		}
	}
}


proc SetSelected {gamebar id} {
	variable Specs
	variable Options

	if {$id eq $Specs(selected:$gamebar)} { return }
	set oldid $Specs(selected:$gamebar)
	set Specs(selected:$gamebar) $id

	if {[llength $oldid]} {
		PrepareAsButton $gamebar $oldid
		::tooltip::tooltip include $gamebar input$oldid
	}

	::tooltip::tooltip exclude $gamebar input$id

	if {[UseSeparateColumn $gamebar]} {
		set Specs(emphasize:-1:$gamebar) $Specs(emphasize:$id:$gamebar)
		PrepareAsSunkenButton $gamebar $id
		PrepareSeparateColumn $gamebar $id
		PrepareAsHeader $gamebar -1
	} else {
		PrepareAsHeader $gamebar $id
	}

	PrepareDigit $gamebar
	Layout $gamebar

	foreach recv $Specs(receiver:$gamebar) {
		eval $recv select $id
	}
}


proc PrepareAsSunkenButton {gamebar id} {
	variable Defaults
	variable Specs

	set lighter		[::colors::lookup $Defaults(background:lighter)]
	set darker		[::colors::lookup $Defaults(background:darker)]
	set selected	[::colors::lookup $Defaults(background:active)]
	set line			$Specs(line:$gamebar)

	$gamebar itemconfigure lighter$id -fill $darker -outline $darker
	$gamebar itemconfigure darker$id -fill $lighter -outline $lighter
	$gamebar itemconfigure hyphen$id -state hidden
	if {$line != 0} { $gamebar itemconfigure blackbg$id -state hidden }
	$gamebar itemconfigure whiteInput$id -state hidden
	$gamebar itemconfigure blackInput$id -state hidden
	foreach i {1 2 3} { $gamebar itemconfigure line$i$id -state hidden }
	$gamebar itemconfigure line1Input$id -state hidden
	$gamebar itemconfigure line2Input$id -state hidden
	$gamebar itemconfigure line1bg$id -state hidden
	$gamebar itemconfigure line2bg$id -state hidden
	$gamebar itemconfigure whiteCountry$id -state hidden
	$gamebar itemconfigure blackCountry$id -state hidden
#	$gamebar itemconfigure eventCountry$id -state hidden
	$gamebar itemconfigure whiteCountryInput$id -state hidden
	$gamebar itemconfigure blackCountryInput$id -state hidden
#	$gamebar itemconfigure eventCountryInput$id -state hidden
	$gamebar itemconfigure whiteElo$id -state hidden
	$gamebar itemconfigure blackElo$id -state hidden
	if {$Specs(size:$gamebar) > 1} {
		$gamebar itemconfigure digit$id -state normal
	}
	$gamebar itemconfigure white$id -font $::font::text(text:normal)
	$gamebar itemconfigure black$id -font $::font::text(text:normal)
	$gamebar raise blackbg$id
	$gamebar raise black$id
	$gamebar raise digit$id
	$gamebar raise close$id
	$gamebar raise input$id

	foreach item {bg whitebg blackbg} {
		$gamebar itemconfigure $item$id -fill $selected -outline $selected
	}
}


proc PrepareAsButton {gamebar id} {
	variable Defaults
	variable Specs

	set lighter	[::colors::lookup $Defaults(background:lighter)]
	set darker	[::colors::lookup $Defaults(background:darker)]
	set normal	[::colors::lookup $Defaults(background:normal)]
	set line		$Specs(line:$gamebar)

	::tooltip::tooltip include $gamebar input$id
	::tooltip::tooltip include $gamebar close:input$id
	$gamebar itemconfigure lighter$id -fill $lighter -outline $lighter
	$gamebar itemconfigure darker$id -fill $darker -outline $darker
	if {$Specs(size:$gamebar) > 1} {
		$gamebar itemconfigure digit$id -state normal
	}
	if {$line != 0} { $gamebar itemconfigure blackbg$id -state hidden }
	$gamebar itemconfigure whiteInput$id -state hidden
	$gamebar itemconfigure blackInput$id -state hidden
	foreach i {1 2 3} { $gamebar itemconfigure line$i$id -state hidden }
	$gamebar itemconfigure line1Input$id -state hidden
	$gamebar itemconfigure line2Input$id -state hidden
	$gamebar itemconfigure line1bg$id -state hidden
	$gamebar itemconfigure line2bg$id -state hidden
	foreach item {bg whitebg blackbg} {
		$gamebar itemconfigure $item$id -fill $normal -outline $normal
	}
	$gamebar itemconfigure white$id -font $::font::text(text:normal)
	$gamebar itemconfigure black$id -font $::font::text(text:normal)
	$gamebar itemconfigure whiteCountry$id -state hidden
	$gamebar itemconfigure blackCountry$id -state hidden
#	$gamebar itemconfigure eventCountry$id -state hidden
	$gamebar itemconfigure whiteCountryInput$id -state hidden
	$gamebar itemconfigure blackCountryInput$id -state hidden
#	$gamebar itemconfigure eventCountryInput$id -state hidden
	$gamebar itemconfigure whiteElo$id -state hidden
	$gamebar itemconfigure blackElo$id -state hidden
	$gamebar itemconfigure hyphen$id -state hidden
	$gamebar raise blackbg$id
	$gamebar raise black$id
	$gamebar raise line1$id
	$gamebar raise line2$id
	$gamebar raise line3$id
	$gamebar raise digit$id
	$gamebar raise close$id
	$gamebar raise input$id
}


proc PrepareAsHeader {gamebar id} {
	variable Defaults
	variable Options
	variable Specs

	if {$Specs(emphasize:$id:$gamebar)} { set color emphasize } else { set color selected }

	set darker		[::colors::lookup $Defaults(background:darker)]
	set shadow		[::colors::lookup $Defaults(background:shadow)]
	set selected	[::colors::lookup $Defaults(background:$color)]

	if {$id eq "-1"} {
		foreach item {	white black lighter darker bg whitebg
							whiteInput blackInput line1 line1Input
							line1bg line2 line2Input line2bg line3
							input} {
			$gamebar itemconfigure ${item}-1 -state normal
		}
		foreach item {close:lighter close:darker close:bg} {
			$gamebar itemconfigure ${item}-1 -state normal
		}
		foreach item {digit close:icon close:input} {
			$gamebar itemconfigure ${item}-1 -state hidden
		}
	}

	$gamebar itemconfigure blackbg$id -state normal
	foreach i {1 2 3} { $gamebar itemconfigure line$i$id -state normal }
	$gamebar itemconfigure line1Input$id -state normal
	$gamebar itemconfigure line2Input$id -state normal
	$gamebar itemconfigure line1bg$id -state normal
	$gamebar itemconfigure line2bg$id -state normal
	foreach item {bg whitebg blackbg line1bg line2bg} {
		$gamebar itemconfigure $item$id -fill $selected -outline $selected
	}
	$gamebar itemconfigure white$id -font $::font::text(text:bold)
	$gamebar itemconfigure black$id -font $::font::text(text:bold)
	if {$Options(separateLines)} { set state hidden } else { set state normal }
	$gamebar itemconfigure hyphen$id -state $state
	if {$Options(separateLines)} { set state normal } else { set state hidden }
	$gamebar itemconfigure whiteCountry$id -state $state
	$gamebar itemconfigure blackCountry$id -state $state
#	$gamebar itemconfigure eventCountry$id -state $state
	$gamebar itemconfigure whiteCountryInput$id -state $state
	$gamebar itemconfigure blackCountryInput$id -state $state
#	$gamebar itemconfigure eventCountryInput$id -state $state
	$gamebar itemconfigure whiteInput$id -state normal
	$gamebar itemconfigure blackInput$id -state normal
	$gamebar itemconfigure lighter$id -fill $darker -outline $darker
	$gamebar itemconfigure darker$id -fill $shadow -outline $shadow
	ConfigureElo $gamebar $id

	$gamebar raise digit$id
	$gamebar raise input$id
	$gamebar raise whiteCountryInput$id
	$gamebar raise blackCountryInput$id
#	$gamebar raise eventCountryInput$id
	$gamebar raise whitebg$id
	$gamebar raise white$id
	$gamebar raise whiteInput$id
	$gamebar raise blackbg$id
	$gamebar raise black$id
	$gamebar raise blackInput$id
	$gamebar raise line1bg$id
	$gamebar raise line2bg$id
	$gamebar raise line3bg$id
	$gamebar raise line1$id
	$gamebar raise line2$id
	$gamebar raise line3$id
	$gamebar raise line1Input$id
	$gamebar raise line2Input$id
	$gamebar raise close$id

	if {$id eq $Specs(selected:$gamebar)} {
		::tooltip::tooltip exclude $gamebar -item input$id
#		::tooltip::tooltip exclude $gamebar close:input$id
		after 10 { ::tooltip::hide }
	}
}


proc PrepareSeparateColumn {gamebar id} {
	variable Options
	variable Specs

	$gamebar itemconfigure line1-1 -text [$gamebar itemcget line1$id -text]
	$gamebar itemconfigure line2-1 -text [$gamebar itemcget line2$id -text]
	$gamebar itemconfigure line3-1 -text [$gamebar itemcget line3$id -text]
	$gamebar itemconfigure white-1 -text [$gamebar itemcget white$id -text]
	$gamebar itemconfigure black-1 -text [$gamebar itemcget black$id -text]

	if {$Options(separateLines)} {
		foreach {side eloIdx} {white 8 black 9} {
			set country [$gamebar itemcget ${side}Country${id} -image]
			if {[string length $country]} {
				$gamebar itemconfigure ${side}Country-1 -image $country
				$gamebar itemconfigure ${side}Country-1 -state normal
			} else {
				$gamebar itemconfigure ${side}Country-1 -state hidden
			}
			if {[lindex $Specs(data:$id:$gamebar) $eloIdx]} { set state normal } else { set state hidden }
			$gamebar itemconfigure ${side}Elo-1 -state $state
		}
#		set country [$gamebar itemcget eventCountry${id} -image]
#		if {[string length $country]} {
#			$gamebar itemconfigure eventCountry-1 -image $country
#			$gamebar itemconfigure eventCountry-1 -state normal
#		} else {
#			$gamebar itemconfigure eventCountry-1 -state hidden
#		}
	} else {
		$gamebar itemconfigure whiteCountry-1 -state hidden
		$gamebar itemconfigure blackCountry-1 -state hidden
#		$gamebar itemconfigure eventCountry-1 -state hidden
		$gamebar itemconfigure whiteElo-1 -state hidden
		$gamebar itemconfigure blackElo-1 -state hidden
	}
}


proc ShowSeparateColumn {gamebar {flag -1}} {
	variable Options
	variable Specs

	if {$flag >= 0} {
		if {$flag == $Options(separateColumn)} { return }
		set Options(separateColumn) $flag
	}

	if {[UseSeparateColumn $gamebar]} {
		if {[llength $Specs(selected:$gamebar)]} {
			PrepareAsSunkenButton $gamebar $Specs(selected:$gamebar)
			PrepareSeparateColumn $gamebar $Specs(selected:$gamebar)
		}
		PrepareAsHeader $gamebar -1
	} else {
		if {[llength $Specs(selected:$gamebar)]} {
			PrepareAsHeader $gamebar $Specs(selected:$gamebar)
		}
		foreach item [$gamebar find withtag all-1] {
			$gamebar itemconfigure $item -state hidden
		}
	}

	PrepareDigit $gamebar
	Layout $gamebar
}


proc AddGameMenuEntries {gamebar m addSaveMenu addGameHistory clearHistory remove} {
	variable ::game::history::mc::GameHistory
	variable ::scidb::clipbaseName
	variable ::scidb::scratchbaseName
	variable icon::15x15::digit

	if {[::game::historyIsEmpty?]} {
		set clearHistory 0
	}

	set sub $m.__history__
	menu $sub -tearoff 0
	$sub configure -disabledforeground black
	set parent [winfo parent $m]

	if {$addGameHistory} {
		set headerScript {
			upvar sub n

			uplevel { incr count }

			$n add command \
				-label [::util::databaseName $base] \
				-background [::colors::lookup table,menu:headerbackground] \
				-foreground [::colors::lookup table,menu:headerforeground] \
				-activebackground [::colors::lookup table,menu:headerbackground] \
				-activeforeground [::colors::lookup table,menu:headerforeground] \
				-font $::table::options(menu:headerfont) \
				-state disabled \
				;
		}

		set gameScript {
			upvar sub n

			set lbl ""

			append lbl [lindex $tags 4]
			append lbl " - "
			append lbl [lindex $tags 5]

			$n add command \
				-label $lbl \
				-command [list ::game::openGame [winfo parent $n] $index] \
				;
		}

		set count 0
		::game::traverseHistory $headerScript $gameScript

		if {$count > 0} {
			if {$clearHistory == 1} {
				$sub add separator
				$sub add command \
					-label " $::game::mc::ClearHistory" \
					-image $::icon::16x16::clear \
					-compound left \
					-command ::game::clearHistory \
					;
			}
			$m add cascade \
				-menu $sub \
				-label " $GameHistory" \
				-image $::icon::16x16::folder \
				-compound left \
				;
		} else {
			destroy $sub
			set clearHistory 0
		}
	}

	$m add command \
		-label " $mc::GameNew" \
		-accelerator "Ctrl+X" \
		-image $::icon::16x16::documentNew \
		-compound left \
		-command [list ::menu::gameNew $parent] \
		;

	set sub [menu $m.newGame -tearoff 0]
	addVariantsToMenu $parent $sub 1
	$m add cascade \
		-menu $sub \
		-label " $mc::GameNew" \
		-image $::icon::16x16::documentNewAlt \
		-compound left \
		;

	set actual [::scidb::db::get name]
	set position [::scidb::game::current]
	set currentVariant [::scidb::game::query Variant?]
	lassign [::scidb::game::link? $position] base variant index
	set sink [lindex [::scidb::game::sink? $position] 0]

	if {$actual eq $scratchbaseName || [::scidb::db::count games] == 0} {
		set state disabled
	} else {
		set state normal
	}
	$m add command \
		-label " $mc::LoadGameNumber..." \
		-image $::icon::16x16::none \
		-compound left \
		-command [namespace code [list LoadGameNumber $parent]] \
		-state $state
		;
	$m add command \
		-label " $::import::mc::ImportPgnGame" \
		-image $::icon::16x16::filetypePGN \
		-compound left \
		-command [list ::application::pgn::importGame $parent] \
		-accel "$::mc::Key(Ctrl)-$::application::board::mc::Accel(import-game)" \
		;
	
	if {$addSaveMenu && ![::game::trialMode?]} {
		$m add separator
		set variant [::util::toMainVariant $variant]
		unset -nocomplain state

		set actual [::scidb::db::get name]

		if {$base ne $scratchbaseName} {
			if {	$index >= 0
				&& [::scidb::db::get open? $base $variant]
				&& ![::scidb::db::get readonly? $base $variant]} {
				set state normal
			} else {
				set state disabled
			}

			set name [::util::databaseName $base]
			set number [expr {$index + 1}]

			$m add command \
				-label " [format $mc::ReplaceGame $name]" \
				-image $::icon::16x16::save \
				-compound left \
				-command [namespace code [list ReplaceGame $parent $base $variant $position $number]] \
				-state $state \
				-accel "$::mc::Key(Ctrl)-$::application::board::mc::Accel(replace-game)" \
				;

			if {![::scidb::game::query modified?]} { set state disabled }
			$m add command \
				-label " [format $mc::ReplaceMoves $name]" \
				-image $::icon::16x16::save \
				-compound left \
				-command [namespace code [list ReplaceMoves $parent $base $variant $position $number]] \
				-state $state \
				-accel "$::mc::Key(Ctrl)-$::application::board::mc::Accel(replace-moves)" \
				;
		}

		if {	$actual eq $scratchbaseName
			|| [::scidb::db::get readonly? $actual]
			|| $variant ni [::scidb::db::get variants $actual]} {
			set state disabled
		} else {
			set state normal
		}
		$m add command \
			-label " [format $mc::AddNewGame [::util::databaseName $actual]]" \
			-image $::icon::16x16::saveAs \
			-compound left \
			-command [list ::dialog::save::open $parent $actual $variant $position] \
			-state $state \
			-accel "$::mc::Key(Ctrl)-$::application::board::mc::Accel(add-new-game)" \
			;

		menu $m.save
		set state disabled
		if {[addDestinationsForSaveToMenu $parent $m.save 1] > 1 || $actual ne $clipbaseName} {
			set state normal
		}
		$m add cascade \
			-menu $m.save \
			-label " [format $mc::AddNewGame {}]" \
			-image $::icon::16x16::saveAs \
			-compound left \
			-state $state \
			;

		::application::database::addRepertoireGameEntry $parent $m 0 $currentVariant
		::application::database::addRepertoireLineEntry $parent $m 0 $currentVariant

		if {$base ne $scratchbaseName && $sink ne $scratchbaseName} {
			if {[::scidb::game::query modified?]} { set state normal } else { set state disabled }
			$m add command \
				-label " $mc::ReloadCurrentGame" \
				-image $::icon::16x16::reload \
				-compound left \
				-command [namespace code [list ReloadCurrentGame $parent]] \
				-state $state \
				;
		}
	}

	if {$position < 9 && $addSaveMenu} {
		$m add separator
		set idList [lsort -integer [getIdList $gamebar]]
		foreach id $idList {
			append players($id) [lindex [GetPlayerInfo $id white] 0]
			append players($id) " \u2013 "
			append players($id) [lindex [GetPlayerInfo $id black] 0]
		}
		$m add command \
			-label " $mc::CopyThisGameToClipbase" \
			-image $::icon::16x16::none \
			-compound left \
			-command [namespace code [list CopyThisGameToClipbase $parent $position]] \
			;
		$m add command \
			-label " $mc::CopyThisGameToClipboard" \
			-image $::icon::16x16::clipboardIn \
			-compound left \
			-command [namespace code [list CopyThisGameToClipboard $parent $position]] \
			;

		set clipbaseState normal
		if {[::scidb::db::count games $clipbaseName $variant] == 0} { set clipbaseState disabled }
		$m add command \
			-label " $mc::PasteLastClipbaseGame" \
			-image $::icon::16x16::none \
			-compound left \
			-command [namespace code [list PasteFromClipbase $gamebar $position]] \
			-state $clipbaseState \
			;
		if {[llength $idList] <= 1} { set state disabled } else { set state normal }
		set sub [menu $m.pasteFrom]
		foreach id $idList {
			if {$id != $position} {
				$sub add command \
					-label " $players($id)" \
					-image $digit([expr {$id + 1}]) \
					-compound left \
					-command [namespace code [list PasteGameFrom $parent $id $position]] \
					;
			}
		}
		$m add cascade \
			-menu $sub \
			-label " $mc::PasteGameFrom" \
			-image $::icon::16x16::none \
			-compound left \
			-state $state \
			;

		$m add command \
			-label " $mc::ExportThisGame..." \
			-image $::icon::16x16::fileExport \
			-compound left \
			-command [namespace code [list exportGame $parent $position]] \
			-accel "$::mc::Key(Ctrl)-$::application::board::mc::Accel(export-game)" \
			;

		set state $clipbaseState
		if {[::merge::alreadyMerged $position clipbase]} { set state disabled }
		set cmd [list ::merge::openDialog $parent $position clipbase]
		$m add command \
			-label " $::merge::mc::MergeLastClipbaseGame..." \
			-image $::icon::16x16::none \
			-compound left \
			-command $cmd \
			-state $state \
			;
		set sub [menu $m.mergeFrom]
		set count 0
		foreach id $idList {
			if {$id != $position && ![::merge::alreadyMerged $position $id]} {
				$sub add command \
					-label " $players($id)" \
					-image $digit([expr {$id + 1}]) \
					-compound left \
					-command [list ::merge::openDialog $parent $position $id] \
					;
				incr count
			}
		}
		if {$count} { set state normal } else { set state disabled }
		$m add cascade \
			-menu $sub \
			-label " $::merge::mc::MergeGameFrom..." \
			-image $::icon::16x16::none \
			-compound left \
			-state $state \
			;
	}

	if {$clearHistory == 2} {
		$m add separator
		if {$remove >= 0} {
			$m add command \
				-label " $::game::mc::RemoveSelectedGame" \
				-image $::icon::16x16::remove \
				-compound left \
				-command [list ::game::removeHistoryEntry $remove] \
				;
		}
		$m add command \
			-label " $::game::mc::ClearHistory" \
			-image $::icon::16x16::clear \
			-compound left \
			-command ::game::clearHistory \
			;
	}
}


proc PasteClipboardContent {parent} {
	# TODO
	puts "Not yet implemented"
}


proc ReplaceGame {parent base variant position number} {
	if {[::game::verify $parent $position $number]} {
		::dialog::save::open $parent $base $variant $position $number
	}
}


proc ReplaceMoves {parent base variant position number} {
	if {[::game::verify $parent $position $number]} {
		::application::pgn::replaceMoves $parent $base $variant $position $number
	}
}


proc CheckIfModified {parent position} {
	if {![::scidb::game::query $position modified?]} { return false }
	set reply [::dialog::question -parent $parent -message $mc::DiscardChanges]
	return [expr {$reply eq "no"}]
}


proc WhichVersion {parent title} {
	variable Mode_

	if {![info exists Mode_]} { set Mode_ original }

	set dlg [tk::toplevel $parent.whichVersion -class Dialog]
	set top [ttk::frame $dlg.top -takefocus 0]
	pack $top -fill both
	ttk::radiobutton $top.original \
		-text $mc::OriginalVersion \
		-value original \
		-variable [namespace current]::Mode_ \
		;
	ttk::radiobutton $top.modified \
		-text $mc::ModifiedVersion \
		-value modified \
		-variable [namespace current]::Mode_ \
		;
	grid $top.original -row 1 -column 1 -sticky w
	grid $top.modified -row 3 -column 1 -sticky w
	grid columnconfigure $top {0 2 4} -minsize $::theme::padx
	grid rowconfigure $top {0 2 4} -minsize $::theme::pady

	::widget::dialogButtons $dlg {ok}
	$dlg.ok configure -command [list destroy $dlg]

	wm protocol $dlg WM_DELETE_WINDOW [list bell]
	wm transient $dlg [winfo toplevel $parent]
	wm title $dlg $title
	wm resizable $dlg false false

	wm withdraw $dlg
	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	focus $top.original
	::ttk::grabWindow $dlg
	tkwait window $dlg
	::ttk::releaseGrab $dlg

	return $Mode_
}


proc CopyThisGameToClipbase {parent position} {
	variable ::scidb::scratchbaseName
	variable ::scidb::clipbaseName
	variable mode

	lassign [::scidb::game::link? $position] base variant index
	set sink [lindex [::scidb::game::sink? $position] 0]
	set mode original

	if {[::scidb::game::query $position modified?]} {
		if {$base ne $scratchbaseName} {
			if {$sink eq $scratchbaseName} {
				set msg $mc::WillCopyModifiedGame
				set reply [::dialog::question -parent $parent -message $msg -default yes]
				if {$reply eq "no"} { return }
				set mode modified
			} else {
				set mode [WhichVersion $parent $mc::CopyGame]
			}
		} else {
			set mode modified
		}
	}

	::scidb::game::copy game $clipbaseName $position $mode
}


proc CopyThisGameToClipboard {parent position} {
	variable ::scidb::scratchbaseName
	variable mode

	lassign [::scidb::game::link? $position] base variant index
	set sink [lindex [::scidb::game::sink? $position] 0]
	set mode original

	if {[::scidb::game::query $position modified?]} {
		if {$base ne $scratchbaseName} {
			if {$sink eq $scratchbaseName} {
				set mode modified
			} else {
				set mode [WhichVersion $parent $mc::CopyGame]
			}
		} else {
			set mode modified
		}
	}

	set flags [::export::getPgnFlags]
	set result [string trim [::scidb::game::toPGN $mode -position $position -flags $flags]]

	if {[string length $result]} {
		::clipboard::selectText $result
	}
}


proc PasteFromClipbase {parent position} {
	if {![CheckIfModified $parent $position]} { ::scidb::game::paste clipbase $position }
}


proc PasteGameFrom {parent from to} {
	if {![CheckIfModified $parent $to]} { ::scidb::game::paste $from $to }
}


proc ReloadCurrentGame {parent} {
	set reply [::dialog::question -parent $parent -message $::application::mc::ThrowAwayAllChanges]
	if {$reply eq "yes"} { ::scidb::game::reload }
}


proc LoadGameNumber {parent} {
	variable Action_

	set dlg [tk::toplevel $parent.descr -class Dialog]
	set top [ttk::frame $dlg.top -borderwidth 0 -takefocus 0]
	pack $top -fill both

	ttk::label $top.enter -text "$mc::EnterGameNumber:"
	set max [::scidb::db::count games [::scidb::db::get variant?]]
	set cmd [namespace code [list CheckOkButton $dlg $max]]
	::ttk::spinbox $top.number -from 1 -to $max -width 10 -exportselection false 
	$top.number delete 0 end
	$top.number insert 0 1
	::validate::spinboxInt $top.number -clamp no -vcmd $cmd
	::theme::configureSpinbox $top.number

	grid $top.enter  -row 1 -column 1
	grid $top.number -row 1 -column 3
	grid rowconfigure $top {0 2} -minsize $::theme::pady
	grid columnconfigure $top {0 2 4} -minsize $::theme::padx

	::widget::dialogButtons $dlg {ok cancel}
	$dlg.cancel configure -command [list set [namespace current]::Action_ "cancel"]
	$dlg.ok configure -command [list set [namespace current]::Action_ "ok"]

	wm protocol $dlg WM_DELETE_WINDOW [$dlg.cancel cget -command]
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm title $dlg $mc::LoadGameNumber
	wm resizable $dlg false false
	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	focus $top.number
	::ttk::grabWindow $dlg
	tkwait variable [namespace current]::Action_
	::ttk::releaseGrab $dlg
	::widget::busyCursor on

	if {$Action_ eq "ok"} {
		set number [string trim [$top.number get]]
		set dlg [winfo toplevel $top.number]
		set position [::scidb::game::current]
		if {[::application::pgn::unlocked? $position]} {
			set view [lindex [::game::getSourceInfo $position] 2]
		} else {
			set view -1
		}
		::game::new [winfo parent $dlg] \
			-base [::scidb::db::get name] \
			-variant [::scidb::db::get variant?] \
			-number [expr {$number - 1}] \
			-view $view \
			;
	}

	::widget::busyCursor off
	destroy $dlg
}


proc CheckOkButton {dlg max value valid} {
	if {$valid && [string is integer -strict $value] && $value >= 1 && $value <= $max} {
		set state normal
	} else {
		set state disabled
	}
	$dlg.ok configure -state $state
}


proc GetSource {id} {
	lassign [::scidb::game::sink? $id] base variant index
	set variant [::util::toMainVariant $variant]
	return [list $base $variant $index]
}


proc PopupEventMenu {gamebar id} {
	variable Specs

	set menu $gamebar.menu
	catch { destroy $menu }
	menu $menu -tearoff 0

	lassign [::scidb::game::link? $id] base variant _
	set variant [::util::toMainVariant $variant]

	if {[::scidb::db::get open? $base $variant]} {
		set Specs(event:locked) 1
		set name [GetEventName $id]
		if {[string length $name]} {
			lassign [GetSource $id] base variant index
			::eventtable::popupMenu $gamebar $menu $base $variant 0 $index game
			$menu add separator
		}
	}

	BuildMenu $gamebar $id {} $menu
}


proc PopupSiteMenu {gamebar id} {
	variable Specs

	set menu $gamebar.menu
	catch { destroy $menu }
	menu $menu -tearoff 0

	set Specs(site:locked) 1
	lassign [::scidb::game::link? $id] base variant _
	set variant [::util::toMainVariant $variant]
	set site [lindex $Specs(data:$id:$gamebar) 3]
	if {[::web::isWebLink $site]} {
		lassign [GetSource $id] base variant index
		::sitetable::popupMenu $gamebar $menu $site
		$menu add separator
	}

	BuildMenu $gamebar $id {} $menu
}


proc PopupPlayerMenu {gamebar id side} {
	variable Specs

	set menu $gamebar.menu
	catch { destroy $menu }
	menu $menu -tearoff 0

	lassign [::scidb::game::link? $id] base variant _
	set variant [::util::toMainVariant $variant]

	if {[::scidb::db::get open? $base $variant]} {
		set Specs(player:locked) 1
		set info [GetPlayerInfo $id $side]
		set name [lindex $info 0]
		if {$name eq "?" || $name eq "-"} { set name "" }
		if {[string length $name]} {
			lassign [GetSource $id] base variant gameIndex
			::playertable::popupMenu $menu $base $variant $info [list $gameIndex $side]
			$menu add separator
		}
	}

	BuildMenu $gamebar $id $side $menu
}


proc PopupMenu {gamebar {id -1}} {
	set menu $gamebar.menu
	catch { destroy $menu }
	menu $menu -tearoff 0
	# C12: the one game-tab context menu.
	if {[llength [info commands ::context::Build]]} {
		set object [dict create parent $gamebar id $id gameSlot $id]
		if {[::context::Build C12 $menu $object]} {
			tk_popup $menu {*}[winfo pointerxy $gamebar]
			return
		}
		destroy $menu
		return
	}
	BuildMenu $gamebar $id {} $menu
}


proc BuildMenu {gamebar id side menu} {
	variable Specs
	variable Options

	HideTags $gamebar
	set sid $Specs(selected:$gamebar)
	set current [expr {$id == ($Specs(size:$gamebar) == 1 ? $sid : -1)}]
	set addsep {}

	set end [$menu index end]
	AddGameMenuEntries $gamebar $menu [expr {$current && $Specs(size:$gamebar) > 0}] 1 1 -1
	if {[$menu index end] ne $end} { set addsep [list $menu add separator] }

	if {$Specs(size:$gamebar) > 0} {
		eval $addsep
		set addsep {}
	
		if {$current && [lindex [::scidb::game::sink? $id] 0] ne $::scidb::scratchbaseName} {
			lassign [::scidb::game::link? $id] base variant index
			set variant [::util::toMainVariant $variant]
			if {[::scidb::db::get open? $base $variant] && ![::scidb::db::get readonly? $base $variant]} {
				set flag [::scidb::db::get deleted? $index -1 $base]
				if {$flag} { set var UndeleteGame } else { set var DeleteGame }
				$menu add command \
					-compound left \
					-image $::icon::16x16::remove \
					-label " [set ::gamestable::mc::$var]" \
					-command [namespace code [list ::gamestable::deleteGame $base $variant $index]] \
					;
				::gamestable::addGameFlagsMenuEntry $menu $base $variant -1 $index
				set addsep [list $menu add separator]
			}
		}

		# C1: explain the game currently on the board (the selected row).
		if {$current && [llength [info commands ::application::ai::explainSelection]]} {
			eval $addsep
			set addsep {}
			$menu add command \
				-compound left \
				-image $::icon::16x16::none \
				-label " $mc::ExplainGame" \
				-command [namespace code [list ExplainGame [winfo parent $menu]]] \
				;
			set addsep [list $menu add separator]
		}

		if {$id == -1} { set lid $sid } else { set lid $id }
		if {	!$Specs(modified:$lid:$gamebar)
			&& !$Specs(frozen:$lid:$gamebar)
			&& $Specs(state:$lid:$gamebar) ne "modified"} {
			eval $addsep
			set addsep {}
			if {$Specs(locked:$lid:$gamebar)} {
				set count 0
				foreach key [array names Specs -glob locked:*:$gamebar] {
					if {$Specs($key)} { incr count }
				}
				if {$count == $Specs(size:$gamebar)} {
					$menu add command \
						-compound left \
						-image $icon::15x15::close(unlocked) \
						-label " $mc::UnlockGame" \
						-command [namespace code [list SetState $gamebar $lid unlocked]] \
						;
					set addsep [list $menu add separator]
				}
			} else {
				$menu add command \
					-compound left \
					-image $icon::15x15::close(locked) \
					-label " $mc::LockGame" \
					-command [namespace code [list SetState $gamebar $lid locked]] \
					;
					set addsep [list $menu add separator]
			}
		}

#		currently not working
#		foreach {num text} [list 0 $mc::Players 2 $mc::Event 3 $mc::Site] {
#			$menu add radiobutton \
#				-label $text \
#				-value $num \
#				-variable [namespace current]::Specs(line:$gamebar) \
#				-command [namespace code [list SelectLine $gamebar]]
#		}
#		::theme::configureRadioEntry $menu
#		$menu add separator

		eval $addsep
		menu $menu.configuration -tearoff no
		$menu add cascade \
			-label " $::mc::Configuration" \
			-image $icon::16x16::none \
			-compound left \
			-menu $menu.configuration \
			;

		menu $menu.configuration.alignment -tearoff no
		$menu.configuration add cascade -label $::mc::Alignment -menu $menu.configuration.alignment

		foreach item {left center} {
			set text [set ::toolbar::mc::[string toupper $item 0 0]]
			$menu.configuration.alignment add radiobutton \
				-label $text \
				-value $item \
				-variable [namespace current]::Options(alignment) \
				-command [namespace code [list Layout $gamebar]] \
				;
			::theme::configureRadioEntry $menu.configuration.alignment
		}

		menu $menu.configuration.layout -tearoff no
		$menu.configuration add cascade -label $::mc::Layout -menu $menu.configuration.layout

		if {$Options(separateColumn)} { set state disabled } else { set state normal }

		$menu.configuration.layout add checkbutton \
			-label $mc::SeparateHeader \
			-onvalue 1 \
			-offvalue 0 \
			-variable [namespace current]::Options(separateColumn) \
			-command [namespace code [list ShowSeparateColumn $gamebar]] \
			;
		::theme::configureCheckEntry $menu.configuration.layout
		$menu.configuration.layout add checkbutton \
			-label $mc::ShowActiveAtBottom \
			-onvalue 1 \
			-offvalue 0 \
			-variable [namespace current]::Options(selectedAtBottom) \
			-command [namespace code [list ShowAtBottom $gamebar]] \
			-state $state \
			;
		::theme::configureCheckEntry $menu.configuration.layout
		$menu.configuration.layout add checkbutton \
			-label $mc::ShowPlayersOnSeparateLines \
			-onvalue 1 \
			-offvalue 0 \
			-variable [namespace current]::Options(separateLines) \
			-command [namespace code [list ShowAtSeparateLines $gamebar]] \
			;
		::theme::configureCheckEntry $menu.configuration.layout
	}

	if {[$menu index end] eq "none"} { return }

	if {$Specs(player:locked)} {
		bind $menu <<MenuUnpost>> [namespace code [list LeavePlayer $gamebar $id $side yes]]
	} elseif {$Specs(event:locked)} {
		bind $menu <<MenuUnpost>> [namespace code [list LeaveEvent $gamebar $id yes]]
	} elseif {$Specs(site:locked)} {
		bind $menu <<MenuUnpost>> [namespace code [list LeaveSite $gamebar $id yes]]
	}

	tk_popup $menu {*}[winfo pointerxy .]
}


proc ShowAtSeparateLines {gamebar} {
	variable Specs
	variable Options

	if {[UseSeparateColumn $gamebar]} { set id -1 } else { set id $Specs(selected:$gamebar) }

	if {$Options(separateLines)} { set state hidden } else { set state normal }
	$gamebar itemconfigure hyphen$id -state $state

	if {$Options(separateLines)} { set state normal } else { set state hidden }
	$gamebar itemconfigure whiteCountry$id -state $state
	$gamebar itemconfigure blackCountry$id -state $state
	$gamebar itemconfigure whiteCountryInput$id -state $state
	$gamebar itemconfigure blackCountryInput$id -state $state
	ConfigureElo $gamebar $id

	Layout $gamebar
}


proc ShowAtBottom {gamebar} {
	PrepareDigit $gamebar
	Layout $gamebar
}


proc PrepareDigit {gamebar} {
	variable Options
	variable Specs

	if {($Options(separateColumn) || $Options(selectedAtBottom)) && $Specs(size:$gamebar) > 1} {
		set state normal
	} else {
		set state hidden
	}
	$gamebar itemconfigure digit$Specs(selected:$gamebar) -state $state
}


proc SelectLine {gamebar} {
	variable Specs

	for {set i 0} {$i < $Specs(size:$gamebar)} {incr i} {
		UpdateLine $gamebar $Specs(lookup:$i:$gamebar)
	}

	Layout $gamebar
}


proc UpdateLine {gamebar id} {
	variable Specs
	variable Options

	set line $Specs(line:$gamebar)
	if {$line == 0} { set state normal } else { set state hidden }
	set white [lindex $Specs(data:$id:$gamebar) $line]
	if {$white eq ""} { set white "?" }
	set black [lindex $Specs(data:$id:$gamebar) 1]
	if {$black eq ""} { set text "?" }
	$gamebar itemconfigure white$id -text $white
	$gamebar itemconfigure black$id -text $black

	if {[UseSeparateColumn $gamebar] || $id ne $Specs(selected:$gamebar)} {
		$gamebar itemconfigure black$id -state $state
		$gamebar itemconfigure blackbg$id -state $state
		$gamebar itemconfigure blackInput$id -state $state
	}

	if {$id eq $Specs(selected:$gamebar)} {
		$gamebar itemconfigure white-1 -text $white
		$gamebar itemconfigure black-1 -text $black
	}
}


proc MakeData {gamebar id tags {update no}} {
	variable ::scidb::scratchbaseName
	variable Specs

	lassign {"N.N." "N.N." "?" "?" "" "" "" "" 0 0} \
		white black event site date eventCountry whiteCountry blackCountry whiteElo blackElo
	lassign [::scidb::game::link? $id] base _ _

	if {$base eq $scratchbaseName && !$update} {
		if {![info exists Specs(count:$id:$gamebar)]} {
			set Specs(count:$id:$gamebar) [incr Specs(counter:game)]
		}

		set white $mc::NewGameFstPart
		set black $mc::NewGameSndPart
		set event "$::mc::Number $Specs(count:$id:$gamebar)"
		set site  [::locale::formatTime [::game::time? $id]]
		set date  ""
	} else {
		foreach pair $tags {
			lassign $pair name value

			switch $name {
				White				{ set white [Normalize [normalizePlayer $value] $white] }
				Black				{ set black [Normalize [normalizePlayer $value] $black] }
				Event				{ set event [Normalize $value $event] }
				Site				{ set site [Normalize $value $site] }
				Date				{ set date $value }
				EventCountry	{ set eventCountry $value }
			}
		}

		set whiteCountry [::scidb::game::query $id country white]
		set blackCountry [::scidb::game::query $id country black]
		set whiteElo [::scidb::game::query $id elo white]
		set blackElo [::scidb::game::query $id elo black]
		set eventDate [::locale::formatNormalDate $date]

		set date ""
		if {[string length $eventDate]} {
			if {[string length $site]} { append date ", " }
			append date $eventDate
		}
	}

	return [list $white $black $event $site $date $eventCountry \
					$whiteCountry $blackCountry $whiteElo $blackElo]
}


proc Update {gamebar id {update yes}} {
	variable Specs
	variable Options

	if {$id >= 9} { return }

	set tags [::scidb::game::tags $id]
	set data [MakeData $gamebar $id $tags $update]

	set Specs(data:$id:$gamebar) $data
	set Specs(tags:$id:$gamebar) $tags

	$gamebar itemconfigure line1$id -text [lindex $data 2]
	$gamebar itemconfigure line2$id -text [lindex $data 3]
	$gamebar itemconfigure line3$id -text [lindex $data 4]
	$gamebar itemconfigure whiteElo$id -text [lindex $data 8]
	$gamebar itemconfigure blackElo$id -text [lindex $data 9]

	$gamebar itemconfigure line1-1 -text [lindex $data 2]
	$gamebar itemconfigure line2-1 -text [lindex $data 3]
	$gamebar itemconfigure line3-1 -text [lindex $data 4]
	$gamebar itemconfigure whiteElo-1 -text [lindex $data 8]
	$gamebar itemconfigure blackElo-1 -text [lindex $data 9]

	SetCountryFlag $gamebar $id $data white
	SetCountryFlag $gamebar $id $data black
	ConfigureElo $gamebar $id

	UpdateLine $gamebar $id
	Layout $gamebar
}


proc Layout {gamebar} {
	variable Specs
	variable Defaults
	variable Options
	variable icon::15x15::close
	variable icon::15x15::digit

	if {$Specs(size:$gamebar) == 0} {
		set barHeight 1
	} else {
		switch _[::theme::currentTheme] {
			_default	{ set scrollWidth 16 }
			_clam		{ set scrollWidth 15 }
			_alt		{ set scrollWidth 17 }
			default	{ set scrollWidth 17 }
		}

		set spacewidth		[font measure $::font::text(text:normal) " "]
		set useSepColumn	[UseSeparateColumn $gamebar]
		set line				$Specs(line:$gamebar)
		set padx				$Defaults(padx)
		set pady				$Defaults(pady)
		set digitWidth		[image width $digit(1)]
		set digitHeight	[image height $digit(1)]
		set closeWidth		[image width $close(unlocked)]
		set closeHeight	[image height $close(unlocked)]
		set closePad		[expr {($scrollWidth - $closeWidth)/2}]
		set rowWidth		[winfo width $gamebar]
		set lineWidth		[expr {$rowWidth - $scrollWidth}]
		set closeOffsX		[expr {$rowWidth - $scrollWidth}]
		set digitOffsX		-1
		set barHeight		0
		set height			0
		set flagSep			5
		set whiteEloWd		0
		set blackEloWd		0

		set Specs(linewidth:$gamebar) $lineWidth
		if {$useSepColumn} { set id -1 } else { set id $Specs(selected:$gamebar) }
		set selHeight [expr {2*$pady}]
		if {	!$useSepColumn
			&& $Options(selectedAtBottom)
			&& [$gamebar itemcget digit$id -state] eq "normal"} {
			incr selHeight [expr {$digitHeight + 2*$pady}]
		}
		set height0 0
		foreach i {1 2} {
			lassign [$gamebar bbox line$i$id] x1 y1 x2 y2
			set height$i [expr {$y2 - $y1 + 1}]
			set width$i [expr {min($lineWidth, $x2 - $x1)}]
			incr selHeight [set height$i]
		}
		lassign [$gamebar bbox line3$id] x1 y1 x2 y2
		set width2 [expr {min($lineWidth, $width2 + $x2 - $x1)}]
		lassign [$gamebar bbox white$id] x1 y1 x2 y2
		set whiteWd [expr {$x2 - $x1}]
		set height0 [expr {$y2 - $y1}]
		incr selHeight [expr {$y2 - $y1}]
		lassign [$gamebar bbox black$id] x1 y1 x2 y2
		set blackWd [expr {$x2 - $x1}]
		if {$Options(separateLines)} {
			incr selHeight [expr {$y2 - $y1}]
			set flagWd 0
			set flagHt 0
			lassign [$gamebar bbox whiteCountry$id] wx1 wy1 wx2 wy2
			lassign [$gamebar bbox blackCountry$id] bx1 by1 bx2 by2
			if {[llength $wx2]} { set flagWd [expr {$wx2 - $wx1}] }
			if {[llength $bx2]} { set flagWd [expr {max($flagWd, $bx2 - $bx1)}] }
			if {[llength $wy2]} { set flagHt [expr {$wy2 - $wy1}] }
			if {[llength $by2]} { set flagHt [expr {$by2 - $by1}] }
			if {$flagWd > 0} { incr flagWd $flagSep }
			if {[$gamebar itemcget whiteElo$id -state] eq "normal"} {
				lassign [$gamebar bbox whiteElo$id] wx1 _ wx2 _
				set whiteEloWd [expr {$wx2 - $wx1 + $spacewidth}]
			}
			if {[$gamebar itemcget blackElo$id -state] eq "normal"} {
				lassign [$gamebar bbox blackElo$id] wx1 _ wx2 _
				set blackEloWd [expr {$wx2 - $wx1 + $spacewidth}]
			}
			set width0 [expr {$whiteWd + $whiteEloWd}]
			set width0 [expr {max($width0, $blackWd + $blackEloWd)}]
			set width1 [expr {max($width0,$width1)}]
			set width2 [expr {max($width0,$width2)}]
		} else {
			lassign [$gamebar bbox hyphen$id] x1 y1 x2 y2
			set hyphenWd [expr {$x2 - $x1}]
			set width0 [expr {$whiteWd + $hyphenWd + $blackWd}]
		}

		if {$Specs(size:$gamebar) > 1} {
			set id $Specs(lookup:0:$gamebar)
			if {$id eq $Specs(selected:$gamebar)} { set id $Specs(lookup:1:$gamebar) }
			lassign [$gamebar bbox white$id] x1 y1 x2 y2

			set rowHeight	[expr {max($y2 - $y1, $digitHeight, $closeHeight) + 2*$pady + 2}]
			set closeOffsY	[expr {($rowHeight - $closeHeight)/2}]
			set digitOffsY	[expr {($rowHeight - $digitHeight)/2}]
			set whiteOffsY	[expr {($rowHeight - ($y2 - $y1))/2}]
			set blackOffsY	$whiteOffsY
			set barHeight	[expr {$selHeight + ($Specs(size:$gamebar) - 1)*$rowHeight}]
			set maxWidth	0

			if {$useSepColumn} { incr barHeight $rowHeight }

			if {$Options(alignment) eq "center"} {
				set maxWidth 0
				set colors white
#				if {$line == 0} { lappend colors black }

				for {set i 0} {$i < $Specs(size:$gamebar)} {incr i} {
					set id $Specs(lookup:$i:$gamebar)
					foreach color $colors {
						if {$useSepColumn || $id ne $Specs(selected:$gamebar)} {
							set state [$gamebar itemcget $color$id -state]
							$gamebar itemconfigure $color$id -state normal
							lassign [$gamebar bbox $color$id] x1 y1 x2 y2
							set maxWidth [expr {max($maxWidth, $x2 - $x1)}]
						}
					}
				}
			}

			if {$line == 0} {
				set blackOffsX	[expr {($lineWidth + $digitWidth)/2 + $padx}]
				set digitOffsX	[expr {$blackOffsX - $padx - $digitWidth}]
				set whiteOffsX	$padx

				if {$maxWidth} { set whiteOffsX [expr {max($whiteOffsX, $digitOffsX - $maxWidth - $padx)}] }
				set items {digit white black}
			} else {
				if {$maxWidth} {
					set digitOffsX [expr {max(1, ($lineWidth - $maxWidth - $digitWidth - $padx)/2)}]
					set whiteOffsX [expr {$digitOffsX + $digitWidth + $padx}]
				} else {
					set digitOffsX	$padx
					set whiteOffsX	[expr {$digitOffsX + $digitWidth + $padx}]
				}
				set items {digit white}
			}

			for {set i 0} {$i < $Specs(size:$gamebar)} {incr i} {
				set id $Specs(lookup:$i:$gamebar)

				if {$useSepColumn || $id ne $Specs(selected:$gamebar)} {
					set maxY [expr {$height + $rowHeight - 1}]

					$gamebar coords lighter$id 0 $height $lineWidth $maxY
					$gamebar coords darker$id 1 [expr {$height + 1}] $lineWidth $maxY
					$gamebar coords bg$id 1 [expr {$height + 1}] [expr {$lineWidth - 2}] [expr {$maxY - 1}]
					$gamebar coords blackbg$id \
						[expr {$digitOffsX - $padx}] [expr {$height + 1}] \
						[expr {$lineWidth - 2}] [expr {$maxY - 1}]
					$gamebar coords input$id 0 $height $lineWidth $maxY

					$gamebar coords close:lighter$id $closeOffsX $height $rowWidth $maxY
					$gamebar coords close:darker$id \
						[expr {$closeOffsX + 1}] [expr {$height + 1}] $rowWidth $maxY
					$gamebar coords close:bg$id \
						[expr {$closeOffsX + 1}] [expr {$height + 1}] [expr {$rowWidth - 2}] [expr {$maxY - 1}]
					$gamebar coords close:input$id $closeOffsX $height $rowWidth $maxY

					$gamebar coords close:icon$id \
						[expr {$closeOffsX + $closePad}] [expr {$height + $closeOffsY}]

					foreach item $items {
						$gamebar coords $item$id [set ${item}OffsX] [expr {$height + [set ${item}OffsY]}]
					}
					$gamebar coords whitebg$id {*}[$gamebar bbox white$id]

					set height [expr {$maxY + 1}]
				} elseif {!$Options(selectedAtBottom)} {
					set selectedX $height
					incr height $selHeight
					incr height [Adjustment $gamebar $barHeight]
				}
			}
		} else {
			set barHeight $selHeight
			set selectedX 0
		}

		if {$digitOffsX == -1 || $line > 0} {
			set digitOffsX [expr {($lineWidth - $digitWidth)/2}]
		}
		if {!$useSepColumn && !$Options(selectedAtBottom)} { set height $selectedX }
		set rowHeight $selHeight
		set adjust [Adjustment $gamebar $barHeight]
		incr barHeight $adjust
		incr rowHeight $adjust

		if {$useSepColumn} { set id -1 } else { set id $Specs(selected:$gamebar) }
		set maxY [expr {$height + $rowHeight - 1}]
		$gamebar coords lighter$id 0 $height $lineWidth $maxY
		$gamebar coords darker$id 1 [expr {$height + 1}] $lineWidth $maxY
		$gamebar coords bg$id 1 [expr {$height + 1}] [expr {$lineWidth - 2}] [expr {$maxY - 1}]
		$gamebar coords input$id 0 $height $lineWidth $maxY

		$gamebar coords close:lighter$id $closeOffsX $height $rowWidth $maxY
		$gamebar coords close:darker$id [expr {$closeOffsX + 1}] [expr {$height + 1}] $rowWidth $maxY
		$gamebar coords close:bg$id \
			[expr {$closeOffsX + 1}] [expr {$height + 1}] [expr {$rowWidth - 2}] [expr {$maxY - 1}]
		$gamebar coords close:input$id $closeOffsX $height $rowWidth $maxY
		$gamebar coords close:icon$id \
			[expr {$closeOffsX + $closePad}] [expr {$height + ($rowHeight - $closeHeight)/2}]

		if {	!$useSepColumn
			&& $Options(selectedAtBottom)
			&& [$gamebar itemcget digit$id -state] eq "normal"} {
			incr height [expr {2*$pady + $adjust/3}]
			$gamebar coords digit$id $digitOffsX $height
			incr height [expr {$pady + $digitHeight + $adjust/3}]
		} else {
			incr height [expr {$pady + $adjust/2}]
		}
		if {$Options(alignment) eq "center"} {
			set x [expr {max(2, ($lineWidth - $width1)/2)}]
			set x [expr {min($x, max(2, ($lineWidth - $width0)/2))}]
			set x [expr {min($x, max(2, ($lineWidth - $width2)/2))}]
		} elseif {$Options(separateLines)} {
			set x [expr {$flagWd + 5}]
		} else {
			set x 5
		}
		if {$Options(separateLines)} {
			$gamebar coords line1$id $x $height
		} elseif {$Options(alignment) eq "center"} {
			$gamebar coords line1$id [expr {max(2, ($lineWidth - $width1)/2)}] $height
		} else {
			$gamebar coords line1$id $x $height
		}
		$gamebar coords line1bg$id {*}[$gamebar bbox line1$id]
		$gamebar coords line1Input$id {*}[$gamebar bbox line1$id]
		incr height $height1
		if {$Options(separateLines)} {
			if {$flagWd > 0 || $Options(alignment) ne "center"} {
				set fx [expr {$x - $flagWd}]
				set fy [expr {$height - ($flagHt - $height0)/2}]
				$gamebar coords whiteCountry$id $fx $fy
				$gamebar coords blackCountry$id $fx [expr {$fy + $height0}]
				$gamebar coords whiteCountryInput$id {*}[$gamebar bbox whiteCountry$id]
				$gamebar coords blackCountryInput$id {*}[$gamebar bbox blackCountry$id]
			}
			set eloX [expr {$x + max($whiteWd,$blackWd) + max($whiteEloWd,$blackEloWd) + $spacewidth}]
			if {$whiteEloWd > 0} {
				$gamebar coords whiteElo$id [expr {$eloX - $whiteEloWd}] $height
			}
			$gamebar coords white$id $x $height
			incr height $height0
			if {$blackEloWd > 0} {
				$gamebar coords blackElo$id [expr {$eloX - $blackEloWd}] $height
			}
			$gamebar coords black$id $x $height
			incr height $height0
		} else {
			if {$Options(alignment) eq "center"} {
				set x [expr {max(2, ($lineWidth - $width0)/2)}]
			} else {
				set x 5
			}
			$gamebar coords white$id $x $height
			incr x $whiteWd
			$gamebar coords hyphen$id $x $height
			incr x $hyphenWd
			$gamebar coords black$id $x $height
			incr height $height0
			if {$Options(alignment) eq "center"} {
				set x [expr {max(2, ($lineWidth - $width2)/2)}]
			} else {
				set x 5
			}
		}
		foreach side {white black} {
			$gamebar coords ${side}bg${id} {*}[$gamebar bbox ${side}${id}]
			$gamebar coords ${side}Input${id} {*}[$gamebar bbox ${side}${id}]
		}
		$gamebar coords line2$id $x $height
		lassign [$gamebar bbox line2$id] x1 y1 x2 y2
		$gamebar coords line3$id [expr {$x + ($x2 - $x1)}] $height
		$gamebar coords line2Input$id {*}[$gamebar bbox line2$id]
		$gamebar coords line2bg$id {*}[$gamebar bbox line2$id]
	}

	if {$Specs(height:$gamebar) != $barHeight} {
		set $Specs(height:$gamebar) $barHeight
		$gamebar configure -height $barHeight
	}
}


proc Hilite {gamebar id item} {
	variable Defaults
	variable Specs

	if {$Specs(emphasize:$id:$gamebar)} { set color hilite2 } else { set color hilite }
	$gamebar itemconfigure ${item}bg${id} \
		-fill [::colors::lookup $Defaults(background:$color)] \
		-outline [::colors::lookup $Defaults(background:$color)] \
		;
	$gamebar itemconfigure ${item}${id} -fill [::colors::lookup $Defaults(foreground:$color)]
}


proc Normal {gamebar id item} {
	variable Defaults
	variable Specs

	if {$Specs(emphasize:$id:$gamebar)} { set color emphasize } else { set color selected }
	$gamebar itemconfigure ${item}bg${id} \
		-fill [::colors::lookup $Defaults(background:$color)] \
		-outline [::colors::lookup $Defaults(background:$color)] \
		;
	$gamebar itemconfigure ${item}${id} -fill [::colors::lookup $Defaults(foreground:normal)]
}


proc EnterEvent {gamebar id} {
	variable ::scidb::scratchbaseName
	variable Specs

	set sid $Specs(selected:$gamebar)

	if {$id eq $sid || $id eq "-1"} {
		set name [GetEventName $sid]
		if {[string length $name] && $name ne $scratchbaseName} {
			Hilite $gamebar $id line1
		}
	}
}


proc LeaveEvent {gamebar id {unlock no}} {
	variable Specs

	if {$Specs(event:locked)} {
		if {!$unlock} { return }
		set Specs(event:locked) 0
		if {[winfo containing {*}[winfo pointerxy $gamebar]] eq $gamebar} { return }
	}

	set sid $Specs(selected:$gamebar)

	if {$id eq $sid || $id eq "-1"} {
		Normal $gamebar $id line1
	}
}


proc EnterSite {gamebar id} {
	variable Specs

	set sid $Specs(selected:$gamebar)

	if {$id eq $sid || $id eq "-1"} {
		set site [lindex $Specs(data:$sid:$gamebar) 3]
		if {[::web::isWebLink $site]} {
			Hilite $gamebar $id line2
		}
	}
}


proc LeaveSite {gamebar id {unlock no}} {
	variable Specs

	if {$Specs(site:locked)} {
		if {!$unlock} { return }
		set Specs(site:locked) 0
		if {[winfo containing {*}[winfo pointerxy $gamebar]] eq $gamebar} { return }
	}

	set sid $Specs(selected:$gamebar)

	if {$id eq $sid || $id eq "-1"} {
		Normal $gamebar $id line2
	}
}


proc EnterPlayer {gamebar id side} {
	variable Specs

	set sid $Specs(selected:$gamebar)

	if {($id eq $sid || $id eq "-1") && [string length [GetPlayerName $sid $side]]} {
		Hilite $gamebar $id ${side}
	}
}


proc LeavePlayer {gamebar id side {unlock no}} {
	variable Specs
	variable Defaults

	if {$Specs(player:locked)} {
		if {!$unlock} { return }
		set Specs(player:locked) 0
		if {[winfo containing {*}[winfo pointerxy $gamebar]] eq $gamebar} { return }
	}

	set sid $Specs(selected:$gamebar)

	if {$id eq $sid || $id eq "-1"} {
		Normal $gamebar $id ${side}
	}
}


proc EnterFlag {gamebar id side} {
	variable Specs

	set sid $Specs(selected:$gamebar)

	if {$id eq $sid || $id eq "-1"} {
		set data $Specs(data:$sid:$gamebar)
		switch $side {
			white { set countryCode [lindex $data 6] }
			black { set countryCode [lindex $data 7] }
		}
		if {[string length $countryCode]} {
			::tooltip::show $gamebar [::country::name $countryCode]
		}
	}
}


proc LeaveFlag {gamebar id} {
	variable Specs

	set sid $Specs(selected:$gamebar)
	if {$id eq $sid || $id eq "-1"} { ::tooltip::hide true }
}


proc GetEventInfo {id} {
	variable ::scidb::scratchbaseName

	lassign [GetSource $id] base variant index
	if {$base eq $scratchbaseName} { return {""} }
	return [scidb::db::fetch eventInfo $index $base $variant -card]
}


proc GetEventName {id} {
	variable ::scidb::scratchbaseName

	lassign [GetSource $id] base variant index
	if {$base eq $scratchbaseName} { return {""} }
	set name [scidb::db::fetch eventName $index $base $variant]
	if {$name eq "?" || $name eq "-"} { set name "" }
	return $name
}


proc ShowCrossTable {gamebar id} {
	::crosstable::open .application {*}[GetSource $id] -1 game
}


proc ShowEvent {gamebar id} {
	variable Specs

	set sid $Specs(selected:$gamebar)
	set info [GetEventInfo $sid]
	set name [lindex $info 0]
	if {$name eq "?" || $name eq "-"} { set name "" }

	if {[string length $name]} {
		::eventtable::popupInfo $gamebar $info
	} else {
		ShowTags $gamebar $id
	}
}


proc HideEvent {gamebar id} {
	variable Specs

	set sid $Specs(selected:$gamebar)
	set name [GetEventName $sid]

	if {[string length $name]} {
		::eventtable::popdownInfo $gamebar
	} else {
		HideTags $gamebar
	}
}


proc VisitURL {gamebar id} {
	variable Specs

	set sid $Specs(selected:$gamebar)

	if {$id eq $sid || $id eq "-1"} {
		set site [lindex $Specs(data:$id:$gamebar) 3]
		if {[::web::isWebLink $site]} {
			::web::open $gamebar $site
			Normal $gamebar $id line2
		}
	}
}


proc GetPlayerInfo {id side} {
	lassign [GetSource $id] base variant index
	return [scidb::db::fetch ${side}PlayerInfo $index $base $variant -card -ratings {Any Any}]
}


proc GetPlayerName {id side} {
	lassign [GetSource $id] base variant index
	return [scidb::db::fetch ${side}PlayerName $index $base $variant]
}


proc ShowPlayerCard {gamebar id side} {
	variable Specs

	set sid $Specs(selected:$gamebar)
	set name [GetPlayerName $sid $side]

	if {[string length $name]} {
		lassign [GetSource $id] base variant index
		::playercard::show $base $variant $index $side
	}
}


proc ShowPlayerInfo {gamebar id side} {
	variable Specs

	set sid $Specs(selected:$gamebar)
	set info [GetPlayerInfo $sid $side]
	set name [lindex $info 0]
	if {$name eq "?" || $name eq "-"} { set name "" }

	if {[string length $name]} {
		::playercard::popupInfo $gamebar $info
	} else {
		ShowTags $gamebar $id
	}
}


proc HidePlayerInfo {gamebar id side} {
	variable Specs

	set sid $Specs(selected:$gamebar)
	set name [GetPlayerName $sid $side]

	if {[string length $name]} {
		::playercard::popdownInfo $gamebar
	} else {
		HideTags $gamebar
	}
}


proc Adjustment {gamebar height} {
	variable Specs

	lassign $Specs(adjustment:$gamebar) align incr delta
	set f [expr {($height - $incr - $delta + $align + 3)/$align}]
	set h [expr {$f*$align + $incr + $delta}]
	return [expr {$h - $height}]
}


proc ConfigureElo {gamebar id} {
	variable Specs
	variable Options

	if {$Options(separateLines)} {
		if {$id eq -1} { set sid $Specs(selected:$gamebar) } else { set sid $id }
		if {[UseSeparateColumn $gamebar]} { set i -1 } else { set i $id }

		foreach {side index} {white 8 black 9} {
			set elo [lindex $Specs(data:$sid:$gamebar) $index]

			if {$elo} {
				$gamebar itemconfigure ${side}Elo${id} -text $elo
				$gamebar itemconfigure ${side}Elo${i} -state normal
			} else {
				$gamebar itemconfigure ${side}Elo${i} -state hidden
			}
		}
	} else {
		$gamebar itemconfigure whiteElo${id} -state hidden
		$gamebar itemconfigure blackElo${id} -state hidden
	}
}


proc SetCountryFlag {gamebar id data side} {
	switch $side {
		white { set countryCode [lindex $data 6] }
		black { set countryCode [lindex $data 7] }
	}
	if {[string length $countryCode] == 0} {
		set icon $::icon::12x12::none
	} else {
		set icon $::country::icon::flag($countryCode)
	}
	$gamebar itemconfigure ${side}Country${id} -image $icon
	$gamebar itemconfigure ${side}Country-1 -image $icon
}


proc Configure {gamebar width} {
	set [namespace current]::Specs(width:$gamebar) $width
	Layout $gamebar
   event generate $gamebar <<GamebarConfigure>>
}


proc Normalize {s {default ""}} {
	if {$s eq "?" || $s eq "-" || $s eq ""} { return $default }
	return $s
}


proc WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter [namespace current]::WriteOptions


namespace eval icon {
namespace eval 15x15 {

set digit(1) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABTElEQVR4nIWT
	zytEURzFz/fO+2GhWcjIUslGWVlNWVgpRUopShHN3tJuRlho7CaLsRmxkPEjjUjYKX+Cmr2t5hHx
	Yu6xmPeMZ67nbE7d+/10zvfWBQwiKYFbJNtMM0aRVIF3nZzd5Iul8h7JfgDIZht3oazfoIhokqnj
	ytXaRqGUcWwbQ+nBOwD3QC4SpH6AEoKHp5fr+UJp0X/3oQTa854jiRE4AEkydVS5Xt3c2l14833l
	uvYHCZVQRvY7WQJPF3cOMk8vr4mZydGLVGfHQ72u4TiWjoNDVcdGhs/np8fLy0uZfWq6NGY2ZAGA
	iOjAqyTnAHwCGLBt2yWNoU04lIhARGrBOyRiQlthkiGkAcQ1BtC6MwBQRP4F/4IjXQBorc17x8Fa
	KXEAUclku7GJZTgLB6uzUxPbj16tu6+357ZxlAOwEl+2WTr+V30BEeiQ0cmHeJMAAAAASUVORK5C
	YII=
}]

set digit(2) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACKElEQVR4nH2T
	X0iTURjG3/d8ZyXfErqbg7ZyZDbCq1EtkkRSg5hLNkY1Ctc/CezvxSCo+K5UosTooovVRXdBV6FB
	0W5GBEWaGYguTJA02MpZxhZu37c9XbTBptNzd+D3nPd5n4dDtM4BoACoBaCsx8hVdy7CbU+ePvfO
	f0/W2ayWBIBhIooyc4GIUG0SS6lQMrkYCvaEE03NPjgPdKGp2YdgTziRXFzqllIhAFzSiKJQMDN0
	3XAM3H98dWwibqm3W7+FTnaO7LBZF0Y/TVsGBiPXdN1wMDMAiPKpgogok8l4WzzdWVdrAJPx2esA
	tkx9mbnk7ggabV3n/qbTKx4iIk37z1fsrKrqb8f2bT+FELSn0fGBmdOfJ+MmFMBCiIKUVfYtc2AC
	0ArgMAAB4FCo9+bsrr0ehLV77wHYy51u9JCtbzAS3e324ujxi7+WlpdPC8EVga1JPBB4pgAwj7yM
	PXC1BvL72k7ko7F3dwHUFKusLtY0TSiKQj9SqfPt/gt/nO5j6B+KvABQt6FdTdNKtR08c/nWTOP+
	Tly50TcGoAWACmDTao0s2WXmAgB7/1Dk9seJqZ1ba81Zs6qm+oce9eZyOdXZ4JgHcIeZ54o8SlUx
	EcEwDFfs7egR3ciTYH3z8Ks3HcxMWV0nh91Kfl/7ayKaK/ElMYiIpJTjZ0/5H07Hv9oUqeQFM7Gg
	gm4UFGdD/YIkOV7Or0kOgImIaqjyAzARrTCzXs7+AzSDHfs/p3EvAAAAAElFTkSuQmCC
}]

set digit(3) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACNUlEQVR4nIVT
	X0iTcRS99/vjwyIYSTirmY1AFhhpMCuWUs3AWlvtoTIfpiQ+VJAVo6jAl4gRGNJLFBUFgUERZfUS
	iwqKVKTMxTaabuo3c6MhPWzTtbnTQ/vA2Ua/twPncO459/6ISjwAIoCVAIRSHGkZZgAiEVnu9z+z
	KTMxnX6dbhbAABF5mDlHRCjmxJIkUiwWbz/W5YrWmh0wbj+IWrMDbV2uaCw+55QkkQCwqhHyQoGZ
	kclkDe6+O6dHRgMV1VWVSker7eWGqsrI8Bd/hbv3dncmkzUwMwqiqCCZTNqarM701t2H8dUXOAOg
	zBeYOLFtb1vW4jieTCQWrEREPT1/+QWZNRrNL0O1/icol91srBkiolWiKGpyuUVmsLC8IV4KAMhE
	1EhENKVE9r1+O2j3vP9U7vWNa1v2mEd6r7iOMHMoHzNXdAUAVty8+2haZ9yFGtN+NFnb4fV/v1VW
	Jpde1VLnluadj0VZtHveDZZ7fUHtvYdP69Pp34Z/nNXCADR2nLocaT95cRLADgC6YHj6nMlydLH5
	UOd8YqGwsILrSaVS2tCksvqbf3z9mD/YQERzmXRmXhBEgJCjbJHC1DEAGM5euvbkledDXc3GKsXc
	UD/2cejzFn9waq3VYh69fvW8g5nDKl8iIsoLWZalkDITuxGLx91e34R+PPxCL4kCmeo2RS90d/bJ
	khQGwGpepmWT5PM3P+h/fkD5MavTr6mMOlvtA0T0hpkXqdhtF1mX8L9f9Qc5ayauUMqJ6AAAAABJ
	RU5ErkJggg==
}]

set digit(4) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB10lEQVR4nI2S
	TUhUURTHz7n3vvl4L1MqSCIQBgmKNm0EBfehLcImQowoCKECF9G4EOPNIAptsnCT9EHCuMmyFkFu
	2kpITB8uKoOColdNxJsUSd/z3r8r5ek8rT/c1Tm/8/W/RNsIAG8X/ycIoB5AM4Ca/yoYAXffHX80
	3nk+V54pzV6xlCIiWodVHJjP5xkAv5p9132v+Pjkb3/emim9PRyEITMzADAzQ8Q05kKhYIjo6OD1
	2z3zC4uWY6cgSK5sTtwAAxDMbAA09g0M97//+Lk+YSljDDhuVxEB10ZyJp5M5Z49n27eVVfzJ9Ow
	/4PWhqRkRPet6mwphW/fy2dGxx52BeEKXTh7arIx0/BFGxALoVPJhKmCXdcVzIwgDFuvDo1c9n78
	cpqOHHzdmW0v+ZXKTgJIsHCWloPMhuNExq29duNOcezB02NJS1I6nVqQUiIMgnSojVRKBl3Z9qme
	7tPnmLkCgKNWsW2n9L69e/4KwaS1ThtAhwEjxpFqATjg+/4Jz/vZ8dXzOgBkL+YGpg+1HNej9yeK
	ADJrxyXa9EmYeY6I5iLF6nbYdi+IhW0nF5MJ69OWnV3XFa4LAay/xIuXby7dvFWc9MrlNiDe7y2l
	lCIATlxsFXw0+s3S/mP2AAAAAElFTkSuQmCC
}]

set digit(5) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB+0lEQVR4nI2T
	P2hTURTGv3PufS99pq5isLEWKaiDEAqiIE6tQ6lI6SIuCgWpOIptnPIq4tKhjg6iCAq2oAkuraWK
	kx0U2qUajUYDgRZFBPOv5v05Dn0vpkkEf3CXw/k49/vOvYQWRMQA0AVAmsoEYIuInOZeHQiIiERE
	eh+nFyfXs5/iXRHT2a6LOK6vDvf3FUVkhogKYb8GANu2CYCUSqWBew+fTBQ3vjMTQwAQAb/rLg72
	xjA2OvQCQCG4ybY4pFyrw/N8d3fU8oaHTr3Umj0AcB2PD/X3FTX0auiuce0Q01Ti+x5ZVoRTk5fv
	AlgMehhALfRMRO3if1AlIr85mx2BhdTrHjErKVeq/o2ZO+Na8cXY3j3fRCQDYImIvLa0Q7q7LVHM
	qlSpmfOZpRFfBEoRll+tnJm9mUxqrR44jtuYTq2rmk8vXF//kN9vmtrRrOn1m9VENlfoGR48uTZ7
	a2qMiPIiwqGVHYiIFpFdwbGyua9Xjp8+7w6OjlfK5a0RAEilhBGk+H9Qe6n1hR2Yyzyfyubyca3Y
	U6R45e1a4sfPX+rEwNGP0WjkHQDYNjA9/TcwAiAu3MT9R08nPhc2EDENiPhQzDiWOLKZvHrptmHo
	fDDI7xjYXHrh2vvclx5DsycCxPfFNi+cO/sMwHIgauy5zUmHX1XtmCyAP/il9FAzdVvXAAAAAElF
	TkSuQmCC
}]

set digit(6) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACXklEQVR4nHWT
	UUhTYRiG3/8/5+zo2dTUcC5yZQZqw1Iow5KM8qpsmmWiSLMEwSIqwqiLwCuRCJQoAoOoIOymqIFB
	FEikN1ZkQrqyRNC1s6XD5c60ztzXhTOmtvfuh/fj/Xi+9wfiiIgEIkoiIiGeR1z1ZlFz+f2eZ/ZJ
	tzczy2JWicgJ4BVjLAKA/pfERFGA1zvdWN/cqhaUVlN+SRUVlFZTfXOr6p32O0RRABGx5RkeHeSM
	MdL1cE57V/eF90Oj5myrZcpRe7g322qZ+jDkMnd03j2v6+EtjDEiIh6bygEgGFyoKD/aFNpdXhf+
	7PreQkTCpxHX2cJ9x2j/kcY/mqbZY/0cANra2gAAmhaUdT0smkyJYXNG+qa+/sGG7fm5qWV7d01u
	tGS6FUUJxAVGhIggCpG5oCadbLlycXomYEhONmoNxyvGHXWVtwH0A2BRcEvJNpuNAYAgcFNigiwF
	tXnuUX9K5ow0/8zMrLHj5r2CzjsPywCYlrZegsZjk8GZmTHGZVlG67kmp/PRraozp2u7EwwS3gy8
	OwSgaPmka9ZeXFxUQqEFylifyqorDgwyxt4S0bqeJ72nZgO/FI/Plx7LaEVykjExYDIqbC4Yookp
	TyoRJQ2PjuVo87+5wSDpaSkpC7HDIgDU1NQQACiK8jJv6+YvT1/05V6+duPEnuLCvIHBj4X+2Tmh
	ZOeOr7Isj66hzRiLRBvm+uH1tbtV3/XhkW/WsQm3VRQ4iou2qVcvNXdJkjhORP9oM6zUcrcPPnj8
	3D7p9mRmbbCojrpKJ4DXcbu9WkTEo7+Kx/P8BcegDzoFb4gHAAAAAElFTkSuQmCC
}]

set digit(7) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABxklEQVR4nJVS
	TUhUURg93/O+n9BqFgUSyohOmYojbsQWShK0KMTAXS6lNi1a2XZmm7gUdGerwAciulBw0SYEF5Up
	lA7+NTPM1FgLWzUzz3mnhe/JzZmIvs3lXs453znfdwUXiqQJwAFA7VkAFEXE07EqIIiIkGR0fnF1
	YnfvqEnVGRVCBPDhlSuq63YsS3JSRNIhXmnKBNA793rp2UEmD9tUIAHDEPi+j41325WRB0NrANIh
	PiSHFjfHxx7NfE4dNoth+I5teelMrvHtxuad69ciWdu2M1W2RYTBmSb5PMjsA7g8Nf1q9s36eyPW
	1pICcKg3U7pSkMUD4AX31g9bn3otUyHecXPrkmP/1JsZOjkYmriuW0dS8oUf3blvxzciV+tP+/vi
	H4ulMhKJxB+cmuXYFhaW117GB0Y59vTFEcmewM05uUqFpADAr2Ipsr2z11P2ThFri6aCKevDrSbj
	bA0AEN3f/9JuWed5T/S8NcnJZBIAkC9878x+LTRFrjT8X16S4i6uTMYHR/3HTyZq5q3qHOYF4GRz
	hfZSqSIdt1oPauUFLuw5XBWA4vD9u/PKNP2H9wZdpdRJ+J//aftMCCBZL/J3zG+atdJVevfFoAAA
	AABJRU5ErkJggg==
}]

set digit(8) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACRUlEQVR4nIWT
	XUiTYRTHz3ned5sF4U0559BQC1G0lQM/YHRRb0Kga7OLbAYmxqCuljWKIrwJ+wDDa6EoCooIKaMI
	EiGwKNb8mLGZaxsyRxubycDlPt73PV24yRquzt0Dvz/nz4/zABQZIuKIaBcRccUYvuCNWVh4+PSl
	MRiKlFdq1GEimgCA94goAwBttwl5noNIJHbWYrWHmwzdVN9uoiZDN1ms9nAk9quP5zkgIsxlWDbI
	EJEyGbF2eHTM5pj1qKurNCv9FuOb6irNimPWo741MmbLZMQaRCQiYltbh4aGGABAPJ7oEkwDv9s7
	esXFpcB5IlK4F30X2jp6RcE8kFhfT3Zu8pthll+d5wEAASVZQsaxEgAoYxwrkWUJEZAVGsK82jIR
	1Qxev/v83dRH/YGGffEjh9uiUx8+73F5fpQeP2r4OnLTfgoR/TmeBwDIWgSVSul3znucTpdbP/ft
	e+knh6t05w4VqMt2Q/8Z04xKqfTn81vCAABSqXTt/ccv9NHYGhxsrIvfuGz16hrr4tHYGjx4Mt6c
	Sqdr8vm/hCUSiS7BPLDRKvRIS77li0RUsegNDLYIPdIx87mNZPIfwkQRAAiIMY5kSU4CQFSW5CRj
	HBGSLIr/EWa7dmf87eS0rn7/3pChtXl++suMzuNd1nYKhrl7w1dObiuMiFCh4P3BUGQ0urp6e8Ht
	03oDr7U8x6DlUEP46iXrqELB+4kIc8IQCppkZQiPnr0yBkM/yysrNOG+0ycmAGCy6G0XDhGx7K9i
	xZg/Rf0tQojttDoAAAAASUVORK5CYII=
}]

set digit(9) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACXklEQVR4nHVT
	X0hTcRj9vvu7t9HUthT8M11gUbLYWD7MyKxeFgSKxQhijbQIFkFgFhXWi/QQQgT6UA8WUhFWolAm
	UmBFQoIZ/UGXqajgHNvV6aztzum9u18vUzab5+2Dczicw/kANgERMSLKIiK2GYffcGOCbH/8/FW1
	1yfmGwvzAkTUDQB9iBgHAErnhDzPQBSDZ0+7rwUsFQ4yHThBlgoHudzXA6K4WMMYB0SEaxouIeQQ
	kWRZ2XWnufXy1++jecU7DN5aZ9WbYmPBzOA3T969+203FSVegohERFyyKwcAEIlEquyO89L+o05l
	2DNeR0RZv8cn75Yfc6nVrkskSVIdAEBHRwdbz9zY2AgAAH8lSSOvykKGVqOa9+yeRsRwLBZbysrM
	wEgkSmFpWZcclUsWF+TmLuh126KLobDwqL2zkogOdfW8L5sLhkCr3YqMsWi6ttca/HHkoK239Wmn
	80HbS3f3248nZ33i9hVZBiJVVVVF/E+MiAQACADh+os1/dl6nbm9s2enOB/KNhhyV+eDIWE5tiJT
	HCMAAB6Ph9bFibZVAKg4c6HhRk6Onr3retjU1//FW2opMZ06d6VeUeIcInDJzilHNBrVzfr9hZ8G
	howjYxOL9sNlz/yBuZmwtMy2CLyi02XGkjtKWZhWqx0pNZs8vR8+77t1u6Wh3GatHBj6aV36E2bl
	NuuYRqMZTZdZJSIUBH7K6xNbxIWFpuFfk0UT074innFgK90baLjqbhYEfoqIMBEREFKBicHYn7x4
	Xe31+fONhoJArfP42rZVSLftjSAiLvFV3Gacf0dOJgd/qmcvAAAAAElFTkSuQmCC
}]

set close(locked) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACpklEQVR4nG2S
	WUhUYRTH/+e7947LXEfHjCihREsrWh9My3B5kAgSKlqelMxeKrCCCNpBhF6iBbLVMintIerBHioL
	pqyUinClxlKTwqWmnJp7R5vm3nt6cG5M0nn7zvf/nZ0QZcxMRMTMPFPX9fy+gaGZc9NTR1RVbSGi
	Efvf1sv/AZefOn+96v7jF/k/A5qa6ErQ1xavfsrMx4moPTqAPAV019Q2Hq27dW+dQxZInTXDPzT8
	xV3X2FQSoygGM1cQkd/Wi0hiYmYCsPyhp7VQIli7tm+91NRwbv3O8i2XJSKr2dNaCGBZREcAYMMg
	Ivb5/fGapqvJbpdZUbrpHhG17Cjb3JSclGAGtKDT5/c7/+k5UoLFzM4fAT1HCEkwM3d0eze0d71L
	7ej2rgARCSKhSFIOM3uIKMjMRJGeY548f3n0zMWGPf2Dn1QwEBcXC2YGEWFi4hdAQEbabH3fztIz
	BXnZ1UQUsqedVXvj7jZv30d1UVZGSFEUyTTNH3GxDpr4FWJJkpPC4bDZ09uvXrl5p7wgL/s2gC4b
	dml6MN6lOq3qw5UX5meme9ted5Y0e1oXrila9TY3e2mT9/3AgrJdhyq1gB4PwBW9ZwbIkmRZaHrw
	jW9sbOxg1enioRGfw/PsVerd+rM1mh4cl2RZAGRN6qOmbZskhEJEChEIYBABlmU6FFmRp2ptBzFb
	kmkYlsOhTEtxu0dPHNn7oPlp2+LiolVdKSnu38OjX6abhmExWNh7tuFAoith/MPA56T9x04ekGUJ
	MTEOVp1OpbPnWm4oFF5pGAY0fVxkzVPHAQSi4d6Ksk21Aa1+9+jXb9MnS2WYlgVJCAhBYAYyM+Z8
	ryjdeBVA79+zjNx1gmEYxR1dvWkQYFggSABMwH4vW5I1KMvyIyLSmJn+AKFBTP+A48EkAAAAAElF
	TkSuQmCC
}]

set close(unlocked) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABtElEQVR4nJVT
	z0sbQRidbyx4Fi2EVkH8gfTiRVpEiCcLEvVi3L1lN5u7pBvwtnQ86UX8BxT/m1By0IAnPRiJSlYl
	yXSHYS9FXw/ZLEO0Rb/LNwzvDd/73hvGkgJAjDESQnAiYmYRERNCcMYYJbiXZXL6IBNMgzQDNFWt
	nQaPnY4FgCd3aX/sdKxq7TQAMGXyiHNi1Vo9WFotwPL8UGtdNIlax67t+eHSagHVWj3gPOEJIQgA
	m5ueuBj/NHZfP7/MlLZ/7kmpCgCGpVSF0nawf3Z+mfmcGXuYm568AMCEEJSODoDrOHZsr9Ka/baO
	vFO+bVzfHufd8s3s13VYnh9GUW+iV5cGgKJIO/nij+Z8dhPLaw7ms5vIO+UbKWUq5TViXyM1mnfH
	y2vO05fFjT/ZnPN01WieGItNH0gPRPQMgCulnB1x8F0qzT+OjnyIlOY7u4crv5VyAXAien4xLoAh
	HcfugOYjU3PiwlCquZcoxtptuWWX/HBmIQfLq7S63cgFMNztRq7tVVozCzlYRf++3ZZbRKyfuMTn
	Xz2fbc8PtY7dt/j8v4SR2f+VsLTene0B8Lt+1V/NTFouEVtvTwAAAABJRU5ErkJggg==
}]

# set close(modified) [image create photo -data {
# iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
# ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
# ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
# MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
# Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
# IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
# YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
# cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
# aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
# b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
# b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
# d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
# b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
# IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
# c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
# REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
# TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
# SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
# SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
# RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
# V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
# SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
# RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACKElEQVR4nH3S
# W0iTARQH8HO+79sSzYesJ6E2Bj2skNYWLQnXZmW+KK1dulgIC8reegjCIHooTNns4rzMh20q7OLm
# hKKy6C0iKIgegszSlC4DSRJpuYX5/XvZTDfbeTmcAz8OnHOIigQAYb0+Mxdj/yCATZlMpmFi8lMz
# ACMAqSiMxWJiFhrDiYePD1nPpqqPnMKZC61f3r2fvAhAQURUMB+AyMzLAHZGEmPxzt5BLZOMLZsr
# UlMzX8v3GaqSQ303rcz8SsiDQhaq+oPDbe7uoDb1M0VKhfKPq8n6UbOtMjU5/bnyw9S0lohIyIMy
# ALUvEO3sDcYaFZJIdbX7ZxfTael279CuufmFkrKy0l8a1da5FZwHPf2DCZtCksjRUDfU1d56vaba
# 8P3H/ILAxJKryfpckqQXuYmczWpfMBrXmWzQmx1we4NhAAfc3sDg3sMnl3abHQjHH4wDMK45IwBN
# X2B4RGeyQ29xrsBbPQMhg8WJqhorfIHYPQA78qEyMjrWY6h1Qm92LHfc9YcAmD3dAyG9xQGdyYY+
# f2QEgGoNzBbl19q997XVR+UrN+48AWDu6PKH9BbnaqgugEQkERGYxGVJFJBMzlZcbfNefvT0Wb0M
# 0Plme6LFdeISM8/kllqAlRuUIoiE128n9rx8M06lJUo6d/rYaIvr+H9hDi/aGw9GRWY5/TsjE5Gg
# 3a755rTWe4rBlfdkZpJleeOqXoaZlwAwM2M9SET0F231OT+v2iHjAAAAAElFTkSuQmCC
# }]

# set close(modified) [image create photo -data {
# iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
# ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
# ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
# MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
# Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
# IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
# YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
# cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
# aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
# b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
# b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
# d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
# b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
# IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
# c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
# REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
# TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
# SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
# SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
# RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
# V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
# SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
# RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACKElEQVR4nH3S
# W0iTARQH8HO+79sSzYesJ6E2Bj2skNYWLQnXZmW+KK1dulgIC8reegjCIHooTNns4rzMh20q7OLm
# hKKy6C0iKIgegszSlC4DSRJpuYX5/XvZTDfbeTmcAz8OnHOIigQAYb0+Mxdj/yCATZlMpmFi8lMz
# ACMAqSiMxWJiFhrDiYePD1nPpqqPnMKZC61f3r2fvAhAQURUMB+AyMzLAHZGEmPxzt5BLZOMLZsr
# UlMzX8v3GaqSQ303rcz8SsiDQhaq+oPDbe7uoDb1M0VKhfKPq8n6UbOtMjU5/bnyw9S0lohIyIMy
# ALUvEO3sDcYaFZJIdbX7ZxfTael279CuufmFkrKy0l8a1da5FZwHPf2DCZtCksjRUDfU1d56vaba
# 8P3H/ILAxJKryfpckqQXuYmczWpfMBrXmWzQmx1we4NhAAfc3sDg3sMnl3abHQjHH4wDMK45IwBN
# X2B4RGeyQ29xrsBbPQMhg8WJqhorfIHYPQA78qEyMjrWY6h1Qm92LHfc9YcAmD3dAyG9xQGdyYY+
# f2QEgGoNzBbl19q997XVR+UrN+48AWDu6PKH9BbnaqgugEQkERGYxGVJFJBMzlZcbfNefvT0Wb0M
# 0Plme6LFdeISM8/kllqAlRuUIoiE128n9rx8M06lJUo6d/rYaIvr+H9hDi/aGw9GRWY5/TsjE5Gg
# 3a755rTWe4rBlfdkZpJleeOqXoaZlwAwM2M9SET0F231OT+v2iHjAAAAAElFTkSuQmCC
# }]

set close(modified) $::icon::15x15::close

set frozen [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAC3ElEQVR4nKVT
	bUiTexw9z/Z/pHy2iBrLkGaPzoxs5TLbNSgierFWEURKL0hBX3oPukgXROKWly5kReAHESR6oZph
	WBlCa1iTylJaWjIt55zarIxL5jZxL6cPOehz9/fl8ON3zpdzzg8AQFIiqXE4HNqpXXg6vWd3HSjz
	ejq9Z0kKAHA4HFqSGpISAECSfmJySMqd3b0VR8oqv5jzN/NIWeWXzu7eCpLyrzxJkiBIgqQCIH14
	ZCQPwLSL1Vf3tTxrN8w1zoo2PXIbQpHIvrrLZ/xDweBEelqaB8CwJEkhQVKtueI4/X08ZHO5X6pL
	c3Pe/VNx/N6fFef3eLq8swsLloyeKz/e+Nffl068edeTu3bVin69TmkjeVoDINPZ8txee60hJzAU
	TPnQH1DTjIYx2zLL18loHCusiz8ZjYZwnz+gBgY/ptRea8hxtjy3A8iUSBqv19+vr6q+ujoajUIW
	AtlZGVH/wJA8Nh7GDF0q1Iz0+HtfQBuNxSGEwMlDpU/3Fm/dqQEwKoS2Q6ekjm1YUzhgzjKFPF1e
	Wa/XTe7esXlQr9dNvn7bo82cP29s7eo//LrU6d+FrO0AMJp0eH2ff/AmyWPNzlZ3doE9UXmhxk/y
	VOWFGn92gT3R7Gx1kzwxxVsPAIKk5tbdh5uqa2/Zl+ctsg1+/DQbpPT4SdvceDxx8EnrqzSQUu31
	O9ZmV6up3dM98/CBkiDJxwKAIRaL54+HI3rn0za9LLSwWhbG+gPDKTfqH5j0OgV5loXR930Dire3
	X5FlGbFYPB+AQQPA0tjkyg1HJsBEAmZ13rfbdVX/7i3e8jZBsLRkW4+jruqcOdP0HwCEIxNobHLl
	ArAIAL51awqbbMuX2Fzul2qWmuEb+TyqtHV0zUmRBV60vzGUbN84w6ya/KFwREnmDMCXNEwhuWAo
	GCwmWbr/aLlPtRZx5cbdk6q1iPsPl/tIlk7dF0w18v91Oyn4ra/6Ae7mpRnSnxNrAAAAAElFTkSu
	QmCC
}]

} ;# namespace 15x15
} ;# namespace icon
} ;# namespace gamebar

# vi:set ts=3 sw=3:
