# ======================================================================
# Scidb App Test — media transcript (tcl/ai-transcript.tcl)
# ======================================================================
# The STT discovery (SCIDB_AI_STT, honoured like the voice assistant
# honours it), the one-shot asynchronous transcription, and the
# deterministic summary.
#
# No model, and no faster-whisper, are needed: the engine is a stubbed
# shell script that echoes a sentence (like the voice tests'), and the
# interpreter/script finders of ::ai::transcript are renamed aside for
# one test at a time.  Every test restores the environment it touched.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::transcript {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app transcript_[pid]]

	# the environment touched by envSet, for envUndo in -cleanup
	variable EnvSaved {}

	# what the stubbed ::ai::transcript finders answer
	variable Python {}
	variable ScriptPath {}
}

# ::ai::transcript is usually in the built app; before the SOURCES line is
# applied (patches/ai-transcript-integration.md), source it from the tree.
if {[llength [info commands ::ai::transcript::summary]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl ai-transcript.tcl]
}

# Remember what <name> is in the environment and set it to <value>
# ("" unsets it).  envUndo restores everything envSet changed, in -cleanup.
proc ::scidb::test::transcript::envSet {name value} {
	variable EnvSaved

	if {![dict exists $EnvSaved $name]} {
		if {[info exists ::env($name)]} {
			dict set EnvSaved $name [list $::env($name)]
		} else {
			dict set EnvSaved $name {}
		}
	}
	if {$value eq ""} {
		array unset ::env $name
	} else {
		set ::env($name) $value
	}
	return
}


proc ::scidb::test::transcript::envUndo {} {
	variable EnvSaved

	foreach name [dict keys $EnvSaved] {
		set saved [dict get $EnvSaved $name]
		if {[llength $saved]} {
			set ::env($name) [lindex $saved 0]
		} else {
			array unset ::env $name
		}
	}
	set EnvSaved {}
	return
}


# A small shell script under this test's directory, echoing/executing
# <body>; the STT engine of these tests (like the voice tests'), so they
# are unix-only.
proc ::scidb::test::transcript::shell {name body} {
	variable Dir

	set script [file join $Dir $name]
	set fh [open $script w]
	puts $fh "#!/bin/sh"
	puts $fh $body
	close $fh
	file attributes $script -permissions 0755
	return $script
}


# Force what the finders of ::ai::transcript answer for one test:
# <python> is what fasterWhisperPython reports ({} = not installed),
# <script> what sttScript reports ({} = not shipped).
proc ::scidb::test::transcript::stub {python script} {
	variable Python $python
	variable ScriptPath $script

	if {![llength [info commands ::scidb::test::transcript::realFwp]]} {
		rename ::ai::transcript::fasterWhisperPython ::scidb::test::transcript::realFwp
		rename ::ai::transcript::sttScript ::scidb::test::transcript::realScript
	}
	proc ::ai::transcript::fasterWhisperPython {} {
		return $::scidb::test::transcript::Python
	}
	proc ::ai::transcript::sttScript {} {
		return $::scidb::test::transcript::ScriptPath
	}
	return
}


# The other app tests run in this process after this file: the real
# finders go back.
proc ::scidb::test::transcript::restore {} {
	if {![llength [info commands ::scidb::test::transcript::realFwp]]} { return }
	rename ::ai::transcript::fasterWhisperPython {}
	rename ::ai::transcript::sttScript {}
	rename ::scidb::test::transcript::realFwp ::ai::transcript::fasterWhisperPython
	rename ::scidb::test::transcript::realScript ::ai::transcript::sttScript
	return
}


# The result of transcribe arrives through the event loop: pump it until
# <var> holds a dict (at most ~4 s).
proc ::scidb::test::transcript::wait {var} {
	set n 0
	while {(![info exists $var] || [llength [set $var]] < 2) && $n < 500} {
		update
		after 20
		incr n
	}
	if {[info exists $var]} { return [set $var] }
	return {}
}

# ----------------------------------------------------------------------

tcltest::test transcript-available-off {SCIDB_AI_STT=off makes an engine unfindable} -setup {
	file mkdir $::scidb::test::transcript::Dir
} -body {
	::scidb::test::transcript::stub python3 stt-fake.py
	::scidb::test::transcript::envSet SCIDB_AI_STT off
	list [::ai::transcript::available] [::ai::transcript::engine]
} -cleanup {
	::scidb::test::transcript::envUndo
	::scidb::test::transcript::restore
	file delete -force $::scidb::test::transcript::Dir
} -result {0 {}}

tcltest::test transcript-available-auto {auto finds the shipped transcriber behind a python} -body {
	::scidb::test::transcript::stub python3 [file join $::scidb::test::transcript::Dir stt-fake.py]
	::scidb::test::transcript::envSet SCIDB_AI_STT auto
	list [::ai::transcript::available] [::ai::transcript::engine]
} -cleanup {
	::scidb::test::transcript::envUndo
	::scidb::test::transcript::restore
	file delete -force $::scidb::test::transcript::Dir
} -result {1 script}

tcltest::test transcript-available-auto-no-python {auto without an interpreter finds nothing} -body {
	::scidb::test::transcript::stub {} [file join $::scidb::test::transcript::Dir stt-fake.py]
	::scidb::test::transcript::envSet SCIDB_AI_STT auto
	list [::ai::transcript::available] [::ai::transcript::engine]
} -cleanup {
	::scidb::test::transcript::envUndo
	::scidb::test::transcript::restore
	file delete -force $::scidb::test::transcript::Dir
} -result {0 {}}

tcltest::test transcript-available-template {a template with a real program is usable, others are not} -constraints unix -setup {
	file mkdir $::scidb::test::transcript::Dir
} -body {
	set fake [::scidb::test::transcript::shell fake-stt.sh "echo not run"]
	::scidb::test::transcript::envSet SCIDB_AI_STT "fake-missing-program --model %m %f"
	set missing [::ai::transcript::available]
	::scidb::test::transcript::envSet SCIDB_AI_STT "$fake --model %m --lang %l %f"
	list $missing [::ai::transcript::available] \
		[string equal [::ai::transcript::engine] "$fake --model %m --lang %l %f"]
} -cleanup {
	::scidb::test::transcript::envUndo
	::scidb::test::transcript::restore
	file delete -force $::scidb::test::transcript::Dir
} -result {0 1 1}

tcltest::test transcript-argv {the one-shot command is assembled, and templates substituted} -constraints unix -setup {
	file mkdir $::scidb::test::transcript::Dir
} -body {
	# the three STT_* settings at their defaults
	::scidb::test::transcript::envSet SCIDB_AI_STT auto
	::scidb::test::transcript::envSet SCIDB_AI_STT_MODEL ""
	::scidb::test::transcript::envSet SCIDB_AI_STT_DEVICE ""
	::scidb::test::transcript::envSet SCIDB_AI_STT_LANGUAGE ""
	::scidb::test::transcript::stub python3 [file join $::scidb::test::transcript::Dir stt-fake.py]
	set default [::ai::transcript::argv /tmp/x.wav]

	::scidb::test::transcript::envSet SCIDB_AI_STT_MODEL base.en
	::scidb::test::transcript::envSet SCIDB_AI_STT_DEVICE cuda
	::scidb::test::transcript::envSet SCIDB_AI_STT_LANGUAGE de
	set scripted [::ai::transcript::argv /tmp/x.wav]

	::scidb::test::transcript::shell fake-stt.sh "echo not run"
	::scidb::test::transcript::envSet SCIDB_AI_STT \
		"[file join $::scidb::test::transcript::Dir fake-stt.sh] --model %m --lang %l %f"
	set custom [::ai::transcript::argv /tmp/x.wav]

	list [lindex $default end] [lindex $default 0] [lrange $scripted 2 5] \
		[lrange $scripted 6 8] [lrange $custom 1 5]
} -cleanup {
	::scidb::test::transcript::envUndo
	::scidb::test::transcript::restore
	file delete -force $::scidb::test::transcript::Dir
} -result {/tmp/x.wav python3 {--model base.en --device cuda} {--language de /tmp/x.wav} {--model base.en --lang de /tmp/x.wav}}

tcltest::test transcript-transcribe {a stubbed STT command's output is the transcript} -constraints unix -setup {
	file mkdir $::scidb::test::transcript::Dir
} -body {
	set ::scidb::test::transcript::Result {}
	::scidb::test::transcript::envSet SCIDB_AI_STT \
		[::scidb::test::transcript::shell fake-stt.sh "echo switch to the database tab"]
	::ai::transcript::transcribe [file join $::scidb::test::transcript::Dir lesson.wav] \
		{set ::scidb::test::transcript::Result}
	set result [::scidb::test::transcript::wait ::scidb::test::transcript::Result]
	list [dict get $result ok] [dict get $result text]
} -cleanup {
	::scidb::test::transcript::envUndo
	::scidb::test::transcript::restore
	file delete -force $::scidb::test::transcript::Dir
} -result {1 {switch to the database tab}}

tcltest::test transcript-transcribe-fail {a failing engine reports its stderr} -constraints unix -setup {
	file mkdir $::scidb::test::transcript::Dir
} -body {
	set ::scidb::test::transcript::Result {}
	::scidb::test::transcript::envSet SCIDB_AI_STT \
		[::scidb::test::transcript::shell fake-fail.sh "echo cannot load model 1>&2 ; exit 1"]
	::ai::transcript::transcribe [file join $::scidb::test::transcript::Dir lesson.wav] \
		{set ::scidb::test::transcript::Result}
	set result [::scidb::test::transcript::wait ::scidb::test::transcript::Result]
	list [dict get $result ok] [string match "*cannot load model*" [dict get $result error]]
} -cleanup {
	::scidb::test::transcript::envUndo
	::scidb::test::transcript::restore
	file delete -force $::scidb::test::transcript::Dir
} -result {0 1}

tcltest::test transcript-transcribe-none {without an engine the caller still gets its callback} -setup {
	file mkdir $::scidb::test::transcript::Dir
} -body {
	set ::scidb::test::transcript::Result {}
	::scidb::test::transcript::envSet SCIDB_AI_STT off
	::ai::transcript::transcribe [file join $::scidb::test::transcript::Dir lesson.wav] \
		{set ::scidb::test::transcript::Result}
	set result [::scidb::test::transcript::wait ::scidb::test::transcript::Result]
	list [dict get $result ok] [string match "no speech-to-text engine*" [dict get $result error]]
} -cleanup {
	::scidb::test::transcript::envUndo
	::scidb::test::transcript::restore
	file delete -force $::scidb::test::transcript::Dir
} -result {0 1}

tcltest::test transcript-summary-sentences {the first sentences, and " ..." when the text went on} -body {
	list [::ai::transcript::summary "White plays Rxe4. The rook is lost. Black resigned."] \
		[::ai::transcript::summary "White plays Rxe4. The rook is lost."]
} -result {{White plays Rxe4. The rook is lost. ...} {White plays Rxe4. The rook is lost.}}

tcltest::test transcript-summary-words {a very long transcript is capped at the word count} -body {
	set text w1
	for {set i 2} {$i <= 45} {incr i} { append text " w$i" }
	set s [::ai::transcript::summary $text]
	list [string match "w1 w2* w40 ..." $s] [string match "*w41*" $s]
} -result {1 0}

tcltest::test transcript-summary-short {short and empty texts are passed back as they are} -body {
	list [::ai::transcript::summary "one two three"] [::ai::transcript::summary ""] \
		[::ai::transcript::summary "  \n \t "]
} -result {{one two three} {} {}}

::tcltest::cleanupTests
