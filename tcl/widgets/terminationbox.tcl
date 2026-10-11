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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABo0lEQVR4nG1R
	v0scYRB9M7cbIR6injYpE7AIiJAPwxUh63JgEUM04CJeG0hjTol1wpeF9MmBin/BiWxSHCHpwrqY
	Qgh3oJZ2sRU8C8Vc9vvGYr0fRR4MDPPmwZs3QAdac6edLi0UpksLhf9xlJUmILTKXyqDZUWMFACA
	mc9EsNWId2vQmhGGQlprDsPQKj/YJOLnELxDij0ZsESGSpTjD9ak3xrxlzfQmgkAlB+UAXxObXvi
	MKm30Icpb37YYfcEkNVG/HWn4+0tYNf6l5V67T6aCdYOk3qLLCoCXgcAmpwrj7iX7QMyZgZXf86Q
	v//q0vkXDVp3V4BcM35Yeuwd3TOU+9lO7xQ5u5yQug7n83kBybMhHjwVkatmHPlAKMDdrkU+/l47
	B+HCEXhJkqTuNS2JMesPxumlUsoFIIbbT4Vwcfyrdu7cCj8BqE558z8OkqgFYPt3NjeTT+ZGAKmy
	RSVzk+Vrlb+4weS8sGTe01+zb1wYZsdj8EdjTb0ZR5VurD1RsEzEK9basd7j7GYjjnY6O73A+95f
	nA1Gi7PBaB/Z5W4AOeeyH7U9irkAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABEklEQVR4nH2Q
	rU4DURCFv7l7l1LZBF1R2G15BNQSgqtBEJ4DhSNk+TE8BboBwgOQplUo7IZ0u00wKAQC0ja79w6C
	ioa/z0zmnDniDCyhYJbnDxTkv50eBABFFHVf2u3HIoq6y7osElK0Wmtq7bX1/qgy5lKqan99MnkF
	1AySJBDwYm2qcOuD4ENEbtTaUwG/8CHvdLZw7ngehnu1qrqfW7tbK8s7vD+LiuLhq4X3qYhcZFnm
	UO1nWeYw5pwgSAFkHMeHTrXRzvMTgHEc72yMRn2APIpSFXmTPI6vLMxKeBLVwIiEXrVUERfCZgUr
	8txsNly9fuBhFe9VQQUEY8TA7H067f362O+IggySJPjrYHs4dJ9IpXB/lYNlGwAAAABJRU5ErkJg
	gg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABwUlEQVR4nF2Q
	PW/TUBSG33N97TROQe1CxQAMgJAqQRFXzQLEiaFSJFCCCjYFOhV+ACsDQp6Y+BMMDFiqxESQSmMv
	VRcjuhTxsXRAFJJKBRKFNu49DIlRyzsdna/nvAc4KAKAYrF6+P9cJpEFjuNIAKxKsxU+NP5Zlb3F
	YZ33D9Gg+YmM4yBVF73jYsTYYNY1rfkBEezed1xbX59MgUBnBIrjID1fmj3NFj0ThtxkzXPvorAO
	0In8EQRAoIcXDJDK9SummftAQG1ru30GBLs4c2+FmdvQWB4sLWsAoCmnPiaF9ZVIzvFeehuCbM17
	G1bOvp/u/vmYNMPpfR5YyM5ElxkN5nQhicN5gE+a0nrY+7Z5lJl/qIofDY0DABEAgucJtUVvhDAm
	dNrvCNPs6TTtJM2wplz/LZjpenPyaoDg4J+nr9x5fKF08zIAKNePlOsvAYCq+K9V2XueEXD20t1x
	Y7Qv3zfC1rmZ+YL9e0evroY95foRNO9A0CNmjsjAMXGqWs1Zsv9C9sWKqtz6NAK91s/rGwCQLL8s
	g9AypLUowE+TpfDXP8JoXphddFFAAS2j/fNLo7GbmZ1y6mNr8attAPgLGkmzFJOzD84AAAAASUVO
	RK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABqUlEQVR4nHWS
	P2tTYRTGf+e9TbWxOqhLHUunbMnboYh4r23QWlIV6pvoorj0C7i5XO4ncOzo4JartEhTqlbNBQ0I
	uX4BHdzESawopOl9j0PaoqDPfJ7D8w9ArLUlAOdcwAjC/xCGd4/byPVqC60GgLWrR+TaJbdacW78
	zycCYKPWdYw+weuNvJt25ubcxN4EW6DI7unLjcZUkSSJPyDEBhJfjVYWjAk2KYqriFlC5EL+pn3+
	UMnM4uKxT9vbAwNAHBszNB/V++8EwTrI19FxbEYKmq9ODU7c4dBwnudDG7mHCGUCHuPNlnp1H7rt
	53bevRNlb3wwuNbrVX8asACoUAb28530rXi9h/gNG928L8j7/lnqvd6zH5ComZ7+5iE2BPIIWKrW
	b53rd9tPTVFcxJjY7xfrpGlxkJ4emZ4Nm3UCealafAZ5Icaoer8McgbVlbybdsAFAlCLmldE6IgU
	y+p1l2DsNmp+BcNirSgxI0hHoZm/bm8IwGzkQlRK/ay9869ya2GrgfgHJ7U8/9cEnHNBWqmo3fwS
	TE5OaZbhiYEk8WEYjmVZVvwGJMSrKqYZRdcAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABlElEQVR4nG1R
	MUscYRB9M7snmsJwd6mDlYGDK8IiLETFQ7CRiGg+xGvsoyhWKRL4sqBgqaD5CWvgs1FIfa5eYZEl
	CQcH/ockJ5bn3kyKZM8t8mBg4M3w5r0BcljLeTs1v1ydml+u/o+jv2UJiCRorDWJ8VZFqgBAxL9U
	5VPacjGsZUSRkrWWoyiSoGFOmL3XKvreE1wDQMY6y8x7ItlF2jrbgrVMABA0TBPAYf+h9KLTjnvB
	nHkHBaWJO6iFpjI2prcAbactd5rftgvITqcd94wxnoImQHheq5mR7o37DdCOQncBgOuLzbKqjmfE
	VwDIOTcAKQPkd7uuD4BKhIQUT+vTzfLQfQEkihikay/nVlYBIPN5OMedL3GPiO59xSwADUMz+v3S
	JRDaIOKPABTZ4BWI7jvtuJebXgdwlEl/8kdyfleUq08vlkdKT25JdPtrcvaZ/uUrQePNMZO/JCof
	0NdL32cesMwQe/uZZBffirE+Lpl1It4UkWcAwJ73U2VwkrbcaT7zqF14f7hgKuGCqRTIIfcH/Vus
	N2yEHR0AAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABYklEQVR4nG2R
	zUocURCFv6r0LFwY1JEBX8CdCDbCLASnEdwo6mKa4PgI/uFSEC4NkmVUiHkERcaN+ACtOxFGcO0D
	BEwWIZjNpPuWi7adYfBAQd1zTnHrB0o4p2U6u7BWnV1Yq36kSRFOIPFh9KWF2qblVgVQ1d9m/Oik
	F2c4pySJiXNOkyTxYRSfiugyxgEZNwAENOSTHPo8u+6kl1s4pwIQRnELOM58d/Lx9uoPfZieXx0J
	tPIEstNJ2+dlb3vgdwfNAAUnu4btAcjUUmu08q97Z0EQff7/8/lFa/uC1AC82a9he/76tzJR0yxP
	u1mlrr3ZC5j1Pd4wNEiEUXwfRvH6IF9iptHcmIma9wDlDEfAyfT86sigeWpuaVSEYxW+Fb0U+/Vh
	1PyuEqx48wd07YYhwKSh6GHu86uHtL39vtZeUbwuopve+3EoD+dPO2n7vPT0/u47f30xHqsvxmN9
	4rv2CgXuiEuieI1oAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABmUlEQVR4nIWS
	sWtTURjFf999N3kVdDRLh5ZSZ0teOnTpbWIsFgSxr9fWSRR10b/ApZuTo4KL0LU+xEFwMjFBRNTY
	CGK1KLgr1EKEmmdyP5cqBZH+4CznnO0cAFhdNRzEXkf2pFOzi8dswV4AMLne+2WHwRp7KQBRrmuv
	nmVfADGAJtV03trCSw2Mqcp4sNIy2NeqTIoyGQqmU676GqDinLM9Kb3FcGujma0BJFX/QYTbnWZ2
	B6Bc9VdE9frEUSnLzMmzpXxgn8f9fnlnNO7H3/SiEbnx5mk25r2P3kPEV4qHDF2CnTHFfHtb0Z+7
	cXFpM8tyEfkkYkhqyze3duKRzSzLR2AJZXeiNPguABV3rq6RPgohnO62HjSO1/yoRT5rCJcR+WhE
	XgyDLHRb6w2D91Gnff8JIaxEJnqcuHQu/tHraQhbavSIQHOow5Vua72B95EAOOdsu90eJHPpGRVz
	1yDvFMZBD6twbaOZPfzT+btLklwtAEw7f2q6fl4rJ5a1Mpsu7M/+wTlnAabcYj2ppvP7vQMv8L/L
	/AYA/aXUbSHhNQAAAABJRU5ErkJggg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABv0lEQVR4nG2R
	sWtTYRTFz73vvRgFHRJwLIJSpOtnS0Bo+hoICK0U2s+SOohLB6tIB+lQ4eOBg4tQQR38A4L4tYOC
	CC7pwyUIrypCQUHwD9AoIkSSl3sdytMOnunAHc655wcUco4LO9lYqE42Fqr/uxEAgnOEJBETL68Q
	4ZqqVAGAiL+pyqOs49twjpEkQs45TpJETGwfMgfzKroZCF4DQM46zcx3RPLnWWf7OpxjAgAT2xUA
	W/0+zu53fc/M2A0oKEv93VrNVoZH9aMIbrxNt58U3dYB3Nzv+p61NlDQKRDGjFmNul3fE6J1JtwC
	QDzRtBWFnpAgSAGQ934EUhZomGWPh9baoNzPXwEUTk1dPs5BFCkUEBlRMYQo2kzcMvFi03s/GpTK
	Ag0bby6c+cUfXrS/E+FnqJgGoPX6lSPvdn0KYFmgv82s3YzKwR5Rvook0eLpFoD7uQzG36fPfuCQ
	zMyl80QYF5UtCmmMin1NvPSAObwoIrcppw5Kw0hymjh9kl9+/qo7pPQp2/Ub9JfkAYsWEa8dgKNA
	Vb+UGFcHI7T20qf3ANJD4f/w15q2UmvaCgDU6y48N2vXzNzcMQD4A2FkvStQyXRFAAAAAElFTkSu
	QmCC
}]

} ;# namespace 12x12
} ;# namespace icon
} ;# namespace terminationbox

# vi:set ts=3 sw=3:
