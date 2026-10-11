# ======================================================================
# Author : $Author$
# Version: $Revision: 1262 $
# Date   : $Date: 2017-07-09 05:20:02 -0400 (Sun, 09 Jul 2017) $
# Url    : $URL$
# ======================================================================

# ======================================================================
# Copyright: (C) 2009-2013 Gregor Cramer
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

package require Tk 8.5
package require choosecolor
package require place
if {[catch { package require tkpng }]} { package require Img }
package provide colormenu 1.0

namespace eval colormenu {
namespace eval mc {
set BaseColor			"Base Color"
set UserColor			"User Color"
set UsedColor			"Used Color"
set RecentColor		"Recent Color"
set Texture				"Texture"
set OpenColorDialog	"Open Color Dialog"
set EraseColor			"Erase Color"
set Close				"Close"
}

variable baseColors {
	\#0000ff \#00ff00 \#00ffff \#ff0000 \#ff00ff \#ffff00
	\#000099 \#009900 \#009999 \#990000 \#990099 \#999900
	\#000000 \#333333 \#666666 \#999999 \#cccccc \#ffffff
}

variable selection {}
variable useGrab true

namespace import ::dialog::choosecolor::getActualColor
namespace import ::tcl::mathfunc::min

namespace export popup

proc popup {parent args} {
	variable ::dialog::choosecolor::userColorList
	variable selection
	variable useGrab
	variable haveTooltips

	if {![winfo exists $parent]} {
		return -code error "window name \"$parent\" doesn't exist"
	}

	set disableParent false
	set showEraser false
	set recentColorList {}
	set usedColorList {}
	set baseColorList {}
	set hasParentArg false
	set dlgArgs {}
	set userActions {}
	set textureList {}

	if {!$useGrab && [catch {$parent cget -state}]} { set disableParent true }
	set key [lindex $args 0]

	while {$key != ""} {
		if {[llength $args] <= 1} {
			return -code error "no value given to option \"$key\""
		}

		set value [lindex $args 1]
		set args [lreplace $args 0 1]

		switch $key {
			-recentcolors {
				set recentColorList [set $value]
				lappend dlgArgs $key $value
			}

			-usedcolors {
				set usedColorList $value
			}

			-basecolors {
				if {[llength $value]} {
					set baseColorList $value
					set n [llength $baseColorList]
					if {$n % 6} { lappend baseColorList {*}[lrepeat [expr {6 - ($n % 6)}] {}] }
				}
			}

			-textures {
				set textureList $value
			}

			-eraser {
				if {![string is boolean $value]} {
					return -code error "option \"$key\": value should be boolean"
				}
				set showEraser $value
			}

			-parent {
				set hasParentArg true
				lappend dlgArgs $key $value
			}

			-action {
				if {[llength $value]} {
					if {[llength $value] != 3} {
						return -code error "option \"$key\": value should be {<name> <icon> <tip>}"
					}
					lappend userActions {*}$value
				}
			}

			default {
				lappend dlgArgs $key $value
			}
		}

		set key [lindex $args 0]
	}

	if {!$hasParentArg} { lappend dlgArgs -parent [winfo toplevel $parent] }

	set point [expr {[winfo toplevel $parent] == "." ? "" : "."}]
	set top [winfo toplevel $parent]${point}__colormenu__
	if {[winfo exists $top]} { return }
	
	menu $top -tearoff false
	wm withdraw $top
	tk::frame $top.f -relief raised -borderwidth 2
	set bg [$top.f cget -background]
	pack $top.f

	bind $top <ButtonPress-1> [namespace code [list ClearSelection $top %X %Y]]
	bind $top <ButtonPress-2> [namespace code [list ClearSelection $top %X %Y]]
	bind $top <ButtonPress-3> [namespace code [list ClearSelection $top %X %Y]]
	bind $top <Deactivate> [namespace code { set selection {} }]
	bind $top <Destroy> [namespace code [list ClearTooltips $top %W]]
	if {!$useGrab} { bind $top <FocusOut> [namespace code [list ClearSelection $top]] }

	set colorList {}
	if {[llength $recentColorList]} { set colorList $recentColorList }

	set col		0
	set row		1
	set count	0
	set colors	[concat $baseColorList]
	set nb		[llength $baseColorList]
	set nu		0
	set nd		0
	set nr		0
	set nt		0

	foreach color $userColorList {
		if {[llength $color] == 0 && ($nu == 0 || $nu % 6 == 0)} { break }
		lappend colors $color
		incr nu
	}
	if {$nu % 6} { lappend colors {*}[lrepeat [expr {6 - ($nu % 6)}] {}] }
	foreach color $usedColorList {
		if {[llength $color] == 0 && ($nd == 0 || $nd % 6 == 0)} { break }
		lappend colors $color
		incr nd
	}
	if {$nd % 6} { lappend colors {*}[lrepeat [expr {6 - ($nd % 6)}] {}] }
	foreach color $recentColorList {
		if {[llength $color] == 0 && ($nr == 0 || $nr % 6 == 0)} { break }
		lappend colors $color
		incr nr
	}
	if {$nr % 6} { lappend colors {*}[lrepeat [expr {6 - ($nr % 6)}] {}] }
	foreach texture $textureList {
		if {[llength $texture] == 0 && ($nt == 0 || $nt % 6 == 0)} { break }
		incr nt
	}
	if {$nt % 6} { lappend textureList {*}[lrepeat [expr {6 - ($nt % 6)}] {{} 0 {}}] }

	set actions [list palette [set [namespace current]::icon::16x16::palette] [Tr OpenColorDialog]]
	lappend actions {*}$userActions
	if {$showEraser} {
		lappend actions erase [set [namespace current]::icon::16x16::eraser] [Tr EraseColor]
	}
	lappend actions close [set [namespace current]::icon::16x16::crossHand] [Tr Close]

	set buttonList {}
	set buttonRow {}

	set col 0
	foreach {name icon tip} $actions {
		set f [tk::label $top.f.$name \
			-highlightthickness 1 \
			-highlightcolor black \
			-highlightbackground $bg \
			-background $bg \
			-takefocus 1 \
			-borderwidth 1 \
			-width 16 \
			-height 16 \
			-image $icon \
		]
		grid $f -column $col -row $row
		bind $f <ButtonPress-1> [namespace code [list set selection $name]]
		bind $f <Return> [namespace code [list set selection $name]]
		bind $f <space> [namespace code [list set selection $name]]
		bind $f <Escape> [namespace code [list set selection close]]
		bind $f <Enter> { focus %W }
		lappend buttonRow $f
		Tooltip $f $tip
		incr col
	}
	lappend buttonList $buttonRow

	grid rowconfigure $top.f [expr {$row - 1}] -minsize 2
	grid rowconfigure $top.f [expr {$row + 1}] -minsize 8
	incr row 2
	set col 0
	set buttonRow {}

	foreach color $colors {
		set actual ""
		if {$color != ""} {
			set actual [getActualColor $color]
			if {$actual == ""} {
				return -code error "option \"$key\": invalid color \"$color\""
			}
		}
		set f [tk::frame $top.f.color$col$row \
					-highlightthickness 1 \
					-highlightcolor black \
					-highlightbackground $bg \
					-background $bg \
					-borderwidth 0 \
					-width 22 \
					-height 22]
		set b [tk::frame $f.b \
					-relief solid \
					-borderwidth 1 \
					-width 18 \
					-height 18 \
					-background [expr {[llength $color] ? $color : $bg}]]
		bind $b <ButtonPress-1> [namespace code [list set selection $color]]
		bind $f <ButtonPress-1> [namespace code [list set selection $color]]
		bind $f <Return> [namespace code [list set selection $color]]
		bind $f <space> [namespace code [list set selection $color]]
		bind $f <Escape> [namespace code [list set selection close]]
		bind $f <Enter> { focus %W }
		grid $f -column $col -row $row
		pack $b -padx 1 -pady 1
		lappend buttonRow $f

		if {[llength $color]} {
			if {$count < $nb} {
				set tip BaseColor
			} elseif {$count < $nb + $nu} {
				set tip UserColor
			} elseif {$count < $nb + $nu + $nd} {
				set tip UsedColor
			} elseif {$count < $nb + $nu + $nd + $nr} {
				set tip RecentColor
			} else {
				set tip Texture
			}
			Tooltip $f "[Tr $tip]: [::dialog::choosecolor::extendColorName $actual]"
		}

		incr count
		if {[incr col] == 6} {
			set col 0
			incr row 2
			lappend buttonList $buttonRow
			set buttonRow {}
		}
	}

	if {$col != 0} { incr row 2 }
	set col 0
	set buttonRow {}

	if {$nt > 0} {
		grid [ttk::separator $top.f.sep2] -column 0 -row [expr {$row - 1}] -columnspan 6 -sticky we
		foreach texture $textureList {
			set f [tk::frame $top.f.color$col$row \
						-highlightthickness 1 \
						-highlightcolor black \
						-highlightbackground $bg \
						-background $bg \
						-borderwidth 0 \
						-width 22 \
						-height 22]
			set b [tk::canvas $f.b -relief solid -borderwidth 1 -width 16 -height 16]
			lassign $texture texture rotation tooltip
			set result [list $texture $rotation]
			if {[llength $texture]} { $b create image 1 1 -image $texture -anchor nw }
			bind $b <ButtonPress-1> [namespace code [list set selection $result]]
			bind $f <ButtonPress-1> [namespace code [list set selection $result]]
			bind $f <Return> [namespace code [list set selection $result]]
			bind $f <space> [namespace code [list set selection $result]]
			bind $f <Escape> [namespace code [list set selection close]]
			bind $f <Enter> { focus %W }
			grid $f -column $col -row $row
			pack $b -padx 1 -pady 1
			lappend buttonRow $f
			if {[llength $tooltip]} { Tooltip $f "[Tr Texture]: $tooltip" }
			incr count
			if {[incr col] == 6} {
				set col 0
				incr row 2
				lappend buttonList $buttonRow
			}
		}
	}

	if {$col != 0} { incr row 2 }
	set lastrow [expr {$row - 1}]

	foreach row $buttonList {
		for {set i 0} {$i < [llength $row]} {incr i} {
			set k [expr {$i + 1}]
			bind [lindex $row $i] <Right> [list focus [lindex $row $k]]
			bind [lindex $row $k] <Left>  [list focus [lindex $row $i]]
		}
	}
	for {set i 0} {$i < [llength $buttonList] - 1} {incr i} {
		set row0 [lindex $buttonList $i]
		set row1 [lindex $buttonList [expr {$i + 1}]]
		bind [lindex $row0 end] <Right> [list focus [lindex $row1 0]]
		foreach b0 $row0 b1 $row1 {
			if {[llength $b0] && [llength $b1]} { bind $b0 <Down> [list focus $b1] }
		}
	}
	for {set i 1} {$i < [llength $buttonList]} {incr i} {
		set row0 [lindex $buttonList [expr {$i - 1}]]
		set row1 [lindex $buttonList $i]
		bind [lindex $row1 0] <Left> [list focus [lindex $row0 end]]
		foreach b0 $row0 b1 $row1 {
			if {[llength $b0] && [llength $b1]} { bind $b1 <Up> [list focus $b0] }
		}
	}

	set sum 0
	foreach v {nb nu nd nr nt} {
		set sum [expr {$sum + [set $v]}]
		set row [expr {2*(($sum + 5)/6) + 2}]
		if {0 <= $row && $row < $lastrow} { grid rowconfigure $top.f $row -minsize 8 }
	}
	grid columnconfigure $top.f 6 -minsize 1

	Tooltip on $top*
	wm transient $top [winfo toplevel [winfo parent $top]]
	catch { wm attributes $top -type popup_menu }
	util::place $top -parent $parent -position below -type popup
	wm deiconify $top
	raise $top
	focus $top
	if {[tk windowingsystem] == "x11"} {
		catch { tkwait visibility $top }
		update idletasks
		if {![winfo exists $top]} { return }
	}
	if {$useGrab} { ttk::globalGrab $top.f }
	catch { focus -force $top.f.close }
	vwait [namespace current]::selection
	if {$useGrab} { ttk::releaseGrab $top.f }
	destroy $top
	Tooltip on
	update idletasks

	switch $selection {
		close		{ return "" }
		palette	{
			if {$disableParent} { $parent configure -state disabled }
			set selection [::dialog::chooseColor {*}$dlgArgs]
			if {$disableParent} { $parent configure -state normal }
		}
	}

	return $selection
}


proc ClearSelection {menu {x {}} {y {}}} {
	if {[llength $x]} {
		set w [winfo containing $x $y]
	} else {
		set w [focus]
	}

	if {![string match $menu* $w]} {
		set [namespace current]::selection {}
	}
}


proc ClearTooltips {menu w} {
	if {$menu eq $w} {
		::dialog::choosecolor::tooltip clear $w.*
		::dialog::choosecolor::tooltip hide
	}
}


proc Tr {tok} { return [::dialog::choosecolor::mc [namespace current]::mc::$tok] }
proc Tooltip {args} { ::dialog::choosecolor::tooltip {*}$args }

namespace eval icon {
namespace eval 16x16 {

set eraser [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACVUlEQVR4nJWS
	T0gUYRjGn++bmd3ZXdMChYiii7SxIKnfrMUijrsqeYgJqVlTCjpJRFGHunQZBrondOnYqT+a0MGD
	HRb7VMrMMAqqwx4qrIgO/qfcnZ23g44aLlYPfPDxvvweeN/nBf4qh5f//4ucDYCvv621nWWapgoA
	9c1WwshkPxmZ7Me6lBXf2gucy8JSSs9IW/FQpCJHwCwRvkaiFc/rUlZcSunZtq0AANsJZkr0BQjF
	l7kHNYmEHYrtU8YBdsgr/EzNjD1+7zgOZ+XgurQVD/PoM5D/nYADjHB3enTgcm1TZ+XuXVU5zvj+
	QgEtr8fu5/k2OGXFdTU2yYD8/OfFBt/HeTWsXzLS2dv5qZHF6dzDJgARhZduAiA12Kx03TU4Gpsk
	nz7Q/HJbPj9SQB5DwuyyQ9HKwcZ0doUx/GCMV4L7j9bZtViMtB1PdvTMJdu6J4U4EQ16QvRpANDQ
	0mUl23vo2PFz1Nh6+uJ6zhwAmBB9mmi1Z41M9/hB09QBsCDvIDIjY1852tFLwjx1YWt9M0YGAgDt
	S4QAQAx/U4To06SUntFq3wjpFf3FYvHqKzl0RwihSSm97SO09ywk285M1NZ2hgPfxrR9ramjlxoy
	9tlyN8MCE9d1/fpmK6GFY1M++W+IvH4iboR1/Xph9ddTDtwi8vcwrqyuFtQnbyfuzQFgG3cQxHjE
	PFmvqfow+dhLVGKMYQHEOBiqQChxhfueT+0zowNjtm0rf16i43C4ri+E0JSawxF1cYlWNKYAQKxI
	JVRXY35hid7JweVy42ya/Id+Axkn8pjo1WEcAAAAAElFTkSuQmCC
}]

set palette [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACtklEQVR4nIWT
	T2gdVRTGf+feO8lLiJKKUYLgwo1Ra9v0JeK/OHlY/6BtJW3HtBtBsDu3QgVlrAvFnRvd1LW0TpKC
	SgOiCS9EDE0mCdI+XKkLEbFQbV/NpDNz57h4RlpL6wcHDpzD4Xzf+Q5cDyGODTfHDXX5T64AI08f
	Hkb1gFbVDgQrcF4tX6RfJ4sAxLHh+PHq2gEC6IOPPntHT2//CeuCA74oLqjqOsKGqIzYwN1T+WpJ
	s/zV9LuZH7aGCHRW2hmu3x643kWBwbKqjq7Nn5oJw6gvs2b47NjQtyPN1hjWfiwi95ZV/sTa3PT3
	cRwbiaLIJkni6+OHThvnGly6PLS8fOY3iM3u8Var1tt3/2bW/mB1fupYh97kklY6kN2pD7SSpBSA
	Rxov75Sga91vZi+sLEzPjj5zeKIs81WDne7u6avnG+131MhsJViTlz/bWs+vRZ4fWWtOnXQAXnWS
	Ir+YLkzP1sej94Og51hV+tSWRPnm1aHK6BUjdikQI17Y4ctiUYy+BJw0dKR/CPT8P2JaVEGp+Y0f
	f1mZ+3TWqoqIEQAJ/F+q+ocg2wD+vamCBzQb4K0iz/aVhufSNC0AludnFnKfb7/q8+2q2h8E3ftU
	+RzAAYjIOeAoQCtJCuBLgDAMXdvc/YaBRoVeEuh3rrbHl+WZzd/lE8AYAE/xmQuCgd3hwb2APr5/
	/23Esbli7nrTGvOeopVAvzFy2Rf5Kytzp/a2WkkOKFEUWYD6eDQzuufIn/WxicEtWvXGoYV6Y/Ls
	LayNdCKWjpFqiyJm0Ffla6tzyenhp6LHXHfXN1VRvH3fgH7YbrddlmW+2Wz6LdtfZ+WHn3xxW1dX
	3wnn3MGyKC6Apta6570vPkrnp14Pw9A1m83yf59pNIx2VU4mUHYZ4Sdr9d2lr5KL1/bcnNKt3/kG
	/A2YszgKGcdQ1QAAAABJRU5ErkJggg==
}]

set crossHand [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACr0lEQVR4nG2T
	z2tdVRDHP3POvffFZ/1VSRQ3YikIkVTxProQ9bXGSgjdWBxdFCluFFwprvwBj4erRhcu3LkSSlEP
	LUQRgtWkb1ENmLQoNBT/gIJEFzZt09x7zxkXeX0azXdzDsyc73dmznzh/xDoOYDOU/rowSOvalke
	bQOoqt8leXeUz+sUDeeyongg1tV8lbWO/3ru1A1V9WFy0uj3038JZPjwbms4nWX5bIz1VUl84op8
	zlLaiKn68OLS2Y/+LeRuX1TVAUZtLzgnsynW84ZFc3IrNs31lOxb5/K5zvQrX5bP6UEAej03Irh8
	Ga+qXhx7Ukq/N8Y3GIWJObCNRPwOsxrjGTPOzMzMtOj37TaBrK2FKoQQMbkJkpO4ExETs2Qggt2f
	zP5MMb2H8OB6c9cYYNmwd+tMH9snrng8NfERzGrnJGJEnBiJ6GAzQUSsLSbRZ4UBZACd6WP7LPmf
	BCZclhOb6jegDewFa4nIfWYyhrAX2/l7GWAWZSoriomtun7Cp3gSZFpMfkTinDQsmuMeXFwi+ZNO
	ZCOZZdm1jVEFssfcDzdi/YfHXl9dmpztHF47unL+qwvAhaHQpeF58clDLx0XkVEFTlXdYBCuR4tv
	Z8XYm+Wza4+tLIWvu91uNtw8UVVflmXe7XYzEUk79iCEEFXVX1o8c6qpb/2C5zOA9fUJFyYnDSCE
	kMbHx91gMGhI8WHMbub5X5ujIY6Q0ht5q71cHtITq+fD5/T/CS0sLGzt3z/Tkix/y2KaHwwGjar6
	US+q6kMIsTysH+fFHe/U1ea7eE43dXWt3ipce4wp8f5TkIe8NQeWF8NVej3Z4QVVddskL38gTt63
	lFoYFYB438JYtli9tjo4ewUzQcR2c6MAduDIixNF454G7kXyShxXfv7+i5XtlJ6DbTf+DW4WOsAH
	dGnXAAAAAElFTkSuQmCC
}]

} ;# namespace 16x16
} ;# namespace icon
} ;# namespace colormenu

# vi:set ts=3 sw=3:
