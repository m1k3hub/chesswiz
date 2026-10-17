# ======================================================================
# Author : $Author$
# Version: $Revision: 1507 $
# Date   : $Date: 2018-08-13 08:17:53 -0400 (Mon, 13 Aug 2018) $
# Url    : $URL$
# ======================================================================

# =================================================================
# Modifications by Gregor Cramer
# Copyright: (C) 2009-2018 Gregor Cramer
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
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
		if {[string index $y 0] eq "+" && $y0 < 22} { set y "+22" }
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAOoklEQVR4nO2b
	e3BUVZ7Hv99zbz/yIiHJOJAnMq4KqLgPIIEZLRbxMchTh3VqZkEZlCUwqzta83DF7tZxpnSqprZW
	SRYXENylZFUMKCoKLDojJAHH8QUoKpKQBEQSEpNOOt19z2//uN3J7QCSR4fVXb+VrlR139fvd37n
	c77n3HuBb/T/WzzfJxQRAiBIISAAIABhfy8k5Xxf03lTLPiYTNCTAXoyAJhn2WbodV5OJiKMt6yI
	5EaBiV3vPDO+69ThfADwDB/dkDb+B28D2Euyqfc+Qynz3JsMTvFARMQAcMOJzXf+Q/DDl6ag/ViW
	skIAgFbDC2y7tyVtzPd3i0gFgG0krfORhCGtAEc5G5GTh28/tuHmFdL455ERASy6BFCx4DQNidAk
	oPL++tjIv3/2AVf2qNUALAAYyiSooTowAMDvj7VgdE7D+tkPRuv/PLJLeS1LeQRUABn7KFjKI2Hl
	taL1fxrZsG7mg0B0DkmBf2gbacgSID6fYiCgRaS4ccOCu/HZ+zlRM8WCaAMAlETpkZDySEgpidpB
	ijaiZoqFY+/nNm5YcLeIjGKAWny+IbvOIcmuo/TZ/sFL9x//z/n360hYQCoBxZAwxZsTSrlwynsA
	EPp09+UINXktuoUQQkQrl5t5P974QOqlNz6A2HA5FF1hqBKgSGoRmXzkXydttI7uLbQMrxYIlURg
	ZIxoy1/0ss+Td8V/AWBX/dt/17Buhl+3Hc+w6AJBMayQMgonHh31jzW3kNwTP2ayrzXppSUihE39
	9KadD5VJ45uFluHRgFYExFTksCn/9Jwn74oKksdINnoKriwf9r2fbTIUSYEAWlmGR0vjm4Wf7/j1
	MhHJiB0z6Q2W/L7l95OAWO2nZrdWrZoT1RABCCht6i5lFJQezp16TznJLhExRMQg2ZV79d3lRsHk
	w6Z0KUBpARjVkLaaVbOtzlOzCAj8/q92AhzgK/psc9kyfnE0TSu7X4tEKe5hOme6fw2AN2NjvBUf
	7wH8Kec6/2p4h1kiURJCrdzC1vq0z54rWyYixQwEkg7EpB1MRAi/X0REtR188bbOg1tLwnQJoZVA
	abdEmTJu7htpF09bbw9vjtaMDZdpF/3tk96xc3e7JUqB0oRWYbqk48ALJcGDL94qIip2jqRVQjKz
	GXdtk5p3PLgIkXaShggohu6iZI1qy5tfsZJkg4hdKd07BgJaxKdINuT94PHHMHzUF4buooBCGsJI
	kCd3PLgIQEnsHF+tBCSAb8dDZbphX5GlesBnGIpZpUs3wUjZavPAf4bhzG+zwnC/mFmy9DnDULRn
	i1pZyqN1w76ipp0PlolIejKBmKQKiIGvs3VWa83jCeAzdJcyCko+zZ768wqSHTiLv7f5LyTZkT31
	5+UsKPnU0IlAbK3+99nobE0qEAedAPH5FGmD70TlsjK21qU7wQd3hs6Z7lsDYF+s1bqDFxH2asl4
	y775resCq8WdoROBeDS90QZiUbKAOKgDOMEX/PCVWzsObCmN9AJf6ri5u9Munt4NPpICsnuWyHg5
	k3Buk3bRtCdTL5v3hhOIEbqk8+DzJW0HX7wtWUAc1M4Ox1dS+2jpxmhddXHc8Rk6DJVV1D76F4cW
	0/Q8bUMuoHvt7wIAkpHE72NVFe2af/jhi1frlrp0S7lth6hDyiycVFv80+ofkqwarEMccAU4wJfW
	tPM3Zbphb7HT8RkGOax0SSUMdzf4RIQCUETc0Y6m+U3b7lvbtO2+tdGOlvki4o79RgcQtw6bXPac
	YbA3EIubdjyUFCAOYkHETwI62tk6q7V61VxLQ0SBhNKGDilVNPlI7tRfrSTZ4agUEhTpbJ1dv2p6
	OY6/lQMA7R+8fEPB4u0wwaclNpzG9ukQkfLg+1uuNur2jLKUXV1RDWmteXxO1lXLXzKBpwR+BQdb
	+qMBVYADfIXHK5ctc4IPMfDlXpMIvp6VIW1+/vrvZvH4Wzld8Ea74I3y+Fs5zW/8fqaINtnTovH/
	+3Kv9a/GaUCsSz/+7DIbiBw4EPu9UyL4tt0aOrCl1On4XBJl6rjZe9IuvXZdAvh6ZEqwOU2TIhAl
	EKVJkWBzGhwVmQDEi6evTx03Z3dvIIYObCltO/jyrY5r6ndXGEjW4gFNaNr+wCKE25XT8SGruG3k
	TRUrSdb3dnzdSaSyqyV+QAiF6nRv0OMQ60fetGqlZBW3xR0iaAi62lXzjgcWAZg0UIfYrwQ4wXdy
	18NlVn3NqATHp8jM0iWVcKe/cHbH11/FgOhO2TqsdGllAhANj9YNe4ubdv6mTETSBgLEflZAzPGF
	22e2VpXPi2rp5fgmHcme+qtyksGzOb7+yuEQg7lTf1Gu8kuOOB2ipUVaa1bNRbh9pp2Y/jnEPifA
	Cb4Tm5YuUy116Vp5YuCzYo7v/rU4g+NLguItuzf32sAaG4gWCaGlPMKWuvSGZ5cuF5HC/gKxTxs6
	IRM8tGNhx/4tkxPBF6F37OyqtEuuX0dSnwF8g1IiEK9Znzpu9h63RE4H4oev9nvK3NdMxQOaePJV
	308QbnOAL0zJLGrPv7niMZJHzwa+wcoBxKMjb6pYKVlF7coJxHCbOrU9sAjAhP4A8ZwJcIKv+bVH
	luqG6l7gAzNLkg2+sykOxPQXMictqTRVokO0GqpHndz1cL+A2IcKsMGHcOeNLXvK50UtB/isLqXy
	J9bmTLs3qeA7m5xAzJl2b7nKn1ibAERLpK2qYi7CnTf2FYhfmgAH+AqObVqyjC21GQng86Tr7Gvu
	Xwtg7xCA76yX1QNE3xq40zUcQERLbcaxTXcsF5GCvgDxrD8mgm/7wo79m6eEaSaAL2XMrOqMMTf0
	G3wUTQEE9tRYBBCK7lOfdQBRp11y/Trv2NlVLgcQwzSlY/+WycFD2xf2xSF+WXYcji8QA58pAorS
	YUpWYfu35z22kmRdfDW4LwEACLtHXl6vSMIKG7DChiJpjry8HkC4T0lwAHHEzf8WA2I4toZoCsJt
	qmm7/yfoAxDPmAAH+FKbdz2y1KqvvtAJPlOBmROXbDZShj8vAOE/N/hIis/nUyR11uSlT7rGL6oy
	vVna9GZp1/hFVdmTlz5JUse26UMl2UA03OkvZE68Y7OpkAjE+uoLT/73I+cE4hm/7FmQ6Jh/+OEx
	SV2Q6JkVyl+EGt+9GgC8eVe8TvIj6SdEHdPs0tpHS56K1tX0a0EGOEMFOMCX3/jM0mVsqc2wHOAT
	d7pkX7PiCQA1AwFffLpL8qOU/PGrU/LHrx5I8D05EAKoyb02sBaeRCCypTaj4enbvxSIqtfResD3
	8c6FHe8/993e4EsdM7MqY8yMJwbq+BwV4BWRcbFPSnytsD9KBOJ161LGzKruDcTQ/sopnR/vXHA2
	IPZeEWKspCZ8/opvMcNtivYqDJQOUw8rDObNqxgI+HoHP6Llzf/4Zfvex2eICDMmLH5ZRH5LsrG/
	lRBfHSZZJx0tKw/X/vEK1dKQppWrG4ifv+JbXHTRtO0k94lIwupRdwU4wXdy1yNlchr4hFmlt29G
	SmafwXf61RI0XOj8aNeC5q133hn+9I2LIkd2f+fUi3ctD37w8m00PehvFQAA/DGHmJL5fOakJVvO
	BMTmXY+UiUhqbyAmdAECAis844uqipssSyc4PuZNOJozbUU5yfaBOD57PRCio2H3F+9tmmSETumo
	KzUSdaVGVKhVt79XOUlHQins6dd9lsMhtudM++eVKn9CnWE5HaKWlqqKm2CFZ7AXsxQQBx9FRPIb
	n75jOVuOdINPxKJ40iT3mhVrAVQP1PE5EhZ1jRjXQEUl0ZBLoiFTKSj3iLENiPmAAdrpbiDmTLvv
	CfGkSSIQj2Q0PrNkuYjkk5Q4EO0KCASEphvBj3b+OHSwMsHxuW3wVaePvXHA4Isr7gOyE32AGOMX
	7h3+vbvWsedWeb/lBGL62BufSB0z83QgHqicEvxk149ouIFAwH7sxjGWFtSvm1sZPbD5b7qUV8Me
	S6kyC4LFP3tniZmavWEg4OstBwgvCjW8cxWo6c37yz+SPDTAoTDx+PFnFDqaf3T49+NX6daGNEu5
	BKB4dEi5xs3bl79w01ySDSKinAy4LHzs3UsisB/ZBQSGUsiceHu/HN+5RNv7k+THKQVXrk3J/6s1
	JA+hx3oPTt1AHP585sTbNxsq3mOFERBdx96+BMBl8c0V/H4AQMene4p0qDVdqEDAXugYPvpUzvQV
	60m2JXOqGwOdEp/P/vQamgZ17B4gtuVMX7Feska3GDpMAiJQ0J2tGaHaqkIAgN8PEwjYe1qdrp4Z
	GUEAyjOsE8AJAHjtNb/y+ZJxiYid29HV/QH4fEl8WOM1vwKgAXxOb3ongSyAsT9NbYXc9oYBmPD7
	gEAAnuzRJ+HyhhFqdQuFFk2g6aMLgod2zhCRA+x1A/OrrID9nJIr+PHO7+umT75l0RSB2J3P9IbN
	rFEnAQB+XwIEr6x7tGRz5GhNkaW8IhCaEiEzC5uzvnvXRvcFYz8EokTSV/uSLAVAmRI+ceCSlj/8
	yy3SejQ7SpfEJnI0CyfVFf+0ejbJd0REmejpex+kXjrr9faGmgUWoSmionTBaK3L/mLbPWWWmf6/
	GFX/ZUTboS0Ni24QQhDaUFRpY2e9BuDD2GYSuxnpUyRDIrIm+MHWqa66qsKImWJRLMOiW7QlAit4
	+r2rr7AsGFpo0g7esFzRToOjJtflTrt3jR2r7Um6SRQ3IOGW+sXHVl//W/lsf06XcglonLfFvmQp
	HpT9hoZFj44Q3x7XlLf41V+6s/LWAD1uMyEBtB9dMa3OU7ccf2rBPV2Hd12hIkHor1P0DikC2pUG
	z+ip74744YbfGSnDNoK0IHJ6AgDnayqEiB4XPPDCnPb3K68Kn/ykWEc7UwB7LfNrIBqulA5Xznfq
	Ui+b+4eMsTM3k2o/IKe9inO6744/wAQI6ILocBaACwB48DWJHnZcXQBOULlbIBHEnzyB9DGEmDs7
	76/VDYEYi+XMP55rb4m/5/f11P/t9xC/0Tf6Rt9osPoftjK6Uyo9kNMAAAAASUVORK5CYII=
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAASw0lEQVR4nO1b
	eXRURda/t97WS7YmQjCsITQSIMCnyCoDKgKKmLjhDjjKcVxwdFScQSWJguM2KiowqAiK8o0ImqC4
	oIPsBAVkTZAkQNg0YMie7rfVnT/ee6SzQXcAx3PGe05Oktevq+791a1bt279CuB3+d8W/G90SkRN
	9ouI9Gvrcs6FiJCIGBGxjIwMBqcGHTMyMpjzfnNA/ebFMdo2uJ6IogBerxuISCIil/0jeb1uEEWh
	UVshgJwTMM5qo7aSiIg85JkEAIkAkLQrryB538EjHY4dL00or6qK1VVdAUSSZFGLi46uaNM6vqRL
	x3aHevXwFwHAPgD4CRH1kLYYANDZnCpnDQAiYo7hRCQAgP/HfcVDVq7KvWTXnsI+R47+3KmsvNKn
	ajrqhgmccyCy7EBEYMhAlARwyRL54mLK2iW2LU5N8W+7fFj/df4undcDQCEimg37OlM5YwCICJ0R
	ISIFAAZ+lP3VtV+vzr2ioGi/v6KyRjJMExABGGPAEAkRG/kz2W1xIrTAARAFAWJjvHq3rkl7rxg2
	6Osb0kZ+AgCbEFFt2HdL5YwAcEZCUWQIBtUBi5Yun5i9fOU1+w4cTlQ1HUSRgcAYR0TbxNAuqcGj
	kOf2QyICk3NmGBwUWYIundsfTb/ysmW33jhmgculbFJV7Yy9oUUAOAEJEYmIErZs333nG28uuntH
	XkGybhggSyLZnyGiZRHnxEyTAw9xewsYACI6OR0YIggCA8ac6QTotKXpBkqiCL17dit8YNIt8y7q
	03M+IpYQETLGyGnjnAJgu539J/V/dc7CqR8tW3F1ZVW1oMgSRwQkssDhnKNumIjIwOtWoFVcTOV5
	8b7j8a3ijkdFecsURQoCAKiq7qqurvGVnihv/UtpWesT5ZUxNQEViDhIokC2cYgIQASkajqLiY4y
	x6WN+vTPf7r9WUT8HgCQLLQiQkFsifGSJJKm6emTp8x4ek3u1lSBIbgUmVtRGomIo6Yb6HG7oFty
	50N9e3ffPPCiPrlDBvTdKYpiMQD8AgABADBC9HADwHmGYXRav2lbau6W7QO37djTb//BIx1qA0GU
	RAEQGQEQcykyDwQCwjuLPkkv3FecTETTZFnKtl0lorgQtgc4xhMRVlbWjL/nL5nTd+YXtnMrEier
	HUQAruoG87gVuKhPz+3XjhmRPWL4wC8BYJcgsGrOw9OLMQTT5FEA0OubVbmjP1n+TfqW7bv71AZU
	UGSRE4G1HAJQQNVZakrXw2/PzHzS6/UutKdL2J4QFgCICJxzBACoqQmMn3Df317YU1jcxu1STCIu
	ICKZJgeTc0xN6Xrg7juuf3f4Jf3/5XYpe4KqdrKZkGSmOeVOxhbnHZciQyCodl+zYfPNb7770YSd
	+YWdBcZIEJg9KMwMBFWhu79zycI5z05xu90LLRDDiwlhAeBEWiJKv/nuR2ftyi9K9Lhkzq3npOsG
	uhSZbkgf9emj9098CQDW2UY4RkecvIQkVfYKSQgAQ1+ateCRJdlfjQ2qGkqSSESEDJHXBjXWu0fX
	I4veevF+RMwJd3U4bQwIMb7fA1OmT7eMV0xOXGCIXNV0Fh/vq/nbw3fNvmLY4JcR8WfbcIaIvKXr
	dKgX2G0RAKwhor29e/j3Pjdz3n2lJ8o9iiRxTsQ8LsXckVfYbvLj06cT0RFE3BwOCKcEwJ73nIha
	vzp34ZNrc3/o6XbJJrfdXtV01jbhvMpXZjw+o8cFya8jYuBMDW8GDCfDZIj4MxFNa5/Y9vhDTzz/
	REnJLzGyLBEnLrhdsrlm4w+9Zs5d+CQRTULE46cLio02K6HGO7+3bN9910efrLiaMeTOaOiGgefF
	x9Xaxr8SavzZMryh2IPBEDHQ44LkV1955rFn41vF1eqG4eQkjDHki3NWjNm6M/+P4WygmgUA6uZf
	v9fmfnBPZXW1IArWbs00OblkmT/+50mz7ZHXW2K8vWuMKBcJAUHrmeJ/7a9/mTTbJctkmtYSIwoC
	VFZWi6/NWXgPAPRzgGmuvSY/cNyGiJQPlnx21878ws6KLNkdA5mcsxvTRy0feemgl1oy8s5yiva+
	ICS5ihSEwMhhg1664ZqRn5ucM6tZYoos8R35hUmLli7/IxHJTh9hAwDW6kAA0D97+cp0wzDAylyR
	q5rBeqUkH3zk/okv2GloS0becVmJiCRn7Y5EQkAoeXTync/3Skk+qGqGHX8ADMOg7OX/TgeAAbYt
	4QNgNy58lP3V9fsPHkmQJZGIADnn6HG7aNKEcfMBYINd8Ahbc2dpIyK5vKpq3BtvffDOzLnvzy8t
	Lb/F3klGOiXI1mHDpDtuWOBxu4hzjkSAsiTCvuIjbRfnfHkdEQnNDVKjVSBkRJO/Xr1xpKbppMgS
	ARBpuskG9uuzc/jgfh+EjEBEQ4cAVFEdSLvnoczZeXv3xwMBrMvdetWcl59CRFwEEWSnIdOHE9H7
	F/bpfu263G2piixyAARV0/GbVRtHjUsbPQcA9jblrY08IDMzEwAACvYduKSg6IBfZAyBCDkn9Lhd
	kH715UsVWS5wOg5XWWfOcyLpvUVL0/L27o9XJNFQFNH4sbDY9+7/56Rxzk85X5sBgRMRKopckD5m
	xMdutws4JwQiFBiDgqJif8GBQ0NCbQuVeh4QgqY4550Ph1ZU1oiCwDggoK6b6E/udPSKYYO+0HQd
	oC5O/BYENU2nkcMHfzHv/Y8n5f+4L1GRRRIExisqa8V/f7txKBEtRESjYV7Q0AMc5BN379nb1zBN
	a4sDQIwx6Jva/TsA2G2/E5nr2yPLEPXxt16f06NbUqmqG6KqGuIFXTuVTbglLYcx1FpY5XHe3/V/
	qd2/Y8gArPQbDNOAXfl7+wLA+Q1sBIDmM8Euh48e62jbDnbwg0H9UjcKAquBuhwhYuGWey+b+2om
	W7goZywHwttvGPtZK1/sx0QtK9A4+w5BYDXfrN6Qu+zzb9NVTUPGgBABDh8t6QQAXQDgUMPv1gPA
	mSO78gqSy8or4xizHMQ0CX2xUdVDBly0g3M6o1qc/T0VAD4koiXWIzRCPm9Jsyd1Gjyw3w6fL7r6
	yNHjUYwJxBiDsvLKuLw9BckAsLphHKg3BbKyskgUBdh38FAHVdMZQyQABE4E8fGtSuxiRosFEcnj
	dgERuYnIAwASnOU4oohicXyrVses0hsCs/csRfsPdxAFBllZWfX6O+kBDoKKosCx42UJTn7tfB7f
	Ku44AJQ6r0eiVEhm2W/xJ1+On/Hym+2s/TpnsTExNVVVVZ9GRUVl2yl1S4/InO+Uxvtij4Pl8mDt
	W0w8VlqWoLgUMGoCFOrBjWJAdXWN9PLsBbGcEwjMCvSIDGK83jIAqI1Yq7rttD/rhVkzcz5fPZgT
	BwSrWso5h7UbN185+x+ZgAiL4cxL9bXR0d4yxLocjXMOlZVVsdXVtWLodANoOhMUVNWQya5zAVkL
	geKSggBgRqqNM+f2FBwY+s3qTYOJTJJEwRQF5JKAXJFFI+/H/fGLFi8byzmJkeYBTYjhkuSAU4lH
	ACACCGq6Ak0M+Cl2gw288Iw3uXWnZQCEBMAIgIG1haXyyipvUwqeNWlmUjUFgOlSJBWdgr5VigZV
	010A0Pj08jTieEB3f5e1I4YN2ADImGHyRvmHwNjZCoZiUNXcdgy0dkEI4FIkFeqq0CelEQBRUR49
	OjqqkjHHCxGIOFTX1PgAwBOpNk6qiogFGVPuf2j6E5NfTk3xbzc5BwfjsyyeqpoaHxEHJ5wwxiAm
	JroiyutpBMBJl3OSCTWoUZvWvhJJFEHX9ZPRsvREeWsAiAeAYxBhGhyyafmeiLYXFBYv3J5X0Afo
	rALg6BRfWlbR2nlIRChJIrSJ95Woqmqr00wqnJGRgYZpQpeOHQ4pssStrI2AIcLxEycSDMPodCYa
	2sGNVdfWSueK+WAYRqfSEyfaMDsKciJUZIl3Tmp/yDA5ZGRk1Ou6HgDOfO3Vw1/ki4sp59wKXIKA
	VFZeHbV+05bejGGLqSzO904x31uMCyISYwzW5m7tXVZWFSUIzD6T5OCLiylP7e4vAmi8I2xuFdjX
	PjHhINlRkDFGtbVB2Lh55yDT5F6oq9OfNbEPjfTTvNakOGcPpml6czfvGFQbUIExK4slAmif2LYY
	LMJFI2kIgDMyR3t2T94mCqJzaoucOPywfU9/AOhpv3N2AECrROZyyQQA7RhjLfEwR5de23blX8yJ
	A9iHpaIgQq+U5G0A8JP9Tr226wGAiJSRkcEQ0Rgx7JI1sTEewzQ5AwKQRIGKDx9NXLFqw1WyJDVq
	qKVCBCgKDL74es0fHp324uLCfcWTiEiMsGJMRIQrVm646kDxT4mSKBAQgGlyFhvjMS7/w5C1iGjY
	tjUPAEDdHPEnd1jvT+5cYHJOgEiMIdUGgpC9fOV1qqb5T1dujkAQEeFEeWXr5SvW9c94blYmAAx0
	VqUwLHeM8mcv/+a6QCBouT8imZyDPzlprz+5w/pQ20KlkQEhZa6iy4cNWiHLElqjAUwSBdq6Pa/X
	ynXf3U5ELDMzs1nO36nEtA5a650XCojc61HMov2HEr/fsrtPcwo3MB5tHdjKdd/dtnVnfk9JEojI
	Kq7KsgQjhg9YAQBFDWxrHgC7YYaI5k3po5YmdWxXoukGIAIxxqg2EMR5C5dMBIDBWVlZddlG+KJ1
	69LpMCJDTTcEzjlwzoETYSCoCtHR3mD3lKSj4QAAAGjrMGTee0vurA2oyBgjRCBNNyC5U7ufx6WN
	XoqIZnPe2pwLO+63KX3MZdmiKKLFYiGmyCLflV/U8aVZ8x8nogSnOnxaTeviCx937ej30kYP2xgT
	HWV6PW7wejzgdruwY7vzayZNuOHdaI9nVYgeTStYt8ts++Ib7zy+a09RB4s7QIwIQBRFTBtzeTYA
	fAenSNyaHb2QDi6eeN/UD7fsyE+yWSDIOZEsiTB96oMvj7h00LRITodCagP+ogOHLjlWUupljBFH
	jr0u6HY0OtqzChFPnKrqFKKbe8XK9c889fc3HtYNAxgiIiIFVY1d1Dtl/4LZz95kZ5/N6tbs7svJ
	4QFg84P33jF38pRnZ9QGAigwBoLAMKhp+OzMt+47v+15vxDRK4iohQOCE9wQsQAACk4F0mmMl3fn
	Fzz43Mx596qahpJoLdmGaUJsTJTx0J8m/BMANp+ufB+W616YmvLOuPSRn3F+snOURJFKS8s9Dz/1
	4tS8H4seIiJ3uNPBssOm0mZkhPy2KLHhjPzu/IKHH37yxamlJ8o9tvGIiJxzYuPSR33Wt/cF88PJ
	J8JdZiyCxOPT569at6WXQ5BARK7pOov3xdX+9aG7Zo+8dMg/sI4gEdHBSRg6OEyR879cuf6RF16b
	d2/piXKPLFmHtgyZWRtUhUsvuWjX688/ORERt4TlkREowIko7dZJj83akVfYrimKzPVpoz577IGJ
	LwHAWgd9aiG/1zlHdAyw/x/64hsLHl2S89XValMUmZ7+w4vefOF+RFwWbkyKiCSlyDKVV1SMv+Pe
	qS/sKTiQ0CxJasKN7w4f3O9fbpdrT9DaggK0lCTlUiAQCKasXPfdze8sXDp+Z35hZ0FgJLCGJKmk
	kndnzZji88W8p2l62MTJFtHkampq7rj74czpO3cXtq9Hk0PgqlZHk0u78rKckZcNdmhyVRHS5KIB
	oNeKlRtG53yxMm3L9rw+tYFg0zS5nl0Pvz3z6Se8bvf7eC5ocg1BsImSaZOnzHjGIUoKgnDytNhm
	iILbrUBSh3aH+/buvnnAxb1zh/a/MJQoWQv1iZIecIiSuVtTN27Z4RAl2weCKkiiAHWMUeSmaTKT
	E/xh0IU7Xn/+iWmyJOXohhExW/RMqbIXz/zn+1MX53w1to4qiyeVCKXKetwK+OJiqs6L9x2P98Ue
	j472lrkUOQAAEFQ1d1VVja+0rKL1L6VlrcvKK6Nrm6TKWhQQhyp7U/roZQ/ec9vf8Qyosi09i4Np
	06axrKwsTkQJW3fmT3x97gd379i9t+uvRZaefM9tb1+YmjIfEY9lZGSwp59+mocz588KAI44kdam
	y/dftHT5nTmffzu2aP+hdqqmgygwEIQzpMubnBmmRZfvmtThyDWjL/301hvHLHApyiZV+y/R5UMl
	NHEhi+YyYEnOl9d+vTr3ir2FB/0VVVWyYTS+MBHaOYW0Ve/ChChCbLRX69a1c8GI4QNX3HjNqGz4
	LV2YCJXQkSDrykzXogNHBn+9av3QXXkFfQ8fLelYVl7hUzWd1V2ZsZWwwZFEARRF4r7Y2LL2iQkH
	U3t0+2HE8IHrkjt32AC/1SszodIwebGfSWCRE5Ly9hQkF+0/3OFYaVlCZWVVbFDTFAAElyypMTHR
	FW3ifSVdkjoe7Nk9eR8A7Idf4dLUORE61bU5gYHX08S1OY8bRKHxNuJcX5s75+KAEQLIb+ri5O9X
	Z3+X/3H5DygzbUAqGPJKAAAAAElFTkSuQmCC
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAATiElEQVR4nO1b
	eXhV1bX/rb3POXfITcgNmQRCVETSCjLI5IB+r60jwWL78ZwoIFpxeK/Pfm2pZbogiErt8NqKYqmI
	dND6tUVAS7XtewVKkRlBDQlTEqYkJDcJSe69Z9jr/XHuTW4mciOifn1d38dwz9137/X7rbX3Xnvt
	dYB/yf9voU9jUGbuclwi4k9alwsuzEzMLJhZcCgk+BykM0AcConW9t0Q9ZmXBOgQQqLTl7qESPeD
	mXVm9sb/6CLdD+iyU/MQQheUjI+107iSREQq6ZkOoB+AS6J7Dg5SZeUF5ukzeVx/tg9HYh4iYngN
	kzLTG7T87CptcGGld+SQwwCOADhFRFZSXwIAf5xT5WMjgJlFAjgzSwCDoweOXBvZuPk6a2/pcKf8
	ZKFd2xjUIyaRZQNKAQkYBEAIKF2D7TNY9s0Ia4X9yj0jP7fXN/GaLUbRpX8HcIiInI5jna+cNwHM
	TAmLMLMHwPizL6+/I/LW5hut948M1sJNOts2bEFQUoAFMYi408gMgJlIMQlHQVMM0jTYWQHL+Pyl
	pf6JN7yTNn3iHwC8S0SxjmN/VDkvAhKWEF4DTiQ2rmnl72c0/ebt21Fa0Y9jJixdgjWhAGodqL22
	yS7Q/n8c/5tsJXTLAXkMYMjAk4G7bloXeOArLwuf512OmuftDR+JAGYmEEAgZua8yLb99zU+9dID
	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
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
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAVgUlEQVR4nO1b
	eXQUVdb/3VdVXd3pLIQIKBAEkggBAsgelBEVxVGUuKGfyqIDw6iDI+PCDDqEOKCijOMGrqCCOoow
	BpQZQAeXYQkICGFJJAuETQOGhGy9VNW73x9dRZqkExJQx/N9c8/pc7qrq+579/fuu++++34F/Ff+
	fwv9Jxpl5ojtEhH/1H350YWZiZkFM4vMzEyBpkGnzMxM4dzfGFA/e3GMtg0+RVRVgdfrATNrzOy2
	P5rX64GqKg10hQHyo4Dxgyq1O0lEJMOuaQDaA+iya09BUvGBw4lHj5W1q6iqijMChg4i1lxqsFVM
	zIm2bRJKu3bqcLBXj5QiAMUAviUiI0yXAMA/5FT5wQBgZuEYzswKgJRviksuWvt5zsW78gv7HD7y
	3fnlFZXxgaBBhmlBSgnmkB1EBEECqqbA7dI4vlVseYf255akpaZsv/ySQetSunZeD6CQiKz6bZ2t
	nDUAzEzOiDCzDmDIB9mrr//ki5wrCor2pZyorNFMywIRIISAIGIiauDPbOuSzBQCB1AVBXGxXuOC
	5C57r7gk/ZObRl/5IYBNRBSo3/aZylkB4IyErrvg9wcGv7ts5YTslWuvK95/qH0gaEBVBRQhJBHZ
	JoY3yfUuhV23LzIzLCmFaUroLg1dO3c8kvHLy1bcdvM1b7rd+qZAIHjW3nBGADgBiYiYmdtt3bH7
	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
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
