# ======================================================================
# Author : $Author$
# Version: $Revision: 1511 $
# Date   : $Date: 2018-08-20 08:43:10 -0400 (Mon, 20 Aug 2018) $
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
# Copyright: (C) 2010-2018 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source date-selection-box

proc datebox {w args} { return [datebox::Build $w {*}$args] }

namespace eval datebox {
namespace eval mc {

set Today		"Today"
set Calendar	"Calendar..."
set Year			"Year"
set Month		"Month"
set Day			"Day"

set Hint(Space)	"Clear"
set Hint(?)			"Open calendar"
set Hint(!)			"Set to game date"
set Hint(=)			"Skip entering"

} ;# namespace mc


bind DateBoxFrame <Configure> [namespace code { Configure %W }]
bind DateBoxFrame <Destroy>	[list namespace delete [namespace current]::%W]
bind DateBoxFrame <Destroy>	{+ rename %W {} }


proc validate {y m d {minYear 0} {maxYear 9999}} {
	set error ""
	set result ""

	set y [string trimleft $y 0]
	set m [string trimleft $m 0]
	set d [string trimleft $d 0]

	if {[llength $y]} { append result $y } else { append result "????" }
	if {[llength $m]} { append result ".[Format $m]" } else { append result ".??" }
	if {[llength $d]} { append result ".[Format $d]" } else { append result ".??" }

	if {[llength $y]} {
		if {$y < $minYear || $maxYear < $y} {
			set error InvalidYear
		} elseif {[llength $m]} {
			if {$m < 1 || 12 < $m} {
				set error InvalidMonth
			} elseif {[llength $d] && $d < 1 || 31 < $d} {
				set error InvalidDay
			}
		} elseif {[llength $d]} {
			set error MissingMonth
		}
	} elseif {[llength $m] || [llength $d]} {
		set error MissingYear
	}

	if {[string length $error] == 0} {
		if {[string first "?" $result] == -1} {
			lassign [split $result .] y m d
			if {![::calendar::validDate? $y $m $d]} {
				set error InvalidDate
			}
		}
	}

	return [list $result $error]
}


proc keybar {w keys} {
	set myText ""
	set myTip ""
	set nl ""
	foreach {key tip} $keys {
		append myText $key
		append myTip "${nl}${key}  [set $tip]"
		set nl "\n"
	}
	ttk::label $w -relief flat -text "($myText)"
	bind $w <Enter> [list [namespace current]::tooltip show $w $myTip]
	bind $w <Leave> [list [namespace current]::tooltip hide]
}


proc tooltip {args} {}


proc Build {w args} {
	array set opts [list -minYear [::scidb::misc::minYear] -maxYear [::scidb::misc::maxYear]]
	set opts(-tooltip) [namespace current]::mc::Today
	set opts(-usetoday) 0
	set opts(-skipspace) 0
	array set opts $args

	ttk::frame $w -borderwidth 0 -takefocus 0 -class DateBoxFrame

	namespace eval [namespace current]::$w {}
	variable [namespace current]::${w}::Priv

	set Priv(minYear) $opts(-minYear)
	set Priv(maxYear) $opts(-maxYear)
	set Priv(today) [::calendar::today]
	set Priv(init) $Priv(today)
	set Priv(overhang1) {}
	set Priv(overhang2) {}
	set Priv(last) cal
	set Priv(year) ""

	ttk::entry $w.y \
		-exportselection no \
		-justify right \
		-width 5 \
		-textvariable [namespace current]::${w}::Priv(y) \
		-validate key \
		-validatecommand [namespace code [list ValidateYear $w %P %S %s]] \
		-invalidcommand { bell } \
		;
	bind $w.y <FocusIn> [namespace code [list SetYear $w]]
	bind $w.y <Any-Key> [list after idle [namespace code [list CheckKey $w %A $opts(-skipspace)]]]
	bind $w.y <Tab> [namespace code [list CheckFocus $w y]]
	bind $w.y <Tab> {+ break }
	ttk::label $w.dot1 \
		-text "." \
		-relief flat
		;
	ttk::entry $w.m \
		-exportselection no \
		-justify right \
		-width 3 \
		-textvariable [namespace current]::${w}::Priv(m) \
		-validate key \
		-validatecommand [namespace code [list ValidateMonth $w %P]] \
		-invalidcommand { bell } \
		-cursor xterm \
		;
	bind $w.m <Tab> [namespace code [list CheckFocus $w m]]
	bind $w.m <Tab> {+ break }
	if {$opts(-skipspace)} {
		bind $w.m <Key-space> [list after idle [namespace code [list SkipSpace $w m]]]
	}
	ttk::label $w.dot2 \
		-text "." \
		-relief flat \
		;
	ttk::entry $w.d \
		-exportselection no \
		-justify right \
		-width 3 \
		-textvariable [namespace current]::${w}::Priv(d) \
		-validate key \
		-validatecommand [namespace code [list ValidateDay $w %P]] \
		-invalidcommand { bell } \
		-cursor xterm \
		;
	if {$opts(-skipspace)} {
		bind $w.d <Key-space> [list after idle [namespace code [list SkipSpace $w d]]]
	}
	ttk::button $w.cal \
		-style icon.TButton \
		-image $icon::16x16::calendar \
		-command [namespace code [list Choose $w]] \
		;
	set hint {Space "?"}
	if {$opts(-usetoday)} {
		ttk::button $w.today \
			-style icon.TButton \
			-image $icon::16x16::today \
			-command [namespace code [list Today $w]] \
			;
		set Priv(last) today
		lappend hint "!"
	}
	lappend hint "="
	foreach key $hint { lappend hints $key [namespace current]::mc::Hint($key) }
	keybar $w.hint $hints
	bind $w.hint <<KeybarPress>> [namespace code [list Invoke $w %d $opts(-skipspace)]]
	
	grid $w.y		-row 0 -column 0
	grid $w.dot1	-row 0 -column 1
	grid $w.m		-row 0 -column 2
	grid $w.dot2	-row 0 -column 3
	grid $w.d		-row 0 -column 4
	grid $w.cal		-row 0 -column 6 -sticky ns

	if {$opts(-usetoday)} {
		grid $w.today -row 0 -column 8 -sticky ns
		grid $w.hint -row 0 -column 10
		grid columnconfigure $w 7 -minsize 3
		grid columnconfigure $w 9 -minsize 5
		::tooltip::tooltip $w.today $opts(-tooltip)
	} else {
		grid $w.hint -row 0 -column 8
		grid columnconfigure $w 7 -minsize 5
	}
	grid columnconfigure $w 5 -minsize 5

	::tooltip::tooltip $w.y		[namespace current]::mc::Year
	::tooltip::tooltip $w.m		[namespace current]::mc::Month
	::tooltip::tooltip $w.d		[namespace current]::mc::Day
	::tooltip::tooltip $w.cal	[namespace current]::mc::Calendar

	rename ::$w $w.__w__
	proc ::$w {command args} "[namespace current]::WidgetProc $w \$command {*}\$args"

	return $w
}


proc WidgetProc {w command args} {
	switch -- $command {
		overhang1	{ return [set [namespace current]::${w}::Priv(overhang1)] }
		overhang2	{ return [set [namespace current]::${w}::Priv(overhang2)] }
		date			{ return [CheckDate $w] }
		get			{ return [lindex [CheckDate $w] 0] }
		focus			{ return [focus $w.y] }
		result		{ return [Result $w] }
		valid?		{ return [expr {[string length [lindex [CheckDate $w] 1]] == 0}] }

		value	 {
			lassign [CheckDate $w] result error
			if {[string length $error] > 0} { return "????.??.??" }
			return $result
		}

		bind {
			if {1 > [llength $args] || [llength $args] > 3} {
				error "wrong # args: should be \"datebox bind <tag> ?<sequence>? ?<script?>\""
			}
			foreach attr {y m d} {
				bind $w.$attr {*}$args
			}
			return
		}

		today {
			variable ${w}::Priv
			if {[llength $args] == 0} {
				return $Priv(today)
			}
			set Priv(today) [lindex $args 0]
			if {[llength $Priv(today)] == 0} {
				set Priv(today) $Priv(init)
			}
			return $w
		}

		set {
			if {[llength $args] != 1} {
				error "wrong # args: should be \"databox set YYYY.MM.DD\""
			}
			lassign {0 0 0} y m d
			scan $args "%d.%d.%d" y m d
			SetDate $w [list $y $m $d]
			return $w
		}

		cget {
			if {[llength $args] != 1} {
				error "wrong # args: should be \"[namespace current] cget <option>\""
			}
			if {[lindex $args 0] eq "-state"} { return "normal" }
		}

		icursor - selection { return [$w.y $command {*}$args] }
	}

	return [$w.__w__ $command {*}$args]
}


proc SetYear {w} {
	set [namespace current]::${w}::Priv(year) [$w.y get]
}


proc SkipSpace {w which} {
	variable ${w}::Priv

	if {[${w}.${which} get] == " " || [string length [${w}.${which} get]] == 0} {
		${w}.${which} delete 0 end
		if {$which eq "m"} { $w.d delete 0 end }
		tk::TabToWindow [tk_focusNext ${w}.${Priv(last)}]
	}
}


proc CheckFocus {w which} {
	variable ${w}::Priv

	switch $which {
		y {
			if {[string length [${w}.${which} get]] == 0} {
				$w.m delete 0 end
				$w.d delete 0 end
				set which $Priv(last)
			}
		}
		m {
			if {[string length [${w}.${which} get]] == 0} {
				$w.d delete 0 end
				set which $Priv(last)
			}
		}
	}
	tk::TabToWindow [tk_focusNext ${w}.${which}]
}


proc CheckKey {w key skipSpace} {
	variable ${w}::Priv

	switch $key {
		"?" {
			$w.y delete 0 end
			$w.m delete 0 end
			$w.d delete 0 end
			focus $w.cal
			$w.cal invoke
		}
		"!" {
			if {[winfo exists $w.today]} {
				$w.today invoke
			}
		}
		" " {
			$w.y delete 0 end
			$w.m delete 0 end
			$w.d delete 0 end
			if {$skipSpace} {
				tk::TabToWindow [tk_focusNext ${w}.$Priv(last)]
			}
		}
		"=" {
			if {$skipSpace} {
				tk::TabToWindow [tk_focusNext ${w}.$Priv(last)]
			}
		}
	}
}


proc Invoke {w key skipSpace} {
	update idle ;# required for popup
	if {$key eq "Space"} { set key " " }
	CheckKey $w $key $skipSpace
}


proc Configure {w} {
	variable ${w}::Priv

	if {[winfo height $w] > 1} {
		set Priv(overhang1) [winfo y $w.d]
		set Priv(overhang2) [expr {[winfo height $w] - [winfo height $w.d] - [winfo y $w.d]}]
	}
}


proc Result {w} {
	set y [string trim [string trim [$w.y get]] ?]
	set m [Normalize [string trim [string trim [$w.m get]] ?]]
	set d [Normalize [string trim [string trim [$w.d get]] ?]]

	return [list $y $m $d]
}


proc CheckDate {w} {
	variable ${w}::Priv

	return [validate {*}[Result $w] $Priv(minYear) $Priv(maxYear)]
}


proc Choose {w} {
	variable ${w}::Priv

	set date [::calendar::popup $w.cal -minYear $Priv(minYear) -maxYear $Priv(maxYear) -weekStart 1]

	if {[llength $date] == 3} {
		SetDate $w $date
		after 1 [list tk::TabToWindow [tk_focusNext ${w}.$Priv(last)]]
	}
}


proc Today {w} {
	variable ${w}::Priv

	SetDate $w $Priv(today)
	tk::TabToWindow [tk_focusNext ${w}.$Priv(last)]
}


proc SetDate {w date} {
	variable ${w}::Priv

	lassign $date y m d
	set Priv(y) [Format $y]
	set Priv(m) [Format $m]
	set Priv(d) [Format $d]
	event generate $w <<DateChanged>> -when mark
}


proc Format {value} {
	if {[string length $value] == 0 || $value eq "0"} {
		return ""
	}
	if {[string length $value] == 1} {
		return "0$value"
	}
	return $value
}


proc Normalize {v} {
	if {[string length $v] == 2 && [string index $v 0] == "0"} { return [string index $v 1] }
	return $v
}


proc ValidateYear {w value key current} {
	variable ${w}::Priv

	if {$key eq "="} {
		if {[string length $current] == 0} {
			$w.y insert end $Priv(year)
		}
		return 0
	}
	if {$key eq " "} {
		return 0
	}
	event generate $w <<DateChanged>> -when tail
	set value [string trim $value]
	if {[string length $value] > 4} { return 0 }
	if {[string length $value] == 0} { return 1 }
	if {![regexp {[1-2?][0-9?]*} $value result]} { return 0 }
	if {[string length [string trim $value ?]] == 0} { return 1 }
	if {[string first ? $value] >= 0} { return 0 }
	if {[string length $value] != [string length $result]} { return 0 }
	return 1
}


proc ValidateMonth {w value} {
	event generate $w <<DateChanged>> -when tail
	set value [string trim $value]
	if {[string length $value] > 2} { return 0 }
	if {![regexp {[0-9?]*} $value result]} { return 0 }
	if {[string trim $value ?] == 0} { return 1 }
	if {[string length [string trim $value ?]] == 0} { return 1 }
	if {[string length $value] != [string length $result]} { return 0 }
	if {$value > 12} { return 0 }
	return 1
}


proc ValidateDay {w value} {
	event generate $w <<DateChanged>> -when tail
	set value [string trim $value]
	if {[string length $value] > 2} { return 0 }
	if {![regexp {[0-9?]*} $value result]} { return 0 }
	if {[string length [string trim $value ?]] == 0} { return 1 }
	if {[string first ? $value] >= 0} { return 0 }
	if {[string length $value] != [string length $result]} { return 0 }
	if {$value > 31} { return 0 }
	return 1
}


namespace eval icon {
namespace eval 16x16 {

set calendar [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADG0lEQVR4nE1T
	TWhcVRT+zr33zXN+3rTDMJkxuhIVRRCKq4pQs+kiK9MoptGNMtmJUEktCO1kcCERxVLwB0EXImoi
	JqsarDsXZu2iXbSkxHEmmUkzTfLeZN68uT/HxUyg3+bAd375zjkEAMxMAAhAup8k5yUA3/dvLS0h
	BoClJaSTJDmPMQ8gBsBExACA1dVVOS40NVe93LlYXWwz8xTGYOapi9XF9lz1cueEP8lRzExEZJm5
	3GjuXthutCYYjDt3t+a3G61JALhzd+vV+41WmUBoNHcvMPNtItpjZqJxh8p3P65dX1nfeO3gMPQI
	IN9PEY3cYGYkyZAZ4MLpvJ6bmV5/9+2ZDwC0BQAcRtHZn3+7Odvc2fONsWSdI+ecNsb0jTF955y2
	zpExlpo7Hf+XtZuvh2H4EhGxAoBu9+CUNlYVC6dsEGRsLpO2y/XFzSRJmmPhnrxS++xs7zhWUa8v
	BolWcTJ8mZn/JADYae9de+e9q/W9B/su/ViKmMkpTxqtDQgEqQQb4zwChHWWk6ERLzz71P73X3+8
	IADAOUcgwDpHSikSgmgwSBgMq40xxtiUp6SQSsJaNxIGI6MAYDgw23E8QD6Xpa8+v/ZNZaK4yRav
	HITRM/lcNrbO/j7U5uGgPzhXvVRbEELgi0+ufOsrf0MBAJPTzjkIIZAPgj+KhUJnfuHD5a3tZunM
	i8/bLz+9uqEU/dRqtUHAAjMjjHr/lEvFRI2nGa0TQNTv+wACIUQQRpG8t/Wv/K/VeqJWq6kwjv2T
	4xJCpIgIAo+CGUE6RUrJWzeWP7peLJzGUA+hhLhdr9dNNp0ePhrMzCMNrHVEALQxw+5B9Ny9+403
	tdZeuVTsMzNSKf9Mo7mr97sPn7bWaaVk6kRMAoDw+Hhm5q33f2139mU+yGgplUcE1sYwAHhKgZmF
	tVaH0bH3eLlk13648UY+n10XABBkMpvzs9Mrk5VSTykJgDUzG09J6ylpmdkC0EpJTFYmenOz0ytB
	kPkbAGj8TMzMk0dHR+cedA+zQgoGJJzVBABCegxYOOuoMlHs5XK5v4hoh5npfx6Qto1F/+n2AAAA
	AElFTkSuQmCC
}]

set today [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADG0lEQVR4nE1T
	TWhcVRT+zr33zXN+3rTDMJkxuhIVRRCKq4pQs+kiK9MoptGNMtmJUEktCO1kcCERxVLwB0EXImoi
	JqsarDsXZu2iXbSkxHEmmUkzTfLeZN68uT/HxUyg3+bAd375zjkEAMxMAAhAup8k5yUA3/dvLS0h
	BoClJaSTJDmPMQ8gBsBExACA1dVVOS40NVe93LlYXWwz8xTGYOapi9XF9lz1cueEP8lRzExEZJm5
	3GjuXthutCYYjDt3t+a3G61JALhzd+vV+41WmUBoNHcvMPNtItpjZqJxh8p3P65dX1nfeO3gMPQI
	IN9PEY3cYGYkyZAZ4MLpvJ6bmV5/9+2ZDwC0BQAcRtHZn3+7Odvc2fONsWSdI+ecNsb0jTF955y2
	zpExlpo7Hf+XtZuvh2H4EhGxAoBu9+CUNlYVC6dsEGRsLpO2y/XFzSRJmmPhnrxS++xs7zhWUa8v
	BolWcTJ8mZn/JADYae9de+e9q/W9B/su/ViKmMkpTxqtDQgEqQQb4zwChHWWk6ERLzz71P73X3+8
	IADAOUcgwDpHSikSgmgwSBgMq40xxtiUp6SQSsJaNxIGI6MAYDgw23E8QD6Xpa8+v/ZNZaK4yRav
	HITRM/lcNrbO/j7U5uGgPzhXvVRbEELgi0+ufOsrf0MBAJPTzjkIIZAPgj+KhUJnfuHD5a3tZunM
	i8/bLz+9uqEU/dRqtUHAAjMjjHr/lEvFRI2nGa0TQNTv+wACIUQQRpG8t/Wv/K/VeqJWq6kwjv2T
	4xJCpIgIAo+CGUE6RUrJWzeWP7peLJzGUA+hhLhdr9dNNp0ePhrMzCMNrHVEALQxw+5B9Ny9+403
	tdZeuVTsMzNSKf9Mo7mr97sPn7bWaaVk6kRMAoDw+Hhm5q33f2139mU+yGgplUcE1sYwAHhKgZmF
	tVaH0bH3eLlk13648UY+n10XABBkMpvzs9Mrk5VSTykJgDUzG09J6ylpmdkC0EpJTFYmenOz0ytB
	kPkbAGj8TMzMk0dHR+cedA+zQgoGJJzVBABCegxYOOuoMlHs5XK5v4hoh5npfx6Qto1F/+n2AAAA
	AElFTkSuQmCC
}]

} ;# namespace 16x16
} ;# namespace icon
} ;# namespace datebox

# vi:set ts=3 sw=3:
