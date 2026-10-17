# ======================================================================
# Author : $Author$
# Version: $Revision: 926 $
# Date   : $Date: 2013-09-04 11:57:51 -0400 (Wed, 04 Sep 2013) $
# Url    : $URL$
# ======================================================================

# ======================================================================
# Copyright: (C) 2011-2013 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

package require Tk 8.4
if {[catch { package require tkpng }]} { package require Img }
package require tooltip
package provide choosedir 1.0


proc choosedir {w args} {
	return [::choosedir::Build $w {*}$args]
}


namespace eval choosedir {
namespace eval mc {

set ShowPredecessor	"Show Predecessor"
set ShowTail			"Show Tail"
set Folder				"Folder"

}

namespace import ::tcl::mathfunc::max

proc tooltip {args} {}
proc mc {tok} { return [tk::msgcat::mc [set $tok]] }

if {![catch {package require tooltip}]} {
	proc tooltip {args} { ::tooltip::tooltip {*}$args }
}

proc Tr {tok} { return [mc [namespace current]::mc::$tok] }


proc Build {w args} {
	namespace eval [namespace current]::${w} {}
	variable ${w}::Vars

	array set opts {
		-width				300
		-borderwidth		1
		-padx					2
		-pady					5
		-relief				raised
		-font					TkTextFont
		-activebackground	{}
		-initialdir			{}
		-showlabel			0
		-showhidden			0
	}
	array set opts $args

	if {[llength $opts(-activebackground)] == 0} {
		set opts(-activebackground) [::colors::lookup theme,activebackground]
		if {[llength $opts(-activebackground)] == 0} {
			tk::button $w
			set opts(-activebackground) [$w cget -activebackground]
			destroy $w
		}
	}

	set Vars(dir) ""
	set Vars(dir:components) { "" }
	set Vars(dir:size) 0
	set Vars(prefix:components) { "" }
	set Vars(prefix:size) 0
	set Vars(size) 0
	set Vars(start) 1
	set Vars(font) $opts(-font)
	set Vars(padx) $opts(-padx)
	set Vars(pady) $opts(-pady)
	set Vars(initialdir) $opts(-initialdir)
	set Vars(user) 0
	set Vars(icon) {}
	set Vars(startmenu) {}
	set Vars(showhidden) $opts(-showhidden)
	set Vars(prefix) ""
	set Vars(basename) ""
	set Vars(tooltip) ""

	set Vars(linespace) [font metrics $opts(-font) -linespace]
	set Vars(activebackground) $opts(-activebackground)
	set Vars(showlabel) $opts(-showlabel)

	array unset opts -font
	array unset opts -pad*
	array unset opts -activebackground
	array unset opts -initialdir
	array unset opts -showlabel
	array unset opts -showhidden

	set opts(-height) [expr {$Vars(linespace) + 2*$Vars(pady)}]
	set bg [::colors::lookup theme,background]

	tk::frame $w -background $bg -takefocus 0 {*}[array get opts]

	if {$Vars(showlabel)} {
		tk::button $w.label      \
			-text "[Tr Folder]:"  \
			-pady 2               \
			-padx 2               \
			-relief flat          \
			-overrelief flat      \
			-background $bg       \
			-activebackground $bg \
			;
		bind $w.label <ButtonPress-1> { break }
	}

	tk::button $w.prev                           \
		-image $icon::14x14::prevComponent        \
		-relief flat                              \
		-overrelief raised                        \
		-background $bg                           \
		-activebackground $Vars(activebackground) \
		-takefocus 0                              \
		;
	bind $w.prev <Enter> [namespace code [list ShowTooltip $w]]
	bind $w.prev <Leave> { ::tooltip::hide yes }
	tk::button $w.next                           \
		-image $icon::14x14::nextComponent        \
		-relief flat                              \
		-overrelief raised                        \
		-background $bg                           \
		-activebackground $Vars(activebackground) \
		-takefocus 0                              \
		;
	bind $w.prev <Leave> {+ %W configure -relief flat }
	tooltip $w.next [Tr ShowTail]
	if {$Vars(showlabel)} {
		grid $w.label -column 1 -row 1 -sticky ns
	}
	grid $w.prev -column 3 -row 1 -sticky ns
	grid $w.next -column 1000 -row 1 -sticky ns
	grid rowconfigure $w {0 2} -minsize $Vars(pady)
	grid columnconfigure $w {2 1001} -minsize $Vars(padx)

	bind $w <Destroy> [list catch [list namespace delete [namespace current]::${w}]]
	bind $w <Configure> [namespace code { Configure %W %w }]
	catch { rename ::$w $w.__choosedir__ }
	proc ::$w {command args} "[namespace current]::WidgetProc $w \$command {*}\$args"

	if {[string length $Vars(initialdir)] == 0} { set Vars(initialdir) [pwd] }
	$w set $Vars(initialdir) "" "" ""

	return $w
}


proc WidgetProc {w command args} {
	switch -- $command {
		set {
			if {[llength $args] != 4} {
				error "wrong # args: should be \"[namespace current] $command <dir> <basename> <icon> <prefix>\""
			}
			variable ${w}::Vars

			lassign $args folder basename icon prefix
			if {$folder ne $Vars(dir) || $prefix ne $Vars(prefix)} {
				set separator [file separator $folder]
				set Vars(dir) $folder
				set Vars(basename) $basename
				set Vars(prefix) $prefix
				set Vars(prefix:components) [file split $prefix]
				set Vars(dir:components) [file split $folder]
				foreach attr {dir prefix} {
					if {[llength $Vars($attr:components)] <= 1} {
						set Vars($attr:components) {}
					} else {
						set Vars($attr:components) [lreplace $Vars($attr:components) 0 0]
					}
					set Vars($attr:size) [llength $Vars($attr:components)]
				}
				set Vars(start) [expr {$Vars(dir:size) - $Vars(prefix:size) + 1}]
				set Vars(user) 0
				set Vars(icon) $icon
				Layout $w
			}

			return $w
		}

		setfolder {
			if {[llength $args] != 2 && [llength $args] != 3} {
				error "wrong # args: should be \"[namespace current] $command <folder> <basename> ?<icon>?\""
			}
			variable ${w}::Vars

			set icon {}
			lassign $args folder basename icon
			if {$folder ne $Vars(dir)} {
				set Vars(dir) $folder
				set Vars(dir:components) { "" }
				set Vars(dir:size) 0
				set Vars(prefix) ""
				set Vars(prefix:components) { "" }
				set Vars(prefix:size) 0
				set Vars(basename) $basename
				set Vars(start) 1
				set Vars(user) 1
				set Vars(icon) $icon
				Layout $w
			}

			return $w
		}

		setstartmenu {
			if {[llength $args] != 1} {
				error "wrong # args: should be \"[namespace current] $command <start-menu>\""
			}
			variable ${w}::Vars
			set Vars(startmenu) [lindex $args 0]
			return $w
		}

		showhidden {
			if {[llength $args] != 1} {
				error "wrong # args: should be \"[namespace current] $command <flag>\""
			}
			variable ${w}::Vars
			set Vars(showhidden) [lindex $args 0]
			return $w
		}

		tooltip {
			if {[llength $args] != 1} {
				error "wrong # args: should be \"[namespace current] $command <string>\""
			}
			variable ${w}::Vars
			set Vars(tooltip) [lindex $args 0]
			return
		}

		dir {
			variable ${w}::Vars
			return $Vars(dir)
		}

		configure {
			if {[llength $args] % 2 == 1} {
				error "value for \"[lindex $args end]\" missing"
			}
			array set opts $args
			foreach option {padx pady} {
				if {[info exists opts(-$option)]} {
					set Vars($option) $opts(-$option)
					array unset opts -$option
				}
			}
			if {[info exists opts(-font)]} {
				set value $opts(-font)
				for {set i 0} {$i < $Vars(size)} {incr i} {
					$w.text-$i configure -font $value
				}
			}
			if {[info exists opts(-activebackground)]} {
				set value $opts(-activebackground)
				for {set i 0} {$i < $Vars(size)} {incr i} {
					$w.text-$i configure -activebackground $value
					$w.image-$i configure -activebackground $value
				}
			}
			set args [array get opts]
			if {[llength $args]} {
				$w.__choosedir__ {*}$args
			}
			Layout $w
			return $w
		}
	}

	return [$w.__choosedir__ {*}$args]
}


proc ShowTooltip {w} {
	variable ${w}::Vars

	if {[string length $Vars(tooltip)]} {
		::tooltip::show $w $Vars(tooltip)
	}
}


proc Layout {w} {
	variable ${w}::Vars

	set bg [::colors::lookup theme,background]
	set n [expr {$Vars(dir:size) - $Vars(prefix:size) + 1}]

	for {set i $Vars(size)} {$i < $n} {incr i} {
		tk::button $w.text-$i                                       \
			-font $Vars(font)                                        \
			-padx 2                                                  \
			-pady 2                                                  \
			-relief flat                                             \
			-overrelief raised                                       \
			-background $bg                                          \
			-activebackground $Vars(activebackground)                \
			-command [namespace code [list Invoke $w $w.text-$i $i]] \
			-takefocus 0                                             \
			;
		tk::button $w.image-$i                                          \
			-image $icon::9x14::Delimiter                                \
			-relief flat                                                 \
			-pady 2                                                      \
			-overrelief raised                                           \
			-background $bg                                              \
			-activebackground $Vars(activebackground)                    \
			-command [namespace code [list PopupDirs $w $w.image-$i $i]] \
			-takefocus 0                                                 \
			;
		# we have to help Tk a little bit
		bind $w.text-$i <Leave> { %W configure -relief flat }
		bind $w.image-$i <Leave> { %W configure -relief flat }
		set col [expr {4*($i + 2)}]
		grid $w.text-$i -column [incr col] -row 1
		grid $w.image-$i -column [incr col] -row 1 -sticky ns
	}

	$w.text-0 configure -text $Vars(basename)

	for {set i $Vars(prefix:size)} {$i < $Vars(dir:size)} {incr i} {
		set k [expr {$i - $Vars(prefix:size) + 1}]
		$w.text-$k configure -text [lindex $Vars(dir:components) $i]
	}

	set Vars(size) [max $n $Vars(size)]
	set removeLast 0

	if {[llength [glob -nocomplain -tails -dir $Vars(dir) -types d *]] == 0} {
		set removeLast 1
	}

	update idletasks

	if {[winfo exists $w.image-0]} {
		set iwd [winfo width $w.image-0]
	} else {
		set iwd 0
	}
	set bwd [$w.__choosedir__ cget -borderwidth]
	set twd [expr {[winfo width $w] - 2*$bwd - [winfo width $w.prev] - 3*$Vars(padx)}]
	if {!$removeLast} { set twd [expr {$twd - $iwd}] }
	if {$Vars(showlabel)} { set twd [expr {$twd - [winfo width $w.label] - $Vars(padx)}] }

	set i 0
	set x 0
	set width(0) 0

	while {$i < $n} {
		set wd [winfo width $w.text-$i]
		set x [expr {$x + $wd + $iwd}]
		set width([incr i]) $x
	}

	set e $n
	set f $e
	while {$f > 0 && $width($e) - $width([expr {$f - 1}]) <= $twd} { incr f -1 }

	while {$f > $Vars(start)} {
		incr f -1
		while {$e > $f && $width($e) - $width($f) > $twd} { incr e -1 }
	}

	if {$e < $n} {
		set twd [expr {$twd - [winfo width $w.next]}]
		if {$e > 0 && $width($e) - $width($f) > $twd} { incr e -1 }
	}

	if {$f > 0} {
		if {$width($e) - $width($f) > $twd} { incr f 1 }
		bind $w.next <ButtonRelease-1> [namespace code [list SetRange $w $w.next $n]]
	}
	if {$f == 0} {
		set icon $Vars(icon)
		if {[llength $icon] == 0} { set icon $icon::16x16::fileSystem }
		$w.prev configure -command [namespace code [list Invoke $w $w.prev -1]]
		tooltip $w.prev ""
	} else {
		set icon $icon::14x14::prevComponent
		$w.prev configure -command [namespace code [list SetRange $w $w.prev [expr {$f - 1}]]]
		tooltip $w.prev [Tr ShowPredecessor]
	}
	$w.prev configure -image $icon
	if {$f >= $e} { set f [expr {$e - 1}] }

	for {set i 0} {$i < $Vars(size)} {incr i} {
		if {$i >= $f && $i < $e} {
			grid $w.text-$i
			grid $w.image-$i
		} else {
			grid remove $w.text-$i
			grid remove $w.image-$i
		}
	}

	if {$Vars(user)} {
		if {[llength $Vars(icon)] == 0} {
			grid remove $w.prev
		}
		grid remove $w.image-0
	} else {
		grid $w.prev
		if {$removeLast} { grid remove $w.image-[expr {$n - 1}] }
		if {$e < $n} { grid $w.next } else { grid remove $w.next }
	}
}


proc ButtonEnter {w} {
	# poor Tk: we have to help Tk a bit
	set ptrw [winfo containing {*}[winfo pointerxy .]]
	if {$ptrw eq $w} {
		$w configure -relief [$w cget -overrelief]
		::tk::ButtonEnter $w
	}
}


proc Invoke {w btn i} {
	variable ${w}::Vars

	if {$i == -1} {
		event generate $w <<GetStartMenu>>
		set m $w.popup
		if {[winfo exists $m]} { destroy $m }
		menu $m -tearoff false
		foreach {icon name folder} $Vars(startmenu) {
			if {[string length $name] == 0} {
				$m add separator
			} else {
				$m add command \
					-label " $name" \
					-image $icon \
					-compound left \
					-command [namespace code [list ChangeFolder $w $folder]] \
					;
			}
		}
		bind $m <<MenuUnpost>> [list $btn configure -state normal -relief flat]
		bind $m <<MenuUnpost>> +[namespace code [list ButtonEnter $btn]]
		tk_popup $m [winfo rootx $btn] [expr {[winfo rooty $btn] + [winfo height $btn]}]
	} elseif {$Vars(user)} {
		event generate $w <<SetFolder>> -data $Vars(dir)
	} elseif {$i == 0} {
		event generate $w <<SetDirectory>> -data [file join "/" {*}$Vars(prefix:components)]
	} else {
		set components [lrange $Vars(dir:components) 0 [expr {$i + $Vars(prefix:size) - 1}]]
		event generate $w <<SetDirectory>> -data [file join "/" {*}$components]
	}

	after idle [namespace code [list ButtonEnter $btn]]
}


proc PopupDirs {w btn i} {
	variable ${w}::Vars

	if {$Vars(user)} {
		set subdirs {}
	} else {
		set i [expr {$i + $Vars(prefix:size) - 1}]
		set rootdir [file join "/" {*}[lrange $Vars(dir:components) 0 $i]]
		set filter *
		if {$::tcl_platform(platform) eq "unix" && $Vars(showhidden)} { lappend filter .* }
		set subdirs [glob -nocomplain -tails -dir $rootdir -types d {*}$filter]
		foreach dir {. ..} {
			set i [lsearch -exact $subdirs $dir]
			if {$i >= 0} { set subdirs [lreplace $subdirs $i $i] }
		}
		set subdirs [lsort -dictionary -unique $subdirs]
	}

	set m $w.popup
	if {[winfo exists $m]} { destroy $m }
	menu $m -tearoff false

	if {[llength $subdirs]} {
		set linespace [font metrics [$m cget -font] -linespace]
		set maxh [winfo screenheight $m]
		set columns [expr {(2*[llength $subdirs]*$linespace + $maxh - 1)/$maxh}]
		if {$columns > 4} { set columns [expr {([llength $subdirs]*$linespace + $maxh - 1)/$maxh}] }
		set size [expr {[llength $subdirs]/$columns}]
		set n 0
		foreach dir $subdirs {
			set opts {}
			if {$n == $size} {
				lappend opts -columnbreak 1
				set n 0
			}
			if {$Vars(user)} {
				set rootdir [file dirname $dir]
				set dir [lindex [file split $dir] end]
			}
			$m add command {*}$opts -label $dir -command [namespace code [list ChangeDir $w $rootdir $dir]]
			incr n
		}
	}

	bind $m <<MenuUnpost>> [namespace code [list ButtonEnter $btn]]
	tk_popup $m [winfo rootx $btn] [expr {[winfo rooty $btn] + [winfo height $btn]}]
}


proc ChangeFolder {w folder} {
	event generate $w <<SetFolder>> -data $folder
}


proc ChangeDir {w rootdir subdir} {
	event generate $w <<SetDirectory>> -data [file join $rootdir $subdir]
}


proc SetRange {w btn index} {
	variable ${w}::Vars

	set Vars(start) $index
	Layout $w
	after idle [namespace code [list ButtonEnter $btn]]
}


proc Configure {w width} {
	variable ${w}::Vars

	if {$width <= 1} { return }
	set Vars(start) [expr {[llength $Vars(dir:components)] - $Vars(prefix:size)}]
	Layout $w
}


namespace eval icon {
namespace eval 16x16 {

set fileSystem [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACj0lEQVR4nIVS
	PU9UURA9c9/dvW93kW80QEXA2NrZECR+FBJMQBogIBrBSqyEQmIumxhRY2ViKTYaDIlIgtFCazt/
	gRKUgMB+ILLw3r6vOxYIQjBhyjNzTuacGQIAZq77vbV1Npv5lRIWGEeUMUbUVFZtlpWVfCZmrpt8
	OfPw9cyHzqJXVHwkHQAByUTC7Ww//44KBae7s3/4xUomZ5eWJANLyhh4Z+hQ/cWDMAxdpyhtOx7K
	1UympOh7VmlJMnj25N796qrKec/zLAvi0C4RDCmlolx+vXF49MGY47pxKSzBYMCSMnaiqvprff3x
	qaMcLC6v9lhSxJgBub/hOG5May0ACADmP1wBwLiOE9sFDghYluB0Om201kin04cEdvG+get79sQB
	j5EhrbVobW0VzCy01kJrLZhZMLMAILTWwkTmX8Tz3xdvNF/q85vb+nl5OdNzlP/dDFrar5rTLV0s
	TWQIBERhGKxlcyeXln4OMFmNQoDdYnEBABK23QAA247zIx6Le5nselMUmoAIcSoUnO6O/luTq5l8
	4lgq6SsVj9u2DQDwPA8AoJQCAPi+jyAMOQyC0HG9mG0rf+cTX719PPXmfVfR96QxBoXCtkVEECQI
	AIwxTASAiFLJRCgsgYSt/CttF+YIAJi5dqNQOLO96Zy7fXdi8NvCoq3iMQ6CkABASgkisOMU6VRT
	g/v00djzZEp9qigt/SKZmYhoBcAsM2+lkolrkWEKgojKy8sAABsbmwCBKirKkEwop762Zo6IPu6l
	ysxiepotZraZ+U7vzdF879BIbi2bH1/L5sd7h0ZyvYMj2dVMboKZLzJzave0tE+EiIiZWXqedxmw
	oJScBQAvDDsQRVBKzRFRuP+kfwC9p08Vli3/9gAAAABJRU5ErkJggg==
}]

} ;# namespace 16x16

namespace eval 14x14 {

set prevComponent [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABX0lEQVR4nI1S
	PUhCYRS990OinykksCki3CrMwJbIoohsiEgcIgiJdEmUGoJCrIaQooKWIBocChteS4lvMaESCWoK
	CqSMoKmprR9K32nxwbOe6V0u93IPnHPuYdIpAExETERgZgAQRETMrOjda0Ha+j3rgkShGwF0Aagr
	zO0AzNpbgxbEzAoA04EUC8uJlMPvnVgHkPXOLm80GOtfAUwy8z0AYVDpqaDDIzm8tbPvzuW+UVtT
	3e8JLHkTF1fmQbstS0RVfzQBaIxKsYi1zwWL3Zk/PbtM++ZXn5utDrhnFp8AjAEQRR4AEMdyctM2
	MA5Lj/PtPH19Mhdce2zpHMaUL3gHYEQIUWSUKG1VGTOLqcb/o+rUo6qCTVEpHunodaGte1S5uc3E
	p/2hTJNlCJ5A6AFAqyrNQESkpoOZXwAs5JEnOZFyvH98Jve2V3bVdxDRVynaFQegpOZyLukuKwn5
	Dzu49Rznog9kAAAAAElFTkSuQmCC
}]

set nextComponent [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABbUlEQVR4nJ2S
	TyiDcRzGv993y8XNEC6Sl1Ij28ou5k+ZeMsB22FOyFyGlVgx4eDCgTjuMgkHO0islRykMLXLarKa
	RU5qLQ5OYo/L3vVumOU5/Q7P7/t7Ps/vy6QQAIGIiJlTAJiImIjAzKACxTkD+TejbKgD0JQ+FwMw
	AtAo08hSAxDS0erdK5s7ieRLCYCZYCgsbnn2XJLZFAAwx8zPspeISK0YUpRIvmpOz29Eu3NpbXJ8
	KB65uy+Pxh6HVawixWXOMANgAAKAgRGH+6FG3wvH7MrT2fn1pa7d+qHvtGL34GQbQNVPzCwIAgHo
	G51YuK01SJh2r8YvrkJHurbBt5YuGw79Z+syaxbwT93mbTQ76nxOVMunvtOKPd+xF0BlJqr8NACt
	3bkYq27uwdjUYjQcifobW/tTug4r9n1+L4AKJZ+y1fey0pJkd4cRno1lVzAUFrUNokEymwI2i/Tt
	O/69AHlqye7gL0PBS/4Fwaz1EIidNzoAAAAASUVORK5CYII=
}]

set fileSystem [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACSElEQVR4nH2Q
	zW9MYRjFf8973zu3lakiKWOa0vooirRGRCuCP0AiKRthJU0msbBiQ+jUmo0ImvjY+AhBIkJYsRAf
	m1YqilIVk46mRTWadubemfexaDXShbN6Fr+T85wjAKoaAPMB5f8SYFREClZV627cfnj4VVdPkxHj
	HCpmFu0Ag6hTZ5o3NXar6mn75m1f6/krNw9+Hx3DtxYxs21TUueIikW6et5tWb965Wc7NPwjPpHP
	6/o1Kz4cbNt7e2RkVKwBjEy97VSKDqqq5uu5izf29H/JrsoNjVTYIPBLqirz5saj7S0bL8Ri/qBn
	DM45AIwxlJwjDKPq67fu71JVCQK/ZJ1zAlByaoAgOnrMnE0mvXQ6XQLo7Oz00rlcCQimGZxzYv9p
	IUCRjg6XntoDgHQ6PXVnMsVpBgBrjFFB1HpeCMRVtQ4oB35OMwuASaDcel4oiBpj1ObD0AeV/oFs
	4siJU53l5UGN7/tzfv8ezwFUVMSTURRNTE4Wsv0D2QQg+TD0bWrdmo+1NdW/+ga+Jh4/eZ5Q5yiW
	SgRBUAVQKBSwnocYsxQR6pcvGU01ru0TVY1ns7ld3b19qcp4vPni1Tup3vefYgf2tX4DuHzt7uKG
	1SvCtv27u8bGx182NtR3La1J3pspq6pNBw4df/DsRXfSWkMsFgMgDEOiomNbS2rw0pmTO0XkNYBV
	VZPJZACGt27e8Ci5aOGOsjK/bGxsfAigsjKeyOej/LLa6qfAcHt7u8lkMswkTqfOAaqBYNaqBWBQ
	RCb+sn8AaYYA5uqNfhgAAAAASUVORK5CYII=
}]

} ;# namespace 14x14

namespace eval 9x14 {

set Delimiter [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAkAAAAOCAYAAAD9lDaoAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAAt0lEQVR4nGNg
	IBf8//+fkYGBgRFK41SA1wQmKG1+8tyl2v///yvgUiDe0DVtl09E1t////97olgBxSyHjp1pNnWO
	+D9rwaoF////58dmSoBLYMrnzOKm8////1dnYGBgqK+vZ4IQEAVqmcVN550Dk7/8//8/AFkzzCT+
	mQtXzzd1jvh/8Oiplv///7MwQJ2ArMjTJyLrb0PXtF3///8XxzAFKqBw8syl2v///5tjVUB0YBKM
	BmIAAFmxiU+3/d+fAAAAAElFTkSuQmCC
}]

} ;# namespace 9x14
} ;# namespace icon
} ;# namespace choosedir

# vi:set ts=3 sw=3:
