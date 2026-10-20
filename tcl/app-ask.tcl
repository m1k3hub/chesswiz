# ======================================================================
# ::application::ask -- the Ask field (the palette input) and speech input.
#
# Decision 003 / D-7: the Ask field in the top strip *is* the palette.
# There is no separate palette window.
#
#   Typing filters the action registry on every keystroke into a result
#   list under the field. Only runnable actions are listed (the same
#   enabled/visible predicates as the main drop-down, VAL-RULE-004).
#   Up/Down select, Enter runs the selection through ::action::run (so
#   the registry confirm gate applies). The last row is always "Ask the
#   assistant": selecting it, or a query with no matching action, sends
#   the text to the assistant as plain language. Esc closes the list and
#   restores the focus that was there before.
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
#   Linux: whisper.cpp's whisper-cli (CPU only; CUDA_VISIBLE_DEVICES="")
#          plus arecord or ffmpeg. Windows: the operating system's Win+H
#          dictation. macOS: the system dictation hint. With no path the
#          microphone is hidden and Preferences > Assistant says what to
#          install (no error dialog).
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
set Placeholder		"Ask or tell Chesswiz what to do (Ctrl+K)"
set AskAssistant		"Ask the assistant"
set Send				"Send to the assistant"
set Mic				"Speak"
set Recording		"Recording… click to stop"
set Transcribing	"Transcribing… click to cancel"
set Heard			"Heard: %s"
set NothingHeard	"Nothing heard"
set AssistantPrefs	"Assistant Preferences…"
}

variable Query ""
variable Priv
array set Priv {
	index		0
	rows		{}
	focusBefore	{}
	histIndex	-1
	list		{}
	window		{}
}

} ;# namespace ask
} ;# namespace application

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
	set entry [ttk::entry $frame.entry -takefocus 1 \
		-textvariable ::application::ask::Query]
	set mic [ttk::button $frame.mic -text $::application::ask::mc::Mic \
		-takefocus 0 -command ::application::speech::toggle]
	pack $mic -side right -padx {2 2} -pady 1
	pack $entry -side left -fill x -expand yes -padx {2 2} -pady 1

	set placeholder [ttk::label $frame.placeholder \
		-text $::application::ask::mc::Placeholder -foreground grey]
	place $placeholder -in $entry -relx 0 -x 4 -rely 0.5 -anchor w

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
	bind $frame <Destroy> +::application::speech::CleanupSession

	SyncMic
	PlaceholderState
	RegisterAction
	return $frame
}

# Keep the placeholder visible exactly while the field is empty.
proc ::application::ask::PlaceholderState {} {
	variable Priv
	variable Query

	if {![info exists Priv(placeholder)] || ![winfo exists $Priv(placeholder)]} { return }
	if {[string length $Query]} {
		place forget $Priv(placeholder)
	} else {
		place $Priv(placeholder) -in $Priv(entry) -relx 0 -x 4 -rely 0.5 -anchor w
	}
}

proc ::application::ask::EnterField {entry placeholder} {
	PlaceholderState
}

proc ::application::ask::LeaveField {entry placeholder} {
	PlaceholderState
}

# Put the field in the top strip, immediately left of the main drop-down.
proc ::application::ask::Place {menuX height} {
	variable Priv
	variable Width

	if {![info exists Priv(frame)] || ![winfo exists $Priv(frame)]} { return }
	if {![info exists Width]} { set Width 380 }
	set width $Width
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
	if {[llength [info commands ::application::speech::available]] \
	 && [::application::speech::available]} {
		if {[manager::place? $Priv(mic)] eq ""} { pack $Priv(mic) -side right -padx {2 2} -pady 1 }
	} else {
		catch { pack forget $Priv(mic) }
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
	if {[dict exists $::action::Registry app.preferences.assistant]} { return }
	::action::register app.preferences.assistant [dict create \
		label    "Assistant Preferences…" \
		object   {} \
		handler  [list ::application::ask::Preferences] \
		what     "open the Assistant preferences" \
		ai       1 \
		doc      "Choose the local speech tools (whisper-cli, model, recorder) and see what to install when speech input is not available." \
	]
}

# ======================================================================
# Focus and startup.
# ======================================================================
proc ::application::ask::Focus {} {
	variable Priv

	if {![winfo exists [Entry]]} { return 0 }
	set current [focus]
	if {$current ne [Entry]} { set Priv(focusBefore) $current }
	if {$Priv(focusBefore) eq "" && [BoardWidget] ne ""} {
		set Priv(focusBefore) [BoardWidget]
	}
	focus -force [Entry]
	catch { [Entry] selection range 0 end }
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

# Ctrl+K and Ctrl+Shift+K are bound on the main window. On Text/Script
# widgets the class binding has already killed the line; leave it alone.
proc ::application::ask::CtrlK {} {
	if {[InMultilineEditor]} { return }
	Focus
}

proc ::application::ask::CtrlShiftK {} {
	Focus
}

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
	if {[string trim $Query] eq ""} {
		set Priv(rows) {}
		HideList
		return
	}
	set Priv(rows) [::action::labels asklist [string trim $Query]]
	set Priv(index) 0
	ShowList
}

proc ::application::ask::ShowList {} {
	variable Priv
	variable Query
	variable mc

	set rows $Priv(rows)
	set assistantIndex [llength $rows]
	set items {}
	set i 0
	foreach row $rows {
		lassign $row id label accel enabled visible
		set text [format " %-48s %s" $label $accel]
		lappend items [list $text $id]
		incr i
	}
	lappend items [list " $mc::AskAssistant" ""]

	set w $Priv(list)
	if {$w eq "" || ![winfo exists $w]} {
		set w .application.askList
		catch { destroy $w }
		toplevel $w -class AskList
		wm overrideredirect $w 1
		wm transient $w .application
		listbox $w.list -exportselection 0 -takefocus 0 -activestyle none \
			-height 1 -borderwidth 1 -relief solid -highlightthickness 0
		pack $w.list -fill both -expand yes
		bind $w.list <ButtonPress-1> "[list ::application::ask::Click] %y"
		bind $w.list <ButtonRelease-1> { break }
		bind $w.list <Double-Button-1> { break }
		set Priv(list) $w
	}
	set list $w.list
	$list delete 0 end
	foreach item $items { $list insert end [lindex $item 0] }
	if {[llength $items]} {
		if {$Priv(index) < 0} { set Priv(index) 0 }
		if {$Priv(index) >= [llength $items]} { set Priv(index) [expr {[llength $items] - 1}] }
		$list selection clear 0 end
		$list selection set $Priv(index)
		$list activate $Priv(index)
		$list see $Priv(index)
	}

	set entry [Entry]
	if {[winfo exists $entry]} {
		set x [winfo rootx $entry]
		set y [expr {[winfo rooty $entry] + [winfo height $entry] + 2}]
		set width [expr {[winfo width $entry] + [winfo width [Mic]] + 8}]
		set rowHeight [expr {[font metrics [$list cget -font] -linespace] + 4}]
		set height [expr {min(320, max($rowHeight, [llength $items] * $rowHeight + 4))}]
		wm geometry $w "${width}x${height}+${x}+${y}"
	}
	catch { wm deiconify $w }
	catch { raise $w }
	return $w
}

proc ::application::ask::HideList {} {
	variable Priv
	if {[info exists Priv(list)] && $Priv(list) ne ""} {
		catch { wm withdraw $Priv(list) }
	}
}

proc ::application::ask::ListVisible {} {
	variable Priv
	if {![info exists Priv(list)] || $Priv(list) eq ""} { return 0 }
	if {![winfo exists $Priv(list)]} { return 0 }
	return [expr {[wm state $Priv(list)] eq "normal"}]
}

proc ::application::ask::Move {direction} {
	variable Priv

	if {![ListVisible]} {
		if {$direction < 0} { return [HistoryStep -1] }
		return [HistoryStep 1]
	}
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
	Choose
	return "break"
}

proc ::application::ask::Choose {} {
	variable Priv
	variable Query

	if {![ListVisible] && [string trim $Query] eq ""} { return "break" }
	if {![llength $Priv(rows)]} { return [SendToAssistant] }

	set index $Priv(index)
	if {$index < [llength $Priv(rows)]} {
		lassign [lindex $Priv(rows) $index] id
		HideList
		catch { focus -force [Entry] }
		set failed [catch { ::action::run $id } result]
		if {$failed || [string match "error:*" $result] || [string match "declined*" $result]} {
			# ::action::run reports errors as text; a raising handler is
			# reported the same way, never as a Tk background error.
			catch { ::ui::message $result }
		} else {
			set Query ""
		}
		PlaceholderState
		return "break"
	}
	return [SendToAssistant]
}

proc ::application::ask::SendToAssistant {} {
	variable Priv
	variable Query

	set submitted [[::application::ask::Entry] get]
	set text [string trim $submitted]
	if {$text eq ""} { return "break" }
	HideList
	if {![llength [info commands ::application::assistant::ask]]} {
		catch {::ui::message "Assistant is unavailable."}
		return "break"
	}
	if {[llength [info commands ::application::assistant::show]]} {
		catch { ::application::assistant::show }
	}
	if {[catch {::application::assistant::ask $text} accepted]} {
		catch {::ui::message "error: $accepted"}
		return "break"
	}
	if {$accepted ne "1"} {
		catch {::ui::message "Assistant is busy. Try again when it finishes."}
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
set Install		"Speech input needs whisper-cli (whisper.cpp), a ggml model and arecord or ffmpeg. Set them in Preferences > Assistant."
set InstallMac	"macOS uses the system dictation: turn it on in System Settings > Keyboard > Dictation, then press the dictation key (or Fn Fn)."
set InstallWin	"Windows uses the system dictation: press Win+H while the Ask field has focus."
set Listening	"Recording… click to stop"
set Working		"Transcribing… click to cancel"
set Nothing		"Nothing heard"
set Failed		"Speech failed: %s"
set NoRecord	"Speech was cancelled"
}

variable Settings
array set Settings {
	whisperCli	""
	whisperModel	""
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
	transcribeStart	0
	stable		0
	lastSize	-1
	tempFiles	{}
	sessionDir	""
}

} ;# namespace speech
} ;# namespace application

foreach {speechEnv speechKey} {
	SCIDB_AI_WHISPER_CLI	whisperCli
	SCIDB_AI_WHISPER_MODEL	whisperModel
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

# The speech path in effect: {mode available reason cli model recorder stub}.
proc ::application::speech::detect {} {
	variable Settings

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
	if {$recorder eq "" && [dict exists $fixture recorder]} { set recorder [dict get $fixture recorder] }

	set platform $::tcl_platform(platform)
	if {$stub ne ""} {
		return [dict create mode stub available 1 reason "" cli $cli model $model recorder $recorder stub $stub]
	}
	if {$platform eq "windows"} {
		return [dict create mode windows available 1 reason "" cli "" model "" recorder "" stub ""]
	}
	if {$::tcl_platform(os) eq "Darwin"} {
		return [dict create mode mac available 1 reason "" cli "" model "" recorder "" stub ""]
	}

	set cliPath [which $cli]
	set modelPath $model
	if {![file exists $modelPath]} { set modelPath "" }
	set recPath ""
	if {$recorder ne "" && $recorder ne "auto"} {
		set recPath [which $recorder]
	} else {
		foreach candidate {arecord ffmpeg} {
			set recPath [which $candidate]
			if {$recPath ne ""} { break }
		}
	}

	set available [expr {$cliPath ne "" && $modelPath ne "" && $recPath ne ""}]
	set reason ""
	if {!$available} {
		set missing {}
		if {$cliPath eq ""} { lappend missing "whisper-cli" }
		if {$modelPath eq ""} { lappend missing "a ggml model" }
		if {$recPath eq ""} { lappend missing "arecord or ffmpeg" }
		set reason [format "%s Missing: %s." [string trim $::application::speech::mc::Install] [join $missing ", "]]
	}
	return [dict create mode whisper available $available reason $reason \
		cli $cliPath model $modelPath recorder $recPath stub ""]
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
	if {[dict get $d cli] ne ""} { lappend parts "whisper-cli [dict get $d cli]" }
	if {[dict get $d model] ne ""} { lappend parts "model [dict get $d model]" }
	if {[dict get $d recorder] ne ""} { lappend parts "recorder [dict get $d recorder]" }
	if {![dict get $d available]} { lappend parts [hint] }
	return [join $parts "; "]
}

# ----------------------------------------------------------------------
# The microphone button.
# ----------------------------------------------------------------------
proc ::application::speech::toggle {} {
	variable Priv
	variable Settings

	switch -- $Priv(state) {
		idle {
			Start
		}
		recording {
			StopRecording
		}
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
	if {$mode eq "windows"} { ::application::speech::WindowsDictation; return }
	if {$mode eq "mac"} { ShowHint; return }

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
		return
	}
	set pids {}
	if {[catch {
		set pids [exec {*}[RecorderArgv $d $file] > /dev/null 2>@1 &]
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

proc ::application::speech::RecorderArgv {d file} {
	set recoder [dict get $d recorder]
	set base [file tail $recoder]
	if {$base eq "arecord" || $base eq "arecord.exe"} {
		return [list $recoder -q -f S16_LE -r 16000 -c 1 -t wav $file]
	}
	# ffmpeg: PulseAudio is the usual Linux desktop, ALSA the fallback.
	return [list $recoder -y -loglevel quiet -f pulse -i default -ar 16000 -ac 1 -c:a pcm_s16le $file]
}

proc ::application::speech::StopRecording {} {
	variable Priv

	if {$Priv(state) ne "recording"} { return }
	foreach pid $Priv(recordPids) { catch { exec kill -TERM $pid } }
	set Priv(recordPids) {}
	set file $Priv(recordFile)
	set Priv(recordFile) ""
	SetState transcribing
	SetMicText $::application::speech::mc::Working
	# give the recorder a moment to flush its header
	Schedule 200 [list StartTranscribe $file]
}

# Cancel (button while transcribing, Esc, or the API): insert nothing.
proc ::application::speech::Cancel {} {
	variable Priv

	foreach pid [concat $Priv(recordPids) $Priv(transcribePids)] {
		catch { exec kill -TERM $pid }
	}
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
	if {![dict get $d available] || [dict get $d mode] ni {whisper stub}} {
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
	set argv [list $cli -m $model -f $file -nt -np]
	set cmd [list env CUDA_VISIBLE_DEVICES= {*}$argv]
	set pids {}
	if {[catch { set pids [exec {*}$cmd >@ $output 2> /dev/null &] } err]} {
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
		if {[catch { exec kill -0 $pid }]} { continue }
		return 1
	}
	return 0
}

proc ::application::speech::PollTranscribe {} {
	variable Priv

	if {$Priv(state) ne "transcribing"} { Cleanup; return }
	set out $Priv(transcribeOut)
	if {$out eq "" || ![file exists $out]} {
		if {![Alive? $Priv(transcribePids)]} { FinishTranscribe } else { Schedule 120 PollTranscribe }
		return
	}
	set size [file size $out]
	if {$size == $Priv(lastSize)} { incr Priv(stable) } else { set Priv(stable) 0; set Priv(lastSize) $size }
	if {![Alive? $Priv(transcribePids)] && $Priv(stable) >= 1} { FinishTranscribe; return }
	if {[clock milliseconds] - $Priv(transcribeStart) > 120000} {
		Cancel
		return
	}
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
	if {$text eq ""} { return 0 }
	if {![winfo exists [::application::ask::Entry]]} { return 0 }
	set entry [::application::ask::Entry]
	$entry insert insert $text
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
	set cmd [list env CUDA_VISIBLE_DEVICES= [dict get $d cli] -m [dict get $d model] \
		-f $file -nt -np]
	return [string trim [exec {*}$cmd 2> /dev/null]]
}

# A directory is created atomically with private permissions. Existing
# paths must be real directories owned by this user and remain private.
# Each process/session has its own private subdirectory (pid + random)
# so concurrent instances never collide or clean each other's files.
proc ::application::speech::TempDir {} {
	variable Priv
	set base /tmp
	if {[info exists ::env(TMPDIR)] && $::env(TMPDIR) ne ""} { set base $::env(TMPDIR) }
	set userDir [file join [file normalize $base] chesswiz-ask-[exec id -u]]
	catch {exec mkdir -m 0700 -- $userDir}
	if {[file type $userDir] ne "directory" || ![file owned $userDir]
		|| ([file attributes $userDir -permissions] & 0077) != 0} {
		error "speech temporary directory is not private"
	}
	if {![info exists Priv(sessionDir)] || $Priv(sessionDir) eq ""
		|| [file dirname $Priv(sessionDir)] ne $userDir
		|| ![file exists $Priv(sessionDir)]} {
		for {set attempt 0} {$attempt < 10} {incr attempt} {
			set rand [format %06x [expr {int(rand() * 0xffffff)}]]
			set sdir [file join $userDir "session-[pid]-$rand"]
			if {[file exists $sdir]} { continue }
			catch {exec mkdir -m 0700 -- $sdir}
			if {[file exists $sdir]} { break }
		}
		if {![file exists $sdir] || [file type $sdir] ne "directory" || ![file owned $sdir]
			|| ([file attributes $sdir -permissions] & 0077) != 0} {
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
}

# Windows: the operating system's dictation (Win+H). Implemented with the
# Win32 SendInput call through PowerShell, so nothing is linked in.
proc ::application::speech::WindowsDictation {} {
	set script {
Add-Type -Namespace W -Name K -MemberDefinition '[DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, System.UIntPtr dwExtraInfo);';
[W.K]::keybd_event(0x5B,0,0,[System.UIntPtr]::Zero);
[W.K]::keybd_event(0x48,0,0,[System.UIntPtr]::Zero);
[W.K]::keybd_event(0x48,0,2,[System.UIntPtr]::Zero);
[W.K]::keybd_event(0x5B,0,2,[System.UIntPtr]::Zero);
}
	set hint $::application::speech::mc::InstallWin
	if {[catch { exec powershell -NoProfile -NonInteractive -Command $script }]} {
		SetHint $hint
	} else {
		SetHint $hint
	}
	return
}

# ======================================================================
# Preferences > Assistant.
# ======================================================================
proc ::application::ask::Preferences {args} {
	set dlg .application.assistantPreferences
	if {[winfo exists $dlg]} { raise $dlg; return }
	toplevel $dlg -class Dialog
	wm title $dlg "Assistant"
	wm transient $dlg [winfo toplevel .application]
	set top [ttk::frame $dlg.content -padding 12]
	pack $top -fill both -expand yes

	ttk::label $top.title -text "Speech input" -font TkHeadingFont
	pack $top.title -anchor w -pady {0 4}
	ttk::label $top.hint -text [::application::speech::hint] -wraplength 460 \
		-justify left -foreground #7a4b00
	pack $top.hint -anchor w -pady {0 8}
	if {[::application::speech::hint] eq ""} {
		$top.hint configure -text "A local speech path is configured."
	}

	set vars [dict create \
		whisperCli ::application::speech::Settings(whisperCli) \
		whisperModel ::application::speech::Settings(whisperModel) \
		recorder ::application::speech::Settings(recorder) \
		stub ::application::speech::Settings(stub)]
	foreach {key label} {
		whisperCli "whisper-cli path"
		whisperModel "ggml model path"
		recorder "Recorder (arecord/ffmpeg)"
		stub "Test stub command (optional)"
	} {
		set row [ttk::frame $top.$key]
		ttk::label $row.label -text $label -width 26 -anchor w
		ttk::entry $row.entry -textvariable ::application::speech::Settings($key) -width 46
		pack $row.label -side left
		pack $row.entry -side left -fill x -expand yes
		pack $row -fill x -pady 2
	}

	set status [ttk::label $top.status -text [::application::speech::status] -wraplength 460 \
		-justify left -foreground #555555]
	pack $status -anchor w -pady {8 4}

	set buttons [ttk::frame $top.buttons]
	ttk::button $buttons.detect -text "Detect" -command [list ::application::ask::PrefsDetect $status]
	ttk::button $buttons.close -text "Close" -command [list destroy $dlg]
	pack $buttons.detect -side left -padx {0 6}
	pack $buttons.close -side right
	pack $buttons -fill x -pady {8 0}

	bind $dlg <Escape> [list destroy $dlg]
	bind $dlg <F1> [list ::help::open .application Ask-Field -parent $dlg]
	::util::place $dlg -parent .application -position center
	focus -force $top.whisperCli.entry
}

proc ::application::ask::PrefsDetect {status} {
	if {[winfo exists $status]} {
		$status configure -text [::application::speech::status]
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
	}
}

# vi:set ts=3 sw=3:
