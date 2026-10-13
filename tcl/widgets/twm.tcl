# ======================================================================
# Author : $Author$
# Version: $Revision: 1529 $
# Date   : $Date: 2018-11-22 05:48:49 -0500 (Thu, 22 Nov 2018) $
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

::util::source tiled-window-manager

package require Tk 8.5
package require tktwm 1.0
package require Ttk

namespace eval twm {
namespace eval mc {

set Close			"Close"
set Undock			"Undock"
set Amalgamate		"Amalgamate"
set Separate		"Separate"

set Timeout			"Timeout after eight seconds without mouse motions,\
						the frame has been re-docked to old place."
set TimeoutDetail	"This safety handling is required to avoid frozen screens, as long as the\
						tiling window management is in an experimental stage."

} ;# namespace mc

# TEMPORARILY:
# After 8 seconds without any mouse motion we will dock the window,
# because it's too dangerous to keep the global grab. Change
# globalgrab:timeout to zero when this is not needed anymore.

array set Defaults {
	header:fix:foreground		white
	header:flex:background		#4f94cd
	header:flex:foreground		white
	header:active:background	#fffdfc
	header:font						TkHeadingFont
	header:fontsize				9
	header:button:background	#d7d7d7
	header:tab:background		#4f94cd
	header:tab:foreground		#333333
	header:borderwidth			1
	frame:borderwidth				1
	float:borderwidth				1
	flathandle:size				7
	flathandle:color:dark		#0e62a8
	flathandle:color:lite		#a6ceef
	flathandle:color:gray		#74aedf
	panedwindow:relief			flat
	panedwindow:background		""
	panedwindow:timeout			50
	sash:size						5
	cross:color:1					black
	cross:color:2					#24a249
	cross:active					yellow
	cross:size						24
	cross:showall					0
	highlight:color				#3778ed
	highlight:border				#0849c0
	highlight:opacity				0.3
	highlight:minsize				150
	highlight:timeout				100
	motion:busy						0
	motion:overrideredirect		1
	deiconify:timeout				50
	deiconify:force				0
	mtab:padding:selected		{4 2 4 0}
	mtab:padding:hidden			{4 0 4 2}
	mtab:padding:fixed			{4 1 4 1}
	repeat:delay					300
	repeat:interval				75
	globalgrab:timeout			8000
}
# flathandle:color:dark		#000000
# flathandle:color:lite		#ffffff
# flathandle:color:gray		#efefef
# highlight:opacity 0.4

array set Options [array get Defaults]

array set DirMap {
	m center
	t top    n top
	b bottom s bottom
	l left   w left
	r right  e right
}

set Frozen ""


proc tr {tok} { return [::tk::msgcat::mc [set $tok]] }
proc tooltip {args} {}
proc makeStateSpecificIcons {icon} { return $icon }

namespace export twm tr tooltip


if {![catch {package require tooltip}]} {
	proc tooltip {args} { ::tooltip::tooltip {*}$args }
}


proc twm {path args} {
	namespace eval [namespace current]::$path {}
	variable ${path}::Vars
	variable Options

	array set opts [list \
		-makepane {} \
		-buildpane {} \
		-workarea {} \
		-resizing {} \
		-adjustcmd {} \
		-fullscreencmd {} \
		-borderwidth 0 \
		-allowempty 0 \
		-disableclose 0 \
		-state normal \
		-panedwindowaligntimeout 50 \
		-frameborderwidth $Options(frame:borderwidth) \
		-headerborderwidth $Options(header:borderwidth) \
		-floatborderwidth $Options(float:borderwidth) \
		-panedwindowrelief $Options(panedwindow:relief) \
		-panedwindowbackground $Options(panedwindow:background) \
	]
	array set opts $args
	set Vars(cmd:makepane) $opts(-makepane)
	set Vars(cmd:buildpane) $opts(-buildpane)
	set Vars(cmd:workarea) $opts(-workarea)
	set Vars(cmd:adjustcmd) $opts(-adjustcmd)
	set Vars(cmd:fullscreencmd) $opts(-fullscreencmd)
	set Vars(cmd:resizing) $opts(-resizing)
	set Vars(allow:empty) $opts(-allowempty)
	set Vars(disable:close) $opts(-disableclose)
	set Vars(state) $opts(-state)
	set Vars(docking:recipient) ""
	set Vars(docking:position) ""
	set Vars(docking:current) ""
	set Vars(afterid:release) {}
	set Vars(cross:showall) $Options(cross:showall)
	set Vars(frame:borderwidth) $opts(-frameborderwidth)
	set Vars(header:borderwidth) $opts(-headerborderwidth)
	set Vars(float:borderwidth) $opts(-floatborderwidth)
	set Vars(panedwindow:relief) $opts(-panedwindowrelief)
	set Vars(panedwindow:background) $opts(-panedwindowbackground)
	set Vars(panedwindow:timeout) $opts(-panedwindowaligntimeout)

	catch { font delete ${path}::Vars(header:font) }
	set Vars(header:font) [font create ${path}::Vars(header:font) \
		-family [font configure $Options(header:font) -family] \
		-weight bold \
		-size $Options(header:fontsize) \
	]

	ttk::frame $path -class TwmToplevel -borderwidth $opts(-borderwidth) -takefocus 0
	bind $path <Destroy> [list [namespace current]::DestroyTWM %W]

	set h [tk::toplevel $path.__highlight__ -borderwidth 0]
	pack [tk::canvas $h.c -borderwidth 0]
	$h.c create image 0 0 -anchor nw -tag image
	wm withdraw $h

	rename ::$path $path.__twm_frame__
	proc ::$path {command args} "[namespace current]::WidgetProc $path \$command {*}\$args"

	SetupTheme $path
	bind $path <<ThemeChanged>> [namespace code [list SetupTheme $path]]
	bind $path <<ThemeChanged>> {+ break }

	return $path
}


proc nameOfOptionsArray {} {
	return [namespace current]::Options
}


proc resetFontSize {} {
	variable Options
	variable Defaults

	set Options(header:fontsize) $Defaults(header:fontsize)
}


proc frozen {} {
	return [set [namespace current]::Frozen]
}


proc frozen? {{twm ""}} {
	variable Frozen
	return [expr {[string length $twm] == 0 ? [string length $Frozen] > 0 : $Frozen eq $twm}]
}


proc extractLeaves {layout} {
	set length [llength $layout]
	set result {}

	for {set i 0} {$i < $length} {incr i 3} {
		set type [lindex $layout $i]

		if {$type in {pane frame}} {
			lappend result [lindex $layout [expr {$i + 1}]]
		} else {
			set result [concat $result [extractLeaves [lindex $layout [expr {$i + 2}]]]]
		}
	}

	return $result
}


proc layoutContainsOnlyOnePane {layout} {
	if {[llength $layout] != 3} { return false }
	lassign $layout type - body
	if {$type eq "root"} { return [layoutContainsOnlyOnePane $body] }
	if {$type ne "pane"} { return false }
	return true
}


proc compareLayouts {twm lhs rhs {ignoreCoords no}} {
	return [CompareLayouts $twm $lhs $rhs $ignoreCoords 0]
}


proc CompareLayouts {twm lhs rhs ignoreCoords level} {
	set length [llength $lhs]
	if {$length != [llength $rhs]} { return false }

	for {set i 0} {$i < $length} {incr i} {
		set typeL [lindex $lhs $i]
		set typeR [lindex $rhs $i]

		if {$typeL ne $typeR} { return false }
		incr i

		if {$typeL in {pane frame}} {
			if {[lindex $lhs $i] ne [lindex $rhs $i]} { return false }
			incr i
		}

		if {![CompareOptions $twm [lindex $lhs $i] [lindex $rhs $i] $ignoreCoords $level]} { return false }

		if {$typeL ni {pane frame}} {
			incr i
			if {![CompareLayouts \
						$twm \
						[lindex $lhs $i] \
						[lindex $rhs $i] \
						$ignoreCoords \
						[expr {$level + 1}] \
			]} {
				return false
			}
		}
	}

	return true
}


proc CompareOptions {twm lhs rhs ignoreCoords level} {
	array set optionsL $lhs
	array set optionsR $rhs
	if {$ignoreCoords || $level == 0} {
		array unset optionsL -x; array unset optionsL -y
		array unset optionsR -x; array unset optionsR -y
	}
	array unset optionsL -snapshots; array unset optionsL -structures
	array unset optionsR -snapshots; array unset optionsR -structures
	return [ArrayEqual $twm optionsL optionsR $level]
}


proc ArrayEqual {twm lhs rhs level} {
	upvar 1 $lhs foo $rhs bar

	foreach key [lsort -unique [concat [array names foo] [array names bar]]] {
		if {![info exists foo($key)]} {
			if {$key ne "-attrs"} { return false }
			set foo($key) {}
		} elseif {![info exists bar($key)]} {
			if {$key ne "-attrs"} { return false }
			set bar($key) {}
		}
		if {$key eq "-attrs"} {
			array set a $foo($key)
			array set b $bar($key)
			array unset a hide; array unset a stayontop
			array unset b hide; array unset b stayontop
			if {[info exists a(flat)] && !$a(flat)} { array unset a flat }
			if {[info exists b(flat)] && !$b(flat)} { array unset b flat }
			if {[info exists a(amalgamate)] && !$a(amalgamate)} { array unset a amalgamate }
			if {[info exists b(amalgamate)] && !$b(amalgamate)} { array unset b amalgamate }
			if {[info exists a(fullscreen)] && !$a(fullscreen)} { array unset a fullscreen }
			if {[info exists b(fullscreen)] && !$b(fullscreen)} { array unset b fullscreen }
			if {![ArrayEqual $twm a b $level]} { return false }
		} elseif {[string match {*%} $foo($key)] && [string match {*%} $bar($key)]} {
			set orient [expr {[string match {*height} $key] ? "vert" : "horz"}]
			return [$twm eqp? $orient $foo($key) $bar($key)]
		} elseif {$foo($key) ne $bar($key)} {
			return false
		}
	}

	return true
}


proc Collect {twm what args} {
	switch -- $what {
		amalgamate {
			return [lmap w [$twm find amalgamate 1] \
				{expr {[llength [$twm amalgamated $w]] ? $w : [continue]}}]
		}
		!amalgamate {
			return [lmap w [$twm find amalgamate 0] {expr {[$twm amalgamatable $w] ? $w : [continue]}}]
		}
		flat {
			return [lmap w [$twm find flat 1] {expr {[$twm ismetachild $w] ? [continue] : $w}}]
		}
		!flat {
			return [lmap w [$twm find flat 0] {expr {[$twm ismetachild $w] ? [continue] : $w}}]
		}
		floats {
			return [lmap w [$twm floats] {expr {[$twm get! $w hide 0] ? $w : [continue]}}]
		}
		visible {
			set w ""
			if {[llength $args]} {
				set w [lindex $args 0]
				if {[string length [set v [$twm amalgamated $w]]]} { set w $v }
			}
			set result {}
			foreach entry [$twm visible {*}$w] {
				lappend result [lindex $entry 0]
			}
			return $result
		}
	}
}


proc SetupTheme {twm} {
	variable ${twm}::Vars

	ttk::style configure twm.TLabel -background [ttk::style lookup TNotebook.Tab -background]
	ttk::style configure twm.TNotebook -borderwidth 0
#	ttk::style configure twm.TNotebook.Tab -font $Vars(header:font)
	ttk::style configure twm.TNotebook.Tab -padding {2 2}
	ttk::style configure twm.TButton -padding {1 1 0 0} -relief raised
	ttk::style map twm.TButton -relief [list {!disabled pressed} sunken] 
	ttk::style layout twm.TButton \
		{ Button.border -children { Button.padding -children { Button.label } } }

	if {[::scidb::tk::twm exists $twm]} {
		if {[string length [set background $Vars(panedwindow:background)]] == 0} {
			set background [GetBackground background]
		}
		foreach t [$twm toplevels] {
			foreach w [$twm container $t] {
				if {[$twm ispanedwindow $w]} {
					$w configure -background $background
				}
			}
		}
	}

#	set background [ttk::style lookup $::ttk::currentTheme -background]
#	ttk::style map twm.TNotebook.Tab -background [list active $background selected $background]
	set Vars(theme) $::ttk::currentTheme

	if {[info exists Vars(theme)] && $Vars(theme) ne $::ttk::currentTheme} {
		$twm refresh
	}
}


proc WidgetProc {twm command args} {
	variable Options
	variable ${twm}::Vars

	if {$command in {zoom undock dock destroy}} {
		::debuglog::log twm "$twm $command $args"
	}

	switch -- $command {
		adjacent			{ return [::scidb::tk::twm adjacent $twm {*}$args] }
		adjust			{ return [Adjust $twm {*}$args] }
		amalgamatable	{ return [::scidb::tk::twm amalgamatable $twm {*}$args] }
		amalgamate		{ return [Amalgamate $twm 1 {*}$args] }
		amalgamated		{ return [::scidb::tk::twm amalgamated $twm {*}$args] }
		build				{ return [BuildPane $twm {*}$args] }
		cget				{ return [$twm.__twm_frame__ cget {*}$args] }
		changeuid		{ return [::scidb::tk::twm changeuid $twm {*}$args] }
		childconfigure	{ return [ChildConfigure $twm {*}$args] }
		clone				{ return [::scidb::tk::twm clone $twm {*}$args] }
		close				{ return [Close $twm {*}$args] }
		collect			{ return [Collect $twm {*}$args] }
		compare			{ return [compareLayouts $twm {*}$args] }
		configure		{ return [$twm.__twm_frame__ configure {*}$args] }
		container		{ return [::scidb::tk::twm container $twm {*}$args] }
		deiconify		{ return [Deiconify $twm {*}$args] }
		destroy			{ DestroyPane $twm {*}$args }
		dimension		{ return [::scidb::tk::twm dimension $twm {*}$args] }
		fullscreen		{ return [Fullscreen $twm {*}$args] }
		geometry			{ return [Geometry $twm {*}$args] }
		dock				{ return [::scidb::tk::twm dock $twm {*}$args] }
		dump				{ return [::scidb::tk::twm dump $twm {*}$args] }
		eqp?				{ return [::scidb::tk::twm eqp $twm {*}$args] }
		exists			{ return [::scidb::tk::twm exists $twm {*}$args] }
		find				{ return [::scidb::tk::twm find $twm {*}$args] }
		flat?				{ return [HasFlatHeader $twm {*}$args] }
		floats			{ return [::scidb::tk::twm floats $twm] }
		frame				{ return [MakeFrame $twm frame {*}$args] }
		frame2			{ MakeFrame2 $twm {*}$args }
		framehdrsize	{ return [FrameHeaderSize $twm {*}$args] }
		frames			{ return [::scidb::tk::twm frames $twm {*}$args] }
		frozen?			{ return [expr {[set [namespace current]::Frozen] eq $twm}] }
		get				{ return [::scidb::tk::twm get $twm {*}$args] }
		get!				{ return [::scidb::tk::twm get! $twm {*}$args] }
		header			{ UpdateHeader $twm {*}$args }
		headerfontsize	{ return [HeaderFontSize $twm {*}$args] }
		headerframes	{ return [::scidb::tk::twm headerframes $twm] }
		hidden			{ return [::scidb::tk::twm hidden $twm {*}$args] }
		hide				{ Hide $twm {*}$args }
		id					{ return [::scidb::tk::twm id $twm {*}$args] }
		init				{ ::scidb::tk::twm init $twm -aligntimeout $Vars(panedwindow:timeout) {*}$args }
		inspect			{ return [::scidb::tk::twm inspect $twm \
											flat hide stayontop amalgamate fullscreen {*}$args] }
		iscontainer		{ return [::scidb::tk::twm iscontainer $twm {*}$args] }
		isdocked			{ return [::scidb::tk::twm isdocked $twm {*}$args] }
		isfloat			{ return [expr {$args in [$twm floats]}] }
		isframe			{ return [string match "TwmFrame" [winfo class {*}$args]] }
		isheaderframe	{ return [string match {Twm*rame} [winfo class {*}$args]] }
		ismetachild		{ return [::scidb::tk::twm ismetachild $twm {*}$args] }
		ismetaframe		{ return [string equal "TwmMetaframe" [winfo class {*}$args]] }
		ismultiwindow	{ return [string match {*Multiwindow} [winfo class {*}$args]] }
		isnotebook		{ return [string match {*Notebook} [winfo class {*}$args]] }
		ispane			{ return [::scidb::tk::twm ispane $twm {*}$args] }
		ispanedwindow	{ return [string match {*Panedwindow} [winfo class {*}$args]] }
		isroot			{ return [string match $twm {*}$args] }
		istoplevel		{ return [expr {[::scidb::tk::twm toplevel $twm {*}$args] eq $args}] }
		isundockable	{ return [::scidb::tk::twm get $twm [::scidb::tk::twm leaf $twm {*}$args] undock 0]}
		leader			{ return [::scidb::tk::twm leader $twm {*}$args] }
		leaf				{ return [::scidb::tk::twm leaf $twm {*}$args] }
		leaves			{ return [::scidb::tk::twm leaves $twm {*}$args] }
		load				{ ::scidb::tk::twm load $twm {*}$args }
		metaframe		{ return [MakeFrame $twm metaframe {*}$args] }
		multiwindow		{ return [MakeMultiwindow $twm {*}$args] }
		nbhdrsize		{ return [NotebookHeaderSize $twm {*}$args] }
		neighbors		{ return [::scidb::tk::twm neighbors $twm {*}$args] }
		new				{ return [::scidb::tk::twm new $twm {*}$args] }
		notebook			{ return [MakeNotebook $twm {*}$args] }
		orientation		{ return [::scidb::tk::twm orientation $twm {*}$args] }
		pack				{ return [Pack $twm {*}$args] }
		paneconfigure	{ return [PaneConfigure $twm {*}$args] }
		panedwindow		{ return [MakePanedWindow $twm {*}$args] }
		pane				{ return [MakePane $twm {*}$args] }
		panes				{ return [::scidb::tk::twm panes $twm {*}$args] }
		parent			{ return [::scidb::tk::twm parent $twm {*}$args] }
		ready				{ event generate $twm <<TwmReady>> -data $args }
		ready?			{ return [::scidb::tk::twm ready $twm] }
		refresh			{ return [::scidb::tk::twm refresh $twm {*}$args] }
		resize			{ return [Resize $twm {*}$args] }
		resizing			{ return [Resizing $twm {*}$args] }
		sashsize			{ return $Options(sash:size) }
		see				{ ::scidb::tk::twm see $twm {*}$args }
		select			{ return [Select $twm {*}$args] }
		selected			{ return [QuerySelected $twm {*}$args] }
		separate			{ return [Amalgamate $twm 0 {*}$args] }
		set				{ ::scidb::tk::twm set $twm {*}$args }
		set!				{ ::scidb::tk::twm set! $twm {*}$args }
		show				{ ::scidb::tk::twm show $twm {*}$args }
		showall			{ return [ShowAll $twm {*}$args] }
		stayontop		{ StayOnTop $twm {*}$args }
		title				{ UpdateTitle $twm {*}$args }
		togglebar		{ return [ToggleHeaders $twm {*}$args] }
		togglenotebook	{ return [::scidb::tk::twm toggle $twm {*}$args] }
		toplevel			{ return [::scidb::tk::twm toplevel $twm {*}$args] }
		toplevels		{ return [::scidb::tk::twm toplevels $twm {*}$args] }
		uid				{ return [::scidb::tk::twm uid $twm {*}$args] }
		undock			{ return [::scidb::tk::twm undock $twm {*}$args] }
		unpack			{ return [Unpack $twm {*}$args] }
		visible			{ return [::scidb::tk::twm visible $twm {*}$args] }
		zoom {
			set result [::scidb::tk::twm zoom $twm {*}$args]
			if {$::debuglog::enabled} {
				::debuglog::log twm "$twm zoomed=[::scidb::tk::twm zoomed $twm]"
			}
			return $result
		}
		zoomed { return [::scidb::tk::twm zoomed $twm] }
		zoomsashes { return [ZoomSashes $twm {*}$args] }
		workarea			{ return [WorkArea $twm {*}$args] }
		default			{ return -code error "unknown command '$command'" }
	}

	return $twm
}


proc HeaderFontSize {twm {fontSize 0}} {
	variable ${twm}::Vars
	variable Options

	if {$fontSize <= 0} { return $Options(header:fontsize) }
	if {$fontSize == $Options(header:fontsize)} { return }

	font configure $Vars(header:font) -size [set Options(header:fontsize) $fontSize]
	$twm refresh

	foreach frame [$twm headerframes] {
		after idle [list [namespace current]::ConfigureLabelBar frame $twm $frame -1]
	}
}


proc ShowAll {twm flag} {
	variable ${twm}::Vars
	set Vars(cross:showall) $flag
}


proc DestroyPane {twm pane} {
	catch { destroy $pane }
}


proc BuildPane {twm frame id width height} {
	variable ${twm}::Vars

	set pane $frame
	if {![$twm ispane $pane]} { set pane [lindex [pack slaves $frame] end] }
	if {[llength $Vars(cmd:buildpane)]} {
		set bd [expr {-2*$Vars(frame:borderwidth)}]
		incr width $bd
		incr height $bd
		$Vars(cmd:buildpane) $twm $pane $id $width $height
	}
	$frame configure -background [$pane cget -background]
}


proc FrameHeaderSize {twm frame} {
	variable ${twm}::Vars
	variable Options

	# During a multiwindow<->notebook toggle the C++ may query the header
	# size of a node that is no longer a frame; get! then throws. Treat
	# that as not-flat (notebook-style header) instead of crashing.
	set flat 0
	catch { set flat [$twm get! $frame flat 0] }
	if {$flat} {
		set size $Options(flathandle:size)
	} else {
		lassign $Options(mtab:padding:selected) l t r b
		set size  [expr {$t + $b + 2}] ;# 2 additional pixels (TODO: what's the reason?)
		set font [ttk::style lookup twm.TLabel -font]
		if {[string length $font] == 0} { set font TkDefaultFont }
		incr size [font metrics $font -linespace]
		incr size [expr {$size % 2}] ;# we have even sized headers
	}
	incr size [expr {2*$Vars(header:borderwidth)}]
#	if {[set ht [winfo height $frame.__header__]] > 1 && $ht != $size} {
#		puts stderr "FrameHeaderSize: computed=$size, but measured=$ht"
#	}
	return $size
}


proc NotebookHeaderSize {twm {nb}} {
	set padding [ttk::style lookup twm.TNotebook.Tab -padding]
	if {[llength $padding] == 0} {
		puts stderr "\[ttk::style lookup TNotebook.Tab -padding\] returns empty list"
		set padding {2 2}
	}
	set size [expr {2*[ttk::style lookup TNotebook -borderwidth] + 1}] ;# plus one overlapping pixel
	switch [llength $padding] {
		2 { incr size [expr {2*[lindex $padding 1]}] }
		3 { incr size [lindex $padding 1] }
		4 { incr size [lindex $padding 1]; incr size [lindex $padding 3] }
	}
	set font [ttk::style lookup TNotebook.Tab -font]
	if {[string length $font] == 0} {
		set font [ttk::style lookup TNotebook -font]
		if {[string length $font] == 0} { set font TkDefaultFont }
	}
	set linespace [font metrics [ttk::style lookup TNotebook.Tab -font] -linespace]
	set haveImage 0
	if {[string length $nb]} {
		foreach tab [$nb tabs] {
			if {[string length [set img [$nb tab $tab -image]]]} {
				set linespace [expr {max($linespace, [image height $img])}]
				set haveImage 1
			}
		}
	}
	incr size $haveImage
	incr size $linespace
#	if {	[string length [$nb select]]
#		&& [set ht [expr {[winfo height $nb] - [winfo height [$nb select]]}]] > 1
#		&& $ht != $size} { puts stderr "NotebookHeaderSize: computed=$size, but measured=$ht" }
	return $size
}


proc MakeMultiwindow {twm args} {
	variable ${twm}::Counter

	# NOTE: Instead of tk::multiwindow another choice may be ttk::scrollbar w/o tab handles.
	set w [tk::multiwindow $twm.__multiwindow__[incr Counter(multiwindow)] -takefocus 0]
	if {[llength $args] == 1} { set args [lindex $args 0] }
	foreach {name value} $args {
		catch { $w configure $name $value }
	}
	# ensure existence of this attribute
	$twm set! $w amalgamate [$twm get! $w amalgamate 0]
	return $w
}


proc MakeNotebook {twm args} {
	variable ${twm}::Vars
	variable ${twm}::Counter

	set w [ttk::notebook $twm.__notebook__[incr Counter(notebook)] -style twm.TNotebook -takefocus 0]
	if {$Vars(state) eq "disabled"} { $w configure -state "disabled" }
	MenuBindings $twm $w $w
	if {[llength $args] == 1} { set args [lindex $args 0] }
	foreach {name value} $args {
		catch { $w configure $name $value }
	}
	return $w
}


proc MakePanedWindow {twm args} {
	variable ${twm}::Counter
	variable ${twm}::Vars
	variable Options

	set w [tk::panedwindow $twm.__panedwindow__[incr Counter(panedwindow)]]
	if {[string length [set background $Vars(panedwindow:background)]] == 0} {
		set background [GetBackground background]
	}
	$w configure \
		-background $background \
		-sashwidth $Options(sash:size) \
		-sashrelief $Vars(panedwindow:relief) \
		-state [expr {$Vars(state) eq "normal" ? "normal" : "disabled"}] \
		;
	if {[llength $args] == 1} { set args [lindex $args 0] }
	foreach {name value} $args {
		catch { $w configure $name $value }
	}
	return $w
}


proc MakePane {twm id} {
	variable ${twm}::Vars

	lassign [$Vars(cmd:makepane) $twm $twm pane $id] w name priority transient close undock move zoomable
	$w configure -borderwidth $Vars(frame:borderwidth) -relief raised
	$twm set $w name $name priority $priority transient $transient zoomable [expr {$zoomable eq "1"}]
	if {$zoomable eq "1"} {
		set hdr [tk::frame $w.__header__]
		pack $hdr -side top -fill x
		ttk::label $hdr.title -textvariable $name
		pack $hdr.title -side left
		ttk::button $hdr.zoom -image $icon::12x12::maximise -takefocus 0 -command [list $twm zoom $w]
		pack $hdr.zoom -side right
		tooltip $hdr.zoom "Maximise / restore pane (Ctrl+Shift+Z)"
	}
	return $w
}


proc MakeFrame {twm type {id ""}} {
	variable ${twm}::Counter

	set frame $twm.__${type}__${id}__[incr Counter($type)]
	set class Twm[string toupper $type 0 0]
	tk::frame $frame -class $class -borderwidth 0 -takefocus 0
	# ensure existence of this attribute
	$twm set! $frame amalgamate [$twm get! $frame amalgamate 0]
	return $frame
}


proc MakeFrame2 {twm frame id} {
	variable Options
	variable ${twm}::Vars

	if {[$twm isframe $frame]} {
		lassign [$Vars(cmd:makepane) $twm $frame frame $id] \
			child name priority transient closable undockable moveable zoomable
		$twm set $frame zoomable [expr {$zoomable eq "1"}]
		$child configure -borderwidth $Vars(frame:borderwidth) -relief raised
	} elseif {[$twm iscontainer $id]} {
		set child $id
		set leader [$twm leader $id]
		set name [$twm get $leader name]
		set priority [$twm get $leader priority]
		set transient [$twm get $leader transient]
		set panes [lmap w [$twm panes $child] {expr {[$twm ispane $w] ? $w : [continue]}}]
		if {[llength $panes] > 0} {
			lassign {0 0 0} closable undockable moveable
		} else {
			lassign {1 1 1} closable undockable moveable
			foreach f [$twm frames $child] {
				if {![$twm get $f move]} { set moveable 0 }
				if {![$twm get $f close]} { set closable 0 }
				if {![$twm get $f undock]} { set undockable 0 }
			}
		}
	} else {
		set child $id
		lassign {0 0 0} closable undockable moveable
		set priority [$twm get $id priority]
		set transient [$twm get $id transient]
		set name [$twm get $id name]
	}

	if {![$twm isframe $frame] && ![$twm istoplevel $frame]} {
		raise $child $frame
	}

	set hdr [tk::frame $frame.__header__ \
		-borderwidth $Vars(header:borderwidth) \
		-relief raised \
		-takefocus 0 \
	]

	if {$moveable} {
		set bg $Options(header:flex:background)
	} else {
		set bg [ttk::style lookup $::ttk::currentTheme -background]
	}
	$hdr configure -background $bg
	if {![$twm ismetachild $frame] && $Vars(state) eq "normal"} {
		bind $hdr <Double-Button-1> [list [namespace current]::ToggleHeaders $twm $frame]
	}

	pack $child -side top -fill both -expand yes -in $frame

	ttk::button $hdr.join -style twm.TButton -takefocus 0
	MouseWheelBindings $twm $frame $hdr.join
	MenuBindings $twm $frame $hdr.join

	if {$closable} {
		ttk::button $hdr.close \
			-style twm.TButton \
			-image $icon::12x12::close \
			-state [expr {$closable ? "normal" : "disabled"}] \
			-takefocus 0 \
			;
		MouseWheelBindings $twm $frame $hdr.close
		MenuBindings $twm $frame $hdr.close
		if {$Vars(state) eq "normal"} {
			$hdr.close configure -command [list $twm close $frame]
			tooltip $hdr.close [tr [namespace current]::mc::Close]
		}
	}
	if {$undockable} {
		ttk::button $hdr.undock \
			-style twm.TButton \
			-image $icon::12x12::undock \
			-state [expr {$undockable ? "normal" : "disabled"}] \
			-takefocus 0 \
			;
		MouseWheelBindings $twm $frame $hdr.undock
		MenuBindings $twm $frame $hdr.undock
		if {$Vars(state) eq "normal"} {
			$hdr.undock configure -command [list [namespace current]::Undock $twm $frame]
			tooltip $hdr.undock [tr [namespace current]::mc::Undock]
		}
	}

	$twm set $frame \
		name $name \
		id $id \
		move $moveable \
		close $closable \
		undock $undockable \
		priority $priority \
		transient $transient \
		;

	# ensure existence of this attribute
	$twm set! $frame flat [$twm get! $frame flat 0]

	if {[$twm get $frame zoomable 0]} {
		ttk::button $hdr.zoom -style twm.TButton -image $icon::12x12::maximise -takefocus 0 \
			-command [list $twm zoom $frame]
		tooltip $hdr.zoom "Maximise / restore pane (Ctrl+Shift+Z)"
	}
	ShowHeaderButtons $twm $frame
	HeaderBindings $twm $frame $hdr
}


proc GetBackground {option} { ;# use with "background" or "troughcolor"
	variable Scale {}
	if {[catch { ::ttk::style lookup $::ttk::currentTheme -$option } result]} {
		if {[llength $Scale] == 0} {
			set Scale [ttk::scale .__hopefully_unique_widget_id__[clock milliseconds]]
		}
		set result [$Scale cget -$option]
	}
	if {[string length $result] == 0} {
		set result #d9d9d9
	}
	return $result
}


proc ShowHeaderButtons {twm frame} {
	variable ${twm}::Vars

	set hdr $frame.__header__
	if {[winfo exists $hdr.zoom]} { grid $hdr.zoom -column 7 -row 0 }

	if {[$twm isframe $frame] && [llength [$twm panes $twm]] == 1} {
		catch { grid forget $hdr.close }
		catch { grid forget $hdr.undock }
		catch { grid forget $hdr.join }
	} else {
		set undockable [$twm get $frame undock]
		set closable   [$twm get $frame close]

		set w $frame
		if {[$twm ismetaframe $w]} {
			if {[string length [set w [$twm amalgamated $w]]] == 0} {
				set w $frame
			}
		}
		set amalgamate [$twm get! $w amalgamate]

		if {[$twm amalgamatable $w] && $amalgamate == [$twm ismetaframe $frame]} {
			grid $hdr.join -column 1 -row 0
			grid columnconfigure $hdr 2 -minsize 3
			set dir [expr {$amalgamate ? "down" : "up"}]
			$hdr.join configure -image $icon::12x12::arrow($dir)
			if {$Vars(state) eq "normal"} {
				set cmd [expr {$amalgamate ? "separate" : "amalgamate"}]
				$hdr.join configure -command [list $twm $cmd $w]
				set tip [expr {$amalgamate ? "Separate" : "Amalgamate"}]
				tooltip $hdr.join [tr [namespace current]::mc::$tip]
			}
		} else {
			grid $hdr.join -column 1 -row 0
			catch { grid forget $hdr.join }
			grid columnconfigure $hdr 2 -minsize 0
		}

		if {$undockable} { grid $hdr.undock -column 3 -row 0 }
		if {$closable}   { grid $hdr.close  -column 5 -row 0 }

		grid columnconfigure $hdr 0 -weight 1 -minsize 5
		if {$closable && $undockable} {
			grid columnconfigure $hdr 4 -minsize 3
		}
		grid columnconfigure $hdr 6 -minsize 2
	}
}


proc UnbindHeader {w} {
	bind $w <Configure> {#}
	bind $w <ButtonPress-1> {#}
	bind $w <Button1-Motion> {#}
	bind $w <ButtonRelease-1> {#}
}


proc HeaderBindings {twm frame w} {
	variable ${twm}::Vars

	if {$Vars(state) eq "normal"} {
		if {[$twm get $frame move]} {
			bind $w <ButtonPress-1>		[list [namespace current]::HeaderPress $twm $frame %X %Y]
			bind $w <Button1-Motion>	[list [namespace current]::HeaderMotion $twm $frame %X %Y]
			bind $w <ButtonRelease-1>	[list [namespace current]::HeaderRelease $twm $frame]
			bind $w <ButtonPress-1>		{+ break }
			bind $w <ButtonRelease-1>	{+ break }
			bind $w <Button1-Motion>	{+ break }
		}
	}
	MouseWheelBindings $twm $frame $w
	MenuBindings $twm $frame $w
}


proc MenuBindings {twm frame w} {
	variable ${twm}::Vars

	if {$Vars(state) eq "normal"} {
		bind $w <ButtonPress-3> [list event generate $twm <<TwmMenu>> -x %X -y %Y -data $frame]
	}
}


proc MouseWheelBindings {twm frame w} {
	variable ${twm}::Vars
	
	if {$Vars(state) eq "disabled"} { return }

	switch [tk windowingsystem] {
		x11 {
			bind $w <Button-4> [list [namespace current]::PlaceLabelBar $twm $frame -5]
			bind $w <Button-5> [list [namespace current]::PlaceLabelBar $twm $frame +5]
		}
		aqua {
			bind $w <MouseWheel> "[list [namespace current]::PlaceLabelBar $twm $frame] \[expr {-(%D)}\]"
		}
		win32 {
			bind $w <MouseWheel> \
				"[list [namespace current]::PlaceLabelBar $twm $frame] \[expr {-(%D/120)*5}\]"
		}
	}
}


proc Resize {twm pane width height args} {
	set bd [expr {2*[$pane cget -borderwidth]}]
	if {$width > 0} { set width [expr {$width + $bd}] }
	if {$height > 0} { set height [expr {$height + $bd}] }
	if {[llength $args] == 4} {
		lassign $args minWidth minHeight maxWidth maxHeight
		if {$minWidth > 0} { set minWidth [expr {$minWidth + $bd}] }
		if {$minHeight > 0} { set minHeight [expr {$minHeight + $bd}] }
		if {$maxWidth > 0} { set maxWidth [expr {$maxWidth + $bd}] }
		if {$maxHeight > 0} { set maxHeight [expr {$maxHeight + $bd}] }
		::scidb::tk::twm resize $twm $pane $width $height $minWidth $minHeight $maxWidth $maxHeight
	} else {
		::scidb::tk::twm resize $twm $pane $width $height
	}
}


proc UpdateTitle {twm frame titlePath args} {
	if {![winfo exists $frame]} { return }
	if {[string length $titlePath] == 0} {
		set title [$twm get $frame title ""]
		if {[string length $title] == 0} { return }
	} else {
		set leader [$twm leader $frame]
		set name [$twm get $leader name]
		set title [$twm get $titlePath title $name]
		if {[info exists $title]} {
			trace add variable $title write [list [namespace current]::UpdateTitle $twm $frame ""]
		}
	}
	SetTitle $twm $frame $title
}


proc SetTitle {twm frame title} {
	$twm set $frame title $title
	if {[info exists $title]} { set title [set $title] }
	if {[winfo toplevel $frame] eq $frame} {
		wm title $frame $title
	}
}


proc Amalgamate {twm flag args} {
	foreach frame $args {
		set t [$twm parent $frame]
		if {![$twm ismultiwindow $t]} { set t $frame }
		$twm set! $t amalgamate $flag
	}
	$twm refresh
}


proc Adjust {twm frame id dimensions} {
	variable ${twm}::Vars

	if {[llength $Vars(cmd:adjustcmd)] == 0} { return {} }
	return [{*}$Vars(cmd:adjustcmd) $twm $frame $id $dimensions]
}


proc ToggleHeaders {twm args} {
	foreach frame $args {
		ToggleHeader $twm $frame
	}
	after idle [list $twm refresh]
}


proc ToggleHeader {twm frame} {
	variable ${twm}::Vars
	variable Options

	if {![winfo exists $frame]} { return }

	set flat [$twm get! $frame flat 0]
	$twm set! $frame flat [expr {!$flat}]
	set hdr $frame.__header__

	if {$flat} {
		pack forget $hdr.__flat__
		ShowHeaderButtons $twm $frame
		HeaderBindings $twm $frame $frame
		HeaderBindings $twm $frame $hdr
		UpdateHeader $twm $frame [$twm get $frame panes]
		if {$Vars(state) eq "normal"} {
			bind $hdr <Double-Button-1> [list [namespace current]::ToggleHeaders $twm $frame]
		}
		event generate $twm <<TwmHeader>> -data $frame
	} else {
		MakeFlatHeader $twm $frame
	}
}


proc MakeFlatHeader {twm frame} {
	variable ${twm}::Vars
	variable Options

	set hdr $frame.__header__
	set decor $hdr.__flat__
	if !{[winfo exists $decor]} {
		tk::canvas $decor -height $Options(flathandle:size) -background $Options(header:flex:background)
		if {$Vars(state) ne "disabled"} {
			bind $decor <Configure> [list [namespace current]::ConfigureFlatHandle $decor %w %h]
		}
		MenuBindings $twm $frame $decor
	}
	catch { destroy $hdr.l }
	catch { destroy $hdr.r }
	destroy {*}[$twm get $frame labels {}]
	set slaves [grid slaves $hdr]
	if {[llength $slaves]} { grid forget {*}$slaves }
	foreach w [place slaves $hdr] { place forget $w }
	$twm set $frame labels {}
	pack $decor -fill x -side top -expand yes
	if {$Vars(state) eq "normal"} {
		bind $decor <ButtonRelease-1> [list [namespace current]::ToggleHeaders $twm $frame]
		bind $decor <ButtonRelease-1> {+ break }
		bind $hdr <Double-Button-1> {#}
	}
	UnbindHeader $frame
	UnbindHeader $hdr
	event generate $twm <<TwmHeader>> -data $frame
}


proc HasFlatHeader {twm frame} {
	set hdr $frame.__header__
	set decor $hdr.__flat__
	return [expr {[winfo exists $hdr] && $decor in [pack slaves $hdr]}]
}


proc ConfigureFlatHandle {canv w h} {
	variable Options

	if {$w <= 1} { return }

	set n [expr {$w/2}]
	set x0 [expr {($w - 2*$n)/2}]
	set y0 1
	set yi $y0

	for {set i 1} {$i <= $n} {incr i; incr x0 2} {
		if {[llength [$canv find withtag $i]] == 0} {
			foreach k {1 2 3} { set x$k [expr {$x0 + $k}]; set y$k [expr {$y0 + $k}] }
			$canv create rectangle $x0 $y0 $x2 $y2 -fill $Options(flathandle:color:lite) -outline {} -tag $i
			$canv create rectangle $x1 $y1 $x3 $y3 -fill $Options(flathandle:color:dark) -outline {} -tag $i
			$canv create rectangle $x1 $y1 $x2 $y2 -fill $Options(flathandle:color:gray) -outline {} -tag $i
		}
		if {$y0 == $yi} { incr y0 3 } else { set y0 $yi }
	}
}


proc UpdateHeader {twm frame panes {selection ""}} {
	variable ${twm}::Vars
	variable Options

	set hdr $frame.__header__
	bind $hdr <Configure> {#}
	destroy {*}[place slaves $hdr]
	catch { destroy $hdr.l }
	catch { destroy $hdr.r }
	foreach w [winfo children $hdr] {
		if {[string match {*:label} $w]} { destroy $w }
	}
	$twm set $frame labels {} panes $panes
	set zoomPane $selection
	if {$zoomPane eq ""} { set zoomPane $frame }
	if {[$twm iscontainer $zoomPane]} { set zoomPane [$twm leader $zoomPane] }
	if {![$twm get $zoomPane zoomable 0] || [$twm isfloat [$twm toplevel $zoomPane]]} {
		if {[winfo exists $hdr.zoom]} { destroy $hdr.zoom }
	} else {
		if {![winfo exists $hdr.zoom]} {
			ttk::button $hdr.zoom -style twm.TButton -image $icon::12x12::maximise -takefocus 0
			tooltip $hdr.zoom "Maximise / restore pane (Ctrl+Shift+Z)"
		}
		$hdr.zoom configure -command [list $twm zoom $zoomPane]
	}


	if {[llength $panes] == 0} {
		if {$Vars(docking:current) ne $frame} {
			pack forget $frame.__header__
		}
		return
	}

	if {"$frame.__header__" ni [pack slaves $frame]} {
		pack $frame.__header__ -side top -fill x -expand no -before [lindex [pack slaves $frame] 0]
	}

	raise $hdr ;# seems to be a bug in Tk lib that a child must be raised

	set flat [expr {[llength [pack slaves $hdr]] > 0}]
	if {$flat != [$twm get! $frame flat 0]} {
		if {$flat} {
			pack forget {*}[pack slaves $hdr]
			if {![$twm ismetachild $frame] && $Vars(state) eq "normal"} {
				bind $hdr <Double-Button-1> [list [namespace current]::ToggleHeaders $twm $frame]
			}
		} else {
			MakeFlatHeader $twm $frame
		}
	}

	if {[$twm get! $frame flat 0]} { return }
	ShowHeaderButtons $twm $frame

	set n [llength $panes]
	set parent [$twm parent $frame]
	set labels {}
	set type [expr {[$twm get $frame move] ? "flex" : "fix"}]
	set lighter [ttk::style lookup $::ttk::currentTheme -background]
	set darker [ttk::style lookup TNotebook.Tab -background]
	set confCmd [list [namespace current]::ConfigureLabelBar trace $twm $frame 0]

	for {set i 0} {$i < $n} {incr i} {
		set f [lindex $panes $i]
		set lbl $hdr.$i:label
		set name [$twm get [$twm leader $f] name]
		if {[info exists $name]} {
			trace add variable $name write $confCmd
			set var var
		} else {
			set var ""
		}
		ttk::label $lbl -style twm.TLabel -text$var $name -takefocus 0
		if {$var eq "var"} { bind $lbl <Destroy> [list trace remove variable $name write $confCmd] }
		place $lbl -x 0 -y 0
		lappend labels $lbl
		if {$f eq $frame || $f eq $selection} {
			HeaderBindings $twm $frame $lbl
			$twm set $frame mine $lbl
			set index $i
			if {[$twm get $frame move]} {
				$lbl configure \
					-relief flat \
					-padding $Options(mtab:padding:selected) \
					-background $Options(header:$type:background) \
					-foreground $Options(header:$type:foreground) \
					;
			} else {
				$lbl configure \
					-relief raised \
					-padding $Options(mtab:padding:fixed) \
					-background $Options(header:tab:background) \
					-foreground $Options(header:$type:foreground) \
					;
			}
		} else {
			if {$Vars(state) ne "disabled"} {
				bind $lbl <ButtonPress-1> [list [namespace current]::Select $twm $parent $f]
				bind $lbl <ButtonPress-1> {+ break }
				bind $lbl <Enter> [list $lbl configure -background $lighter]
				bind $lbl <Leave> [list $lbl configure -background $darker]
				MouseWheelBindings $twm $frame $lbl
				MenuBindings $twm $frame $lbl
			}
			$lbl configure \
				-relief raised \
				-padding $Options(mtab:padding:hidden) \
				-foreground $Options(header:tab:foreground) \
				-background $darker \
				;
		}
	}

	$twm set $frame maxoffset 0 labels $labels repeat 0 width 0
	after idle [list [namespace current]::ConfigureLabelBar init $twm $frame -1]
	bind $hdr <Configure> [list [namespace current]::ConfigureLabelBar hdr $twm $frame %w]
	bind $hdr <Map> [list [namespace current]::ConfigureLabelBar hdr $twm $frame -1]
	bind $frame <Configure> [list [namespace current]::ConfigureLabelBar frame $twm $frame %w]
}


proc ConfigureLabelBar {source twm frame width args} {
	variable ${twm}::Vars

	if {![winfo exists $frame]} { return }

	set hdr $frame.__header__
	if {$hdr ni [pack slaves $frame]} { return }
	set bd [expr {2*$Vars(header:borderwidth)}]
	set see [expr {$width < 0}]
	set force [expr {$width <= 0}]
	set current [expr {$width >= 0}]
	if {$width <= 1} { set width [winfo width $frame] }
	if {$width <= 1} { return }
	if {!$force && [$twm get $frame width 0] == $width} { return }
	$twm set $frame width $width
	set labels [$twm get $frame labels]
	if {[llength $labels] == 0} { return }
	set parent [$twm parent $frame]
	set offset [$twm get $parent offset 0]
	set h [winfo reqheight [lindex $labels 0]]
	if {$h % 2 == 1} { incr h }
	set showButtons [expr {!([$twm isframe $frame] && [llength [$twm panes $twm]] == 1)}]
	set haveClose [expr {$showButtons && [winfo exists $hdr.close]}]
	set haveUndock [expr {$showButtons && [winfo exists $hdr.undock]}]
	set haveJoin [expr {$showButtons && [winfo exists $hdr.Join]}]
	if {$haveClose} { incr width -[winfo width $hdr.close] }
	if {$haveUndock} { incr width -[winfo width $hdr.undock] }
	if {$haveJoin} { incr width -[winfo width $hdr.Join] }
	if {$haveClose || $haveUndock} { incr width -8 }
	if {$haveJoin} { incr width -8 }
	if {!!$haveClose && !!$haveUndock && !!$haveJoin >= 2} { incr width -3 }
	incr width -$bd

	foreach w $labels { incr totalWidth [winfo reqwidth $w] }
	if {$totalWidth > $width && [llength $labels] > 1} {
		MakeArrow $twm $frame l -5
		MakeArrow $twm $frame r +5
		set arrwd [winfo reqwidth $hdr.l]
		set maxoffset [expr {$totalWidth - $width + 2*$arrwd - $bd}]
		$twm set $frame maxoffset $maxoffset
		if {$offset > $maxoffset} { $twm set $parent offset $maxoffset }
		set totalWidth [expr {min($totalWidth, $width) - $arrwd}]
	} else {
		if {[winfo exists $hdr.l]} {
			destroy $hdr.l; destroy $hdr.r
		}
		$twm set $parent offset 0
		$twm set $frame maxoffset 0
	}

	$twm set $frame height $h labelbarwidth [expr {min($width,$totalWidth)}]
	PlaceLabelBar $twm $frame [expr {$see ? "see" : ($current ? 0 : "setup")}]
	$hdr configure -height [expr {$h + $bd}]
	grid rowconfigure $hdr 0 -minsize $h
}


proc PlaceLabelBar {twm frame incr} {
	variable ${twm}::Vars

	if {[$twm get! $frame flat 0]} { return }

	set parent [$twm parent $frame]
	set maxoffset [$twm get $frame maxoffset 0]
	set labels [$twm get $frame labels]
	set width [$twm get $frame labelbarwidth]
	set bd [expr {2*$Vars(header:borderwidth)}]
	set hdr $frame.__header__

	if {$incr eq "setup"} {
		set offset [$twm get $parent offset]
	} else {
		if {$incr eq "see"} {
			set incr 0
			set visible [$twm get $frame mine]
			$twm set $parent visible $visible
		} else {
			set visible [$twm get $parent visible ""]
		}
		set offset [expr {max(0, min($maxoffset, [$twm get $parent offset 0] + $incr))}]
		if {$maxoffset > 0} {
			if {$incr == 0} {
				if {[string length $visible] > 0} {
					set x0 0
					foreach w $labels {
						set x1 [expr {$x0 + [winfo reqwidth $w]}]
						if {$w eq $visible} { break }
						set x0 $x1
					}
					if {$x0 < $offset} {
						set offset [expr {min($x0, $maxoffset)}]
					} elseif {[set d [expr {$x1 + [winfo reqwidth $hdr.l] - $width - $offset - $bd}]] > 0} {
						set offset [expr {min($offset + $d, $maxoffset)}]
					}
				}
			} elseif {$offset == [$twm get $parent offset]} {
				return
			}
		}
	}

	$twm set $parent offset $offset
	set height [$twm get $frame height]
	set x -$offset

	if {$maxoffset > 0} {
		set ht [winfo reqheight $hdr]
		place $hdr.l -x -$bd -y 3 -height $ht
		set x [expr {$x + [winfo reqwidth $hdr.l] - $bd}]
		if {$offset == 0} { set state disabled } else { set state normal }
		if {$state ne [$hdr.l cget -state]} { $hdr.l configure -state $state }
	}

	foreach w $labels {
		if {$x >= $width} {
			place forget $w
		} else {
			set y $height
			if {[$w cget -relief] ne "flat"} { incr y $bd }
			set wd [expr {min([winfo reqwidth $w], $width - $x)}]
			if {$wd < [winfo reqwidth $w]} { set extend 4 } else { set extend 0 }
			place $w -x $x -y $y -width [expr {$wd + $extend}] -anchor sw
			incr x $wd
			raise $w ;# seems to be a bug in Tk lib that a child must be raised
		}
	}

	if {$maxoffset > 0} {
		set x $width
		set ht [winfo reqheight $hdr]
		place $hdr.r -x $x -y 3 -height $ht
		if {$offset == $maxoffset} { set state disabled } else { set state normal }
		if {$state ne [$hdr.r cget -state]} { $hdr.r configure -state $state }
		raise $hdr.l; raise $hdr.r
	}
}


proc MakeArrow {twm frame dir incr} {
	variable ${twm}::Vars

	set arrow $frame.__header__.$dir
	if {[winfo exists $arrow]} { return }
	ttk::button $arrow \
		-style twm.TButton \
		-takefocus 0 \
		-image [makeStateSpecificIcons $icon::8x16::arrow($dir)] \
		-command [list [namespace current]::PlaceLabelBar $twm $frame $incr] \
		;
	raise $arrow
	if {$Vars(state) ne "disabled"} {
		bind $arrow <ButtonPress-1> [list [namespace current]::InvokeRepeat $twm $frame $arrow]
		MouseWheelBindings $twm $frame $arrow
		MenuBindings $twm $frame $arrow
	}
}


proc InvokeRepeat {twm frame w} {
	variable Options

	if {![winfo exists $w]} { return }
	catch { after cancel [$twm get $frame repeat] }
	$twm set $frame repeat [after $Options(repeat:delay) \
		[list [namespace current]::Repeat $twm $frame $w]]
}


proc Repeat {twm frame w} {
	variable Options

	if {![winfo exists $w]} { return }
	$w instate disabled { $w state !pressed } ;# required because of a Tk bug
	$w instate !pressed { return }
	$twm set $frame repeat [after $Options(repeat:interval) \
		[list [namespace current]::Repeat $twm $frame $w]]
	eval [$w cget -command]
}


proc HeaderPress {twm frame x y} {
	variable ${twm}::Vars
	variable Options

	catch { after cancel $Vars(afterid:release) }
	ttk::setCursor $frame.__header__ link
	set Vars(init:x) $x
	set Vars(init:y) $y
	set Vars(delta:x) [expr {$x - [winfo rootx $frame]}]
	set Vars(delta:y) [expr {$y - [winfo rooty $frame]}]
	set Vars(docking:markers) {}
	set Vars(docking:marker) {}
	set Vars(docking:arrow) ""
	set Vars(docking:arrows) {}
	set Vars(docking:container) {}
	set Vars(docking:recipient) ""
	set Vars(docking:position) ""
	set Vars(docking:outside) 0
	set Vars(docking:current) $frame
	set Vars(afterid:display) {}

	if {$Options(globalgrab:timeout) > 0} {
		set Vars(afterid:release) [after $Options(globalgrab:timeout) \
			[list [namespace current]::HeaderRelease $twm $frame 1]]
	}
	ttk::grabWindow $frame
}


proc HeaderMotion {twm frame x y} {
	if {[grab status $frame] eq "none"} { return }

	if {[catch { DoHeaderMotion $twm $frame $x $y } -> opts]} {
		puts stderr "Error in HeaderMotion"
		HeaderRelease $twm $frame
		return {*}$opts -rethrow 1 0
	}
}


proc DoHeaderMotion {twm frame x y} {
	if {![namespace exists [namespace current]::${twm}]} { return }

	variable ${twm}::Vars
	variable Options

	if {$Options(globalgrab:timeout) > 0} {
		catch { after cancel $Vars(afterid:release) }
		set Vars(afterid:release) [after $Options(globalgrab:timeout) \
			[list [namespace current]::HeaderRelease $twm $frame 1]]
	}

	if {[winfo toplevel $frame] eq $frame} {
		after idle [list [namespace current]::ShowDockingPoints $twm $frame $x $y]

		foreach entry $Vars(docking:markers) {
			lassign $entry canv w x0 y0 x1 y1
			if {$x0 <= $x && $x < $x1 && $y0 <= $y && $y < $y1} {
				if {[llength $Vars(docking:marker)]} {
					if {$Vars(docking:marker) eq $canv} { return }
					DockingMotion $twm $frame $w $Vars(docking:marker) leave $x $y
					set Vars(docking:marker) {}
				}
				DockingMotion $twm $frame $w $canv enter $x $y
				set Vars(docking:marker) $canv
				return
			}
			if {$Vars(docking:marker) eq $canv} {
				DockingMotion $twm $frame $w $canv leave $x $y
				set Vars(docking:marker) {}
			}
		}

		foreach entry $Vars(docking:arrows) {
			lassign $entry w size xl yl xr yr
			set lt $w.__left__; set rt $w.__right__
			if {$xl <= $x && $x <= [expr {$xl + $size}] && $yl <= $y && $y <= [expr {$yl + $size}]} {
				if {$Vars(docking:arrow) ne $lt} {
					set Vars(docking:arrow) $lt
					if {[$twm ismultiwindow $w]} {
						$w previous
					} else { ;# [$twm isnotebook $w]
						if {[set curr [$w index [$w select]]] == 0} { set curr [llength [$w tabs]] }
						$w select [expr {$curr - 1}]
					}
					HideDockingPoints $twm no
					ComputeDockingPoints $twm $frame
					return
				}
			} elseif {$Vars(docking:arrow) eq $lt} {
				set Vars(docking:arrow) ""
			}
			if {$xr <= $x && $x <= [expr {$xr + $size}] && $yr <= $y && $y <= [expr {$yr + $size}]} {
				if {$Vars(docking:arrow) ne $rt} {
					set Vars(docking:arrow) $rt
					if {[$twm ismultiwindow $w]} {
						$w next
					} else { ;# [$twm isnotebook $w]
						$w select [expr {([$w index [$w select]] + 1) % [llength [$w tabs]]}]
					}
					HideDockingPoints $twm no
					ComputeDockingPoints $twm $frame
					return
				}
			} elseif {$Vars(docking:arrow) eq $rt} {
				set Vars(docking:arrow) ""
			}
		}

		WithdrawHiliteFrame $twm
		wm geometry $frame +[expr {$x - $Vars(delta:x)}]+[expr {$y - $Vars(delta:y)}]
	} elseif {abs($x - $Vars(init:x)) >= 5 || abs($y - $Vars(init:y)) >= 5} {
		variable Frozen

		set Frozen $twm
		set child [lindex [pack slaves $frame] end]
		if {$Options(motion:busy)} {
			::scidb::tk::busy hold $child
			::scidb::tk::busy configure $child -cursor hand2
		}
		set Vars(docking:container) [lmap v [$twm container] \
			{expr {[$twm ismultiwindow $v] || [$twm isnotebook $v] ? $v : [continue]}}]
		bind $frame <Button1-Motion> {#}
		bind $frame <ButtonRelease-1> {#}
		set wd [winfo width $frame]
		set ht [winfo height $frame]
		set bd [$child cget -borderwidth]
		set x [expr {$x - $Vars(delta:x)}]
		$frame configure -width $wd -height $ht
		ttk::releaseGrab $frame
		$twm undock -temporary $frame
		$child configure -borderwidth $Vars(float:borderwidth)
		set bd [expr {$Vars(float:borderwidth) - $bd}]
		incr wd $bd; incr ht $bd
		wm geometry $frame ${wd}x${ht}+${x}+${y}
		wm overrideredirect $frame $Options(motion:overrideredirect)
		::scidb::tk::wm dialog $frame ;# wm attributes $frame -type dnd
		wm state $frame normal
		tkwait visibility $frame
		ttk::globalGrab $frame
		bind $frame <Button1-Motion> [bind $frame.__header__ <Button1-Motion>]
		bind $frame <ButtonRelease-1> [bind $frame.__header__ <ButtonRelease-1>]
		ComputeDockingPoints $twm $frame
		ComputeArrowPoints $twm $frame
	}
}


proc HeaderRelease {twm frame {timeout 0}} {
	set [namespace current]::Frozen ""
	if {![winfo exists $frame]} { return }
	if {[grab status $frame] eq "none"} { return }

	variable Options

	# Must be at start of this function (for safety).
	ttk::releaseGrab $frame

	if {$Options(motion:busy)} { ::scidb::tk::busy forget [lindex [pack slaves $frame] end] }

	bind $frame <Button1-Motion> {#}
	bind $frame <ButtonRelease-1> {#}
	ttk::setCursor $frame.__header__ {}

	if {![namespace exists [namespace current]::${twm}]} { return }
	variable ${twm}::Vars

	HideDockingPoints $twm

	if {![info exists Vars(docking:markers)]} {
		return ;# Oops, ButtonRelease event w/o ButtonPress event, Tk is sometimes strange.
	}

	set Vars(docking:current) ""
	catch { after cancel $Vars(afterid:release) }
	catch { after cancel $Vars(afterid:display) }

	foreach entry $Vars(docking:markers) {
		set w [lindex $entry 0]
		if {[winfo exists $w]} {
			destroy [winfo parent $w]
		}
		WithdrawHiliteFrame $twm
	}

	if {[winfo toplevel $frame] eq $frame} {
		if {$timeout} {
			set Vars(docking:recipient) ""
			set Vars(docking:position) ""
		}
		Dock $twm $frame
		if {$timeout} {
			tk_messageBox \
				-parent $twm \
				-type ok \
				-message [tr [namespace current]::mc::Timeout] \
				-detail [tr [namespace current]::mc::TimeoutDetail] \
				;
		}
	}

	event generate $twm <<TwmAfter>>
}


proc WithdrawHiliteFrame {twm} {
	set w $twm.__highlight__
	if {[winfo exists $w]} {
		wm withdraw $w
		catch { image delete [$w.c itemcget image -image] }
	}
}


proc ShowDockingPoints {twm frame x y} {
	if {![namespace exists [namespace current]::${twm}]} { return }
	if {![winfo exists $frame]} { return }
	variable ${twm}::Vars

	foreach entry $Vars(docking:panes) {
		lassign $entry pane x0 y0 x1 y1 size

		if {!$Vars(docking:outside) && !($x0 <= $x && $x < $x1 && $y0 <= $y && $y < $y1)} {
			HideDockingPoint $twm $pane
		} elseif {[info exists Vars(docking:hover:$pane)]} {
			ShowDockingPoint $twm $frame $pane $x $y $size
		}
	}

	foreach entry $Vars(docking:arrows) {
		lassign $entry pane size xl yl xr yr
		ShowArrows $twm $frame $pane $size $xl $yl $xr $yr
	}
}


proc ShowDockingPoint {twm frame w x y cs} { # cs is cross size
	variable ${twm}::Vars
	variable Options

	if {[grab status $frame] eq "none"} { return }
	if {[winfo exists $w.__m__]} { return }

	foreach point $Vars(docking:hover:$w) {
		lassign $point pos x0 y0

		set x0 [expr {$x0 + $Vars(docking:shift:x:$w)}]
		set y0 [expr {$y0 + $Vars(docking:shift:y:$w)}]
		array unset lines

		switch $pos {
			m {
				set wd    [expr {$cs + 4}]
				set ht    [expr {$cs + 4}]
				set ht_1  [expr {$ht - 1}]
				set wd_1  [expr {$wd - 1}]
				set ix    2
				set iy    2
				set color 1
				set lines(white) [list -1 0 0 0 -1 $ht_1 0 $ht_1 $wd_1 0 $wd 0 $ht_1 $wd_1 $ht_1 $wd]
				set lines(t) [list 0 0 $wd 0]
				set lines(b) [list 0 $ht_1 $wd $ht_1]
				set lines(l) [list 0 0 0 $ht]
				set lines(r) [list $wd_1 0 $wd_1 $ht]
			}
			l {
				set wd    [expr {$cs + 2}]
				set ht    [expr {$cs + 4}]
				set ht_1  [expr {$ht - 1}]
				set ix    2
				set iy    2
				set color 1
				set lines(white) [list 0 0 $wd 0 0 $ht_1 $wd $ht_1 0 0 0 $ht]
			}
			r {
				set wd    [expr {$cs + 2}]
				set ht    [expr {$cs + 4}]
				set ht_1  [expr {$ht - 1}]
				set wd_1  [expr {$wd - 1}]
				set ix    0
				set iy    2
				set color 1
				set lines(white) [list 0 0 $wd 0 0 $ht_1 $wd $ht_1 $wd_1 0 $wd_1 $ht]
			}
			t {
				set wd    [expr {$cs + 4}]
				set ht    [expr {$cs + 2}]
				set wd_1  [expr {$wd - 1}]
				set ix    2
				set iy    2
				set color 1
				set lines(white) [list 0 0 $wd 0 0 0 0 $ht $wd_1 0 $wd_1 $ht]
			}
			b {
				set wd    [expr {$cs + 4}]
				set ht    [expr {$cs + 2}]
				set ht_1  [expr {$ht - 1}]
				set wd_1  [expr {$wd - 1}]
				set ix    2
				set iy    0
				set color 1
				set lines(white) [list 0 $ht_1 $wd $ht_1 0 0 0 $ht $wd_1 0 $wd_1 $ht]
			}
			n {
				set wd    [expr {$cs + 2}]
				set wd_1  [expr {$cs + 1}]
				set ht    [expr {$cs + 2}]
				set ix    0
				set iy    2
				set color 2
				set lines(white) [list 0 0 $wd 0 $wd_1 0 $wd_1 $ht]
			}
			s {
				set wd    [expr {$cs + 2}]
				set ht    [expr {$cs + 2}]
				set ht_1  [expr {$cs + 1}]
				set ix    2
				set iy    0
				set color 2
				set lines(white) [list 0 0 0 $ht 0 $ht_1 $wd $ht_1]
			}
			e {
				set wd    [expr {$cs + 2}]
				set ht    [expr {$cs + 2}]
				set wd_1  [expr {$cs + 1}]
				set ht_1  [expr {$cs + 1}]
				set ix    0
				set iy    0
				set color 2
				set lines(white) [list 0 $ht_1 $wd_1 $ht_1 $wd_1 0 $wd_1 $ht_1]
			}
			w {
				set wd    [expr {$cs + 2}]
				set ht    [expr {$cs + 2}]
				set ix    2
				set iy    2
				set color 2
				set lines(white) [list 0 0 $wd 0 0 0 0 $ht]
			}
			L {
				set ht [expr {$cs + 4}]
				set c $w.__m__.__docking__
				$c create line 0 0 0 $ht -fill white
				continue
			}
			R {
				set ht [expr {$cs + 4}]
				set wd [expr {$cs + 3}]
				set c $w.__m__.__docking__
				$c create line $wd 0 $wd $ht -fill white
				continue
			}
			T {
				set wd [expr {$cs + 4}]
				set c $w.__m__.__docking__
				$c create line 0 0 $wd 0 -fill white
				continue
			}
			B {
				set ht [expr {$cs + 3}]
				set wd [expr {$cs + 3}]
				$c create line 0 $ht $wd $ht -fill white
				continue
			}
		}

		set tl [tk::toplevel $w.__${pos}__ -width $wd -height $ht -borderwidth 0]
		wm withdraw $tl
		set c [tk::canvas $tl.__docking__ -borderwidth 0 -width $wd -height $ht]
		pack $c
		$c create rectangle 0 0 $wd $ht -width 0 -fill $Options(cross:color:$color) -tag background
		if {$pos eq "m"} { set color black } else { set color white }
		foreach dir {t b l r} {
			if {[info exists lines($dir)]} {
				foreach {lx0 ly0 lx1 ly1} $lines($dir) {
					$c create line $lx0 $ly0 $lx1 $ly1 -fill black -tags [list border:$dir border:m]
				}
			}
		}
		foreach {lx0 ly0 lx1 ly1} $lines(white) { $c create line $lx0 $ly0 $lx1 $ly1 -fill white }
		$c create image $ix $iy -anchor nw -image [set icon::${cs}x${cs}::shape($pos)]
		wm transient $tl $twm
		wm overrideredirect $tl true
		wm attributes $tl -topmost true
		wm geometry $tl ${wd}x${ht}+${x0}+${y0}
		wm state $tl normal
		raise $tl $twm.__highlight__
		if {$Options(motion:overrideredirect)} { raise $tl $frame }

		if {$tl ni $Vars(docking:markers)} {
			lappend Vars(docking:markers) [list $c $w $x0 $y0 [expr {$x0 + $wd}] [expr {$y0 + $ht}]]
		}
	}
}


proc ShowArrows {twm frame w size xl yl xr yr} {
	variable Options

	foreach {dir tag} {l left r right} {
		if {[winfo exists $w.__${tag}__]} { return }
		set tl [tk::toplevel $w.__${tag}__ -width $size -height $size -borderwidth 0]
		wm withdraw $tl
		pack [set c [tk::canvas $tl.__tab__ -borderwidth 0 -width $size -height $size]]
		$c create rectangle 0 0 $size $size -width 0
		$c create image 0 0 -anchor nw -image [set icon::${size}x${size}::arrow($dir)] -tags image
		wm transient $tl $twm
		wm overrideredirect $tl true
		wm attributes $tl -topmost true
		wm geometry $tl ${size}x${size}+[set x$dir]+[set y$dir]
		wm state $tl normal
		raise $tl $twm.__highlight__
		if {$Options(motion:overrideredirect)} { raise $tl $frame }
	}
}


proc DockingMotion {twm frame w canv mode x y} {
	variable ${twm}::Vars
	variable Options

	if {![winfo exists $canv]} { return }

	switch $mode {
		enter {
			regexp {.*\.__([tbrlmnswe])__\.__docking__} $canv -> Vars(docking:position)
			$canv itemconfigure background -fill $Options(cross:active)
			$w.__m__.__docking__ itemconfigure border:$Vars(docking:position) -fill white
			catch { after cancel $Vars(afterid:display) }
			if {$Vars(docking:position) in {n s w e}} { set w [$twm selected $w] }
			set Vars(docking:recipient) $w
			set Vars(afterid:display) [after $Options(highlight:timeout) \
				[list [namespace current]::ShowHighlightRegion $twm $frame $w $canv]]
			raise [winfo toplevel $w]
			raise $frame
			if {$Options(motion:overrideredirect)} {
				foreach entry $Vars(docking:markers) {
					catch { raise [winfo toplevel [lindex $entry 0]] }
				}
				foreach entry $Vars(docking:arrows) {
					set w [lindex $entry 0]
					catch { raise $w.__left__ }
					catch { raise $w.__right__ }
				}
			}
		}

		leave {
			if {$Vars(docking:position) in {n s e w}} { set i 2 } else { set i 1 }
			$canv itemconfigure background -fill $Options(cross:color:$i)
			$w.__m__.__docking__ itemconfigure border:$Vars(docking:position) -fill black
			catch { after cancel $Vars(afterid:display) }
			set Vars(docking:recipient) ""
			set Vars(docking:position) ""
			wm geometry $frame +[expr {$x - $Vars(delta:x)}]+[expr {$y - $Vars(delta:y)}]
			set h $twm.__highlight__
			if {[winfo exists $h]} {
				wm withdraw $h
				catch { image delete [$h.c itemcget image -image] }
			}
		}
	}
}


proc ShowHighlightRegion {twm frame w canv} {
	if {![namespace exists [namespace current]::${twm}]} { return }

	variable ${twm}::Vars
	variable Options

	update idletasks

	set tl $twm.__highlight__
	if {[winfo exists $tl]} {
		wm withdraw $tl
		catch { image delete [$tl.c itemcget image -image] }
		update idletasks
	}

	set minSize $Options(highlight:minsize)
	set position $Vars(docking:position)

	if {$position in {n s w e}} {
		if {![$twm ispane $w]} { set w [lindex [pack slaves $w] end] }
		set dividend 3
		set minSize [expr {($minSize*2)/3}]
	} else {
		set dividend 2
	}

	set x   [winfo rootx $w]
	set y   [winfo rooty $w]
	set wd  [winfo width $w]
	set ht  [winfo height $w]
	set ht2 [expr {max(2,min($minSize,$ht/$dividend))}]
	set wd2 [expr {max(2,min($minSize,$wd/$dividend))}]

	set v $w
	if {$w in [pack slaves [winfo parent $v]]} { set v [winfo parent $w] }
	lassign [$twm neighbors $v] wL wR
	set orient [string index [$twm orientation $v] 0]

	if {$orient eq "h" && $position eq "l" && [string length $wL]} {
		set wdL  [winfo width $wL]
		set wd2L [expr {max(2,min($minSize,$wdL/$dividend))}]
		set wd2  [expr {min($wd2,$wd2L)}]
		set x    [expr {$x - $wd2/2}]
	} elseif {$orient eq "h" && $position eq "r" && [string length $wR]} {
		set wdR  [winfo width $wR]
		set wd2R [expr {max(2,min($minSize,$wdR/$dividend))}]
		set wd2  [expr {min($wd2,$wd2R)}]
		set x    [expr {$x + $wd2/2}]
	} elseif {$orient eq "v" && $position eq "t" && [string length $wL]} {
		set htL  [winfo height $wL]
		set ht2L [expr {max(2,min($minSize,$htL/$dividend))}]
		set ht2  [expr {min($ht2,$ht2L)}]
		set y    [expr {$y - $ht2/2}]
	} elseif {$orient eq "v" && $position eq "b" && [string length $wR]} {
		set htR  [winfo height $wR]
		set ht2R [expr {max(2,min($minSize,$htR/$dividend))}]
		set ht2  [expr {min($ht2,$ht2R)}]
		set y    [expr {$y + $ht2/2}]
	}

	set x2 [expr {$x + $wd - $wd2}]
	set y2 [expr {$y + $ht - $ht2}]

	switch $position {
		m     { set vars {} }
		t - n { set vars {ht} }
		l - w { set vars {wd} }
		b - s { set vars {ht y} }
		r - e { set vars {wd x} }
	}
	foreach var $vars { set $var [set ${var}2] }

	$tl.c configure -width $wd -height $ht
	set img [image create photo -width $wd -height $ht]
	::scidb::tk::x11 region $x $y $img
	::scidb::tk::image paintover $Options(highlight:color) $Options(highlight:opacity) $img
	::scidb::tk::image border $img \
		-width 1 \
		-type dark \
		-composite overlay \
		-bordercolor $Options(highlight:border) \
		;
	$tl.c itemconfigure image -image $img
	wm geometry $tl ${wd}x${ht}+${x}+${y}
	wm overrideredirect $tl true
	wm transient $tl $w
	wm state $tl normal
	if {$Options(motion:overrideredirect)} { raise $tl $frame }
	catch { raise $tl $w.__right__ }
	catch { raise $tl $w.__left__ }
	# due to a Tk bug (?) we have to raise a second time
	if {$Options(motion:overrideredirect)} { catch { raise $tl $w.__right__ } }
	after idle [list [namespace current]::HeaderMotion $twm $frame {*}[winfo pointerxy $twm]]
}


proc HideDockingPoints {twm {includesArrows yes}} {
	variable ${twm}::Vars

	foreach name [array names Vars docking:hover:*] {
		HideDockingPoint $twm [lindex [split $name :] 2]
	}
	if {$includesArrows && [info exists Vars(docking:arrows)]} {
		foreach entry $Vars(docking:arrows) {
			set w [lindex $entry 0]
			# NOTE: do not destroy immediately, because of a Tk bug
			# NOTE: destroy separately for safety reasons
			after idle [list catch [list destroy $w.__left__]]
			after idle [list catch [list destroy $w.__right__]]
		}
	}
}


proc HideDockingPoint {twm w} {
	foreach dir {l r t b m n s e w} {
		# NOTE: do not destroy immediately, because of a Tk bug
		# NOTE: destroy separately for safety reasons
		after idle [list catch [list destroy $w.__${dir}__]]
	}
}


proc SortX {lhs rhs} { return [expr {[lindex $lhs 1] - [lindex $rhs 1]}] }
proc SortY {lhs rhs} { return [expr {[lindex $lhs 3] - [lindex $rhs 3]}] }


proc ComputeDockingPoints {twm frame} {
	variable ${twm}::Vars

	update idletasks
	array unset Vars docking:hover:*
	array unset Vars docking:shift:x:*
	array unset Vars docking:shift:y:*
	set Vars(docking:panes) {}
	set Vars(docking:outside) $Vars(cross:showall)
	array set bounds { l 0 r 0 t 0 b 0 }

	foreach entry [$twm visible] { ComputePoints $twm $entry }

	# The following algorithm is separating overlapping crosses, no cross
	# should overlap another one.

	foreach entry $Vars(docking:panes) {
		lassign $entry w x0 y0 x1 y1

		set points $Vars(docking:hover:$w)
		set Vars(docking:shift:x:$w) 0
		set Vars(docking:shift:y:$w) 0
		set l [lindex $points 1 1]; set r [lindex $points 2 1]
		set t [lindex $points 3 2]; set b [lindex $points 4 2]
		incr r 36; incr b 36
		while {[info exists same($l:$t)]} {
			incr l; incr r; incr Vars(docking:shift:x:$w)
		}
		lappend rects [list $w $l $r $t $b]
		set same($l:$t) 1
	}

	if {![info exists rects]} { return }

	# Firstly separate horizontally.

	set rects [lsort -command [namespace current]::SortX $rects]
	set n [llength $rects]
	set lastr -100000
	set indices {}
	set index 0

	for {set i 0} {$i < $n} {incr i} {
		lassign [lindex $rects $i] w l r t b
		set repr($w) $index
		if {[info exists equal($l)]} {
			lappend equal($l) $i
		} else {
			set dist($index) [expr {$l - $lastr}]
			set move($index) 0
			set lastr $r
			set equal($l) $i
			lappend indices $i
			incr index
		}
	}

	set n [llength $indices]
	set odd 0

	for {set i 0} {$i < $n} {incr i} {
		if {$dist($i) < 0} {
			set shift(l) [expr {-($odd + $dist($i))/2}]
			set shift(r) [expr {-$dist($i) - $shift(l)}]
			if {$dist($i) % 2 == 1} { set odd [expr {1 - $odd}] }

			for {set j [expr {$i - 1}]} {$j >= 0 && $shift(l) > 0} {incr j -1} {
				set d $dist($j)
				set move($j) [expr {$move($j) - $shift(l)}]
				if {$j > 0} { set dist($j) [expr {max(0, $d - $shift(l))}] }
				set shift(l) [expr {$shift(l) - $d}]
			}

			set move($i) [expr {$move($i) + $shift(r)}]
			set dist($i) 0

			for {set j [expr {$i + 1}]} {$j < $n && $shift(r) > 0} {incr j} {
				set d [expr {min($shift(r), max(0, $dist($j)))}]
				set s [expr {$shift(r) - $d}]
				set dist($j) [expr {$dist($j) - $d}]
				set move($j) [expr {$move($j) + $s}]
				set shift(r) [expr {$shift(r) - $d}]
			}
		}
	}

	for {set i 0} {$i < $n} {incr i} {
		set index [lindex $indices $i]
		set l [lindex $rects $index 1]
		foreach k $equal($l) {
			set Vars(docking:shift:x:[lindex $rects $k 0]) $move($i)
		}
	}

	# Secondly separate vertically.

	array unset equal
	array unset move
	array unset dist

	set rects [lsort -command [namespace current]::SortY $rects]
	set n [llength $rects]
	set lastb -100000
	set indices {}
	set index 0

	for {set i 0} {$i < $n} {incr i} {
		lassign [lindex $rects $i] w l r t b
		set repr($w) $index
		if {[info exists equal($t)]} {
			lappend equal($t) $i
		} else {
			set dist($index) [expr {$t - $lastb}]
			set move($index) 0
			set lastb $b
			set equal($t) $i
			lappend indices $i
			incr index
		}
	}

	set n [llength $indices]
	set odd 0

	for {set i 0} {$i < $n} {incr i} {
		if {$dist($i) < 0} {
			set shift(t) [expr {-($odd + $dist($i))/2}]
			set shift(b) [expr {-$dist($i) - $shift(t)}]
			if {$dist($i) % 2 == 1} { set odd [expr {1 - $odd}] }

			for {set j [expr {$i - 1}]} {$j >= 0 && $shift(t) > 0} {incr j -1} {
				set d $dist($j)
				set move($j) [expr {$move($j) - $shift(t)}]
				if {$j > 0} { set dist($j) [expr {max(0, $d - $shift(t))}] }
				set shift(t) [expr {$shift(t) - $d}]
			}

			set move($i) [expr {$move($i) + $shift(b)}]
			set dist($i) 0

			for {set j [expr {$i + 1}]} {$j < $n && $shift(b) > 0} {incr j} {
				set d [expr {min($shift(b), max(0, $dist($j)))}]
				set s [expr {$shift(b) - $d}]
				set dist($j) [expr {$dist($j) - $d}]
				set move($j) [expr {$move($j) + $s}]
				set shift(b) [expr {$shift(b) - $d}]
			}
		}
	}

	for {set i 0} {$i < $n} {incr i} {
		set index [lindex $indices $i]
		set t [lindex $rects $index 3]
		foreach k $equal($t) {
			set Vars(docking:shift:y:[lindex $rects $k 0]) $move($i)
		}
	}

	# Test whether any cross is not completely inside the bounding region.

	foreach entry $Vars(docking:panes) {
		lassign $entry w l0 t0 r0 b0

		foreach point $Vars(docking:hover:$w) {
			lassign $point pos l1 t1

			incr l1 $Vars(docking:shift:x:$w)
			incr t1 $Vars(docking:shift:y:$w)
			set r1 [expr {$l1 + 34}]
			set b1 [expr {$t1 + 34}]

			if {!($l1 >= $l0 && $t1 >= $t0 && $r1 <= $r0 && $b1 <= $b0)} {
				set Vars(docking:outside) 1
			}
		}
	}
}


proc ComputePoints {twm entry} {
	variable ${twm}::Vars
	variable Options

	lassign $entry w dirs
	if {[info exists Vars(docking:hover:$w)]} { return }
	if {![winfo ismapped $w]} { return }

	set x  [winfo rootx $w]
	set y  [winfo rooty $w]
	set wd [winfo width $w]
	set ht [winfo height $w]

	set s $Options(cross:size)
	if {$wd < 5*$s && $ht < 5*$s} { set s 16 }

	set mx [expr {$x + $wd/2 - ($s + 4)/2}]
	set my [expr {$y + $ht/2 - ($s + 4)/2}]
	set tx $mx
	set ty [expr {$my - ($s + 2)}]
	set bx $mx
	set by [expr {$my + ($s + 4)}]
	set lx [expr {$mx - ($s + 2)}]
	set ly $my
	set rx [expr {$mx + ($s + 4)}]
	set ry $my

	set m [list m $mx $my]
	if {"l" in $dirs} { set l [list l $lx $ly] } else { set l [list L $mx $my] }
	if {"r" in $dirs} { set r [list r $rx $ry] } else { set r [list R $mx $my] }
	if {"t" in $dirs} { set t [list t $tx $ty] } else { set t [list T $mx $my] }
	if {"b" in $dirs} { set b [list b $bx $by] } else { set b [list B $mx $my] }
	lappend Vars(docking:hover:$w) $m $l $r $t $b
	if {"n" in $dirs} { lappend Vars(docking:hover:$w) [list n $rx $ty] }
	if {"s" in $dirs} { lappend Vars(docking:hover:$w) [list s $lx $by] }
	if {"e" in $dirs} { lappend Vars(docking:hover:$w) [list e $rx $by] }
	if {"w" in $dirs} { lappend Vars(docking:hover:$w) [list w $lx $ty] }

	lappend Vars(docking:panes) [list $w $x $y [expr {$x + $wd}] [expr {$y + $ht}] $s]
}


proc ComputeArrowPoints {twm frame} {
	variable ${twm}::Vars
	variable Options

	set size [expr {min(24, $Options(cross:size))}]
	set Vars(docking:arrows) {}

	foreach w $Vars(docking:container) {
		if {![winfo exists $w]} { continue }

		set x  [winfo rootx $w]
		set y  [winfo rooty $w]
		set wd [winfo width $w]

		if {[$twm isnotebook $w]} {
			set h [$twm nbhdrsize $w]
		} else { ;# if [$twm ismultiwindow $w]
			set h [$twm framehdrsize [$twm selected $w]]
		}

		set y [expr {max(0, $y + $h - $size)}]
		if {$size > $h} { set y [expr {max(0, $y + ($size - $h)/2)}] }
		set x0 [expr {$x + 1}]
		set x1 [expr {$x + $wd - $size - 2}]
		lappend Vars(docking:arrows) [list $w $size $x0 $y $x1 $y]
	}
}


proc Hide {twm toplevel} {
	if {[wm state $toplevel] eq "normal"} {
		wm state $toplevel withdraw
	}
}


proc Deiconify {twm toplevel width height x y force} {
	variable Options

	if {	[wm state $toplevel] eq "withdrawn"
		&& ($force || $Options(deiconify:force) || ![$twm get! $toplevel hide 0])} {
		after $Options(deiconify:timeout) \
			[list [namespace current]::DoDeiconify $twm $toplevel $width $height $x $y $force]
	}
}


proc DoDeiconify {twm toplevel width height x y force} {
	variable ${twm}::Vars

	set x [expr {$x + [winfo rootx $twm]}]
	set y [expr {$y + [winfo rooty $twm]}]
	incr x -4	;# magic value, this works under KDE (TODO: find the reason)
	incr y -18	;# magic value, this works under KDE (TODO: find the reason)
	if {[$twm get! $toplevel stayontop 0]} {
		wm transient $toplevel [winfo toplevel $twm]
		# NOTE: not every window manager is re-decorating the window.
		catch { wm attributes $toplevel -type dialog }
	}
	wm geometry $toplevel ${width}x${height}+${x}+${y}
	SetTitle $twm $toplevel [$twm get $toplevel name]
	wm state $toplevel normal
	if {$Vars(disable:close)} {
		set cmd {#}
	} else {
		set cmd [list [namespace current]::Dock $twm $toplevel]
	}
	wm protocol $toplevel WM_DELETE_WINDOW $cmd
}


proc Undock {twm frame} {
	variable ${twm}::Vars
	variable Options

	set x [winfo rootx $frame]
	set y [winfo rooty $frame]
	set child [lindex [pack slaves $frame] end]
	set wd [winfo width $child]
	set ht [winfo height $child]
	pack forget $frame.__header__
	$child configure -borderwidth 0
	$child configure -width $wd -height $ht
	set toplevel [$twm undock $frame]
	# ensure existence of these attributes
	$twm set! $toplevel stayontop [$twm get! $toplevel stayontop 0]
	$twm set! $toplevel hide [$twm get! $toplevel hide 0]
	if {[$twm get! $frame stayontop]} {
		wm transient $toplevel [winfo toplevel $twm]
		# NOTE: not every window manager is re-decorating the window.
		catch { wm attributes $toplevel -type dialog }
	}
	::update idletasks ;# is reducing flickering
	#wm geometry $toplevel ${wd}x${ht}+${x}+${y}
	wm geometry $toplevel +${x}+${y}
	SetTitle $twm $toplevel [$twm get $frame name]
	wm state $toplevel normal
	wm protocol $toplevel WM_DELETE_WINDOW [list [namespace current]::Dock $twm $toplevel]
	event generate $twm <<TwmUndocked>> -data $frame
}


proc Dock {twm toplevel} {
	variable ${twm}::Vars
	variable ${twm}::Update
	variable DirMap
	global errorInfo errorCode

	if {![winfo exists $twm]} { return }
	if {![winfo exists $toplevel]} { return }
	wm protocol $toplevel WM_DELETE_WINDOW {}

	set options {}
	set args {}
	set window ""

	if {[string length $Vars(docking:recipient)]} {
		lappend options $Vars(docking:recipient) $DirMap($Vars(docking:position))
		set args [list dock $Vars(docking:recipient)]
	}

	# NOTE: This procedure may be called via WM_DELETE_WINDOW callback, and in this
	# case the error handling of Tcl is not working (I don't know why), thus we have
	# to catch errors by hand.
	set errorInfo {}
	set frame [$twm dock $toplevel {*}$options]
	if {[string length $errorInfo]} {
		# Note that this cannot be reached if the error handling is working.
		# (Test emptiness with string length, not llength: the recorded error
		# text is arbitrary -- a message containing braces and colons, e.g. a
		# JSON body from a failing HTTP request, is not a valid list and
		# llength would fail here, masking the original error.)
		return -code 1 -errorcode $errorCode -errorinfo $errorInfo -rethrow 1 $errorInfo
	}

	$twm set $frame width 0 ;# otherwise ConfigureLabelBar may not work as expected

	set Vars(docking:recipient) ""
	set Vars(docking:position) ""

	if {[llength [set slaves [pack slaves $frame]]] > 0} {
		set bd 0
		if {[$twm isframe $frame] || [$twm ispane $frame]} { set bd $Vars(frame:borderwidth) }
		[lindex $slaves end] configure -borderwidth $bd
	}

	event generate $twm <<TwmDocked>> -data $frame
}


proc Close {twm {frame ""}} {
	::debuglog::log twm "$twm close $frame"
	destroy [expr {[string length $frame] ? $frame : $twm}]
}


proc DestroyTWM {twm} {
	::scidb::tk::twm close $twm
	after idle [list [namespace current]::DestroyNamespace $twm]
}


proc DestroyNamespace {twm} {
	if {[namespace exists $twm]} { namespace delete $twm }
}


proc Resizing {twm toplevel width height} {
	variable ${twm}::Vars

	if {[llength $Vars(cmd:resizing)]} {
		return [{*}$Vars(cmd:resizing) $twm $toplevel $width $height]
	}
	return [list $width $height]
}


proc Fullscreen {twm flag} {
	event generate $twm <<TwmFullscreen>> -data $flag
}


proc Geometry {twm toplevel width height minWidth minHeight maxWidth maxHeight expand} {
	if {$toplevel eq $twm} {
		event generate $twm <<TwmGeometry>> -data \
			[list $width $height $minWidth $minHeight $maxWidth $maxHeight $expand]
	} else {
		if {$minWidth || $minHeight} {
			set minWidth  [expr {max(1,$minWidth)}]
			set minHeight [expr {max(1,$minHeight)}]
		}
		if {$maxWidth || $maxHeight} {
			if {$maxWidth == 0} { set maxWidth [winfo screenwidth $twm] }
			if {$maxHeight == 0} { set maxHeight [winfo screenheight $twm] }
			set maxWidth  [expr {max(1,$maxWidth)}]
			set maxHeight [expr {max(1,$maxHeight)}]
		}
		if {$minWidth || $minHeight} {
			wm minsize $toplevel $minWidth $minHeight
		}
		if {$maxWidth || $maxHeight} {
			wm maxsize $toplevel $maxWidth $maxHeight
		}
		wm geometry $toplevel ${width}x${height}
		set resizeW [expr {$expand in {both x} && ($minWidth == 0 || $minWidth != $maxWidth)}]
		set resizeH [expr {$expand in {both y} && ($minHeight == 0 || $minHeight != $maxHeight)}]
		wm resizable $toplevel $resizeW $resizeH
	}
}


proc WorkArea {twm} {
	variable ${twm}::Vars
	if {[llength $Vars(cmd:workarea)]} { return [$Vars(cmd:workarea) $twm] }
	return [list [winfo screenwidth $twm] [winfo screenheight $twm]]
}


proc PaneConfigure {twm parent child opts} {
	$parent paneconfigure $child {*}$opts
}


proc ChildConfigure {twm parent child opts} {
	array set args $opts

	if {[info exists args(-width)]} {
		$child configure -width $args(-width)
	}
	if {[info exists args(-height)]} {
		$child configure -height $args(-height)
	}
	if {[info exists args(-minwidth)]} {
		grid columnconfigure $parent 1 -minsize $args(-minwidth)
	}
	if {[info exists args(-minheight)]} {
		grid rowconfigure $parent 1 -minsize $args(-minheight)
	}
}


proc Pack {twm parent child opts} {
	set class [winfo class $parent]

	switch -glob -- $class {
		*Panedwindow {
			array set args $opts
			set options {}
			set stretch always

			if {[info exists args(-after)]} {
				lappend options -after $args(-after)
			} elseif {[info exists args(-before)]} {
				lappend options -before $args(-before)
			}
			if {[info exists args(-sticky)]} {
				lappend options -sticky $args(-sticky)
			}
			if {[$parent cget -orient] eq "horizontal"} {
				if {[info exists args(-minwidth)]} { lappend options -minsize $args(-minwidth) }
				if {[info exists args(-maxwidth)]} { lappend options -maxsize $args(-maxwidth) }
				if {[info exists args(-width)]}    { lappend options -width $args(-width) }
				if {[info exists args(-expand)] && $args(-expand) eq "y"} { set stretch never }
			} else {
				if {[info exists args(-minheight)]} { lappend options -minsize $args(-minheight) }
				if {[info exists args(-maxheight)]} { lappend options -maxsize $args(-maxheight) }
				if {[info exists args(-height)]}    { lappend options -height $args(-height) }
				if {[info exists args(-expand)] && $args(-expand) eq "x"} { set stretch never }
			}

			$parent add $child -stretch $stretch {*}$options
		}

		*Notebook {
			array set args $opts
			set options {}

			if {[info exists args(-after)]} {
				set pos [$parent index $args(-after)]
				if {$pos == [$parent index end]} { set pos end }
			} elseif {[info exists args(-before)]} {
				set pos [$parent index $args(-before)]
			} else {
				set pos end
			}
			if {[info exists args(-sticky)]} {
				lappend options -sticky $args(-sticky)
			}

			set leader [$twm leader $child]
			set name [$twm get $leader name]
			if {[info exists $name]} {
				$parent insert $pos $child -text [set $name] {*}$options
				trace add variable $name write \
					[list [namespace current]::UpdateTab $twm $parent $child $name]
			} else {
				$parent insert $pos $child -text $name {*}$options
			}
		}

		*Multiwindow {
			array set args $opts
			set options {}

			if {[info exists args(-after)]} {
				lappend options -after $args(-after)
			} elseif {[info exists args(-before)]} {
				lappend options -before $args(-before)
			}
			if {[info exists args(-sticky)]} {
				lappend options -sticky $args(-sticky)
			}

			$parent add $child {*}$options

			if {[$twm get! $child flat 0]} {
				ToggleHeader $twm $child
			}
		}

		TwmMetaframe {
			pack $child -side top -fill both -expand yes -in $parent
		}

		TwmToplevel - TwmFrame {
			array set args $opts
			set options {}

			if {$class eq "TwmToplevel"} {
				lappend options -sticky nsew
			} elseif {[info exists args(-sticky)]} {
				lappend options -sticky $args(-sticky)
			}
			if {[info exists args(-width)]} {
				$child configure -width $args(-width)
			}
			if {[info exists args(-height)]} {
				$child configure -height $args(-height)
			}

			grid $child -column 1 -row 1 -in $parent {*}$options
			grid rowconfigure $parent 1 -weight 1
			grid columnconfigure $parent 1 -weight 1
			if {[info exists args(-minwidth)]} {
				grid columnconfigure $parent 1 -minsize $args(-minwidth)
			}
			if {[info exists args(-minheight)]} {
				grid rowconfigure $parent 1 -minsize $args(-minheight)
			}
		}
	}
}


proc UpdateTab {twm notebook pane nameVar args} {
	# args: name1 name2 op, appended by the variable trace
	set cmd [list [namespace current]::UpdateTab $twm $notebook $pane $nameVar]

	if {![winfo exists $pane] || ![winfo exists $notebook] || $pane ni [$notebook tabs]} {
		trace remove variable $nameVar write $cmd
		return
	}

	set leader [$twm leader $pane]
	set name [$twm get $leader name]

	if {$name ne $nameVar} {
		trace remove variable $nameVar write $cmd
	} else {
		$notebook tab $pane -text [set $name]
	}
}


proc Unpack {twm parent child} {
	if {[$twm iscontainer $parent]} {
		$parent forget $child
	} else {
		pack forget $child
	}
}


proc Select {twm parent frame} {
	if {$frame ni [$parent tabs]} {
		# This frame is contained in another container, as a result of an amalgamation.
		set container [$twm parent $frame]
		set child $container
		while {![$twm isroot $child]} {
			set parent [$twm parent $child]
			if {[$twm ismultiwindow $parent] || [$twm isnotebook $parent]} {
				if {$child ne [$parent select]} {
					$parent select $child
				}
				set metaframe $child
			}
			set child $parent
		}
		set parent $container
		UpdateHeader $twm $metaframe [$twm get $metaframe panes] $frame
	}
	$parent select $frame
}


proc QuerySelected {twm container} {
	return [$container select]
}


proc StayOnTop {twm toplevel flag} {
	$twm set! $toplevel stayontop $flag
	if {$flag} {
		set master [winfo toplevel $twm]
		wm transient $toplevel $master
		raise $toplevel $master
		# NOTE: not every window manager is re-decorating the window.
		catch { wm attributes $toplevel -type dialog }
	} else {
		wm transient $toplevel ""
	}
}


rename ::ttk::notebook::ActivateTab ::ttk::notebook::ActivateTab__

proc ::ttk::notebook::ActivateTab {w tab} {
	if {[$w cget -style] ne "twm.TNotebook"} {
		return [::ttk::notebook::ActivateTab__ $w $tab]
	}
	set oldtab [$w select]
	$w select $tab
	set newtab [$w select]
	if {$newtab eq $oldtab} { return }
	update idletasks
	if {[set f [ttk::focusFirst $newtab]] ne ""} { ttk::traverseTo $f }
}


namespace eval icon {
namespace eval 12x12 {

set maximise [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAYAAABWdVznAAABIElEQVR4nJ2SvUoDURCFv7n3phCC
	oMW2CdsrgTzAFVQ0jY3mBQRfwmYfaCvBxlS7YLugLxASK9vAVsneOxaadf0pxAMDM8MczvwJLTIz
	Ht/bfr+vdV0LwNav0jSS54H/QKbTqc3zPAxH516cm8TNegcRA4BqtK63jqF5XDw93GVZZsx8PjcA
	il6h8RJQQQVUAFXVI0VvAIqiMK6jpqFp8pfn2W23hcHh8TViL7ZxlyAiZtd77wC3AIbQLFZ2D0V+
	IwBQAgNg+WGDCJ/lXwmqEmrKsllC0yYPTlYiRn8QVLHGutPh6OwVtBcBg2xEzERjbG/g0jSNVVVh
	hJlg95XoVbECIAQxdhVUZwBJkrRKf0ZnnMx4X5gS8N8XUSYK76/xBhMKdYiPFAv+AAAAAElFTkSu
	QmCC
}]

set close [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABKUlEQVR4nJ2S
	P0/CUBTF76m0Rv0WjWPdOlRxIXFSQ2Ax0ckvYGoAcTGAJg4QCH8GXYwjA2HADiyYMGmMsKkrn8KQ
	CNrjYEuqgoNnevnl3HvPu++J/BBJTDv/EkmdpO4bfXOQi4iEfHhyXquP3scgmQBw5/FwOlcqa6rq
	ktwDMAj5lW+j8Vyr3TXhSoXkgYjIUbZUabW7Zmwz0p9MIAkAA5K2IlJtOB1zcWnhSoHCpnNr7EQ3
	+vnTpO158O1yJK2zwuXTynqcRjjGXOHimeRq0KPM3MIM+ZFIcu04W6o2nI6xvxt9UaDwun5jDF+H
	NZI2gPtgJD2VKfaWzS2mM8UeSYuk5bPUF9MnaxURmdfUj/h25DGfTSYAPHiNDgEpa6rq/vvhphX+
	+TU+ATnOwZHwhhzKAAAAAElFTkSuQmCC
}]

set undock [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABYElEQVR4nH2Q
	PUuCARSFz9U3/AhfTJqyJZS2QBsShaAgnENQg0AIgmgJIqIWQYRoKCpwCPwF9Qo119TQUgS1FWQN
	kYEgfhJqlKchFUvpGS/P4Z57Bf9A0gFgEIAdQF5ELpQekk5EGiSd0a1E8j79PGo2Gga8E+4iyfmu
	QAefVqvF9ph+sZfKFYAiywthm+6vlUqlhKQAGKrV6w2lTw9VteC9Wq0AyCitGi05FAp9kRzeiO0d
	HJ2euRcjgTuT0SClciUPIKcAgIg0Om4YAeDQ6XUf4YD/Orq2tAog+6PJU0tyknSQ9K3Hdq824/uX
	JGea4V8oJB3R7UTSqlps1VqdxyfnrrlZ/w2ABxF51TRNHwwG2W5C0hOIrGTHJgMcnw4yvnN4S9JH
	UjRN03dtAGDvN5kt5VIZqqrCbDIKgDcRIUn2CuS9HlcBQtZq9UKxWMk35z2R5tFTAGwAMgBy7W/0
	4BvyOaQwYrkgaQAAAABJRU5ErkJggg==
}]

set arrow(up) [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABdklEQVR4nG2S
	z0tUcRTFP/f7fc4wb147QdxNW6FFi6CpTSs3A4LggLiQNkbhJoIoaFEg4ZDQqnBXMRoDQtDeVRsL
	UbSIpEGo/oXJHqnv+06bNzWmZ3Mv957743AvDECSAZTLJcrl0onYKUhyha3tdffX97r765Jqg7lT
	nSXFn750243peTWm5/Xx89cVSfGJSQPk6oet3YX6+Ew6Vp8IY/WJUB+fSTc2dxckVftcA0xS9d37
	7Xv3Hz69myQV570PBmQhdwcHKYuPbi9du3KpZWa/HCDg/MvVNzcPj49ce7m1ci6Je0kS99rLi6uH
	x0f26vXbG0ANUFTI+D43O7XkcOnoyPBOmv5uAIyODL943nqwk5PHwA+ACMDMfkbePwkhkEsXhoYi
	XzTqXb188Zn3niwEAFxRwGSn4wUGRFmWk2U5QCSwyU7Hm9m/AkmsNZsq9IS4UnJxpeSAAGit2ZQk
	/q7UP0dhv925df1x3/8vdzacGc7O/og/U/OpXveejZcAAAAASUVORK5CYII=
}]

set arrow(down) [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABaElEQVR4nG2R
	v0tCARDHv9/3JOvZjz+hpgYHA6HMXJpahLYihSCChrDBJWoriCgIWhvabAkMmmppaqhM+mWEkrVH
	UBBUL0if34aepeItd9znvnfHHdDEDBIG2QzhLyuJJCWpI5PNzQDA4EDfNsn3KqtTSjJcHxibSr6O
	TSVfJQVqGQB4AIAkxtNpuhNN++u74nITAMfTaZKEpF+BJOzHYo67X9nj+WtYJqD9WMyR9D9BUsfJ
	+dWsAcMGcF0qlR1X0HmSuZ6roGJFQsEtku8eF3Rvp/bmb/MPXQe7WzuW1UoAeHp+mU4srk4G/L1v
	kVDwEMAdAVCS7/jscmFxaXO+vb3NME3TIYCyUzE+PmysLSc3hof610l+QhLdtXyZi5uV8Ejc9odH
	HX941AmPxO3T7M2KJF/19KgNJFm3+WIqOpFQdCKh3N39jiSrrrjJH3oKxcejQvHxSFJP4x8aRQQA
	r7cFXm9LXa5qP3XNtpIv7JwnAAAAAElFTkSuQmCC
}]

} ;# namespace 12x12

namespace eval 16x16 {

set arrow(l) [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABeUlEQVR4nK1T
	zytEURQ+5777ZsavDaWkRiL+AVnPyoJRUxRKKaUMvYUmsbuTBSK29v6HsdMoC2WtqEk008PDk5UZ
	3vM+mzcYvcaMfLvTPd+553zfOUwBAMBExOWQmRGUFwifXDMqkgEwMwNAyHXdISKClPKQmUvlt19/
	BiCv86aRmDbsydmUDWCYiEgpJYJ4wicJZiYAslC4SRor6+mzi8vW0tub5rquUEoJisWEUkoAEBVj
	loOGSJhM89aITy3Y/YNxjEwkb8y7+7lIOFRdA79A251l7yZT6bHz3HVjX0/Xy/Za6qCjoz1jWY8O
	M2tCCA+ep/V0Ry0iOvrUhYioWHzdMlY3l49PTtHS3ES6LqEJ8e55ntQ0jQGAmOC679wd7Xza39uY
	0XU9A0B8CVOXeQEjWA9PO/NL6fHz3FVdI1SImP+DiGUnhN+NzOdNY3Rq0e4dGEZi2nh2HCeulBIq
	m5WBNn4rErhIDpyqi/R/q/yzk1oRmFzPOX8ACgoE5R3gGKcAAAAASUVORK5CYII=
}]

set arrow(r) [image create photo -data {
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

set arrow(hl) [image create photo -width 16 -height 16]
set arrow(hr) [image create photo -width 16 -height 16]

set shape(t) [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACQElEQVR4nJ2T
	u2sUURTGvzNzZ8Z9TFgjE3ejlaKNpYWYwtpHIcbGYCnZJkgQBAWFdTEgNipYSARtLJLG1cZYWCgW
	pvY/EInuJrtJ1p3dzczcx7HIbl4sAb1wmnv5zvnu7/ABAJiZ8I+nryFmJiJiZs43m+FYfW0tbdsW
	DxJpbSgYHu7mcv43IqoxM4meuPDqTeXZ/LuFy3Eivf0me54bT1y58J6ZbwGoWQAQdrtn5iofxqu1
	upcksq2k7Mo9paTsJolsV6sr3lxl4Wqr1TpNRCwAYKXayEmlxZCfkc8f3/+cy/nrUilr52RHCNNs
	hgdv3p05HyfS2YiTMWb+RACw9LtWujFdelBbrvNQNq2k1JII6IMgAMyAELYTxYmQStOpk8car188
	nBTbWAFmBgDHcYSzKdvFvffOvN0WEACQROrHRhTBz2Qw+6Q8m/UPfI1jJWxsbkPDkOcJ1e5E5yan
	S8VUysLTR3deesL7KACAyUhjDIiAoWz6y9EjhflBG1haqhoCisyMVtj+fjg4FIuemy2/nSjxSqWS
	AGABML1rC4DpRMnWii3LcokIAntONpVKyuWyGuSgWJxKdjBhZt5soLUhAqC0kcurjRM/f9Wux3Fs
	72bg6eXVxnGtjRTCdrU2tAUxHwQdz3XV6nrdnbo9c8+2LWeQA62N/BO23dF8oPLBcKf/N/h+evHa
	+MXKaGEkFsJ2QUSDSgjbHS2MxBPjl976vr8I7AlTGHbP1ur1zH5hygdBx/fTi/0w9XH8d5z/AmSu
	NVnemNtNAAAAAElFTkSuQmCC
}]

set shape(b) [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACP0lEQVR4nKVT
	PW8TQRB9s7d755x9jkliE5MyEg0FdSgQdIgUiNCQGkVCikAUKAKBZIISKgSiQBQIGoqkSRSKKPyC
	QMMvQBQgnBg7MVbOX3u3d0Ph2OTDQkKMNNrVat/bnTfzAADMTPjH6GKImYmImJlHazX/XKVadS1L
	cD9QFMWUHRpqZjLeJhGVmJlkF/zm3eqL5bWNK7qtnb5oAATASTh6+urlNWa+Q0QlAQC+35xYXl2f
	2touO8ZEAZi5XxoTBVvbZWdpZf2a7/sTACABoFSpJHUQykEvFbx8+nBxZHjoq9bastApJUJMjuNE
	O7vV8dm7Cw90ENilSjXZI7AswdxZ1cnhkS9jY7mlfiUUi+VpyxJq/y73CA5GvdWyC4WCBCAAxPvH
	AkBcb7XsA4oQEe0TMHq6JRO2np+fN/1+MDNzU3f3cRwHzNwhIBZKCIHIRNirNy98LxaF1kYe1kCa
	vUbzPAMQREh7qbPM/J4A4MdWqXDjduHR9s8yD3pJ6jTs6Gx1mtHWmkMT05nT4ztvXz2e+aMBAUQE
	AGEYmpAIvboIADMgpaUAkl3Cnojtpv7WarXhJhzzfPH+h0zG+xUaIw6+r6SMazX/xK17C5cGBhLq
	2ZO51450NiQA5PIjNSUts7vbULNzCxcF4dgsE4CYEfv1hhobzZoBx94kIi0AwHPdT9NTk6v5fE7b
	tkpJpVx1JKVSrm2r1Kl8Tl+fmlxJp9OfmZkOmcn3mxOlSiX5NzONZrMNz3M/ds3UkeM/7PwbJqoh
	OiOUI4oAAAAASUVORK5CYII=
}]

set shape(l) [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACS0lEQVR4nJVT
	TWsTURQ9982bmXx0QixE0+pC6H9QunMpFZFGELNx2U1BKriRCjEgVFdauqrgQly0CE0FqVvFhf0F
	7kWInTTpV6adZGbee9dFMqW0RehdXR73nHfuvecCAJiZcMFIMcTMRETMzOX9IJjc63QLTkZeB4C4
	r36zMEprQ5YlWGtDpdHRsFj0fhKRz8wkU/D7j43FlfWv91Si3EwmAwDo9fswWgM0EEgA3IwbVaen
	PjPzHBH5AgCCIJxcbWxUfL/jxnGc+K02+61t1lozAAYzg5mV0vHfrW13ZW3jfhAEkwAgAcBvt/NR
	rOTISO5w6fXzb3PzC7cBst+9fbE8ks/86PUiO5vNqc7O7sTs05fzURw7fns3f0xgWYJBABFEsZjf
	U0ontrTtQi73/drVsdV0cM3mdtWyhM0pJiU4GXGsrDTv9ZRTq9XEsE6FYc8+XS9OP5AYMA+Ugev1
	ugFg6vW6SX/9L8FF4wwBG3NsKq1BwxZErVYTWpszhjszA8eROs2zWRkPW4gBYGZmNjmXQGtDYIAZ
	Zn//6JK0hM3M6IbhrT/NpkjX2NrpTGhtEiktJ1VDANDtHk1XHj3+tNVqy4KXT5TSkgG4roOTmrU2
	yUFw6IyXS6rx4c2DQqGwLgDA83KbDytTjfGxK33btu1EaUqUJiEEgWjgECKS0nLGxy5H1cqdNc/z
	NoFTxxSG4Y3DsH/zyfyrGYCwuPBs+aAb/GI2UghhtDZULpWOPC+3mR4TAYPTJCIe5jKKorsA4Lru
	FyJS560vxfwDqo0z4QIyd9AAAAAASUVORK5CYII=
}]

set shape(r) [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACTUlEQVR4nJVT
	S2sTURT+zr13Mskkk7a29rlx484/UBcFtxYRI4hFcNdWEKRuRFGIAbsQhOrCjeBCXLQIjQUp+g+K
	/gURRGo76dQaMuYxM/fOcZGHJXHTs7lwv/N95w0AYGbCCa3LIWYmImJmnqxWg/P+0ZEjpWBjEpJS
	MCVCpdLqDABELf19ZCxfG3bdHSLymJlUl/z6bfnFxtbHy2ErtPlfGAgpkUmnAQCtVguWpcKFwvwW
	M68QkScAIAgasxvl7cLe/oGttYnAzGBmAGyMYa9ywF7F5yiK4n3v0F7f3L4aBMEsACgA8Hw/G0ax
	GnJz0ctnj1bHRk99azYbKpOx4z/11tzSyuNlgOPnqw8+3b735EIYxTnPP8r2BKQUzO3Xmhgd+zoz
	M77erWJ3dz8h0HKsdTw8nP1NBAFqc3oCx63RaFrFYlF0MN1s6lQXiyIt+/1F/4eUgkulUgIgKZVK
	iZTo9ZSE4H7/AYGT2oCAMQl1ShDFYlEYg96ScZIMLNxADxwnE3dKiABgcfFW1MVSKWX+K2BMQgRA
	mySu/Do8++Ond6M7xlq9McfMUFJY1Wp9hBkJuM0B0E6vVqtfKdy8826v4qshNxdJKaxe2gDCMAIB
	UErqWlC3piZP6/KbtWv5fP69AADXdXauFy6Wp6fGQ6VkCkQEEIGIhBAUa0OxNqQsy5qemmgtFOY3
	XdfdAfqOKQgas57vZ6UUnCSJIBLazWXP3X34dAlgrK3ef5Vz0p8dx/nSPSYC2qdJRAMz7mAqDMNL
	AGDb9gci0sc5fwFpwytKhhKeBQAAAABJRU5ErkJggg==
}]

set shape(m) [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACkklEQVR4nKVT
	TUwTYRCd2e3+0i20UOhWEu8ePNOriTFUUSjEtB6MidF4M0qIHkzExIMhqOGCB1EPGqlGCkFRPOgR
	9Gziz1EDbGv5Eb7tdn+6HQ9SLKYmJs7xJfNm3pt5AABARAgN6l9wJCJERCKiGGNWYqVQDMY7Iqam
	ae8Q0SAinTGrqw5fRMR8jSBQa773MDeWnXl1zLYdUVFkt+/wgWdEdOvOg+zF6RdvB8q2Lcqy5Gb6
	umeI6MI2OXIAAIyxRDY3lzKMouT7FcvIr0rZ3HzPlmmezk69PGoUViXPq9iGUZQeT82lmGUlago4
	AIAlY1WzXY8PaU3WpfNnH4WCatlzPeHrt+WwV/GFYJNs37g6eFcLqpbjekKhsBoEABgeHgYOAGBv
	Z3xLlqQqK1nqyNjESWaVFVkRK5FwuFStEgICtEdbywAAiAg8x1HNAw4AQFWl96meg9nWSPMGEVFr
	uHnjeF9yMtLS/AkAAkhIruPwjS4SICJu25DRTH9ya2k5H9qjt5vhltDtDx+/7Fckkbcdl7Bu6i4C
	RKwSkT5+f3Lo6czrbteriJIouuneQ9ypE72fy47rcxw2/IcdCYxZXdPP36TX1jfD5FeFtY3N8JPp
	+XRx/cc+IKoQEFK12pCEAwDIF4tNjuehpirW6PWh8aAi2Y7rBVjJkjieIyAAUZL8vxLU6rdIJAAA
	8v2dqd+LawoAABGBX7cNBwAQi0ZLoiD4zLTUwSsj51jJUgIC73XqsU2B5z2zZMuXr908w0xLlUXB
	6+hoMwHq/kDT1MVMKpnT9agjCoIUj0WdTH9yNhQKTqQHkrN6rM0RhYAc19vtzMCRKU1VF2pL/xEm
	llgprO8Kza8wsa46fAERC7uM+J84/wTXaWFAeTb3vwAAAABJRU5ErkJggg==
}]

foreach {dir pt} {t n b s l w r e} {
	set shape($pt) [image create photo -width 16 -height 16]
	::scidb::tk::image copy $shape($dir) $shape($pt)
	::scidb::tk::image recolor black $shape($pt)
}

} ;# namespace 16x16

namespace eval 24x24 {

set arrow(l) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB+klEQVR4nNVV
	zWvTcBj+vUmWxK/LBGFqa2d14sGTsP9B28IOg1EYCIKwtstBKszhIcl0fqCeJnr03vs8exA8eJRS
	cKIlIWk7TfHk3PLxeGlc2m1al4j6nF/e53mf93l/P8b+d9AwRQAoUgsiQmIKes3/DMLmAEQAOdd1
	cwDkRIgjzYWmYSlTs4ozc7XquC4uM8aYqqrcMH12LQJARAQAgmnaJWVhWXvbeD+6ubVFghBLd79y
	w7CUQrHsTEzmUSiWnaZhKQAkADSsRX1FALiect407VJlYVl798EcPXs69WXl/qKeSZ98SkRurVbj
	6vX6jiRpmsbYXikLFR2QJWZZLSVfLDvnJvPIzZTs9vr6NVkSf9+OcILIuEc7nz4/nruuTzfWmgcn
	sqe+PlyqvhgbO7basjueKImc7/vgGd8vjmNAEPDZ8XSHMfaSiL6FewwJeCLyNzY2H83fvFd99foN
	jhw+xEZGBPAc5wdBIPA8TwB2PzBi8DyfxtMnus+f3Lkiy/KqqqqcruvBUFGLgz0sWppurH1MxKLt
	osiSjcElt2MuOUKyHVO7PVe5cVv/EdO7i3omEyOmg5MAEAyrNV8oVmId2q9JetecvXgJU7NKF0jg
	LerZRETkpVLHn608uKVdOH+mK4kiPM/bt/CfTZL8cz1Isl/8/S/zn8d3RHJvJN8d0h4AAAAASUVO
	RK5CYII=
}]

set arrow(r) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACGklEQVR4nNVV
	TW8SURS9d2aAwY9FmxgqKdYvtIa4MunaxFULTbrCYKoLw0IaIKYxNobGeRtTP9KVBN36A/w1LrTp
	B2VgipkI3WkZmDkurAotCkMxqSd5u/feOee+c+8j+t/BbjYD4LYzYGYMX9JhwuFdBEBtNptRAFEA
	3qGRaJomERGhiZn4/cX63Hymtq0bGQBKLxLJFZNCZFlN+vBxYzSz9EyUyzspAAoz40hOAPD+8um6
	kZ69k/5yZSqGWGKhtrVdzgLw/MkJH7yIiFgIcYgkEolwPB53AHhKlZ0H2aUVsbZZGglfCO3mn+fE
	xESwwMw2AGZmZ2A3RESqz0OfTTMZTaSMq1MxRG+n6uVyNetX1Xahvx3sswKASkQ3N4t6gCXJZqfT
	oU1EskxsNSxnPBiQK1Uz9lhbnV7bKJ2cDJ//+nb16fuxwJlFIqoRETHzjxQIIZiI0Go0bt1LL78r
	6saoosggdG9EZmbbtiFJUstxIJ0+dQKf1ov+5ZXC3fzLJ6bf53sEQCYi212KuqBXK7sskU2yLLPV
	sJyzgYBSNc1orxINpFr1eck0a8lY+yMb3R9Z6bDbZ0x1vZJKPtS09a3KSPjiud38q5wYD44Vvu3t
	8UAx7Wg0o+qq0frCr1kEzMzNZ+qXbkxjNrFQ0/uYR+5S1CLyej10/drl+usXOREKBd8wc+tnSAZS
	367un43rXsR/w/H+Mo8FvgOLfGMGHBiEWgAAAABJRU5ErkJggg==
}]

set arrow(hl) [image create photo -width 24 -height 24]
set arrow(hr) [image create photo -width 24 -height 24]

set shape(t) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADIElEQVR4nLVW
	TWhUVxT+zr33zcx7M8lAaLTSbtxocJBooRv/EEoRKm66aBdduKnRboox4iaS9yZdNaALV82iK0FK
	oYJIEIraIoHubCAOkYhYNGDsaFAz837mzr2ni5kMUWNmRptvdXn33u+c8333nvsIr4GZRRAAQPD6
	VBsECAKAiGyXG98PtHpMAFvm7Yvl8q4oTFLdEOU8L+nv75shovkmLwOAAgBmJiUlV8Pwy5HRibHb
	d+YGtK479GoCbwUD7DiO/mTnwN04jsc9z7tsjCEiYsXMgogsM28bHp0Yu3ZjejDnZeC5GcvMHWUv
	iPByeTk9dX16EMCYMeYOEc0zs1ANQ4HF8tLumdm5HVnPNd8f/+anLz7b/9fTpReO44h1o2ht6YO+
	vJ66fmvPhclLx2/Pzu1YLJd3A5gPAkCtnJZKZTmltVZZN42vjxy6mclmLneUfhNxNY5+vvjbd7qm
	RaUSNv0LGh4AAJFQUkoYY3D/4cKhfx498pKkrqRYvwJjLaXTqn7/4cJ+ay2klCASLV5VKBQIANxU
	eqvrurT45F8+MRIMMeNYNxUQgSrVkD/cvIncVHorABQKBRLdkLwLVKlUYgCo1fSDKIqQy2Yxeb44
	mevJ3EqSupJoIxEaElWW4wPHTvpDURShVtMPAKBUKnFLK0usrbVMBPTmvD8//mjLL91kurDw2BJh
	yFrLlli3KlgZrL5UUVRP+b4vAAgA7XqLAGCjqN66+au51Fo7pAQXi0Xr+z6KxeK6AVbWHD367ZpS
	brjJG3+K1vpojKUVD3zfb8chfN+HMXbNxtgKYGxjARGhv78vaWrfyeNhAWB4+HRCRGDmFlczQACg
	iHw+Fyul6i8robj6+x/7nj17Lp4uvXAc2abZmUazu3Lt5t5qGHNvb9bkc7m4MRuAVrfrkdGJX6du
	TA9mvTSyrmuZuaP3gIi4GkWiGiY4/Pm+mXM/nPmKiO4xs1BNcpJSzodhOA7C2N+zdwe01k4n5ABg
	mZHv6UkO7v107sezp8allPeYmYjoFWMIADPztnJ5aVclDNOdBgDe/mRuON7Q+P/+bfkPwKp6WvXK
	K/oAAAAASUVORK5CYII=
}]

set shape(b) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADEklEQVR4nLVW
	PWjUYBh+3i/5Lk3u2opYdRBBBC0e0iq4+EdBBFFcHBxcXKxVXGwFl0qTq5MFcVScHByqgoPgH9hF
	i6MW9ajUQRCEauSw7V1yueTL65C7s+rZu6J9ppAveZ4n7/u9zxfCb2Bm4TgA4Py+1AQOHAcgoniZ
	L/4baPE1ARwzb5113V7fC1LLIcpYVtDVtXqKiGaqvAwAOgAwM+maxiXPO3ZheGzk1bvp7jCMJP1q
	4K9ggKWU4c7t3e/L5fKoZVn3lVJERKwzsyCimJm3DA6PjTyemOzJWAYs04yZuSX3ggjzCwvGw2eT
	PQBGlFLviGiGmYWeNBSYnXV3TL2d3pa2THV+4MT1wwf7Xn4rzEmpiSVVQhXTmtWd4aOJ57uvXb99
	9tWb6W2uW+gFMOM4gF7bLUXfN6Io0tOmgaOHDkyuWtV+pyX7VXz/vhDfvHXvXBRFYq5YbEvuOkkP
	AEATiVNmhusWDNu2BQABoNm2EwBi1y0YtZLWuAD8FFgMTROcy+Vi27aRy+WWFKg9c/LkqYalFE3c
	/TNWXKBhiZQC1Xpg23YzDmHbNpRqPDN1Aa5OHgCYpl6p1r6VXIkBoL//TKURV11AMEkhBCkV83zR
	6/v0+bMIgkjXsPQcKMRkGHo0v+DtZwY0TZBgknWBbDZLAJBKyU2maWL2y1cMDNkDzDjdgvs6iEDF
	UonXr1uLVEpuAoBsNksr3+R8Ps8A4FeCj77vcyZt4cZV52Y6Y7wIgkhfPDSNoOKkRKVisO/0oN3v
	+z77leAjAOTzef7ZZI4jpRSEENi8ccPTtnTb/eU4LZfKnhCiXykF5jiqf0GSRTlkMlZFShnNFz0x
	/uDJAdctmN8Kc1LKJmEXJmE3/uDJ7pJX5o6OtOrMtAfJqgNaHNcXhsfuPpyY7ElbBtJJXLd0HhAR
	l3xflLwARw7unbp6+eJxIvrAzEKvkpOmaTOe542CMPL67fvuMAxlc+oEMTM629uDvj27pq9cGhrV
	NO0DMxMRxb8cmQCYmbe4bqG36HlGqwLA34/MFccfNf7fvy0/AP2ofie5bVMkAAAAAElFTkSuQmCC
}]

set shape(l) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAC8ElEQVR4nO1W
	TUhUURT+zr1vZnxvRodE+6FWLUySsII2FRREENTKRZuWYSFBYEYbw/eerRKidoWrFi3CIIgoNxkh
	tjWpxNBFISpTI2bOm/fm5917WoxjM466yXZ9cOG+ez6+8+455557CevAzMJxAMABALS1tREATE5O
	8npuNRw4DkBEemveNoMq5wSwZj6QSi8d9rxM1JCGjEYj+wEgyOW/MusQIJJC1OwmYVn55ubGCSKa
	XtVlADAAgJnJkJKzvt/R0zvQNz451VoshBEphDBNEwAQBAG01huGiQGORCLFo4dav+RyuX7Lsp4r
	pYiI2GBmQUSamVu6ewf6hkfG2hNWHSyzTiulOfX9R+kPE/Gq7VZCEGElk4m9ejPWDqBPKfWZiKaZ
	WRilhAKpVPrIxKepg3HLVNevXnrUcf7s6Le5hTNdPW4nAAw+cAYT8brRfD40JP6EqKg0NTUmi69H
	Ro/ff/ika/zj1MF0eukwgGnHAYxytXhBEAvD0IibMVw4d+p9fb01NDs/b4C5EwAaLOvdvr17nm6W
	zOXljB58/OxaGIbil+fVlVadUg4AoJw4Zsbi4s+YbdsiCMJo2R4EYdS2bQFAAKgsRQFAp9NLMWau
	0iobayCFYNd1tRRYI0oJdl1XA9Cu666N8reUtZW1qYPtxH8H/x38PYyNFpXWZNu2UPpP+1EKVD5o
	tm1X0oVt21BKb9iq1hwoXSIQEZqaduRd19WXr1wplO2maRTKB2udhgaA7u6beSICM69prTpwALhI
	JhM5wzDCFc8XL4ffncxkfPVtbuEUqMRd8f3Ts/PzYrNm92L47Ymsn+OGhrhKJhK5ktUBVbbrnt6B
	oVcjY+1xKwbLNDVrJi+bBbB1uyYizgaByPp5nD97cuLenVsXiWiGmYWxKk5Symnf9/tB6Pvw+Utr
	oVCMSClo966dALa+cDQzkvX1+dMnjk3dvX2jX0o5w8xERFWJIQDMzC2pdPqI5/nbcmX+c9SEdbuf
	Lb8BAjyIVR1MwuwAAAAASUVORK5CYII=
}]

set shape(r) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAC+klEQVR4nO1W
	PWgUQRT+3sxe1r2fnASiIhbaaEiQJIWVIQZEEMXGwsLeqI0YAzaR7G6sDKSxERQrQTAQGxUhGEQI
	lhrUEIlgJRjdJOZnb/d+duZZbPa8nGcaY+cHC7tv33xvZt6b7w2hDswsHAcAnPpfm9DR0UEAMDs7
	y7HFgeMARKS3HLjdoNp3AlgzH1rwvK4wKDXVOyutCWAmEoa1wzwAAOVy5XOkIpXN5sp7WlveEtH8
	Bi8DgAEAzEyGlFwIgrODQ6PDbz7MtVUqUYo2T6AKIQRZlgUACMMQSmvdlEpVug+3fSwWiyPpdPqx
	UoqIiA1mFkSkmfngwNDo8POp6c5s2kTasjQzN1y20poXvn0HAGQzGQhBWF33zWcvpjsBDCulPhDR
	PDMLI04osLDgdc+8n2vPpC119eL5O6dO9L1eXF5NpaSoRlHQZJpG5BeKvf1XnX4AuDNm39u/b+/U
	xNPJY7fvPrz45t1cu+ctdwGYdxzASKrFD0MziiIjY5k4c/L49M6duUd/StyXL181mPsBIN9svcrl
	0uNLKyvy/oOJy1EUiVXf3xF7OnEOAECKeKbMDM9bNm3bFgAEgNqyEwB0GEbVAgjDqMm2bbG4+MNM
	tjThSgb8BikFu66rAWjXdatP8i0lqgRSgF3X1bWktWgYYDvxP8D/AH8Po5FRKU3JQbNte9OEbNuG
	Ur9EUGmQbdsiVtotAiQORITW1pZScrDq/DUAXLhwqZwYLMsou66rrwwMlIgIzIzaYBta5CKfzxYN
	w4jW/EA8mXzZs7S0Iv4kdmuFoBcUc6yuhcfW14No4ulkTyEocnNzRuWz2WI8wgHVyvXg0Oj4s6np
	zkzaRCaW64bLZgC+XwBQlWsuhKEoBCWcPtEzM3bz+jki+sTMwtggJynlfBAEIyAMv33/sa1SqaQa
	kQOAFIL27N4FoNpwON+cK/UdPTJ368a1ESnlJ2YmItqUGALAzHzQ85a7/CAw64m3apn5fK7U2tIy
	U98y/zl+2+Ptvrb8BILmjUhsKb2RAAAAAElFTkSuQmCC
}]

set shape(m) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAEC0lEQVR4nLWW
	T2gcZRjGn/ebmezu7L8kNIjguSaRNYkokhpKg6YXEaUHkR7sRcQoYmOCl4Ts7IoHE4rQS6CiVGzx
	byNRQyE27aEr6iWJSciGVCHQ0qYM7Cb7Z2bXmW9eD9lNN3YxadD39DH8eN/he57nnSH8o5hZGAYA
	GJUnBgwDICLvINz/XlR7JoA95kc3TLPTtsoNABDS9XJLS/MCEa3V8Mx7cwwAaoUmVVG4aFknBofH
	RueW062u42oAoGqa80SsdbVUKiV1PTAJAFbZ3oPTJ6WURESsMrMgIo+ZDw8Mj41enk11BHU/9ICf
	ASCXz/umr6Q6IERcSm8OAAZHxo3p2VQsqPugBwLeLg4YlVIuE9EaMwt1WyhgY8PsWlhKtwd1v/fO
	6ycn+np7fgWAmas/d5/9+OIb87+vPJbN5mJSSppfSrcH9YAc6D850dd79BcA+OlaqvujiQv9c4vp
	dtPMdAJYMwxArbogVyz4HcdRQ7ofr77y0iwRfVe5vuKnFy/1O44j8nkroDQo7LiuEgz4+IXjz6Ya
	G8NfAcDmZl6eO//NW67riq1Cwb/92kZ1QAJNTVG7QdPcrUJR+ezLqedub5hBADj/xVR3oVjiSCTk
	HToUsc3Mlo+IwJ4H08z44vG4AADTzPiYGQCgCMFV56iGASQSQEtz80JXrG1lejbVcfbchTc/+fxS
	PwAUbZuKdhnHep5c1HV9Ib9++0jVIooiOJFIeABw6tRrO01rS60ITIqirFmWlSQh4vNLK21OxR2N
	kbDT2/N0+oPht5NC0M21P282eJ5Xt1ndAQBARAyA/H7/JDPPZbO5mGVZfgDQdb3U1BRZEkKsM4MU
	sd/W21UPJwlJdZ4fqHYHrWydGBwZNxaW063VK9I01el6vG21UCgkQ6Hgt/IBN029oMVCuh+BStA2
	c3ntx5nrMfZ41PP4t+WVP/4SQtB+dagTtIA8XS9AS6vtlmV1hiNBuW+FURO0gm37XNdVgwEf6gVI
	ui5lszl/g6IweP8j1OpB0zQPAJgZt+7cDcTjcRUAbt25G2BmEBE0TfOkvGcAKT2qBk1Kr64xdgY4
	jiMAgIjwyMMP2YlEwgWAgYEhm4jANQxXuJaW5nI1aAMDQ2UiAjNDeveG7ayKaDRUUlXVzRUs8cPM
	tZ4NM6MAwNTlq0eKVomjkZCnh/WSlJI0VZVb+SLqcZFIUEZDodJ2ewNU66LB4bGvp2dTHbVr2LJt
	UbTKeP740cUzyaEXAWBwZPz76SvXY3W5vp6FM++/9zIR3WBmcd+qAGF0fmm11XEcDQCi4XD52DNP
	pT8cPZ1UhFgHAZZlGwDX50beTSqKcoOZiYh2CUPbGvNh08x0FizLB/zrJ3Mv7kHcfPC6z1r/9W/L
	3zHkff6hFmKAAAAAAElFTkSuQmCC
}]

foreach {dir pt} {t n b s l w r e} {
	set shape($pt) [image create photo -width 24 -height 24]
	::scidb::tk::image copy $shape($dir) $shape($pt)
	::scidb::tk::image recolor black $shape($pt)
}

} ;# namespace 24x24

namespace eval 32x32 {

set shape(t) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADjUlEQVR4nO1X
	TWhcVRT+zn3nzUwm7SJNQyh5ZjJjCKldCdIuFETcuHRhlkZLKXRRIbpxYdyIXQRXUheWEoKtu4i4
	qgpuBLNIQauUQs3PvLz5aS0hURA7P+++e1zMm/hmJtPmdaZ202/57j3n+965536cCzxhULcFEVF9
	JSIyB9ooIl1F9aphv9wtH0SEiEgUEQJjMgCyWutEL6zMXAeQV0oVRGSPY2+9jRwiMrBVKL/13vzC
	GdcrT2gdcPeDeggEYLZ0LuO4W4Xy4rhz7AoRVaMiOLqfmcUt3J195/0Ln7jenUMCgcj+uQ8KImBt
	s3D0901v+uLCPJitS4hUnoFGwxGREZFn3v1g4azr3Tk0mE7pE9OTa6MjR3Z0EFgqUraDwIgQW1Zw
	b3t3+NbtjSnXKx++eOnKWd/X14io2OTktrhJ1ytlRUROTE+uLX328dsAXAAKQNxaEAADIHf6/PzS
	6s83j+e9UhbAswCKLRVoolqtJgJjlAA0OjK0A2CdiP6KSdwCEdGjI0M7AlBgjKpWq8noensPGEjj
	T0lZCoBKJmyQUpCYzUBEEGMAQIW5AIEwc4sftB+BbTMnTRCgUqlkVq7f+HDxy6//SSZsJYjXAwSh
	Wt03K9dvDFYqlYwJAtjMSQB2h4Dl5WUCAK21Y7GVTtgsP63+6qys/jZHPdqSCCAQJGwWi6201tqJ
	cvbVbh8FDAAzMzMNU2AuBTq4X/d1+tWXT5VmXn/tqy2v3NMRTGTGBpe/+e6Nb39YcQId3GfmUgtn
	W5zva11TlpUeHBjYevHk8x+98tLJP1XDIWP9GRHBiKBe94euff/jC8qyHF/rGgC/owItwqnhUrV6
	nQCw72tC404/ig8IAA5zIczd0lXtAvaglEKYQEQEFNMJIzES5tqfJ07Sx4GnAp4K6HoLQjTnOIrr
	A5GYB5p5iwCt9d5mSykDwG9epbjszRgR8VUjVwdHh4BUKlW3lDIEyB/bu8MApkQkj8ZRHWys/g/N
	mNy97d1hAsRSVpBKpWpdBQDYyGYcdz1fPHLr9sbU6fPzS/0ayYiIchNjLoDNDgHhPEi2zcW1zeLl
	9XxhyvXKh1d/uflcP4ZSAiGXGft77tzsZdvmYjgVGyDSIJGxPFUo3Z399POrZ/JeKduPsTybcdy5
	c28ujjvHviCiWtTa932YEBGMMeMAco/7YdIpOrx2vZB2wcOfZm1Cnszj9P/Gv92NzrJTMeAyAAAA
	AElFTkSuQmCC
}]

set shape(b) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADgElEQVR4nO1X
	O2xURxQ9d9683fUamjUWQX7xfrAsAxUFUEQohZuUKeIyJgghUYBkaChipUlSWFQIChBCFqBUjkSK
	KB8pTaS4sKXEQRYS8Wef335AlmVAioz3MzOX4u2afV6vvWtvAgWnenoz994zd+6dOQO8ZVCjAWYW
	bQ1EZJqayMwNSe2Vw1a+Az+YmYiIBRG0MXEASaVUaC9RpZQlAGkhRIaZN2JsjG8KDmbuWMrkz1wZ
	HTvnevmEUlo23qgdwICUlkrFHXcpk7/b6xy6T0SFWhKydr6Ukt3Ms+FLV7+95npP9zEYzFv7bhZE
	wNxi5sA/i97AjbFRSGndRk3mJeAXHBEZZv7w8pdj513v6b7OaEQdG+ibO9gdW1VaW6Imbc3AMJO0
	LL288rzr8ZOFftfL779x+/75cln9RETZaky5ya7P9XJJZuZjA31z4ze/+QKAC0AAaK6K36Bqkzp7
	cXR86s/ZI2kvlwRwGEA2kIEqCoVCSBsjGKAPumOrAOaJ6GWLgQNgZnWwO7bKAGljRKFQCNeO19VA
	9VsbIwDYldYhAK1WQ9XGNr6vuhh1BLZaABExM4NarIGqDfP2ZdzW0243eE/gPYGGXWCMAfxWIiJq
	+TaosaGKr6YIMNjv93AoxACUbUsWlVZskQAb30ZVfKHie9tzwLalDButsba+npicnvlq/LuHa+GQ
	LRitnQMEpmKpbCanZzrX1tcTRmvYUoYB2HUEJiYmCACUUo4lrWjIlvzH1N/O5NSjkdaTHwSzv/CQ
	LdmSVlQp5dTGfDeKcGhoyBcHUua00q9KZRUd/PhUbujTT75f8vJ72oJEvKdz4odfPvv5t0lHK/1K
	SpkLxNxkVy4rVRSWFe3o6PA+Onn868HTp56TENhFEYKNQaFYiv346+8nhGU5ZaWKAMp1GahCKSVA
	vlphow0AUywF5u8GpuILIJBSKrDtAQKRSKRkCWEI4OWVF10A+pk5Db9WdnMdGwCp5ZUXXQSwJSwd
	iUSKDQkAWEjGHXc+nY09frLQf/bi6Hi7JBkRUSrR4wJYrCNQ0YNk2zI7t5i9M5/O9Ltefv/UX7NH
	2yFKCYRUvOffkQvDd2xbZiuqeOOoBRCQ5ZFM7tnw9VsPzqW9XLIdsjwZd9yRC5/f7XUO3SOiYq3A
	2fJhQkQwxvQCSP3XD5N60m80YLux89NsE5G38zj9v/EaSObauB3RnBIAAAAASUVORK5CYII=
}]

set shape(l) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADeklEQVR4nO2X
	TWhcVRiG3/ecczM3MV2YpGrINNMZY4h2JQgKLly4ceXKLI2WUuiiQnTjooFhwC6CK6kLSynBuowr
	wR/QjWAgWWgLpVCnydzMX2PNz0Yxd3LvPZ+L3JlO5qdJLbWbeeHA5X7nnO8595zL9x7gCYvdAiKi
	Wt8tLi4SAKanp+WhE5H2SB1FpCvUI4qd5j7wQkRIUhSJyNoUgLTv+wljjDXGGN/3TwCA67rlMAzD
	1vGdZIzZA1BQSpVEpJGjEW9JDhHpXy9V3/tobv6MV6yejKLIQCjG6IQ2egAAojD6JwzDGkgKHrAb
	Ahijw0wq6a2XqlfHk6PXSPrNEKa5vzFGvNLGzAcfX/zUK94dFAgknt9GEfocIwCwF4QDSu/DHCYS
	yK+VRn5fK05dmp+DMfpy85cz8eoVSSsiJz68MH/WK94dfGrADU9NTeSfGXl6W2mtdnd3U78s3xgD
	gDffeLUy0N+/XtsLqduOagwsQqN1dG9zZ/jW7dVJr1g9dunytbNBEH5HslzPaVrGTXjFSlpE5NTU
	RH7h80/eB+ABwNLy9QtLKzdmAWD67be+fv21ly/GK+m2BwqABZA5fX5uYeXXmy8WipU0gOcBlJs7
	NeT7fl9krRKAzx0f2gawSnKL5JZX2fibJEgift4iuVmPd2h/ktwCkH/2+NC2AIysVb7vJ1opGzLG
	NFYTWasAOCJCEaHrOLoecx1Hiwiz2ayqxzs0Ff92jt2fqy1HG0AHCUlx3YTcP46AQCTR50gulxOS
	HVt9LLpv0ZEAHrt6AD2AHkAPoAdwGABFhL5fI8GGiSDI2l7AbDbbrRAR9z3gA23bAYAwDBudtVIW
	QFAvLn4QRPWYHwQRScnlcrZbMSJp42IUqP252nIALZbMdd09rZQlIH9s7gwDeEFECgCwtHx9UOKC
	mE6ODorICI5oSO5t7gwTEK105LpurSsAgNV0KundKZSHbt1enTx9fm6h2ZJJ7EAXv/nhnW9//PmV
	h7FkJJk5OeYBWGsDiP0gHceU82vlK3cKpUmvWD228tvNlzqZ0u9/WkoqrZNdVn5AJEAQmdTYX7Pn
	Zq44jinHrtgCTQekyZa7pcrGzGdffHWmUKykwygyfERbnk4lvdlz714dT45+SbImIqjb8o4XE5Kw
	1o4DyDzui0k79BF+nf+ow69mLSBP5nL6f+tf8GUU++O6lqkAAAAASUVORK5CYII=
}]

set shape(r) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADc0lEQVR4nO1X
	O2wcVRQ9582b3bFxGn8ULG+83sWxDKlSoCBRUNBQUeESQxRFShEkQ0MRS5YlUlhUKBREUWSRlKZC
	CJCgQcJSXACRIkvG9u5k9hNDvDYFKJn1zrxLsTOrtXedrJNAmj3S04zmzj33zJs3c88DnjN4WEBE
	1FHJlpaWCABTU1PSUog0HZGIyKGinhJsx73vgoiQpCgSoTFpAJkgCBIdkIvWWvu+fwIAHMcpBnUo
	x3GqAPJKqYKINGrEifpAcYhIz91C+b2PZhfOuV55LAhCffiLAggCIqK1Tlra6gWAMAgfBEFYFQq1
	ZQXZdMq9WyhfH00N3yDpN4vQzWRaa3ELW9MffHz5U9e71ycQSMvbbA8ThkjYWgBgrxb0KqsuhgTW
	c4XB33Pe5JWFWWhtXUXTzOvo6RVJIyInPry0cN717vW90OsEpybH148P9e8EYWippmlrRmiAZELL
	g4cPx36+dXsEAN5840ypp6fHM2Fo7lf+Glhd25xwvfKxK1dvnK/Vgm9JFuOa+gDfuOuVMiIipybH
	1xc//+R9AC4ABeCwVUwAsnzrt0vLK7dnAGDq7be+ev2105ejePbsxdnFlV/uvJz3ShkALwEoxsn7
	PjXf9xOhMUoAvjjUvwNgg2SF5P3o2G5sk6y4pa1/SIIkovMKyQqAjeND/TsCMDRG+b6fbK65T4DW
	ujHNoTEKgC0iFBEVHVvG3NycEhE6tm3FuY5tW3EcgG3qXC01WgS0gUSrVUi2HfPz85JM2NK8XAUi
	jpNs5D6qwJH/ds8aXQFdAV0BXQFdAY8TEDeUto0oakas7tVIsGEyCNL3q43cjgUEQdC42VLKAKhF
	Tcc8ohkZkuLXamGc69dqYRwHsKfqXC01gAOWzHGcPUspQ0D+2N4dADAhInl0Zkj6JGqImdRwn4gM
	RvHsn9u7AwTEUlYYmdT2AgBsZtIpdyNf7F9d25w4e3F28SiWTKTeepe+/v6db3746dW6JdsdXF3L
	nSTJ7NiICyDXIiDyg7RtXVzPFa9t5AsTrlc+tvLrnVeexJR+9+NySllWqs5dd87Z9MjfMxemr9m2
	Lkau2MTTB2CfLXcKpa3pz764eS7vlTLPwpZn0il35sK710dTw1+SrIoIYlvedmNCEsaYUQDZ/3pj
	0srUwafzhHj81uyAkOezOf2/8S8NpSL7AiHg4wAAAABJRU5ErkJggg==
}]

set shape(m) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAFnElEQVR4nMVX
	W0xUVxRd+9wzzEUEBEQUUBwghGKQpj5iGlPbj9r0h/ShfxVrja01NgF/TJS0fNg01kRttY3GGq1t
	Yxtba02jsTG1mqZgwBdEQV7jPBAt8tZ6Ye49ux/OxTsDWFSsO5mfuWefve49e6+1DvCUg0Z7wMxi
	tEdExKPk0Gh7EpEaE6LwJg+9Zgx5NNKaiD+YmYiIBREspbIAeEzTjAEkAyZJKfsANBBRTziXHfsw
	M08CkG+aZoIjZxBAqxDCz8xDNeyaMqo4mDn2mr9t+bryzSu9vraZpmlJIgBMrOsxdxfMm13DzFuF
	EKeVUgQAQghWSr249Yv9ZVU1tfMMY1AHMTEDUmpmdlam95q/be+MzGkHiMhwghgCAABSSvb620s+
	WP/xFq/v+kQGgx2nLYiS6puuFQfa/vYopVYQ0bkw+DllGz/9/OTpqkKlFBTz0OchAhpb/JOvtvjy
	d2wuh5TabueXl+ENBBEpZp5etnHzKq/v+sS4Cbo5Kz+3MS01udM0LU1KzbrS2JITCN6cdqaypvDQ
	keMlzHwBAH44cqLkTGVNodSIp2dltBfk5bTYOTc7ulIuNzTneX1t8Tt2H1gVCpnHiChg14z4AgBy
	vb6gh5l5Vn5u476dm94G4AWgATD9wfYly9ds2NbR2aOfr7tatPS1V+MA0MXaK88ODIR4SkqSsWvL
	hxXp6WmHwy9nAchesbZ839lzdc+0+oIeADkAAsN6AAAMw4ixlBIM0LQpKbcANBJRr91koVCoMTFx
	onGjoyvWMq2YcD5blnJZSlF8QpyRnp7WQkSdjt4y01KTOxkgSylhGIbbWTNi1nVdV3Zz/GMMxAKI
	c8e4wMzQdTeklBMHBkKSiJgICkDEbCulyDBNFzNTTU2NKzx2LqXUUB0pZQSHRB9Be1JiQo8maNKF
	2vr8nV8d/OT7n4/7D/54TB46csIs27h5YcetrrgYKSkzY2oAwB0Aic5WlWGiOnXqFBMRM/OIpBUN
	wF7UuKT45V8amrylnd198Xu/PVziktrQgtBgCIMhE3m5Wb3vliz5iYhMZtbofv5DhwSAMFIiokFm
	3tbXfzvpux+PvdHV3RtvKQWbXydM0FHomeHfULpqu9vt/jUK/KMDiALhZ+bS14sXH/39VGXR3QHD
	TSSYWdGU1Mndi56f+yeAKiKyxhWAA4QIU+3h8G+kIHuOH6f4MADhL6A0IWBalgfAzN7eOzFSgk0T
	lJgY1wfgKhF1VVRU/KdoPRSA0bTAsixp647u1u8umFdYbWvBuAIAxqQFk+qbvLYWvENENYjikkcC
	8EhacPTEMmY+B0DxA4zNmAA44oFaEGxvf3PZexu2d3T26Ocv1RctLX4lDoBFoPEB4NSCqanJnQCa
	whMBAGDm5oSECC1w4THHMOL8nDxt3ePvCF43TNNlmxAb0+MUHwZgPMIMe7/4+HjbAz7weCKOwDTN
	ocWaEApAKKyOIQBg5pAQYtS3FkKwLuVIOUOE5awxDICu64OaEIoAvtHRlQIgj5lbcb8Jc/v67uia
	EKxJbRD3DAdpmghpQnB/3209GGzPZeZLcBiSmx1dKQSwJjRL1/WBUQEAaPZkZXqbWgPJlxua81as
	Ld8XPYY9vX262+2iOUUFF3FPjvHc7IKLv/1R+UJ3b7++Zv2mjwryct6KtmRERNkzM7wAWoYBCHMA
	uVwy0NgS2NPU6s/z+triz56vK2C+778FEYQQWLxwft2S4sUHbC1g5gN/VV966eTpqsIWb1t6U2sw
	3WlKCYTsrIz+0tUle1wuGbApH3A0iIOKdX+wveSzXd+sbPUFPcNs+fyi6nXvL982gi1ftPXL/euq
	qmvnGsZgrNOWe7IyvaWrl+2dkTntayIaYGbYzmvEiwkRQSk1A0D2k76YDIuxjM4Tu5pFbfh0Lqf/
	d/wL3bl/slg2uB8AAAAASUVORK5CYII=
}]

foreach {dir pt} {t n b s l w r e} {
	set shape($pt) [image create photo -width 32 -height 32]
	::scidb::tk::image copy $shape($dir) $shape($pt)
	::scidb::tk::image recolor black $shape($pt)
}

} ;# namespace 32x32

namespace eval 8x16 {

set arrow(l) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAgAAAAQCAYAAAArij59AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAAhUlEQVR4nGNg
	oCr4//8/I3mS9fX1TFBFvP///2f5//8/I1wDjPH//3+rnskLth84djoOm/FehdWd58KTiz/9//8/
	7f///3z////nZWBgYGD8//9/fPfk+bPnL1vP6u5k9YSJienJp0/fGNVU5N6W5iZVMxHrPZxWEOdI
	vN4kKqBIUkQyAABZZnArknCg+AAAAABJRU5ErkJggg==
}]

set arrow(r) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAAgAAAAQCAYAAAArij59AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAApElEQVR4nK2Q
	oQrCABRF7xtLwlbEsc/Q6if4BWowqV2MhgUxCGvr4ifYtAgLsjK1GQSTf6A/cCwiLChTPHDTe7zL
	edLfAez7JcCecQFPkqIociTJlSQzQ5LSLO/uD6cOMDWz7HUJ8AAfGLb74/toMj8CLUlygXqcLGbn
	y7Xq+xXCILhttrtGGNRWwMApq/a2okCa5b04Wa6BZkH3k2a5R5Ue/sQD7ldznEn4Tc8AAAAASUVO
	RK5CYII=
}]

} ;# namespace 8x16
} ;# namespace icon
} ;# namespace twm

# vi:set ts=3 sw=3:

# Sash coordinates are session-only, never attributes in the saved layout.
proc twm::ZoomSashes {twm action} {
	::debuglog::log twm "$twm zoom sashes $action"
	variable ${twm}::Vars
	if {$action eq "save"} {
		set Vars(zoom:sashes) {}
		set queue [winfo children $twm]
		while {[llength $queue]} {
			set queue [lassign $queue w]
			lappend queue {*}[winfo children $w]
			if {![string match *Panedwindow [winfo class $w]]} { continue }
			set coords {}
			for {set i 0} {$i < [llength [$w panes]] - 1} {incr i} {
				lappend coords [$w sash coord $i]
			}
			lappend Vars(zoom:sashes) $w $coords
		}
	} else {
		update idletasks
		foreach {w coords} $Vars(zoom:sashes) {
			if {![winfo exists $w]} { continue }
			set i 0
			foreach xy $coords { $w sash place $i {*}$xy; incr i }
		}
		unset Vars(zoom:sashes)
	}
}
