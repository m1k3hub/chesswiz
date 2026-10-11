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

::util::source time-mode-selection-box

proc timemodebox {w args} {
	return [::timemodebox::Build $w {*}$args]
}


namespace eval timemodebox {
namespace eval mc {

set Mode(normal)	"Normal"
set Mode(rapid)	"Rapid"
set Mode(blitz)	"Blitz"
set Mode(bullet)	"Bullet"
set Mode(corr)		"Correspondence"

} ;# namespace mc


namespace import ::tcl::mathfunc::max

variable modes {normal rapid blitz bullet corr}


proc minWidth {} {
	variable modes

	set len 0
	foreach mode $modes {
		set len [max $len [string length $mc::Mode($mode)]]
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

	catch { rename ::$w $w.__timemodebox__ }
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
			if {[info exists mc::Mode($value)]} {
				$w.__w__ current search mode $mc::Mode($value)
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

		path {
			return $w.__w__
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
		$w.__w__ listinsert [list $icon::12x12::Mode($mode) $mc::Mode($mode)] -index [incr index]
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
			if {[string is alnum -strict $code] || $code in {" " "?" "*"}} {
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
	} elseif {$content in {" " "?" "*"}} {
		$w.__w__ set ""
		$w forgeticon
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

# set Mode(normal) [image create photo -data {
# iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
# RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABlElEQVR4nG1R
# MUscYRB9M7snmsJwd6mDlYGDK8IiLETFQ7CRiGg+xGvsoyhWKRL4sqBgqaD5CWvgs1FIfa5eYZEl
# CQcH/ockJ5bn3kyKZM8t8mBg4M3w5r0BcljLeTs1v1ydml+u/o+jv2UJiCRorDWJ8VZFqgBAxL9U
# 5VPacjGsZUSRkrWWoyiSoGFOmL3XKvreE1wDQMY6y8x7ItlF2jrbgrVMABA0TBPAYf+h9KLTjnvB
# nHkHBaWJO6iFpjI2prcAbactd5rftgvITqcd94wxnoImQHheq5mR7o37DdCOQncBgOuLzbKqjmfE
# VwDIOTcAKQPkd7uuD4BKhIQUT+vTzfLQfQEkihikay/nVlYBIPN5OMedL3GPiO59xSwADUMz+v3S
# JRDaIOKPABTZ4BWI7jvtuJebXgdwlEl/8kdyfleUq08vlkdKT25JdPtrcvaZ/uUrQePNMZO/JCof
# 0NdL32cesMwQe/uZZBffirE+Lpl1It4UkWcAwJ73U2VwkrbcaT7zqF14f7hgKuGCqRTIIfcH/Vus
# N2yEHR0AAAAASUVORK5CYII=
# }]

# set Mode(normal) [image create photo -data {
# iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
# RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABlElEQVR4nG1R
# MUscYRB9M7snmsJwd6mDlYGDK8IiLETFQ7CRiGg+xGvsoyhWKRL4sqBgqaD5CWvgs1FIfa5eYZEl
# CQcH/ockJ5bn3kyKZM8t8mBg4M3w5r0BcljLeTs1v1ydml+u/o+jv2UJiCRorDWJ8VZFqgBAxL9U
# 5VPacjGsZUSRkrWWoyiSoGFOmL3XKvreE1wDQMY6y8x7ItlF2jrbgrVMABA0TBPAYf+h9KLTjnvB
# nHkHBaWJO6iFpjI2prcAbactd5rftgvITqcd94wxnoImQHheq5mR7o37DdCOQncBgOuLzbKqjmfE
# VwDIOTcAKQPkd7uuD4BKhIQUT+vTzfLQfQEkihikay/nVlYBIPN5OMedL3GPiO59xSwADUMz+v3S
# JRDaIOKPABTZ4BWI7jvtuJebXgdwlEl/8kdyfleUq08vlkdKT25JdPtrcvaZ/uUrQePNMZO/JCof
# 0NdL32cesMwQe/uZZBffirE+Lpl1It4UkWcAwJ73U2VwkrbcaT7zqF14f7hgKuGCqRTIIfcH/Vus
# N2yEHR0AAAAASUVORK5CYII=
# }]

set Mode(normal) [image create photo -data {
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

# set Mode(rapid) [image create photo -data {
# iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
# RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABkElEQVR4nIWS
# T2sTYRDGf/PuJmaLbamgH8CDSAUPRksLgTTUgEjx9ka0J7+GB5e9+hGCtLkotHstZUGpKAUhsHgV
# Knr3It0Ek3bzvuPBRksuznGeP8MzM8JM1Tc35yq/oiWAcm70M9/fH51DCmCmRGttALFhGLWcCXed
# CXcZRi1A9YLhX0Ga7nlIPOJL79yxqjvGcAbI2qqtzQhiA6L1VqcnJuwKjL1nrMrLlfaT76c1HgE0
# m80wtNYGaZq4O+v2haquBoPidr+fFQB3Nzr3nPPbBr01nSCALC/bSu0aX9Sz9flj+qnReLo0rkwy
# jx6pK1+ZIDyguHIjz7sTA2h0NVxA0GoYfCOOzSgoH6swKC4NnocVfoAolweLgBpAGM6foMjZxF0n
# SXwQVd/kh3vtr1l26l31pirKcP4EEGOtNXneLUXYMYbeyoOthX72ugC0ft8uIrojsJ3n3dJaa+Tf
# lhJfb3V6IrKh+Ld/Apq2qn+Xv0+fTTly4SZy7trAm4fgwXGQf0iPptjsV0Acm//1fgOYOqqWxtAH
# MQAAAABJRU5ErkJggg==
# }]

set Mode(rapid) [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABkElEQVR4nIWS
	T2sTYRDGf/PuJmaLbamgH8CDSAUPRksLgTTUgEjx9ka0J7+GB5e9+hGCtLkotHstZUGpKAUhsHgV
	Knr3It0Ek3bzvuPBRksuznGeP8MzM8JM1Tc35yq/oiWAcm70M9/fH51DCmCmRGttALFhGLWcCXed
	CXcZRi1A9YLhX0Ga7nlIPOJL79yxqjvGcAbI2qqtzQhiA6L1VqcnJuwKjL1nrMrLlfaT76c1HgE0
	m80wtNYGaZq4O+v2haquBoPidr+fFQB3Nzr3nPPbBr01nSCALC/bSu0aX9Sz9flj+qnReLo0rkwy
	jx6pK1+ZIDyguHIjz7sTA2h0NVxA0GoYfCOOzSgoH6swKC4NnocVfoAolweLgBpAGM6foMjZxF0n
	SXwQVd/kh3vtr1l26l31pirKcP4EEGOtNXneLUXYMYbeyoOthX72ugC0ft8uIrojsJ3n3dJaa+Tf
	lhJfb3V6IrKh+Ld/Apq2qn+Xv0+fTTly4SZy7trAm4fgwXGQf0iPptjsV0Acm//1fgOYOqqWxtAH
	MQAAAABJRU5ErkJggg==
}]

set Mode(blitz) [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABZklEQVR4nHWS
	L0hDURTGv3Pfm2E8HANZEcvAMoTBnua7GQw2xWsxCQaTGNYf6xaNGiwWucFmlWsaurdZxCJDsI3B
	mAzB7e4ei4M9pyedwzl853f+ALNGAKCU8v7IQUwHURQJALwqd1faXdSlVMG0SMIBQEop0W5nBeZ7
	z0S0TDRcSNtefzAYUBzHo0QrKaUPAGFFXYQV1Qor6vGXYJJXaz0ulXf2QHTqW6xZj5+IxA0RvbNz
	vYA7Z8YYS4gigVrNFdfVos+ou7HYaN1fv5SkqpJHOQCHYH4LXKdULpediH5wfIdbEGWEz/slqapN
	o0+cpUsw94fObhpjbG2CJKX0B5Q7IiGyzLzE7LbG7BU9cg3BOG4YfTXBnhkKAIUV9cCAB6DZvNMH
	UkrfGGMTaw3DMBUEAX/62QzzXJeZX/GRLeTzPae1dgA4cbg4jq0xxqZt6ouZGxhjO47PR4VCgSfF
	/9rUW8wgfwMVhZ4ojTz0cQAAAABJRU5ErkJggg==
}]

set Mode(bullet) [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABoklEQVR4nH2R
	vWtUQRTFz71vZnE3EEFMXhMUBJsUaZ6CqIgPXUWsRGf9QAmkiGJhZ2E1DP4BmsaQ9Co6SFAsgiQb
	ogjC5olVsEohgSQEEoJFzL7MXKsNiou/4hSXc+Hce4AuGGOSLmPak7+wluFcHDxhDvRU+bqQHI0I
	U1+bbz4BIP7Tm2WjGs7FLDc3e2rJt4BwDiQ1En53PG+cASCdBbLWclFMlll+9QKBxgPFR1rte78w
	6+8B8lxErnUiEQABwMfyxjAIEwJcpBDT/enAy6315ZEIukzAbDHnxxUADNWv9OugXxNzKTE8LJp+
	LjtvDm1trt4RgEnktK7QaOcG0aW6lCh9SkL8vtD0Y4DlYsb/kIA1ED8VogdfPvgNYwwTABqq367p
	cuczK90bQ7mxvYaT1VTusqo8Rru80Zr309Zads5FBiAq7BiBbLZmXhwBcLia4gkEt+Lur/uteT89
	aEzFORf3esjOmmeskjyGsELEvZwkWSjbH7f7qF5dWpKiKMrO6xUAsGCSOfkZd8Pielx9dVDSBhS9
	XfS+3bXc//CP+Tc+V6ob9vn1bAAAAABJRU5ErkJggg==
}]

set Mode(corr) [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAA/0lEQVR4nG2R
	PUoDURRGz/fmZQwEfzAw7iCVCHEFGcFiBAvBF7eRXldkCjsVLHQFFi5jIIJphEneuxb5cQS/9p7L
	PZdPrCLAjs8uj7raHaXYeACX5cvGfb9+vDzUG8YBhBAcQJ66t05WSRpIGjhZ5aO/azMeoK5rAUi2
	Z6gH7AMY6smMNuMAiqIwgGR6SnHRF+ke0zTFRd/QY5sRv3FAGpbXz17ZIYiY4uz9bVptZtsLIYQM
	SMNRuMnkOmbLidliIrFzWoYxkNbMamHrJ6vk/KfhxoYbu6wzE3bRZnzbz0xzYQBfK187MNP8vx8E
	2Mn5VZGnvEwxrnvIlo1r/vTwA33QbT4k4xtVAAAAAElFTkSuQmCC
}]

} ;# namespace 12x12
} ;# namespace icon
} ;# namespace timemodebox

# vi:set ts=3 sw=3:
