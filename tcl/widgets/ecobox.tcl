# ======================================================================
# Author : $Author$
# Version: $Revision: 1507 $
# Date   : $Date: 2018-08-13 08:17:53 -0400 (Mon, 13 Aug 2018) $
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

::util::source eco-selection-box

proc ecobox {w args} {
	return [::ecobox::Build $w {*}$args]
}


namespace eval ecobox {
namespace eval mc {

set OpenEcoDialog "Open ECO dialog"

}


bind EcoBoxFrame <Destroy>		[list namespace delete [namespace current]::%W]
bind EcoBoxFrame <Destroy>		{+ rename %W {} }
bind EcoBoxFrame <FocusIn>		{ focus [tk_focusNext %W] }

bind EcoBoxFrame <<TraverseIn>> {
	%W.entry instate {!readonly !disabled} {
		%W.entry selection range 0 3
		%W.entry icursor 3
	}
}


proc Build {w variant args} {
	namespace eval [namespace current]::${w} {}
	variable ${w}::Content

	array set opts {
		-textvar {}
		-textvariable {}
	}
	array set opts $args

	if {[llength $opts(-textvariable)] == 0} {
		set opts(-textvariable) $opts(-textvar)
	}
	if {[llength $opts(-textvariable)] == 0} {
		set opts(-textvariable) [namespace current]::${w}::Content
	}

	ttk::frame $w -borderwidth 0 -takefocus 0 -class EcoBoxFrame
	ttk::entry $w.entry \
		-textvariable $opts(-textvariable) \
		-exportselection no \
		-width 4 \
		-validate key \
		-validatecommand [namespace code { ValidateEco %P %S }] \
		-invalidcommand { bell } \
		-cursor xterm \
		;
	grid $w.entry -row 0 -column 0 -sticky ew
	grid columnconfigure $w {0} -weight 1
	if {$variant eq "Normal" && [llength [namespace which -command openEcoDialog]]} {
		set linespace [font metrics [$w.entry cget -font] -linespace]
		set size [expr {$linespace >= 16 ? 16 : 12}]
		ttk::button $w.eco \
			-style icon.TButton \
			-image [set icon::${size}x${size}::dialog] \
			-command [namespace code [list OpenEcoDialog $w]] \
			;
		grid $w.eco -row 0 -column 2 -sticky wns
		grid columnconfigure $w {1} -minsize $::theme::padx
		tooltip $w.eco [namespace current]::mc::OpenEcoDialog
	}

	bind $w.entry <Any-Key> [namespace code [list Completion $w.entry %A %K $opts(-textvariable)]]
	bind $w.entry <<LanguageChanged>> \
		[namespace code [list LanguageChanged $w.entry $opts(-textvariable)]]

	catch { rename ::$w $w.__w__ }
	proc ::$w {command args} "[namespace current]::WidgetProc $w \$command {*}\$args"

	return $w
}


proc tooltip {args} {}


proc OpenEcoDialog {w} {
	set eco [openEcoDialog $w]
	if {[string length $eco]} { $w set $eco }
}


proc WidgetProc {w command args} {
	switch -- $command {
		bind {
			if {1 > [llength $args] || [llength $args] > 3} {
				error "wrong # args: should be \"[namespace current] bind <tag> ?<sequence>? ?<script?>\""
			}
			bind $w.entry {*}$args
			return
		}

		cget {
			if {[llength $args] != 1} {
				error "wrong # args: should be \"[namespace current] cget <option>\""
			}
			if {[lindex $args 0] eq "-takefocus"} {
				$w.entry instate disabled { return 0 }
				return 1
			}
		}

		valid? {
			set value [string range [$w.entry get] 0 2]
			return [regexp {([A-E][0-9][0-9])?} $value]
		}

		value {
			return [string range [$w.entry get] 0 2]
		}

		set {
			if {[llength $args] != 1} {
				error "wrong # args: should be \"[namespace current] set <value>\""
			}
			set var [$w.entry cget -textvariable]
			set $var [lindex $args 0]
			Completion2 $w.entry $var no
			return $w
		}

		instate {
			if {[llength $args] != 1 && [llength $args] != 2} {
				error "wrong # args: should be \"[namespace current] $command <statespec> ?<script>?\""
			}
			if {[llength $args] == 2} {
				if {[$w.entry instate [lindex $args 0]]} {
					return [uplevel 2 [lindex $args 1]]
				}
			}
		}
	}

	return [$w.entry $command {*}$args]
}


proc LanguageChanged {w var} {
	Completion2 $w $var no
}


proc ValidateEco {eco key} {
	switch [string length $eco] {
		0 { return 1 }
		1 { return [expr {$eco eq " " || [string match {[A-Ea-e]} $eco]}] }
		2 { return [string match {[A-Ea-e][0-9]} $eco] }
		3 { return [string match {[A-Ea-e][0-9][0-9]} $eco] }
	}

	return 0
}


proc Completion {w code sym var} {
	if {$sym eq "Tab"} {
		after idle [namespace code [list Completion2 $w $var no]]
	} elseif {$sym in {BackSpace Delete}} {
		$w delete 3 end
	} elseif {[string is alnum -strict $code] || $code eq " "} {
		$w delete 3 end
		after idle [namespace code [list Completion2 $w $var yes]]
	}
}


proc Completion2 {w var selection} {
	set content [string trimleft [string toupper [set $var] 0 1]]
	set len [string length $content]

	if {$len == 0} {
		set $var ""
	} elseif {[string length $content] >= 3} {
		set content [string range $content 0 2]
		set opening [::scidb::app::lookup ecoCode $content]
		lassign $opening long short
		set vars [lrange $opening 2 end]
		append content " \u2013 "
		if {[llength $vars]} {
			append content [::mc::translateEco $short]
			append content ", " [::mc::translateEco [lindex $vars end]]
		} else {
			append content [::mc::translateEco $long]
		}
		set $var $content
		if {$selection} { $w selection clear }
	} else {
		set $var [string range $content 0 2]
	}
}


namespace eval icon {
namespace eval 12x12 {

set dialog [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABd0lEQVR4nIWR
	sYoTcRDGfzObvTM5hShesFHhSgshyRVntbG4BxD9N2JzTV7C2gcRxCaKD2Chi41NThBir3IQghgu
	GrOr+5+xSDZg5Qcz8M18zMzHABBCSPgXsoktas22ePv40V7if24Qk18f3jz/DNC9+/AmSWxFSb98
	fP1sCSD9/jDl0vyJqt43txLkAu5f13vkOnipojuV2Uv9cfmxxv15GxhW7icXrdVLV37osHRYrlZ+
	mK7o4X6iMIz783bDYiWJNM5K89M8f1oARXfwYALw6f2L7wC3snDaVM4sVqIbC6kWyd7WrNPEadZ8
	00sBGrXp3Z1SsyxLABaIANT8p5VaS9fZsfG7V1PAAbqDsATI3+bVZt60PwgGIHeO73XKKhmr6Ajk
	mpl9Q7yHiwBjVb0KPjW3sNuIfY3nrQKXBe4Hjk1E7LcgV0Roi3rp2AT3A1wW8bxVAHB0FJr8B7Vm
	++kQQjKbzQQgz9e3Z1nWAOh0Oj4ajSLAX9Mwne83fuAAAAAAAElFTkSuQmCC
}]

} ;# namespace 12x12
namespace eval 16x16 {

set dialog [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB7UlEQVR4nJWT
	v2tTURiGn++cJBWcHHrt2IIELHZoqqAg3ARHu54O3f0rHGIG8Y9w1uVKoYOrTYqgS1tKiyBEaUcT
	WkEC+XXP+RySm1xbHPpO332438t77nuuMJc450yn0xGAKIo0SZIAEMexzV7KcZ2v1uuGm2q6I9nz
	2tPnd0ql2zGqayCKcGpLxU8+HQlBajOucjJKe/snnz/+nhlUau5FwRZfh+AXNYQugLF20fv0F4C1
	hbvB+y6AGLNojOmmPn15uJe8nURXtkPwF17Hy5vx6tJmvLo0SvsrInIpIpejtL+Sca/j5RDCBco2
	QHaOnobQPtrbOc+OdNzaPUNpo7SPW7tnGT/a2znXENoCPYDCJAAGKELdNJvN6QetA98WpvM/XCd8
	PEswTaHQCFEUaRRFCo2AoMh1LrkKb17fFRWyQScXyWYXyTlnf3aZzXn+ozuvPzMQgWGSJD7vvlFz
	Q4BrvOqGCnZmINBH5MFG1b1DqACo6hGq9wAq1a33Iro+3T8AKYvqaS6BFoulW+XRcPBHYB9VAXlo
	rL0P4H06ANlHVVRkvVRaKI+H/e9zA+Nf+XTw5rCZfMlHrcRbjwEOWx++5vmjZ+4Jxg+n6fOqmzie
	9N1qtTyzuvK8GqARruzVjXPOckXOOfs/nv2NfwHD+uvgJ4DquQAAAABJRU5ErkJggg==
}]

} ;# namespace 16x16
} ;# namespace icon

} ;# namespace ecobox

# vi:set ts=3 sw=3:
