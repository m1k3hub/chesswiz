# ======================================================================
# Author : $Author$
# Version: $Revision: 1260 $
# Date   : $Date: 2017-07-09 04:43:36 -0400 (Sun, 09 Jul 2017) $
# Url    : $URL$
# ======================================================================

# ======================================================================
# Copyright: (C) 2008-2013 Gregor Cramer
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAHZklEQVR4nOVa
	T4xVVxn//b5zzn0z/OlATTGadqPoYoAG+qitjekF0gXRGJjSi0mhrrQrMXHbhY/ZdKMr25WJ0Qgk
	Ns+hrVFDQirz1FSQTjFY3sLAyhrjNC0UGODd8+dz8eaVmarz7pt507Txl9y85OZ+f875/p7vPOAT
	Dn7EdP2gq8R3Ho2GNBoNWT32DcGA/AfYyYYAkwkA8rxYdw1rLHANKa5dkTXEzCmwARtwK7RazZsf
	ltUPVYUTgNYf37eNbmQSSR9V6MjwLE4QvA3BOQT//TdaL7/Vk9mPsq+5ei6zM5/YSldrGWMnQH6G
	5EZShvRwI8jPGuMmYNzvH959YMtC2StawDw0iXneGLfRl52Oahp6sKkm9WWnY6zbGFWeR0Xz9nMh
	AtDxvFg3Sr1CkftU5/kqroOaUNHUS/GHUkDcAwCkQFN8x7uRz108fXyuH39bSUwHGUbhAJAkVNO1
	oGZHCub9ZSq+CGLimGW8QMoGQAHChRudGoC5frSVFmCsU6Bc+Ernbtv3Lv/5xPXlqbwYm790KI6t
	jYt2uSuzP1Ytp39UqOZC/wmuHQ33bvvK02YYSogJY1hmda+0ADFzCs0UXf9XgGOW6S9wcXhBDN6j
	qkoKoUzZiK9UyCotYG60c3us466DuBeqClAoHBtaS0R02UITSAK4/r69cacKab8YUAC8fOpUB8q3
	SYEqFegJHA56vFSpXf3x98unTnVQwbp9gzjPcwMAhJ4XEQV7DNWnpO+q6jXVdPXub5XnLk1K+i6g
	HvNChKJKvLFQ9lLo60KbNm3SLm/zm5TS96AgSAXZUcY9mZW3Ywwsg8aqjZ2YOc0sjTFOO8HcT02v
	A7BQZdJI1fTbhbKXQuVmbrwo3Mg7uGiM+WJK0RubZcF3jr85/ctnsLxAJgDdkR847rKRQzGUpYhx
	Mca/3ZnFg+1201fhWakO5Hlu2s1mSeEPxRgqVIIvo3XZ4frup44A0PHxIiuKwswr9j+foihMvf6s
	A6D1XQe+67LaoeDLqFARY0jgB+12s6ziPr1dqPZdo8F8GnJDLv3JmmxnCGUghSJiksYjM79rvggA
	84tAc3xcMTnZ3cFGg0W7zdnZWbZarQAA9d0Hj4jIj1JKUTWptZkNoTy/Xrc81tqFNE87NBdCo9GQ
	ycnJtDM/uBUGZwGuSSklEiLGMcV4HMDRmTMvXVmKz4682CxGjhpjDsXgVRVJRATQW9T4yPkzU5d6
	sqroNVAiL4rCNJvNuH3XgX3W2JNQSEohkqSxmcQYbgL6sip+nYi3HEf+BQBe73xaFFsJ/Too+42x
	62Iok6qqiDUgUkxp4sKZ5q96MqrqNHAlyvPctlqtUM+f3E/jToiYNSGUCjCJ0IjpJrbgfSRwEwAU
	WGedMwCQYkBKGgEVazOmFG9pCk/PTE+92uM9iD4DN3OtVisURWFmWidfKcvOjhTDH8UYAEpV1RB8
	CN5HEobCMQrHSJjgfQzBB1VVQCnGIMXwhxD89pnpqVeLojCDKr+sBSxE5hxX1E0QdC6tqB9Ztgs9
	9HgxIU5OkGY0hVJ1oQspEIKPJG4AgCrWW+sM+F9cSOMtDf7QTOvkK6vuQj0z1/Mn94szU1AdjaET
	Qah1zihwI3j/85jKg9S4VcRvFvGbNcm2mMqD0ftjCty0zhkSGkInQnUNbTa1fdeBfT33HESnZaZR
	ngMwejeN2vk0yr5ptL77G58HcFSMOZzih9OoPHL+zC8GSqNVDzScBFCvP+uSvPdTK9maBYWMyYcj
	M63+hQwAms2XrgB4pr6nOCdiXkgpIaUYrc3WhlD+LM8bX54EKp8zKlngA7/fXXzbuezH3ncClLTO
	GV/6IxdazRfHx4tsyxbEZrO55M4VRSGXLsG0282yvqf4jjHuheB9BFWdq9lQlt+amW7+pGo8DNjM
	6V+NsV/oNnMuC94fe3O6+U2soJl7aNdTx6yrHV7UzN2HB9vNas1c3wX0KuPO/OATdOZ0DCGSFBBz
	EH3MCf4Ro19BO53uF5XXAa5R1WSsMSH4Jy5MT71WpSr3jYHZ2VkCgDJ+zYjTSCighGpNA894wgBW
	rZCQsqIVMqakmhJIlQhqhu6AVIVGyfhVAK/1ZK9oAa1Wq7sDlHpKid0DDQDQifBT3a96cgYpK91v
	SeCD06mCSRMJPLxI9hLoVwcIQPfu3VsD9AHVBFK76nN4dxw9XqSy22noA5v37q1h/ky+FG2lNPrP
	27VRS97TDSkS3VnsKsxGya45uH4srB8B0OnHoNICUlxLuJKAgiRXfzaqUt7JKnUJy53MrfpstCr+
	P2ajMXjCLXq16rPRGHylLFHNhWooofAguueR1Z2NAgpv19f6BjBQYbTYaDSk3WreVOCcsY6qWgJA
	96QlG0nZsIL7sS6tcAwAVLU01lLBsxdPH5+bvyNb2WhxHhSNz8Xgr7qsViNl6BfdpNBltVoM/qph
	eg4Vq+JA16w784mtNG5SFY8qdHSY16wAbwtxVqNvDHLN+rG56Pa4FdrLuOgeDJ/svxoMha4fVvnP
	Hh9D/Bsu0lfCy4oKgAAAAABJRU5ErkJggg==
}]

} ;# namespace 48x48
} ;# namespace icon
} ;# namespace progressbar
} ;# namespace dialog

# vi:set ts=3 sw=3:
