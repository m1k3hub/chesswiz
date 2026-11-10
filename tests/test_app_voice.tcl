# ======================================================================
# Scidb App Test — voice assistant (tcl/app-voice.tcl)
# ======================================================================
# No microphone, no model and no speaker are needed: the pure helpers are
# tested on synthetic PCM, and the session flow is driven with a stubbed
# transcriber and a stubbed assistant.  Every test restores what it touched.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::voice {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app voice_[pid]]
	variable Asked {}
	variable Entry {}
	variable Spoken {}
	variable Answer 1
}

proc ::scidb::test::voice::isolated {body} {
	variable Dir

	set settings [array get ::application::voice::Settings]
	set priv [array get ::application::voice::Priv]
	set asked $::scidb::test::voice::Asked
	set entry $::scidb::test::voice::Entry
	set spoken $::scidb::test::voice::Spoken
	variable Asked {}
	variable Entry {}
	variable Spoken {}
	file mkdir $Dir

	# stub the assistant and the speaker so the flow can be observed
	catch { rename ::application::assistant::ask ::scidb::test::voice::realAsk }
	proc ::application::assistant::ask {request args} {
		lappend ::scidb::test::voice::Asked [list $request $args]
		return 1
	}
	catch { rename ::application::voice::Speak ::scidb::test::voice::realSpeak }
	proc ::application::voice::Speak {text} {
		lappend ::scidb::test::voice::Spoken $text
		return 1
	}
	catch { rename ::application::assistant::SetEntry ::scidb::test::voice::realSetEntry }
	proc ::application::assistant::SetEntry {text} {
		set ::scidb::test::voice::Entry $text
		return 1
	}
	# a real status label, so messages are observable
	if {![winfo exists .voicetest]} { toplevel .voicetest ; wm withdraw .voicetest }
	if {![winfo exists .voicetest.status]} { label .voicetest.status -text "" }
	if {![winfo exists .voicetest.button]} { button .voicetest.button -text "" }
	set ::application::voice::Priv(status) .voicetest.status
	set ::application::voice::Priv(button) .voicetest.button
	.voicetest.status configure -text ""

	set rc [catch { uplevel 1 $body } result]

	catch { rename ::application::assistant::ask {} }
	catch { rename ::scidb::test::voice::realAsk ::application::assistant::ask }
	catch { rename ::application::voice::Speak {} }
	catch { rename ::scidb::test::voice::realSpeak ::application::voice::Speak }
	catch { rename ::application::assistant::SetEntry {} }
	catch { rename ::scidb::test::voice::realSetEntry ::application::assistant::SetEntry }
	array set ::application::voice::Settings $settings
	array set ::application::voice::Priv $priv
	set ::scidb::test::voice::Asked $asked
	set ::scidb::test::voice::Entry $entry
	set ::scidb::test::voice::Spoken $spoken
	if {$rc} { return -code error $result }
	return $result
}

# A raw PCM file of <ms> milliseconds: <level> for the speech part.
proc ::scidb::test::voice::raw {file silenceBefore speech silenceAfter {level 3000}} {
	set samples {}
	set rate 16000
	for {set i 0} {$i < $rate * $silenceBefore / 1000} {incr i} { lappend samples 0 }
	for {set i 0} {$i < $rate * $speech / 1000} {incr i} { lappend samples $level }
	for {set i 0} {$i < $rate * $silenceAfter / 1000} {incr i} { lappend samples 0 }

	set fh [open $file wb]
	fconfigure $fh -translation binary
	puts -nonewline $fh [binary format s* $samples]
	close $fh
	return $file
}

proc ::scidb::test::voice::statusText {} {
	set w $::application::voice::Priv(status)
	if {[winfo exists $w]} { return [$w cget -text] }
	return ""
}


proc ::scidb::test::voice::wait {cond ms} {
	set n 0
	while {![uplevel #1 [list expr $cond]] && $n < $ms} { update ; after 10 ; incr n }
	return [uplevel #1 [list expr $cond]]
}

# ----------------------------------------------------------------------

tcltest::test voice-wav-roundtrip {raw PCM is wrapped in a readable WAV} -setup {
	file mkdir $::scidb::test::voice::Dir
} -body {
	set raw [::scidb::test::voice::raw [file join $::scidb::test::voice::Dir a.raw] 0 100 0]
	set wav [file join $::scidb::test::voice::Dir a.wav]
	set bytes [::application::voice::wavFromRaw $raw $wav 16000 1]
	list [expr {$bytes == 3200}] [::application::voice::wavInfo $wav] \
		[llength [::application::voice::samples $wav]]
} -cleanup {
	file delete -force $::scidb::test::voice::Dir
} -result {1 {16000 1 16 3200} 1600}

tcltest::test voice-windows-and-bounds {RMS windows find the speech in silence} -body {
	set samples {0 0 0 0 1000 1000 1000 1000 0 0}
	list [::application::voice::windowRms $samples 2] \
		[::application::voice::speechBounds $samples 2 500] \
		[::application::voice::speechBounds {0 0 0 0} 2 500]
} -result {{0.0 0.0 1000.0 1000.0 0.0} {4 7} {}}

tcltest::test voice-trim {silence is trimmed off both ends} -setup {
	file mkdir $::scidb::test::voice::Dir
} -body {
	set raw [::scidb::test::voice::raw [file join $::scidb::test::voice::Dir t.raw] 300 400 300]
	set trimmed [::application::voice::trim $raw [file join $::scidb::test::voice::Dir t.wav] 16000]
	list [dict get $trimmed ok] \
		[expr {abs([dict get $trimmed ms] - 400) <= 40}] \
		[llength [::application::voice::samples [file join $::scidb::test::voice::Dir t.wav]]]
} -cleanup {
	file delete -force $::scidb::test::voice::Dir
} -result {1 1 6400}

tcltest::test voice-trim-silence {an all-silent recording is refused} -setup {
	file mkdir $::scidb::test::voice::Dir
} -body {
	set raw [::scidb::test::voice::raw [file join $::scidb::test::voice::Dir s.raw] 200 0 200]
	set trimmed [::application::voice::trim $raw [file join $::scidb::test::voice::Dir s.wav] 16000]
	list [dict get $trimmed ok] [dict get $trimmed error]
} -cleanup {
	file delete -force $::scidb::test::voice::Dir
} -result {0 silence}

tcltest::test voice-trim-too-short {an utterance below the minimum is refused} -setup {
	file mkdir $::scidb::test::voice::Dir
} -body {
	set raw [::scidb::test::voice::raw [file join $::scidb::test::voice::Dir k.raw] 0 100 0]
	set trimmed [::application::voice::trim $raw [file join $::scidb::test::voice::Dir k.wav] 16000]
	list [dict get $trimmed ok] [string match {too short*} [dict get $trimmed error]]
} -cleanup {
	file delete -force $::scidb::test::voice::Dir
} -result {0 1}

tcltest::test voice-parse {transcripts are cleaned, artefacts dropped} -body {
	list [::application::voice::parseTranscript "  switch   to the  database  tab . "] \
		[::application::voice::parseTranscript "Thanks for watching!"] \
		[::application::voice::parseTranscript ""]
} -result {{switch to the database tab} {} {}}

tcltest::test voice-argv {recorder and transcriber commands are built, and templates substituted} -body {
	::scidb::test::voice::isolated {
		::application::voice::configure -recorder arecord -stt script -sttModel base.en -sttLanguage en
		set rec [::application::voice::recorderArgv /tmp/x.raw]
		set stt [::application::voice::sttArgv /tmp/x.wav]
		::application::voice::configure -stt "mytool --model %m --lang %l %f"
		set custom [::application::voice::sttArgv /tmp/x.wav]
		list \
			[expr {[lindex $rec 0] eq "arecord" && [lindex $rec end] eq "/tmp/x.raw"}] \
			[expr {"base.en" in $stt && "en" in $stt && [lindex $stt end] eq "/tmp/x.wav"}] \
			$custom
	}
} -result {1 1 {mytool --model base.en --lang en /tmp/x.wav}}

tcltest::test voice-status {the status describes what the machine can do} -body {
	::scidb::test::voice::isolated {
		set text [::application::voice::status]
		list [string match {*recorder*} $text] [string match {*speech to text*} $text] \
			[string match {*speech output*} $text]
	}
} -result {1 1 1}

tcltest::test voice-no-microphone {without a recorder the feature says so and does not start} -body {
	::scidb::test::voice::isolated {
		::application::voice::configure -recorder off
		set started [::application::voice::Start]
		list $started $::application::voice::Priv(recording) \
			[string match {*[Nn]o microphone*} [::scidb::test::voice::statusText]]
	}
} -result {0 0 1}

tcltest::test voice-flow {a recording is trimmed, transcribed and sent to the assistant} -constraints unix -setup {
	file mkdir $::scidb::test::voice::Dir
} -body {
	::scidb::test::voice::isolated {
		# a transcriber that just prints a sentence (the pluggable one-shot path)
		set fake [file join $::scidb::test::voice::Dir fake-stt.sh]
		set fh [open $fake w]
		puts $fh "#!/bin/sh"
		puts $fh "echo switch to the database tab"
		close $fh
		file attributes $fake -permissions 0755

		::application::voice::configure -recorder off -stt $fake -sttServer 0 -tts off -review 0
		set ::application::voice::Priv(raw) [::scidb::test::voice::raw \
			[file join $::scidb::test::voice::Dir f.raw] 200 500 200]
		set ::application::voice::Priv(wav) [file join $::scidb::test::voice::Dir f.wav]
		set ::application::voice::Priv(pid) {}
		::application::voice::Finish {}

		::scidb::test::voice::wait {[llength $::scidb::test::voice::Asked] > 0} 300
		lassign $::scidb::test::voice::Asked asked
		list [llength $::scidb::test::voice::Asked] [lindex $asked 0] [lindex $asked 1] \
			[string match {*Heard: switch to the database tab*} [::scidb::test::voice::statusText]]
	}
} -cleanup {
	file delete -force $::scidb::test::voice::Dir
} -result {1 {switch to the database tab} {-observer ::application::voice::OnAssistant} 1}

tcltest::test voice-review {review mode holds the transcript instead of sending it} -constraints unix -setup {
	file mkdir $::scidb::test::voice::Dir
} -body {
	::scidb::test::voice::isolated {
		set fake [file join $::scidb::test::voice::Dir fake-stt.sh]
		set fh [open $fake w]
		puts $fh "#!/bin/sh"
		puts $fh "echo prepare against Carlsen"
		close $fh
		file attributes $fake -permissions 0755

		::application::voice::configure -recorder off -stt $fake -sttServer 0 -tts off -review 1
		set ::application::voice::Priv(raw) [::scidb::test::voice::raw \
			[file join $::scidb::test::voice::Dir r.raw] 100 400 100]
		set ::application::voice::Priv(wav) [file join $::scidb::test::voice::Dir r.wav]
		set ::application::voice::Priv(pid) {}
		::application::voice::Finish {}

		::scidb::test::voice::wait {[string length $::scidb::test::voice::Entry] > 0} 300
		list $::scidb::test::voice::Entry [llength $::scidb::test::voice::Asked]
	}
} -cleanup {
	file delete -force $::scidb::test::voice::Dir
} -result {{prepare against Carlsen} 0}

tcltest::test voice-gate-holds {an implausible transcript is held for review} -body {
	::scidb::test::voice::isolated {
		::application::voice::OnGate "gibberish words" [dict create ok 1 label 0 confidence 0.9 source classifier]
		list $::scidb::test::voice::Entry [llength $::scidb::test::voice::Asked]
	}
} -result {{gibberish words} 0}

tcltest::test voice-gate-sends {a plausible transcript is sent} -body {
	::scidb::test::voice::isolated {
		::application::voice::OnGate "switch to the database tab" [dict create ok 1 label 1 confidence 0.9 source classifier]
		list $::scidb::test::voice::Entry [llength $::scidb::test::voice::Asked]
	}
} -result {{} 1}

tcltest::test voice-gate-undecided {an undecided gate sends as before} -body {
	::scidb::test::voice::isolated {
		::application::voice::OnGate "whatever" [dict create ok 0]
		list $::scidb::test::voice::Entry [llength $::scidb::test::voice::Asked]
	}
} -result {{} 1}

tcltest::test voice-tts-modes {replies are spoken only when they should be} -body {
	::scidb::test::voice::isolated {
		::application::voice::configure -ttsMode voice
		::application::voice::OnAssistant reply "a short answer"
		::application::voice::OnAssistant tool "ignored"
		::application::voice::configure -ttsMode off
		::application::voice::OnAssistant reply "not spoken"
		::application::voice::configure -ttsMode always
		::application::voice::OnAssistant reply "spoken again"
		set ::scidb::test::voice::Spoken
	}
} -result {{a short answer} {spoken again}}

# review finding UI-12: a speech command that never ends, or floods its
# output, is killed and fails once instead of leaving the voice busy
proc ::scidb::test::voice::runAsync {argv timeout} {
	set ::application::voice::RunTimeout $timeout
	set ::scidb::test::voice::ran {}
	::application::voice::RunAsync $argv {apply {{r} { lappend ::scidb::test::voice::ran $r }}}
	set id [after 5000 {lappend ::scidb::test::voice::ran gave-up}]
	vwait ::scidb::test::voice::ran
	after cancel $id
	# a late second completion would show up here
	after 300 {set ::scidb::test::voice::settled 1}
	vwait ::scidb::test::voice::settled
	set ::application::voice::RunTimeout 120000
	return $::scidb::test::voice::ran
}

proc ::scidb::test::voice::leftover {} {
	llength [array names ::application::voice::Priv {[ode][ure]*,*}]
}

tcltest::test voice-run-deadline {a command past its deadline is killed and fails once} -constraints unix -body {
	set t0 [clock milliseconds]
	set ran [::scidb::test::voice::runAsync {sh -c {exec sleep 30}} 300]
	list [llength $ran] [dict get [lindex $ran 0] ok] \
		[string match "*did not finish*" [dict get [lindex $ran 0] error]] \
		[expr {[clock milliseconds] - $t0 < 3000}] [::scidb::test::voice::leftover]
} -result {1 0 1 1 0}

tcltest::test voice-run-output-cap {a command that floods its output is stopped} -constraints unix -body {
	set ran [::scidb::test::voice::runAsync {sh -c {exec yes transcript}} 10000]
	list [llength $ran] [dict get [lindex $ran 0] ok] \
		[string match "*more than*" [dict get [lindex $ran 0] error]] [::scidb::test::voice::leftover]
} -result {1 0 1 0}

tcltest::test voice-run-ok {a normal command still completes with its output} -constraints unix -body {
	set ran [::scidb::test::voice::runAsync {sh -c {echo hello; echo noise >&2}} 10000]
	list $ran [::scidb::test::voice::leftover]
} -result {{{ok 1 text hello}} 0}

# review finding UI-10: Piper synthesises in the background, and the reply
# plays once it is done
tcltest::test voice-piper-async {Speak returns before Piper is done; the reply plays after} -constraints unix -setup {
	set dir [file join $::env(HOME) fake-piper]
	file mkdir $dir
	set f [open [file join $dir piper] w]
	puts $f {#!/bin/sh
out=""
while [ $# -gt 0 ]; do [ "$1" = --output_file ] && out=$2; shift; done
sleep 1
cat > "$out"}
	close $f
	file attributes [file join $dir piper] -permissions 0755
	set ::scidb::test::voice::path $::env(PATH)
	set ::env(PATH) $dir:$::env(PATH)
	rename ::application::voice::ttsEngine ::scidb::test::voice::realTtsEngine
	proc ::application::voice::ttsEngine {} { return piper }
	rename ::application::voice::Play ::scidb::test::voice::realPlay
	proc ::application::voice::Play {wav} {
		set f [open $wav]; set ::scidb::test::voice::played [string trim [read $f]]; close $f
		return 1
	}
	set ::scidb::test::voice::mode $::application::voice::Settings(ttsMode)
	set ::application::voice::Settings(ttsMode) always
	set ::scidb::test::voice::played {}
} -body {
	set t0 [clock milliseconds]
	set ok [::application::voice::Speak "a long reply"]
	set took [expr {[clock milliseconds] - $t0}]
	set id [after 8000 {set ::scidb::test::voice::played timeout}]
	vwait ::scidb::test::voice::played
	after cancel $id
	list $ok [expr {$took < 500}] $::scidb::test::voice::played
} -cleanup {
	set ::env(PATH) $::scidb::test::voice::path
	rename ::application::voice::ttsEngine {}
	rename ::scidb::test::voice::realTtsEngine ::application::voice::ttsEngine
	rename ::application::voice::Play {}
	rename ::scidb::test::voice::realPlay ::application::voice::Play
	set ::application::voice::Settings(ttsMode) $::scidb::test::voice::mode
	file delete -force [file join $::env(HOME) fake-piper]
} -result {1 1 {a long reply}}

tcltest::cleanupTests