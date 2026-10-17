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
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB7ElEQVR4nE2S
	MWhTURiFz7u5976X2tA2MWkMHULAClUohYrEFETFQURtMlYcMjgVhI5uTio6qMVBVESLdjBYFMHS
	xWLRKhKUFEwglhJBOtjG8Ib0Jbm593dJtGf8OMt3OEAnthQgIk5ErMuIiBERt6XoIlhEFAVw5vXi
	u+GNyq/IHr/fO5Ya/2kAvP/wJe41mk4iPvT7/OkTZQBvrVJ54+W12w8za8UfkEKg1VLYG+wDAGz/
	cSGlQEspjI7sx5WZSwu8vF4Jf86vITs1+T2VHHve3GkO35x9PAUAt67OzNs9dvnjp28Xnsy/Olhe
	r4R5ve6V+gK9E2OHDiyfnDhyXan26P2nL84BwKnjR+8IwQtvFpdjC4HekXrdK3FDpA2RtVWt6XQ6
	4wPgU0qZjqMvnc74tqo1bYgsQ6QZs6zuKjqXy2kADfxPo8M0ADDLYswYo40xGNo3GCWiFIBxIQST
	QjAAh4koFYsNRo0xMMZobjsiAsDcffDs7I3ZR5M9fr/ertYcAEhfvHxvx/OY33E0AGM7IsJCA/0J
	zjlTqh0Ih4KbUogWLCZgMSGlaIZDwU2l2gHOOQsN9CdQc93symp+yfO8aSKKE1Hya6E4ly8U54go
	SUTxuudNr6zml2qum+1ewLdLFFIKSCF2o3+dv5hs47mCfzYHAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACQ0lEQVR4nJXR
	T0gUcRjG8e87Ozbz2wx0N3WrjRLCjpEUmRlEdOlal6CgutQhIqlLWccgO3fKoC4JHUKoDlpELbT9
	QcKoKJVQkf6tpmllO7PuzLwdXMXEqN7Tw+flvbyPqKoAIiIR/zGqagEq88AF0kCyROPA+1JePc/H
	gI8i4gPYqprwvMKRq+0dO551v0x//fZjOUCiYtnYti31Q6hKtrundmJyKjnrDZs2fMjn8xljTJtM
	T0+fPX76wvlHT3sIwwjXdQAl7xUoX2oAmPrpETcOIPh+gVjMYvvWei61njln50bGE739A8SNE+3b
	s7undk36PsDg8PtdN2/dqwc4enDvnA8Nf9h1o6Ozvrd/wMqNjCdsRfsVgnjc2KeOHWozrnMFwPML
	g3c6M5cBFvrtrkybqgaK9ttBEAQaRaoi9PUN5v3CNABv+gbzUTRTzHzvm3VVDYIgsBDmmnCcJbHZ
	HJ+XnT9kBLEW67fU8T/5b+D7haKIRCIS+X6h+DcHsFEUFBCtq1ubVtXNAGEYpplZsLgrKGqLJWW2
	XSae72tzy8UTn3KjJwFWpqrDMIwEoLmltflT7sucF4tFNa4rM7eWVadgT0x+17sPH6+KmzgAr96+
	wymzFaDrwZOVS+Mz/rr3HQLqplzbtqw6O1VTNbF+XS3JygrZ2bT5cXV1IguQGx3fnn32ohGgqWHj
	k1R18tGsZ7LPG5cnK0nVVE2IqlZOed7hGMSMMddd1/lcetwKzyvsBzDGaf/dvQMhhOXGXFvYyn/P
	Lw86Nfsmtg98AAAAAElFTkSuQmCC
}]

} ;# namespace 16x16
} ;# namespace icon

} ;# namespace ecobox

# vi:set ts=3 sw=3:
