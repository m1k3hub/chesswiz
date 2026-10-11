# ======================================================================
# Author : $Author$
# Version: $Revision: 1507 $
# Date   : $Date: 2018-08-13 08:17:53 -0400 (Mon, 13 Aug 2018) $
# Url    : $URL$
# ======================================================================

# =================================================================
# Modifications by Gregor Cramer
# Copyright: (C) 2009-2018 Gregor Cramer
# =================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

package require Tk 8.5
if {[catch { package require tkpng }]} { package require Img }
package provide messagebox 1.0

namespace eval dialog {
namespace eval mc {
### Client Relevant Data ########################################
set Ok				"&OK"
set Cancel			"&Cancel"
set Yes				"&Yes"
set No				"&No"
set Retry			"&Retry"
set Abort			"&Abort"
set Ignore			"&Ignore"
set Continue		"Con&tinue"

set Error			"Error"
set Warning			"Warning"
set Information	"Information"
set Question		"Query"
set Wait				"Wait"

set DontAskAgain	"Don't ask again"
#################################################################
} ;# namespace mc

### Client Relevant Data ########################################
variable iconOk {}
variable iconCancel {}
variable iconGoNext {}
variable iconYes {}
#################################################################

namespace export alert error warning info question


namespace eval messagebox {

variable ButtonOrder {ok continue cancel abort retry ignore yes no}
variable Current ""

# TODO: -check is unused
variable Specs {
	{ -parent			"" "" "" }
	{ -message			"" "" "" }
	{ -detail			"" "" "" }
	{ -buttons			"" "" "" }
	{ -default			"" "" "" }
	{ -title				"" "" "" }
	{ -check				"" "" "" }
	{ -type				"" "" "" }
	{ -topmost			"" "" "" }
	{ -centeronscreen	"" "" "" }
	{ -embed				"" "" "" }
	{ -addbuttons		"" "" "" }
	{ -width				"" "" "" }
}


proc mc {msg} {
	package require msgcat
	return [::msgcat::mc [set $msg]]
}


proc tokenize {msg} {
	return [list "" msg]
}


proc open? {} { return [set [namespace current]::Current] }


proc changeDesktop {w type} {}


# A font given as a description is freed with the last widget using it, so
# every dialog would repeat the fontconfig match (~5-8 ms each). Named fonts
# stay cached.
proc Font {family size weight} {
	variable Fonts
	set key [list $family $size $weight]
	if {![::info exists Fonts($key)]} {
		set Fonts($key) [font create -family $family -size $size -weight $weight]
	}
	return $Fonts($key)
}

} ;# namespace messagebox


# this is a replacement for tk_messageBox
proc messageBox {args} {
	upvar [namespace current]::Data data
	tclParseConfigSpec [namespace current]::Data [set [namespace current]::messagebox::Specs] "" $args

	array set opts [list                 \
		-parent				$data(-parent)  \
		-message				$data(-message) \
		-detail				$data(-detail)  \
		-buttons				{}              \
		-default				{}              \
		-title				$data(-title)   \
		-check				{}              \
		-type					info            \
		-topmost				no              \
		-centeronscreen	no              \
		-embed				$data(-embed)   \
		-addbuttons			{}              \
		-width				$data(-width)   \
	]

	switch $data(-type) {
		abortretryignore	{ set opts(-buttons) {abort retry ignore} }
		ok						{ set opts(-buttons) {ok} }
		okcancel				{ set opts(-buttons) {ok cancel} }
		retrycancel			{ set opts(-buttons) {cancel retry} }
		yesno					{ set opts(-buttons) {yes no} }
		yesnocancel			{ set opts(-buttons) {cancel yes no} }
		default				{ set opts(-buttons) {ok} }
	}

	foreach button $opts(-buttons) {
		switch $button {
			abort - cancel - ignore - no - ok - retry - yes {
				if { $data(-default) eq $button} { set opts(-default) $button }
			}
		}
	}

	if {[llength $opts(-default)] == 0} { set opts(-default) [lindex $opts(-buttons) 0] }

	switch $data(-icon) {
		error		{
			set opts(-type) error
			if {[llength $opts(-title)] == 0} { set opts(-title) [messagebox::mc ::dialog::mc::Error] }
		}
		info		{
			set opts(-type) info
			if {[llength $opts(-title)] == 0} { set opts(-title) [messagebox::mc ::dialog::mc::Information]}
		}
		warning	{
			set opts(-type) warning
			if {[llength $opts(-title)] == 0} { set opts(-title) [messagebox::mc ::dialog::mc::Warning] }
		}
		question {
			set opts(-type) question
			if {[llength $opts(-title)] == 0} { set opts(-title) [messagebox::mc ::dialog::mc::Question] }
		}
	}

	return [alert {*}[array get opts]]
}


proc error {args} {
	array set opts {
		-parent	.
		-message	""
		-detail	""
		-buttons	{ok}
		-default	ok
		-title	""
		-check	""
		-type		error
		-topmost	no
		-centeronscreen no
		-embed   {}
		-addbuttons {}
		-width	384
	}
	upvar [namespace current]::Data data
	tclParseConfigSpec [namespace current]::Data [set [namespace current]::messagebox::Specs] "" $args
	array set opts $args
	return [alert {*}[array get opts]]
}


proc warning {args} {
	array set opts {
		-parent	.
		-message	""
		-detail	""
		-buttons	{ok cancel}
		-default	cancel
		-title	""
		-check	""
		-type		warning
		-topmost	no
		-centeronscreen no
		-embed   {}
		-addbuttons {}
		-width	384
	}
	upvar [namespace current]::Data data
	tclParseConfigSpec [namespace current]::Data [set [namespace current]::messagebox::Specs] "" $args
	array set opts $args
	return [alert {*}[array get opts]]
}


proc question {args} {
	array set opts {
		-parent	.
		-message	""
		-detail	""
		-buttons	{yes no}
		-default	yes
		-title	""
		-check	""
		-type		question
		-topmost	no
		-centeronscreen no
		-embed   {}
		-addbuttons {}
		-width	384
	}
	upvar [namespace current]::Data data
	tclParseConfigSpec [namespace current]::Data [set [namespace current]::messagebox::Specs] "" $args
	array set opts $args
	return [alert {*}[array get opts]]
}


proc info {args} {
	array set opts {
		-parent	.
		-message	""
		-detail	""
		-buttons	{ok}
		-default	ok
		-title	""
		-check	""
		-type		info
		-topmost	no
		-centeronscreen no
		-embed   {}
		-addbuttons {}
		-width	384
	}
	upvar [namespace current]::Data data
	tclParseConfigSpec [namespace current]::Data [set [namespace current]::messagebox::Specs] "" $args
	array set opts $args
	return [alert {*}[array get opts]]
}


# ----------------------------------------------------------------------
# Non-interactive mode (SCIDB_NONINTERACTIVE=1, or ::dialog::nonInteractive 1).
# A modal dialog waits for a button, so a scripted, headless or unattended
# run (a test, the assistant's tools, a batch job) looks like a hang. In this
# mode no dialog is ever built: the message goes to stderr and to
# ::dialog::NonInteractiveLog and the reply is the SAFE answer -- cancel, no
# or abort when offered, never "yes" to an "overwrite?" question.
# ----------------------------------------------------------------------

variable NonInteractive 0
variable NonInteractiveLog {}
variable MaxNonInteractiveLog 100
# (inside this namespace "info", "error", "warning" are the dialog procs)
if {[::info exists ::env(SCIDB_NONINTERACTIVE)] && [string is true -strict $::env(SCIDB_NONINTERACTIVE)]} {
	set NonInteractive 1
}

proc nonInteractive {args} {
	variable NonInteractive
	if {[llength $args]} { set NonInteractive [string is true -strict [lindex $args 0]] }
	return $NonInteractive
}

# the answer of a dialog nobody will see: cancel > no > abort > ok > the first button
proc safeReply {buttons} {
	set names {}
	foreach b $buttons { lappend names [lindex $b 0] }
	foreach preferred {cancel no abort ok} {
		if {$preferred in $names} { return $preferred }
	}
	return [lindex $names 0]
}

proc nonInteractiveReply {kind message detail buttons} {
	variable NonInteractiveLog
	variable MaxNonInteractiveLog

	set reply [safeReply $buttons]
	set text [string trim $message]
	if {[string length [string trim $detail]]} { append text " -- [string trim $detail]" }
	set text [string map {\n " "} $text]
	lappend NonInteractiveLog [list [clock seconds] $kind $text $reply]
	if {[llength $NonInteractiveLog] > $MaxNonInteractiveLog} {
		set NonInteractiveLog [lrange $NonInteractiveLog end-[expr {$MaxNonInteractiveLog - 1}] end]
	}
	catch { puts stderr "scidb (non-interactive) $kind: $text -> $reply" }
	return $reply
}


proc alert {args} {
	variable iconGoNext
	variable iconCancel
	variable iconYes
	variable messagebox::ButtonOrder
	variable messagebox::Current

	array set opts {
		-parent	.
		-message	""
		-detail	""
		-buttons	{ok}
		-default	ok
		-title	""
		-check	""
		-type		info
		-topmost	no
		-centeronscreen no
		-embed   {}
		-addbuttons {}
		-width	384
	}
	upvar [namespace current]::Data data
	tclParseConfigSpec [namespace current]::Data [set [namespace current]::messagebox::Specs] "" $args
	array set opts $args

	if {[llength $opts(-type)] == 0} {
		set type [messagebox::mc ::dialog::mc::Information]
	}
	if {[llength $opts(-title)] == 0} {
		set opts(-title) [tk appname]
	}
	if {	[llength $opts(-default)] == 0
		|| [lsearch -exact -index 0 $opts(-buttons) $opts(-default)] == -1} {
		set opts(-default) [lindex [lindex $opts(-buttons) 0] 0]
	}

	if {[nonInteractive]} {
		return [nonInteractiveReply $opts(-type) $opts(-message) $opts(-detail) $opts(-buttons)]
	}

	# Only "OK" to press: nothing is asked, so nothing may block. The message
	# is shown as a non-modal card (notice.tcl) and the caller carries on.
	if {	[llength [::info commands ::dialog::notice::post]] && [::dialog::notice::available]
		&& $opts(-type) in {error warning info}
		&& [llength $opts(-buttons)] == 1 && [lindex [lindex $opts(-buttons) 0] 0] eq "ok"
		&& [llength $opts(-check)] == 0 && [llength $opts(-addbuttons)] == 0
		&& [llength $opts(-embed)] == 0} {
		::dialog::notice::post $opts(-type) $opts(-message) $opts(-detail)
		return ok
	}

	set parent $opts(-parent)
	set path $parent
	if {$path ne "."} { set path "$path." }
	set w ${path}alert[clock milliseconds]
	while {[winfo exists $w]} { set w ${path}alert[clock milliseconds] }
	set windowingsystem [tk windowingsystem]
	tk::toplevel $w -relief solid -class Dialog
	wm title $w $opts(-title)
	wm iconname $w Dialog
	wm protocol $w WM_DELETE_WINDOW {#}
	bind $w <Alt-Key> [list tk::AltKeyInDialog $w %A]
	bind $w <Right> [list event generate $w <Tab>]
	bind $w <Left> [list event generate $w <Shift-Tab>]

	if {[winfo viewable [winfo toplevel $parent]] } {
		wm transient $w [winfo toplevel $parent]
	}
	if {$windowingsystem eq "aqua"} {
		catch { ::tk::unsupported::MacWindowStyle style $w moveableModal {} }
	}
	catch { wm attributes $w -type dialog }

	set alertBox [tk::frame $w.alert]
	set infoFont [messagebox::Font \
		[font configure TkDefaultFont -family] [font configure TkDefaultFont -size] normal]
	set alertFont [messagebox::Font \
		[font configure TkDefaultFont -family] [font configure TkDefaultFont -size] bold]

	if {[llength $opts(-embed)]} {
		set k [string first <embed> $opts(-message)]
		set ante [string trim [string range $opts(-message) 0 [expr {$k - 1}]]]
		set post [string trim [string range $opts(-message) [expr {$k + 7}] end]]

		if {[llength $ante]} {
			grid [tk::message $alertBox.ante \
				-font $alertFont -text $ante -justify left -width $opts(-width)] \
				-row 0 -column 0 -sticky w
			grid rowconfigure $alertBox 1 -minsize 10
		}

		set f [tk::frame $alertBox.embed -borderwidth 0]
		eval $opts(-embed) $f [list $infoFont $alertFont]
		grid $f -row 2 -column 0 -sticky we
		bind $alertBox <Configure> [namespace code [list messagebox::Resize $alertBox %w]]

		if {[llength $post]} {
			grid [tk::message $alertBox.post \
				-font $alertFont -text $post -justify left -width $opts(-width)] \
				-row 4 -column 0 -sticky w
			grid rowconfigure $alertBox 3 -minsize 10
		}
	} else {
		set normalSize [font configure TkDefaultFont -size]
		set smallSize [font configure TkTooltipFont -size]
		set defaultFamily [font configure TkDefaultFont -family]
		set fixedFamily [font configure TkFixedFont -family]
		set parts [messagebox::tokenize $opts(-message)]
		set row 0

		foreach {attrs str} $parts {
			if {[string length $attrs]} {
				set weight normal
				set padx 10
			} else {
				set weight bold
				set padx 0
			}
			set family $defaultFamily
			set size $normalSize

			foreach attr [split $attrs -] {
				switch -- $attr {
					small		{ set size $smallSize }
					normal	{ set weight normal }
					bold		{ set weight bold }
					fixed		{ set family $fixedFamily }
				}
			}

			set font [messagebox::Font $family $size $weight]
			if {$row > 0} { grid rowconfigure $alertBox [expr {$row - 1}] -minsize 5 }
			grid [tk::message $alertBox.m$row \
				-font $font -text $str -justify left -padx $padx -width $opts(-width)] \
				-row $row -column 0 -sticky w
			incr row 2
		}
	}

	if {[string length $opts(-detail)]} {
		set infoText [tk::message $w.info -font $infoFont -text $opts(-detail) -width $opts(-width)]
	} else {
		set infoText [tk::frame $w.info -width 1 -height 1]
	}
	set iconLabel [tk::label $w.icon -image [set [namespace current]::icon::64x64::$opts(-type)]]
	set buttonFrame [tk::frame $w.buttonFrame]
	if {[string length $opts(-addbuttons)]} {
		set f [tk::frame $buttonFrame.embed -borderwidth 0]
		eval $opts(-addbuttons) $f
		grid $f -column 0 -row 0 -sticky sw
	}

	set entries {}
	foreach entry $opts(-buttons) {
		lassign $entry type text icon
		set index [lsearch -exact $ButtonOrder $type]
		lappend entries [list $type $text $icon $index]
	}
	set entries [lsort -integer -index 3 $entries]
	set defaultButton {}
	set col 1

	foreach entry $entries {
		lassign $entry type text icon
		if {![::info exists text] || [string length $text] == 0} {
			switch $type {
				abort		{ set text [messagebox::mc ::dialog::mc::Abort ]	}
				cancel	{ set text [messagebox::mc ::dialog::mc::Cancel]	}
				continue	{ set text [messagebox::mc ::dialog::mc::Continue]	}
				ignore	{ set text [messagebox::mc ::dialog::mc::Ignore]	}
				no			{ set text [messagebox::mc ::dialog::mc::No    ]	}
				ok			{ set text [messagebox::mc ::dialog::mc::Ok    ]	}
				retry		{ set text [messagebox::mc ::dialog::mc::Retry ]	}
				yes		{ set text [messagebox::mc ::dialog::mc::Yes   ]	}
				default	{ set text "" }
			}
		}
		if {![::info exists icon] || [llength $icon] == 0} {
			switch $type {
				ok			{ set icon $iconGoNext }
				continue	{ set icon $iconGoNext }
				cancel	{ set icon $iconCancel }
				no			{ set icon $iconCancel }
				yes		{ set icon $iconYes }
				default	{ set icon {} }
			}
		}

		set cmd [list set ::dialog::Reply($w) $type]
		set button [::tk::AmpWidget ::ttk::button $buttonFrame.bt-$type -text " $text" -command $cmd]

		if {$type eq $opts(-default)} {
			$button configure -default active -takefocus 1
			bind $button <Return> [list $button invoke]
			set defaultButton $button
		}

		if {[llength $icon]} {
			$button configure -image $icon -compound left
		}

		bind $button <Return> {
			focus %W
			event generate %W <Key-space>
		}
		grid $button -column [incr col] -row 0 -padx {12 0} -sticky se
	}

	set n [lsearch -exact $entries abort]
	if {$n == -1} { set n [lsearch -exact $entries cancel] }
	if {$n == -1} { set n [lsearch -exact $entries no] }
	if {$n == -1 && [llength $entries] == 1} { set n 0 }
	if {$n == -1 && [llength $entries] == 0} {
		wm protocol $w WM_DELETE_WINDOW [list set ::dialog::Reply($w) ""] }

	if {$n >= 0} {
		set escCmd [list $buttonFrame.bt-[lindex $entries $n] invoke]
		switch $::tcl_platform(platform) {
			macintosh	{ bind $w <Command-period> $escCmd }
			windows		{ bind $w <Escape> $escCmd }
			x11			{ bind $w <Escape> $escCmd; bind $w <Control-c> $escCmd }
		}
	}

	grid columnconfigure $buttonFrame 1 -weight 1
	if {[string length $opts(-addbuttons)]} {
		grid columnconfigure $buttonFrame 1 -minsize 20
	}

	# grid elements following guidlines from Apple HIG:
	# http://developer.apple.com/documentation/UserExperience/Conceptual/OSXHIGuidelines/index.html

	grid $iconLabel $alertBox
	grid ^ $infoText
	if {[string length $opts(-addbuttons)]} {
		grid ^ $buttonFrame -sticky news
	} else {
		grid $buttonFrame - -sticky news
	}

	grid configure $iconLabel -padx {24 8} -pady 15 -sticky n
	grid configure $alertBox -padx {8 24} -pady {15 4} -sticky w
	grid configure $infoText -padx {8 24} -pady {4 5} -sticky w
	grid configure $buttonFrame -padx {8 24} -pady {5 20}

	set Current $opts(-type)
	wm withdraw $w
	update idletasks

	# center the window
	set rw [winfo reqwidth $w]
	set rh [winfo reqheight $w]
	set sw [winfo workareawidth  $parent]
	set sh [winfo workareaheight $parent]
	if {$opts(-centeronscreen)} {
		set x0 [expr {($sw - $rw)/2}]
		set y0 [expr {($sh - $rh)/2}]
	} elseif {$parent eq "."} {
		set x0 [expr {($sw - $rw)/2 - [winfo vrootx $parent]}]
		set y0 [expr {($sh - $rh)/2 - [winfo vrooty $parent]}]
	} else {
		set x0 [expr {[winfo rootx $parent] + ([winfo width  $parent] - $rw)/2}]
		set y0 [expr {[winfo rooty $parent] + ([winfo height $parent] - $rh)/2}]
	}
	set x "+$x0"
	set y "+$y0"
	if {$windowingsystem ne "win32"} {
		if {$x0 + $rw > $sw}	{ set x "-0"; set x0 [expr {$sw - $rw}] }
		if {$x0 < 0}			{ set x "+0" }
		if {$y0 + $rh > $sh}	{ set y "-0"; set y0 [expr {$sh - $rh}] }
		if {$y0 < 0}			{ set y "+0" }
	}
	if {$windowingsystem eq "aqua"} {
		# avoid the native menu bar which sits on top of everything
		scan $y0 "%d" y
		if {0 <= $y && $y < 22} { set y0 "+22" }
	}
	wm geometry $w ${x}${y}

	if {$opts(-topmost)} {
		wm attributes $w -topmost true
	}
	if {[llength $opts(-buttons)] == 0} {
		wm protocol $w WM_DELETE_WINDOW [list destroy $w]
	}
	wm resizable $w false false
	messagebox::changeDesktop $parent $opts(-type)
	wm deiconify $w
	raise $w
#	tkwait visibility $w
	set focus [expr {[llength $defaultButton] ? $defaultButton : $w}]
	if {[llength $opts(-buttons)] == 0} {
		focus -force $focus
		return $w
	}

	::ttk::grabWindow $w
	tkwait visibility $w
	focus -force $focus
	vwait ::dialog::Reply($w)
	::ttk::releaseGrab $w
	destroy $w
#	update idletasks
	set Current ""

	return $::dialog::Reply($w)
}


proc messagebox::Resize {alertBox width} {
	if {$width > 384} {
		if {[winfo exists $alertBox.ante]} {
			$alertBox.ante configure -width $width
		}
		if {[winfo exists $alertBox.post]} {
			$alertBox.post configure -width $width
		}
	}
}

namespace eval icon {
namespace eval 64x64 {

set warning [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAANJ0lEQVR4nO2b
	a4xd1XWAv7X3Pvc1M35gG6SoaaFt1JahCMwwHmOCjFSpLU3aStXMD9oqlIApzQ9DYxvDhNyZxjZj
	U1RGahNRExwk+udOK7VFDWpVyVZ52OMHTdQOIpWaNPyIsBmD7fGd+zjn7NUf5547d8Zjex53DGlZ
	v+45Z+99zlp77W+vvfa+8Kn8/xb5OF6qRcwRMK33toKXYfzH8T3XTLSIKRZnK94qxSJGr/B8JeSa
	eUCpHzswRgwwPhJ0u0DvxuuNClhrfqSxvLFxZ/2duWVXWq6JAUol7MAA8Vsjwa/mA93rlfsKWaxp
	vN0rTNeIjfDd6ao8tWUw/M+0zkp/24obIO3No/vsb+dz8jeZgM6LFQCi1nIKblUeaiEXp2t6/11P
	xq9eC09YUQOkCozvdz3ZgDe9kgkjIhEcgJJATxpAVCUKHM4ItaqXLX07wlMrbYQVA442jHu4iFP0
	oLNkojhRXgFVNJ/B5DMYVVQBEVwUEzlLVrw/eLjYNNSKddSKGeBIMem5Qs49uqZDbitXiQCnCkYg
	GyDVmn6/WtfvZwPECIkVwJWrRKsLcnuhwz06MEZ8pIhdqe9cEcumU90XV3MDsZswhtVR4sQi4J1F
	wli+1LsrfAXg1IHgD4zTl6MIVbAkZfDKeUzUfcfjvD80hAyvQJywIh7Q3Z18bBi6ZzpzrK1HKGC8
	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
	OgtLwQAAAABJRU5ErkJggg==
}]

set info [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAPdUlEQVR4nO1b
	a3Bd1XX+1tr73CvzMo7B1MTFMcEUVGKQZcDtOD6SbFpImgI2B7tNZhoeNZPOZCZ/MtPOADeXx6/m
	R2Yy05SHSdJmEpyD7ZCQ1gEj6RIyIztcDG4xDxM8Tg0UxwZMwJLu2Xut/jjnSFdX19KVLFFmwjej
	Hzr37L2/tfbea6+91jrAx/gYf9CgD2+cEkXRPjp8+DABwIIFC7T+hfrncdyuQFkBaJO+ZprY7PUd
	RREDQBzHfjodRFFksvaCWVLGLCigxGHYz5VKxdU/6+x+aQlULgLhQhCdC9WzAMzJXhgE0RGovgHF
	KyB+qdp30QGgLHkPYRjaSqVL6p/NBGZSARRFEeez3dn5V6fg9NO6ifwXlLAKiqXG2AKIQQSojp1Q
	IoIqABV474ZBeFUVTxPop8Gg9g0MxINAuipmckXMiAIyUh4AOrrXLTYU3ArI3xDbTxMxVDxEPFTh
	QZMQVxARGWYGsYGqQMX9BjA/9FrbvKdv28HGMU8GJ6sAQqlEKJflkp4vnNOmp3wdhFuNsXO9OKj3
	okRCqgyibCxVVWqqBCIlIHtPVfO2ZAwbtvDeHYPiwSE6/s//3fuzt1AqMconZyynrYD6Gejs2XAL
	AXcbaxc6l0BVHUEZIE5FgaQCwhAziOr0kUFVs9mWdKWk73PKUUVBQkTW2gDeuTcVcke1N97cyOVD
	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
}]

set error [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAQr0lEQVR4nO1b
	a2xcx3X+zplZkbvLhxRZcuQypEXtg5QdyY1cBygCXzkJaruFH3G9Mor8iR+w0/5ojAABWsBvx79a
	9IEAbeNUjtOiaS3asRunSQwUkdYtCtSR/FBiSbt3JYUyLdWWFFOUyCW5M+f0x72XWtFLciVLitP6
	/JAu7947c843M+fM+eZc4CP5SP5fC12MTjTqhwDQjiAgANi8erViZCR6oFTCjnffje6Xyxq9AqXo
	/19PUYAUMFoqmXNuo1QyChi9gAN13ht+GODNQcDXlcsuuacAH8rl1jqiIU9UMMBlAlxCqmkAUKI6
	A8c8cNioVq3qvv5a7SABkrSxPQjsjnJZHm26dz7kvAEQjxIT4AFg55o1mUu6uq7zRDcR8BlVzaeN
	WZYiAgEQ1bn5Hb1IUABOFXWRGQA1Bf6TVb9v6vXt/WNj9bgfA0DO1/I4LwAoYBLDDwwPDxjv7xGi
	P+ggWpciwowIZiKDPVRVW3Q8d4+ICDAdROhgRkMVM6r7GfjuKeatV+zdOzq/zw8iHwiAxLkRILvX
	rr20N5X6GojuyTD31iOjhVRFiXjOvtjBKeb+BeJZgchvJDpp8m4HEWeYMSlyQlX/fqLR+LMNBw++
	owDjAzrLcwZgG2C2xCPwi0LhbgYezxizZsJ7eFVHkdGsgEJVIjvJpIiQIsIcIoi0FwANVTRUoarR
	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
	SUVORK5CYII=
}]

set question [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAARmUlEQVR4nO1b
	a5BV1ZX+1tr73AuI4AONDyLR+MAeR4WLSE0ppxs0kvhAgaNYWjPjY7CSP5P54dRMlXq9mNSkMlM1
	U5UqEx+Q50TxCPjKSADpvsSyGuMFpBJ84CP4HBEUVIS+Z++15sc5p/t29+0HDTipil8VVdzT++y9
	HnuvtfZa6wBf4kv8RYO+uHXKFEVbaceOHQQAxx9/vDYOaHwexy0KVBSANpnrUBN2+OaOoogBII5j
	P5IJoigy2fuCwySMwyCAModhB1erVdf4rNT28qlQmQzCmSA6CaoTAIzOBuwD0U6ovgfFqyB+udY+
	+U2gIvkMYRjaarVVGp8dChxKAVAURZxru1S6YgyOHNtG5K9UwkVQnGGMLYAYRIBqb4USEVQBqMB7
	1wXCa6p4lkBPBPu0vbMz3geku+JQ7ohDIoCMKA8AU9rmTTIU3ArI9cT260QMFQ8RD1V40BCEK4iI
	DDOD2EBVoOJeB8yvvdaXbGpfsb3vmgeDgxUAoVwmVCpyzqwrvzJKx9wOwq3G2PFeHNR7USIhVQZR
	tpaqKjUVApESkI1T1fxdMoYNW3jv9kDx4H76/N//sO7JD1AuMyoHZyxHLIBGDZRmXXcLAfcYa090
	LoGqOoIyQJyyAkkZhCFmEDXII4OqZtqWdKek4zmlUUVBQkTW2gDeufcVcmdtXbykLy1fiABSg1R1
	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
	LqYAAAAASUVORK5CYII=
}]

} ;# namespace 64x64
} ;# namespace icon
} ;# namespace dialog

# The 18 direct tk_messageBox calls of the program are modal too.
if {[llength [info commands ::tk_messageBox]] || [auto_load tk_messageBox]} {
	rename ::tk_messageBox ::__tk_messageBox__orig
	proc ::tk_messageBox {args} {
		if {[::dialog::nonInteractive]} {
			array set o {-type ok -message "" -detail "" -icon info}
			array set o $args
			set buttons [dict get {
				abortretryignore {abort retry ignore}
				ok {ok}
				okcancel {ok cancel}
				retrycancel {retry cancel}
				yesno {yes no}
				yesnocancel {yes no cancel}
			} $o(-type)]
			return [::dialog::nonInteractiveReply $o(-icon) $o(-message) $o(-detail) $buttons]
		}
		return [::__tk_messageBox__orig {*}$args]
	}
}

# vi:set ts=3 sw=3:
