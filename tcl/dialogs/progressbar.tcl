# ======================================================================
# Author : $Author$
# Version: $Revision: 1260 $
# Date   : $Date: 2017-07-09 04:43:36 -0400 (Sun, 09 Jul 2017) $
# Url    : $URL$
# ======================================================================

# ======================================================================
# Copyright: (C) 2008-2013 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

package require Tk 8.5
if {[catch { package require tkpng }]} { package require Img }
package provide progressbar 1.0

namespace eval dialog {

proc progressBar {path args} {
	return [progressbar::open $path {*}$args]
}

namespace export progressBar

namespace eval progressbar {
namespace eval mc {

set Interrupt "Stop"

}

namespace export open

variable ticks 300

variable Priv


proc busyCursor {w state} {
	if {$state eq "on"} {
		$w configure -cursor watch
	} else {
		catch { $w configure -cursor {} }
	}
}


proc open {w args} {
	variable icon::48x48::hourGlass
	variable icon::16x16::stop
	variable Priv
	variable ticks

	array set opts {
		-title			""
		-message			"Busy..."
		-information	""
		-maximum			0
		-interrupt		0
		-topmost			0
		-close			1
		-transient		1
		-class			Dialog
		-mode				determinate
		-variable		{}
		-command			{}
		-parent			{}
	}
	array set opts $args

	tk::toplevel $w -relief solid -class $opts(-class)
	set parent $opts(-parent)
	if {[llength $parent] == 0} {
		set parent [winfo parent $w]
	}
	set Priv(interrupted:$w) 0
	set Priv(interruptable:$w) $opts(-interrupt)
	setTitle $w $opts(-title)
	wm iconname $w ""
	wm resizable $w false false
	wm protocol $w WM_DELETE_WINDOW {#}
	if {[string length $parent]} {
		if {$opts(-transient)} { wm transient $w $parent }
		wm group $w $parent
	}
	wm attributes $w -topmost $opts(-topmost)
	catch { wm attributes $w -type dialog }
	
	tk::label $w.l \
		-image $hourGlass \
		-text $opts(-message) \
		-compound left \
		-wraplength [expr {$ticks - 50}] \
		-justify left \
		;

	set options {}
	if {[llength $opts(-variable)]} { lappend options -variable $opts(-variable) }
	if {$opts(-mode) eq "determinate"} { lappend options -maximum $opts(-maximum) }
	ttk::progressbar $w.p \
		-orient horizontal \
		-mode $opts(-mode) \
		-length $ticks \
		{*}$options \
		;
	
	tk::label $w.m -text " "

	if {$opts(-interrupt)} {
		variable icon::16x16::stop
		ttk::button $w.i -text $mc::Interrupt -command [namespace code [list interrupt $w]] -takefocus 0
		if {[info exists stop]} {
			$w.i configure -image $stop -compound left
		}
		bind $w.i <ButtonRelease-1> [list after idle [list $w.i state pressed]]
	}

	grid $w.l -row 1 -column 1 -sticky we
	grid $w.p -row 3 -column 1 -sticky we
	grid $w.m -row 5 -column 1 -sticky w

	grid rowconfigure $w {0} -minsize 10
	grid rowconfigure $w {2} -minsize 15
	grid rowconfigure $w {4} -minsize 5
	grid rowconfigure $w {6} -minsize 10

	grid columnconfigure $w {0 2} -minsize 10

	if {$opts(-interrupt)} {
		grid $w.i -row 7 -column 1 ;# -sticky we
		grid rowconfigure $w {8} -minsize 10
	}

	if {[string length $opts(-information)]} {
		setInformation $w $opts(-information)
	}

	bind $w.l <Destroy> [namespace code [list Cleanup $w]]
	wm withdraw $w
	update idletasks

	set rw [winfo reqwidth $w]
	set rh [winfo reqheight $w]
	set sw [winfo workareawidth  $parent]
	set sh [winfo workareaheight $parent]
	if {$parent eq "."} {
		set x0 [expr {($sw - $rw)/2 - [winfo vrootx $parent]}]
		set y0 [expr {($sh - $rh)/2 - [winfo vrooty $parent]}]
	} else {
		set x0 [expr {[winfo rootx $parent] + ([winfo width  $parent] - $rw)/2}]
		set y0 [expr {[winfo rooty $parent] + ([winfo height $parent] - $rh)/2}]
	}
	set x "+$x0"
	set y "+$y0"
	if {$::tcl_platform(platform) ne "win32"} {
		if {$x0 + $rw > $sw}	{ set x "-0"; set x0 [expr {$sw - $rw}] }
		if {$x0 < 0}			{ set x "+0" }
		if {$y0 + $rh > $sh}	{ set y "-0"; set y0 [expr {$sh - $rh}] }
		if {$y0 < 0}			{ set y "+0" }
	}
	wm geometry $w ${x}${y}
	wm deiconify $w
	if {[tk windowingsystem] == "x11"} {
		# prevent error 'window ".progress" was deleted before its visibility changed'
		catch { tkwait visibility $w }
		if {![winfo exists $w]} { return }
	}
	if {[llength $opts(-command)]} { busyCursor $w on }
	if {[llength $opts(-command)] == 0} { return }
	after idle [namespace code [list Start $w $opts(-command) $opts(-close)]]
	focus -force $w
	ttk::grabWindow $w
	tkwait window $w
	ttk::releaseGrab $w
	if {[llength $opts(-command)]} { busyCursor $w off }
	update idletasks
}


proc maximum {w} {
	return [$w.p cget -maximum]
}


proc ticks {} {
	return [set [namespace current]::ticks]
}


proc tick {w {amount 1}} {
	$w.p step $amount
}


proc interruptable? {w} {
	return [set [namespace current]::Priv(interruptable:$w)]
}


proc interrupted? {w} {
	variable Priv
	return [expr {[info exists Priv(interrupted:$w)] && $Priv(interrupted:$w)}]
}


proc interrupt {w} {
	variable Priv

	if {$Priv(interruptable:$w)} {
		set Priv(interrupted:$w) 1
		event generate $w <<Stop>>
	}
}


proc setInformation {w msg} {
#	if {[string length $msg]} { grid $w.m } else { grid remove $w.m }
	$w.m configure -text $msg
}


proc setMessage {w msg} {
	$w.l configure -text $msg
}


proc setTitle {w title} {
	set t [tk appname]
	if {[llength $title]} { append t " - $title" }
   wm title $w $t
}


proc setMaximum {w maximum} {
	$w.p configure -value 0
	$w.p configure -maximum $maximum
}


proc Start {w command close} {
	{*}$command
	if {$close} { destroy $w }
}


proc Cleanup {w} {
	unset [namespace current]::Priv(interrupted:$w)
}


namespace eval icon {
namespace eval 16x16 {

# user may overwrite
# set stop [image create photo -data {}]

};# namespace 16x16
namespace eval 48x48 {

set hourGlass [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAJDUlEQVR4nN1a
	e3CU1RX/nXu/bx95QwiSQZBXCGmqMJJMAY1Kw1AfM4oI4tjxDx0d1I4KUkiLSsApqViEoPVVqI52
	po/E0mqrqBErEKqWDAU0whJIAqIIeYeQ3f2+797TP3ZXQyTst0uY0f5mdmZ3Z79zzu/ec84959wF
	vuegRB9gZkrmObfiiYgviGQiAi6c4f1UuVeTzA4MB3AJAA+AwVotAmABOEJEJxN50Ij3A2YmIgIz
	G11dPfMfq3jmnkBDU76jlJnAQsXRARhS2vl5YwOdnZ0bMzMzq4nIYWbEc6m4BACAiLirp2fePYtX
	bKg/0DjMkAIYLOtjYEZ9oDE3cKjphy89vVoT0Z/hwkPEuWUyERFrrXPWbnh5YX2gcVhqqs8xTQOJ
	+Gk8EBFM00Bqqs+pDzQOW7Nh071a6xwi4mjSGBDxdoAQ8fMxgUON+YYUrLWWUkprZO5FbYYhzMEg
	4Dja/upka7bSyjSE4MChxnwAYwC09LEhKQIxeJTWBkDkOBoXj76o7e9/eGYRgGPxFMRB7NmL59zx
	QGXz0eO5IEJEFzxuBLgl8LWBzAxDSg+Ao0T0UcImn0048zRDSg/zGevgalHOGQMDQWvWAFQyzw4A
	FZWZMNzuAIDIfmtmmIbhAXA5MwsAJoCklCOygDaAKaZheJgZIsHk4JaABoiZGaYh+YvjJzMW3LVk
	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
}]

} ;# namespace 48x48
} ;# namespace icon
} ;# namespace progressbar
} ;# namespace dialog

# vi:set ts=3 sw=3:
