# ======================================================================
# Author : $Author$
# Version: $Revision: 1529 $
# Date   : $Date: 2018-11-22 05:48:49 -0500 (Thu, 22 Nov 2018) $
# Url    : $URL$
# ======================================================================

# ======================================================================
# Copyright: (C) 2009-2018 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

namespace eval theme {

variable padding 5
variable padx 5
variable pady 5
variable padY 10
variable padX 10
variable sliderWidth 8
variable strongTtk false
variable repeatDelay 0
variable repeatInterval 0
variable useCustomStyleMenuEntries 1

variable Settings
variable Setup 1
variable ActiveBackground {}
variable DisabledMenu {}


# this should be already done in tk8.x.x/library/tk.tcl,
# but it doesn't work for any reason
switch [tk windowingsystem] {
	x11 {
		event add <<Cut>>		<Control-Key-x> <Key-F20> 
		event add <<Copy>>	<Control-Key-c> <Key-F16>
		event add <<Paste>>	<Control-Key-v> <Key-F18>
		event add <<PasteSelection>> <ButtonRelease-2>
		event add <<Undo>>	<Control-Key-z>
		event add <<Redo>>	<Control-Key-y>
	}

	win32 {
		event add <<Cut>>		<Control-Key-x> <Shift-Key-Delete>
		event add <<Copy>>	<Control-Key-c> <Control-Key-Insert>
		event add <<Paste>>	<Control-Key-v> <Shift-Key-Insert>
		event add <<PasteSelection>> <ButtonRelease-2>
		event add <<Undo>>	<Control-Key-z>
		event add <<Redo>>	<Control-Key-y>
	}

	aqua {
		event add <<Cut>>		<Command-Key-x> <Key-F2> 
		event add <<Copy>>	<Command-Key-c> <Key-F3>
		event add <<Paste>>	<Command-Key-v> <Key-F4>
		event add <<PasteSelection>> <ButtonRelease-2>
		event add <<Clear>>	<Clear>
		event add <<Undo>>	<Command-Key-z>
		event add <<Redo>>	<Command-Key-y>
	}
}

proc bindCut {w {cmd {#}}} {
	switch [tk windowingsystem] {
		x11 	{ set keys {<Control-Key-x> <Key-F20>} }
		win32	{ set keys {<Control-Key-x> <Shift-Key-Delete>} }
		aqua	{ set keys {<Control-Key-x> <Key-F2> } }
	}
	foreach key $keys {
		bind $w $key $cmd
	}
}


proc bindCopy {w {cmd {#}}} {
	switch [tk windowingsystem] {
		x11 	{ set keys {<Control-Key-c> <Key-F16>} }
		win32	{ set keys {<Control-Key-c> <Control-Key-Insert>} }
		aqua	{ set keys {<Control-Key-c> <Key-F3> } }
	}
	foreach key $keys {
		bind $w $key $cmd
	}
}


proc bindPaste {w {cmd {#}}} {
	switch [tk windowingsystem] {
		x11 	{ set keys {<Control-Key-v> <Key-F18>} }
		win32	{ set keys {<Control-Key-v> <Shift-Key-Insert>} }
		aqua	{ set keys {<Control-Key-v> <Key-F4> } }
	}
	foreach key $keys {
		bind $w $key $cmd
	}
}


proc bindUndo {w {cmd {#}}} {
	foreach key {<Control-Key-z> <Control-Key-Z>} {
		bind $w $key $cmd
	}
}


proc bindRedo {w {cmd {#}}} {
	foreach key {<Control-Key-y> <Control-Key-Y>} {
		bind $w $key $cmd
	}
}


proc bindPasteSelection {w {cmd {#}}} {
	bind $w <ButtonRelease-2> $cmd
}


event add <<ControlOn>>		<KeyPress-Control_L>    <KeyPress-Control_R>
event add <<ControlOff>>	<KeyRelease-Control_L>	<KeyRelease-Control_R>
event add <<ShiftOn>>		<KeyPress-Shift_L>		<KeyPress-Shift_R>
event add <<ShiftOff>>		<KeyRelease-Shift_L>		<KeyRelease-Shift_R>


switch $::tcl_platform(platform) {
	unix			{ event add <<Cancel>> <Control-c> <Escape> }
	windows		{ event add <<Cancel>> <Escape> }
	macintosh	{ event add <<Cancel>> <Command-period> }
}


# This is not working under older Tk versions.
#proc currentTheme {} { return [ttk::style theme use] }
proc currentTheme {} { return $::ttk::currentTheme }


proc isDark {} {
	return [expr {[currentTheme] eq "dark"}]
}


proc getToplevelBackground {} {
	return [set [namespace current]::Settings(tk:background)]
}


proc getColor {which} {
	switch $which {
		disabled {
			return [ttk::style lookup [currentTheme] -foreground disabled]
		}

		activebackground {
			if {[isDark]} {
				return "#353c4a"
			}
			# for any reason the correct implementation is not
			# working, so I'm using a workaround
			return #efefef
		}
	}

	return [ttk::style lookup [currentTheme] -$which]
}


proc setTheme {name} {
	variable Setup

	if {$name ne [currentTheme] || $Setup} {
		::ttk::setTheme $name
		SetupCurrentTheme
		set Setup 0
	}
}


proc configureCanvas {canv} {
	configureBackground $canv
	bind $canv <<ThemeChanged>> [namespace code [list configureBackground $canv]]
}


proc configurePanedWindow {win} {
	$win configure -background [GetTroughColor]
}


proc configureSpinbox {sbox} {
	if {[winfo class $sbox] eq "Spinbox"} {
		$sbox configure -relief sunken
		ConfigureSpinboxBackground $sbox
		bind $sbox <<ThemeChanged>> [namespace code [list ConfigureSpinboxBackground $sbox]]
	}
}


proc enableScale {scale {enable true}} {
	if {$enable} {
		$scale configure \
			-foreground [::ttk::style lookup [currentTheme] -foreground] \
			-troughcolor [GetTroughColor] \
			-state normal
	} else {
		disableScale $scale
	}
}


proc configureCheckEntry {menu {index end}} {
	variable useCustomStyleMenuEntries

	set entry [$menu index $index]
	set text [$menu entrycget $entry -label]
	if {[string index $text 0] ne " "} {
		$menu entryconfigure $entry -label " $text"
	}

	if {$useCustomStyleMenuEntries} {
		set img [$menu entrycget $entry -image]
		if {[string length $img] == 0} {
			# TODO: using 14x14 is only a work-around, because the menu is adding
			# an extra pixel, otherwise 16x16 should be preferred.
			$menu entryconfigure $entry \
				-image $icon::14x14::checkNo \
				-selectimage $icon::14x14::checkYes \
				-compound left \
				-indicatoron no \
				;
		} else {
			variable Icons
			if {![info exists Icons($img)]} {
				set y [expr {(16 - [image height $img])/2}]
				set imgOff [image create photo -width 36 -height 16]
				$imgOff copy $icon::16x16::checkNo -to 0 0
				$imgOff copy $img -to 20 $y
				set imgOn [image create photo -width 36 -height 16]
				$imgOn blank
				$imgOn copy $img -to 20 $y
				$imgOn copy $icon::16x16::checkYes -to 0 0
				set Icons($img) [list $imgOff $imgOn]
			} else {
				lassign $Icons($img) imgOff imgOn
			}
			$menu entryconfigure $entry -indicatoron off -image $imgOff -selectimage $imgOn -compound left
		}
	}
}

proc configureRadioEntry {menu {index end}} {
	variable useCustomStyleMenuEntries

	set entry [$menu index $index]

	if {$useCustomStyleMenuEntries} {
		set text [$menu entrycget $entry -label]
		if {[string index $text 0] ne " "} {
			$menu entryconfigure $entry -label " $text"
		}
		set img [$menu entrycget $entry -image]
		if {[string length $img] == 0} {
			# TODO: using 14x14 is only a work-around, because the menu is adding
			# an extra pixel, otherwise 16x16 should be preferred.
			$menu entryconfigure $entry \
				-indicatoron off \
				-image $icon::14x14::radioOff \
				-selectimage $icon::14x14::radioOn \
				-compound left \
				;
		} else {
			variable Icons
			if {![info exists Icons($img)]} {
				set y [expr {(16 - [image height $img])/2}]
				set imgOff [image create photo -width 36 -height 16]
				$imgOff copy $icon::16x16::radioOff -to 0 0
				$imgOff copy $img -to 20 $y
				set imgOn [image create photo -width 36 -height 16]
				$imgOn copy $icon::16x16::radioOn -to 0 0
				$imgOn copy $img -to 20 $y
				set Icons($img) [list $imgOff $imgOn]
			} else {
				lassign $Icons($img) imgOff imgOn
			}
			$menu entryconfigure $entry -indicatoron off -image $imgOff -selectimage $imgOn -compound left
		}
	} else {
		$menu entryconfigure $entry \
			-indicatoron off \
			-image $::icon::15x15::none \
			-selectimage $icon::15x15::Dot \
			-compound left \
			;
	}
}


proc disableScale {scale} {
	$scale configure -state disabled
	ConfigureScaleBackground $scale
}


proc configureDefaultButton {but} {
	$but configure -default active
}


proc configureBackground {w} {
	$w configure -background [::ttk::style lookup [currentTheme] -background]
}


proc notebookBorderwidth {} {
	switch [currentTheme] {
		alt { return 1 }
		clam - clearlooks - scidblue - dark { return 2 }
	}
	set result [ttk::style lookup TNotebook -borderwidth]
	if {[string is integer -strict $result]} { return $result }
	return 1
}


proc notebookTabPaneSize {nb} {
	set padding [ttk::style lookup TNotebook.Tab -padding]
	if {[llength $padding] == 0} {
		puts stderr "\[ttk::style lookup TNotebook.Tab -padding\] returns empty list for '[currentTheme]'"
		set padding {2 2}
	}
	set size [expr {2*[notebookBorderwidth] + 1}] ;# plus one overlapping pixel
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
	set linespace [font metrics $font -linespace]
	set haveImage 0
	foreach tab [$nb tabs] {
		if {[string length [set img [$nb tab $tab -image]]]} {
			set linespace [expr {max($linespace, [image height $img])}]
			set haveImage 1
		}
	}
	incr size $haveImage
	incr size $linespace
#	if {	[string length [$nb select]]
#		&& [set ht [expr {[winfo height $nb] - [winfo height [$nb select]]}]] > 1
#		&& $ht != $size} { puts stderr "notebookTabPaneSize($nb): computed=$size, but measured=$ht" }
	return $size
}


proc SetupCurrentTheme {} {
	variable strongTtk
	variable Settings

	# 1. Makes a correction of read-only state color. Read-Only does not mean disabled!
	set fbg {}
	switch "_[currentTheme]" {
		_alt		{ set fbg [list readonly white disabled [ttk::style lookup [currentTheme] -background]] }
		_clam		{ set fbg [list \
									readonly white \
									{readonly focus} [::ttk::style lookup [currentTheme] -selectbackground]] }
		_default	{ set fbg [list readonly white disabled [ttk::style lookup [currentTheme] -background]] }
		_dark		{ set fbg [list \
									readonly #2b303b \
									{readonly focus} #2f6feb \
									disabled #1f2329] }
	}
	if {[llength $fbg]} {
		ttk::style map TCombobox -fieldbackground $fbg
		ttk::style map TEntry -fieldbackground $fbg
		if {[info tclversion] >= "8.6"} {
			ttk::style map TSpinbox -fieldbackground $fbg
		}
	}

	# adjust padding of arrows in spinbox (the default padding is quite ugly)
	switch "_[currentTheme]" {
		_alt - _clam - _default - _dark { ttk::style configure TSpinbox -padding {2 0 2 0} }
		_clearlooks - _scidblue { ttk::style configure TSpinbox -padding {2 0 2 0} }
	}

	# get current settings
	set background [::ttk::style lookup [currentTheme] -background]
	set foreground [::ttk::style lookup [currentTheme] -foreground]
	if {[string length $foreground] == 0} { set foreground #000000 }
	set selectbg [::ttk::style lookup [currentTheme] -selectbackground]
	set selectfg [::ttk::style lookup [currentTheme] -selectforeground]
	set disabledfg [::ttk::style lookup [currentTheme] -foreground disabled]
	if {[string length $disabledfg] == 0} { set disabledfg #808080 }

	if {![isDark]} { RestoreLightOptions }
	if {[isDark]} {
		set Settings(tk:background) $background
		set fieldbg #1b1f27
		set activebg #353c4a
		set activefg $foreground
		set controlbg #2b303b
		set bordercol #30363d
	} else {
		set f [tk::frame .__hopefully_unique_widget_id__[clock milliseconds]]
		set Settings(tk:background) [$f cget -background]
		destroy $f
		set fieldbg #ffffff
		set activebg #ececec
		set activefg #000000
		set controlbg $background
		set bordercol $background
	}

	# 2a. Provide a left aligned button.
	ttk::style configure aligned.TButton -anchor w -width -9
	# 2b. Provide a button for icons.
	ttk::style configure icon.TButton -padding 0
	# 2c. Tree rows fit the font (Tk's default is a fixed 20 pixels, which
	#     clips the rows on a high-resolution screen).
	ttk::style configure Treeview -rowheight [expr {[font metrics TkDefaultFont -linespace] + 4}]

	# 3. Provide a ttk::scale with keyboard focus.
	ttk::style configure active.Horizontal.TScale -troughcolor [GetActiveTroughColor]
	ttk::style configure active.Vertical.TScale -troughcolor [GetActiveTroughColor]

	if {[isDark]} {
		variable DarkOptions
		set DarkOptions {}
		# 4. Set theme options in Tk option database for classic Tk widgets
		DarkOption *Spinbox.selectBackground $selectbg
		DarkOption *Spinbox.selectForeground $selectfg
		DarkOption *Spinbox.disabledBackground $background
		DarkOption *Spinbox.disabledForeground $disabledfg
		DarkOption *Spinbox.background $fieldbg
		DarkOption *Spinbox.foreground $foreground
		DarkOption *Spinbox.insertBackground $foreground
		DarkOption *Spinbox.buttonBackground $controlbg

		DarkOption *Entry.selectBackground $selectbg
		DarkOption *Entry.selectForeground $selectfg
		DarkOption *Entry.disabledBackground $background
		DarkOption *Entry.disabledForeground $disabledfg
		DarkOption *Entry.readonlyBackground $background
		DarkOption *Entry.background $fieldbg
		DarkOption *Entry.foreground $foreground
		DarkOption *Entry.insertBackground $foreground

		DarkOption *Scale.highlightBackground $background
		DarkOption *Scale.background $background
		DarkOption *Scale.foreground $foreground
		DarkOption *Scale.activeBackground $activebg
		DarkOption *Scale.troughColor [GetTroughColor]

		DarkOption *Listbox.background $fieldbg
		DarkOption *Listbox.foreground $foreground
		DarkOption *Listbox.selectBackground $selectbg
		DarkOption *Listbox.selectForeground $selectfg
		DarkOption *Listbox.disabledForeground $disabledfg
		DarkOption *Listbox.highlightBackground $background

		DarkOption *TCombobox*Listbox.background $fieldbg
		DarkOption *TCombobox*Listbox.foreground $foreground
		DarkOption *TCombobox*Listbox.selectBackground $selectbg
		DarkOption *TCombobox*Listbox.selectForeground $selectfg

		DarkOption *Text.background $fieldbg
		DarkOption *Text.foreground $foreground
		DarkOption *Text.selectBackground $selectbg
		DarkOption *Text.selectForeground $selectfg
		DarkOption *Text.insertBackground $foreground
		DarkOption *Text.highlightBackground $background

		DarkOption *Menu.background $background
		DarkOption *Menu.foreground $foreground
		DarkOption *Menu.activeBackground $selectbg
		DarkOption *Menu.activeForeground $selectfg
		DarkOption *Menu.disabledForeground $disabledfg
		DarkOption *Menu.selectColor $foreground

		DarkOption *Menubutton.background $background
		DarkOption *Menubutton.foreground $foreground
		DarkOption *Menubutton.activeBackground $activebg
		DarkOption *Menubutton.activeForeground $activefg
		DarkOption *Menubutton.disabledForeground $disabledfg
		DarkOption *Menubutton.highlightBackground $background

		DarkOption *Button.background $controlbg
		DarkOption *Button.foreground $foreground
		DarkOption *Button.activeBackground $activebg
		DarkOption *Button.activeForeground $activefg
		DarkOption *Button.disabledForeground $disabledfg
		DarkOption *Button.highlightBackground $background

		DarkOption *Checkbutton.background $background
		DarkOption *Checkbutton.foreground $foreground
		DarkOption *Checkbutton.activeBackground $activebg
		DarkOption *Checkbutton.activeForeground $activefg
		DarkOption *Checkbutton.disabledForeground $disabledfg
		DarkOption *Checkbutton.selectColor $fieldbg
		DarkOption *Checkbutton.highlightBackground $background

		DarkOption *Radiobutton.background $background
		DarkOption *Radiobutton.foreground $foreground
		DarkOption *Radiobutton.activeBackground $activebg
		DarkOption *Radiobutton.activeForeground $activefg
		DarkOption *Radiobutton.disabledForeground $disabledfg
		DarkOption *Radiobutton.selectColor $fieldbg
		DarkOption *Radiobutton.highlightBackground $background

		DarkOption *Label.background $background
		DarkOption *Label.foreground $foreground
		DarkOption *Label.disabledForeground $disabledfg
		DarkOption *Label.highlightBackground $background

		DarkOption *Message.background $background
		DarkOption *Message.foreground $foreground
		DarkOption *Message.highlightBackground $background

		DarkOption *Labelframe.background $background
		DarkOption *Labelframe.foreground $foreground
		DarkOption *Labelframe.highlightBackground $background

		DarkOption *Frame.background $Settings(tk:background)
		DarkOption *Frame.highlightBackground $Settings(tk:background)
		DarkOption *Toplevel.background $Settings(tk:background)
		DarkOption *Toplevel.highlightBackground $Settings(tk:background)
		DarkOption *Dialog.background $Settings(tk:background)
		DarkOption *Dialog.highlightBackground $Settings(tk:background)
		if {[info exists ::scidb::app] && [string length $::scidb::app]} {
			DarkOption *$::scidb::app.background $Settings(tk:background)
			DarkOption *$::scidb::app.highlightBackground $Settings(tk:background)
		}
		DarkOption *Canvas.background $background
		DarkOption *Canvas.highlightBackground $background
		DarkOption *Panedwindow.background [GetTroughColor]
		DarkOption *TreeCtrl.background $fieldbg
		DarkOption *TreeCtrl.foreground $foreground

		foreach {pattern value} $DarkOptions { SaveLightOption $pattern }
		foreach {pattern value} $DarkOptions { option add $pattern $value }

	} else {
		RestoreLightOptions
		# 4. Set theme options
	#	option add *Frame.background $Settings(tk:background)
	#	option add *Button.background $background
		option add *Spinbox.selectBackground [::ttk::style lookup [currentTheme] -selectbackground]
		option add *Spinbox.disabledBackground $background
		option add *Entry.selectBackground [::ttk::style lookup [currentTheme] -selectbackground]
		option add *Scale.highlightBackground $background
		option add *Scale.background $background
		option add *Scale.troughColor [GetTroughColor]
		option add *Listbox.disabledForeground [::ttk::style lookup [currentTheme] -foreground disabled]
	#	option add *Listbox.selectBackground [::ttk::style lookup [currentTheme] -selectbackground]
	#	option add *Listbox.selectForeground [::ttk::style lookup [currentTheme] -selectforeground]
	#	option add *Panedwindow.background [GetTroughColor]

		if {$strongTtk} {
			option add *Frame.background $background
			option add *Toplevel.background $background
			option add *Dialog.background $background
			option add *Label.background $background
			option add *Canvas.background $background
			option add *Notebook.background $background
		}
	}

	ApplyThemeToWidgetTree .
}


# Save the effective light defaults before adding any dark resources. Tk has no
# option-delete operation, so restore the saved values on the return to light.
proc SaveLightOption {pattern} {
	variable LightOptions
	if {![info exists LightOptions($pattern)]} {
		regexp {\*([^*.]+)\.([^.]*)$} $pattern -> cls resource
		set command [string tolower $cls]
		if {$cls eq "TreeCtrl"} { set command treectrl }
		if {[info commands ::tk::$command] ne ""} { set command ::tk::$command }
		set probe .__theme_defaults
		if {[catch {$command $probe}]} { tk::frame $probe -class $cls }
		set opt -[string tolower $resource]
		if {[catch {$probe cget $opt} prior]} {
			set prior [$probe cget -background]
		}
		set LightOptions($pattern) $prior
		destroy $probe
	}
}

proc DarkOption {pattern value} {
	variable DarkOptions
	lappend DarkOptions $pattern $value
}

proc RestoreLightOptions {} {
	variable LightOptions
	if {[info exists LightOptions]} {
		foreach {pattern value} [array get LightOptions] { option add $pattern $value }
		unset LightOptions
	}
}

# New refresh handlers have no work on an untouched light widget. Remember
# dark use per widget, and discard the marker when the widget is destroyed.
proc needsPaletteRefresh {w} {
	variable DarkWidgets
	if {![winfo exists $w]} { return 0 }
	if {[isDark]} {
		if {![info exists DarkWidgets($w)]} {
			bind $w <Destroy> +[list unset -nocomplain [namespace current]::DarkWidgets($w)]
		}
		set DarkWidgets($w) 1
		return 1
	}
	if {[info exists DarkWidgets($w)]} {
		unset DarkWidgets($w)
		return 1
	}
	return 0
}

proc ForgetLightWidget {w destroyed} {
	if {$w ne $destroyed} { return }
	variable LightWidgets
	variable LightMenuEntries
	unset -nocomplain LightWidgets($w) LightMenuEntries($w)
}

proc ApplyThemeToWidgetTree {root} {
	if {![winfo exists $root]} { return }
	variable Settings

	variable LightWidgets
	variable LightMenuEntries
	if {![isDark]} {
		if {[info exists LightMenuEntries]} {
			foreach {w entries} [array get LightMenuEntries] {
				if {![winfo exists $w]} { continue }
				foreach {index label options} $entries {
					catch {
						if {[$w entrycget $index -label] eq $label} { $w entryconfigure $index {*}$options }
					}
				}
			}
			unset LightMenuEntries
		}
		if {[info exists LightWidgets]} {
			foreach {w options} [array get LightWidgets] {
				if {[winfo exists $w]} { catch { $w configure {*}$options } }
			}
			unset LightWidgets
		}
		return
	}
	set background [::ttk::style lookup [currentTheme] -background]
	set foreground [::ttk::style lookup [currentTheme] -foreground]
	if {[string length $foreground] == 0} { set foreground #000000 }
	set selectbg [::ttk::style lookup [currentTheme] -selectbackground]
	set selectfg [::ttk::style lookup [currentTheme] -selectforeground]
	set disabledfg [::ttk::style lookup [currentTheme] -foreground disabled]
	if {[string length $disabledfg] == 0} { set disabledfg #808080 }

	set tkbg $background
	set fieldbg #1b1f27
	set activebg #353c4a
	set activefg $foreground
	set controlbg #2b303b

	set stack [list $root]
	while {[llength $stack]} {
		set w [lindex $stack end]
		set stack [lrange $stack 0 end-1]
		if {![winfo exists $w]} { continue }

		foreach child [winfo children $w] {
			lappend stack $child
		}

		set saveWidget [expr {![info exists LightWidgets($w)]}]
		if {$saveWidget} {
			set LightWidgets($w) {}
			if {[catch {$w configure} specs]} { continue }
			foreach spec $specs {
				if {[llength $spec] == 5 && [regexp -nocase {color|background|foreground} [lindex $spec 0]]} {
					lappend LightWidgets($w) [lindex $spec 0] [lindex $spec 4]
				}
			}
			bind $w <Destroy> +[namespace code [list ForgetLightWidget $w %W]]
		}
		set cls [winfo class $w]
		if {[winfo toplevel $w] eq $w && $cls ni {Toplevel Dialog Frame}} {
			catch {
				$w configure -background $tkbg -highlightbackground $tkbg
			}
		}
		switch $cls {
			Toplevel -
			Dialog -
			Toolbar -
			ToolbarFrame -
			ToolbarHandle -
			ToolbarSeparator -
			TwmFrame -
			TwmMetaframe -
			Frame {
				catch {
					set curbg [$w cget -background]
					# Do not clobber explicit 1px border frames (#a0a0a0, gray50, black, etc.) unless they are standard light/dark backgrounds
					if {$curbg in [list #d9d9d9 #ececec #f0f0f0 #efefef #e5e5e5 #dce4e5 #ebf4f5 #f6f6f6 #fafafa #23272e #1b1f27 #2b303b $Settings(tk:background)] || [winfo toplevel $w] eq $w || $cls in {Toolbar ToolbarFrame ToolbarHandle ToolbarSeparator} || [string match ".*.__tb*__" $w]} {
						$w configure -background $tkbg
					}
					$w configure -highlightbackground $tkbg
				}
			}
			TreeCtrl {
				catch {
					set curbg [$w cget -background]
					if {$curbg in {white #ffffff #ffffee #f5f5f5 #f5f5e4 #d9d9d9 #ececec #1b1f27 #23272e #282e38}} {
						$w configure -background $fieldbg
					}
					$w configure -foreground $foreground
				}
			}
			Canvas {
				catch {
					if {[string match "*.handle*.c" $w]} {
						$w configure -background $tkbg -highlightbackground $tkbg
						::toolbar::ConfigureHandle [winfo parent $w] [winfo width $w] [winfo height $w]
					}
				}
			}
			Labelframe {
				catch {
					$w configure -background $background -foreground $foreground -highlightbackground $background
				}
			}
			Menu {
				catch {
					$w configure \
						-background $background \
						-foreground $foreground \
						-activebackground $selectbg \
						-activeforeground $selectfg \
						-disabledforeground $disabledfg \
						-selectcolor $foreground
					set endIdx [$w index end]
					if {$endIdx ne "none"} {
						for {set i 0} {$i <= $endIdx} {incr i} {
							set etype [$w type $i]
							if {$etype in {command checkbutton radiobutton cascade}} {
								catch {
									set ebg [$w entrycget $i -background]
									if {$ebg ne ""} {
									if {$saveWidget} {
										set entryOptions {}
										foreach opt {-background -foreground -activebackground -activeforeground} {
											lappend entryOptions $opt [$w entrycget $i $opt]
										}
										lappend LightMenuEntries($w) $i [$w entrycget $i -label] $entryOptions
									}
										$w entryconfigure $i \
											-background [::colors::lookup table,menu:headerbackground] \
											-foreground [::colors::lookup table,menu:headerforeground] \
											-activebackground [::colors::lookup table,menu:headerbackground] \
											-activeforeground [::colors::lookup table,menu:headerforeground]
									}
								}
							}
						}
					}
				}
			}
			Menubutton {
				catch {
					$w configure \
						-background $background \
						-foreground $foreground \
						-activebackground $activebg \
						-activeforeground $activefg \
						-disabledforeground $disabledfg \
						-highlightbackground $background
				}
			}
			Label -
			Message {
				catch {
					set curbg [$w cget -background]
					if {$curbg in [list #d9d9d9 #e0e0e0 #ececec #f0f0f0 #efefef #e5e5e5 #dce4e5 #ebf4f5 #f6f6f6 #fafafa white #ffffff #23272e #1b1f27 #2b303b $Settings(tk:background)] || [string match "*.__tb*" $w]} {
						$w configure -background $background
					}
					set curfg [$w cget -foreground]
					if {$curfg in {black #000000 #333333 #e6edf3 white #ffffff} || [string match "*.__tb*" $w]} {
						$w configure -foreground $foreground
					}
					$w configure -highlightbackground $background
				}
			}
			Button {
				catch {
					$w configure \
						-background $controlbg \
						-foreground $foreground \
						-activebackground $activebg \
						-activeforeground $activefg \
						-disabledforeground $disabledfg \
						-highlightbackground $background
				}
			}
			Checkbutton -
			Radiobutton {
				catch {
					$w configure \
						-background $background \
						-foreground $foreground \
						-activebackground $activebg \
						-activeforeground $activefg \
						-disabledforeground $disabledfg \
						-selectcolor $fieldbg \
						-highlightbackground $background
				}
			}
			Entry {
				catch {
					$w configure \
						-background $fieldbg \
						-foreground $foreground \
						-insertbackground $foreground \
						-selectbackground $selectbg \
						-selectforeground $selectfg \
						-disabledbackground $background \
						-disabledforeground $disabledfg \
						-readonlybackground $background \
						-highlightbackground $background
				}
			}
			Spinbox {
				catch {
					$w configure \
						-background $fieldbg \
						-foreground $foreground \
						-insertbackground $foreground \
						-buttonbackground $controlbg \
						-selectbackground $selectbg \
						-selectforeground $selectfg \
						-disabledbackground $background \
						-disabledforeground $disabledfg \
						-readonlybackground $background \
						-highlightbackground $background
				}
			}
			Listbox {
				catch {
					$w configure \
						-background $fieldbg \
						-foreground $foreground \
						-selectbackground $selectbg \
						-selectforeground $selectfg \
						-disabledforeground $disabledfg \
						-highlightbackground $background
				}
			}
			Text {
				catch {
					set curbg [$w cget -background]
					if {$curbg in {white #ffffff #ffffee #f5f5f5 #f5f5e4 #d9d9d9 #ececec #1b1f27 #23272e #282e38}} {
						$w configure -background $fieldbg
					}
					$w configure \
						-foreground $foreground \
						-insertbackground $foreground \
						-selectbackground $selectbg \
						-selectforeground $selectfg \
						-highlightbackground $background
				}
			}
			Scale {
				catch { ConfigureScaleBackground $w }
			}
			Panedwindow {
				catch { $w configure -background [GetTroughColor] }
			}
		}
	}
}


proc ConfigureListbox {list} {
	$list configure \
		-disabledforeground [::ttk::style lookup [currentTheme] -foreground disabled]
#		-selectbackground [::ttk::style lookup [currentTheme] -selectbackground]
#		-selectforeground [::ttk::style lookup [currentTheme] -selectforeground]
}


proc ConfigureSpinboxBackground {sbox} {
	set borderwidth 1
	switch "_[currentTheme]" { _alt { set borderwidth 2 } }

	$sbox configure \
		-buttonbackground [::ttk::style lookup [currentTheme] -background] \
		-selectbackground [::ttk::style lookup [currentTheme] -selectbackground] \
		-disabledbackground [::ttk::style lookup [currentTheme] -background] \
		-borderwidth $borderwidth
}


proc ConfigureScaleBackground {scale} {
	set background [::ttk::style lookup [currentTheme] -background]

	if {[$scale cget -state] eq "disabled"} {
		$scale configure \
			-foreground [getColor disabled] \
			-highlightbackground $background \
			-background $background \
			-troughcolor $background
	} else {
		$scale configure \
			-highlightbackground $background \
			-background $background \
			-troughcolor [GetTroughColor]
	}
}


proc GetTroughColor {} {
	variable Settings

	switch "_[currentTheme]" {
		_aqua			-
		_winnative	-
		_xpnative	{
			if {![info exists Settings([currentTheme]:troughcolor)]} {
				set sc [tk::scale .__hopefully_unique_widget_id__[clock milliseconds]]
				set Settings([currentTheme]:troughcolor) [$sc cget -troughcolor]
				destroy $sc
			}

			return $Settings([currentTheme]:troughcolor)
		}
	}

	return [::ttk::style lookup [currentTheme] -troughcolor]
}


proc GetActiveTroughColor {} {
	return [::ttk::style lookup [currentTheme] -selectbackground]
}


proc ListboxHome {w} {
	switch [$w cget -selectmode] {
		single {
			$w activate 0
			$w see 0
		}
		browse {
			$w selection clear 0 end
			$w selection set 0
			$w activate 0
			$w see 0
		}
		default {
			return -code error "ListboxHome not implemented for select mode [$w cget -selectmode]"
		}
	}
}


proc ListboxEnd {w} {
	switch [$w cget -selectmode] {
		single {
			$w activate end
			$w see end
		}
		browse {
			$w selection clear 0 end
			$w selection set end
			$w activate end
			$w see end
		}
		default {
			return -code error "ListboxEnd not implemented for select mode [$w cget -selectmode]"
		}
	}
}


proc ListboxNext {w} {
	if {[$w cget -selectmode] eq "extended"} {
		return -code error "ListboxNext not implemented for select mode 'extended'"
	}
	set index [$w nearest 0]
	set active [$w index active]
	set font [$w cget -font]
	if {[string length $font] == 0} { set font TkDefaultFont }
	set linespace [expr {[font metrics $font -linespace] + 1}]
	set nrows [expr {[winfo height $w]/$linespace}]
	set last [expr {$index + $nrows - 1}]
	if {$last == $active} {
		$w yview scroll +1 pages
		$w yview scroll +1 units
	}
	$w activate @0,10000
	if {[$w cget -selectmode] eq "browse"} {
		$w selection clear 0 end
		$w selection set [$w index active]
		event generate $w <<ListboxSelect>>
	}
}


proc ListboxPrior {w} {
	if {[$w cget -selectmode] eq "extended"} {
		return -code error "ListboxPrior not implemented for select mode 'extended'"
	}
	set index [$w index active]
	if {$index eq ""} { return }
	if {[$w bbox $index] ne ""} {
		set bbox [$w bbox [expr {$index - 1}]]
		if {$bbox eq ""} {
			$w yview scroll -1 pages
			$w yview scroll -2 units
		}
	}
	$w activate @0,0
	if {[$w cget -selectmode] eq "browse"} {
		$w selection clear 0 end
		$w selection set [$w index active]
		event generate $w <<ListboxSelect>>
	}
}


proc ListboxUpDown {w dir} {
	if {[$w cget -selectmode] eq "extended"} {
		return -code error "ListboxUpDown not implemented for select mode 'extended'"
	}
	set index [$w index active]
	if {$index eq ""} { return }
	set bbox [$w bbox $index]
	if {$bbox eq ""} {
		if {$dir == -1} {
			$w activate @0,10000
		} else {
			$w activate @0,0
		}
	} else {
		$w activate [expr {$index + $dir}]
		$w see active
	}
	if {[$w cget -selectmode] eq "browse"} {
		$w selection clear 0 end
		$w selection set [$w index active]
		event generate $w <<ListboxSelect>>
	}
}


proc ScaleMove {scale delta} {
	$scale set [expr {[$scale get] + $delta}]
}


proc ScaleJump {scale x y} {
	set curr [$scale get]
	set next [$scale get $x $y]

	if {$next < $curr} {
		$scale set [$scale cget -from]
	} elseif {$next > $curr} {
		$scale set [$scale cget -to]
	}
}


proc ScaleTakeFocus {scale} {
	if {[$scale cget -takefocus] && [$scale cget -state] ne "disabled"} { focus $scale }
}


proc ComboboxSelected {w} {
	# theme "clam" has a bug, we cannot clear the selection
	if {[currentTheme] ne "clam"} { $w selection clear }
}

option add *background #efefef
option add *inactiveSelectBackground darkgrey
option add *inactiveSelectForeground white

option add *Spinbox.background white
option add *Spinbox.foreground black
option add *Spinbox.selectForeground white
option add *Spinbox.readonlyBackground white

option add *Entry.foreground black
option add *Entry.selectForeground black
option add *Entry.readonlyBackground white
#option add *Entry.selectBackground #678db2

option add *Listbox.background white
option add *Listbox.foreground black
option add *Listbox.selectBorderWidth 0
option add *Listbox.activeStyle none
option add *Listbox.selectBackground #2b73af
option add *Listbox.selectForeground white

option add *Panedwindow.sashWidth 3
option add *Panedwindow.sashRelief flat

option add *Menu.tearOff 0
option add *Menu.foreground black
option add *Menu.activeBackground #2b73af
option add *Menu.activeForeground white
option add *Menu.activeBorderWidth 0

option add *Text.background white
option add *Text.foreground black
#option add *Text.selectBackground #678db2

option add *Label.foreground black
option add *Labelframe.foreground black

option add *Button.foreground black
option add *Button.highlightThickness 0

option add *Radiobutton.foreground black
option add *Checkbutton.foreground black
option add *Menubutton.foreground black

option add *Canvas.highlightThickness 0

option add *Scale.foreground black

option add *TreeCtrl.highlightThickness 0
option add *TreeCtrl.foreground black

option add *TButton.foreground black
option add *TRadiobutton.foreground black
option add *TCheckbutton.foreground black
option add *TMenubutton.foreground black
option add *TLabel.foreground black
option add *TScale.foreground black
option add *TNotebook.foreground black

option add *TCombobox.exportSelection 0 ;# fixing a bug with -exportselection
option add *TCombobox.foreground black

option add *TSpinbox.wrap 0
option add *TSpinbox.foreground black

option add *TEntry.exportSelection 0 ;# fixing a bug with -exportselection
option add *TEntry.background white
option add *TEntry.foreground black
#option add *TEntry.selectBackground #678db2
#option add *TEntry.cursor xterm

#option add *Combobox.cursor xterm

bind Listbox <Home>	[namespace code { ListboxHome %W }]
bind Listbox <End>	[namespace code { ListboxEnd %W }]
bind Listbox <Next>	[namespace code { ListboxNext %W }]
bind Listbox <Prior>	[namespace code { ListboxPrior %W }]
bind Listbox <Up>		[namespace code { ListboxUpDown %W -1 }]
bind Listbox <Down>	[namespace code { ListboxUpDown %W +1 }]

bind Scale <Button-1>	+[namespace code { ScaleTakeFocus %W }]
bind Scale <FocusIn>		+[namespace code { %W configure -troughcolor [GetActiveTroughColor] }]
bind Scale <FocusOut>	+[namespace code { %W configure -troughcolor [GetTroughColor] }]

bind Spinbox <FocusIn>  {+ if {[%W cget -state] eq "normal"} { %W selection range 0 end } }
bind Spinbox <FocusOut> {+ if {![%W cget -exportselection]} { %W selection clear } }

#bind TSpinbox <FocusIn>  {+ %W instate {!readonly !disabled} { %W selection range 0 end } }
bind TSpinbox <FocusOut> {+ if {![%W cget -exportselection]} { %W selection clear } }

bindRedo Text { catch { %W edit redo } }

# TODO: probably we want to override <Ctrl-A> of text/entry/ttk::entry

bind TCombobox <<ComboboxSelected>> +[namespace code { ComboboxSelected %W }]
# idle: the combobox may be gone by then (its dialog closed)
bind TCombobox <FocusOut> {+ after idle { if {[winfo exists %W] && ![%W cget -exportselection]} { %W selection clear } } }
bind TCombobox <B1-Leave> { break }	;# avoid AutoScroll (bug in Tk)

bind TEntry <FocusOut> {+ if {![%W cget -exportselection]} { %W selection clear } }

# change readonly behavior of ttk::entry

bind TEntry <ButtonPress-2> {
	%W instate {!readonly !disabled} { ttk::entry::ScanMark %W %x }
}
bind TEntry <Shift-ButtonPress-1> {
	%W instate {!readonly !disabled} { ttk::entry::Shift-Press %W %x }
}
bind TEntry <Double-ButtonPress-1> {
	%W instate {!readonly !disabled} { ttk::entry::Select %W %x word }
}
bind TEntry <Triple-ButtonPress-1> {
	%W instate {!readonly !disabled} { ttk::entry::Select %W %x line }
}
bind TEntry <<TraverseIn>> {
	%W instate {!readonly !disabled} {
		%W selection range 0 end
		%W icursor end
	}
}
bind TEntry <Control-Key-slash> {
	%W instate {!readonly !disabled} {
		%W selection range 0 end
	}
}

# an entry should have a xterm cursor if in normal state
bind TEntry <Enter> {
	%W instate {!readonly !disabled} {
		%W configure -cursor xterm
	}
}

bind TEntry <Leave> {
	%W instate {!readonly !disabled} {
		%W configure -cursor {}
	}
}

bind THorzScale <ButtonPress-1>		[bind TScale <ButtonPress-1>]
bind THorzScale <B1-Motion>			[bind TScale <B1-Motion>]
bind THorzScale <ButtonRelease-1>	[bind TScale <ButtonRelease-1>]
bind THorzScale <Control-Button-1>	[namespace code { ScaleJump %W %x %y }]
bind THorzScale <Key-Right>			[namespace code { ScaleMove %W +1 }]
bind THorzScale <Key-Left>				[namespace code { ScaleMove %W -1 }]
bind THorzScale <Control-Right>		[namespace code { ScaleMove %W +10 }]
bind THorzScale <Control-Left>		[namespace code { ScaleMove %W -10 }]
bind THorzScale <Home>					{ %W set [%W cget -from] }
bind THorzScale <End>					{ %W set [%W cget -to] }
bind THorzScale <FocusIn>				{ %W configure -style active.Horizontal.TScale }
bind THorzScale <FocusOut>				{ %W configure -style Horizontal.TScale }
bind THorzScale <Button-1>				{+ focus %W }

bind TVertScale <ButtonPress-1>		[bind TScale <ButtonPress-1>]
bind TVertScale <B1-Motion>			[bind TScale <B1-Motion>]
bind TVertScale <ButtonRelease-1>	[bind TScale <ButtonRelease-1>]
bind THorzScale <Control-Button-1>	[namespace code { ScaleJump %W %x %y }]
bind TVertScale <Key-Down>				[namespace code { ScaleMove %W +1 }]
bind TVertScale <Key-Up>				[namespace code { ScaleMove %W -1 }]
bind THorzScale <Control-Down>		[namespace code { ScaleMove %W +10 }]
bind THorzScale <Control-Up>			[namespace code { ScaleMove %W -10 }]
bind THorzScale <Home>					{ %W set [%W cget -from] }
bind THorzScale <End>					{ %W set [%W cget -to] }
bind TVertScale <FocusIn>				{ %W configure -style active.Vertical.TScale }
bind TVertScale <FocusOut>				{ %W configure -style Vertical.TScale }
bind TVertScale <Button-1>				{+ focus %W }

bind Spinbox		<<ThemeChanged>> [namespace code [list ConfigureSpinboxBackground %W]]
bind Scale			<<ThemeChanged>> [namespace code [list ConfigureScaleBackground %W]]
bind Listbox		<<ThemeChanged>> [namespace code [list ConfigureListbox %W]]
bind Panedwindow	<<ThemeChanged>> [namespace code [list configurePanedWindow %W]]


scrollbar .__scrollbar__
set repeatDelay [.__scrollbar__ cget -repeatdelay]
set repeatInterval [.__scrollbar__ cget -repeatinterval]
destroy .__scrollbar__


namespace eval icon {
namespace eval 14x14 {

set checkYes [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABYUlEQVR4nJWS
	MUtCYRSGz7lcsKGGIEKqpaXApQwapIhsqX5AS0Gi1e6WTpdoKMiGggoKUppawhAaIoXwDmVB0JBL
	aAqWShmFeguL+7Z4xTRD3/k8h+d7z8dUZwAwETERgZnRCNRYNAiADsAgAH3lgABAqAE1ycmIw+Rd
	TSxfn7gBNJcGmVllZrX4DgLAzAwAuqtUzD59uuu8SN93vhXyrUQkaptFACYA/UREEiRB0wslHxxd
	nsV32p6Hze+RARjLlcwjR2uPk77NOwATmt5lMuLUIGvAEwQwoNmIGpv9+hSDqbBh3LexDkANpWOG
	qbM9Z0LJtFh7h+X9MYudmW8ACMyscrEAIV/4mBk6dq3cZuIdZr0hHM2+tMWV53ZrTzVUVXvuW5nt
	O1x6oi0baGcBFr9bLtP71Xh57QyAX5WcZdTris4FDs7/hf64mQDACKCbiEiSpNpQ6ZY1ltWdv35R
	ZX4AqGHu5HDt8rUAAAAASUVORK5CYII=
}]

set checkNo [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABkElEQVR4nI1S
	MWtTURg9592PNlhCqhTX0qVDKukjo4UG7NCkg/9C7ORQd0UXR0En9Ye0GQw41A6WGEtMKUVE3EQk
	IWhrefceh7zXpOUVPNO59zvn+w73uwQAScvtTnd9MDwpOBcJOfA+sFScOa3G5SbJTyZp+dGzly+a
	rferifd5nnOYGRp3VjYkPbD2QW+92dpbNXP9ytLiN+/9VBTxwtQQROfcWe/oy/z2293a3XqtboPB
	sJD4RPGtpa+vnj++B+AXAALIzBm/cX/ryZv9zud4MPxdMJICQB/8NIAfJL/nxZSUeO+nAZCkbFyi
	AJikCEAEIKSFjFuqOb+80JhkABBIhkk+ET3X+N+wS2dmUaVxqpTzCqMIIMniTWgCMHqcVDMySiIA
	Oef+ArgpyXDFOlKNJNFKpeKpOWP38Hhh8+HT18H7qXRF4ywSI+fOuofHC+aM10vFE6tWyjuNtZWN
	7dZu7cPHbhW5P3U018zQWLv9Lq6Um0w7VtqdXv1nv3/NXZqWwUucm539U43LOyQP/gHClLXY5jAL
	SgAAAABJRU5ErkJggg==
}]

set radioOn [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACcElEQVR4nHWS
	X0hTARTGz2n3DnWDuVBwOv/rNnab9qBJYBlBUSbCIJDqYahYQmz4UvniU6ELIY0ZpFPKRAuielEk
	6cEKSlwPc+6qV93QeWOGwrwwp+j09NC10uiDA9/D+Tjngx8CABARIiIxCgXsxuOFkYhUys8HswEA
	OEPeslar8bAMsxDf2/uze2CIKHlmIWBranbe8M4I5mg0pgIAUKuTNovMxpkpvzBoNuX3I+IGESHK
	F5OH348/aO96fvPHWoTVp6fEsjJ0IgBASAxniuH1xLRU7e4de233lYsVLYi4ASzLwqwQdFRU2XYs
	5VZydrqHichKRPnyWJ2d7mFLuZUqqmw7vLDoYFkWgIgK7PdaPcayamrr6Bkhohz5CwURKWSf09bR
	M2IsqyZ7c6uHiAqYSEQ6NcXPndCnp8SamxrciLhERGee9L20yyEXIn4mIveHTxPnfH6Bk6RoKcPP
	B7M3N7cTirjCeQDwERHb1Tvk6B14exUAQQ5/BQBfVoZO9PELhuk5IefYPvwrRKSD0P/EWAx5yypV
	wnboe1gPAEWIGCQi18HC7fprLkSME1FxSAzr1arELbOpYInRajWTxZzJPzY+UeLsdDcQkVfu9EW+
	vkdEua2P3A1ieD3p0vnTnuMazSSjVCoXvf7ZAR8vFA+9Ga1ExC4i6gOAabmf5eHj3vpX70Yvp6Vq
	dxvragaUSmXgNwAjYx/vt7ue3Vpdi7B6XcpWll63AgAQWglniqu/ALjrqHtaeeFsCyJKeAi5uYCt
	u//19Sle4P5G7iRn5BtrawZNhtwXR5E7BLkkRUt4IZANsA+csXBZo1F/Owr5T/7NWRRkadqzAAAA
	AElFTkSuQmCC
}]

set radioOff [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAACYUlEQVR4nH2S
	T0jTARTH39v2G+oGc6Ew/6yZqRtbyw6GBOIgKcqGf06SQUML86J0qbx4KnQhqJGH/ANlYsQGdVEq
	T3YL10HT3/SnTpQtXShuIzfFqd8u03KHHjz48nhf3pfHh4mIADAzQyGXU/zgoDAUilwWF1cMRESW
	ovw1rVbjERSKpYPDw7+7xwJAunfJ53jY5rwz7ZXMOzsxFRGRWp0WvWg2emfmpFGz6fwwM4cBMCcu
	po99mXzW1fem6ddmSMjNzojps3V+IiL/elAfWN9K02Vq449aGvpvXbe1M3OYBEGgeWml1WZ37FvL
	auHsHRwDUAOgMNE1zt7BMWtZLWx2x74oLbcKgkAEoKDlSYfHWFqFzp6BcQAGSioAhs7u/nFjaRVa
	2jo8AApoeztcX26/u1tRey8KoJqIyOVyyQHIAMhcLpc8Ya6uqGmM2uyOWDj8+7ZCXFwxRKN7KVaz
	XiIiEQATEZj5KGGQJWaiPifLP+tdMs4uSHmyo+Rc/y2cKJm1KH9NpUrZ869v6InIwsxwu918HNXt
	djMzg4gu+H8G9WpV6q7ZVLCq0Go1U8UW09zE5LcSZ89AE4AZZl5Nek5eR/dgU2BjK+3G1SueMxrN
	lEKpVC5Pz82P/BCl4ncfPleyTNYHYIiIRCJiIjI/fzF0//3HTzd1mdp4c2PdiFKp9J0AMD7x9WnX
	y9cPgpshITcrI6bPSQAQCJ4NBLdSdZna+OPWxleV18rbmTnCp5Bb8Dn6h931M6Jk+Re5Sxaj2NxQ
	N2oqOvc2GblTkEciOyWi5DMQHZHFWLim0ai/J0P+B3xJTBALJwTNAAAAAElFTkSuQmCC
}]

} ;# namespace 14x14
namespace eval 15x15 {

set None [image create photo -width 15 -height 15]

set Dot [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAA8AAAAPCAYAAAA71pVKAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABfklEQVR4nK2S
	O0hCYRTHz7ncLatrgrm1VJNQc3eJhh5ChJpDotXQFFTQFBToULT1IIgeS2WR1WAWYUGvpb05ImgK
	L14f1HY//Lco3G4SFp3lg3N+5/Hn+xP9dwBgAFIkEpEASAC46sZq82wFmBkAbETUrum60+lwaET0
	yMwf5XqZlys0tuzFz+aSqbvuXK6gNNjr8wOerisA88z8bB4gWzfGjpKzK5sHw0IIalBqjaeXV9fy
	RmyEJQaACfMFkuX8tsTFnUcYAsGAJ35/vjsU9PUdGYbA6cW1h4jazLxMRBSNRomI6E3TXLl8od6u
	1BVnJseOmTkBAKmbh0E9W1A0XW8082W9UulVfeEpza16i4ur24cA/IsrW3G36i36R6bSADrMPFs1
	75+cry2tx0aFEGRXakUu/y7LskzT4+GdUKD/i2aZiKjUyKXCAorEycvbnmy2oLQ2N2UGejuvQoH+
	hUrf9c0IAGwA1HQm4wOgAqj5yUDfBlSbrwj+ydu/iU9tjAE+iv1VPwAAAABJRU5ErkJggg==
}]

} ;# namespace 15x15

namespace eval 16x16 {

set checkYes [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABe0lEQVR4nJ2T
	vU4CURCFz8AVrTBQGOlXGyofQhNEC1/Bwmji2lhqZAlvoFEfwEBCTdDC6FsYs0Jl4QJxLz+N6N3k
	WChm1SX+THGLSb45Z87kCv5QJMUBBAAcgCLCP8FR/chmFCwiJJl4DoKluAIV1JWIDH+tTFK5um1n
	ywf+QrWkDU0OAGIAICIokLECGQtbDSmru25ra6V+5Nzo+/RTYARQ41VF5JNyQ3v23Nmej+N1Wmf7
	fqPXtklOfoiRnDLG5A2ZJ5kYzfkO7/luz7NJqvB6MDS5hWpJZ8sHvqu9HZJxknFXd3asMKzb32D1
	9igMAyO33fvUyvlJ4XptdwgA+fqh0xx4KSuZ0Rer2441PXMqIsEom5FNATDR7Hc2lmtHxcbAS88n
	My0Rodt/yFjJWV3PbxfnU7MnX+GPAaOkm/3OZq52WGwOWmkA+Akec2vPzlacx2zFeXzPY+JTYF8v
	FnHzRAAsvgd0KSIvY5XHOfmpF+kgDDj//XH/qVdXthi/a+gwiwAAAABJRU5ErkJggg==
}]

set checkNo [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAB2UlEQVR4nKVS
	PW8TQRB9s7u+w84Zozh2HKeM+BEICXpSEYQg0KdxSboInU5yQUFLS4UITRKJItTQ5EcgGiSbs89O
	iHz+ON/tDgVcdIk5hGCkKZ525s28N0sAwMzN8zC8G/TPloQEIyeMNlSr3hhXKpWPRNRlZlLM3Hz9
	5vDFu8MP92fRzObcdoAIuGbb0eOte++Z+RkR+SIMp3f2D44fdnuBkyQaICoAVABl8hdOEo2uP3De
	Hhw/Go0mtwBA+f2+M5tH8rpTil+9fN5eqS5/iaJISoiLXTQM2batB8PTjdZue28+n1t+ECwBgBJS
	MBiQShVWqyuf19fr+3kSOp3+tpSiwACk/DlAZQsmk2nBdV0BQAAwmScBwEwm08JVUpEFUgr2PM8A
	MJ7nXWSK06m5BP8S/01wyQOtDaUeuK57aZDrutDa0B8JSqVinGq+UmcAYGenFS8QGG0IBOgkiXvD
	wc2vHf9p3j/oDQcbWptYKWml26hGvR7alpV8OxsWW7vtPSnFwqkyEuPzUWg1G7WkUVseA4BwnOKn
	Jw82j5prtUgpaYGI8lIpaTXX6tH21uZBuVw+AQACAGZe/T4a3Q6C09Lvbp01uVGrjcvl0gkR+cxM
	YOYFZ/8m0r4fpmPdaEinKdsAAAAASUVORK5CYII=
}]

set radioOn [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAADQElEQVR4nH2T
	XUxTZxzGn/ecU+gZ9CNkE4TZMYQeEItMnJBRP+IyYzER60xERnYxF7dhsmwmy+aWDW8mWbLsQtSY
	2V2RFV1CFRNAxbjMr7gPBAZU2qLWDgQ3x9qDXb/OOf9dWEi3ZXuu3ov3l/yT3/MwpENEjDFGPM9B
	UdRlAFaEQrNLAcBiKZgB4BUE/hdV1Rb/AgDLhImoYHBk/JVTnvPbfJN3pD8ishkA8kzGsLW0xNe0
	09Gz2lbhZozNLjAsA6446uo61OXp2/ZwTuZEfTYMuSJAgPwoingiiSfzTNruHQ1n972++wBjbIKI
	mJCG84+43O2uTk+jpml44Xmbf5O99vRzVdJIQlH4yclQzblLVxt+GvJaT3R2b09f/SZj7AF0OgGD
	P3v3129pUW12J7W1H7lARDVEVEpEG4homSE3B0RUe/CzYwM2u5PqHS3q0Ij3XZ0gQEgmU0+/1/a5
	87e5CGdfWxU4+MG+92OxmOGjTw+7vP67JVUVpXdnZn8/wBjrJ6KP74Wmnrn+42jZ154+ZzKV+kYA
	UOkLBK2imI0X19f1AJjo+NLdNfDdD9U8I5qa/nVVQf5TbxDR5aws3Q13d2/vzVHfO75AUAJQyQVD
	00vDsmwy5IiQpOVjAJRoLK7nOabps7NTgsBpEXleB0BIpRRWbi0Zz80REY7IpmBoupDjkBEVi2r/
	K/ziiwAAnMVSNGM2GiPz0RhuBSZtAPgnRH1c1YiLJxJZiqJxJqMhBUDR6QQa891eOR+NwWwyRoot
	Rfc5AGNSWbE/Fkvg0pXvGwGUv723+YuXNqwdLixYIm/dbB9ufW3XccZYNJlM1fVeuNyQiCchlT3r
	AzD+WOPw2P56x2ONn7R3DBDRmrTG9Rka69raOy7a6p1kd7Sog2mNC1XOP+rqOn6is3u7pmlYU73C
	v3Fd7ZnqyrIRRdH4wO17Nee+veYYHBq3cjyPva/uPN26p+ktxtiDzCqXH/vq5CF3d2/jw7kIJ+r1
	MOSIIBDmH/25WOXml7f2tO5p+nChyv8a083RW80nPf2N/sAdaS4smwGGPLMhLJUun9jl3HJ29ap/
	jOl/5lwRDE0XAkCxpeg+AK/A81Oq9vc5/wVogbjMvmrMSAAAAABJRU5ErkJggg==
}]

set radioOff [image create photo -data {
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAC6ElEQVR4nJVT
	X0hTYRw9v7trbmluSJRlLcu2pW4VUhlNnypwCtkqyEp6KaLypYKI8uFeX7KH3jII9E1SC1wYOAmr
	FyNKW5nO5bb+jJWWFLYt0znb/fXgFjd76rx838PvfN/hnN8hpMDMRESs0Qj49Su5FkBxOPxlFQAY
	jXmfAfhEUfMxmVT+zAIAqcnMnOd5PXrsjuvBPv/b95bv0ZgBAHL1ORHzxg3+2kOO7lJbUTsRfUlz
	SEUuutnacbXD5d73bSoqaDOXIDtLBzAwPTOL+FwCy3P1ypEDVffrTx65TERjzExiiryyubW9qbXN
	VaMoCnZt3+x37K5w20pMXgAYGQ1aex/1V70Y8lla2rr2p1SfJqJJZGSI8Az7Ltgr65K2cifL15r7
	mHkHM5PaH2Yuk68199nKnWx31CVfvfadzxBFiInE/JqL0nXn16moYN+xOSBdqm8gogEAJEmSAAAp
	w54zc8OHjxPrng2OmG673M7E/PxdEUCJPxgy67SZcOyt6NHptAOSJAmyLDMRKWkFsiwLAAar9lb0
	DI34z/mDIQuAEiEUHl8VicX02VlalBSZvPH4HKl+hfpORFxsKvRmZ+kQicb0ofD4akGACkn8Bxbe
	F4zG/M+GnJzo9M84RseCVp02k9Oy1SamT1/wnfXHz1kY9DnRAmP+hAjAazEVBPzvwit6H/VXz8zG
	O4looLGxcbGJiizLZe6+/uq5eAIW03o/gNGFGIe8F+yOhRilphsPmbmMmQWVAoGZd0pNNx7a7E4u
	d9QlPakY09JW3mztuNXS1rVfURRs21ocqNxT7rZuKvQCGnh9AWvv4ydVnlc+s6ARcOr4oXtnT9Se
	IaJJMbXKk8x8mYi4vaun5ungsNkzPGZetlQHAPgxM4u51CofPVjdffZE7ZUUh/4p08uRN0c7Xb01
	geB7y1QkZgAIuYZlEcvGwrHDzsr7pVsWlUnt9KI6F4XC46sBoMCYPwHAJ2o0n5LK33X+DTEUkJhW
	c84GAAAAAElFTkSuQmCC
}]

} ;# namespace 16x16
} ;# namespace icon
} ;# namespace theme


bind Button <Map> {
	variable ::tk::Priv

	if {[info exists Priv(buttonWindow)] && $Priv(buttonWindow) eq "%W"} {
		# Fix bug in Button widget:
		# Reset this variable otherwise ::tk::ButtonEnter may
		# set the relief to sunken if the mouse hovers the
		# button during popup.
		set Priv(buttonWindow) ""
	}
}


# We fix a problem with tk::ButtonEnter; this function is not working
# well if it is called twice (this may happen under some circumstances).

rename tk::ButtonEnter tk::ButtonEnter_theme_orig_
rename tk::MbEnter     tk::MbEnter_theme_orig_
rename ttk::entry::CharSelect ttk::entry::CharSelect_theme_orig_
rename ttk::entry::WordSelect ttk::entry::WordSelect_theme_orig_
rename ttk::entry::LineSelect ttk::entry::LineSelect_theme_orig_

namespace eval tk {

proc ButtonEnter {w} {
	variable ::tk::Priv

	if {$Priv(window) ne $w} {
		ButtonEnter_theme_orig_ $w
	}
}


# we have to tweak the Alt key handling
proc FindAltKeyTarget {path char} {
	switch -- [winfo class $path] {
		Button - Label - Menubutton - TButton - TLabel - TCheckbutton - TRadiobutton {
			if {[string equal -nocase $char [string index [$path cget -text] [$path cget -underline]]]} {
				return $path
			}
			return
		}
		TNotebook {
			foreach tab [$path tabs] {
				set i [$path index $tab]
				set text [$path tab $i -text]
				set ul [$path tab $i -underline]
				if {[string equal -nocase $char [string index $text $ul]]} {
					ttk::notebook::ActivateTab $path [$path index $i]
					return {}
				}
			}
			set target [FindAltKeyTarget [$path select] $char]
			if {$target ne ""} {
				return $target
			}
		}
	}

	foreach child [concat [grid slaves $path] [pack slaves $path] [place slaves $path]] {
		set target [FindAltKeyTarget $child $char]
		if {$target ne ""} {
			return $target
		}
	}

	return {}
}


# we have to tweak the Alt key handling
proc AltKeyInDialog {path key} {
	set target [tk::FindAltKeyTarget $path $key]
	if {[llength $target] == 0} { return }

	switch [winfo class $target] {
		TButton {
			ttk::button::activate $target
		}
		Menubutton {
			tk::MbPost $target
			tk::MenuFirstEntry [$target cget -menu]
		}
		default {
			event generate $target <<AltUnderlined>> -when head
		}
	}
}


# fix tk::spinbox::AutoScan
rename ::tk::spinbox::AutoScan ::tk::spinbox::AutoScan_buggy_

proc spinbox::AutoScan {w} {
	if {[winfo exists $w]} { return [AutoScan_buggy_ $w] }
}

} ;# namespace tk


namespace eval ttk {

if {[info tclversion] < "8.6"} {

	proc spinbox {args} { ::spinbox {*}$args }

	# we don't like text selection while an arrow is pressed
	bind Spinbox <1> {+
		switch -exact [%W identify %x %y] {
			buttonup - buttondown {
				%W selection clear
			}
		}
	}

} else {

	namespace eval spinbox {

	# - ttk::spinbox takes the focus in state "readonly"; this is misplaced!
	# - we don't like text selection while an arrow is pressed
	proc Press {w x y} {
		$w instate disabled { return }
		$w instate !readonly { focus $w }
		switch -glob -- [$w identify $x $y] {
			uparrow - downarrow { $w selection clear }
		}
		switch -glob -- [$w identify $x $y] {
			*textarea	{ ttk::entry::Press $w $x }
			*rightarrow	-
			*uparrow 	{ ttk::Repeatedly event generate $w <<Increment>> }
			*leftarrow	-
			*downarrow	{ ttk::Repeatedly event generate $w <<Decrement>> }
			*spinbutton {
				if {$y * 2 >= [winfo height $w]} {
					set event <<Decrement>>
				} else {
					set event <<Increment>>
				}
				ttk::Repeatedly event generate $w $event
			}
		}
	}


	# should not select if readonly!
	proc SelectAll {w} {
		$w instate !readonly {
			$w selection range 0 end
			$w icursor end
		}
	}


	# - we have to fix value adjustment (who has tested ttk::spinbox?)
	# - we don't like text selection while an arrow is pressed
	proc Spin {w dir} {
		set nvalues [llength [set values [$w cget -values]]]
		set value [$w get]
		if {$nvalues} {
			set current [lsearch -exact $values $value]
			set index [Adjust $w [expr {$current + $dir}] 0 [expr {$nvalues - 1}]]
			$w set [lindex $values $index]
		} else {
			if {[catch {set v [expr {[scan [$w get] %f] + $dir*[$w cget -increment]}]}]} {
				set v [$w cget -from]
			}
			$w set [FormatValue $w [Adjust $w $v [$w cget -from] [$w cget -to]]]
		}
		uplevel #0 [$w cget -command]
	}

	} ;# namespace spinbox

} ;# [info tclversion] >= "8.6"


namespace eval entry {

# ttk::entry takes the focus in state "readonly"; this is misplaced!
proc Press {w x} {
    variable State

    $w icursor [ClosestGap $w $x]
    $w selection clear
    $w instate {!readonly !disabled} { focus $w }

    # Set up for future drag, double-click, or triple-click.
    set State(x) $x
    set State(selectMode) char
    set State(anchor) [$w index insert]
}


# should not select if readonly!
proc LineSelect {w from to} {
	$w instate !readonly {
		LineSelect_theme_orig_ $w $from $to
	}
}


# should not select if readonly!
proc CharSelect {w from to} {
	$w instate !readonly {
		CharSelect_theme_orig_ $w $from $to
	}
}


# should not select if readonly!
proc WordSelect {w from to} {
	$w instate !readonly {
		WordSelect_theme_orig_ $w $from $to
	}
}

} ;# namespace entry


namespace eval combobox {

# The implementation of ttk::combobox is a bit clumsy.
# The textarea, but only the textarea, should have a
# xterm cursor.

bind TCombobox <Motion>	+[namespace code { CBMotion %W %x %y }]

proc CBMotion {w x y} {
	variable Priv

	set cursor [$w cget -cursor]

	if {[$w identify $x $y] eq "textarea"} {
		if {[$w cget -state] eq "normal" && $cursor ne "xterm"} {
			$w configure -cursor xterm
		}
	} elseif {[llength $cursor]} {
		$w configure -cursor {}
	}
}

# # we want the invocation with a space key-press, but only if
# #   - it is empty
# #   - or the insertion cursor is at position 0
# #   - or the insertion cursor is at end of selection, and the
# #     selection starts at position 0
# bind TCombobox <KeyPress-space> {
# 	if {	[string length [%W get]] == 0
# 		|| [%W index insert] == 0
# 		|| ([%W index sel.first] == 0 && [%W index insert] == [%W index sel.last])} {
# 		ttk::combobox::Post %W
# 	} else {
# 		ttk::entry::Insert %W " "
# 	}
# }

if {[tk windowingsystem] eq "x11"} {

# Bug in Tk: Mouse wheel is generating a button press event.
# This shouldn't unpost the list box.
bind ComboboxPopdown <ButtonPress> {
	if {%b <= 3} { ttk::combobox::Unpost [winfo parent %W] }
}


# We like to bind the mouse wheel to the list box.
bind ComboboxListbox <ButtonPress-4> {
	%W yview scroll -1 units
	after idle { ttk::combobox::LBHover %W %x %y }
}

bind ComboboxListbox <ButtonPress-5> {
	%W yview scroll +1 units
	after idle { ttk::combobox::LBHover %W %x %y }
}

bind ComboboxListbox <Any-Key> {
	if {[string is alnum -strict "%A"]} {
		set key  [string toupper "%A"]
		set cb [ttk::combobox::LBMaster %W]
		set values [$cb cget -values]
		set i [$cb current]
		if {$i >= 0} {
			while {$i < [llength $values] && [string index [lindex $values $i] 0] eq $key} { incr i }
			set i [lsearch -glob -start $i $values ${key}*]
		}
		if {$i == -1} { set i [lsearch -glob $values ${key}*] }
		if {$i >= 0} {
			%W activate $i
			%W selection clear 0 end
			%W selection set $i
			%W see $i
		}
	}
}

bind ComboboxPopdown <ButtonPress-4> { %W.l yview scroll -1 units }
bind ComboboxPopdown <ButtonPress-5> { %W.l yview scroll +1 units }

::shadow::addBindings ComboboxPopdown

}

} ;# namespace combobox


namespace eval theme::clam {

ttk::style theme settings clam {
	ttk::style map TCombobox -foreground [list disabled $::ttk::theme::clam::colors(-disabledfg)]
}

} ;# namespace theme::clam


#namespace eval notebook {
#
# make keyboard traversal in notebooks comfortable
# (otherwise "-takefocus 0" have to be set in all children of each tab)
#proc ActivateTab {w tab} {
#	if {[$w index $tab] eq [$w index current]} {
#		focus $w
#	} else {
#		$w select $tab
#	}
#}
#
#} ;# namespace notebook
} ;# namespace ttk

# vi:set ts=3 sw=3:
