# ======================================================================
# Author : $Author$
# Version: $Revision: 926 $
# Date   : $Date: 2013-09-04 11:57:51 -0400 (Wed, 04 Sep 2013) $
# Url    : $URL$
# ======================================================================

# ======================================================================
# Copyright: (C) 2011-2013 Gregor Cramer
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB2ElEQVR4nJ2R
	PWtUURCGnznnfqxmVzcELEStrFNkuzSbFEIqK29po43gHxAUBAPiP/A/eNFGkViZ2wY2djZqozZu
	ErIxS7L345yx2A8T3RV1msNh5n2YeV8A4KHhn2uokfF3cfHaXO3iBRt8P9Q/yapzDXE7B1Wn8+po
	Ami1kxs2DJ9WrmyKqkFEpqpVVUV8YG2vrIo77zZfPA8AVLjlvNsD7oqRSBU/TS9GjCqFU30k2NvA
	EAAo3n/Y3kyf/c31rZXkJmAAxgAU4iRJLGABN0NrAfdphxgoTwEENE1TlyQJaZpOBYx7rZVEx04H
	v8xIt9sVTqRzsqb1AgARUfAKaJZl1Yz1mfREVTD6cwPVEBGzvHy9EYZieyNBfFz3APmZvgFoAmWp
	LkcsqjIBqGErDGsPctjNIQqgD+DmivpwKOoD9KFOTBFEcVTlg/UJYLDAutnLtwSaiNn16h+LqniV
	ewBG9ImKqCD3BV1wZdE77sqbCeB9mhbAS4Cl1aQlYkTxyshqFVERI6r+W+dt+vqU6+O33W7b/ehy
	HJSDbWPtJfXegTRGiEMxxnrnvlZhbWm++JJnWeYA/S2uq2tr8fnqSg32iY/yoYlnYwPzHASfBx83
	NvJZKf1X/QA26Mz40bSUUQAAAABJRU5ErkJggg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABRklEQVR4nK1S
	vUrDUBg99zY1jYgK+gTi1C1NpQF/rqZFM1rls6ABd32IS1/CJ3DRgF27yS0OGaTSwU4+goJbsU1z
	HUo1gqUqnu3Ad853Pr4D/DOYEMIYEyLKAJJPFaXJSDQFUo5cnUploeDRue/7JgA43tF+wTvcTM+k
	1/N6vZ64LllML7WQ4KzZbL7ZggIjO9MA+DIAdLvdL4kYAAhxmlvzau1iudYBAGeHjku7gbYFBelt
	YwEDwFyXzIGFO8Z5rF+fNvT8SjWTMa6G/fig3QobQghDKRV/xJt6+ARwABqAjqKwN5fMrjONLFtc
	vW/fhtfJMD7J5syboqBAKRVDfv8SDgCuS1axXOs42/QIALagoLQX6IJHVeDzPWmHRErJoyjsafay
	pTkufN83H1R4GQ/6VSB5BoB8Pq8nxf99AdLiv1TuR3gHkXdrT7fWuA4AAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABS0lEQVR4nK2S
	wUoCURSG/3udccoWLmrRA7Ry59wBhaibV6lZuMjqZsi0b9E7DL5FD9AmpNy0cBVNEEgkFoQPEbWz
	TBrmtnDGphAR6lvdC+c/5z8/B/gfXCqlTEQ/zrkGgMwsj4tDJotd16UAYIrdNVPICgDYtm1khTxm
	pVI6XhNBAaDX64Ud6ZKuGReWkE6r1RqSQB0RtXjDWDlVr9eDqH7iVFaQtdyWoywhHQCwRLVrFasP
	+bycj9v+4Z1zrnme5zO+v031RFP5/sGCej5/05ZvVRDo+gCr7XbjY2x1Gv1+nwCA+hXUWOi6LvU8
	z2cFWdPmkk0/8A/vrxtnJL1yB8BIjqYNwh6jPlH8ppCV3KajsuF+5sbek1WsPjJWTsXDHD8ymUzo
	JHj59Ic73avGqW3bhqLkRJHX9U7n8j0ML5i618wH8M0fT24WvgArMnFwr/wHqwAAAABJRU5ErkJg
	gg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABvUlEQVR4nJ2R
	sWsUURDGv5l52Q3kjBAQDKSQQFJEEMLiFSlyAS2CZcJiSqs0Imjpn6Bd7Oy0E6IWQjqFXIqwFkcq
	U0RI0imIwnGLy+29N2Oxlz1Pu3zweDC8b34z3wMuKQKAZnN9Wq/MNDV4AQAzo7FHRAYALC5ERf75
	8PBDzwFAmGq8Zug9kP0imCP6t7/BQJ6gM/043gOw4SoC3Rp4//AqfrwCbrg8j8PftkajL8C57+q1
	B0z0FABcNQpKERu0P7W9oR0IsHEePAGW3NkcQKkEAK6IIFUIAFprtWS4e30uaqoQsyoXV3clpjRN
	GQCnaTpGvKh9/YlhTKNRjTTku7vvA4CA/xUAYHltIycSq41miJndyu1W2jVRCoqSSWIAUAt9YUQU
	2JRpxdTiERH6kiV+pDZIoTQtIlOq+h0ARNx1C+G3MbosTr2WL+pwOvvvnknvdKGzujRnZE8shJOo
	wHxUYN5CODGyx53VpTnpnS4c7b99XhuTZHsiy7IiOTjeEol2iGWxnLSzctLOiGVRJNpJDo7vZ1lW
	JMn2BIZx1/fy3a3ZiHHTe/Uaql1YqO8cu1Lx5ejjm2+jr72k/gBVhMHCvh0BRgAAAABJRU5ErkJg
	gg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAAo0lEQVR4nGNg
	oBAwUkeBiocHO0yACVk2NDSUmYGB4b+xU6gr/0/ePpgYsiJGLS2t//r2/gL//zG0MDMwzmJgYGBc
	raX1H67C3t6ehYGBgcHYMXSJsVNYCpLJKNYwGNuHpBg7hC5F1gQB9fVMDAwMjGaOgfpGDqEn9e39
	BeqhYnCHh167xsjAwPD/LwNzKiMjU+3Fgxs/XIOKYfgbyctUCkSyAQB0uyjLV1HVEwAAAABJRU5E
	rkJggg==
}]

} ;# namespace 9x14
} ;# namespace icon
} ;# namespace choosedir

# vi:set ts=3 sw=3:
