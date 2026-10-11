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
		zoom { return [::scidb::tk::twm zoom $twm {*}$args] }
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
		ttk::button $hdr.zoom -text "□" -takefocus 0 -command [list $twm zoom $w]
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
		ttk::button $hdr.zoom -style twm.TButton -text "□" -takefocus 0 \
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
			ttk::button $hdr.zoom -style twm.TButton -text "□" -takefocus 0
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABBElEQVR4nJWS
	MU7DQBBF36wtDuMKa6HNZq1EmEhBCGn3OhbXCaIKChRAlB5E51vkAAR5l4IsmMgF/HL+18yfPwMJ
	TaOccxkHcM5lNI06rP+gTw4Jm31RV97qkZsCGGNyY0wOcGL8RFfeJm3etq0AqMBRyFhq6y8368UK
	oDSujllcho45QNu2Ivs5Cq5DaVytlNwhTCXEEEWeRLr5y/PtfdJ8W0sWSns10tZvtfXb47EzfQ5g
	YPsciBHiYCbDlpRMpAsxKnkUuotfllL2p2N/pq3baetnqVtpXK0r/1EaV8PXTVRRFBEgKHYSZPa6
	XqxSrG+bmwfpOFeZvAMk7f8O1yf/8hqfb+NoL5nldVcAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABEklEQVR4nJVQ
	vUoDQRic/XYPCUZCELQPPoB6rZoflWAsBMPeI/gWsiy+ha+w2KmFQcFWONPZmVpQkGA0SLLfWsTi
	lAvRaT74mBlmBvgnRN7TGEPWWo6reoMi1UIIHxz8VXrj7miak9ZaehJvIfBeoVg6QcA+AOQKrAWc
	c54QFpnZDwf9ewDzAKB+k+P4KKpUHvjxOWkK4NIzmmP+fFKBytnQBBia3G9hI6mvVg93Zq6wVmtv
	x42kPs1MAMD6VntzLPhVClomITvMobWyhE6vV6Y0PR1lDRUACEkHcxTVPI/Awe92b8+uuzAE2B/k
	7ErvhWIpJpJREPyitZbG5EeeCAQuhoP+sSB1LlktOOf8zLJ/xRdboGQWgkUSLAAAAABJRU5ErkJg
	gg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAA7ElEQVR4nI2Q
	MU7DQBBF39iWEwnXdHRcwEqXZpQuUkTHFsBhIh8ip3CZgu1ClS5wgbQI0RsJF/ZQOI4NMZDf7Oj/
	t7OzA6eSX+pBDQHfvKAr7RhMZs5PZs532fLISe+0Br5dSxAuMMysftxt8ptDJm1XgaVMpy8X5Xi8
	NrM3gXcMAy4RuRqVn4vtNv2AzAJVDSGryzi+B3je5HeHN2X3lD8IVE2W1Q170PV8PmrHS9WtUnWr
	duRe1n16732pqhFgIlQiVICparT3vmy5qL+yoiiaJRjxiTd0IUkSA5CA15/en3LOhc658F/wHH0B
	ZLtMHhG4Fp0AAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAA7UlEQVR4nK2Q
	vU4CURCFv7mXZEm8CR2NseMFzFrRrGu1CbHzUvMcNMTnsaSQDm9DZ3gDWmJCuSaLkB2bXVx+TCw8
	3Tlz5ucM/Ae899Z7by/VTJMkSdICWG0YrzaMm1qNI5LnuQBoyfWpdrHBOacACF9n2ulJvSyLQgh7
	QFSxqlhAQgj7XpZFh4b6xk7hRvHD8A1QY9gZww7Qu3Q47xRuVOcRQGAi/f7yattuT1V1LfABKEoX
	kZtoWwwWi9tPeNY6kAAKEN8/TcXaAaBalq/v85fHqnbwVNBqG8Spn8Wpn/0Mmxy9vwn5o/ar4cz8
	DevKTC1ouVvyAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABBElEQVR4nLVT
	sUoDQRB9s3ucRrD0GjvLFCbh8BqJq6BFOiVskR+xXfYj/Ir5A4vAIYIIgpVfIWiXwr0dC43JgQfx
	Dl+1xcx7b97MAv8G55S1VrftVq2FjTEJAOTjyyI/szdrLui3+pqSMSYpyzIMj68GemvnDoLRl6Fm
	Rz+s1lrNzNXhyXS0naYPArl/S94n+4tFBQBZlsmylpkjAFnRfCsMjB0WF7PXo/MZbzoyOeeU917y
	02lBKrkFZDdWcU4KQYQUESIEBIIAAtI6hBivn+f84pxT7dOuocsIy0fbEGu7XV9j2us9VuHj6WAP
	Y+73Bd4Lask34K+H1IAOp7zi6PSZNscn2K1vEEjXrzIAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABAUlEQVR4nLWT
	u0oDURCG/5lzRNA+D2FhIiExTTwYxVZBptCXGba1z0PIImJl6yGdoChCWvv10oiY4O4eC6MsgZD7
	X00xfPPPDVi2RMRAlecnTQmhv+rVXWlXm0d1AHDO2eHE0dRBRQLKZnWtU3aHFe99OgyhYiwi/8Ak
	SQgAXkolXn/nayJufvV7jafO5b2ImDiOs2laQn3v5Ly2f/q2uXO8NbD461BVOYqivNKSDct8FrLM
	AgQEEAghBDBRyEMOy4ZbAH2EPD24u7m4VVVawHrmbaGQM9MQi4CiCKok3S49v8KzWan1vz+3H/3V
	g3POeu/TcY4nPqTJNes/LO6ZRugHVSxqCLgLn+MAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB3UlEQVR4nJ1T
	wWpTURA9M/f6Xlt92UiliBDwC5q6FZKsu5HEiyDuXPkTPvIHuvEXXFxt/QAR4rKg+AHtotC4sAm0
	aZsmL+/OuMmz74VSpAN3c+7cM2fOnQEW4Zwz+M8o51L5otls2svVR2t2fKbXPcxrCa1eHk36/X5e
	YJymKQNAo/2ic2E2BiGbj6ZRdDKL49PymUbRScjmowu7cdRodzsAkKYpEwByzt05GOoxE39X1Y8q
	iJgRytVFYIiREfFLFXn6eB0PvPdzC0APD89W+F6tlof8/a/+zteb+t9sdv5YY7cHg2kMILMAEGoJ
	Iei5MebdVsv9JsCAUPVBQQoEYjxU1fPZWswAYK8SlAgsIA1QKIBlI4kIQkqiKlT4bwEgnsxkFsd3
	VfK3P/o7X25q4Umz8wxsduPJTKoKABU2yeKPDVA1scD2h0i4pK5MAFIV7z8F5xy89xWCAttqPRfQ
	1fhUFCgRFwqcc8vqjXMO+0MwLSvI84wQx6wqY+8/h2vko8A2W90xiDnPMyoIqF5PpgdDHRtjXzda
	bsUQIl0iIcAERcZMryB6Wq8n0709EKVpyr1eTxrtbsew/aCq91WEiaiyJ6qqxCxENBKVNz+/+V0s
	Rvlf3GaZyi7fap3/AjEF5fJT/a0hAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB2UlEQVR4nJ2T
	z2pTQRTGv3NmetPGJhuxFCIUfILG7L0NuHWTOLjoA4i7vsElPoRLl25GK64VaV5A+gBVCGRnAk0v
	afPnzjkuzA33hiDSD2ZzzsyZ33znDLCSc87gP1XcS8VEHMf2bu9x1d6kuu1gVq/R3t3wtt/vZ3mM
	kyRhAGi2X3Wm9nAYFsvxLIqu55XKpLhmUXQdFsvx1B4Om+1uBwCSJGECQM65nZ8j/U1kLkTkgyFE
	CoTi7QSYoFiw4VMEefbkEQ6890sLQAeDdJce1OpBsveXF5++/Ov9xyfdmSF+MRikuwAWFgCsjTQA
	QsT1lUEGGwR57GqEOgCxNlIAsEVKUhXvPwbnHLz3pQJ57OnJSwHR2vxiASgR5wTOuU1645zD1Qhc
	bF2JgCWk3p+HLfjIY624k4JNmWBerTAynRLbt622ew0Fg1CeBQWBIARqqMp0Xq1wmYBIlZRVYOiv
	YZvDRKoIYGWA1jkLAOYmVdmv72chO7vsn3/bgr/Wcdx5bo39Gt3OJC9AR0e12a+RTqzZOWu13YEK
	IuayDyIwxFgQ8amKTBqNyhwAUZIk3Ov1pNnudgzbd6r6UEWYCq0CAFVVYhYiGovKmx/f/WesRnmt
	+3ymte77nf8A2PPaDRLdDcwAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABs0lEQVR4nM2T
	wWpTQRSGvzN3em9bSTaidCFEfIKGuDbJA7hJGLrQla58ikvoO7gUtzJU30AJ7oroC1ghkF0TaFPa
	pDd35rhIUi66kaz8Yfhhzpn/MD//gTWccwn/iGqvVAvtdtvO9x7th7IQgOzmNlbrZb0me/PxzXA4
	LDd3Js9zA9DsHvWu7cG4LJZTDYwJjG+z9GJ1sstFml6EYjm9tgfjZrffA8jz3Aggzrmds4meGzFf
	Neh7DMcoQeAYw44qUSAJSmES84IQnz15wEPv/dICOhpd7cq9Wj1oePdjePKx1XWvEcpvX/yHP/9/
	2OkvEjHPR6OrXaCwANamGiCKmLpzLvl1TgqYtVkJEDb8c0IdiNamCmAq4iKq0XsfEBRBvfcBCFUW
	1Vg1vyqwFf4vAVWRlXG6cmFjYpVVxAC6eWQByrIQssyoxpn3J6HVdQVQbsxb9waAw05/hhhTrtNq
	AWk0aouzic4Ssa9abWeAxyjhaccd/RUkIy+Jetlo1Banp4jkeW4Gg0Fsdvu9xNi3UfU+qnMBAd1f
	DRdRVRVjoohMo8Y33z/7T6yjfIdtlukO267zb4O534IcWASNAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABuUlEQVR4nM2T
	v4pTQRTGf2dmvHezkjSibCEEfYMQSyHe2i5xsLFQrHyI5ZKXsLS0GRfxBWTTLii+wArBdLuBbJb9
	k5vMHItNQlYbSeXXfDDn8M3Md74DS3jvLf+IzV7ZLHQ6HXdVe7jrpue6eT7bzQ2AdZnWrkaXg8Fg
	saqZsiwNQKt42b1we6NYzcfXWTaZ5fnZLM8mszybEBlp5Fes5uMLtzdqFb0uQFmWRgDx3t85PtUT
	EXuYUvpohUwhimBIzBX2ESyJfbHmtab09PF9HoQQ5g7Q4fB8R+7WGzEtPvw4PPjy55/bhX8FuG+D
	8KlV9JIR83w4PN8BKgfgXKYRkohpLA2yQFzxzxMywHnv7fGYBkpyLlMAs3GRiGoKIUQg3mJBETSE
	EEU1bZq/KbAV/i8BVRGzMvEW640L3nurIgZYB80BLBaVkOdGNU1DOIjcTIAVtwtfASmEEJ8Uvali
	zGJRyUpAms369fGpTq11b1vP/M5fQVIeIdh2x79AzBtSOms269dHR4iUZWn6/X5qFb2uNe69qt7T
	lIyICOjyqXKpoCJSE5Fx0vTu+9fwmWWU19hmmdbYdp1/Ayn42KiqBddAAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACXUlEQVR4nKWT
	zUtUYRTGn3PeV2f8SjcNEoYg0YctQsdaReOss412lWij7fI/KJDbhRbRLjcRFG60zc0W4doaIxFx
	dKWLhGBAIbIMv8aZe9/3PS3SmKLZ1G91OM/h4fAcDnCE53kKlfg+/7X+Y5YqhUwmow/r2uqt3jH5
	mZlipZbu66tXplnXHW4Uc7mcOe6zf+TelR3qP1Ctm64cb1GxYTudHXwC+Az43N3rjVOxYduV460D
	3brRlR3o/7mYzwSAvE6v5lMKX4jpvXUyyYwzWiceRmVzWYkjlaxdjOPoPjlZJ0XD4uRqx0mkwjCM
	NQDZbCkniOuanTXPVnLTMwCQzg4Fit0p55yTqOSW34WPAJJLmUGjGdcLhb0kgIiOA+qeW11gVufF
	uQ8gOk3EF7XYNgtccYJpOJ3qSJnv61/ptoJMJMrllvn5N3uMAEAQOIHzQDQpAiFSq87ENxZmw00R
	NEJEIks2DENLTlxl+BoIHABaefu6AGAUv0NOxBGqo33f5yAIXDrj3WTNT51ICxGJiHuenw1HAQbg
	qhpwEATS6Xm1wvJCRBZg5Rase1CjE3d7rg10CWMXRFzVAIA0FvaSBDphDU3kc+GrJel8HEdla7Vq
	UyADALVKlOd5SpgYgFRkUB2yJFaJJoFdzr38lv95xl0w2JiIjg1of7+plGyQXaXlTjrjsdDaWV2b
	UFHZfFZGSCUTqrt38B6J95EUhsVhp729qbS4CGLf92ltLYwEMgKiHmKaYsVjJi6Nr+TOLS/NXcib
	uDTOiseIaQrEaWGMhGEYwffpv5/pF//6zj8AzgA1YKQaH5sAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABxUlEQVR4nOWV
	T0vjQBjGn2QySQZlQZDVz+BhwRapexJcEKxe3GXAb+P32PPe5lDxEAvduxatC0WLB897KCiI2iQz
	k8wetsW4Nf1jrQj7wJwm83ue9807CfA/yequqcGnpT07YzK20cADnHMihEg+fd756DJ6YIxR4Ty+
	tIRQ3UfMMAM7byMLp4wGrj9TAsDGy59TQR/cY0UZhw1FVLlZq7S754amf7aCJ3DfOXQ9VpRR+MtO
	zHazVmlzzkkm3HNrYAU2gLQLr1KPLWsZ1TsdU24di5tREg8ysACYlTW+mBIrcBx3WWt1rmT8TRP6
	+4MHV6VI8lFzaPz8fptlZQ0sAFhd5b7ycUocZylJtIYxMWBpwFBYVpqHNjCpbTu2SfTZrX+/cVWt
	yt5W7hS9lvpaVFrfXUiMCQilBa3lhZLWV03SiVvUU/YlH1KPFbSM6vd3cuvyZP/6JRX826KUc06a
	R5W2ivSmklGDeqw0M+vWVtb4IvB3jJE/okPHFD3I412ggeuzoow6Z8rxNpu1H5NdNAAQQiSPlaiy
	jMOGx2YLVMfBEufuoHAjGfSZhKoso4c6gHAU6Jia7HM9qqb5w3li8iZG70t/AKOK01yZGN4rAAAA
	AElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABu0lEQVR4nOVV
	zUpbQRg9X+bn5t4WpIJKXXcV0lJUSBauRDG2tdDFgPQB+hp9oKF1IabQ0kWhEoMYggi+gomFQqE3
	c+/cny6SgITcq0mqFHpgVjNzvr8zZ4D/ETRY9xLozogH5O8LfysLAoCSUsL9ga9EJMKefX3W2O8q
	pZjWOs66eGMGY1CURa8iXFEvV3aXtNaxUorlZnZLEID0+bpaYAJ1WfTWQuO3At+8OG8edLIqGVcB
	ZSwopVj7u77ixF6Fxm/JorfieO6nvEqmVsLT9bePpLB14bhVG5h24Pdq582DziDpZFwAApACwOrm
	uzngZya5KID9ChDKNH5cYOyjEE45isJ2IU53Tr7py+tcwwAEAE9qNTlnHn4mxleSJEoIlC2CNCWA
	IiDlIHIY4zyO7IUwtHp8rM3w1DQqygCNbfhMLeKxXRZSfOD85hZNjFJVzbseDoXsD9kau33W2O9i
	ZMiTyJSGMqxs7C25Lr5Ix6tGQdAakg/2k1Gy24IApM+23iyKmB9Kp//QrIl28ixjGi86ctwHa4Hx
	T4PfvZd5rxiYzotMaPym7dlci5gFE9n1rIHujPhevsx/A38AhGTJcLHklSMAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACYUlEQVR4nMVV
	PW/UQBB9M/aufZc7B/ogUVCBhISOIgWIBqSToAM3iP8AJV2ULvkfpDrKFCkiEKmuICAREA0FQulO
	4sOX3Mfa3qGIbS7xxZdDfDxpZWk882Z2d3YeYTroFPssyCwHCsPQ+U1yZLHHipta6XIY1uJv0POQ
	q/Mw3U5neNJOk992u6174+Y6Md8Xa4PMPuu4BIAQcyTWPv/h9Z9+2toy+T8GgDAMGYD0xs117S88
	FitLAPgM5HlxLFaWPH/hyeK4uQZAMs6iQmm17tUR1D4TO0Gayt0kcd743oBH47qtYs99HCdpKZc3
	rU0jRMOLu7ubAwDk5o5Jw9GuSF3SxLy9deUlVlcriUtYWXnRevXBAKgnDUcDGABAkcBVWpDCQoSv
	7exdSG48jObhd3f2AoAZRNZ1ddGuRQIzUqyVSYj5HAu91yqeawOAA2Kqi9jvZqQ5t3JVyJ9AsQPt
	xxYpKbF2QNq5LNZGSWzIVbrydeY+xByIST+CSGk/Lu7PLUUQiRH19d32s8N5Kr1651GiyJaKKScA
	QKavMNHCM7gJgJDpK3D58U9NkB1LTjxzgAGQrAtL+OuX/H8SGE/lc+jMK4s5PUESG4IIQUTSenyI
	o7O32bdqWQBHMSICEUpiUwzJX6PiIDUI9IDICbxefLN1O3xdGykeTvT0NOQ+tmevMyttJY1qIz2e
	3IGEYehk029Deb7H7Gwjxf5QxV+QYr9q5T7MzrbyfA/ARrfbGWbqJscE51K7rRfHzTUwP8CcggPm
	CFMEZ7pkLoe1uDGnZB7AdLtlyTyJfyP6FfZZKL36n+Z4Ivnvz7HgAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACYUlEQVR4nMVV
	PW8TQRB9M7e7PtuxA0h0KSioEEhITpECUSAKC9HBNfwJKOmidMkPSWVKkCIoAEHhxqJKaCiiUKaA
	mMg+397NUOTO+bA52yDgSauTZmfezM7uzSNMB/3CPgs6y4GiKAp+kxx57Lnipla6FkVV/w1uEXJ7
	GUm30xletNPZb7vddoejxhYxP1KRZm6f1S4FoMTcV5EXR5Ufz7/s7CTFHgNAFEUMQA9HjS0X1p+q
	6AoAnoO8KI5VdKUS1p8tjxqbADTnHFeordbDGprVfaKgKZo9oAC9amx5GHopYy98JJVVw/aVaNZH
	f3it13s5AECmcEyXAmeAqkqaxFfp416nk5TwTuBGFH3gwzQBUEuXAgdgAADjBMY6RQaAiIKBrQPw
	xenmaJEGA1sHeQKgxrhxjJkW4UZezhDPfNsANI+ZAM8R/Ef4PwlSnxSva+6Vx8yXQF3D46T3xV2U
	LQGgecwEJi9ZlRz5K637kUl9Qsa60ksufIh8U1UJROf8xwmS2LKziSfmS+plDwAMOyAroz/10UxA
	zDVV+Z7EbtyZv37J4xO40AsyMioyEJKbqQ/7CxHZuMnCuyAy7sx4OR0VPiFDlgHIp7u3vmJjo3QG
	TWB9/aj1flegyqn34xd1OiqOswRNNyAOmrfffb6X3XnSCysDjke10kSFT/B2b5WtcSJZvxq7UbHP
	OBmtQT79tq0LK0GAN876AxG776w/KFuFT2DotXVhBcB2t9sZ5uqm5wTnervtlkeNTTA/xoKCA+Y+
	pgjOdMlci6p+aUHJPEbS7U5K5kX8G9Evsc/CxF//E0ptI27FguLAAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACVUlEQVR4nO1V
	vW4TQRD+Zu52zxefnRhBl4ICCSltUkSIMoUl6OBegBeAkkdIHgOJVKEEKRLpEJIlSANIaSj4cWcp
	CDv22be3OxScT2d8RxQEVPmk0Wl3Z+dvb+YjVINq9s+DnKdAcRx7f2gc+d2F4Coj3Y7j0HyDBoB0
	qhgA2BuLr3RthKqDtHdwkCxFXP52u109mLX2iPmeONcWgAiwuY5fY1sACDEPxbln34PR44+Hh+n8
	jPPUGIAMZq093Wg+FCfrAJhEmIjWiGgNInXvQgBYnKwHjeaj1VlrF4DkNkG5yObm3RW0w09EXts6
	c4d9fpsZ7vjs3gMAKd4Q54aZSalcqnCqOGkY5zK35bN64cQOMUyuHx8/nwCgIu0s8rQPhOKy9FSi
	15+Pnkxv3nrgomAEAEhFnb47ejque4ONOH7FgywFsJJFngYwAQCeKxRREVE4cU0A5LmRKuqQjtS8
	HKXMi7U3UU0QEYgWfobCQRkqsA6AeL4qFPNLtaJnxlXZqnTwN3Hp4NLBP3JgAo8BkM1MMX8yk5ab
	a0nSQFXa4gUDIgQRSTIeAxDLLTM/F90y+NlUDotN5gCIXTFjiAhEKA8GQGkE+2c2RVtPiLz2NZvc
	vroTv8nMuDM/12SubO7Efu2wG7gtZqWd2GE41bNyBhLHsZdPv30VNALx8BIWfZ/sByKKiCiS1J7A
	ou+z/gqL/lwSZb7Aos/sHamgEQDY7/UOkpzdZIFwbnS7enXW2gXzfVyQcMA8RAXhVFPmdhya6IKU
	eYa011umzF/xf0j/N/vnYSnDH79lHTqKGrzdAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACWklEQVR4nO1W
	PW8TQRB9s3u754vtSxDQRYKCFhoLlAbRBMlCdHAdEj8BSn5C8ifoUpkyRYRokFK4IB0KQqJA4M5C
	EXbs8+3e7lDkfPLHmSgIqPKk0elGu29m527mLaEatMJ/Hvi8BZQkifxDchR755KrzHQrSSJ7Ar2K
	KLeGvKsTAOia9QCgrsB0O510KePZZ7vd1v2suUtCPGHv48K/qlw5ADAgCWASYsDev/kZDl99OTgw
	xRoWxdEEAO5nzV1dq79gz5sAxEpyZiKiDSLaIGYBQLDnzbBWf7meNXcAcMFZZsit1uM1xNFXIhl7
	do9I4iiaKJEWJZiWJlCaSYiYrT8GgNyL24HyJ87SXSXFvmc3wCC9eXS0PwZAQbm5IXUAROxzM7lO
	h8edjsEK3Hn4LFfIAAATW//x+f3r4Y0Hzw+v+ZEBsJY3pAYwRlEGAECg9NkvRkRyrOrFyaZlotl3
	MkM13Sf9UAGgKPB1EBGIuOSaDTALnVl/9v2qbZZABooBsMqcr+KqDPA3cRngMsA/CmBCtdhgc5Zb
	U84ol1sCQDaUlVylM7eGwExgZrdmRzhrqsWG8wCYddOWAUTTAuA0FyMwM5jnEihnUXDqDGI9JpJx
	2Lf3W9vJh5XDjmw8beWaGl1tbScCZnxPyEB7doNoorPZE3CSJLKYfnsqrIVCyHdw6KXKfoNDb2qB
	0N/h0GPjPhFRg4gaAbmPcOghoLcqrIUA9rrdTlqoG88Jzq12W69nzR0I8RQXFBwIMUCF4FRL5lYS
	2cYFJfMUpttdlsxF/B/R/43/PCxdW34B5JUaafzTZqIAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADUElEQVR4nL2W
	v28cRRTHP292Z+Z+n4MUmhiJ2iVOJDdI/AiShaDC28AfQahiqihd8ockzbqDSAemMaS4IkaiceUC
	Ra58EsZ3vh+7cztDcXvGxGfrMBJPWu3s03fem/fd92OExSJvfIf/iPt7Q5Ik0ZvKUic3wF06AQAb
	SVJ1JxgAfYu8m6bjm+Lk4ntzc9P0suZTUeqL4H0LQJTqB+93Tu1g+7DTcUBYApeXdoMqQ1NA6GXN
	p6ZS/zr4sAooQAUfVm2l/qCdNZ8AfklcKG0i5RM2NpKqq/C7RFE7uOLz3OtXAMa4u0qi73xR9E8r
	g3cA2lnjSCRu+lB8KhH7AH7q78ZKv/Ch6NMfv7u///0IkHjO1TAeVQzVui+m+a8/7+xeoHH3vQ+2
	coG6GTd1bGwgTGohTPPJbXl5kKY5wFqS/KJ60xyoTRuRAUYA5w7q09rExQxVFLXXP0o+yfMyAp3d
	Uyo2vij69Mizlb7V1npAopGuAw4gGuk64gQIcWzO01WVfEXdbjpGeK5NxYL8aLR7bbR7jUQ/aFOx
	CM8PDtL8VsPq+WaTOc8s90O5viQxQJqmHpBTO9huT0CUSkIILUBE5CibDHdu28E2wDjLfazMIlsL
	ZU5RADjsdDLgm7UkeRj/OTvpdCVzc54BYm0CxdL2UYuU+WAgi9Y3kXkE/yw0p7aCz1oAK77dX/8w
	SRv++Nu9vb3J1OXybyi6qtDulE4l+HDHVuoPztTbTwCq1iyM+joHkqZpsb7+WQ340mWTLBA+JmKV
	iFUfivsum2QQvlpLEnNyljlCWJq28zqYNiITQzX4qwuIY4yttzxusnQE5w7K7AiISP0P1+TRoxOA
	+svfml60AD7WdlZAIgEgt1pR/r/camVG7poIXC6xaAX44Vt6wOPHHmCYJINqLwQgmuaZAGgJCiiK
	mhtSpnhRc0OGIQBq6pxcchCfFTktMxKJWrbn3l+/n7wCKI6Leyoyxoein1cGDqCaNUYicfMqXHVi
	srnd81ZRdr9n2lasUtFPFBxRcBRF8a62FQs8O+x0slkxyrW4bjcdl9MtLGwVKLXFrFVA2SpOZ61C
	AZzawcP2hHANTkqbV4zMjaTqGuUoPCPvdq8YmUviLsr/M/QX6G98bfkLv6vio1RL5yQAAAAASUVO
	RK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAC00lEQVR4nO1X
	u24TQRQ9d3bWxkAkU9FCEA2PBmOBLMAKPUSRMh9Cm2blBkp+gm5BSLRIQIQEKCEUCKVBMtAhpSBS
	SIw9j0OxmPgJ8doiDadZrebOPWfmPnQHOGTIlOsHBSczTxKVJImaETmSJFEY42/ECRMFNAIA1Ovm
	+DaOamAbwR+b6DZUtEugjDL23Opq+n3Q9zgBAoCVG+aixKpBsgqyCDBnKIQQaSvBGp1N3q4+/tDl
	GBKQJIlqNBq8XF86D114qZQuA4TIdJEgAwBB8Pab0F9ff/5oM0kSaTSym9CD9kFFd7XSZe+sB7hG
	4ouACiKTJRIphAQRniJUVev4hHPhHoDbvQeXni/P1c3xIwoftY5PemffbDxPa7mP3oPKwvLrSBeu
	eGe/Wl08+/7pg90uZ/8NtFGQErWIEhCfjDFRs9Uqtkol19nZmSgPCnNzLLVaer5Uaje30BRRVwHG
	bqddBLDbtesTEOmYQCf7ETBNUw9gL9exM3Q2AFQWzO/wZRz7GMwBkBAyAMTpyk2zLKAOlDBodxAo
	oSLEIeA0GUAOl/2QABGo4B1ESU1UVAOAKA971x8AwiN4BxEMldTMul1ejAiBhEhreGtfEe7+jEJw
	J4rjmrN2yM+IEJAiChA2N549fJiHeBCVheVFEVUT4VAvGRLwG0TBGBMhSwGfkzsC4JtbLIwzGC9A
	hGmaemMMfpXjxOju7S3DQRx6Ev4X8F/AeAGkYDZDqfzyNRJ9ZeidFcTdbbTIRqfIGJOXPOshIraP
	Y5wAFNEhxJGBgJoHgDRNO3nZsd/AzmQ+xeq5YrvXYHAmDJcWlp9oXbzlnPWCsE7K56lHMqqqjuPI
	2c6Tdy/SxS4XMNwJRQW/Ery9pnV8AuDVbJLJj96hNJKwgoG8GjmWX64vXZAobgSgCvLIlGP5DwWs
	0/9lLN/HbB8mFntu8w8Pk9E43KfZROsHxYSP03+In7aOXEfNmq6uAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAC2UlEQVR4nO1X
	PW8TQRSct7dnx5BISUULkWj4aHAikAVYpucjUvaH0KY5uYGSP0F3IKS0SIQICVBCKBBKgwjQIaUg
	UkiM73Z3KBzL30l8NgpFpjmdbu/N7Htvd2eBE4aM+P244HDDo0hFUaTGRI4oihQGxOszw0gBVQ8A
	5bKZ3MEZDezAu7NDZUMFewSmMY19u7oa/+6OPUiAAGDxtrkqoaqSnAeZB5ixFEKI1JVgjTaNPqy+
	+Nzk6BEQRZGqVqucKy9chs69UUpPA4TIaJUgPQCBd+kvobu1vvJ8M4oiqVYbmdDd470KHmmlp51N
	HcA1Ej8EVBAZrpFIIcSL8Dyh5rUOZ6z1jwHca5+4tD15qWwmJxS+aB2eczZ9v7ESlzJPvQ3FyuK7
	QOeuO5v+THX+4qeXT/eanJ0ZqCMnBWoRJYDfAgBjTA6Ay8gdxHGcAPJVRN0AGNrdeh7AXnNAh4BA
	hwSSxgslPFDp4jjOJMAYAwACMuzkaGFwhzVqPuQG0hc8rH/GttlkxamAUwHdO2ELpBhjAgDBwXLK
	gsAYg63twWfJYAGC5GD9Z92E0Py3WFlMji2AFCE9QJkt3jGLAmpP8f1+PgpKqAix8JglPUjpyUSP
	ABEq7yxESUlUUAKAIAt7Mx4AwsE7CxH29Nz/14QkfKA1XJq+JeyTMZXgYRCGJZsmPXH6lAAUUYDg
	28ar+FkW4m4UK+aBiCqJ9J4tHQKcTQXNc4sQY0ywVavla4WCTXZ3h7JluakpFmo1PVso1Le2WwbE
	2bQjTmcG8kgIsaQnBBcOluH+MMRdSDYAFCtmlvQEJNVT+Xr7gG5P6K9VFpe1zt+1NnUCv07K95Et
	GdW8DsPApsnyx9fx/SYX0NsDorxb8i69qXU4A/BGw8lkR7spDcQvocuJ97Xlc+WFKxKEVQ/Mg5wY
	0Zb/UcA63RG2vIXxXkxS7NvNQy4m/XGyV7Ohvh8X4/CW/wZ/AaR2WEq7A1jjAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAC1UlEQVR4nO2X
	zW8URxDFf9UfrI2NYougXBCKiHJJnAOYFWBFWZkzBhk8/mN8Ge0l/COcmEMkh1ukgLmAAAcJRVwg
	UcKJiwVRWCvr6e7KYT+y6+zaXmHgsk8ajWa6VO91dc/Ua/jIkHccPyh0tPA8N3mem0MiJ89zw5B8
	A2aYG6gngFotm37DUQdvSHFqpGoY21CYYYbtsLFRvN2de5gAAXT+u+wb8aauqlVUK6CiKiKCAVAl
	iegByiqKSNMIDzWU+eONH37tcHSFdufdLtG52vKceHPPGLdsrTvpfOWE8xOfOu+Pi8isiMw674+3
	3u13VU5Y606K8dew/l518frXvVwAbpdkTcZ+74ybiaGMoA9V+bM9dsoYuQgQyvI+8FJQg8jgSqiK
	IklEP1dM1Tk/G0K6AVzprbz03PWrWjY9YXjunP8shvLB5p1ioRN45tLqkjN2HSCkeOXJz7d+3H8J
	WphfXLlv3ZHzMZSvSlf58ulPNxsdzv4KNDkik+pEjED6HWD+8uWjpycnmy+2mOqJnMqyzAIWiHtw
	26IodkB+EzEXQH34u1kBGp2APgHWeYWd1oOKB+SvEGJRFPHsYtbdvaKaiqKIWZZRFMVQAVmWAQiq
	vp/jPwz/1ltrO+IPZCB06D7ZU8AHwljAWMBYwFjAWMBwAarC4ZhSaecaiL5uGEMpdPqWaAnoJ87Z
	LMvsiy3pilUR02nH7Y43DK12LVL2cQwTQIUdRYJqUjCnATZv397eBM5cWm30RDbabXgvL0DP+Bet
	nFK6Y5Vmb0BXTZ7npl6vp7OLK+vOVZZCKKOQHqHyR7uXdi1ZSjqaJVNTdd7bUO6s/3K3uNrh+n8F
	QEyKaymW3zrnZ0EvtJwMqCZSDK2yeb8gYhY4AFQTIKRYvraS1ti1rwba8nO15Tmxvp6giurEO9ry
	fww80jjYlr/3g0nJdni2x8FkMD7u0Wyk8YPiMLzl+8G/wFA8s4m+y0sAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACy0lEQVR4nO1X
	TU8TQRh+3vlgUTChQeKFGOPHRfHARyMSY1NOXMCgDD+Gy6YX/SOe3IMJcjNR4YIB0cQYLyJRT16I
	JNpiuzPzeti2ttgPGkAufZLN7s7MzvO8787u+wxwyqAj9h8W3NnwMBRhGIpjIkcYhgJN5msQYSiA
	nAeATMb07+GsAvbgXV9H2RAyz8AABlCwq6vRr4NzNxNAAHj8rrlJWuSYOQ3mAOC25MxERBDJNTwR
	M0AMoqIgbLCNwzerTz9UOKpCq3GXUzSRmR8hLdaEUPNSqmGlgyGle8+3P/QgEaWIKKW0HkzagiEp
	1TAJfR9Sr6WzD27UcgGAOhiIF/KhEmrA2dgBvMGMrwQWIGq8kJiJQR7ARSHoNgDYOF4H8A0AiPgS
	Q6SV0ilr/SMAc7WZp5ozX8+Y/l6BT0rpC87Gr7deRlPtUl/B6PTirBJyGQCsd3PvXjx5Vukbzy6s
	S9Vzy9n4e6yCa++fP85XOOszUEQPnWFFJAjwOwBgjOkB4FpwSwBuexd9NW19xhi5s78fbK2sFAD6
	TCQmAdb2ZzEAkK8MrBMglWaglNww6bJKF0VRUwHGGERR5Mayprq6idlHUeSuzsw4AARmXc/xF82/
	9eSdd/gDaQhuun5aCvhP6AroCugK6AroCmgugJlwPKaUynM1RF01dDYmVOoWcYykGEljTCsCaYzB
	9i5Vg2EiUS7HEkkxius4mglAgBKDLLNnQFwGgCiKSi3jK3uF0enFfE1bvlzCC+X7K8mcFKtzQbH2
	4aqaMAxFLpfzY9mFZaWCWWtjR/CbzPSlU0vmPddbMhZppbW0cWn57avoXoXr3wwAJLxb8i6+o5RO
	ATyZOJn2YPbwzgIAlNZTRGKq0g4QvIt/SPJLOLCuGtryicz8CEmd80AazL1HtOW/BbDJrrEtP/GN
	SYyC/dhiY9IYp7s166j/sDgOb3ky+ANqOT8s8PQI3AAAAABJRU5ErkJggg==
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAFJUlEQVR4nMVX
	XWwUVRT+zpk7u126hVZDI4kkpP48VJDItFJ/cCkBXkSloWN4wPDGs28mxGScmGjim688mBiIqQ4G
	EvFBaywLMRTKYlJNQxQRE7W6JrTQ7c/uzL3Hh9nd7ra7orTCSTa7k3PPud+c/e453wXus9Fd+OV/
	iFlinsee53Ejl+u6VpNNqOxrkM5jNMnXIJHHgG8AIJNx09NYo4BptOlWmp9PF3K5Y2FNrCz97ThH
	7ChdbAWmAbSjHXNRNhsUluZuBoAAiPOCu4Vs9kWkFyLJRS9NkeCUmhd/dDSYr4mXvj43FaX4LSHZ
	D5GOmpgiEy5JFHqXs6e+XwJ8EYDneez7vvRkBp6ASpxnVu2AgKhSOYExBpalEBYXvsRMx77cvg0a
	ALqDCdXSiTOJZMserSMwczW1iAFAMDqcItE7xkY+nfA8j3w/roRaUgExbL2jWLXrKNSAXBLBLwRi
	QEhI+ozRG1QiuVevnToI/9hxAEj1Dx5UdsueMCxGYsykAY0CJAIxRLJJwL1K2R1RZN4F8HLti1PN
	t3Rn3HSK8YOl7Id0VLqYGzn5TC26p3YdeJJhjVqWnYzC0okrZ4PDALBtp/uhshOHdBQWoWV77lzw
	XW2c0z94wVKJ7ToK/whV8rHx4ROzlT3rK1BEAimxiZgg9KPrutb1+fnkrauRxqPA3O11P7cmbs+Q
	ohQRqtwgQpKIGNCFQrTuhuu6Vj6fp87OTg6CoATQT0TcB4gdzRSTAGYrsXUAUmloRCQxR6Q9CE5q
	AHMAgGvA1szhFBElISJEVMfmChTLzNhBEGjEx1IAEETsygpL2XU9oRYA5Z7rntl2buJXMeZBEO1y
	MoNvAnQVbGwjbBhzBwBKg0CiMbEcwPINEDO5aSOqUtx1XYbvGyZ5j9hiIm5l236bbRWwlfhIKTXE
	luVaSllRGP5lbP4gPtcrs2qCIAi053l8+euTQ2Gp+DpANyH1wAWAMXqcGC9++9XQ744z2bDz/Rer
	40B8Nj2+ctZ/39kx8AlsuweRaTVMhhkk4D8xfe2bXC4XAuCurimTy60igDIM4zhH7Nz5Y5MAPlvm
	9jx2u7qsMtFWtwLlHTiX80MA2Jp5pV1hTXVNGolC1vcXgvjxTpP0rgAQ4Jv6WRBVz3uB9FRP/6vV
	WZDP51cMokrCyvjtyQxsJpvPMasBy1IPKzu5Pv4k1jNbj6tE8o2wBacd54jdPO2/txXNguxI9vhq
	ASDf9013xk0D6AVEALmUGwmerV3s7Ha3wOCiiLAR7AawagBiKyJBKVFETIC5DgCu6yby+bzp7OyU
	8d/abqSTtwpEibpZsGoA4jZaih+EbMRM19ls1gCQ7j7XBmhV2F+xFbfSpaajcLnKEmkKuq4COgoJ
	FW6ThIi7r5XJZKj8F4TAreYKV0Q0rw0r4xjxC2oQVXTkMoD1HEiiJKBIxAjAXQAQz/PYnN3uJhgr
	LSJGBMXFfVESEQOy0uk1M5uCoF6QAHgkzkmhaksWax0VAFLWhIVt/YNjAL0koKed/sELInSjegy1
	9BGRTUTMjOFKEiYME9FrINii5XNnp1svyYR6ASIRjI0Pn5gt79VQExIbfdTo8Hml7A5A+mIlA9SJ
	0tLCF7jd8XFF68uZyaGobeqQnWzZq3W0kZk3NhKlFpmjWNLCG8rynszAZrJs3wC9EGmpeplvkpHT
	zWU5ecK0H8Y8sJiRFhgYE30HWb5oK7+YpFKF9Iw1K0A7QsxFE/9wMWls9/dqdkf/Pbic3kP7GzED
	jtRrsYKgAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAAX0lEQVR4nGNg
	oDOor2eiTNLEMdhKyz6UJzQ0lBmuoR7KMHYIjjdyDO1F18vIwMDAYOQQksXIxFTy7z9DMwPDf0Y2
	JlaWv/9+Xjmzf+0xPPbCrcdvBWFHEudNkhRRHQAAa9chklj3CeYAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAAeElEQVR4nGNg
	GABQX89EkiJGmEDotWuMV18xcHIx/dM7s3/tMQaGeiYGhsZ/GJqN7UN7jOxDEyD66pkYGRgYGEwc
	g62Ymdh1fv37/YeB4f9/Jgammv////edO7B6KgtWNzAyMDAwYpoOscIRixUkOZJwWBAVUFQFAJlm
	MPpdPKyHAAAAAElFTkSuQmCC
}]

} ;# namespace 8x16
} ;# namespace icon
} ;# namespace twm

# vi:set ts=3 sw=3:

# Sash coordinates are session-only, never attributes in the saved layout.
proc twm::ZoomSashes {twm action} {
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
