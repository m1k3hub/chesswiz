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
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source termination-selection-box

proc terminationbox {w args} {
	return [::terminationbox::Build $w {*}$args]
}


namespace eval terminationbox {
namespace eval mc {

set Normal								"Normal"
set Unplayed							"Unplayed"
set Abandoned							"Abandoned"
set Adjudication						"Adjudication"
set Disconnection						"Disconnection"
set Emergency							"Emergency"
set RulesInfraction					"Rules infraction"
set TimeForfeit						"Time forfeit"
set Unterminated						"Unterminated"

set Result(1-0)						"Black resigned"
set Result(0-1)						"White resigned"
set Result(0-0)						"Declared lost for both players"
set Result(1/2-1/2)					"Draw agreed"

set Reason(Unplayed)					"Game is unplayed"
set Reason(Abandoned)				"Game is abandoned"
set Reason(Adjudication)			"Adjudication"
set Reason(Disconnection)			"Disconnection"
set Reason(Emergency)				"Abandoned due to an emergency"
set Reason(RulesInfraction)		"Decided due to a rules infraction"
set Reason(TimeForfeit)				"%s forfeits on time"
set Reason(TimeForfeit,both)		"Both players forfeits on time"
set Reason(TimeForfeit,remis)		"%causer ran out of time and %opponent cannot win"
set Reason(Unterminated)			"Unterminated"

set Termination(checkmate)			"%s is checkmate"
set Termination(stalemate)			"%s is stalemate"
set Termination(three-checks)		"%s got three checks"
set Termination(material)			"%s wins by losing all material"
set Termination(equal-material)	"Game drawn by stalemate (equal material)"
set Termination(less-material)	"%s wins by having less material (stalemate)"
set Termination(bishops)			"Game drawn by stalemate (opposite color bishops)"
set Termination(fifty)				"Game drawn by the 50 move rule"
set Termination(threefold)			"Game drawn by threefold move repetition"
set Termination(fivefold)			"Game drawn by fivefold move repetition"
set Termination(nomating)			"Neither player has mating material"
set Termination(nocheck)			"Neither player can give check"

set Black						"Black"
set White						"White"

} ;# namespace mc


namespace import ::tcl::mathfunc::max

variable reasons {Normal Unplayed Abandoned Adjudication Disconnection
						Emergency RulesInfraction TimeForfeit Unterminated}


proc buildText {reason result toMove termination variant} {
	switch $termination {
		equal-material - bishops {
			return $mc::Termination($termination)
		}
		less-material {
			if {$toMove eq "white" && $result eq "1-0"} {
				return [format $mc::Termination($termination) $mc::White]
			}
			if {$toMove eq "black" && $result eq "0-1"} {
				return [format $mc::Termination($termination) $mc::Black]
			}
		}
		default {
			if {[info exists mc::Termination($termination)]} {
				return [format $mc::Termination($termination) [set mc::[string toupper $toMove 0 0]]]
			}
		}
	}

	if {([string length $reason] == 0 || $reason eq "Normal") && $result eq "1/2-1/2"} {
		if {[info exists mc::Termination($termination)]} {
			return $mc::Termination($termination)
		}
	}

	if {[string length $reason] == 0} { return ""  }

	switch $reason {
		Normal {
			if {[info exists mc::Result($result)]} {
				return $mc::Result($result)
			}
			return ""
		}

		TimeForfeit {
			switch $result {
				1-0 {
					return [format $mc::Reason(TimeForfeit) $mc::Black]
				}
				0-1 {
					return [format $mc::Reason(TimeForfeit) $mc::White]
				}
				1/2-1/2	{
					switch  $termination {
						mating {
							if {$variant eq "ThreeCheck"} {
								return $mc::Termination(nocheck)
							} else {
								return $mc::Termination(nomating)
							}
						}
						white {
							set mapping [list %causer $mc::Black %opponent $mc::White]
							return [string map $mapping $mc::Reason(TimeForfeit,remis)]
						}
						black {
							set mapping [list %causer $mc::White %opponent $mc::Black]
							return [string map $mapping $mc::Reason(TimeForfeit,remis)]
						}
						default {
							return $mc::Reason(TimeForfeit,both)
						}
					}
				}
				default { return "" }
			}
		}
	}

	return $mc::Reason($reason)
}


proc minWidth {} {
	variable reasons

	set len 0
	foreach reason $reasons {
		set len [max $len [string length [set mc::$reason]]]
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
		-column reason \
		-validate key \
		-validatecommand { return [string is alpha %P] || [regexp {[-]*} %P] } \
		-state $opts(-state) \
		-width $width \
		-placeicon yes \
		;
	$w.__w__ addcol image -id icon -justify center
	$w.__w__ addcol text -id reason
	pack $w.__w__ -anchor w

	Setup $w

	bind $w <Destroy> [list catch [list namespace delete [namespace current]::${w}]]
	bind $w.__w__ <Any-Key> [namespace code [list Completion $w %A %K $opts(-textvariable)]]
	bind $w.__w__ <<LanguageChanged>> [namespace code [list LanguageChanged $w]]
	bind $w.__w__ <<ComboboxSelected>> [namespace code [list CheckEntry $w]]

	$w.__w__ current 0

	catch { rename ::$w $w.__terminationbox__ }
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

		valid? {
			set value [$w.__w__ get]
			set index [lsearch -exact [$w.__w__ cget -values] $value]
			if {$index >= 0} { return true }
			if {$value eq "-" || $value eq "\u2014" || $value eq ""} { return true }
			return false
		}

		value {
			variable reasons
			set item [$w.__w__ current]
			if {$item <= 0} { return "" }
			return [lindex $reasons [expr {$item - 1}]]
		}

		set {
			if {[llength $args] != 1} {
				error "wrong # args: should be \"[namespace current] set <value>\""
			}
			set value [lindex $args 0]
			if {[info exists mc::$value]} {
				$w.__w__ current search reason [set mc::$value]
			} else {
				$w.__w__ current 0
			}
			CheckEntry $w
			$w placeicon
			return $w
		}

		focus {
			return [focus $w.__w__]
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
	variable reasons

	set current [$w.__w__ current]
	$w.__w__ forgeticon
	$w.__w__ listinsert [list "" "\u2014"] -index 0
	set index 0
	foreach reason $reasons {
		$w.__w__ listinsert [list [set icon::12x12::$reason] [set mc::$reason]] -index [incr index]
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
	variable reasons

	set content [string trimleft [set $var]]
	set len [string length $content]

	if {$len == 0} {
		$w.__w__ current 0
		CheckEntry $w
	} elseif {$len == 1 && [string is digit -strict $content]} {
		if {$content <= [llength $reasons]} {
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
		$w.__w__ current search -nocase reason $content
	} else {
		$w.__w__ current match -nocase reason $content
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

set Normal [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACNklEQVR4nEXS
	z0uTcRwH8M/nu0enmWvlUJ9k/lg2ZerULmUq6Yz8AVlBl6CCJCxQIjt06VR0KLBERVI8GJREnZoE
	JqHWbJb0w62U8NEmNnRrOmgqNN32vLsUvf6GFwNgZoaGBUXVWKE74K12+hfMRETl6blKcapxXBJi
	JgYQAJaYmQBovRu/zta/6Gp9s6KUhAURMVMimI6k5boXQ6vdxuSUR8wc4XihIc/6WlO1/V7H/Oaq
	rmFv4XRVhnlqOxaJjfz4dmDi51xZnl5eH228djVHZxggAJZjQx1u6ruETtdoD4AMLWsIwE4AjQOz
	zofUcxH1Q11uABbhDizVOHzfi2pS8z9eKbb1ElFSWI3KT5UP14uf3Wo/ZSoJ1ButU2M+xeoKem2S
	0+8xbwnwSZN10rXmrWuZeNLSmGl9f2f65fEIY0doO+yvzbJMDQfmDk4uL+RJ9JdKRDopUZ0JrmRO
	+ueyDFp9ZNDWdDtTt6cvFP59VxATCwFxKD1XSYCA3eMqN+kNI13lp29UyvlLDyrPtDdkF9wkot3v
	/J6K+ChQJpsUAmCpfd7ppr7LaP/8qhtAAYBSAEkAsnu+jPVTbzPq7J0uABaOExpaXF+7YLPf71A2
	V3cdTTN/KpP3ObRCE+/0ew4PL8+UmpPTQ2Mn2tpydIYBJiIGEOfdCJ5rfj3Y6vDNl2xJTCpACTGi
	Knm/q992vjsjSf+YmSP8vwZTVFULvga91W99HjMRUYVsUopSjOOSELP/avwBzl0XEgs8gyUAAAAA
	SUVORK5CYII=
}]

set RulesInfraction [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAkAAAAMCAYAAACwXJejAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABRUlEQVR4nI2R
	MUgCARiF//9O06jIGiIwGhRzscnBwUEcrEAEKShXNyMEqblWQcqx9gqsLLAtpcFJHFwUGgsz4QIv
	0yz1qrvXIuHoWz7ee9t7RKMKAA/o/H543AbgHM4JgDDgUiN2WGzM+dCIJYoAbP89AAYgdtL3iZo1
	gHbyLF+zBtBJ5xIARAAsMDOIyN1OnoYNLodMpqkZg8sht4/Ow0TkZmYQAFPz4OS6Zg8qvUIl82xe
	6fcKlUzNHlTe9o9vAEwLqtzc6l5mNyaC3pTeYSmN2RZFvcNSGg96U72r3Loqt0Mk+aNlyRepAvAA
	2G3txD8A7AHwSL5IVfJHy/yyvPku6sRPtpjrLArz0DAr6Lip/WiveKovqKo2yV+3+Xj3Irum9hUD
	QL8kkEoaicykE40GxRhavWMAY0RkGtqWiQhDvjXSI3/4YLHKNghFOgAAAABJRU5ErkJggg==
}]

set Adjudication [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACHklEQVR4nGNg
	gIL///8zQWnrleu3z7t05Ub5////+aBijAzIAEmxc3XzxLPqZj7/7b3jvx07db7p////3Cia6hGK
	ZecvX39O3dz3f1ZZ81P3kPRPlm7RP4+cOteMrImpkZHx3////10WrtiwccnKLdqMDP//PXj4jDcj
	MfTpj1+/WHsnLchkYGDQgjqGken////W1S0Tu9r65xk+ff6SLS895sP/f/+4OybMUePiZP+vq6N+
	nYGB4RXMSUwr129PWbt5j6Gbg/kzJQXZz1t2HODj4GD/++nzV6b//xmYQnxd7zAwMLxkZGT8z8DA
	wMCkqa50XUJM+Pude495U+OCn759/5Hxxu0HLBkJYbfZ2VjfphTURZw+d6nq////3IyMjP8Y////
	z3/4+Nnikrqeyt9//rJwsrMxMDAyMnBysL2Jj/DbPmvRWu9//xj4+5qKm81N9ftgwcpx++79hojk
	0ntdE+fuvX7r3mwjx7BvNl5xbxev3LjQ1ivuhWtgyufHj1+kM75//9lxx77DHhzs7FxiokJSX7/9
	+KKrpXLtzbv3Yqn5DbmsrKyfDHTUru87fNqmsjB5DsOuvUemWLhH/9ezDf6vYx3wX93c739cRsWD
	////m+89eKLSLSj1m7Z14P+wxMLnL1+/jmV88+GDy6HDpwO+ffvBwsTExPDn3z9mDWWF+6bGOhMY
	GBgYHj19Hn/05HkDZzuzI2IiImsBZWoPoSNYX48AAAAASUVORK5CYII=
}]

set Disconnection [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACE0lEQVR4nHWR
	XUiTYQCFz/v5TjOnkJFE1k1p0K/lEnVolgwTIQlrBKFhQRdmgaWOSpOoESilkEGIGUWUlT/ZQGSp
	mzLnZInkRVJMxVQGxSdhKzam63TRvOzcHXgOz8WBqqoGq83ZTDIHAOykBACSMSRTScaGuwAAWAed
	zQePGFlV1zBGUr8GD424b5eW1846XBOVYViQFDIvV9/ZP+xMe9s7lA6ihWT9iHsiqcb84BoBTZQm
	IqSREVQUASEEpBBimOSV9dHRj9/09O/dGL/hkWt8MjIQDIaazCZzmm5/u2Ps49XV1aDIytC1IqzS
	Pn3RPZBy+CR3pOYzr+jCyqcv060kExzO8Zv6/OI/JWXXF0keUAAQwPau3sHd2xI3+86ePj7l/abK
	1119uz57Zs0VtQ01AmLl/JmiNgAzEv8iQ6FQVISiBOpMF1vm5r0nunttR10fJvVbtyQEK8tL67Mz
	dfeEED4lPJjPzUr3LHi/b+qwWAuePDT3GAsNU7NfF5lxKGUlO1PnEUL47Ha7XDPs/On7Fe/3B3C3
	se3Y83aLjoLrYrUxyrNXFu3Sj+VqkjNCiFFJMtl0635jx7uB5GJjwXRcnHZpyOFOklIuV5SVuGbm
	FhJfdvbtI9lE0iQBMFITGTAWGsbu3LhcBcBTfelcIoAQgDkAe/y//U2DDnf6e9voKYSfTSKZjP+E
	ZI7VNtKsqqrhL5S7Cmz1lYtjAAAAAElFTkSuQmCC
}]

set Emergency $::icon::12x12::gameflag(~)

set TimeForfeit [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACGklEQVR4nF2S
	3UtTYRyAf7/3vFJYGFGDQYRpMvZ13Fxpiq2wurGLwrrSChFSagwa2LyIQJAVXYSI60YYGZTQTeFN
	RlHtpgwcsx3n3DjM2dhHJ4ZdLLtx5z2/Lvogev6BhwceJCJERGKMgRDCqWbzPXElZUUA8LgcGUtL
	Y1SSpFXDMICIkCMiENEOrbJ52TcW8sfiSZcuBAIBcC5R+xFZKZW0B2az6TEi1ngd51SpbF4auTE+
	uf652NB7pjtptTQjAEBGzdHLNx/cI0VtMhIOGZzzWSAi+7XRCaXVe5Eezj2fJqLe/uFgoX/4ZoGI
	zj6am5+WvRfINzqhEJGdZ7Ibp5cTa7K3s00ZGui7CwB7vm/9qEdEAAB1cOB8IpZInox9SslqNneK
	KSsZi24Y2O5xfGSIGgDsBgKs1WoIAIe4xMqeVvuiLgxMJFULg39AxgAAvnlc9ky+8HVv4Na9O7ow
	vLohtn8bgbucVpUzRkvx1WNCiCZE3CCisWp1a2rh7fuOQPHL4Fp63cEQwS3b1L/Rzu4+evrsxQwR
	Hd5VvxOI6Hi+UI7ML7x7bes8R77gr2jknENJqwxd9d+eyhXKDSe62paPuhxLuiG205lc+6voYldL
	08FqJBwKHDDvn0UAQCKq07TKldD9GX9MSbl1YQAiAkOADo8zMR68HjaZ9j1BxBr+t4ZDzeZ7Esm0
	BRiAW7aplubGqCRJqT9r/ATx8RCt+UYfJgAAAABJRU5ErkJggg==
}]

set Unplayed [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACCklEQVR4nGWS
	T0iTcRzGn9/7+23RpQ4xWo1YgzH3t21uMliiCEXQTboY1CGJcjIjW39OpYtBFJWUFUTCgrTLPLZj
	mYcGtsG7123pXkuNmrwwOoiHYPq+3w4tiHrggefhuTyHDyMixhgjSZKg67p/WV3rU6rLLgAIHnGr
	bqdjjnNeNQwDRMQEYwxEtEtr/jgzfDWTLCm1kK4bAAFcSIgGfeVGQ3titVpeMca2mUkINDa0wcFL
	tybWv2t7euOdclc4sECks1K5FpsvyKHDhw5svpzMjFqtliyIyDuUSiv+7n56PZt/SkQ2wSUILoGI
	bNO5N8/83f00lLqtEJEXSyurI7FjA8bFK+NFIvITkZuIwm27iShw4fJYKXb8tFFf+ZIUSrXuau0Y
	rCfeVVhdb5y4kX5wvdVqSQBgNpuNu2Opez1Ho4Vi+VNErqodEgAAhHb4TxIA9lcXQW+Hahac3heK
	8YFTJ6dy2Yd5ALvb+08ApjuPXmTNJkFhv6cuuV2Ot+Ggp/LhoxKdmc0nAGyZBJdNgssAtmZy+USh
	tBjpDHoXXU77OyaEQENrnjs/cnNi7dvG3t54uBwNBRYAoCRXYvMFOeSwH9ycejw+arPuzzIAjIhM
	mtY8m7n/PFlUaqEd3fj9l0uIhH3l9LXEpMWyb5oxts3+QcOnfv7aV64suQAgFPCoLqd9jnNe+4PG
	L4Xv9OuOw/KgAAAAAElFTkSuQmCC
}]

set Abandoned [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB9UlEQVR4nFWR
	UUhTcRTGz/nfUTAXhkSSL2aBawwJdOVojnVniMbQelkPPUQJPSUtQq9l62bFpbDp8GVI+CIFtafA
	qDCGchXWLCtLGVhoK4hCqVjQbO3erwdN1u/lPJzvO98Hh4mIiQgASomoitZ4vz53ExGIaImZfxKB
	LcwE00TD4NCd0GRyxmWYoEM+93MhMZ6OJ11CCPZ5XNMAosycZAA13b39w6NjU/sqysuykhBi5XvW
	VigUqHxbWd6Emf/89Zutrdn3TAufbafUzGxPnT+IUx2XpgH43y1+jNXJQeNcz41lAMcByO1nwi9d
	/mN48XquW6QXPlQChGa/J0FE6Wt9sfo/hiFOnwjet5VY7zLzeKDl4GTBMJFeWKoUjuqdGSGYH47p
	MhH5KnZs/wGAOtXI4SeJKQWAPPp4wmORBDuqqzIEwKn09ift7jacv9ynAzgZG743Yq9vRYeifYnG
	Rt7sqm3BhasDSQBOCzPPA+jKr+YHHzya8G4psWKvc0928yYJi5lP1oSeqgk0eWe1cEhh5nkGwMwM
	AN7QxZvRhJ6q3Vpqo1xu1fyV+y2a5AOvopoSYmYdABMRkaqqgta+5+m6Enlr3x+Aw92KTvXWHICG
	Ys0G8XhcWjcd0QZuL1+PDK0AOFq8+w8AXJTUCKDx3+WNKkT0F3F9A9xdYCWTAAAAAElFTkSuQmCC
}]

set Unterminated [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACQklEQVR4nDXB
	W0iTYRgA4Pf99pWlZpIVoy7KkrmcS/eLK8slMkntJsKLcgW2CyVkEWRqSGDMiLSDIXlRdIIw6ka6
	qaQowRK1+qc7uNafuWLONoeCx2Ht+9+ueh4kIkREYoyBECJXmQiWuryBbFAJpTxDQJe1o1+j0fhU
	VQUiQo6IQERJkdjsqfqmK47PsjcvIQQCAXCuocICozscjtzRarc8QcS/nHNOsdjsybpzrbd+/JxK
	qyw76NVnZSIAQEAJ0uv3g/l14ejN+11tKuf8ERBRzpkGp3uvpYoe9vR2EVFldW1jqLr2QoiIjjzu
	edFltFRRfYPTTUR7eEAJWuUxv9Gy3+S2245dBYCNi0vLyQgIAKDU2I6ODcvuki8ev1GZmLQyty+g
	E6qKhZJhiCFGACAVVEAhBADATq5h0xXW4o/x+B/0jCvZDP5TAZAxAIC5AlNO4HswvKmlrdOZEOrZ
	+Orq7kbH6fEKa8kgz8vVK5wx+jTq2yeEyETEIBE1zy8staempGyz1TZdd3m+JpklQ7S87MBartdl
	vpPyc7wDQy7T895XF4moIyV5/YfllbgNAMovt3cfX16Jb5c933Rv+4ctyDmHSCRmtzsu3Z4MTacd
	KjK5zJJxZH5+MTH1O6ovtxava73WbdZuzljo7mhp5olEAjMy0p/e62xlzht3HfLYuDQi+yREhDVc
	AwZ9Vjg9bUPS+fqaPq126zNORICIq4yxB0KIYWXiV+mox58tSMXDpUWemZm5XS/fDJwgUGXGWPwf
	npoTqa4OZhYAAAAASUVORK5CYII=
}]

} ;# namespace 12x12
} ;# namespace icon
} ;# namespace terminationbox

# vi:set ts=3 sw=3:
