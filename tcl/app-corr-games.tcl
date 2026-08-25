# ======================================================================
# Author : $Author$
# Version: $Revision: 1 $
# Date   : $Date: 2026-08-24 $
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
# Copyright: (C) 2026 scidb-beta
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source corr-game-manager

namespace eval application {
namespace eval corr {
namespace eval games {
namespace eval mc {

set Title				"Correspondence Games"
set Refresh			"Refresh"
set OpenGame			"Open Game"
set Filter				"Filter"
set StatusAll			"All"
set StatusOngoing		"Ongoing"
set StatusFinished	"Finished"
set NoGames			"No correspondence games found"
set NoDatabase		"No database is open"
set Sync			"Sync"
set Close				"Close"
set Game				"Game"
set ICCF				"ICCF"
set Status				"Status"
set WhiteTime			"White Time"
set BlackTime			"Black Time"
set LastMove			"Last Move"
set Event				"Event"
set Result				"Result"
set White				"White"
set Black				"Black"

} ;# namespace mc

variable Vars
array set Vars {
	filter		all
	selected		{}
}


proc open {parent} {
	variable Vars

	set dlg $parent.corrGames
	if {[winfo exists $dlg]} {
		raise $dlg
		refresh $dlg
		return $dlg
	}

	set dlg [tk::toplevel $parent.corrGames -class Dialog]
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm resizable $dlg true true

	build $dlg
	refresh $dlg
	return $dlg
}


proc build {dlg} {
	variable Vars

	set Vars(dlg) $dlg

	# Toolbar -----------------------------------------------------------------
	set tb [ttk::frame $dlg.tb -borderwidth 0]
	ttk::button $tb.refresh -text $mc::Refresh -command [namespace code [list refresh $dlg]]
	ttk::button $tb.sync -text $mc::Sync -command [namespace code [list syncFromServer $dlg]]
	ttk::button $tb.open -text $mc::OpenGame -command [namespace code [list openGame $dlg]]
	ttk::label $tb.filterlbl -text $mc::Filter
	set filter [ttk::combobox $tb.filter \
		-values [list $mc::StatusAll $mc::StatusOngoing $mc::StatusFinished] \
		-state readonly \
		-width 12 \
	]
	$filter set $mc::StatusAll
	bind $filter <<ComboboxSelected>> [namespace code [list filterChanged $dlg]]
	ttk::button $tb.close -text $mc::Close -command [list destroy $dlg]

	pack $tb.refresh -side left -padx 2
	pack $tb.sync -side left -padx 2
	pack $tb.open -side left -padx 2
	pack $tb.filterlbl -side left -padx {12 2}
	pack $tb.filter -side left -padx 2
	pack $tb.close -side right -padx 2

	# Game list table ---------------------------------------------------------
	set tree [ttk::treeview $dlg.tree \
		-columns {number white black iccf status whitetime blacktime lastmove event result} \
		-show headings \
		-height 15 \
		-selectmode browse \
	]

	$tree heading number -text "#"
	$tree heading white -text $mc::White
	$tree heading black -text $mc::Black
	$tree heading iccf -text $mc::ICCF
	$tree heading status -text $mc::Status
	$tree heading whitetime -text $mc::WhiteTime
	$tree heading blacktime -text $mc::BlackTime
	$tree heading lastmove -text $mc::LastMove
	$tree heading event -text $mc::Event
	$tree heading result -text $mc::Result

	$tree column number -anchor e -width 50 -stretch 0
	$tree column white -anchor w -width 150 -stretch 1
	$tree column black -anchor w -width 150 -stretch 1
	$tree column iccf -anchor w -width 100 -stretch 0
	$tree column status -anchor w -width 90 -stretch 0
	$tree column whitetime -anchor e -width 100 -stretch 0
	$tree column blacktime -anchor e -width 100 -stretch 0
	$tree column lastmove -anchor w -width 90 -stretch 0
	$tree column event -anchor w -width 150 -stretch 1
	$tree column result -anchor w -width 60 -stretch 0

	set sb [ttk::scrollbar $dlg.sb -orient vertical -command [list $tree yview]]
	$tree configure -yscrollcommand [list $sb set]

	bind $tree <<TreeviewSelect>> [namespace code [list selectionChanged $dlg]]
	bind $tree <Double-1> [namespace code [list openGame $dlg]]

	# Detail area -------------------------------------------------------------
	set detail [ttk::frame $dlg.detail -borderwidth 0 -padding 4]
	ttk::label $detail.iccf -text "" -font $::font::text(text:normal)
	ttk::label $detail.status -text "" -font $::font::text(text:normal)
	ttk::label $detail.whitelbl -text $mc::WhiteTime -font $::font::text(text:normal)
	ttk::label $detail.blacklbl -text $mc::BlackTime -font $::font::text(text:normal)
	ttk::label $detail.whitetime -text "\u2014" -font $::font::text(text:bold)
	ttk::label $detail.blacktime -text "\u2014" -font $::font::text(text:bold)

	grid $detail.iccf -row 1 -column 1 -sticky w -padx 4
	grid $detail.status -row 1 -column 2 -sticky w -padx 4
	grid $detail.whitelbl -row 2 -column 1 -sticky w -padx 4 -pady {6 0}
	grid $detail.whitetime -row 2 -column 2 -sticky w -padx 4 -pady {6 0}
	grid $detail.blacklbl -row 3 -column 1 -sticky w -padx 4
	grid $detail.blacktime -row 3 -column 2 -sticky w -padx 4

	# Layout ------------------------------------------------------------------
	pack $tb -fill x -padx 4 -pady 4
	pack $tree -side left -fill both -expand yes -padx {4 0} -pady {0 4}
	pack $sb -side left -fill y -pady {0 4}
	pack $detail -fill x -padx 4 -pady {0 4}

	set Vars(tree) $tree
	set Vars(detail) $detail
	set Vars(filterbox) $filter
}


proc refresh {dlg} {
	variable Vars

	if {![winfo exists $dlg]} { return }
	set tree $Vars(tree)

	$tree delete [$tree children {}]

	set base [::scidb::db::get name]
	if {[string length $base] == 0} {
		$tree insert {} end -values [list "" "" "" "" $mc::NoDatabase "" "" "" "" ""]
		return
	}

	set variant [::scidb::app::variant]
	set count 0
	catch { set count [::scidb::db::count games $base $variant] }

	if {$count == 0} {
		$tree insert {} end -values [list "" "" "" "" $mc::NoGames "" "" "" "" ""]
		return
	}

	set filter $Vars(filter)

	for {set i 0} {$i < $count} {incr i} {
		set tags {}
		catch { set tags [::scidb::db::get tags $i $base $variant] }

		if {![isCorrespondenceGame $tags]} { continue }

		set status [getGameStatus $tags]
		if {$filter ne "all" && $status ne $filter} { continue }

		set white [getTag $tags White]
		set black [getTag $tags Black]
		set event [getTag $tags Event]
		set result [getTag $tags Result]
		set iccf [getTag $tags ICCFGameID]
		set whiteTime [formatTime [getTag $tags WhiteTimeLeft]]
		set blackTime [formatTime [getTag $tags BlackTimeLeft]]
		set lastMove [getTag $tags Date]

		$tree insert {} end \
			-values [list [expr {$i + 1}] $white $black $iccf $status \
							$whiteTime $blackTime $lastMove $event $result]
	}
}


proc syncFromServer {dlg} {
	variable Vars

	if {![::iccf::xfcc::configured?]} {
		::iccf::xfcc::openSettings $dlg
		return
	}

	::widget::busyCursor on
	if {[catch {
		set games [::iccf::xfcc::getGames]
		set count [llength $games]

		# Update the treeview with server data
		set tree $Vars(tree)
		$tree delete [$tree children {}]

		if {$count == 0} {
			$tree insert {} end -values [list "" "" "" "" $mc::NoGames "" "" "" "" ""]
		} else {
			foreach game $games {
				set id [dict get $game id]
				set white [dict get $game white]
				set black [dict get $game black]
				set event [dict get $game event]
				set result [::iccf::xfcc::resultToPgn [dict get $game result]]
				set myTurn [dict get $game myTurn]
				set status [expr {$myTurn eq "true" ? "ongoing" : "ongoing"}]
				if {[dict get $game result] ne "Ongoing"} { set status "finished" }

				# Format time remaining
				set dp [dict get $game daysPlayer]
				set hp [dict get $game hoursPlayer]
				set mp [dict get $game minutesPlayer]
				set do [dict get $game daysOpponent]
				set ho [dict get $game hoursOpponent]
				set mo [dict get $game minutesOpponent]
				set hasWhite [dict get $game hasWhite]
				if {$hasWhite eq "true"} {
					set wt [format "P%sDT%sH%sM" $dp $hp $mp]
					set bt [format "P%sDT%sH%sM" $do $ho $mo]
				} else {
					set wt [format "P%sDT%sH%sM" $do $ho $mo]
					set bt [format "P%sDT%sH%sM" $dp $hp $mp]
				}
				set wtf [::corrclock::formatDuration {*}[::corrclock::parseIsoDuration $wt]]
				set btf [::corrclock::formatDuration {*}[::corrclock::parseIsoDuration $bt]]

				set eventDate [dict get $game eventDate]

				$tree insert {} end \
					-values [list $id $white $black "" $status $wtf $btf $eventDate $event $result]
			}
		}

		tk_messageBox -parent $dlg -title $mc::Sync \
			-message "Synced $count game(s) from ICCF server." \
			-type ok -icon info
	} err]} {
		::widget::busyCursor off
		tk_messageBox -parent $dlg -title $mc::Sync \
			-message "Sync failed: $err" \
			-type ok -icon error
		return
	}
	::widget::busyCursor off
}


proc openGame {dlg} {
	variable Vars

	if {![winfo exists $dlg]} { return }
	set tree $Vars(tree)
	set sel [$tree selection]
	if {![llength $sel]} { return }

	set values [$tree item [lindex $sel 0] -values]
	set number [lindex $values 0]
	if {![string is integer -strict $number]} { return }

	set base [::scidb::db::get name]
	set variant [::scidb::app::variant]

	catch {
		::game::new [winfo toplevel $dlg] \
			-base $base \
			-number [expr {$number - 1}] \
			-variant $variant
	}
}


proc filterChanged {dlg} {
	variable Vars

	set box $Vars(filterbox)
	set value [$box get]
	switch -- $value {
		$mc::StatusOngoing	{ set Vars(filter) ongoing }
		$mc::StatusFinished	{ set Vars(filter) finished }
		default					{ set Vars(filter) all }
	}
	refresh $dlg
}


proc selectionChanged {dlg} {
	variable Vars

	if {![winfo exists $dlg]} { return }
	set tree $Vars(tree)
	set detail $Vars(detail)
	set sel [$tree selection]

	if {![llength $sel]} {
		$detail.iccf configure -text ""
		$detail.status configure -text ""
		$detail.whitetime configure -text "\u2014"
		$detail.blacktime configure -text "\u2014"
		return
	}

	set values [$tree item [lindex $sel 0] -values]
	lassign $values number white black iccf status whitetime blacktime lastmove event result

	$detail.iccf configure -text [format "%s: %s" $mc::ICCF $iccf]
	$detail.status configure -text [format "%s: %s" $mc::Status $status]
	$detail.whitetime configure -text $whitetime
	$detail.blacktime configure -text $blacktime
}


proc formatTime {iso8601} {
	if {[string length $iso8601] == 0} { return "\u2014" }
	set dur [::corrclock::parseIsoDuration $iso8601]
	if {[llength $dur] == 0} { return "\u2014" }
	return [::corrclock::formatDuration {*}$dur]
}


proc getTag {tags name} {
	foreach pair $tags {
		lassign $pair n v
		if {$n eq $name} { return $v }
	}
	return ""
}


proc getGameStatus {tags} {
	set status [getTag $tags CorrStatus]
	if {[string length $status] == 0} { return "ongoing" }
	return $status
}


proc isCorrespondenceGame {tags} {
	# A game is correspondence if TimeMode is "corr" (the scidb time-mode
	# value), or if any correspondence-specific extra tag is present.
	set timeMode [getTag $tags TimeMode]
	if {[string equal -nocase $timeMode "corr"]} { return 1 }
	if {[string equal -nocase $timeMode "correspondence"]} { return 1 }

	foreach name {ICCFGameID CorrStatus WhiteTimeLeft BlackTimeLeft CorrType ICCFEvent} {
		if {[string length [getTag $tags $name]]} { return 1 }
	}
	return 0
}

} ;# namespace games
} ;# namespace corr
} ;# namespace application

# ======================================================================
# Integration:
#
# 1. Add to tcl/Makefile SOURCES list (after app-db-games.tcl):
#    app-corr-games.tcl \
#
# 2. Add a menu item in menu.tcl (or wherever the game menu is built):
#    $menu add command -label "Correspondence Games..." \
#        -command [list ::application::corr::games::open $parent]
#
# 3. The open proc creates a modal-less toplevel that can stay open while
#    the user works. It lists correspondence games from the current
#    database, filtered by status, with a detail area showing remaining
#    time for the selected game.
# ======================================================================

# vi:set ts=3 sw=3:
