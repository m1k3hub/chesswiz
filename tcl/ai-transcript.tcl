# ======================================================================
# AI: media transcript (audit item C4 -- make an audio lesson searchable)
# ======================================================================
# The speech of an audio (or video) lesson as text, so the assistant can
# answer "what does this lesson say about X" and the media pane can show
# what a lesson is about.  It uses the same local speech-to-text the voice
# assistant uses.  Nothing is stored, no database is written and the media
# player is not touched: the transcript is returned to the caller.
#
#   ::ai::transcript::available -> 0|1
#                               1 when a working STT command is discoverable
#                               (SCIDB_AI_STT, or faster-whisper behind the
#                               shipped scripts/stt-transcribe.py)
#   ::ai::transcript::transcribe <audiofile> <script>
#                               runs the engine one-shot and asynchronously;
#                               <script> is called at global level with
#                               {ok 1 text TRANSCRIPT} or {ok 0 error MESSAGE}
#   ::ai::transcript::summary <text>
#                               a deterministic short description (the first
#                               sentences, word-capped) -- no model needed
#
# Engine discovery mirrors ::application::voice (tcl/app-voice.tcl):
#   SCIDB_AI_STT=auto|off|<command template>
#     "auto"    the shipped transcriber scripts/stt-transcribe.py, behind
#               a python that can import faster_whisper
#     "off"     no engine
#     template  any command that prints the transcript on stdout; %f is the
#               file, %m the model, %l the language; the magic value
#               "script" forces the shipped transcriber
# SCIDB_AI_STT_MODEL, SCIDB_AI_STT_DEVICE and SCIDB_AI_STT_LANGUAGE feed the
# shipped transcriber and the %m/%l substitutions, as the voice settings do.
#
# A template is trusted only when its program is findable, and "auto" only
# when the shipped script is installed; without an engine
# ::ai::transcript::transcribe still calls back, with ok 0.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-transcript
}

package require Tcl 8.5

namespace eval ::ai::transcript {

	# pipes of running engines: channel -> {script bytes errFile}
	variable Pipes
	array set Pipes {}

	variable Count 0

	# the interpreter that can import faster_whisper, probed once, lazily
	variable Python {}
	variable PythonProbed 0

	# this module's own directory: <root>/tcl, the script in <root>/scripts
	variable ModuleDir [file dirname [file normalize [info script]]]

	# summary: the first sentences, capped at so many words
	variable SummarySentences 2
	variable SummaryWords 40
}


# ======================================================================
# Engine discovery.
# ======================================================================

# The python interpreter that can import faster_whisper, or {}.  Probed
# lazily and once: startup never waits for a python import.
proc ::ai::transcript::fasterWhisperPython {} {
	variable Python
	variable PythonProbed

	if {!$PythonProbed} {
		set Python {}
		foreach py {python3 python} {
			if {![llength [auto_execok $py]]} { continue }
			if {![catch { exec $py -c "import faster_whisper" 2>/dev/null }]} {
				set Python $py
				break
			}
		}
		set PythonProbed 1
	}
	return $Python
}


# The path of the shipped transcriber, or {}.  The build installs it
# below the share directory (tcl/Makefile: $(DATADIR)/scripts); in the
# source tree it is the scripts/ directory next to this module's own.
proc ::ai::transcript::sttScript {} {
	set candidates {}
	if {[info exists ::scidb::dir::share]} {
		lappend candidates [file join $::scidb::dir::share scripts stt-transcribe.py]
	}
	lappend candidates [file join $::ai::transcript::ModuleDir .. scripts stt-transcribe.py]
	if {[info exists ::nameofexecutable]} {
		lappend candidates [file join [file dirname $::nameofexecutable] stt-transcribe.py]
	}
	foreach candidate $candidates {
		if {[file exists $candidate]} { return $candidate }
	}
	return {}
}


# The model / device / language of the shipped transcriber, defaulting
# to what the voice assistant ships with.
proc ::ai::transcript::model {} {
	return [expr {[info exists ::env(SCIDB_AI_STT_MODEL)] ? $::env(SCIDB_AI_STT_MODEL) : "small.en"}]
}


proc ::ai::transcript::device {} {
	return [expr {[info exists ::env(SCIDB_AI_STT_DEVICE)] ? $::env(SCIDB_AI_STT_DEVICE) : "cpu"}]
}


proc ::ai::transcript::language {} {
	return [expr {[info exists ::env(SCIDB_AI_STT_LANGUAGE)] ? $::env(SCIDB_AI_STT_LANGUAGE) : "en"}]
}


# The STT engine: {} (none found), "script" (the shipped transcriber), or
# a command template.  SCIDB_AI_STT decides, as ::application::voice does.
proc ::ai::transcript::engine {} {
	if {[info exists ::env(SCIDB_AI_STT)]} {
		set setting [string trim $::env(SCIDB_AI_STT)]
	} else {
		set setting auto
	}

	if {$setting eq "" || $setting eq "off"} { return {} }

	if {$setting ne "auto"} {
		if {$setting eq "script"} {
			if {[llength [fasterWhisperPython]] && [llength [sttScript]]} { return script }
			return {}
		}
		# a command template: usable when its program is findable
		if {![llength [auto_execok [lindex $setting 0]]]} { return {} }
		return $setting
	}

	# auto: the shipped transcriber behind faster-whisper
	if {[llength [fasterWhisperPython]] && [llength [sttScript]]} { return script }
	return {}
}


# 1 when a working speech-to-text command is discoverable, else 0.
proc ::ai::transcript::available {} {
	return [expr {[engine] ne ""}]
}


# The one-shot command that transcribes <file>, or {} when there is no
# engine.  Templates substitute: %f the file, %m the model, %l the language.
proc ::ai::transcript::argv {file} {
	set engine [engine]
	if {$engine eq ""} { return {} }

	if {$engine eq "script"} {
		set argv [list [fasterWhisperPython] [sttScript] --model [model] --device [device]]
		set language [language]
		if {[string length $language]} { lappend argv --language $language }
		lappend argv $file
		return $argv
	}

	set argv {}
	foreach word $engine {
		lappend argv [string map [list %f $file %m [model] %l [language]] $word]
	}
	return $argv
}


# <script> is called with {ok 1 text TRANSCRIPT} or {ok 0 error MESSAGE},
# always asynchronously, so the caller needs one code path.
proc ::ai::transcript::transcribe {file script} {
	set argv [argv $file]
	if {![llength $argv]} {
		after 0 [list {*}$script [list ok 0 error \
			"no speech-to-text engine (set SCIDB_AI_STT, or pip install faster-whisper)"]]
		return
	}
	runAsync $argv $script
	return
}


# ======================================================================
# Running the engine asynchronously: the interface never waits.
# ======================================================================

# <script> is called when the command has finished.
proc ::ai::transcript::runAsync {argv script} {
	variable Pipes
	variable Count

	set dir [tempDir]
	file mkdir $dir
	set errFile [file join $dir ai-transcript-[incr Count].err]
	if {[catch { set chan [open "|[list {*}$argv] 2>$errFile" r] } err]} {
		after 0 [list {*}$script [list ok 0 error $err]]
		return
	}
	fconfigure $chan -blocking 0 -buffering none
	set Pipes($chan) [list $script "" $errFile]
	fileevent $chan readable [namespace code [list OnReadable $chan]]
	return
}


proc ::ai::transcript::OnReadable {chan} {
	variable Pipes

	if {![info exists Pipes($chan)]} { return }
	lassign $Pipes($chan) script out errFile

	if {![eof $chan]} {
		append out [read $chan]
		set Pipes($chan) [list $script $out $errFile]
		return
	}

	# the engine is done: stdout is the transcript, stderr its complaint
	fileevent $chan readable {}
	unset Pipes($chan)
	set out [string trim $out]
	# a channel still non-blocking loses the child's exit status in close
	# (on 8.6 the status is only reported for a blocking pipeline): switch
	# back before closing, or a failing engine would look like an empty
	# transcript
	catch { fconfigure $chan -blocking 1 }
	set failed [catch { close $chan } err]

	# the child's complaint on stderr is the failure detail
	set said {}
	catch {
		set fh [open $errFile r]
		set said [string trim [read $fh]]
		close $fh
	}

	if {[string length $said]} {
		after 0 [list {*}$script [list ok 0 error $said]]
	} elseif {$failed && ![string length $out]} {
		# no stdout either: the close itself explains (an exit status the
		# event loop already reaped reports "child process lost", which is
		# only a failure when there is nothing to return)
		after 0 [list {*}$script [list ok 0 error [string trim $err]]]
	} else {
		after 0 [list {*}$script [list ok 1 text $out]]
	}
	catch { file delete -force -- $errFile }
	return
}


proc ::ai::transcript::tempDir {} {
	if {[info exists ::scidb::dir::temp]} { return $::scidb::dir::temp }
	return [file join /tmp scidb-ai-transcript-[pid]]
}


# ======================================================================
# summary -- a deterministic short description, no model.
# ======================================================================

# The sentences of <text>, on one line.
proc ::ai::transcript::sentences {text} {
	set text [string trim $text]
	if {![string length $text]} { return {} }

	set out {}
	foreach sentence [regexp -all -inline -- {[^.!?]+[.!?]?} $text] {
		set sentence [string trim $sentence]
		if {[string length $sentence]} { lappend out $sentence }
	}
	return $out
}


# The first SummarySentences sentences, capped at SummaryWords words.
# A " ..." suffix marks that the transcript went on longer.
proc ::ai::transcript::summary {text} {
	variable SummarySentences
	variable SummaryWords

	regsub -all {\s+} $text { } text
	set text [string trim $text]
	if {![string length $text]} { return "" }

	set out [join [lrange [sentences $text] 0 [expr {$SummarySentences - 1}]] { }]

	set words [split [string trim $out] { }]
	if {[llength $words] > $SummaryWords} {
		set out [join [lrange $words 0 [expr {$SummaryWords - 1}]] { }]
	}
	if {$out ne $text} { append out " ..." }
	return $out
}


# vi:set ts=3 sw=3:
