# ======================================================================
# Author : $Author: gcramer $
# Version: $Revision: 1517 $
# Date   : $Date: 2018-09-06 04:47:10 -0400 (Thu, 06 Sep 2018) $
# Url    : $HeadURL: https://svn.code.sf.net/p/scidb/code/trunk/tcl/widgets/searchentry.tcl $
# ======================================================================

# ======================================================================
# Copyright: (C) 2014-2018 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source combo-search-box

package require Ttk
package require Tk 8.5
if {[catch { package require tkpng }]} { package require Img }
package require tooltip


proc searchentry {w args} {
	return [::searchentry::Build $w $w {*}$args]
}


if {![namespace exists mc]} {
	namespace eval mc {
		set Key(Ctrl)	"Ctrl"
		set Enabled		"Enabled"
		set Disabled	"Disabled"
	}
}


namespace eval searchentry {

namespace eval mc {
	set Erase					"Erase"
	set FindNext				"Find Next"
	set InteractiveSearch	"Interactive Search"
}


proc makeStateSpecificIcons {img} { return $img }


proc bindShortcuts {w} {
	bind $w <Control-F> [namespace code [list TriggerFindNext $w focus]]
	bind $w <Control-f> [namespace code [list TriggerFindNext $w focus]]
	bind $w <F3> [namespace code [list TriggerFindNext $w findnext]]
}


proc Build {w ns args} {
	array set opts {
		-type				pattern
		-text				{}
		-textvar			{}
		-textvariable	{}
		-ghosttext		{}
		-ghosttextvar	{}
		-ghostcolor		#444444
		-history			{}
		-length			10
		-values			{}
		-postcommand	{}
		-usehistory		{}
		-mode				{}
		-delay			150
		-minlength		4
		-skipfirst		0
		-width			0
		-helpinfo		{}
		-buttons			{}
		-parent			{}
		-takefocus		{}
	}
	array set opts $args

	if {$opts(-type) ni {pattern number}} {
		error "wrong type: should be one of {pattern number}"
	}
	if {[llength $opts(-mode)] == 0} {
		switch {$opts(-type)} {
			number	{ set opts(-mode) enter }
			pattern	{ set opts(-mode) key }
		}
	} elseif {$opts(-mode) ni {key enter}} {
		error "wrong mode: should be one of {key enter}"
	}
	if {[llength $opts(-usehistory)] == 0} {
		set opts(-usehistory) [expr {$opts(-type) ne "number"}]
	}
	if {[llength $opts(-buttons)] == 0} {
		set opts(-buttons) {erase enter}
		if {$opts(-type) eq "pattern"} { lappend opts(-buttons) mode }
	}
	if {"help" ni $opts(-buttons) && [string length $opts(-helpinfo)]} {
		lappend opts(-buttons) help
	}

	namespace eval [namespace current]::${w} {}
	variable ${w}::NS $ns

	namespace eval [namespace current]::${ns} {}
	variable ${ns}::Vars
	variable ${ns}::Priv

	if {[string length $opts(-textvar)] == 0} {
		set opts(-textvar) $opts(-textvariable)
	}
	if {[llength $opts(-ghosttextvar)] == 0} {
		set opts(-ghosttextvar) ::searchentry::${ns}::Vars(ghosttext)
	}
	foreach attr [array name opts] {
		set Vars([string range $attr 1 end]) $opts($attr)
	}
	if {[string length $Vars(ghosttext)]} {
		set $Vars(ghosttextvar) $Vars(ghosttext)
	}
	if {[string length $Vars(textvar)] == 0} {
		set Priv(text) $opts(-text)
		set Vars(textvar) [namespace current]::${ns}::Priv(text)
	}

	set helpcmd [namespace code [list Help $w.e]]
	set findnextcmd [namespace code [list FindNext $w.e]]
	set erasecmd [namespace code [list Clear $w.e]]
	set buttons $opts(-buttons)

	set Priv(current) 1
	set Priv(search) ""
	set Priv(after) {}
	set Priv(lock) 0
	set Priv(content) [set $Vars(textvar)]
	set Priv(empty) [expr {[string length $Priv(content)] == 0}]
	set Priv(findnextcmd) $findnextcmd
	set Priv(focus) ""

	ttk::frame $w -class TSearchEntry -borderwidth 0 -takefocus 0
	bind $w <Destroy> [list namespace delete [namespace current]::${w}]
	bind $w <FocusIn> [list focus $w.e]
	if {$opts(-usehistory)} {
		ttk::combobox $w.e \
			-class TTSearchBox \
			-postcommand [namespace code [list Post $w]] \
			-textvar [namespace current]::${ns}::Priv(content) \
			-takefocus $opts(-takefocus) \
			;
	} else {
		ttk::entry $w.e \
			-class TTSearchEntry \
			-textvar [namespace current]::${ns}::Priv(content) \
			-takefocus $opts(-takefocus) \
			;
	}
	bind $w.e <Escape> [namespace code [list Leave $w]]
	if {$opts(-width) > 0} {
		$w.e configure -width $opts(-width)
	}
	if {$opts(-type) eq "number"} {
		set vcmd { return [expr {%d == 0 || [string match {[0-9.,]*} [string trim "%P"]]}] }
		$w.e configure -validatecommand $vcmd -validate key -invalidcommand { bell }
	}

	grid $w.e -row 0 -column 0 -sticky nsew
	grid columnconfigure $w {0} -weight 1
	set col 0

	if {"erase" in $buttons} {
		ttk::button $w.c \
			-style icon.TButton \
			-image [makeStateSpecificIcons $icon::16x16::erase] \
			-command $erasecmd \
			;
		grid $w.c -row 0 -column [incr col] -sticky ns
	}
	if {"enter" in $buttons} {
		ttk::button $w.r \
			-style icon.TButton \
			-image [makeStateSpecificIcons $icon::16x16::enter] \
			-command $findnextcmd \
			;
		grid $w.r -row 0 -column [incr col] -sticky ns
	}
	if {"mode" in $buttons} {
		ttk::checkbutton $w.i \
			-style Toolbutton \
			-variable [namespace current]::${w}::Vars(mode) \
			-image $icon::16x16::character \
			-onvalue key \
			-offvalue enter \
			-command [namespace code [list SetupButtons $w]] \
			;
		grid $w.i -row 0 -column [incr col] -sticky ns
	}
	if {"help" in $buttons} {
		ttk::button $w.h \
			-style icon.TButton \
			-image [makeStateSpecificIcons $icon::16x16::help] \
			-command $helpcmd \
			;
		grid $w.h -row 0 -column [incr col] -sticky ns
	}

	FocusOut $w.e

	foreach sub {"" .e} {
		if {"help" in $buttons}  {
			bind ${w}${sub} <F1> $helpcmd
			bind ${w}${sub} <F1> {+ break }
		}
		if {"enter" in $buttons} {
			bind ${w}${sub} <F3> $findnextcmd
			bind ${w}${sub} <F3> {+ break }
		}
		bind ${w}${sub} <Control-Key-x> $erasecmd
		bind ${w}${sub} <Control-Key-X> $erasecmd
	}

	if {"enter" in $buttons && [llength $opts(-parent)]} {
		bind $opts(-parent) <F3> $findnextcmd
		bind $opts(-parent) <F3> {+ break }
	}

	ShowButtons $w
	LanguageChanged $w

	set args [list variable [namespace current]::${ns}::Priv(content) \
		write [namespace code [list ContentChanged $w]]]
	trace add {*}$args
	bind $w.e <Destroy> [list trace remove {*}$args]
	bind $w.e <<LanguageChanged>> [namespace code [list LanguageChanged $w]]

	catch { rename ::$w $w.__search__ }
	proc ::$w {command args} "[namespace current]::WidgetProc $w \$command {*}\$args"

	return $w
}


proc WidgetProc {w command args} {
	switch -- $command {
		configure {
			if {[llength $args] % 2 == 1} {
				error "value for \"[lindex $args end]\" missing"
			}
			variable [set ${w}::NS]::Vars
			variable [set ${w}::NS]::Priv
			array set opts $args
			if {[info exists opts(-text)]} {
				set Vars(text) $opts(-text)
				FocusOut $w.e
				array unset opts -text
			}
			if {[info exists opts(-textvariable)]} {
				set opts(-textvar) $opts(-textvariable)
				array unset opts -textvariable
			}
			if {[info exists opts(-textvar)]} {
				set Vars(textvar) $opts(-textvar)
				FocusOut $w.e
				array unset opts -textvar
 			}
			if {[info exists opts(-text)]} {
				set $Vars(textvar) $opts(-text)
			}
			if {[info exists opts(-length)]} {
				set length $opts(-length)
				if {![string is integer $length] || $length <= 0} {
					error "bad arg: argument for 'length' should be integer > 0"
				}
				set valueVar $Vars(history)
				if {[string length $valueVar] == 0} { set valueVar Vars(values) }
				if {[llength [set $valueVar]] > $length} {
					set values [lrange $valueVar 0 [expr {$length - 1}]]
				}
				set Vars(length) $length
				array unset opts -length
			}
			foreach attr [array names Vars] {
				if {[info exists opts(-$attr)]} {
					set Vars($attr) $opts(-$attr)
					array unset opts -$attr
				}
			}
			ShowButtons $w
			SetupButtons $w
			LanguageChanged $w
			if {[array size opts] == 0} { return }
			set args [array get opts]
		}

		cget {
			if {[llength $args] != 1} {
				error "wrong # args: should be \"[namespace current] cget <option>\""
			}
			set attr [lindex $args 0]
			if {[info exists Vars($attr)]} { return $Vars($attr) }
		}

		clone {
			if {[llength $args] != 1} {
				error "wrong # args: should be \"[namespace current] $command <name>\""
			}
			return [Build [lindex $args 0] [set ${w}::NS]]
		}

		findnext {
			variable [set ${w}::NS]::Priv
			if {[string length $Priv(findnextcmd)]} {
				{*}$Priv(findnextcmd)
			}
			return $w
		}

		focus {
			return [SetFocus $w]
		}
	}

	return [$w.e $command {*}$args]
}


proc SetFocus {w} {
	set focus [focus]
	if {$focus ne "$w.e"} {
		variable [set ${w}::NS]::Priv
		set Priv(focus) [focus]
		::focus $w.e
	}
	$w.e selection range 0 end
	return $w
}


proc Leave {w} {
	variable [set ${w}::NS]::Priv

	if {[string length $Priv(focus)]} {
		set focus $Priv(focus)
		set Priv(focus) ""
	} else {
		set focus [winfo toplevel $w.e]
	}
	catch { focus $focus }
}


proc ShowButtons {w} {
	variable ::searchentry::[set ${w}::NS]::Vars

	foreach {sub attr} {h helpinfo i mode} {
		if {[winfo exists $w.$sub]} {
			if {[string length $Vars($attr)]} {
				grid $w.$sub
			} else {
				grid forget $w.$sub
			}
		}
	}
}


proc Clear {w} {
	set ns [set [winfo parent $w]::NS]
	variable ::searchentry::${ns}::Priv
	variable ::searchentry::${ns}::Vars

	set $Vars(textvar) ""
	set Priv(search) ""
	set Priv(search) ""
	set Priv(current) 1
	set Priv(empty) 1
	if {[focus] eq $w} {
		set Priv(content) ""
	} else {
		set Priv(content) [set $Vars(ghosttextvar)]
		$w configure -foreground $Vars(ghostcolor)
		focus $w
	}
	SetupButtons [winfo parent $w]
}


proc FocusIn {w} {
	set ns [set [winfo parent $w]::NS]
	variable ::searchentry::${ns}::Priv

	if {$Priv(empty)} {
		set Priv(content) ""
		set Priv(search) ""
		set Priv(current) 1
	} else {
		$w selection range 0 end
	}
	$w configure -foreground black
	SetupButtons [winfo parent $w]
	set Priv(search) $Priv(content)
}


proc FocusOut {w} {
	set ns [set [winfo parent $w]::NS]
	variable ::searchentry::${ns}::Vars
	variable ::searchentry::${ns}::Priv

	set Priv(focus) ""
	$w selection clear
	if {[winfo exists $w.popdown] && [winfo ismapped $w.popdown]} { return }

	if {$Priv(empty)} {
		set Priv(lock) 1
		if {$Vars(type) eq "number"} { $w configure -validate none }
		set $Vars(textvar) ""
		set Priv(search) ""
		set Priv(content) [set $Vars(ghosttextvar)]
		$w configure -foreground $Vars(ghostcolor)
		if {$Vars(type) eq "number"} { $w configure -validate key }
		set Priv(lock) 0
		SetupButtons [winfo parent $w]
	} else {
		if {![string match $w* [focus]]} {
			UpdateHistory [winfo parent $w]
		}
		set $Vars(textvar) $Priv(content)
	}
}


proc Return {w} {
	set w [winfo parent $w].r
	if {[winfo exists $w]} { $w invoke }
}


proc UpdateHistory {w} {
	if {[winfo class $w] ni {TTSearchEntry TTSearchBox}} { return }

	set ns [set ${w}::NS]
	variable ::searchentry::${ns}::Vars
	variable ::searchentry::${ns}::Priv

	if {$Priv(empty)} { return }
	set content [string trimright $Priv(content) "*"]

	if {[string length $content] < $Vars(minlength)} { return }

	set valueVar $Vars(history)
	if {[string length $valueVar] == 0} { set valueVar Vars(values) }
	set values [set $valueVar]
	set i [lsearch -exact $values $content]
	if {$i >= 0} {
		set values [lreplace $values $i $i]
	} elseif {[llength $values] >= $Vars(length)} {
		set values [lreplace $values end end]
	}
	set $valueVar [linsert $values 0 $content]
}


proc Search {w key} {
	set cb [winfo parent [::ttk::combobox::LBMaster $w]]
	if {[winfo class $cb] ni {TTSearchEntry TTSearchBox}} { return }
	set ns [set ${cb}::NS]
	variable ::searchentry::${ns}::Vars
	variable ::searchentry::${ns}::Priv

	if {[string length $key] == 1} {
		set valueVar $Vars(history)
		if {[string length $valueVar] == 0} { set valueVar Vars(values) }
		set values [set $valueVar]
		if {[llength $values] == 0} { return }
		if {$Priv(current) >= [llength $values]} { set Priv(current) 0 }
		set key [string toupper $key]
		set current $Priv(current)

		while {1} {
			set i $Priv(current)
			if {[incr Priv(current)] == [llength $values]} { set Priv(current) 0 }
			if {[string index [lindex $values $i] 0] == $key} {
				$w see $i
				$w selection clear
				$w selection set $i
				return
			}
			if {[incr i] == [llength $values]} { set i 0 }
			if {$i == $current} { return }
		}
	}
}


proc ContentChanged {w args} {
	set ns [set ${w}::NS]
	variable ::searchentry::${ns}::Vars
	variable ::searchentry::${ns}::Priv

	if {$Priv(lock)} { return }

	if {[string length $Priv(content)] == 0} {
		set Priv(search) ""
		set Priv(empty) 1
	} else {
		set Priv(empty) 0

		if {$Vars(mode) eq "key" && ![string match "$Priv(content)*" $Priv(search)]} {
			after cancel $Priv(after)
			if {!$Priv(empty) && [string length $Priv(content)]} {
				set Priv(after) [after $Vars(delay) [namespace code [list Find $w.e]]]
			}
		}

		set Priv(search) $Priv(content)
	}

	set $Vars(textvar) $Priv(content)
	SetupButtons $w
}


proc SetupButtons {w} {
	set ns [set ${w}::NS]
	variable ::searchentry::${ns}::Vars
	variable ::searchentry::${ns}::Priv

	if {$Priv(empty)} { set state disabled } else { set state normal }
	if {[winfo exists $w.c]} { $w.c configure -state $state }
	if {[winfo exists $w.r]} { $w.r configure -state $state }

	if {[winfo exists $w.i]} {
		switch $Vars(mode) {
			key		{ set tip "$mc::InteractiveSearch ($mc::Enabled)" }
			enter		{ set tip "$mc::InteractiveSearch ($mc::Disabled)" }
			default	{ set tip "" }
		}
		::tooltip::tooltip $w.i $tip
	}
}


proc FindNext {w} {
	set w [winfo parent $w]
	set ns [set ${w}::NS]
	variable ::searchentry::${ns}::Priv

	if {$Priv(empty)} { return [SetFocus $w] }
	UpdateHistory $w

	if {[string length $Priv(content)]} {
		event generate $ns <<FindNext>> -data $Priv(content)
	}
}


proc Find {w} {
	if {![winfo exists $w]} { return }

	set w [winfo parent $w]
	set ns [set ${w}::NS]
	variable ::searchentry::${ns}::Priv

	if {!$Priv(empty)} {
		event generate $ns <<Find>> -data $Priv(content)
	}
}


proc Help {w} {
	set w [winfo parent $w]
	set ns [set ${w}::NS]
	variable ::searchentry::${ns}::Vars

	if {[string length $Vars(helpinfo)]} {
		event generate $ns <<Help>>
	}
}


proc LanguageChanged {w} {
	set ns [set ${w}::NS]
	variable ::searchentry::${ns}::Vars
	variable ::searchentry::${ns}::Priv

	if {[winfo exists $w.h]} {
		if {[string length $Vars(helpinfo)]} {
			if {[info exists $Vars(helpinfo)]} {
				set helpinfo [set $Vars(helpinfo)]
			} else {
				set helpinfo $Vars(helpinfo)
			}

			::tooltip::tooltip $w.h "$helpinfo <F1>"
		}
	}

	if {[winfo exists $w.r]} { ::tooltip::tooltip $w.r "$mc::FindNext <F3>" }
	if {[winfo exists $w.c]} { ::tooltip::tooltip $w.c "$mc::Erase <$::mc::Key(Ctrl)-X>" }

	if {$Priv(empty)} {
		set Priv(content) [set $Vars(ghosttextvar)]
		set Priv(empty) 1
	}
}


proc Post {w} {
	set ns [set ${w}::NS]
	variable ::searchentry::${ns}::Vars
	variable ::searchentry::${ns}::Priv

	if {[llength $Vars(postcommand)]} {
		{*}$Vars(postcommand)
	} else {
		set valueVar $Vars(history)
		if {[string length $valueVar] == 0} { set valueVar Vars(values) }
		set values [set $valueVar]

		if {$Vars(skipfirst) && [llength $values] > 0 && [$w get] == [lindex $values 0]} {
			set values [lrange $values 1 end]
		} else {
			set values $values
		}
		$w.e configure -values $values
	}

	set Priv(current) 1
	set Priv(search) $Priv(content)
	set $Vars(textvar) $Priv(content)
}


proc TriggerFindNext {w cmd} {
	variable Visited

	array unset Visited *
	set Visited(.) 1
	if {[winfo toplevel $w] eq $w} {
		foreach child [winfo children $w] {
			if {[TriggerFindNextRecursively $child $cmd]} { return 1 }
		}
		return 0
	}
	TriggerFindNextRecursively $w $cmd
}


proc TriggerFindNextRecursively {w cmd} {
	variable Visited

	if {[info exists Visited($w)]} { return 0 }
	if {[winfo toplevel $w] eq $w} { return 0 }
	if {![winfo ismapped $w]} { return 0 }
	if {[winfo class $w] eq "TSearchEntry"} {
		$w $cmd
		return 1
	}
	set Visited($w) 1
	foreach child [winfo children $w] {
		if {[TriggerFindNextRecursively $child $cmd]} { return 1 }
	}
	return 0
}


namespace eval icon {
namespace eval 16x16 {

set erase [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB5klEQVR4nKVT
	QWsTURCeSZ9bwZ5yKiFgoaE1geChqPQsCG26kpNrJAeNpyxZW8yhYFtZDzkUj6X1vwj+AXuwUExB
	CtZkNwnL7vNQLJp98HnZjSFLqeIHD95jZh7ffN8MUwQATEQcP5kZNIar4glEBYn7JBgAMzMAXFdK
	3SciFkK8Z+ZhXBjFNaXUAyKCEOIDM/8EwAQgRUQUhmHpUe2lLFet4KzjWgBERJkBiLOOa5WrVmDU
	mkEYhqWIWSoVUxFCYDgM6fjkNG1ttmzHGZgACAA5Ts+0Nlv28clp+tdwyEKIP/0D4OhonY7b0J80
	/MW7OkpGXQ48f8Pz5fqaYcrFezr0ihmzm47rOP4k6lN0e7262WzZ7S9f03duFy4oxTj89PlGfmFO
	7r/dfnMzmzlgZhXXJGwCIHxfrj9+3jwvLOsoLD+EUWuee/73jViXcVdGGiR9pDHbL0dqooWpbm9Q
	f9rYfv3xqD1TvJW7KBYWfhwetWeeNV7tfHN6JoCpKJeTIrr9kYhrRl0OPO9KEUdzAGC1XLXk/NIK
	9IoZdLv9F3GS6/YtvWIG80srKFctCWA1MQdKKda0a1TM5+Te7padzc4eMDMxM2Uys+/2drfsYj4n
	pzUNSqmROP8/ypea8LfLNJH0z+v8G/sgdSgXvemuAAAAAElFTkSuQmCC
}]

set enter [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABfklEQVR4nLVT
	v0tCURQ+5/qoBw3SkilJREgEDQ3RLDSlDi0VQYvVImRDRYG8em8KGoQWiYim+iua/CMcJDLl1UN5
	lEP0Q5733dOgD0x5Txv6pnu/e+759Z2D4AEiQgBA54qI5GXfF22Hv9BDOIaISEQkc86XAAAlSbpH
	RMt584ykqiprO4qtbe3XVzbTbxXdSBOR1J1JJ4GaprXYaJSpAMA5Z5bFWaFY8qePz7TceQaI6BIR
	bSJiiCg8M5GHh8A0X7cTGyljZjFB8fVUvfJs7DkZEBE6BxkAoqWyHkDGbCEAfQzAsiyaCAV9L9Va
	4ug0u/zwpI9Epic/rrInN8HxMRUA3hEAoNFoxJK7ym1ZN0YlyUdAreYiItq2TYwxLgQxq9lkn1/f
	uDA/B9cX6qEsy1nmWUOnMi68awkAAm3ORTAQkKqmGXcroW8TazVzZ5Am9sgI+bxQFCW2mjy4KxQf
	/bORqXruPKOFwyFHRnSV8S+D9D+j7IaBl6nrg+c6/wD0/PnBywZK5QAAAABJRU5ErkJggg==
}]

set help [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADa0lEQVR4nH2T
	W2yTZQCG3+/rf1jZ1p8N68bqDgy7tpycoGKUkIB4osjW4bKtRBLFeMCE+2FitkjQiDFeAJp0MRGS
	doktE7CdilwYYriZc+kGXTfJmm4d1rmu7f609j99XlgMHuJ7/T7Je/E+BOUwxgghhJlMFJqmNwLY
	lJhPNei6gY0tjYsAbnGcaV7Xjb+6AEDuhRlj9eOTMW8gFOmMz845syt5iXKUSdVVefvG5ri3+8DI
	9q0uPyHkl7sMuQd2nR0KnApcjBz89bcsNVcIkCxVWqFQ5DRdh64zSNWVrO/Q/ktvvdrXTwiZZowR
	rgzXnRnyvzd04WKHpmnYt/vR+J5dj8nBK9+1ziUWLAJHCGfmDLlQMPnOhzrLq98ghKQpz3MYn4wd
	Hg6NvsAYg8e9N3zuw3c+8wfDTRNT8RqON5l0g1FN1egWl32FUhj+UOTgRDTu5TkOVFHUBwLBsGcp
	k6M72jf9/O6J4/2yLI8JglBh39B4J+A7ffzZvU+Gc3KRNtRZ5T27d86nlzLUHwp3Kapq4wBsjs8m
	2swVItz7dl0RRWGyVFLM5z851SOKog1AhpqobqLUyK3K8iuHPdHIt9ebZ27POQBs5hLJ1PpsPi9V
	VVbA1WafUhSVEEKKjLEbvs+/+Hj4y6+7l5eza0SRx+OPbP3B6WiNWqore1dyeUsimWqgFP8KI4Rg
	KZN7xh8KH1lIpdfU1kj5l7rd37zs7fookUjmBIEHYwwAwDU12e6stVhyyVT6/pvTs1sYY3RgYADW
	WqlkW18v19dZ1YDv9NsALvM8txgIRl7PrxbQ3Fifa2myLVIAUw57y0zx9xJGr113A9g5ODhoaNCI
	qqm8YbBKAClCyKKqak9Ern7vLpUUuOwb4gBuUkHgU31dz49Y10nG2MSttsEPzp1kjLVz4IqqomYU
	RVkGoDLGHh54/8zJsYmY3bpOMnq69o8IPJ+6e+W6s0OBT30XQp2GYWDHNte058DT19q3OUTKgPHJ
	eCn01dWnforGnJRSvHbkxZFjR3vfJISkufKV04yxfkII84fCHTd+nHKORWNOsygoYEBRUQRV1XFf
	rcXwHnJfOna090SZIf8p03BwtGPm9pwjm12tAQHWStUrjgdbp3s8z13e/tA/ZPofnV2JZKoBAFqa
	bH/qbDIt6Mbfdf4D9XzHxQi25EEAAAAASUVORK5CYII=
}]

set character [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACqklEQVR4nJ1S
	W0hUURRd+5x7nRlrMqxEeloZJCUVhH30QsggNciSIMH6CMP6iqCgL2f6DL8iIgr6iN4ERU+JtAcR
	YmQhSanZmFpiOdnDprFz71l9OMIg0Ufra3P2Pou11t5AGkiKiIBkJsnNrztjtSQ3kwyRFJKCf6Gu
	rk6liDbt2nv4Q9GGHaM7aw9/MMaUp/f/CZL6/JVbx5etq+SK9dts4ZoKnjhz8RzJ0LjK9HmV9nG8
	znvS0lpsrU/HdXwRsPFRcwmAolT/7wSRSAQA0Ns/sPpNZyxfKxHrW+06Dnp6P+ZcvHq7kqQjIjZd
	xbhniUajlmTgRkPTxuFvPzJc17EARET423hoaHpSBqBwogo14aGgpbV9deJXEhVlJbEZ07MTxnjK
	dR2+6Xo//17T0y1jmwInElApwbMXr9Z3x/rmhTOD5sC+6rOFBYueWhJaKz+RTOL6nfsVABYCwvHM
	VGr39H07pfFh84b48DdZvnTx10AgYMtK1sanhCfR93ztas229q4lz9tel2s15hwAnDT5K569fLXK
	dTTaO7unrdlUHYEIkslRAQCtlf0+8lNduXa30vP9y5FIZJCkKBGh42jeufe4uP/j4IxQMINKlEdQ
	SCvBQIZJXafoMZsrP8XjJdFo1IqIdQDQGG/ukfqTW4e+fGVFafHw0eih27Hevgeu6zJ7alZ57YFI
	aVt7ZygzFLSfh4YD5y7d3E/yO4AGAYCRkcTBqj2HjnZ0vfPD4TAWLZg9eOF0/XYArKo5eLXj7fsc
	zzMCEdCSSim9tCB/6NSxIzUOACil7OxZufjxM6GNMQDU5KTnZaaymRQKBXV4cjYAgYhg9LeBJUVr
	PRYgySxjzO6BwXiW8fzYwrxZAwAepAiKu3v6ZgYDGXNEtAIsAMjM3JzmtJn/xx8i/ViQ7H4FTwAA
	AABJRU5ErkJggg==
}]

} ;# namespace 16x16
} ;# namespace icon


::ttk::copyBindings TEntry TTSearchEntry

bind TTSearchEntry <FocusIn>			{ ::tooltip::hide }
bind TTSearchEntry <FocusIn>			+[namespace code { FocusIn %W }]
bind TTSearchEntry <FocusOut>			[namespace code { FocusOut %W }]
bind TTSearchEntry <Return>			[namespace code { Return %W }]
bind TTSearchEntry <Return>			{+ break }
bind TTSearchEntry <<TraverseIn>>	{}

::ttk::copyBindings TEntry TTSearchBox
::ttk::copyBindings TTCombobox TTSearchBox

bind TTSearchBox <FocusIn>			{ ::tooltip::hide }
bind TTSearchBox <FocusIn>			+[namespace code { FocusIn %W }]
bind TTSearchBox <FocusOut>		[namespace code { FocusOut %W }]
bind TTSearchBox <Return>			[namespace code { Return %W }]
bind TTSearchBox <Return>			{+ break }
bind TTSearchBox <B1-Leave>		{ break } ;# avoid AutoScroll (bug in Tk)
bind TTSearchBox <<TraverseIn>>	{}

bind ComboboxListbox <Any-Key> [namespace code { Search %W %A }]

switch -- [tk windowingsystem] {
	x11	{ option add *TTSearchBox*Listbox.background white }
	aqua	{ option add *TTSearchBox*Listbox.borderWidth 0 }
}

} ;# namespace searchentry

# vi:set ts=3 sw=3:
