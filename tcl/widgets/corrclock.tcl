# ======================================================================
# Author : $Author$
# Version: $Revision: 1 $
# Date   : $Date: 2026-08-23 $
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
# Copyright: (C) 2026 chesswiz
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source corrclock

proc corrclock {path args} {
	return [::corrclock::corrclock $path {*}$args]
}


namespace eval corrclock {
namespace eval mc {

set WhiteClock		"White"
set BlackClock		"Black"
set TimeExpired		"Time expired"
set NoTime			"\u2014"	;# em dash

} ;# namespace mc

variable Defaults
array set Defaults {
	background:normal		gamebar,background:normal
	foreground:normal		gamebar,foreground:normal
	foreground:active		gamebar,foreground:elo
}


proc corrclock {path args} {
	variable Defaults

	namespace eval [namespace current]::${path} {}
	variable ${path}::Position
	variable ${path}::Orient
	variable ${path}::After
	variable ${path}::BaseTime
	variable ${path}::WhiteTime
	variable ${path}::BlackTime
	variable ${path}::OrigWhiteTime
	variable ${path}::OrigBlackTime
	variable ${path}::Running

	array set opts {
		-position 0
		-orient vertical
	}
	array set opts $args

	set Position $opts(-position)
	set Orient $opts(-orient)
	set After {}
	set BaseTime 0
	set WhiteTime {}
	set BlackTime {}
	set OrigWhiteTime {}
	set OrigBlackTime {}
	set Running 0

	set bg [::colors::lookup $Defaults(background:normal)]
	set fg [::colors::lookup $Defaults(foreground:normal)]
	set active [::colors::lookup $Defaults(foreground:active)]

	ttk::frame $path -borderwidth 0 -takefocus 0 -padding 2

	set white [ttk::frame $path.white -borderwidth 0]
	set black [ttk::frame $path.black -borderwidth 0]

	ttk::label $white.name -text $mc::WhiteClock \
		-background $bg -foreground $fg -font $::font::text(text:normal)
	ttk::label $white.time -text $mc::NoTime \
		-background $bg -foreground $fg -font $::font::text(text:normal)
	ttk::label $black.name -text $mc::BlackClock \
		-background $bg -foreground $fg -font $::font::text(text:normal)
	ttk::label $black.time -text $mc::NoTime \
		-background $bg -foreground $fg -font $::font::text(text:normal)

	grid $white.name -row 1 -column 1 -sticky w
	grid $white.time -row 1 -column 2 -sticky e -padx {4 0}
	grid $black.name -row 2 -column 1 -sticky w
	grid $black.time -row 2 -column 2 -sticky e -padx {4 0}

	if {$Orient eq "horizontal"} {
		grid $white -row 1 -column 1 -sticky ew
		grid $black -row 1 -column 2 -sticky ew -padx {8 0}
		grid columnconfigure $path 1 -weight 1
		grid columnconfigure $path 2 -weight 1
	} else {
		grid $white -row 1 -column 1 -sticky ew
		grid $black -row 2 -column 1 -sticky ew
		grid columnconfigure $path 1 -weight 1
	}

	# remember the active-color for the tick handler
	set ${path}::ActiveColor $active
	set ${path}::NormalColor $fg

	bind $path <Destroy> [namespace code [list stop $path]]

	# Don't call update during construction -- no game may be loaded yet.
	# UpdateCorrClock in app-pgn.tcl will call update/start when a game is selected.
	return $path
}


proc parseIsoDuration {s} {
	# Parse "P28DT12H30M", "P40DT0H0M0S", "P2DT4H30M", "P0DT0H0M0S".
	# Returns {days hours minutes seconds}.
	set days 0
	set hours 0
	set minutes 0
	set seconds 0

	if {![regexp {^P([0-9]+)D(?:T(?:(?:([0-9]+)H)?(?:([0-9]+)M)?(?:([0-9]+)S)?))?$} $s \
			-> days hours minutes seconds]} {
		return {}
	}
	foreach var {days hours minutes seconds} {
		if {[string length [set $var]] == 0} { set $var 0 }
	}
	return [list $days $hours $minutes $seconds]
}


proc formatDuration {days hours minutes seconds} {
	# Format {days hours minutes seconds} as "28d 12h 30m".
	set parts {}
	if {$days} { lappend parts "${days}d" }
	if {$hours} { lappend parts "${hours}h" }
	if {$minutes} { lappend parts "${minutes}m" }
	if {$seconds} { lappend parts "${seconds}s" }
	if {[llength $parts] == 0} { return "0m" }
	return [join $parts " "]
}


proc update {w} {
	variable ${w}::Position
	variable ${w}::WhiteTime
	variable ${w}::BlackTime
	variable ${w}::OrigWhiteTime
	variable ${w}::OrigBlackTime
	variable ${w}::BaseTime

	# Guard against game not loaded (can happen during teardown)
	if {[catch { set tags [::scidb::game::tags $Position] } err]} { puts stderr "corrclock: $err"; return }
	set whiteTime {}
	set blackTime {}

	foreach pair $tags {
		lassign $pair name value
		switch -- $name {
			WhiteTimeLeft	{ set whiteTime $value }
			BlackTimeLeft	{ set blackTime $value }
		}
	}

	set WhiteTime [parseIsoDuration $whiteTime]
	set BlackTime [parseIsoDuration $blackTime]
	set OrigWhiteTime $WhiteTime
	set OrigBlackTime $BlackTime
	set BaseTime [clock seconds]

	Redraw $w
}


proc start {w} {
	variable ${w}::After
	variable ${w}::Running

	if {$Running} { return }
	set Running 1
	set After [after 1000 [namespace code [list Tick $w]]]
}


proc stop {w} {
	variable ${w}::After
	variable ${w}::Running

	if {[info exists After] && [string length $After]} {
		after cancel $After
	}
	set After {}
	set Running 0
}


proc Tick {w} {
	variable ${w}::After
	variable ${w}::Running
	variable ${w}::Position
	variable ${w}::BaseTime
	variable ${w}::WhiteTime
	variable ${w}::BlackTime
	variable ${w}::OrigWhiteTime
	variable ${w}::OrigBlackTime

	if {!$Running} { return }

	if {[catch { set stm [::scidb::game::query $Position stm] } err]} { puts stderr "corrclock: $err"; return }
	set elapsed [expr {[clock seconds] - $BaseTime}]

	if {$stm eq "white" && [llength $OrigWhiteTime]} {
		lassign $OrigWhiteTime d h m s
		set total [expr {((($d*24 + $h)*60 + $m)*60 + $s) - $elapsed}]
		if {$total < 0} { set total 0 }
		set WhiteTime [SecondsToDuration $total]
	} elseif {$stm eq "black" && [llength $OrigBlackTime]} {
		lassign $OrigBlackTime d h m s
		set total [expr {((($d*24 + $h)*60 + $m)*60 + $s) - $elapsed}]
		if {$total < 0} { set total 0 }
		set BlackTime [SecondsToDuration $total]
	}

	Redraw $w
	set After [after 1000 [namespace code [list Tick $w]]]
}


proc SecondsToDuration {total} {
	set days [expr {$total / 86400}]
	set total [expr {$total % 86400}]
	set hours [expr {$total / 3600}]
	set total [expr {$total % 3600}]
	set minutes [expr {$total / 60}]
	set seconds [expr {$total % 60}]
	return [list $days $hours $minutes $seconds]
}


proc Redraw {w} {
	variable ${w}::Position
	variable ${w}::WhiteTime
	variable ${w}::BlackTime
	variable ${w}::ActiveColor
	variable ${w}::NormalColor

	if {[catch { set stm [::scidb::game::query $Position stm] } err]} { puts stderr "corrclock: $err"; return }

	foreach {side time} [list white $WhiteTime black $BlackTime] {
		set name [string tolower $side]
		if {[llength $time]} {
			lassign $time d h m s
			set text [formatDuration $d $h $m $s]
		} else {
			set text $mc::NoTime
		}
		$w.$name.time configure -text $text
		if {$stm eq $side} {
			$w.$name.time configure -font $::font::text(text:bold) -foreground $ActiveColor
			$w.$name.name configure -font $::font::text(text:bold) -foreground $ActiveColor
		} else {
			$w.$name.time configure -font $::font::text(text:normal) -foreground $NormalColor
			$w.$name.name configure -font $::font::text(text:normal) -foreground $NormalColor
		}
	}
}


# ======================================================================
# Integration in app-pgn.tcl:
#
# 1. Source the widget (already done via ::util::source corrclock):
#    ::util::source corrclock
#
# 2. Create below the gamebar:
#    set corrclock [::corrclock::corrclock $edit.corrclock -position 0]
#    grid $corrclock -row 2 -column 1 -sticky ew
#
# 3. On game load/update:
#    $corrclock update
#    $corrclock start
#
# 4. On game switch:
#    $corrclock stop
#    $corrclock update
#    $corrclock start
#
# The widget reads WhiteTimeLeft / BlackTimeLeft from the game tags
# (ISO 8601 durations, e.g. "P28DT12H30M") and ticks down the side-to-move
# player's clock once per second. When no time data is present it shows an
# em dash. The timer is cancelled on <Destroy> and on stop.
# ======================================================================

} ;# namespace corrclock
