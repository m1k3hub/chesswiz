# ======================================================================
# Author : $Author$
# Version: $Revision: 813 $
# Date   : $Date: 2013-05-31 18:23:38 -0400 (Fri, 31 May 2013) $
# Url    : $URL$
# ======================================================================

# ======================================================================
# Copyright: (C) 2010-2013 Gregor Cramer
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

package require Ttk
package require Tk 8.5
if {[catch { package require tkpng }]} { package require Img }
package require place
package provide calendar 1.0

namespace eval calendar {
namespace eval mc {

set OneMonthForward	"One month forward (Shift-\u2192)"
set OneMonthBackward	"One month backward (Shift-\u2190)"
set OneYearForward	"One year forward (Ctrl-\u2192)"
set OneYearBackward	"One year backward (Ctrl-\u2190)"

set Su "Su"
set Mo "Mo"
set Tu "Tu"
set We "We"
set Th "Th"
set Fr "Fr"
set Sa "Sa"

set Jan "Jan"
set Feb "Feb"
set Mar "Mar"
set Apr "Apr"
set May "May"
set Jun "Jun"
set Jul "Jul"
set Aug "Aug"
set Sep "Sep"
set Oct "Oct"
set Nov "Nov"
set Dec "Dec"

set MonthName(1)  "January"
set MonthName(2)  "February"
set MonthName(3)  "March"
set MonthName(4)  "April"
set MonthName(5)  "May"
set MonthName(6)  "June"
set MonthName(7)  "July"
set MonthName(8)  "August"
set MonthName(9)  "September"
set MonthName(10) "October"
set MonthName(11) "November"
set MonthName(12) "December"

set WeekdayName(0) "Sunday"
set WeekdayName(1) "Monday"
set WeekdayName(2) "Tuesday"
set WeekdayName(3) "Wednesday"
set WeekdayName(4) "Thursday"
set WeekdayName(5) "Friday"
set WeekdayName(6) "Saturday"

}

namespace import ::tcl::mathfunc::abs
namespace import ::tcl::mathfunc::min

array set Days {
	 1 31
	 2 28
	 3 31
	 4 30
	 5 31
	 6 30
	 7 31
	 8 31
	 9 30
	10 31
	11 30
	12 31
}

variable FontSizes {8 9 10 11 12 14 16 18 20 22 24 26 28}
variable Priv

array set colors {
	label:background	white
	label:foreground	black
	active:background	#ffdd76
	active:foreground	black
	hilite:foreground	darkRed
}

array set options {
	repeat:delay		300
	repeat:interval	100
}

set minYear		1902
set maxYear		2037
set weekStart	0
set useGrab		true


proc popup {parent args} {
	variable FontSizes
	variable Priv
	variable icon::12x10::PrevYear
	variable icon::12x10::NextYear
	variable icon::12x10::PrevMonth
	variable icon::12x10::NextMonth
	variable useGrab
	variable colors
	variable minYear
	variable maxYear
	variable weekStart
	variable options

	if {![winfo exists $parent]} {
		return -code error "parent \"$parent\": window does not exist"
	}

	set disableParent false
	set Priv(weekStart) $weekStart
	set Priv(minYear) $minYear
	set Priv(maxYear) $maxYear

	if {!$useGrab && [catch {$parent cget -state}]} { set disableParent true }
	set key [lindex $args 0]
	set date {}

	while {$key != ""} {
		if {[llength $args] <= 1} {
			return -code error "no value given to option \"$key\""
		}

		set value [lindex $args 1]
		set args [lreplace $args 0 1]

		switch $key {
			-weekStart - -minYear - -maxYear {
				if {![string is integer -strict $value]} {
					return -code error "option \"$key\": value should be integer"
				}
				set Priv([string range $key 1 end]) $value
			}

			-date {
				if {$value ne "today" && $value ne "now"} {
					if {[llength $value] != 3} {
						return -code error \
							"option \"$key\": value should be 'now', 'today', or {Year Month Day}"
					}
					lassign $value y m d
					if {![string is integer -strict $y]} {
						return -code error "option \"$key\": invalid year '$y'"
					}
					if {![string is integer -strict $m] || 1 > $m || $m > 12} {
						return -code error "option \"$key\": invalid month '$m'"
					}
					if {![string is integer -strict $d] || 1 > $d || $d > 31} {
						return -code error "option \"$key\": invalid day '$d'"
					}
					if {![validDate? $y $m $d]} {
						return -code error "option \"$key\": invalid date '$y.$m.$d'"
					}
					set date [list $y [Normalize $m] [Normalize $d]]
				}
			}

			default {
				return -code error "option \"$key\": unknown option"
			}
		}

		set key [lindex $args 0]
	}

	set point [expr {[winfo toplevel $parent] == "." ? "" : "."}]
	set top [winfo toplevel $parent]${point}__calendar__
	if {[winfo exists $top]} { return }

	if {[llength $date] == 0} { set date [today] }
	lassign $date Priv(y) Priv(m) Priv(d)
	set Priv(m:start) $Priv(m)
	set Priv(y:start) $Priv(y)
	set Priv(d:start) $Priv(d)
	set Priv(day) $Priv(d)
	set Priv(daysInMonth) [daysInMonth $Priv(m) $Priv(y)]
	set Priv(active) {}

	menu $top
	wm withdraw $top
	bind $top <Destroy> [namespace code [list ClearTooltips $top %W]]
	bind $top <ButtonRelease-1> [namespace code [list Unpost $top %X %Y]]
	bind $top <ButtonRelease-2> [namespace code [list Unpost $top %X %Y]]
	bind $top <ButtonRelease-3> [namespace code [list Unpost $top %X %Y]]
	bind $top <Deactivate> [namespace code Exit]
	if {!$useGrab} { bind $top <FocusOut> [namespace code Exit] }

	tk::frame $top.calendar -relief raised -borderwidth 2 -takefocus 0
	tk::frame $top.calendar.header -takefocus 0
	pack $top.calendar
	set Priv(background) [$top.calendar cget -background]

	bind $top.calendar <Escape> [namespace code Exit]

	tk::label $top.calendar.header.month -padx 0 -anchor e
	set font [$top.calendar.header.month cget -font]
	set size [abs [font configure $font -size]]
	set n [lsearch -integer $FontSizes $size]
	if {$n < 1} {
		incr size 1
	} else {
		set size [lindex $FontSizes [incr n -1]]
	}
	set boldFont [list [font configure $font -family] $size bold]
	$top.calendar.header.month configure -font $boldFont
	tooltip $top.calendar.header.month [Tr MonthName($Priv(m))]

	tk::label $top.calendar.header.year -font $boldFont -padx 0 -anchor center

	tk::frame $top.calendar.header.left -takefocus 0
	tk::frame $top.calendar.header.right -takefocus 0

	tk::button $top.calendar.header.left.year   -image $PrevYear
	tk::button $top.calendar.header.left.month  -image $PrevMonth
	tk::button $top.calendar.header.right.year  -image $NextYear
	tk::button $top.calendar.header.right.month -image $NextMonth

	foreach which {left.year left.month right.year right.month} {
		$top.calendar.header.$which configure \
			-relief flat \
			-overrelief raised \
			-repeatdelay $options(repeat:delay) \
			-repeatinterval $options(repeat:interval) \
			-background $Priv(background) \
			-activebackground $colors(active:background) \
			;
		bind $top.calendar.header.$which <ButtonRelease-1> \
			[list after idle [namespace code { ButtonEnter %W }]]
	}

	tooltip $top.calendar.header.left.year		[namespace current]::mc::OneYearBackward
	tooltip $top.calendar.header.right.year	[namespace current]::mc::OneYearForward
	tooltip $top.calendar.header.left.month	[namespace current]::mc::OneMonthBackward
	tooltip $top.calendar.header.right.month	[namespace current]::mc::OneMonthForward

#	tk::frame $top.calendar.sep -height 2 -background black -borderwidth 0
	ttk::separator $top.calendar.sep

	pack $top.calendar.header.left.year -side left -padx 2
	pack $top.calendar.header.left.month -side left
	pack $top.calendar.header.right.year -side right -padx 2
	pack $top.calendar.header.right.month -side right

	pack $top.calendar.header.left -side left
	pack $top.calendar.header.month -side left -expand yes -fill x -padx 2
	pack $top.calendar.header.year -side left -expand yes -fill x -padx 2
	pack $top.calendar.header.right -side left

	$top.calendar.header.left.year configure   -command [namespace code [list SetYear  $top -1]]
	$top.calendar.header.right.year configure  -command [namespace code [list SetYear  $top +1]]
	$top.calendar.header.left.month configure  -command [namespace code [list SetMonth $top -1]]
	$top.calendar.header.right.month configure -command [namespace code [list SetMonth $top +1]]

	grid $top.calendar.header -columnspan 7 -sticky ew
	grid $top.calendar.sep -columnspan 7 -sticky ew -padx 2

	set rowData {}
	set day 0

	foreach dayName [nameOfDays $Priv(weekStart)] {
		if {((7 - $day) % 7) == $Priv(weekStart)} {
			set foreground $colors(hilite:foreground)
		} else {
			set foreground black
		}
		tk::label $top.calendar.days:$dayName \
			-text $dayName \
			-font TkFixedFont \
			-borderwidth 1 \
			-width 0 \
			-foreground $foreground \
			;
		tooltip $top.calendar.days:$dayName [Tr WeekdayName([expr {($day + $Priv(weekStart)) % 7}])] 
		lappend rowData $top.calendar.days:$dayName
		incr day
	}

	grid {*}$rowData -sticky e

	set cmd-Up					[namespace code [list Focus $top -7]]
	set cmd-Down				[namespace code [list Focus $top +7]]
	set cmd-Left				[namespace code [list Focus $top -1]]
	set cmd-Right				[namespace code [list Focus $top +1]]
	set cmd-Escape				[namespace code Exit]
	set cmd-Shift-Left		[namespace code [list SetMonth $top -1]]
	set cmd-Shift-Right		[namespace code [list SetMonth $top +1]]
	set cmd-Control-Left		[namespace code [list SetYear  $top -1]]
	set cmd-Control-Right	[namespace code [list SetYear  $top +1]]
	set cmd-Home				[namespace code [list Focus $top first]]
	set cmd-End					[namespace code [list Focus $top last]]
	set cmd-Control-Home		[namespace code "SetMonth $top first; Focus $top first"]
	set cmd-Control-End		[namespace code "SetMonth $top last; Focus $top last"]

	for {set row 1} {$row < 7} {incr row} {
		set rowData {}

		for {set col 1} {$col < 8} {incr col} {
			set lbl [tk::label $top.calendar.$row:$col \
							-borderwidth 1 \
							-width 2 \
							-highlightthickness 1 \
							-relief flat \
							-anchor e \
							-takefocus 1 \
						]
			foreach key {	Up Down Left Right \
								Shift-Left Shift-Right Control-Left Control-Right \
								Home End \
								Control-Home Control-End \
								Escape} {
				bind $lbl <$key> [set cmd-$key]
			}
			lappend rowData $lbl
		}

		grid {*}$rowData -sticky ew -ipadx 1 -ipady 1
	}

	Update $top

	tooltip on $top*
	wm transient $top [winfo toplevel [winfo parent $parent]]
	util::place $top -parent $parent -position below -type popup
	wm deiconify $top
	raise $top
	if {[tk windowingsystem] == "x11"} {
		catch { tkwait visibility $top }
		update idletasks
		if {![winfo exists $top]} { return }
	}
	if {$useGrab} { ttk::globalGrab $top.calendar }
	focus -force $top.calendar.$Priv(widget:$Priv(day))
	vwait [namespace current]::Priv(d)
	if {$useGrab} { ttk::releaseGrab $top.calendar }
	destroy [winfo toplevel $top]
	tooltip on
	update idletasks

	if {$Priv(d) eq "none"} { return {} }
	return [list $Priv(y) $Priv(m) $Priv(d)]
}


proc mc {tok} { return [tk::msgcat::mc [set $tok]] }


proc daysInMonth {month year} {
	variable Days

	set day [clock format [clock add [clock scan 28/02/${year} -format "%d/%m/%Y"] 1 day] -format %d]
	set month [Normalize $month]
	if {$month == 2 && $day == 29} { return 29 }
	return $Days($month)
}


proc nameOfDays {weekStart} {
	set weekend [expr {$weekStart + 6}]
	set daynames {}

	for {set day [expr {$weekStart - 1}]} {$day < $weekend} {incr day} {
		set name [string range [clock format [clock add 1220223600 $day day] -format %a] 0 1]
		lappend daynames [Tr $name]
	}

	return $daynames
}


proc validDate? {y m d} {
	set d [Normalize $d]
	set m [Normalize $m]
	if {1 > $m || $m > 12} { return 0 }
	set daysInMonth [daysInMonth $m $y]
	if {1 > $d || $d > $daysInMonth} { return 0 }
	return 1
}


proc compare {lhs rhs} {
	lassign {0 0 0 0 0 0} y1 m1 d1 y2 m2 d2
	scan $lhs "%d.%d.%d" y1 m1 d1
	scan $rhs "%d.%d.%d" y2 m2 d2

	if {$y1 == 0} {
		if {$y2 == 0} { return 0 }
		return {}
	}
	if {$y2 == 0} {
		if {$y1 == 0} { return 0 }
		return {}
	}
	if {$y1 < $y2} { return -1 }
	if {$y2 < $y1} { return +1 }
	if {$m1 == 0} {
		if {$m2 == 0} { return 0 }
		return {}
	}
	if {$m2 == 0} {
		if {$m1 == 0} { return 0 }
		return {}
	}
	if {$m1 < $m2} { return -1 }
	if {$m2 < $m1} { return +1 }
	if {$d1 == 0} {
		if {$d2 == 0} { return 0 }
		return {}
	}
	if {$d2 == 0} {
		if {$d1 == 0} { return 0 }
		return {}
	}
	if {$d1 < $d2} { return -1 }
	if {$d2 < $d1} { return +1 }
	return 0
}


proc today {} {
	lassign [clock format [clock seconds] -format "%d %m %Y"] d m y
	return [list $y [Normalize $m] [Normalize $d]]
}


proc tooltip {args} {}


proc Tr {tok} { return [mc mc::${tok}] }


proc Normalize {m} {
	if {[string index $m 0] eq "0"} { return [string index $m 1] }
	return $m
}


proc SetMonth {top incr} {
	variable Priv

	switch -- $incr {
		first		{ set month 1 }
		last		{ set month 12 }
		default	{ set month [expr {$Priv(m) + $incr}] }
	}

	if {$month == 0} {
		if {$Priv(y) == $Priv(minYear)} { return }
		set month 12
		incr Priv(y) -1
	} elseif {$month == 13} {
		if {$Priv(y) == $Priv(maxYear)} { return }
		set month 1
		incr Priv(y)
	}

	set Priv(m) $month
	tooltip $top.calendar.header.month [Tr MonthName($Priv(m))]
	set Priv(daysInMonth) [daysInMonth $Priv(m) $Priv(y)]
	set Priv(day) [min $Priv(day) $Priv(daysInMonth)]

	Update $top
	focus $top.calendar.$Priv(widget:$Priv(day))
}


proc SetYear {top incr} {
	variable Priv

	set year [expr {$Priv(y) + $incr}]
	if {$year < $Priv(minYear) || $Priv(maxYear) < $year} { return }
	set Priv(y) $year
	set Priv(daysInMonth) [daysInMonth $Priv(m) $Priv(y)]
	set Priv(day) [min $Priv(day) $Priv(daysInMonth)]
	Update $top
	focus $top.calendar.$Priv(widget:$Priv(day))
}


proc Focus {top incr} {
	variable Priv

	switch -- $incr {
		first		{ set day 1 }
		last		{ set day $Priv(daysInMonth) }
		default	{ set day [expr {$Priv(day) + $incr}] }
	}

	if {$day <= 0} {
		if {$Priv(m) == 1} {
			if {$Priv(y) == $Priv(minYear)} { return }
			incr Priv(y) -1
			set Priv(m) 12
		} else {
			incr Priv(m) -1
		}

		tooltip $top.calendar.header.month [Tr MonthName($Priv(m))]
		set Priv(daysInMonth) [daysInMonth $Priv(m) $Priv(y)]
		set Priv(day) [expr {$Priv(daysInMonth) + $day}]
	} elseif {$day > $Priv(daysInMonth)} {
		if {$Priv(m) == 12} {
			if {$Priv(y) == $Priv(maxYear)} { return }
			incr Priv(y)
			set Priv(m) 1
		} else {
			incr Priv(m)
		}

		tooltip $top.calendar.header.month [Tr MonthName($Priv(m))]
		set Priv(day) [expr {$day - $Priv(daysInMonth)}]
		set Priv(daysInMonth) [daysInMonth $Priv(m) $Priv(y)]
	} else {
		set Priv(day) $day
	}

	Update $top
	focus $top.calendar.$Priv(widget:$Priv(day))
}


proc Update {top} {
	variable Priv
	variable colors

	set monthStart [clock scan 01/$Priv(m)/$Priv(y) -format %d/%m/%Y]
	lassign [clock format $monthStart -format "%b %u"] monthName startDay

	$top.calendar.header.month configure -text [Tr $monthName]
	$top.calendar.header.year configure -text $Priv(y)
	ConfigureButtons $top

	set day [expr {($startDay - $Priv(weekStart) + 6) % 7}]
	set day [expr {$day == 6 ? 1 : -$day}]
	set Priv(current) {}

	for {set row 1} {$row < 7} {incr row} {
		for {set col 1} {$col < 8} {incr col} {
			set lbl $top.calendar.$row:$col
			set Priv(widget:$day) $row:$col

			if {1 <= $day && $day <= $Priv(daysInMonth)} {
				if {$lbl eq $Priv(active)} { set which active } else { set which label }
				$lbl configure \
					-text $day \
					-background $colors($which:background) \
					-foreground $colors($which:foreground) \
					;
				set cmd [namespace code [list set Priv(d) $day]]
				foreach key {ButtonRelease-1 space Return} {
					bind $lbl <$key> $cmd
				}
				foreach {key state} {Leave off Enter on} {
					bind $lbl <$key> [namespace code [list Hilite $lbl $state]]
				}
				if {$Priv(y) == $Priv(y:start) && $Priv(m) == $Priv(m:start) && $day == $Priv(d:start)} {
					if {$lbl ne $Priv(active)} {
						$lbl configure -foreground $colors(hilite:foreground)
					}
					set Priv(current) $lbl
				}
			} else {
				$lbl configure -text "" -background $Priv(background)
				foreach key {ButtonRelease-1 Leave Enter space Return} {
					bind $lbl <$key> {#}
				}
			}

			incr day
		}
	}
}


proc ConfigureButtons {top} {
	variable Priv

	if {$Priv(y) == $Priv(minYear)} {
		$top.calendar.header.left.year configure -state disabled
	} else {
		$top.calendar.header.left.year configure -state normal
	}
	if {$Priv(y) == $Priv(maxYear)} {
		$top.calendar.header.right.year configure -state disabled
	} else {
		$top.calendar.header.right.year configure -state normal
	}
	if {$Priv(y) == $Priv(minYear) && $Priv(m) == 1} {
		$top.calendar.header.left.month configure -state disabled
	} else {
		$top.calendar.header.left.month configure -state normal
	}
	if {$Priv(y) == $Priv(maxYear) && $Priv(m) == 12} {
		$top.calendar.header.right.month configure -state disabled
	} else {
		$top.calendar.header.right.month configure -state normal
	}
}


proc Hilite {lbl state} {
	variable Priv
	variable colors

	switch $state {
		on {
			set background $colors(active:background)
			set foreground $colors(active:foreground)
			set Priv(active) $lbl
		}

		off {
			if {$Priv(current) eq $lbl} {
				set foreground $colors(hilite:foreground)
			} else {
				set foreground $colors(label:foreground)
			}
			set background $colors(label:background)
			set Priv(active) {}
		}
	}

	$lbl configure -background $background -foreground $foreground
}


proc ClearTooltips {menu w} {
	if {$menu eq $w} {
		tooltip clear $w.*
	}
}


proc Exit {} {
	set [namespace current]::Priv(d) none
}


proc Unpost {menu x y} {
    set w [winfo containing $x $y]
	 if {![string match $menu.* $w]} { Exit }
}


proc ButtonEnter {w} {
	if {[winfo containing {*}[winfo pointerxy .]] eq $w} {
		::tk::ButtonLeave $w
		::tk::ButtonEnter $w
	}
}


namespace eval icon {
namespace eval 12x10 {

set PrevYear [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAKCAYAAACALL/6AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAA70lEQVR4nJWR
	sS4EURiFv3/uyEqUvIKGBLG7NWOi19yRiOjECyiJEKWE1gtI1n0Gln6n5Am8xDJ3jsKMSOxKnPLk
	Ozk5/w9/yHvvJvkGsJYVqyvb+3MN6ZAMoJ/vzPfyot+yCZwZgKO+tvfxovfeEULETOuZP5RmR3XU
	TdOYpD+KxukMMYQQu/nupqELxBtWHwMHACEsKWlxgUwu7Wb+1sQl0Z2OHu/3VFUvZuq0XMIUSbVN
	8r8DBiaLVTkMR4qckHLe2yruLE2XJRtPaFCn+sB57135PHgqHwYbtTREyRWw8DX61f591mkTmtzv
	x30C2FNc1YGSAfcAAAAASUVORK5CYII=
}]

set NextYear [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAKCAYAAACALL/6AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAA80lEQVR4nJ1R
	O07DUBCc3WdIQQlXoICCj+KURDERPRJap4E2B6BFCAlRAz0lDco7AwQpbUIJl+ACJn4eCtsUNhIS
	0+1oRpqdARowM9fkmhAAiPtprzc8Xi8pCirjztHp2l6S7tZaNTMFgEJ5T67O42Q0BoTwPpiZk69s
	06G4K/VXot5vs3J/CnhO8CA+HM32BydD732IVhAAyeo4+pNL2ClC9LGYTs6EvFDnrrsDexC6iABb
	hjYUgPA3tnyTkqnLt7pJ+kjVGxbhcvE6GVNCLlUxAKBm7/WxQcitQGbz56f+29S/mJnLl3AAO/+u
	tZX8r+G+Aa8yV88pLFADAAAAAElFTkSuQmCC
}]

set PrevMonth [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAKCAYAAACALL/6AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAAnUlEQVR4nGNg
	wAD1TJhiOAGKYkZsKuCCoaGhzKtXr/5r5him//f//3ZmDraIv69vfOfh4fl/8ODBvwwMDP+RDIaY
	rGcToGbsGHrGyC7YFpcbGOvr65kaGxv/G7uE6jD+Y9z3////kwz/GPYyMDHw/P/P8JeZiYnx11+G
	pRcPrnzAwFDPhMOD/wj5Fc1JTuG4nUSepxFWEQxWQpowAACK2kV9eZ56UAAAAABJRU5ErkJggg==
}]

set NextMonth [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAKCAYAAACALL/6AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAAi0lEQVR4nGNg
	wAvqmfDLIwAjLk2MyGx7e3vmL1++MDKLanD+/fFrBdN/hqrTB1dfCA0NZV69evVfvFYY24faGDuG
	ntF19FOHWASxiRFiZeM/fftwBTZmhui///79Z2RkYGb4x/CFgYnBiZGR0eI/03+ns3tWX6mvr2ck
	2lMEAR4nUcfTOIOVAMBUDABKCjuB2+Y90AAAAABJRU5ErkJggg==
}]

} ;# namespace 12x10
} ;# namespace icon
} ;# namespace calendar

# vi:set ts=3 sw=3:
