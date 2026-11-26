# ======================================================================
# ::application::ask -- the Ask field (the palette input) and speech input.
#
# Decision 003 / D-7: the Ask field in the top strip *is* the palette.
# There is no separate palette window.
#
#   Typing matches the fixed command table against application slot sources.
#   Up/Down and clicks select; Enter runs the displayed action and arguments.
#   Missing slots focus their placeholder and offer state-owned candidates.
#   Questions are an explicit read-only mode, never an unmatched-text fallback.
#
#   Ctrl+K focuses the field and selects its text. D-2 is kept: in a
#   multi-line text editor (comment editor, PGN text, engine console /
#   Script) Ctrl+K still kills the line; Ctrl+Shift+K focuses the field
#   from anywhere. The key editor reports this precedence.
#
#   Speech input enters only here: the microphone button records (or runs
#   the configured stub), transcribes locally, and inserts the transcript
#   at the cursor. The text stays editable and is never sent until the
#   user presses Enter. Nothing is linked into the app for audio or
#   speech: recorders and recognisers are external subprocesses.
#
#   All platforms prefer sherpa-onnx-offline with a transducer model,
#   otherwise whisper-cli with GPU disabled. Recording uses arecord or
#   ffmpeg (PulseAudio on Linux, DirectShow on Windows, AVFoundation on
#   macOS). Windows/macOS retain native dictation when tools are missing.
#   Bundled tools are discovered under tests/tmp-app/speech-tools/bin.
#
#   ::application::ask::Build <notebook>   place the field in the top strip
#   ::application::ask::Focus              Ctrl+K / Ctrl+Shift+K
#   ::application::ask::Query              the current text
#   ::application::ask::Rows               the current result rows
#   ::application::ask::Preferences        Preferences > Assistant
#   ::application::speech::toggle          the microphone button
#   ::application::speech::available       is a speech path present?
#   ::application::speech::transcribeFile  transcribe one WAV (whisper-cli)
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-ask
}

package require Tcl 8.5
package require Tk 8.5

namespace eval application {
namespace eval ask {

namespace eval mc {
set Placeholder		"Type a command (Ctrl+K)"
set AskAssistant		"Ask the assistant"
set AskQuestion		"Ask a question"
set Commands		"Commands"
set Aliases			"Aliases"
set AliasesTitle	"Command aliases"
set AliasesHelp		"Select a command in Ask, then give it a short name."
set AliasesSave		"Save highlighted command"
set AliasesRemove	"Remove selected alias"
set AliasesNeedCommand	"Select a complete command in Ask first."
set AliasesSaved	"Saved. Type the exact alias in Ask, then press Enter."
set AliasesRemoved	"Alias removed."
set Send				"Send to the assistant"
set Mic				"Speak"
set Recording		"Recording… click to cancel"
set Transcribing	"Transcribing… click to cancel"
set Heard			"Heard: %s"
set NothingHeard	"Nothing heard"
set AssistantPrefs	"Assistant Preferences…"

# What the field itself says: a request the assistant could not take, and
# the Preferences > Assistant dialog.
set Unavailable		"The assistant is unavailable."
set Busy			"The assistant is busy. Try again when it finishes."
set Failed			"Error: %s"
set PrefsTitle		"Assistant"
set SpeechInput		"Speech input"
set StartupAssistant	"Show assistant at startup"
set SpeechReady		"A local speech path is configured."
set PathWhisper		"whisper-cli path"
set PathModel		"ggml model path"
set PathRecorder	"Recorder (arecord/ffmpeg)"
set PathSherpa		"sherpa-onnx-offline path"
set PathSherpaModel	"sherpa-onnx model folder"
set PathHotwords	"Hotwords file (optional)"
set PathStub		"Test stub command (optional)"
set Detect			"Detect"
set Close			"Close"

# The registry row that reaches Preferences > Assistant (menus, the Ask
# list and the assistant all show these).
set PrefsWhat		"open the Assistant preferences"
set PrefsDoc		"Choose the local speech tools (whisper-cli, model, recorder) and see what to install when speech input is not available."

# English defaults, restored before every language load (see i18n.tcl),
# so switching back to English brings the field's own text back and a
# language that translates none of these strings shows English rather
# than the previous language's text.
set ::application::ask::DefaultMC {}
foreach _name [lsort [info vars ::application::ask::mc::*]] {
	if {[array exists $_name] || [string index [namespace tail $_name] 0] eq "_"} { continue }
	lappend ::application::ask::DefaultMC [namespace tail $_name] [set $_name]
}
unset _name
}

variable Mode command
variable Query ""
variable FmtCache [dict create]
variable ListTexts {}
variable ListGeom ""
variable ListIndex -1
variable RowHeight ""
variable Priv
array set Priv {
	index		0
	rows		{}
	focusBefore	{}
	histIndex	-1
	list		{}
	listVisible	0
	prewarmAfter	{}
	prewarmDeferred	0
	prewarmed	0
	lastTheme	{}
	refreshAfter	{}
	blinkAfter	{}
	blinkPaused	0
	window		{}
	prefs		{}
	prefsStartup	{}
	prefsTitle	{}
	prefsHint	{}
	prefsStatus	{}
	prefsDetect	{}
	prefsClose	{}
	prefsFields	{}
}

} ;# namespace ask
} ;# namespace application

proc ::application::ask::ResetMC {} {
	foreach {name value} $::application::ask::DefaultMC {
		set ::application::ask::mc::$name $value
	}
	return
}
if {[llength [info commands ::mc::addDefaultReset]]} {
	::mc::addDefaultReset ::application::ask::ResetMC
}

# ======================================================================
# The field itself.
# ======================================================================
proc ::application::ask::Entry {} {
	return .application.nb.ask.entry
}

proc ::application::ask::Mic {} {
	return .application.nb.ask.mic
}

proc ::application::ask::Build {notebook} {
	variable Priv
	variable Query

	if {[winfo exists $notebook.ask]} { return $notebook.ask }

	set frame [ttk::frame $notebook.ask]
	if {[tk windowingsystem] eq "aqua"} {
		# Tk 8.6's ttk::entry uses a hardcoded 600/300 ms cursor blink timer
		# that is not reset while typing and cannot be configured via
		# -insertofftime; on Aqua each blink invalidates the entire .application
		# NSView (~35-65 ms), colliding with keystroke 2 (~600 ms after focus).
		# Use tk::entry on Aqua so PauseBlink can hold the caret steady while
		# typing and resume blinking after idle.
		set entry [tk::entry $frame.entry -takefocus 1 -exportselection 0 \
			-textvariable ::application::ask::Query -font TkTextFont \
			-borderwidth 1 -relief solid -highlightthickness 1 \
			-insertofftime 0]
		set Priv(blinkPaused) 1
	} else {
		set entry [ttk::entry $frame.entry -takefocus 1 \
			-textvariable ::application::ask::Query]
		set Priv(blinkPaused) 0
	}
	# The strip is only as tall as the notebook tabs: no vertical padding,
	# or large desktop fonts cut the button labels.
	ttk::style configure AskStrip.TButton -padding {6 0}
	set mic [ttk::button $frame.mic -text $::application::ask::mc::Mic \
		-style AskStrip.TButton -takefocus 0 -command ::application::speech::toggle]
	ttk::button $frame.mode -text $::application::ask::mc::AskQuestion -style AskStrip.TButton \
		-takefocus 0 -command ::application::ask::ToggleMode
	ttk::button $frame.alias -text $::application::ask::mc::Aliases -style AskStrip.TButton \
		-takefocus 0 -command ::application::ask::Aliases
 pack $frame.alias -side right
 pack $frame.mode -side right
	pack $mic -side right -padx {2 2}
	# Own mouse gestures; the class binding invokes -command only on release.
	bind $mic <ButtonPress-1> {::application::speech::Press %W; break}
	bind $mic <ButtonRelease-1> {::application::speech::Release %W; break}
	pack $entry -side left -fill x -expand yes -padx {2 2} -pady 1

	set Priv(entry) $entry
	StyleEntry
	set placeholderBg [expr {[::theme::isDark] ? [::ttk::style lookup TEntry -fieldbackground] : ""}]
	if {[tk windowingsystem] eq "aqua"} {
		set placeholderBg [$entry cget -background]
	}
	set placeholder [ttk::label $frame.placeholder \
		-text [PlaceholderText] \
		-foreground [expr {[::theme::isDark] ? "#8b949e" : "grey"}] \
		-background $placeholderBg]
	place $placeholder -in $entry -relx 0 -x 4 -rely 0.5 -anchor w -relwidth 1 -width -8
	bind $placeholder <ButtonPress-1> ::application::ask::Focus
	bind $frame <<ThemeChanged>> [namespace code ThemeChanged]

	bind $entry <KeyRelease> [namespace code [list Typed %K]]
	bind $entry <Down> [namespace code [list Move 1]]
	bind $entry <Up> [namespace code [list Move -1]]
	bind $entry <Return> [namespace code Choose]
	bind $entry <KP_Enter> [namespace code Choose]
	bind $entry <Escape> [namespace code Escape]
	bind $entry <F1> [namespace code Help]
	bind $entry <FocusIn> [namespace code [list EnterField $entry $placeholder]]
	bind $entry <FocusOut> [namespace code [list LeaveField $entry $placeholder]]
	bind $entry <Button-1> +[namespace code { after idle ::application::ask::Typed {} }]

	set Priv(entry) $entry
	set Priv(frame) $frame
	set Priv(placeholder) $placeholder
	set Priv(mic) $mic
	set Priv(notebook) $notebook
	set Priv(filtered) ""
	set Priv(lastTheme) [list [::theme::currentTheme] [::theme::isDark]]
	bind $frame <Destroy> +::application::speech::CleanupSession
	bind $frame <Destroy> +[namespace code CancelPrewarm]
	bind $frame <Destroy> +[namespace code CancelRefresh]
	bind $frame <Destroy> +[namespace code CancelBlink]
	# a language switch relabels the field in place (i18n.tcl generates
	# the event for every widget); typing is never touched
	bind $frame <<LanguageChanged>> [namespace code Relabel]

	SyncMic
	PlaceholderState
	RegisterAction
 ::commandline::RegisterActions
	catch { InstallShortcutTags $notebook }
	# Run filtering synchronously right after Entry/TEntry inserts a character
	# on KeyPress, instead of waiting for KeyRelease (which adds hold latency
	# and a second native display pass on Aqua). KeyRelease remains as a
	# fallback for IME/paste paths; Typed short-circuits when unchanged.
	set tags [bindtags $entry]
	set entryClass [winfo class $entry]
	if {"AskEntry" ni $tags} {
		set pos [lsearch -exact $tags $entryClass]
		if {$pos >= 0} {
			bindtags $entry [linsert $tags [expr {$pos + 1}] AskEntry]
		} else {
			bindtags $entry [linsert $tags 1 AskEntry]
		}
	}
	return $frame
}

# The localized field hint names the shortcut of this platform. The
# language files spell the Control key (Ctrl+K, German Strg+K); on aqua
# the same key is Command, exactly as ::menu::FormatAccel displays it.
proc ::application::ask::PlaceholderText {} {
	set text $::application::ask::mc::Placeholder
	if {[llength [info commands ::menu::Aqua?]] && [::menu::Aqua?]} {
		set text [string map {Ctrl+ Cmd+ Strg+ Cmd+} $text]
	}
	return $text
}

# Keep the placeholder visible exactly while the field is empty.
proc ::application::ask::PlaceholderState {} {
	variable Priv
	variable Query

	if {![info exists Priv(placeholder)] || ![winfo exists $Priv(placeholder)]} { return }
	if {[string length $Query]} {
		if {[winfo manager $Priv(placeholder)] ne ""} {
			place forget $Priv(placeholder)
		}
	} elseif {[winfo manager $Priv(placeholder)] ne "place"} {
		place $Priv(placeholder) -in $Priv(entry) -relx 0 -x 4 -rely 0.5 -anchor w -relwidth 1 -width -8
	}
}

proc ::application::ask::InvalidateCache {} {
	variable Priv
	variable FmtCache
	variable ListGeom
	variable ListIndex
	variable RowHeight
	set FmtCache [dict create]
	set ListGeom ""
	set ListIndex -1
	set RowHeight ""
	unset -nocomplain Priv(filtered)
	return
}

proc ::application::ask::CancelRefresh {} {
	variable Priv
	if {[info exists Priv(refreshAfter)] && $Priv(refreshAfter) ne ""} {
		catch { after cancel $Priv(refreshAfter) }
		set Priv(refreshAfter) ""
	}
	return
}

# Coalesce bursts of registry/predicate/state invalidations into one idle
# refresh when the Ask result list is currently open.
proc ::application::ask::ScheduleRefresh {} {
	variable Priv
	if {[info exists ::menu::SwitchingLanguage] && $::menu::SwitchingLanguage} {
		return
	}
	if {![ListVisible]} { return }
	if {[info exists Priv(refreshAfter)] && $Priv(refreshAfter) ne ""} {
		return
	}
	set Priv(refreshAfter) [after idle [namespace code RefreshOpenList]]
	return
}

proc ::application::ask::RefreshOpenList {} {
	variable Priv
	variable Query
	CancelRefresh
	if {![ListVisible]} { return }
	set text [string trim $Query]
	if {$text eq ""} {
		set Priv(rows) {}
		HideList
		return
	}
	set Priv(filtered) $text
	PopulateRows $text
	if {$Priv(index) >= [llength $Priv(rows)] + 1} { set Priv(index) 0 }
	ShowList
	return
}

proc ::application::ask::PrewarmBlocked {} {
	if {[llength [info commands grab]]} {
		set currentGrab ""
		catch { set currentGrab [grab current] }
		if {$currentGrab ne ""} { return 1 }
	}
	if {[DialogOpen]} { return 1 }
	return 0
}

proc ::application::ask::CancelPrewarm {} {
	variable Priv
	if {[info exists Priv(prewarmAfter)] && $Priv(prewarmAfter) ne ""} {
		catch { after cancel $Priv(prewarmAfter) }
		set Priv(prewarmAfter) ""
	}
	set Priv(prewarmDeferred) 0
	return
}

proc ::application::ask::SchedulePrewarm {} {
	variable Priv
	CancelPrewarm
	set Priv(prewarmAfter) [after idle [namespace code Prewarm]]
	return
}

# Push a pending Prewarm past active typing so it never fires between
# keystrokes, without losing the deferred work once typing goes quiet
# (or when the Ask list closes).
proc ::application::ask::DeferPrewarm {{delayMs 300}} {
	variable Priv
	if {![info exists Priv(prewarmAfter)] || $Priv(prewarmAfter) eq ""} {
		return 0
	}
	catch { after cancel $Priv(prewarmAfter) }
	set Priv(prewarmDeferred) 1
	set Priv(prewarmAfter) [after $delayMs [namespace code Prewarm]]
	return 1
}

proc ::application::ask::EnsureListWidget {} {
	variable Priv
	variable ListTexts
	variable ListGeom
	variable ListIndex
	variable RowHeight

	set w $Priv(list)
	if {$w ne "" && [winfo exists $w]} { return 0 }
	set w .application.askList
	catch { destroy $w }
	toplevel $w -class AskList
	wm overrideredirect $w 1
	wm transient $w .application
	listbox $w.list -exportselection 0 -takefocus 0 -activestyle none \
		-height 1 -borderwidth 1 -relief solid -highlightthickness 0
	ttk::scrollbar $w.scroll -orient horizontal -command [list $w.list xview]
	$w.list configure -xscrollcommand [list $w.scroll set]
	pack $w.scroll -side bottom -fill x
	pack $w.list -fill both -expand yes
	bind $w.list <ButtonPress-1> "[list ::application::ask::Click] %y"
	bind $w.list <ButtonRelease-1> { break }
	bind $w.list <Double-Button-1> { break }
	set Priv(list) $w
	set Priv(listVisible) 0
	set ListTexts {}
	set ListGeom ""
	set ListIndex -1
	set RowHeight [expr {[font metrics [$w.list cget -font] -linespace] + 4}]
	return 1
}

proc ::application::ask::Prewarm {} {
	variable Priv
	variable FmtCache
	variable RowHeight

	set Priv(prewarmAfter) ""
	set Priv(prewarmDeferred) 0
	if {![winfo exists [Entry]]} { return }
	if {![info exists ::application::Vars(ready)] || !$::application::Vars(ready)} { return }
	if {[PrewarmBlocked]} {
		# Defer popup creation and registry evaluation while a grab or modal
		# dialog is active; reschedule via timer so update never spins on idle.
		set Priv(prewarmAfter) [after 250 [namespace code Prewarm]]
		return
	}
	if {[EnsureListWidget]} {
		set w $Priv(list)
		if {[tk windowingsystem] eq "aqua"} {
			# Keep the Aqua popup NSWindow warm and hidden offscreen so the
			# first Ask keystroke avoids macOS WindowServer creation latency.
			catch { wm attributes $w -alpha 0.0 }
			catch { wm geometry $w 1x1+-10000+-10000 }
			catch { wm deiconify $w }
		} else {
			catch { wm withdraw $w }
		}
		set Priv(listVisible) 0
	} elseif {$RowHeight eq "" && [winfo exists $Priv(list).list]} {
		set RowHeight [expr {[font metrics [$Priv(list).list cget -font] -linespace] + 4}]
	}
	if {[llength [info commands ::action::labels]]} {
		if {![catch { set rows [::action::labels asklist ""] }]} {
			if {[dict size $FmtCache] > 4096} { set FmtCache [dict create] }
			foreach row $rows {
				lassign $row id label accel
				set key [list $label $accel]
				if {![dict exists $FmtCache $key]} {
					set plain [lindex [::menu::AmpText $label] 0]
					dict set FmtCache $key [format " %-48s %s" [string trimleft $plain] $accel]
				}
			}
		}
	}
	set Priv(prewarmed) 1
	return
}

proc ::application::ask::StyleEntry {} {
	variable Priv
	if {[tk windowingsystem] ne "aqua"} { return }
	if {![info exists Priv(entry)] || ![winfo exists $Priv(entry)]} { return }
	if {[winfo class $Priv(entry)] ne "Entry"} { return }
	if {[::theme::isDark]} {
		set bg [::ttk::style lookup TEntry -fieldbackground]
		if {$bg eq ""} { set bg "#1b1f27" }
		set fg [::ttk::style lookup TEntry -foreground]
		if {$fg eq ""} { set fg "#e6edf3" }
		$Priv(entry) configure -background $bg -foreground $fg \
			-insertbackground $fg -selectbackground "#2f6feb" \
			-selectforeground "#ffffff" -highlightbackground "#30363d" \
			-highlightcolor "#58a6ff"
	} else {
		$Priv(entry) configure -background "#ffffff" -foreground "#000000" \
			-insertbackground "#000000" -selectbackground "#b3d7ff" \
			-selectforeground "#000000" -highlightbackground "#c0c0c0" \
			-highlightcolor "#4a90d9"
	}
	return
}

proc ::application::ask::CancelBlink {} {
	variable Priv
	if {[info exists Priv(blinkAfter)] && $Priv(blinkAfter) ne ""} {
		catch { after cancel $Priv(blinkAfter) }
		set Priv(blinkAfter) ""
	}
	return
}

proc ::application::ask::PauseBlink {} {
	variable Priv
	if {[tk windowingsystem] ne "aqua"} { return }
	if {![info exists Priv(entry)] || ![winfo exists $Priv(entry)]} { return }
	if {[winfo class $Priv(entry)] ne "Entry"} { return }
	CancelBlink
	if {![info exists Priv(blinkPaused)] || !$Priv(blinkPaused)} {
		catch { $Priv(entry) configure -insertofftime 0 }
		set Priv(blinkPaused) 1
	}
	set Priv(blinkAfter) [after 1500 [namespace code ResumeBlink]]
	return
}

proc ::application::ask::ResumeBlink {} {
	variable Priv
	set Priv(blinkAfter) ""
	if {[tk windowingsystem] ne "aqua"} { return }
	if {![info exists Priv(entry)] || ![winfo exists $Priv(entry)]} { return }
	if {[winfo class $Priv(entry)] ne "Entry"} { return }
	if {[focus] ne $Priv(entry)} { return }
	if {[info exists Priv(blinkPaused)] && $Priv(blinkPaused)} {
		catch { $Priv(entry) configure -insertofftime 300 }
		set Priv(blinkPaused) 0
	}
	return
}

proc ::application::ask::ThemeChanged {} {
	variable Priv
	set themeKey [list [::theme::currentTheme] [::theme::isDark]]
	if {[info exists Priv(lastTheme)] && $Priv(lastTheme) eq $themeKey} {
		return
	}
	set Priv(lastTheme) $themeKey
	set Priv(prewarmed) 0
	InvalidateCache
	StyleEntry
	if {[info exists Priv(placeholder)] && [winfo exists $Priv(placeholder)]} {
		set bg [expr {[::theme::isDark] ? [::ttk::style lookup TEntry -fieldbackground] : ""}]
		if {[tk windowingsystem] eq "aqua" && [info exists Priv(entry)] && [winfo exists $Priv(entry)]} {
			set bg [$Priv(entry) cget -background]
		}
		$Priv(placeholder) configure \
			-foreground [expr {[::theme::isDark] ? "#8b949e" : "grey"}] \
			-background $bg
	}
	if {[ListVisible]} {
		RefreshOpenList
	} else {
		SchedulePrewarm
	}
}

proc ::application::ask::EnterField {entry placeholder} {
	variable Priv
	PauseBlink
	PlaceholderState
	if {$Priv(list) eq "" || ![winfo exists $Priv(list)] \
	 || ![info exists Priv(prewarmed)] || !$Priv(prewarmed)} {
		SchedulePrewarm
	}
}

proc ::application::ask::LeaveField {entry placeholder} {
	CancelBlink
	PlaceholderState
}

# The microphone button's text for the state speech input is in; the busy
# states are how a recording or a transcription announces itself.
proc ::application::ask::MicText {} {
	if {[info exists ::application::speech::Priv(state)]} {
		switch -- $::application::speech::Priv(state) {
			recording		{ return $::application::speech::mc::Listening }
			transcribing	{ return $::application::speech::mc::Working }
		}
	}
	return $::application::ask::mc::Mic
}

# A language switch: everything the field owns follows the new language,
# the user's own text does not. The placeholder is a separate label, so it
# takes the new text while the field is empty and stays out of the way (and
# never overwrites what was typed) when it is not. The microphone is
# relabelled for the state it is in, an open result list redraws so its
# last row -- "Ask the assistant" -- is in the new language, and a
# Preferences > Assistant dialog left open relabels itself.
proc ::application::ask::Relabel {} {
	variable Priv
	variable Mode
	variable mc

	RegisterAction
	if {[llength [info commands ::action::InvalidateAskRows]]} {
		::action::InvalidateAskRows
	} else {
		InvalidateCache
	}
	if {[info exists Priv(placeholder)] && [winfo exists $Priv(placeholder)]} {
		$Priv(placeholder) configure -text [PlaceholderText]
	}
	if {[info exists Priv(frame)] && [winfo exists $Priv(frame)]} {
		if {[winfo exists $Priv(frame).mode]} {
			$Priv(frame).mode configure -text [expr {$Mode eq "command" ? $mc::AskQuestion : $mc::Commands}]
		}
		if {[winfo exists $Priv(frame).alias]} {
			$Priv(frame).alias configure -text $mc::Aliases
		}
	}
	PlaceholderState
	if {[info exists Priv(mic)] && [winfo exists $Priv(mic)]} {
		$Priv(mic) configure -text [MicText]
	}
	SyncMic
	RelabelPreferences
	RelabelAliases
	if {[info exists ::menu::SwitchingLanguage] && $::menu::SwitchingLanguage} {
		return
	}
	set Priv(prewarmed) 0
	if {[ListVisible]} {
		RefreshOpenList
	} else {
		SchedulePrewarm
	}
	return
}

proc ::application::ask::RelabelAliases {} {
	variable mc
	set w .application.commandAliases
	if {![winfo exists $w]} { return }
	wm title $w $mc::AliasesTitle
	$w.help configure -text $mc::AliasesHelp
	$w.save configure -text $mc::AliasesSave
	$w.remove configure -text $mc::AliasesRemove
	return
}

# Put the field in the top strip, immediately left of the main drop-down.
proc ::application::ask::Place {menuX height} {
	variable Priv
	variable Width

	if {![info exists Priv(frame)] || ![winfo exists $Priv(frame)]} { return }
	if {![info exists Width]} { set Width 380 }
	# The Speak button and translated labels can need more than the default.
	set width [expr {max($Width, [winfo reqwidth $Priv(frame)])}]
	set x [expr {$menuX - $width - 4}]
	# never cover the notebook tabs on the left
	set left 286
	if {$x < $left} {
		set x $left
		set width [expr {$menuX - $left - 4}]
		if {$width < 120} { set width 120 }
	}
	place $Priv(frame) -x $x -y 0 -width $width -height [expr {$height + 2}]
}

# Show or hide the microphone with the current speech path.
proc ::application::ask::SyncMic {} {
	variable Priv

	if {![info exists Priv(mic)] || ![winfo exists $Priv(mic)]} { return }
	set Priv(micHint) [::application::speech::hint]
	if {$Priv(micHint) eq ""} { set Priv(micHint) $::application::ask::mc::Mic }
	::tooltip::tooltip $Priv(mic) ::application::ask::Priv(micHint)
	if {[llength [info commands ::application::speech::available]] \
	 && [::application::speech::available]} {
		if {[manager::place? $Priv(mic)] eq ""} {
			pack $Priv(mic) -side right -padx {2 2}
			after idle { catch ::application::PlaceMenues }
		}
	} else {
		if {[manager::place? $Priv(mic)] ne ""} {
			pack forget $Priv(mic)
			after idle { catch ::application::PlaceMenues }
		}
	}
}

# A tiny helper so package changes re-pack the button only once.
namespace eval ::application::ask::manager {
	proc place? {w} {
		if {![winfo exists $w]} { return "" }
		foreach slave [pack slaves [winfo parent $w]] {
			if {$slave eq $w} { return "packed" }
		}
		return ""
	}
}

# The Ask field is a registry action too, so menus/palette/assistant can
# reach Preferences > Assistant without adding a drop-down row (the
# frozen drop-down fixture stays untouched).
proc ::application::ask::RegisterAction {} {
	variable mc

	set record [dict create \
		label    $mc::AssistantPrefs \
		object   {} \
		handler  [list ::application::ask::Preferences] \
		what     $mc::PrefsWhat \
		ai       1 \
		doc      $mc::PrefsDoc \
	]
	if {[dict exists $::action::Registry app.preferences.assistant]} {
		# already registered: a language switch only refreshes the text it
		# shows, the handler and the assistant flag stay as they are
		set old [::action::get app.preferences.assistant]
		foreach key {label what doc} {
			dict set old $key [dict get $record $key]
		}
		dict set ::action::Registry app.preferences.assistant $old
		if {[llength [info commands ::action::NoteRegistryChange]]} {
			::action::NoteRegistryChange
		}
		return
	}
	::action::register app.preferences.assistant $record
	return
}

# ======================================================================
# Focus and startup.
# ======================================================================
# Resolve actions against the pane that owned focus before entering Ask.
proc ::application::ask::ContextFocus {} {
	variable Priv
	set current [focus]
	if {($current eq [Entry] || [string match ".application.nb.ask.*" $current])
	 && [info exists Priv(focusBefore)] && [winfo exists $Priv(focusBefore)]} {
		return $Priv(focusBefore)
	}
	return $current
}

proc ::application::ask::Focus {} {
	variable Priv
	variable FmtCache

	if {![winfo exists [Entry]]} { return 0 }
	set current [focus]
	if {$current ne [Entry]} { set Priv(focusBefore) $current }
	if {$Priv(focusBefore) eq "" && [BoardWidget] ne ""} {
		set Priv(focusBefore) [BoardWidget]
	}
	focus -force [Entry]
	PauseBlink
	catch { [Entry] selection range 0 end }
	if {$Priv(list) eq "" || ![winfo exists $Priv(list)] \
	 || ![info exists Priv(prewarmed)] || !$Priv(prewarmed)} {
		SchedulePrewarm
	}
	return 1
}

proc ::application::ask::StartupFocus {} {
	if {[DialogOpen]} { return }
	Focus
}

# A modal/toplevel dialog (other than the main window) that is mapped and
# visible: the startup focus must not steal the keyboard from it.
proc ::application::ask::DialogOpen {} {
	foreach w [winfo children .] {
		if {$w eq ".application"} { continue }
		if {[catch { wm state $w } state]} { continue }
		if {$state eq "normal" && [winfo ismapped $w]} { return 1 }
	}
	return 0
}

proc ::application::ask::BoardWidget {} {
	if {[info exists ::application::board::Vars(widget:frame)] \
	 && [winfo exists $::application::board::Vars(widget:frame)]} {
		return $::application::board::Vars(widget:frame)
	}
	return ""
}

proc ::application::ask::Escape {} {
	variable Priv

	HideList
	unset -nocomplain Priv(filtered)
	if {[info exists Priv(focusBefore)] && $Priv(focusBefore) ne "" \
	 && $Priv(focusBefore) ne [Entry] && [winfo exists $Priv(focusBefore)]} {
		focus -force $Priv(focusBefore)
	} elseif {[BoardWidget] ne ""} {
		focus -force [BoardWidget]
	}
	return "break"
}

proc ::application::ask::Help {} {
	::help::open .application Ask-Field
	return -code break
}

# Ctrl+K and Ctrl+Shift+K are bound on a private tag in front of the
# class. In Text/Script widgets Ctrl+K falls through to the class
# kill-line binding; Ctrl+Shift+K breaks before it and focuses the field.
proc ::application::ask::CtrlK {} {
	if {[InMultilineEditor]} { return }
	Focus
	# This private tag runs before the widget class. Stop the chain or the
	# class Control-k binding (TEntry/Entry delete from the cursor to end)
	# also runs: it wiped the Ask field and truncated any other entry.
	return -code break
}

proc ::application::ask::CtrlShiftK {} {
	Focus
}

# Ctrl+Shift+K must be seen before the class bindings that eat Control-K
# (the engine console's Script bindings kill the line for both cases).
# A private bindtag placed just before the widget's class tag reserves it;
# Ctrl+K itself still falls through to the class binding (kill-line).
proc ::application::ask::AttachShortcutTag {w} {
	if {![winfo exists $w]} { return }
	set top [winfo toplevel $w]
	if {$top ne ".application" && ![string match ".application.*" $top]} { return }
	set tags [bindtags $w]
	if {"AskShortcut" in $tags} { return }
	set class [winfo class $w]
	set pos [lsearch -exact $tags $class]
	if {$pos < 0} { set pos 1 }
	catch { bindtags $w [linsert $tags $pos AskShortcut] }
	return
}

proc ::application::ask::InstallShortcutTags {{w .application}} {
	if {![winfo exists $w]} { return }
	AttachShortcutTag $w
	foreach child [winfo children $w] { InstallShortcutTags $child }
	return
}

bind AskShortcut <Control-Key-k> {::application::ask::CtrlK}
bind AskShortcut <Control-Key-K> {::application::ask::CtrlShiftK; break}
bind AskEntry <KeyPress> {::application::ask::Typed %K}

proc ::application::ask::InMultilineEditor {} {
	set w [focus]
	if {$w eq ""} { return 0 }
	set class [winfo class $w]
	if {$class in {Text Comment Script}} { return 1 }
	if {"Script" in [bindtags $w]} { return 1 }
	return 0
}

# ======================================================================
# Filtering and the result list.
# ======================================================================
proc ::application::ask::Typed {{key ""}} {
	variable Priv
	variable Query

	PlaceholderState
	if {![winfo exists [Entry]]} { return }
	PauseBlink

	# KeyRelease follows every KeyPress, including the navigation keys.
	# Only a real text change may refilter and reset the selection.
	if {$key in {Up Down Return KP_Enter Escape Tab ISO_Left_Tab}} { return }
	set text [string trim $Query]
	if {$text ne ""} { DeferPrewarm }
	if {[info exists Priv(filtered)] && $Priv(filtered) eq $text \
	 && [ListVisible]} {
		return
	}
	CancelRefresh
	set Priv(filtered) $text

	if {$text eq ""} {
		if {$Priv(rows) ne {} || [ListVisible]} {
			set Priv(rows) {}
			HideList
		}
		return
	}
	PopulateRows $text
	set Priv(context) [CommandContext]
	set Priv(index) 0
	ShowList
}

proc ::application::ask::PopulateRows {text} {
	variable Priv
	set Priv(commands) {}
	set Priv(rows) {}
	if {$::application::ask::Mode ne "question"} {
		# The typed command grammar first, then the registry palette: the
		# 200+ menu actions must stay reachable exactly as before.
		foreach row [::commandline::Suggest $text] {
			lappend Priv(commands) $row
			lappend Priv(rows) [list [dict get $row action] [dict get $row label] Enter 1 1]
		}
		set seen {}
		foreach row $Priv(commands) { dict set seen [dict get $row action] 1 }
		foreach paletteRow [::action::labels asklist $text] {
			lassign $paletteRow id label accel enabled visible
			if {[string match command.* $id] || [dict exists $seen $id]} { continue }
			dict set seen $id 1
			lappend Priv(commands) [dict create id $id action $id args {} missing {} \
				template {} label $label input $text palette 1]
			lappend Priv(rows) [list $id $label $accel $enabled $visible]
		}
	}
	return
}

proc ::application::ask::ShowList {} {
	variable Priv
	variable Query
	variable mc
	variable FmtCache
	variable ListTexts
	variable ListGeom
	variable ListIndex
	variable RowHeight

	set rows $Priv(rows)
	if {[dict size $FmtCache] > 4096} { set FmtCache [dict create] }
	set texts {}
	foreach row $rows {
		lassign $row id label accel
		# The registry label is Tk menu markup ("&Quit", "&&" for a literal
		# "&"). Cache formatted row strings so typing never re-strips and
		# re-formats hundreds of rows on every keystroke.
		set key [list $label $accel]
		if {[dict exists $FmtCache $key]} {
			lappend texts [dict get $FmtCache $key]
		} else {
			set plain [lindex [::menu::AmpText $label] 0]
			set text [format " %-48s %s" [string trimleft $plain] $accel]
			dict set FmtCache $key $text
			lappend texts $text
		}
	}
	# Pad the permanent trailing assistant row so it remains the widest item in
	# the listbox; deleting shorter action rows then never triggers Tk's O(N)
	# maxWidth CoreText rescan across hundreds of remaining rows.
	lappend texts [format " %-96s" $mc::AskAssistant]
	set count [llength $texts]

	set wasVisible [ListVisible]
	set opening [EnsureListWidget]
	set w $Priv(list)
	set list $w.list
	# Consecutive prefixes often keep almost all rows in the same order.
	# Avoid copying the widget contents out on every key, and strip any
	# identical leading/trailing slices so unchanged rows are not re-measured
	# by Tk/CoreText on every keystroke.
	set listChanged 0
	if {$opening || $ListTexts ne $texts} {
		set listChanged 1
		set oldLen [llength $ListTexts]
		if {!$opening && $oldLen > 0 && $count > 0 && [$list size] == $oldLen} {
			set p 0
			set minLen [expr {$oldLen < $count ? $oldLen : $count}]
			while {$p < $minLen && [lindex $ListTexts $p] eq [lindex $texts $p]} {
				incr p
			}
			set oldEnd [expr {$oldLen - 1}]
			set newEnd [expr {$count - 1}]
			while {$oldEnd >= $p && $newEnd >= $p \
			 && [lindex $ListTexts $oldEnd] eq [lindex $texts $newEnd]} {
				incr oldEnd -1
				incr newEnd -1
			}
			if {$oldEnd >= $p || $newEnd >= $p} {
				set didMiddle 0
				if {($oldEnd - $p) >= 40 && ($newEnd - $p) >= 40} {
					# Even when rows above and below a large block change (e.g.
					# high- and low-scoring rows around 400 synthetic rows),
					# anchor on the midpoint so the unchanged block is kept in place.
					set mid [expr {($p + $newEnd) / 2}]
					set oldMid [lsearch -exact -start $p $ListTexts [lindex $texts $mid]]
					if {$oldMid >= $p && $oldMid <= $oldEnd} {
						set oLo $oldMid
						set nLo $mid
						while {$oLo > $p && $nLo > $p \
						 && [lindex $ListTexts [expr {$oLo - 1}]] eq [lindex $texts [expr {$nLo - 1}]]} {
							incr oLo -1
							incr nLo -1
						}
						set oHi $oldMid
						set nHi $mid
						while {$oHi < $oldEnd && $nHi < $newEnd \
						 && [lindex $ListTexts [expr {$oHi + 1}]] eq [lindex $texts [expr {$nHi + 1}]]} {
							incr oHi
							incr nHi
						}
						if {($oHi - $oLo + 1) >= 32} {
							if {$oldEnd > $oHi} { $list delete [expr {$oHi + 1}] $oldEnd }
							if {$newEnd > $nHi} { $list insert [expr {$oHi + 1}] {*}[lrange $texts [expr {$nHi + 1}] $newEnd] }
							if {$oLo > $p} { $list delete $p [expr {$oLo - 1}] }
							if {$nLo > $p} { $list insert $p {*}[lrange $texts $p [expr {$nLo - 1}]] }
							set didMiddle 1
						}
					}
				}
				if {!$didMiddle} {
					if {$oldEnd >= $p} {
						$list delete $p $oldEnd
					}
					if {$newEnd >= $p} {
						$list insert $p {*}[lrange $texts $p $newEnd]
					}
				}
			}
		} else {
			$list delete 0 end
			$list insert end {*}$texts
		}
		set ListTexts $texts
	}
	if {$count} {
		if {$Priv(index) < 0} { set Priv(index) 0 }
		if {$Priv(index) >= $count} { set Priv(index) [expr {$count - 1}] }
		if {[$list curselection] ne $Priv(index)} {
			$list selection clear 0 end
			$list selection set $Priv(index)
		}
		if {[$list index active] != $Priv(index)} { $list activate $Priv(index) }
		if {$opening || $listChanged || $ListIndex != $Priv(index)} {
			$list see $Priv(index)
			set ListIndex $Priv(index)
		}
	}

	set entry [Entry]
	if {[winfo exists $entry]} {
		set x [winfo rootx $entry]
		set y [expr {[winfo rooty $entry] + [winfo height $entry] + 2}]
		set width [expr {[winfo width $entry] + [winfo width [Mic]] + 8}]
		if {$RowHeight eq ""} {
			set RowHeight [expr {[font metrics [$list cget -font] -linespace] + 4}]
		}
		if {$count <= 20} {
			set listFont [$list cget -font]
			foreach text $texts {
				set width [expr {max($width, [font measure $listFont [string trimright $text]] + 24)}]
			}
		}
		if {![catch { lassign [winfo workarea .application] wx wy ww wh }] && $ww > 32} {
			set width [expr {min($width, $ww - 16)}]
			set x [expr {max($wx, min($x, $wx + $ww - $width))}]
		}
		set height [expr {min(320, max($RowHeight, $count * $RowHeight + 24))}]
		set geom "${width}x${height}+${x}+${y}"
		# Avoid redundant wm geometry calls on Aqua: even an unchanged
		# geometry triggers a native Cocoa window frame/display cycle.
		if {$opening || $ListGeom ne $geom} {
			wm geometry $w $geom
			set ListGeom $geom
		}
	}
	# Reordering an already visible Aqua window forces another native
	# display pass on every key. On Aqua, HideList keeps the NSWindow warm
	# offscreen at alpha 0.0 so reopening does not pay WindowServer deiconify
	# latency; reveal and raise only when transitioning hidden -> visible.
	if {[tk windowingsystem] eq "aqua"} {
		if {$opening || [wm state $w] ne "normal"} {
			wm deiconify $w
		}
		if {$opening || !$wasVisible} {
			catch { wm attributes $w -alpha 1.0 }
			raise $w
		}
	} elseif {$opening || [wm state $w] ne "normal"} {
		wm deiconify $w
		raise $w
	}
	set Priv(listVisible) 1
	return $w
}

proc ::application::ask::HideList {} {
	variable Priv
	variable ListGeom
	CancelRefresh
	set Priv(listVisible) 0
	if {[info exists Priv(list)] && $Priv(list) ne "" && [winfo exists $Priv(list)]} {
		if {[tk windowingsystem] eq "aqua"} {
			catch { wm attributes $Priv(list) -alpha 0.0 }
			catch { wm geometry $Priv(list) 1x1+-10000+-10000 }
			set ListGeom ""
		} else {
			catch { wm withdraw $Priv(list) }
		}
	}
	if {[info exists Priv(prewarmDeferred)] && $Priv(prewarmDeferred) \
	 && [info exists Priv(prewarmAfter)] && $Priv(prewarmAfter) ne ""} {
		SchedulePrewarm
	}
}

proc ::application::ask::ListVisible {} {
	variable Priv
	if {![info exists Priv(list)] || $Priv(list) eq ""} { return 0 }
	if {![winfo exists $Priv(list)]} { return 0 }
	if {[tk windowingsystem] eq "aqua"} {
		return [expr {[info exists Priv(listVisible)] && $Priv(listVisible) && [wm state $Priv(list)] eq "normal"}]
	}
	return [expr {[wm state $Priv(list)] eq "normal"}]
}

proc ::application::ask::Move {direction} {
	variable Priv

	if {![ListVisible]} {
		if {$direction < 0} { return [HistoryStep -1] }
		return [HistoryStep 1]
	}
 # ShowList always appends the "Ask the assistant" row, so the navigable
 # count is one more than the matched commands (and one when none match).
 set count [expr {[llength $Priv(rows)] + 1}]
	set index [expr {$Priv(index) + $direction}]
	if {$index < 0} { set index 0 }
	if {$index >= $count} { set index [expr {$count - 1}] }
	set Priv(index) $index
	ShowList
	return "break"
}

proc ::application::ask::Click {y} {
	set list .application.askList.list
	set index [$list nearest $y]
	set ::application::ask::Priv(index) $index
	ShowList
	return "break"
}

proc ::application::ask::CommandContext {} {
 set context {}
 catch {lappend context [::scidb::db::get name] [::application::database::currentVariant] [::scidb::pos::fen]}
 return $context
}
proc ::application::ask::ToggleMode {} {
 variable Mode
 variable mc
 set Mode [expr {$Mode eq "command" ? "question" : "command"}]
 [winfo parent [Entry]].mode configure -text [expr {$Mode eq "command" ? $mc::AskQuestion : $mc::Commands}]
 unset -nocomplain ::application::ask::Priv(filtered)
 Typed
}
proc ::application::ask::Choose {} {
 variable Priv
 variable Query
 if {$::application::ask::Mode eq "question"} {return [SendToAssistant]}
 if {![ListVisible] && [string trim $Query] eq ""} {return "break"}
 set rows {}
 if {[info exists Priv(rows)]} {set rows $Priv(rows)}
 if {$Priv(index) < 0} {return "break"}
 # Past the last row (or with no match at all) the text is a question.
 if {![llength $rows] || $Priv(index) >= [llength $rows]} {return [SendToAssistant]}
 lassign [lindex $rows $Priv(index)] id
 # A row from the command grammar carries its resolved arguments; any
 # other row is a plain registry palette action.
 set row ""
 if {[info exists Priv(commands)] && $Priv(index) < [llength $Priv(commands)]} {
  set candidate [lindex $Priv(commands) $Priv(index)]
  if {[dict exists $candidate action] && [dict get $candidate action] eq $id} {set row $candidate}
 }
 if {$row ne "" && ![dict exists $row palette]} {
  if {[info exists Priv(context)] && ($Priv(filtered) ne [string trim $Query] \
   || $Priv(context) ne [CommandContext])} {
   unset -nocomplain Priv(filtered)
   Typed
   return "break"
  }
  if {[llength [dict get $row missing]]} {MissingSlot $row; return "break"}
 set failed [catch {::commandline::Run $row} result]
 if {$failed || [string match "error:*" $result] || [string match "declined*" $result]} {
  catch {::ui::message $result error}
 } else {
  set Query ""
  HideList
  # Query actions return useful text too, without needing a model to narrate it.
  if {$result ne ""} {catch {::ui::message $result}}
 }
 PlaceholderState
 return "break"
 }
 # Registry palette action: run it through the same gate as a menu click.
 HideList
 catch { focus -force [Entry] }
 set failed [catch {::action::run $id} result]
 if {$failed || [string match "error:*" $result] || [string match "declined*" $result]} {
  catch {::ui::message $result error}
 } else {
  set Query ""
 }
 PlaceholderState
 return "break"
}
proc ::application::ask::MissingSlot {row} {
 variable Query
 variable Priv
 set slot [lindex [dict get $row missing] 0]
 set completed [::commandline::CompleteText [dict get $row template] [dict get $row args] [dict get $row missing]]
 set marker <$slot>
 set start [string first $marker $completed]
 if {$start < 0} {
  set completed "[string trim $Query] $marker"
  set start [string first $marker $completed]
 }
 # A file slot has no useful typed candidates: open the platform picker and
 # drop the chosen path into the sentence, quoted when it contains spaces.
 if {[::commandline::FileSlot? $slot]} {
  set picked [::commandline::PickFile $slot]
  if {$picked ne ""} {
   set quoted [::commandline::QuoteArgument $picked]
   set Query [string replace $completed $start [expr {$start+[string length $marker]-1}] $quoted]
   catch { [Entry] selection clear }
   catch { [Entry] icursor end }
   focus -force [Entry]
   unset -nocomplain Priv(filtered)
   Typed
   return
  }
 }
 set Query $completed
 [Entry] selection range $start [expr {$start+[string length $marker]}]
 [Entry] icursor $start
 focus -force [Entry]
 set Priv(filtered) [string trim $Query]
 set Priv(commands) {}; set Priv(rows) {}
 set ::commandline::Cache {}
 foreach value [::commandline::Values $slot ""] {
  set text [string replace $Query $start [expr {$start+[string length $marker]-1}] $value]
  foreach candidate [::commandline::Suggest $text] {
   if {[dict get $candidate id] ne [dict get $row id]} {continue}
   lappend Priv(commands) $candidate
   lappend Priv(rows) [list [dict get $candidate action] [dict get $candidate label] Enter 1 1]
  }
 }
 set Priv(index) 0
 ShowList
}

proc ::application::ask::SendToAssistant {} {
	variable Priv
	variable Query
	variable mc

	set submitted [[::application::ask::Entry] get]
	set text [string trim $submitted]
	if {$text eq ""} { return "break" }
	HideList
	if {![llength [info commands ::application::assistant::ask]]} {
		catch {::ui::message $mc::Unavailable}
		return "break"
	}
	if {[llength [info commands ::application::assistant::show]]} {
		catch { ::application::assistant::show }
	}
	set ::application::assistant::QuestionMode 1
 set failed [catch {::application::assistant::ask $text} accepted]
 set ::application::assistant::QuestionMode 0
 if {$failed} {
		catch {::ui::message [format $mc::Failed $accepted]}
		return "break"
	}
	if {$accepted ne "1"} {
		catch {::ui::message $mc::Busy}
		return "break"
	}
	if {[llength [info commands ::application::assistant::HistoryAdd]]} {
		catch { ::application::assistant::HistoryAdd $text }
	}
	if {$Query eq $submitted} { set Query "" }
	PlaceholderState
	return "break"
}

# ======================================================================
# Shared history (Up in an empty field).
# ======================================================================
proc ::application::ask::HistoryStep {direction} {
	variable Priv

	set history {}
	if {[info exists ::application::assistant::History]} {
		set history $::application::assistant::History
	}
	if {![llength $history]} { return }
	if {$Priv(histIndex) == -1} {
		if {$direction > 0} { return }
		set Priv(histIndex) [expr {[llength $history] - 1}]
	} else {
		set Priv(histIndex) [expr {$Priv(histIndex) + $direction}]
	}
	if {$Priv(histIndex) < 0} { set Priv(histIndex) 0; return }
	if {$Priv(histIndex) >= [llength $history]} {
		set Priv(histIndex) -1
		[::application::ask::Entry] delete 0 end
		PlaceholderState
		return
	}
	set text [lindex $history $Priv(histIndex)]
	[::application::ask::Entry] delete 0 end
	[::application::ask::Entry] insert 0 $text
	catch { [::application::ask::Entry] icursor end }
	PlaceholderState
	return "break"
}

# ======================================================================
# ::application::speech -- speech INPUT only (no speech output).
# ======================================================================
namespace eval application {
namespace eval speech {

namespace eval mc {
set Install		"Speech input needs sherpa-onnx-offline and a sherpa-onnx model folder (or whisper-cli with a ggml model), and arecord or ffmpeg. Set them in the Assistant Preferences\u2026 dialog."
set InstallMac	"macOS uses the system dictation: turn it on in System Settings > Keyboard > Dictation, then press the dictation key (or Fn Fn)."
set InstallWin	"Windows uses the system dictation: press Win+H while the Ask field has focus."
set Listening	"Recording… click to cancel"
set Working		"Transcribing… click to cancel"
set Nothing		"Nothing heard"
set Failed		"Speech failed: %s"
set NoRecord	"Speech was cancelled"

# What detect() reports when the path is incomplete: the sentence and the
# name of each missing piece.
set Missing		"%s Missing: %s."
set MissingCli	"whisper-cli"
set MissingModel	"a ggml model"
set MissingRecorder	"arecord or ffmpeg"

# English defaults, restored before every language load (see i18n.tcl).
set ::application::speech::DefaultMC {}
foreach _name [lsort [info vars ::application::speech::mc::*]] {
	if {[array exists $_name] || [string index [namespace tail $_name] 0] eq "_"} { continue }
	lappend ::application::speech::DefaultMC [namespace tail $_name] [set $_name]
}
unset _name
}

variable Settings
array set Settings {
	whisperCli	""
	whisperModel	""
	sherpaCli	""
	sherpaModel	""
	hotwords	""
	recorder	""
	stub		""
	language	"en"
	maxSeconds	60
}
variable Priv
array set Priv {
	state		idle
	recordFile	""
	recordPids	{}
	transcribeFile	""
	transcribePids	{}
	transcribeOut	""
	transcribeMode	""
	transcribeStart	0
	stable		0
	lastSize	-1
	tempFiles	{}
	sessionDir	""
}

} ;# namespace speech
} ;# namespace application

proc ::application::speech::ResetMC {} {
	foreach {name value} $::application::speech::DefaultMC {
		set ::application::speech::mc::$name $value
	}
	return
}
if {[llength [info commands ::mc::addDefaultReset]]} {
	::mc::addDefaultReset ::application::speech::ResetMC
}

foreach {speechEnv speechKey} {
	SCIDB_AI_WHISPER_CLI	whisperCli
	SCIDB_AI_WHISPER_MODEL	whisperModel
	SCIDB_AI_SHERPA_CLI	sherpaCli
	SCIDB_AI_SHERPA_MODEL	sherpaModel
	SCIDB_AI_SPEECH_HOTWORDS	hotwords
	SCIDB_AI_RECORDER	recorder
	SCIDB_AI_SPEECH_STUB	stub
} {
	if {[info exists ::env($speechEnv)] && $::env($speechEnv) ne ""} {
		set ::application::speech::Settings($speechKey) $::env($speechEnv)
	}
}

proc ::application::speech::configure {args} {
	variable Settings
	foreach {key value} $args {
		if {![info exists Settings($key)]} { error "unknown speech setting '$key'" }
		set Settings($key) $value
	}
	if {[llength [info commands ::application::ask::SyncMic]]} { ::application::ask::SyncMic }
	return
}

proc ::application::speech::setting {key} {
	variable Settings
	return $Settings($key)
}

proc ::application::speech::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Settings
}
if {[llength [info commands ::options::hookWriter]]} {
	::options::hookWriter ::application::speech::WriteOptions
}

# ----------------------------------------------------------------------
# Discovery: preferences, then PATH, then the test fixture description.
# ----------------------------------------------------------------------
proc ::application::speech::which {name} {
	if {$name eq ""} { return "" }
	if {[file isdirectory $name]} { return "" }
	if {[file exists $name]} { return $name }
	if {[catch { set found [auto_execok $name] }]} { set found "" }
	if {$found ne ""} { return [lindex $found 0] }
	return ""
}

proc ::application::speech::RepoRoot {} {
	set d [file dirname [file dirname [file normalize [info script]]]]
	if {[file exists [file join $d tcl actions.tcl]]} { return $d }
	if {[file exists [file join [pwd] tcl actions.tcl]]} { return [pwd] }
	return [pwd]
}

proc ::application::speech::Fixture {} {
	set path [file join [RepoRoot] tests fixtures speech-fixture.txt]
	if {![file exists $path]} { return {} }
	set result [dict create]
	if {[catch {
		set chan [open $path r]
		while {[gets $chan line] >= 0} {
			set line [string trim $line]
			if {$line eq "" || [string index $line 0] eq "#"} { continue }
			set eq [string first = $line]
			if {$eq < 0} { continue }
			dict set result [string trim [string range $line 0 [expr {$eq - 1}]]] \
				[string trim [string range $line [expr {$eq + 1}] end]]
		}
		close $chan
	}]} {
		catch { close $chan }
	}
	return $result
}

# Keep platform selection separate so device-free tests can exercise every OS.
proc ::application::speech::Host {} {
	if {$::tcl_platform(platform) eq "windows"} { return win-x64 }
	if {$::tcl_platform(os) eq "Darwin"} { return macos-universal2 }
	return linux-x64
}

proc ::application::speech::NullDevice {} {
	if {[Host] eq "win-x64"} { return NUL }
	return /dev/null
}

proc ::application::speech::BundledTool {name} {
	set root [file join [RepoRoot] tests tmp-app speech-tools bin [Host]]
	if {[Host] eq "win-x64"} { append name .exe }
	foreach pattern [list [file join $root $name] [file join $root * $name] \
			[file join $root * bin $name] [file join $root * * bin $name]] {
		foreach path [glob -nocomplain -types f $pattern] {
			if {[file executable $path]} { return $path }
		}
	}
	return ""
}

# The speech path in effect: {mode available reason cli model recorder stub}.
proc ::application::speech::detect {} {
	variable Settings
	variable mc

	set fixture [Fixture]
	set root [RepoRoot]
	set cli $Settings(whisperCli)
	set model $Settings(whisperModel)
	set recorder $Settings(recorder)
	set stub $Settings(stub)
	if {$cli eq "" && [dict exists $fixture whisper_cli]} {
		set cli [file join $root [dict get $fixture whisper_cli]]
	}
	if {$model eq "" && [dict exists $fixture model]} {
		set model [file join $root [dict get $fixture model]]
	}
	if {$recorder eq "" && [Host] eq "linux-x64" && [dict exists $fixture recorder]} { set recorder [dict get $fixture recorder] }

	if {$stub ne ""} {
		return [dict create mode stub available 1 reason "" cli $cli model $model recorder $recorder stub $stub]
	}

	set recPath ""
	if {$recorder ne "" && $recorder ne "auto"} {
		set recPath [which $recorder]
	} else {
		set recPath [BundledTool ffmpeg]
		set candidates {ffmpeg}
		if {[Host] eq "linux-x64"} { set candidates {arecord ffmpeg} }
		foreach candidate $candidates {
			if {$recPath ne ""} { break }
			set recPath [which $candidate]
			if {$recPath ne ""} { break }
		}
	}

	set sherpa [SherpaModel $Settings(sherpaModel)]
	set sherpaCli [which $Settings(sherpaCli)]
	if {$Settings(sherpaCli) eq ""} { set sherpaCli [BundledTool sherpa-onnx-offline] }
	if {$sherpaCli ne "" && [dict size $sherpa] && $recPath ne ""} {
		return [dict create mode sherpa available 1 reason "" cli $sherpaCli \
			model [dict get $sherpa dir] recorder $recPath stub "" sherpa $sherpa]
	}

	set cliPath [which $cli]
	set modelPath $model
	if {![file exists $modelPath]} { set modelPath "" }
	set available [expr {$cliPath ne "" && $modelPath ne "" && $recPath ne ""}]
	if {!$available && [Host] in {win-x64 macos-universal2}} {
		set mode [expr {[Host] eq "win-x64" ? "windows" : "mac"}]
		return [dict create mode $mode available 1 reason "" cli "" model "" recorder "" stub ""]
	}
	set reason ""
	if {!$available} {
		set missing {}
		if {$cliPath eq ""} { lappend missing $mc::MissingCli }
		if {$modelPath eq ""} { lappend missing $mc::MissingModel }
		if {$recPath eq ""} { lappend missing $mc::MissingRecorder }
		set reason [format $mc::Missing [string trim $mc::Install] [join $missing ", "]]
	}
	return [dict create mode whisper available $available reason $reason \
		cli $cliPath model $modelPath recorder $recPath stub ""]
}

# A sherpa-onnx offline transducer model folder: {dir encoder decoder joiner
# tokens type ?bpevocab?}, or {} when <dir> is not one. int8 files are
# preferred. NeMo (Parakeet) models are recognised by their folder name.
proc ::application::speech::SherpaModel {dir} {
	if {$dir eq "" || ![file isdirectory $dir]} { return {} }
	set result [dict create dir [file normalize $dir]]
	foreach part {encoder decoder joiner} {
		set files [lsort [glob -nocomplain -types f -directory $dir $part*.onnx]]
		if {![llength $files]} { return {} }
		set int8 [lsearch -inline -glob $files *int8*]
		dict set result $part [expr {$int8 ne "" ? $int8 : [lindex $files 0]}]
	}
	set tokens [file join $dir tokens.txt]
	if {![file isfile $tokens]} { return {} }
	dict set result tokens $tokens
	set name [string tolower [file tail $dir]]
	dict set result type [expr {[string match *nemo* $name] || [string match *parakeet* $name] ? "nemo_transducer" : "transducer"}]
	set vocab [file join $dir bpe.vocab]
	if {[file isfile $vocab]} { dict set result bpevocab $vocab }
	return $result
}

# The sherpa-onnx-offline command line for one WAV.
proc ::application::speech::SherpaArgv {d file} {
	variable Settings
	set m [dict get $d sherpa]
	set argv [list [dict get $d cli] --provider=cpu --num-threads=4 \
		--encoder=[dict get $m encoder] --decoder=[dict get $m decoder] \
		--joiner=[dict get $m joiner] --tokens=[dict get $m tokens]]
	if {[dict get $m type] eq "nemo_transducer"} { lappend argv --model-type=nemo_transducer }
	set hot $Settings(hotwords)
	if {$hot ne "" && [file isfile $hot] && [dict exists $m bpevocab]} {
		lappend argv --decoding-method=modified_beam_search --hotwords-file=$hot \
			--modeling-unit=bpe --bpe-vocab=[dict get $m bpevocab]
	}
	lappend argv $file
	return $argv
}

# The transcript in sherpa-onnx-offline's output: the "text" of its JSON
# result line (the tool prints one JSON object per input file).
proc ::application::speech::SherpaText {output} {
	set text ""
	foreach line [split $output \n] {
		if {[regexp {"text":\s*"((?:[^"\\]|\\.)*)"} $line -> raw]} {
			set text [subst -nocommands -novariables $raw]
		}
	}
	return [string trim $text]
}

# Look for whisper-cli and a ggml model where whisper.cpp installs them,
# for each setting that is empty or points at nothing; set what is found.
# Returns "name path" phrases for the report.
proc ::application::speech::search {} {
	variable Settings
	set found {}
	set home [file normalize ~]
	set trees [list [file join $home whisper.cpp] [file join $home src whisper.cpp] \
		/usr/local/share/whisper.cpp /usr/share/whisper.cpp /opt/homebrew/share/whisper-cpp]
	set sherpaRoots [list [file join $home .local share sherpa-onnx] /usr/local/share/sherpa-onnx \
		/opt/sherpa-onnx [file join [RepoRoot] tests tmp-app speech-tools]]
	if {[which $Settings(sherpaCli)] eq ""} {
		set path [BundledTool sherpa-onnx-offline]
		if {$path eq ""} { set path [which sherpa-onnx-offline] }
		foreach root $sherpaRoots {
			if {$path ne ""} break
			foreach cand [glob -nocomplain -types f [file join $root bin sherpa-onnx-offline] \
					[file join $root bin [Host] sherpa-onnx * bin sherpa-onnx-offline*]] {
				if {[file executable $cand]} { set path $cand; break }
			}
		}
		if {$path ne ""} {
			set Settings(sherpaCli) $path
			lappend found "sherpa-onnx-offline $path"
		}
	}
	if {![dict size [SherpaModel $Settings(sherpaModel)]]} {
		set cands {}
		foreach root $sherpaRoots {
			lappend cands {*}[glob -nocomplain -types d [file join $root models *] [file join $root models asr *]]
		}
		# Parakeet first: the most accurate on the smoke test; then the rest
		set cands [lsort -command {apply {{a b} {
			expr {[string match *parakeet* [file tail $b]] - [string match *parakeet* [file tail $a]]}
		}}} $cands]
		foreach dir $cands {
			if {[dict size [SherpaModel $dir]]} {
				set Settings(sherpaModel) $dir
				lappend found "sherpa model $dir"
				break
			}
		}
	}
	if {[which $Settings(whisperCli)] eq ""} {
		set dirs [lmap t $trees {file join $t build bin}]
		lappend dirs /usr/local/bin /opt/homebrew/bin
		foreach name {whisper-cli whisper-cpp} {
			set path [which $name]
			foreach dir $dirs {
				if {$path ne ""} break
				if {[file executable [file join $dir $name]]} { set path [file join $dir $name] }
			}
			if {$path ne ""} {
				set Settings(whisperCli) $path
				lappend found "whisper-cli $path"
				break
			}
		}
	}
	if {$Settings(whisperModel) eq "" || ![file isfile $Settings(whisperModel)]} {
		set dirs [lmap t $trees {file join $t models}]
		lappend dirs [file join $home .cache whisper] [file join $home .local share whisper] \
			/usr/local/share/whisper /usr/share/whisper
		set models {}
		foreach dir $dirs { lappend models {*}[glob -nocomplain -types f [file join $dir ggml-*.bin]] }
		if {[llength $models]} {
			# the smallest model answers fastest; a larger one is the user's choice
			set best [lindex [lsort -command {apply {{a b} {expr {[file size $a] - [file size $b]}}}} $models] 0]
			set Settings(whisperModel) $best
			lappend found "model $best"
		}
	}
	if {$Settings(recorder) in {"" auto}} {
		set recorder [BundledTool ffmpeg]
		if {$recorder ne ""} {
			set Settings(recorder) $recorder
			lappend found "ffmpeg $recorder"
		}
	}
	return $found
}

proc ::application::speech::available {} {
	return [dict get [detect] available]
}

proc ::application::speech::hint {} {
	set d [detect]
	switch -- [dict get $d mode] {
		windows	{ return $::application::speech::mc::InstallWin }
		mac		{ return $::application::speech::mc::InstallMac }
		default {
			set reason [dict get $d reason]
			if {$reason ne ""} { return $reason }
			return ""
		}
	}
}

proc ::application::speech::status {} {
	set d [detect]
	variable Priv
	set state $Priv(state)
	set parts [list "mode [dict get $d mode]" "state $state"]
	if {[dict get $d cli] ne ""} {
		lappend parts "[expr {[dict get $d mode] eq "sherpa" ? "sherpa-onnx-offline" : "whisper-cli"}] [dict get $d cli]"
	}
	if {[dict get $d model] ne ""} { lappend parts "model [dict get $d model]" }
	if {[dict get $d recorder] ne ""} { lappend parts "recorder [dict get $d recorder]" }
	if {![dict get $d available]} { lappend parts [hint] }
	return [join $parts "; "]
}

# ----------------------------------------------------------------------
# The microphone button.
# ----------------------------------------------------------------------
# A quick gesture leaves recording running; a hold transcribes on release.
# Remember the session so a late release after timeout/cancel cannot restart it.
proc ::application::speech::Press {button} {
	variable Priv
	if {[$button instate disabled]} { return }
	$button state pressed
	unset -nocomplain Priv(pressSession) Priv(pressTime)
	if {$Priv(state) ne "idle"} { Cancel; return }
	Start
	if {$Priv(state) eq "recording"} {
		set Priv(pressSession) $Priv(generation)
		set Priv(pressTime) [clock milliseconds]
	}
}

proc ::application::speech::Release {button} {
	variable Priv
	$button state !pressed
	if {[info exists Priv(pressSession)]} {
		set held [expr {[clock milliseconds] - $Priv(pressTime) >= 300}]
		set current [expr {$Priv(pressSession) == $Priv(generation)}]
		unset Priv(pressSession) Priv(pressTime)
		if {$held && $current && $Priv(state) eq "recording"} { StopRecording }
	}
}

proc ::application::speech::toggle {} {
	variable Priv
	variable Settings

	switch -- $Priv(state) {
		idle {
			Start
		}
		recording -
		transcribing {
			Cancel
		}
	}
	return
}

proc ::application::speech::Start {} {
	variable Priv
	variable Settings

	set d [detect]
	if {![dict get $d available]} { ShowHint; return }
	set mode [dict get $d mode]
	if {$mode in {windows mac}} {
		# Native dictation types into the focused control, not necessarily
		# the button's sibling. Set focus before handing off to the OS.
		focus -force [::application::ask::Entry]
		if {$mode eq "windows"} { WindowsDictation } else { ShowHint }
		return
	}

	Cancel
	if {[catch {set file [TempFile .wav]} err]} {
		SetHint [format $::application::speech::mc::Failed $err]
		return
	}
	if {[winfo exists [::application::ask::Entry]]} {
		set entry [::application::ask::Entry]
		if {[string first ::application::speech::Cancel [bind $entry <Destroy>]] < 0} {
			bind $entry <Destroy> +::application::speech::Cancel
		}
	}
	SetState recording
	SetMicText $::application::speech::mc::Listening
	set Priv(recordFile) $file
	if {$mode eq "stub"} {
		# The deterministic path: no recorder, the stub supplies the text.
		set Priv(recordPids) {}
		Schedule [expr {1000 * $Settings(maxSeconds)}] [list RecordTimeout $file]
		return
	}
	set pids {}
	if {[catch {
		set argv [RecorderArgv $d $file]
		if {[file rootname [file tail [dict get $d recorder]]] eq "arecord"} {
			set pids [exec {*}$argv > [NullDevice] 2>@1 &]
		} else {
			set Priv(recordChan) [open [list | {*}$argv > [NullDevice] 2>@1] w]
			fconfigure $Priv(recordChan) -blocking 0 -buffering none
			set pids [pid $Priv(recordChan)]
		}
	} err]} {
		Cleanup
		SetState idle
		SetMicText $::application::ask::mc::Mic
		SetHint [format $::application::speech::mc::Failed $err]
		return
	}
	set Priv(recordPids) $pids
	# A recording is never longer than maxSeconds; guard against a lost stop.
	Schedule [expr {1000 * $Settings(maxSeconds)}] [list RecordTimeout $file]
}

proc ::application::speech::RecordTimeout {file} {
	variable Priv
	if {$Priv(state) eq "recording" && $Priv(recordFile) eq $file} { StopRecording }
}

# ffmpeg reports devices on stderr and exits unsuccessfully after listing.
proc ::application::speech::WindowsAudioDevices {recorder} {
	catch {exec $recorder -hide_banner -list_devices true -f dshow -i dummy 2>@1} output
	set devices {}
	foreach line [split $output \n] {
		if {[regexp {"(.*)" \(audio\)} $line -> name]} { lappend devices $name }
	}
	return $devices
}

proc ::application::speech::RecorderArgv {d file} {
	variable Settings
	set recorder [dict get $d recorder]
	if {[file rootname [file tail $recorder]] eq "arecord"} {
		return [list $recorder -q -f S16_LE -r 16000 -c 1 -t wav $file]
	}
	switch -- [Host] {
		win-x64 {
			set devices [WindowsAudioDevices $recorder]
			if {![llength $devices]} { error "No DirectShow audio recording device found" }
			set input [list -f dshow -i "audio=[lindex $devices 0]"]
		}
		macos-universal2 { set input [list -f avfoundation -i :0] }
		default { set input [list -f pulse -i default] }
	}
	return [list $recorder -y -loglevel error {*}$input -t $Settings(maxSeconds) \
		-ar 16000 -ac 1 -c:a pcm_s16le $file]
}

proc ::application::speech::CloseRecorder {} {
	variable Priv
	if {[info exists Priv(recordChan)]} {
		catch {close $Priv(recordChan)}
		unset Priv(recordChan)
	}
}

proc ::application::speech::StopRecording {} {
	variable Priv

	if {$Priv(state) ne "recording"} { return }
	if {[info exists Priv(recordChan)]} {
		catch {puts $Priv(recordChan) q; flush $Priv(recordChan)}
	} else {
		foreach pid $Priv(recordPids) { catch {::platform::sys::kill $pid TERM} }
	}
	set file $Priv(recordFile)
	set Priv(recordFile) ""
	SetState transcribing
	SetMicText $::application::speech::mc::Working
	# give the recorder a moment to flush its header; it keeps its pid (so
	# Cancel still reaches it) until it has exited and written the whole file
	if {[llength $Priv(recordPids)]} {
		Schedule 200 [list WaitRecorder $file [expr {[clock milliseconds] + 2000}]]
	} else {
		Schedule 200 [list StartTranscribe $file]
	}
}

# Transcribe <file> once the recorder is gone; one that ignores TERM past
# <deadline> is killed.
proc ::application::speech::WaitRecorder {file deadline} {
	variable Priv

	if {$Priv(state) ne "transcribing"} { return }
	set alive {}
	foreach pid $Priv(recordPids) {
		if {[::platform::sys::alive $pid]} { lappend alive $pid }
	}
	set Priv(recordPids) $alive
	if {[llength $alive] && [clock milliseconds] < $deadline} {
		Schedule 50 [list WaitRecorder $file $deadline]
		return
	}
	foreach pid $alive { catch { ::platform::sys::kill $pid KILL } }
	CloseRecorder
	set Priv(recordPids) {}
	StartTranscribe $file
}

# Cancel (button while recording/transcribing, Esc, or the API): insert nothing.
proc ::application::speech::Cancel {} {
	variable Priv

	if {[llength [info commands ::chesswiz::win::dictateEdit]]} {
		catch { if {[::chesswiz::win::dictateEdit active]} { ::chesswiz::win::dictateEdit cancel } }
	}

	# the recording is thrown away: a recorder that ignores TERM (it may
	# already have been asked to stop) is killed
	foreach pid $Priv(recordPids) {
		catch { ::platform::sys::kill $pid KILL }
	}
	foreach pid $Priv(transcribePids) {
		catch { ::platform::sys::kill $pid TERM }
	}
	CloseRecorder
	set Priv(recordPids) {}
	set Priv(transcribePids) {}
	set Priv(recordFile) ""
	Cleanup
	SetState idle
	SetMicText $::application::ask::mc::Mic
	SetHint $::application::speech::mc::NoRecord
	return
}

proc ::application::speech::StartTranscribe {file} {
	variable Priv
	variable Settings

	set d [detect]
	if {![dict get $d available] || [dict get $d mode] ni {whisper sherpa stub}} {
		Cleanup
		SetState idle
		SetMicText $::application::ask::mc::Mic
		SetHint [hint]
		return
	}
	if {$Priv(state) ne "transcribing"} {
		catch { file delete -force $file }
		return
	}

	if {[dict get $d stub] ne ""} {
		# The deterministic test path: a script that prints a transcript.
		set stub [dict get $d stub]
		set text [RunStub $stub]
		set Priv(transcribeOut) ""
		set Priv(transcribeFile) $file
		# a short wait makes cancel observable
		Schedule 120 [list FinishStub $text]
		return
	}

	if {[catch {set output [TempOutput .txt out]} err]} {
		Cancel
		SetHint [format $::application::speech::mc::Failed $err]
		return
	}
	set cli [dict get $d cli]
	set model [dict get $d model]
	if {[dict get $d mode] eq "sherpa"} {
		set argv [SherpaArgv $d $file]
	} else {
		set argv [list $cli -m $model -f $file -nt -np -ng]
	}
	set Priv(transcribeMode) [dict get $d mode]
	set cmd $argv
	set pids {}
	if {[catch { set pids [exec {*}$cmd >@ $output 2> [NullDevice] &] } err]} {
		close $output
		Cleanup
		SetState idle
		SetMicText $::application::ask::mc::Mic
		SetHint [format $::application::speech::mc::Failed $err]
		return
	}
	close $output
	set Priv(transcribeFile) $file
	set Priv(transcribeOut) $out
	set Priv(transcribePids) $pids
	set Priv(transcribeStart) [clock milliseconds]
	set Priv(lastSize) -1
	set Priv(stable) 0
	Schedule 120 PollTranscribe
}

proc ::application::speech::FinishStub {text} {
	variable Priv
	if {$Priv(state) ne "transcribing"} {
		Cleanup
		return
	}
	Cleanup
	SetState idle
	SetMicText $::application::ask::mc::Mic
	InsertTranscript $text
}

proc ::application::speech::Alive? {pids} {
	foreach pid $pids {
		if {![::platform::sys::alive $pid]} { continue }
		return 1
	}
	return 0
}

proc ::application::speech::PollTranscribe {} {
	variable Priv

	if {$Priv(state) ne "transcribing"} { Cleanup; return }
	# the deadline holds on every path, also while there is no output file
	if {[clock milliseconds] - $Priv(transcribeStart) > 120000} {
		Cancel
		return
	}
	set out $Priv(transcribeOut)
	if {$out eq "" || ![file exists $out]} {
		if {![Alive? $Priv(transcribePids)]} { FinishTranscribe } else { Schedule 120 PollTranscribe }
		return
	}
	set size [file size $out]
	if {$size == $Priv(lastSize)} { incr Priv(stable) } else { set Priv(stable) 0; set Priv(lastSize) $size }
	if {![Alive? $Priv(transcribePids)] && $Priv(stable) >= 1} { FinishTranscribe; return }
	Schedule 120 PollTranscribe
}

proc ::application::speech::FinishTranscribe {} {
	variable Priv

	if {$Priv(state) ne "transcribing"} { Cleanup; return }
	set out $Priv(transcribeOut)
	set text ""
	if {$out ne "" && [file exists $out]} {
		catch {
			set chan [open $out r]
			fconfigure $chan -encoding utf-8
			set text [read $chan]
			close $chan
		}
	}
	if {$Priv(transcribeMode) eq "sherpa"} { set text [SherpaText $text] }
	set text [string trim $text]
	Cleanup
	SetState idle
	SetMicText $::application::ask::mc::Mic
	if {$text eq ""} {
		SetHint $::application::speech::mc::Nothing
		return
	}
	InsertTranscript $text
}

# Put a transcript at the cursor in the Ask field. Editable, never sent.
proc ::application::speech::InsertTranscript {text} {
	set text [string trim $text]
	# whisper-cli ends sentences with punctuation ("Go."). Ignore it for the
	# spoken confirmation, but leave the transcript itself untouched.
	set spoken $text
	regsub {[\s.!?,;:]+$} $spoken {} spoken
	if {[string equal -nocase $spoken "go"] && [::application::ask::ListVisible]} {
		::application::ask::Choose
		return 1
	}
	if {$text eq ""} { return 0 }
	if {![winfo exists [::application::ask::Entry]]} { return 0 }
	set entry [::application::ask::Entry]
	# Do not fuse a transcript with the word on either side of the cursor.
	set insert $text
	set current [$entry get]
	set pos [$entry index insert]
	if {$pos > 0} {
		set before [string index $current [expr {$pos - 1}]]
		if {$before ne "" && ![string is space $before]} {
			set insert " $insert"
		}
	}
	if {$pos < [string length $current]} {
		set after [string index $current $pos]
		if {$after ne "" && ![string is space $after]} {
			append insert " "
		}
	}
	$entry insert insert $insert
	focus -force $entry
	Schedule idle ::application::ask::Typed
	SetHint [format $::application::ask::mc::Heard $text]
	return 1
}

# Transcribe one file synchronously (used by tests and tooling).
# CUDA_VISIBLE_DEVICES="" keeps the GPUs free for the film.
proc ::application::speech::transcribeFile {file} {
	set d [detect]
	if {![dict get $d available]} { error [hint] }
	if {[dict get $d mode] eq "stub"} {
		return [string trim [RunStub [dict get $d stub]]]
	}
	if {[dict get $d mode] eq "sherpa"} {
		return [SherpaText [exec {*}[SherpaArgv $d $file] 2> [NullDevice]]]
	}
	set cmd [list [dict get $d cli] -m [dict get $d model] \
		-f $file -nt -np -ng]
	return [string trim [exec {*}$cmd 2> [NullDevice]]]
}

# A directory is created atomically with private permissions. Existing
# paths must be real directories owned by this user and remain private.
# Each process/session has its own private subdirectory (pid + random)
# so concurrent instances never collide or clean each other's files.
proc ::application::speech::TempDir {} {
	variable Priv
	if {$::tcl_platform(platform) eq "windows"} {
		# Use the per-user profile directory, inheriting its Windows ACLs.
		# POSIX ownership/mode bits and the id/mkdir utilities do not exist
		# on a native Windows installation. Do not fall back to shared /tmp.
		if {![info exists ::env(LOCALAPPDATA)] || $::env(LOCALAPPDATA) eq ""} {
			error "speech temporary directory requires LOCALAPPDATA"
		}
		set userDir [file join [file normalize $::env(LOCALAPPDATA)] Chesswiz Speech]
		file mkdir $userDir
		if {[file type $userDir] ne "directory"} {
			error "speech temporary directory is not a directory"
		}
	} else {
		set base /tmp
		if {[info exists ::env(TMPDIR)] && $::env(TMPDIR) ne ""} { set base $::env(TMPDIR) }
		set userDir [file join [file normalize $base] chesswiz-ask-[exec id -u]]
		catch {exec mkdir -m 0700 -- $userDir}
		if {[file type $userDir] ne "directory" || ![file owned $userDir]
			|| ([file attributes $userDir -permissions] & 0077) != 0} {
			error "speech temporary directory is not private"
		}
	}
	if {![info exists Priv(sessionDir)] || $Priv(sessionDir) eq ""
		|| [file dirname $Priv(sessionDir)] ne $userDir
		|| ![file exists $Priv(sessionDir)]} {
		for {set attempt 0} {$attempt < 10} {incr attempt} {
			set rand [format %06x [expr {int(rand() * 0xffffff)}]]
			set sdir [file join $userDir "session-[pid]-$rand"]
			if {[file exists $sdir]} { continue }
			if {$::tcl_platform(platform) eq "windows"} {
				file mkdir $sdir
			} else {
				catch {exec mkdir -m 0700 -- $sdir}
			}
			if {[file exists $sdir]} { break }
		}
		if {![file exists $sdir] || [file type $sdir] ne "directory"
			|| ($::tcl_platform(platform) ne "windows" && (![file owned $sdir]
			|| ([file attributes $sdir -permissions] & 0077) != 0))} {
			error "speech session directory is not private"
		}
		set Priv(sessionDir) $sdir
	}
	return $Priv(sessionDir)
}

# All timers carry ownership of the current session, including idle work.
proc ::application::speech::Schedule {delay script} {
	variable Priv
	if {![info exists Priv(generation)]} { set Priv(generation) 0 }
	lappend Priv(timers) [after $delay [namespace code [list Timer $Priv(generation) $script]]]
}

proc ::application::speech::Timer {generation script} {
	variable Priv
	if {$generation != $Priv(generation)} { return }
	{*}$script
}

proc ::application::speech::CancelTimers {} {
	variable Priv
	if {[info exists Priv(timers)]} {
		foreach timer $Priv(timers) { after cancel $timer }
	}
	set Priv(timers) {}
	if {![info exists Priv(generation)]} { set Priv(generation) 0 }
	incr Priv(generation)
}

# Run the test stub: an executable (script) or, when that is not a
# program, a Tcl command whose result is the transcript.
proc ::application::speech::RunStub {stub} {
	set text ""
	if {[file exists [lindex $stub 0]] || [auto_execok [lindex $stub 0]] ne ""} {
		if {![catch { set text [exec {*}$stub] }]} { return $text }
	}
	catch { uplevel #0 $stub } text
	return $text
}

# file tempfile creates exclusively; transcription redirects the open
# channel rather than opening a predictable output filename in the child.
proc ::application::speech::TempOutput {suffix nameVar} {
	variable Priv
	upvar 1 $nameVar path
	set channel [file tempfile path [file join [TempDir] ask-XXXXXX$suffix]]
	lappend Priv(tempFiles) $path
	return $channel
}

proc ::application::speech::TempFile {suffix} {
	set channel [TempOutput $suffix path]
	close $channel
	return $path
}

proc ::application::speech::Cleanup {} {
	variable Priv
	CancelTimers
	foreach file $Priv(tempFiles) {
		if {$file ne ""} { catch { file delete -force $file } }
	}
	set Priv(recordFile) ""
	set Priv(transcribeFile) ""
	set Priv(transcribeOut) ""
	set Priv(transcribePids) {}
	set Priv(tempFiles) {}
}

proc ::application::speech::CleanupSession {} {
	variable Priv
	Cleanup
	if {[info exists Priv(sessionDir)] && $Priv(sessionDir) ne "" && [file exists $Priv(sessionDir)]} {
		catch { file delete -force $Priv(sessionDir) }
		set Priv(sessionDir) ""
	}
}

proc ::application::speech::SetState {state} {
	variable Priv
	set Priv(state) $state
}

proc ::application::speech::SetMicText {text} {
	if {[winfo exists [::application::ask::Mic]]} {
		[::application::ask::Mic] configure -text $text
	}
}

proc ::application::speech::SetHint {text} {
	variable Priv
	set Priv(hint) $text
	if {[info exists Priv(hintWidget)] && [winfo exists $Priv(hintWidget)]} {
		$Priv(hintWidget) configure -text $text
	}
}

proc ::application::speech::LastHint {} {
	variable Priv
	if {[info exists Priv(hint)]} { return $Priv(hint) }
	return ""
}

proc ::application::speech::ShowHint {} {
	SetHint [hint]
	# A click gives visible guidance without opening Preferences or adding
	# startup chrome. The normal hover tooltip carries the same wording.
	variable Priv
	set parent .application.nb
	if {![winfo exists $parent]} { return }
	set w $parent.dictationHint
	if {![winfo exists $w]} {
		ttk::label $w -textvariable ::application::speech::Priv(hint) -padding {6 3}
	}
	set Priv(hintWidget) $w
	place $w -relx 1.0 -anchor ne -y [winfo height $parent.ask]
	raise $w
	Schedule 15000 [list place forget $w]
}

# Windows: the operating system's dictation (Win+H). Implemented with the
# Win32 SendInput call through PowerShell, so nothing is linked in.
# Voice typing only types into UI Automation text fields, which Tk entries
# are not. The native helper lays a Win32 EDIT over the Ask entry, focuses it
# and presses Win+H; DictateFinish copies the result back.
proc ::application::speech::WindowsDictation {} {
	variable Priv

	set entry [::application::ask::Entry]
	if {[llength [info commands ::chesswiz::win::dictateEdit]] && [winfo exists $entry]} {
		if {[::chesswiz::win::dictateEdit active]} { return }
		set Priv(dictateOriginal) [$entry get]
		set font [font actual [$entry cget -font]]
		set weight [expr {[dict get $font -weight] eq "bold" ? 700 : 400}]
		if {![catch {
			::chesswiz::win::dictateEdit begin $entry $Priv(dictateOriginal) [$entry index insert] \
				[dict get $font -family] [dict get $font -size] $weight \
				::application::speech::DictateFinish
		}]} {
			SetHint $::application::speech::mc::InstallWin
			return
		}
	}
	WindowsDictationHelper
}

# Commit: the EDIT's text replaces the entry's; cancel: the original stays.
# Neither submits the request.
proc ::application::speech::DictateFinish {action text} {
	variable Priv

	set entry [::application::ask::Entry]
	if {![winfo exists $entry]} { return }
	if {$action ne "commit"} {
		if {[info exists Priv(dictateOriginal)]} { set text $Priv(dictateOriginal) } else { set text [$entry get] }
	}
	unset -nocomplain Priv(dictateOriginal)
	$entry delete 0 end
	$entry insert 0 $text
	$entry icursor end
	focus -force $entry
}

proc ::application::speech::WindowsDictationHelper {} {
	set script {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ChesswizDictation {
    [StructLayout(LayoutKind.Sequential)]
    public struct Keyboard { public ushort vk, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)]
    public struct Mouse { public int x, y; public uint data, flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Explicit)]
    public struct Payload {
        [FieldOffset(0)] public Keyboard keyboard;
        [FieldOffset(0)] public Mouse mouse;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct Input { public uint type; public Payload payload; }
    [DllImport("user32.dll", SetLastError=true)]
    public static extern uint SendInput(uint count, Input[] inputs, int size);
    public static void Start() {
        Input[] inputs = new Input[4];
        ushort[] keys = { 0x5B, 0x48, 0x48, 0x5B };
        for (int i = 0; i < inputs.Length; ++i) {
            inputs[i].type = 1;
            inputs[i].payload.keyboard.vk = keys[i];
            inputs[i].payload.keyboard.flags = i < 2 ? 0u : 2u;
        }
        if (SendInput(4, inputs, Marshal.SizeOf(typeof(Input))) != 4)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
}
'@
[ChesswizDictation]::Start();
}
	# Run the helper in the background. Win+H asks the focused window for its
	# text-input context; a blocking exec would stall the Tk event loop at that
	# moment, so Windows sees no input context and shows no overlay.
	SetHint $::application::speech::mc::InstallWin
	if {[catch {
		set chan [open |[list powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command $script] r]
	}]} {
		return
	}
	fconfigure $chan -blocking 0
	fileevent $chan readable [list ::application::speech::DictationDone $chan]
	return
}

proc ::application::speech::DictationDone {chan} {
	read $chan
	if {![eof $chan]} { return }
	fconfigure $chan -blocking 1
	catch { close $chan }
}

# ======================================================================
# Preferences > Assistant.
# ======================================================================
proc ::application::ask::Preferences {args} {
	variable Priv
	variable mc

	# Opened from another dialog (Choose Model), it belongs to that dialog:
	# transient to the main window it would open underneath it.
	set parent .application
	if {[llength $args] && [winfo exists [lindex $args 0]]} { set parent [winfo toplevel [lindex $args 0]] }
	set dlg .application.assistantPreferences
	if {[winfo exists $dlg]} {
		wm transient $dlg $parent
		raise $dlg
		focus -force $dlg
		return
	}
	toplevel $dlg -class Dialog
	wm title $dlg $mc::PrefsTitle
	wm transient $dlg $parent
	set top [ttk::frame $dlg.content -padding 12]
	pack $top -fill both -expand yes

	ttk::checkbutton $top.startup -text $mc::StartupAssistant \
		-variable ::application::Options(assistant:startup) \
		-command ::application::assistant::panel::SyncPreference
	pack $top.startup -anchor w -pady {0 8}

	ttk::label $top.title -text $mc::SpeechInput -font TkHeadingFont
	pack $top.title -anchor w -pady {0 4}
	ttk::label $top.hint -text [::application::speech::hint] -wraplength 460 \
		-justify left -foreground #7a4b00
	pack $top.hint -anchor w -pady {0 8}
	if {[::application::speech::hint] eq ""} {
		$top.hint configure -text $mc::SpeechReady
	}

	set vars [dict create \
		whisperCli ::application::speech::Settings(whisperCli) \
		whisperModel ::application::speech::Settings(whisperModel) \
		recorder ::application::speech::Settings(recorder) \
		sherpaCli ::application::speech::Settings(sherpaCli) \
		sherpaModel ::application::speech::Settings(sherpaModel) \
		hotwords ::application::speech::Settings(hotwords) \
		stub ::application::speech::Settings(stub)]
	# field name -> the mc string that labels it, so a language switch can
	# relabel the open dialog in place
	set fields {}
	foreach {key name} {
		sherpaCli	PathSherpa
		sherpaModel	PathSherpaModel
		hotwords	PathHotwords
		whisperCli	PathWhisper
		whisperModel	PathModel
		recorder	PathRecorder
		stub		PathStub
	} {
		set row [ttk::frame $top.$key]
		ttk::label $row.label -text [set mc::$name] -width 26 -anchor w
		ttk::entry $row.entry -textvariable ::application::speech::Settings($key) -width 46
		pack $row.label -side left
		pack $row.entry -side left -fill x -expand yes
		pack $row -fill x -pady 2
		lappend fields $row.label $name
	}

	set status [ttk::label $top.status -text [::application::speech::status] -wraplength 460 \
		-justify left -foreground #555555]
	pack $status -anchor w -pady {8 4}

	set buttons [ttk::frame $top.buttons]
	ttk::button $buttons.detect -text $mc::Detect -command [list ::application::ask::PrefsDetect $status]
	ttk::button $buttons.close -text $mc::Close -command [list destroy $dlg]
	pack $buttons.detect -side left -padx {0 6}
	pack $buttons.close -side right
	pack $buttons -fill x -pady {8 0}

	# a language switch relabels the open dialog in place; the paths the
	# user typed are in the settings, not in these labels
	set Priv(prefs) $dlg
	set Priv(prefsStartup) $top.startup
	set Priv(prefsTitle) $top.title
	set Priv(prefsHint) $top.hint
	set Priv(prefsStatus) $status
	set Priv(prefsDetect) $buttons.detect
	set Priv(prefsClose) $buttons.close
	set Priv(prefsFields) $fields
	bind $dlg <<LanguageChanged>> +[namespace code RelabelPreferences]
	bind $dlg <Destroy> +[namespace code ForgetPreferences]

	bind $dlg <Escape> [list destroy $dlg]
	bind $dlg <F1> [list ::help::open .application Ask-Field -parent $dlg]
	::util::place $dlg -parent $parent -position center
	raise $dlg
	focus -force $top.whisperCli.entry
}

proc ::application::ask::ForgetPreferences {} {
	variable Priv
	foreach key {prefs prefsStartup prefsTitle prefsHint prefsStatus prefsDetect prefsClose prefsFields} {
		set Priv($key) {}
	}
	return
}

# The dialog's labels follow the language; the status line and the hint
# are derived text, so they are asked for again rather than translated.
proc ::application::ask::RelabelPreferences {} {
	variable Priv
	variable mc

	if {![info exists Priv(prefs)] || ![winfo exists $Priv(prefs)]} { return }
	wm title $Priv(prefs) $mc::PrefsTitle
	foreach {widget text} [list $Priv(prefsStartup) $mc::StartupAssistant \
		$Priv(prefsTitle) $mc::SpeechInput \
		$Priv(prefsDetect) $mc::Detect $Priv(prefsClose) $mc::Close] {
		if {[winfo exists $widget]} { $widget configure -text $text }
	}
	foreach {widget name} $Priv(prefsFields) {
		if {[winfo exists $widget]} { $widget configure -text [set mc::$name] }
	}
	if {[winfo exists $Priv(prefsHint)]} {
		set hint [::application::speech::hint]
		if {$hint eq ""} { set hint $mc::SpeechReady }
		$Priv(prefsHint) configure -text $hint
	}
	if {[winfo exists $Priv(prefsStatus)]} {
		$Priv(prefsStatus) configure -text [::application::speech::status]
	}
	return
}

# Detect searches the usual install places for what the fields leave empty
# (or point at nothing), fills in what it finds, and always reports: what it
# found, what is still missing and the time, so a click visibly did something.
proc ::application::ask::PrefsDetect {status} {
	set found [::application::speech::search]
	set d [::application::speech::detect]
	set lines [list "Checked at [clock format [clock seconds] -format %H:%M:%S]."]
	if {[llength $found]} {
		lappend lines "Found: [join $found {; }]."
	}
	if {[dict get $d available]} {
		lappend lines "Speech input is ready."
	} else {
		lappend lines [dict get $d reason]
		lappend lines "Searched PATH, ~/whisper.cpp, ~/src/whisper.cpp, ~/.cache/whisper,\
			~/.local/share/whisper and /usr/(local/)share/whisper.cpp."
	}
	if {[winfo exists $status]} {
		$status configure -text [join $lines \n] -foreground [expr {[dict get $d available] ? "#1d6b2a" : "#7a4b00"}]
	}
	::application::speech::SetHint [::application::speech::hint]
	::application::ask::SyncMic
}

# ======================================================================
# Key bindings on the main window (D-2 / D-7).
# ======================================================================
if {[llength [info commands ::application::ask::Build]]} {
	catch {
		bind .application <Control-Key-k> {::application::ask::CtrlK}
		bind .application <Control-Key-K> {::application::ask::CtrlShiftK}
		# New widgets (panes, dialogs, the engine console, the comment
		# editor) get the private tag before they can take a key.
		bind all <Map> +[list ::application::ask::AttachShortcutTag %W]
		bind all <FocusIn> +[list ::application::ask::AttachShortcutTag %W]
	}
}

# vi:set ts=3 sw=3:

# Save the highlighted concrete command; no alias text is ever executable Tcl.
proc ::application::ask::Aliases {} {
 variable Priv
 variable mc
 ::commandline::LoadLearning
 set Priv(aliasRow) {}
 if {[info exists Priv(commands)] && [llength $Priv(commands)]} {
  set row [lindex $Priv(commands) $Priv(index)]
  # Aliases persist grammar input and re-match it before execution. A raw
  # registry palette row has no such command text; use the normal prompt.
  if {$row ne "" && ![dict exists $row palette]} {set Priv(aliasRow) $row}
 }
 set w .application.commandAliases
 if {[winfo exists $w]} {raise $w; return}
 toplevel $w
 wm title $w $mc::AliasesTitle
 wm transient $w .application
 ttk::label $w.help -text $mc::AliasesHelp -padding 8
 ttk::entry $w.name -width 40
 listbox $w.list -height 8 -exportselection 0
 foreach alias [lsort [dict keys $::commandline::Aliases]] {$w.list insert end $alias}
 ttk::button $w.save -text $mc::AliasesSave -command ::application::ask::SaveAlias
 ttk::button $w.remove -text $mc::AliasesRemove -command ::application::ask::DeleteAlias
 ttk::label $w.status -text "" -wraplength 420
 if {$Priv(aliasRow) ne ""} {$w.status configure -text [dict get $Priv(aliasRow) label]}
 pack $w.help $w.name $w.list $w.save $w.remove $w.status -fill x -padx 8 -pady 4
 bind $w.name <Return> {::application::ask::SaveAlias; break}
 bind $w <Escape> [list destroy $w]
 focus -force $w.name
}
proc ::application::ask::SaveAlias {} {
 variable Priv
 variable mc
 set w .application.commandAliases
 if {$Priv(aliasRow) eq ""} {$w.status configure -text $mc::AliasesNeedCommand; return}
 if {[catch {::commandline::AddAlias [$w.name get] $Priv(aliasRow)} error]} {$w.status configure -text $error; return}
 $w.list delete 0 end
 foreach alias [lsort [dict keys $::commandline::Aliases]] {$w.list insert end $alias}
 $w.status configure -text $mc::AliasesSaved
}
proc ::application::ask::DeleteAlias {} {
 variable mc
 set w .application.commandAliases
 set selection [$w.list curselection]
 if {$selection eq ""} {return}
 if {[catch {::commandline::RemoveAlias [$w.list get $selection]} error]} {$w.status configure -text $error; return}
 $w.list delete $selection
 $w.status configure -text $mc::AliasesRemoved
}
