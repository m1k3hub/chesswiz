# ======================================================================
# Author : $Author$
# Version: $Revision: 1510 $
# Date   : $Date: 2018-08-19 08:42:28 -0400 (Sun, 19 Aug 2018) $
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
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source event-mode-selection-box

proc eventmodebox {w args} {
	return [::eventmodebox::Build $w {*}$args]
}


namespace eval eventmodebox {
namespace eval mc {

set OTB				"Over the board"
set PM				"Correspondence"
set EM				"E-mail"
set ICS				"Internet Chess Server"
set TC				"Telecommunication"
set Analysis		"Analysis"
set Composition	"Composition"

} ;# namespace mc


namespace import ::tcl::mathfunc::max

variable modes {OTB PM EM ICS TC Analysis Composition}


proc minWidth {} {
	variable modes

	set len 0
	foreach mode $modes {
		set len [max $len [string length [set mc::$mode]]]
	}

	return [expr {$len + 3}]
}


proc Build {w args} {
	namespace eval [namespace current]::${w} {}
	variable ${w}::Content

	array set opts {
		-textvar			{}
		-textvariable	{}
		-width			0
		-state			normal
	}
	array set opts $args

	if {[llength $opts(-textvariable)] == 0} {
		set opts(-textvariable) $opts(-textvar)
	}
	if {[llength $opts(-textvariable)] == 0} {
		set opts(-textvariable) [namespace current]::${w}::Content
	}

	ttk::frame $w -borderwidth 0 -takefocus 0
	bind $w <FocusIn> { focus [tk_focusNext %W] }
	set width [expr {max([minWidth], $opts(-width))}]
	ttk::tcombobox $w.__w__ \
		-textvariable $opts(-textvariable) \
		-exportselection no \
		-column mode \
		-state $opts(-state) \
		-width $width \
		-placeicon yes \
		;
	$w.__w__ addcol image -id icon -justify center
	$w.__w__ addcol text -id mode
	pack $w.__w__ -anchor w

	Setup $w

	bind $w <Destroy> [list catch [list namespace delete [namespace current]::${w}]]
	bind $w.__w__ <Any-Key> [namespace code [list Completion $w %A %K $opts(-textvariable)]]
	bind $w.__w__ <<LanguageChanged>> [namespace code [list LanguageChanged $w]]
	bind $w.__w__ <<ComboboxSelected>> [namespace code [list CheckEntry $w]]

	$w.__w__ current 0

	catch { rename ::$w $w.__eventmodebox__ }
	proc ::$w {command args} "[namespace current]::WidgetProc $w \$command {*}\$args"

	return $w
}


proc WidgetProc {w command args} {
	switch -- $command {
		cget {
			if {[lindex $args 0] eq "-takefocus"} {
				return 0
			}
		}

		bind {
			if {1 > [llength $args] || [llength $args] > 3} {
				error "wrong # args: should be \"[namespace current] bind <tag> ?<sequence>? ?<script?>\""
			}
			bind $w.__w__ {*}$args
			return
		}

		focus {
			return [focus $w.__w__]
		}

		valid? {
			set value [$w.__w__ get]
			set index [lsearch -exact [$w.__w__ cget -values] $value]
			if {$index >= 0} { return true }
			if {$value eq "-" || $value eq "\u2014" || $value eq ""} { return true }
			return false
		}

		value {
			variable modes
			set item [$w.__w__ current]
			if {$item <= 0} { return "" }
			return [lindex $modes [expr {$item - 1}]]
		}

		set {
			if {[llength $args] != 1} {
				error "wrong # args: should be \"[namespace current] set <value>\""
			}
			set value [lindex $args 0]
			if {[info exists mc::$value]} {
				$w.__w__ current search mode [set mc::$value]
			} else {
				$w.__w__ current 0
			}
			CheckEntry $w
			$w placeicon
			return $w
		}

		instate {
			if {[llength $args] != 1 && [llength $args] != 2} {
				error "wrong # args: should be \"[namespace current] $command <statespec> ?<script>?\""
			}
			if {[llength $args] == 2} {
				if {[$w.__w__ instate [lindex $args 0]]} {
					return [uplevel 2 [lindex $args 1]]
				}
			}
		}
	}

	return [$w.__w__ $command {*}$args]
}


proc LanguageChanged {w} {
	$w.__w__ forgeticon
	set current [$w.__w__ current]
	Setup $w
	if {$current >= 0} {
		$w.__w__ current $current
	}
}


proc Setup {w} {
	variable modes

	set current [$w.__w__ current]
	$w.__w__ listinsert [list "" "\u2014"] -index 0
	set index 0
	foreach mode $modes {
		$w.__w__ listinsert [list [set icon::12x12::$mode] [set mc::$mode]] -index [incr index]
	}
	$w.__w__ resize
	$w.__w__ mapping [::mc::mappingForSort] [::mc::mappingToAscii]

	if {$current >= 0} {
		$w.__w__ current $current
		CheckEntry $w
	}
}


proc Completion {w code sym var} {
	if {[$w popdown?]} { return }

	switch -- $sym {
		Tab {
			set $var [string trimleft [set $var]]
			Search $w $var 1
			if {[$w testicon]} {
				$w placeicon
			} else {
				$w select none
			}
		}

		default {
			if {[string is alnum -strict $code] || $code eq " "} {
				after idle [namespace code [list Completion2 $w $var [set $var]]]
			} elseif {$sym ne "Down"} {
				after idle [list $w testentry]
			}
		}
	}
}


proc Completion2 {w var prevContent} {
	variable modes

	set content [string trimleft [set $var]]
	set len [string length $content]

	if {$len == 0} {
		$w.__w__ current 0
		CheckEntry $w
	} elseif {$len == 1 && [string is digit -strict $content]} {
		if {$content <= [llength $modes]} {
			$w.__w__ current $content
			$w.__w__ icursor end
			$w.__w__ selection clear
			$w.__w__ selection range 0 end
			CheckEntry $w
		} else {
			$w.__w__ set ""
			bell
		}
	} elseif {[string equal -nocase -length [expr {$len - 1}] $content $prevContent]} {
		$w testicon
		Search $w $var 0
	}
}


proc Search {w var full} {
	set content [set $var]
	if {[string length $content] == 0} { return }

	if {$full} {
		$w.__w__ current search -nocase mode $content
	} else {
		$w.__w__ current match -nocase mode $content
		set newContent [$w get]
		
		if {$content ne $newContent} {
			set k 0
			set j 0
			set n [string length $content]
			while {$j < $n} {
				set c [string index $newContent $k]

				if {[string equal -nocase $c [string index $content $j]]} {
					incr j
				} else {
					incr j [string length [::mc::mapForSort $c]]
				}

				incr k
			}

			$w.__w__ icursor $k
			$w.__w__ selection clear
			$w.__w__ selection range $k end
			CheckEntry $w
		}
	}
}


proc CheckEntry {w} {
	if {[$w get] eq "\u2014"} {
		$w.__w__ set ""
	}
}


namespace eval icon {
namespace eval 12x12 {

set OTB $::icon::12x12::filetypeScidbBase

set PM [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAJCAYAAAAGuM1UAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABAUlEQVR4nJWQ
	L05DQRyEv9/uo4RUYRCcAFt6AF4NAQnJSgyCcABM1UstFhTcgCVcAEKR0LQHwJGQIMH13+vbQbQU
	3UnGzZfJDKwoW1jNveMdy2pHqqpNGQIwYeb9D6l66HfjO2AuhODmqL+BlGPpycl6TtbD8Qgpl3QL
	EEJwWYxRADK+SSRw+/2XuwuAZh4uMY1kNgKIMcrBvB5R1sblOcbHbiu8NVvhFdPn2nj9DFEuJsj9
	j1E2rWeTwXO8LsvhwbQcHg6691fT+mRiKPvLZRSF0elIZpbJnzby8IUxAmjkYcPLb8+sMgCKwpak
	vGsr6cQ5tkh4AByVJMm79qr3L/ULqkxr9vPw8SEAAAAASUVORK5CYII=
}]

set EM [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABiklEQVR4nI2S
	P08UURTFz333zeywuzgGY0GilR0F2bgJsaCASGk7GEP4BnTGRgsbDY0x0a+gsdgtaKBekqUyTgLx
	A1BQUBCCZv8xM/e+a0GWoBZ6q3OTc5rzOwAA4LXDP+/KQ9O3tZzdBQBmb6pCf+rDg+7ZNEDtleyt
	8/xERRsEeJAFAICRM0DY8yiI7ub73Ve0tLRxSxrlOZH7VJbD57NzLMUFNwGAG/VRMRk6z8l7s7Dp
	R/Edx+k4AXBMRIu1uLk3+TFzL+/vnOb9ndNQlPMRJ7sOaBFwzOk48QOtUWwaBpPx6mwt2Ypi7rdX
	n76DWSD2L4LKBzeKPlq9/DrQGjnHhRGBbyf1+rdeZ7tUfQyEdRCeVSprea/zhpo6QwR2XJgPKgR4
	kZ96CQCHvc4RgIc3C7UhT9BQCSrkg08qVEiR0oPWcnYSMbhSKABMtcbVfRjS4JOKAKC9km079huq
	UhHZbxDNKDD7KKh8zve7L6/BLTzK5mIPZvZ2M6AqpIjk+8GXi7+w/880fgFj5KwsEbY1twAAAABJ
	RU5ErkJggg==
}]

set ICS [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABhklEQVR4nH2R
	MWsUYRCGn5lvs1iYBButbIJBVMRijwgaNBdSJNi6IEar2EjyHz62yT84ESSVNmGtAmKldxAtBI9U
	CpIiYJfaILLZb8biuJgi+MLAwMsw8z4DY8Wo47ZYKqeLpXL6LE9GFQUq63TLp6K6ZmbXQVCR7+62
	9bVfvyZGpapcYoxaVZUVC+ULVO/gdoD7RRAQOURkBrfPw369TowqAJ37Dx950Ff2R69K3r4UeIeK
	uLHiTXiu5+yHmT/bG9TbGYCrrAcNR563AxGdxf2Wm4uIXiZP14JmR1i7AWzLzQePL+S/j7+ArgDg
	9qHxfB4gl+aThLToNiFg75vjidsn6f8nM5PTlCi65W4I2ZW2bX+JyCzuP53RSe6+n2XZZGrb/eGg
	vqcAYt5Lls57ExbcfQd8U1Q23X0nKd2U2kmD3mjDiK8V3bKH6F1xO3C3S6AgHILMgO0O+283TrCO
	hzqL5RMhrJnbDQAR/ZZIW3sf6zcQFSr7l+zU++eWV6fmllenzvL+AtAqsFD3t4p9AAAAAElFTkSu
	QmCC
}]

set TC [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABo0lEQVR4nJWQ
	sWsTYRjGf+93lztDrYpYHBwcWhc7aRwytNzVqZsVenTQxb8g4ijIEQdXdRE3B3HxgqVDSye9b8tg
	FCkVSroIdbEiBFsuyd19n0MaiaMvvMvz/h7ehwf+c2S0sUDT3ri52rDWuQzm5KwQKb99fN96PmZO
	DNhrQTSnFLsIb6zlGECEKSx3jGH+s072RxLI9TB67LiVu6YYep20dWkyQi1c/a5cb2iK4nUnfRtL
	ENw6d6QqXZT7hLK8T1nUT6tfhwBHp87PMHDbOM4zTPGwMPkVpfVGz1p56Yg0LNYvlMm0Do3WoSn6
	JrNY3xFpgLz4ojd6CuBTmjzK8v6CIGVhmIamgaZxC++MQJnl/YXOhyQe1QA2CAJ3R68fAFtV12/V
	ltZma0trs+KpBNjc0esHQRC7gJW/9caxBGmqjtXFpyC3R6p5N1X+eKDD0NBs2kkDAPV6VPX9q/lv
	2X0FMG3n7w0GXyvtdpKNGQUQRZEDkFfNSuZ19wRZFGQx87p7edWsTDL/fJhbXvZnygtnh8PSAHie
	ow6dn7397e3BmPkDKrWs0123TW8AAAAASUVORK5CYII=
}]

set Analysis [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABpElEQVR4nHWR
	MWsUURSFz73v7WTAxMK4C1aW4kIKdw12eRssIhgWwTxBUEtLf4EwbiP+A9HWENCHGrKC6xYJE1JY
	OCgiA6IWFmKhSGDHhJ2deddCXcJCbnn5Ps7lHuCwiSIGgLq1wb8FH8rCWgUAqNeDZmtl++yibf+X
	aJI1xug4jotG68qSruiHxWi0AeAqs7/+ZvPpywkhYqDjG+byMpjXtAruFUV+gyBdT9xtL5ze4QlY
	mi17kZR6xOALo71Bn4iqXtGzt1tPttM0pYMJZEykMkq/QuS+Yu5C63dFkX+Y8T/O1Go1cc6V4wRr
	LWdZEgjJN1b6dknYKYtyCaCfA6redM6Vxhg9FpxzZZK82CPPdz1wTXyxkmw97hPkPYA5AMiyU6Sj
	KOJOp+Mbi7YZTh1ZHg53V5PN9S8HLj0nJA8AYHr6o+g0TQkABHzSw98BKp/mjf0NzUc95BZKnIBW
	rwBQHMcl/e3HBmFNnhPxHCC7AEKBhAQ+zkTfvfefq+Gg3ev1huMvzZ+/NAvMgGWk99VQKnno1T7n
	+bF8KvQoX/fdLwD4A1O5qcNXWlSjAAAAAElFTkSuQmCC
}]

set Composition [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABNUlEQVR4nHXS
	sUoDQRAG4H92Q0QLizS+xl32QLC4y140mGCI5LJrbHwMW5/BylorJQSiIClU8FJYqKBPIVhIQAsT
	zO1aSOQ8k78b5ptihgHmRCnFUyXNc1PNAWA1bK945babbrGsDYIgh04ncfxmLbHmiog6xZI6BiwB
	YCyL4zieeIFezy8sXhprzPB9WASh4pV3HQCGZbHjR1XLcQEz2SbQQ2G50IfFW0J4BUAsjd1AbXLO
	e2Rt+/7m7BxAjxitESX7T9enL1CKAThgACCkrgmpx16o6wDghboupB4JGVWyVyNXal+E+kOUogYA
	uP4U69rvIdIpytaRCFqHACBKOw0h9djxo+os/FNYfLJcbsuTOm9h9mDRfB50+9Pd/g1wSycgGhFj
	SzBfG4+33btZeG4yb/En3yGpcUqxYR76AAAAAElFTkSuQmCC
}]

} ;# namespace 12x12
} ;# namespace icon
} ;# namespace eventmodebox

# vi:set ts=3 sw=3:
