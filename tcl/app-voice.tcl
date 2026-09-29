# ======================================================================
# ::application::voice -- speak to the assistant, hear the answer.
#
# Push to talk: the microphone button in the assistant pane (or Extras >
# "AI: Voice Assistant", or the configured shortcut) records until you
# stop speaking, transcribes locally, and sends the text through the
# ordinary ::application::assistant::ask.  Nothing about the text path
# changes: routing, tools, the grounded analysis loop and -- most
# importantly -- the confirmation gate for anything that changes
# something are inherited as they are.  Voice adds a microphone, not
# authority.
#
#   record   raw PCM from the first recorder found (ffmpeg, arecord, rec),
#            or from a command template you set.  Raw, not WAV, so the
#            growing file can be watched and the header written by us at
#            the end (::application::voice::wavFromRaw) -- a recorder
#            killed mid-write never leaves an unreadable file.
#   trim     silence at both ends is removed (RMS per 20 ms window); an
#            utterance that is all silence is reported as "nothing heard".
#   STT      any command that prints the transcript on stdout.  The
#            shipped engine is scripts/stt-transcribe.py (faster-whisper,
#            local).  With sttServer on, that script is kept running and
#            fed one path per line: loading the model costs ~2 s, so a
#            persistent process is what makes a spoken command feel
#            instant.
#   TTS      piper (with a voice model) if present, else espeak-ng.  By
#            default only replies to *spoken* requests are spoken aloud
#            (ttsMode voice), so typing does not make the machine talk.
#
# Recognition is imperfect -- proper nouns especially ("Nepomniachtchi"
# came back as "Nepomniage" in testing).  That is why the transcript is
# always shown in the pane, why review mode can hold it in the entry for
# editing, and why the confirm gate shows the *resolved* action before
# anything runs.  A misheard sentence can therefore ask for the wrong
# read-only thing; it cannot quietly do the wrong thing.
#
# Everything is local: the audio never leaves the machine, and after the
# model has been downloaded once, neither does anything else.
#
#   ::application::voice::toggle            push to talk (start/stop)
#   ::application::voice::status            human-readable state, for the
#                                           assistant tool voice_status
#   ::application::voice::configure -tts off ...
#
# Environment (all optional; the dialog's settings are saved in the
# options file and overridden by these for one session):
#   SCIDB_AI_STT=auto|off|<command>   SCIDB_AI_STT_MODEL=small.en
#   SCIDB_AI_STT_DEVICE=cpu|cuda      SCIDB_AI_STT_SERVER=0|1
#   SCIDB_AI_STT_LANGUAGE=en
#   SCIDB_AI_RECORDER=auto|off|<command>
#   SCIDB_AI_TTS=auto|off|piper|espeak-ng   SCIDB_AI_TTS_VOICE=<name|.onnx>
#   SCIDB_AI_TTS_MODE=voice|always|off      SCIDB_AI_VOICE_REVIEW=0|1
#   SCIDB_AI_VOICE_MAX_SECONDS=30           SCIDB_AI_VOICE_SILENCE_MS=900
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-voice
}

package require Tcl 8.5
package require Tk 8.5

namespace eval application {
namespace eval voice {
namespace eval mc {

set Speak			"Speak"
set Stop			"Stop"
set Listening		"Listening... click to stop"
set Transcribing	"Transcribing..."
set CheckTranscript "Heard: %s (not sure this is a request - check and press Enter)"
set Heard			"Heard: %s"
set Nothing			"Nothing heard (no speech above the noise floor)"
set NoMic			"No microphone found: install ffmpeg, arecord or sox, or set SCIDB_AI_RECORDER"
set NoStt			"No speech-to-text engine: pip install faster-whisper (SCIDB_AI_STT)"
set Failed			"Voice failed: %s"
set Speaking		"Speaking..."
set Title			"AI: &Voice Assistant (Push to Talk)"

} ;# namespace mc

# Settings.  <recorder>/<stt>/<tts> are "auto" (discover), "off", or a
# command template; "auto" never names a model or a program in logic.
variable Settings
array set Settings {
	recorder     auto
	stt          auto
	sttModel     small.en
	sttDevice    cpu
	sttServer    1
	sttLanguage  en
	tts          auto
	ttsVoice     ""
	ttsMode      voice
	review       0
	gate         1
	gateThreshold 0.5
	maxSeconds   30
	silenceMs    900
}

variable Rate 16000      ;# Hz, mono, signed 16 bit little-endian
variable WindowMs 20     ;# RMS window
variable SilenceRms 260  ;# below this counts as silence (16-bit RMS)
variable MinSpeechMs 300 ;# shorter utterances are refused

variable Priv
array set Priv {
	recording	0
	pid			{}
	raw			{}
	wav			{}
	pollId	{}
	maxId		{}
	button	{}
	status	{}
	busy		0
	serverChan	{}
	serverPid	{}
	serverBusy	0
	asyncCount	0
	engines		{}
	enginesProbed 0
}

if {[info exists ::env(SCIDB_AI_STT)]}          { set Settings(stt)        $::env(SCIDB_AI_STT) }
if {[info exists ::env(SCIDB_AI_STT_MODEL)]}    { set Settings(sttModel)   $::env(SCIDB_AI_STT_MODEL) }
if {[info exists ::env(SCIDB_AI_STT_DEVICE)]}   { set Settings(sttDevice)  $::env(SCIDB_AI_STT_DEVICE) }
if {[info exists ::env(SCIDB_AI_STT_SERVER)]}   { set Settings(sttServer)  $::env(SCIDB_AI_STT_SERVER) }
if {[info exists ::env(SCIDB_AI_STT_LANGUAGE)]} { set Settings(sttLanguage) $::env(SCIDB_AI_STT_LANGUAGE) }
if {[info exists ::env(SCIDB_AI_RECORDER)]}     { set Settings(recorder)   $::env(SCIDB_AI_RECORDER) }
if {[info exists ::env(SCIDB_AI_TTS)]}          { set Settings(tts)        $::env(SCIDB_AI_TTS) }
if {[info exists ::env(SCIDB_AI_TTS_VOICE)]}    { set Settings(ttsVoice)   $::env(SCIDB_AI_TTS_VOICE) }
if {[info exists ::env(SCIDB_AI_TTS_MODE)]}     { set Settings(ttsMode)    $::env(SCIDB_AI_TTS_MODE) }
if {[info exists ::env(SCIDB_AI_VOICE_REVIEW)]} { set Settings(review)     $::env(SCIDB_AI_VOICE_REVIEW) }
if {[info exists ::env(SCIDB_AI_VOICE_GATE)]}   { set Settings(gate)       $::env(SCIDB_AI_VOICE_GATE) }
if {[info exists ::env(SCIDB_AI_VOICE_GATE_MIN_CONFIDENCE)]} { set Settings(gateThreshold) $::env(SCIDB_AI_VOICE_GATE_MIN_CONFIDENCE) }
if {[info exists ::env(SCIDB_AI_VOICE_MAX_SECONDS)]} { set Settings(maxSeconds) $::env(SCIDB_AI_VOICE_MAX_SECONDS) }
if {[info exists ::env(SCIDB_AI_VOICE_SILENCE_MS)]}  { set Settings(silenceMs)  $::env(SCIDB_AI_VOICE_SILENCE_MS) }

} ;# namespace voice
} ;# namespace application


proc ::application::voice::configure {args} {
	variable Settings

	foreach {key value} $args {
		set key [string trimleft $key -]
		if {![info exists Settings($key)]} { error "unknown voice setting '$key'" }
		set Settings($key) $value
	}
	return
}


proc ::application::voice::setting {key} {
	variable Settings
	return $Settings($key)
}


proc ::application::voice::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Settings
}
if {[llength [info commands ::options::hookWriter]]} {
	::options::hookWriter ::application::voice::WriteOptions
}


# ======================================================================
# Discovery: what this machine can actually do.  Cached; probed lazily so
# startup never waits for a python import.
# ======================================================================
proc ::application::voice::engines {} {
	variable Priv

	if {$Priv(enginesProbed)} { return $Priv(engines) }

	set found [dict create]
	foreach tool {ffmpeg arecord rec sox} {
		if {[llength [auto_execok $tool]]} { dict set found $tool 1 }
	}
	foreach tool {piper espeak-ng spd-say} {
		if {[llength [auto_execok $tool]]} { dict set found $tool 1 }
	}
	foreach tool {paplay aplay ffplay} {
		if {[llength [auto_execok $tool]]} { dict set found $tool 1 }
	}
	dict set found faster-whisper [expr {[llength [fasterWhisperPython]] ? 1 : 0}]

	set Priv(engines) $found
	set Priv(enginesProbed) 1
	return $found
}


# The python interpreter that can import faster_whisper, or {}.
proc ::application::voice::fasterWhisperPython {} {
	foreach py {python3 python} {
		if {![llength [auto_execok $py]]} { continue }
		if {![catch { exec $py -c "import faster_whisper" 2>/dev/null }]} { return $py }
	}
	return {}
}


proc ::application::voice::recorder {} {
	variable Settings

	if {$Settings(recorder) eq "off"} { return {} }
	if {$Settings(recorder) ne "auto"} { return $Settings(recorder) }

	set have [engines]
	foreach tool {ffmpeg arecord rec} {
		if {[dict exists $have $tool] && [dict get $have $tool]} { return $tool }
	}
	return {}
}


# The recorder argv for <file> (raw PCM), or {} when there is none.
proc ::application::voice::recorderArgv {file} {
	variable Rate

	set engine [recorder]
	if {$engine eq ""} { return {} }
	switch -- $engine {
		ffmpeg {
			return [list ffmpeg -loglevel quiet -nostdin -f pulse -i default \
				-ac 1 -ar $Rate -f s16le -y $file]
		}
		arecord {
			return [list arecord -q -f S16_LE -r $Rate -c 1 -t raw $file]
		}
		rec - sox {
			return [list rec -q -r $Rate -c 1 -b 16 -e signed -t raw $file]
		}
		default {
			# a command template: %f is the output file
			return [SplitTemplate $engine $file]
		}
	}
}


proc ::application::voice::SplitTemplate {template args} {
	set argv {}
	foreach word $template {
		set word [string map [list %f [lindex $args 0] %m [lindex $args 1] \
			%l [lindex $args 2] %t [lindex $args 3]] $word]
		lappend argv $word
	}
	return $argv
}


# The speech-to-text engine: "auto", "off", our transcriber script, or a
# command template.
proc ::application::voice::sttEngine {} {
	variable Settings

	if {$Settings(stt) eq "off"} { return {} }
	if {$Settings(stt) ne "auto"} { return $Settings(stt) }

	if {[llength [fasterWhisperPython]] && [file exists [sttScript]]} { return script }
	return {}
}


proc ::application::voice::sttScript {} {
	set candidates {}
	if {[info exists ::scidb::dir::share]} {
		lappend candidates [file join $::scidb::dir::share scripts stt-transcribe.py]
	}
	# the build tree: this file's directory is <root>/tcl, the bundle is in it
	lappend candidates \
		[file join [file dirname [file dirname [file normalize [info script]]]] scripts stt-transcribe.py]
	if {[info exists ::nameofexecutable]} {
		lappend candidates [file join [file dirname $::nameofexecutable] stt-transcribe.py]
	}
	foreach candidate $candidates {
		if {[file exists $candidate]} { return $candidate }
	}
	return [lindex $candidates 0]
}


# The one-shot argv for transcribing <file>.
proc ::application::voice::sttArgv {file} {
	variable Settings

	set engine [sttEngine]
	if {$engine eq ""} { return {} }
	if {$engine eq "script"} {
		set python [fasterWhisperPython]
		set argv [list $python [sttScript] --model $Settings(sttModel) --device $Settings(sttDevice)]
		if {[string length $Settings(sttLanguage)]} {
			lappend argv --language $Settings(sttLanguage)
		}
		lappend argv $file
		return $argv
	}
	# a command template: %f file, %m model, %l language
	return [SplitTemplate $engine $file $Settings(sttModel) $Settings(sttLanguage)]
}


# The argv that keeps the model loaded (our transcriber only).
proc ::application::voice::sttServerArgv {} {
	variable Settings

	set python [fasterWhisperPython]
	set argv [list $python [sttScript] --serve --model $Settings(sttModel) --device $Settings(sttDevice)]
	if {[string length $Settings(sttLanguage)]} { lappend argv --language $Settings(sttLanguage) }
	return $argv
}


proc ::application::voice::ttsEngine {} {
	variable Settings

	if {$Settings(tts) eq "off"} { return {} }
	if {$Settings(tts) ne "auto"} { return $Settings(tts) }

	set have [engines]
	if {[dict exists $have piper] && [dict get $have piper] && [string length $Settings(ttsVoice)]} {
		return piper
	}
	if {[dict exists $have espeak-ng] && [dict get $have espeak-ng]} { return espeak-ng }
	return {}
}


proc ::application::voice::player {} {
	set have [engines]
	foreach tool {paplay aplay ffplay} {
		if {[dict exists $have $tool] && [dict get $have $tool]} { return $tool }
	}
	return {}
}


# ======================================================================
# Pure helpers (no UI, no processes) -- unit-tested in
# tests/test_app_voice.tcl.
# ======================================================================

# The 44-byte canonical WAV header for <dataLen> bytes of PCM.
proc ::application::voice::wavHeader {dataLen rate channels {bits 16}} {
	set byteRate  [expr {$rate * $channels * $bits / 8}]
	set blockAlign [expr {$channels * $bits / 8}]

	return [binary format a4ia4a4issiissa4i \
		"RIFF" [expr {36 + $dataLen}] "WAVE" \
		"fmt " 16 1 $channels $rate $byteRate $blockAlign $bits \
		"data" $dataLen]
}


# Wrap raw PCM into a WAV. Returns the number of PCM bytes written.
proc ::application::voice::wavFromRaw {rawFile wavFile {rate 16000} {channels 1}} {
	set in [open $rawFile rb]
	fconfigure $in -translation binary
	set pcm [read $in]
	close $in

	set out [open $wavFile wb]
	fconfigure $out -translation binary
	puts -nonewline $out [wavHeader [string length $pcm] $rate $channels]
	puts -nonewline $out $pcm
	close $out
	return [string length $pcm]
}


# The mono/stereo rate of a WAV file as {rate channels bits dataBytes}.
proc ::application::voice::wavInfo {file} {
	set in [open $file rb]
	fconfigure $in -translation binary
	set head [read $in 44]
	close $in
	if {[string length $head] < 44 || [string range $head 0 3] ne "RIFF"} {
		error "not a WAV file: $file"
	}
	binary scan $head a4ia4a4issiissa4i \
		_ _ _ _ _ _ channels rate byteRate blockAlign bits _ dataLen
	return [list $rate $channels $bits $dataLen]
}


# Signed 16-bit samples from a WAV's data chunk.
proc ::application::voice::samples {file} {
	set in [open $file rb]
	fconfigure $in -translation binary
	seek $in 44
	set pcm [read $in]
	close $in
	if {[binary scan $pcm s* samples] != 1} { return {} }
	return $samples
}


# RMS of a sample list (0 when empty).
proc ::application::voice::rms {samples} {
	if {![llength $samples]} { return 0 }
	set sum 0.0
	foreach s $samples { set sum [expr {$sum + double($s) * double($s)}] }
	return [expr {sqrt($sum / [llength $samples])}]
}


# RMS of every window of <windowMs> milliseconds.
proc ::application::voice::windowRms {samples {window 320}} {
	set out {}
	for {set i 0} {$i < [llength $samples]} {incr i $window} {
		lappend out [rms [lrange $samples $i [expr {$i + $window - 1}]]]
	}
	return $out
}


# {start end} sample indices of the first and last window above
# <threshold>, or {} when the whole clip is silence.
proc ::application::voice::speechBounds {samples {window 320} {threshold 260}} {
	set windows [windowRms $samples $window]
	set first -1
	set last -1
	set n 0
	foreach value $windows {
		if {$value >= $threshold} {
			if {$first < 0} { set first $n }
			set last $n
		}
		incr n
	}
	if {$first < 0} { return {} }
	return [list [expr {$first * $window}] \
		[expr {[llength $samples] - 1 < ($last + 1) * $window ? [llength $samples] - 1 : ($last + 1) * $window - 1}]]
}


# Trim silence from both ends of a raw recording into <outWav>.  Returns
# {ok 1 ms N} or {ok 0 error "..."} -- the caller decides what to say.
proc ::application::voice::trim {rawFile outWav rate} {
	variable SilenceRms
	variable WindowMs
	variable MinSpeechMs

	if {[catch { wavFromRaw $rawFile $outWav $rate } bytes]} {
		return [list ok 0 error $bytes]
	}
	if {$bytes < 2} {
		return [list ok 0 error "the recording was empty"]
	}
	set samples [samples $outWav]
	set window [expr {$rate * $WindowMs / 1000}]
	set bounds [speechBounds $samples $window $SilenceRms]

	if {![llength $bounds]} {
		return [list ok 0 error "silence"]
	}
	lassign $bounds first last
	set ms [expr {($last - $first + 1) * 1000 / $rate}]
	if {$ms < $MinSpeechMs} {
		return [list ok 0 error "too short ($ms ms)"]
	}

	# rewrite the WAV with only the speech
	set pcm [binary format s* [lrange $samples $first $last]]
	set out [open $outWav wb]
	fconfigure $out -translation binary
	puts -nonewline $out [wavHeader [string length $pcm] $rate 1]
	puts -nonewline $out $pcm
	close $out
	return [list ok 1 ms $ms bytes [string length $pcm]]
}


# The transcript, cleaned for the assistant: single spaces, no stray
# punctuation-only output.  Returns "" when nothing was understood.
proc ::application::voice::parseTranscript {text} {
	regsub -all {\s+} [string trim $text] { } text
	regsub -all {^[\s\.,!?]+|[\s\.,!?]+$} $text {} text
	# Whisper's artefacts on silence
	if {[string match {*[Aa]mara*} $text] || [string match {*[Tt]hanks for watching*} $text]} { return "" }
	return $text
}


# ======================================================================
# Session
# ======================================================================
proc ::application::voice::attach {button status} {
	variable Priv
	set Priv(button) $button
	set Priv(status) $status
	Refresh
	return
}


proc ::application::voice::Refresh {} {
	variable Priv
	variable mc

	if {[winfo exists $Priv(button)]} {
		$Priv(button) configure -text [expr {$Priv(recording) ? $mc::Stop : $mc::Speak}]
	}
	if {[winfo exists $Priv(status)]} {
		# the assistant pane's status line is shared; only speak when idle
		if {$Priv(recording)} { $Priv(status) configure -text $mc::Listening }
	}
	return
}


# Push to talk.
proc ::application::voice::toggle {} {
	variable Priv

	if {$Priv(recording)} { Stop ; return }
	Start
	return
}


proc ::application::voice::Start {} {
	variable Priv
	variable Settings
	variable mc

	if {$Priv(recording) || $Priv(busy)} { return 0 }

	if {[recorder] eq ""} {
		Message $mc::NoMic
		return 0
	}
	if {[sttEngine] eq ""} {
		Message $mc::NoStt
		return 0
	}

	set dir [file join [TempDir]]
	file mkdir $dir
	set Priv(raw) [file join $dir utterance.raw]
	set Priv(wav) [file join $dir utterance.wav]
	catch { file delete -force $Priv(raw) $Priv(wav) }

	set argv [recorderArgv $Priv(raw)]
	set null [expr {$::tcl_platform(platform) eq "windows" ? "NUL" : "/dev/null"}]
	if {[catch { set Priv(pid) [exec {*}$argv < $null > $null 2> $null &] } err]} {
		Message [format $mc::Failed $err]
		set Priv(pid) {}
		return 0
	}

	set Priv(recording) 1
	Message $mc::Listening
	Refresh
	# watch the tail for silence, and never record longer than maxSeconds
	set Priv(pollId) [after 300 [namespace code Poll]]
	set Priv(maxId) [after [expr {$Settings(maxSeconds) * 1000}] [namespace code Stop]]
	return 1
}


# Called every 300 ms while recording: stop when the tail has been quiet
# for Settings(silenceMs) -- the user simply stops talking.
proc ::application::voice::Poll {} {
	variable Priv
	variable Settings
	variable Rate
	variable WindowMs
	variable SilenceRms

	if {!$Priv(recording)} { return }

	set quietMs 0
	if {![catch { set size [file size $Priv(raw)] }]} {
		set quietMs [expr {$size * 1000 / (2 * $Rate)}] ;# only used to bound
		# read the last silenceMs + one window of audio
		set want [expr {2 * ($Settings(silenceMs) + $WindowMs) * $Rate / 1000}]
		set offset [expr {$size > $want ? $size - $want : 0}]
		set in [open $Priv(raw) rb]
		fconfigure $in -translation binary
		seek $in $offset
		set pcm [read $in]
		close $in
		if {[binary scan $pcm s* samples] == 1} {
			set window [expr {$Rate * $WindowMs / 1000}]
			set windows [windowRms $samples $window]
			# count trailing windows below the floor
			set trailing 0
			foreach value [lreverse $windows] {
				if {$value >= $SilenceRms} { break }
				incr trailing
			}
			set quietMs [expr {$trailing * $WindowMs}]
		}
	}

	if {$quietMs >= $Settings(silenceMs)} { Stop ; return }
	set Priv(pollId) [after 300 [namespace code Poll]]
	return
}


proc ::application::voice::Stop {} {
	variable Priv
	variable mc

	if {!$Priv(recording)} { return 0 }
	set Priv(recording) 0
	catch { after cancel $Priv(pollId) }
	catch { after cancel $Priv(maxId) }
	set Priv(pollId) {}
	set Priv(maxId) {}

	if {[string length $Priv(pid)]} {
		# ask politely, so the recorder flushes what it has
		catch { exec kill -INT $Priv(pid) }
		after 400 [namespace code [list Finish $Priv(pid)]]
	} else {
		Finish {}
	}
	return 1
}


proc ::application::voice::Finish {pid} {
	variable Priv
	variable Settings
	variable mc
	variable Rate

	# wait for the recorder to be gone (at most ~1.5 s)
	if {[string length $pid]} {
		set waited 0
		while {![catch { exec kill -0 $pid }] && $waited < 15} {
			after 100
			update
			incr waited
		}
	}
	set Priv(pid) {}

	if {![file exists $Priv(raw)]} {
		Message [format $mc::Failed "the recorder wrote nothing"]
		return
	}

	set trimmed [trim $Priv(raw) $Priv(wav) $Rate]
	if {![dict get $trimmed ok]} {
		if {[dict get $trimmed error] eq "silence"} {
			Message $mc::Nothing
		} else {
			Message [format $mc::Failed [dict get $trimmed error]]
		}
		return
	}

	set Priv(busy) 1
	Message $mc::Transcribing
	Transcribe $Priv(wav) [namespace code [list OnTranscript]]
	return
}


proc ::application::voice::OnTranscript {result} {
	variable Priv
	variable mc

	set Priv(busy) 0
	if {![dict get $result ok]} {
		Message [format $mc::Failed [dict get $result error]]
		return
	}

	set text [parseTranscript [dict get $result text]]
	if {![string length $text]} {
		Message $mc::Nothing
		return
	}
	Message [format $mc::Heard $text]

	# voice mode: the reply to a spoken request is spoken back
	if {[llength [info commands ::application::assistant::ask]] == 0} { return }

	if {[setting review]} {
		# hold the transcript in the entry so it can be corrected first
		if {[llength [info commands ::application::assistant::SetEntry]]} {
			::application::assistant::SetEntry $text
		}
		return
	}
	Gate $text
	return
}


# A8: a last check on the transcript before it becomes an assistant request.
# The classifier is a bounded noul ("is this a plausible request?"); with no
# classifier, or when it is unsure, the transcript is sent as before.  An
# implausible transcript is held in the entry for the user to correct.
proc ::application::voice::Gate {text} {
	if {[setting gate] && [llength [info commands ::ai::decide]]} {
		set question [dict create type noul \
			instructions "Is this a plausible request to Scidb, a chess database assistant? Answer yes when it is something the assistant could act on (search, explain, open, annotate, ...), no when the words look scrambled or unrelated."]
		if {![catch {
			::ai::decide voice_gate $text $question \
				[namespace code [list OnGate $text]] \
				-threshold [setting gateThreshold] \
				-fallback [namespace code Plausible]
		}]} { return }
	}
	Send $text
	return
}


proc ::application::voice::Plausible {} {
	return 1
}


proc ::application::voice::OnGate {text decision} {
	variable mc

	if {[dict get $decision ok] && ![dict get $decision label]} {
		Message [format $mc::CheckTranscript $text]
		if {[llength [info commands ::application::assistant::SetEntry]]} {
			::application::assistant::SetEntry $text
		}
		return
	}
	Send $text
	return
}


proc ::application::voice::Send {text} {
	::application::assistant::ask $text -observer ::application::voice::OnAssistant
	return
}


proc ::application::voice::OnAssistant {args} {
	variable Settings

	if {$Settings(ttsMode) eq "off"} { return }
	if {[lindex $args 0] ne "reply"} { return }
	Speak [lindex $args 1]
	return
}


proc ::application::voice::Message {text} {
	variable Priv

	if {[winfo exists $Priv(status)]} {
		$Priv(status) configure -text $text
	}
	return
}


proc ::application::voice::TempDir {} {
	if {[info exists ::scidb::dir::temp]} { return $::scidb::dir::temp }
	return [file join /tmp scidb-voice-[pid]]
}


# ======================================================================
# Running commands asynchronously: the interface never waits for a
# transcription or a recorder.
# ======================================================================

# <script> is called with {ok 1 text OUTPUT} or {ok 0 error MESSAGE}.
proc ::application::voice::RunAsync {argv script} {
	variable Priv

	set dir [TempDir]
	file mkdir $dir
	set errFile [file join $dir voice-cmd-[incr Priv(asyncCount)].err]
	if {[catch { set chan [open "|[list {*}$argv] 2>$errFile" r] } err]} {
		after 0 [list {*}$script [list ok 0 error $err]]
		return
	}
	fconfigure $chan -blocking 0 -buffering none
	set Priv(out,$chan) ""
	set Priv(err,$chan) $errFile
	fileevent $chan readable [namespace code [list OnReadable $chan $script]]
	return
}


proc ::application::voice::OnReadable {chan script} {
	variable Priv

	if {[eof $chan]} {
		fileevent $chan readable {}
		set out [expr {[info exists Priv(out,$chan)] ? $Priv(out,$chan) : ""}]
		unset -nocomplain Priv(out,$chan)
		set out [string trim $out]
		set failed [catch { close $chan } err]
		if {$failed} {
			set detail $err
			if {[info exists Priv(err,$chan)] && [file readable $Priv(err,$chan)]} {
				set fh [open $Priv(err,$chan) r]
				set said [string trim [read $fh]]
				close $fh
				if {[string length $said]} { set detail $said }
			}
			unset -nocomplain Priv(err,$chan)
			after 0 [list {*}$script [list ok 0 error [string trim $detail]]]
		} else {
			after 0 [list {*}$script [list ok 1 text $out]]
		}
		return
	}
	append Priv(out,$chan) [read $chan]
	return
}


# ======================================================================
# Speech to text
# ======================================================================
proc ::application::voice::Transcribe {file script} {
	variable Settings
	variable Priv

	set engine [sttEngine]
	if {$engine eq ""} {
		after 0 [list {*}$script [list ok 0 error "no speech-to-text engine"]]
		return
	}

	if {$Settings(sttServer) && $engine eq "script"} {
		if {[ServerTranscribe $file $script]} { return }
	}
	# one-shot: any engine that prints the transcript
	set argv [sttArgv $file]
	if {![llength $argv]} {
		after 0 [list {*}$script [list ok 0 error "no speech-to-text command"]]
		return
	}
	RunAsync $argv $script
	return
}


# The persistent transcriber: the model stays loaded between utterances.
# Returns 0 when the caller should fall back to a one-shot run.
proc ::application::voice::ServerTranscribe {file script} {
	variable Priv

	if {$Priv(serverBusy)} { return 0 }
	if {![ServerStart]} { return 0 }

	set Priv(serverScript) $script
	set Priv(serverBusy) 1
	set Priv(serverDeadline) [after 60000 [namespace code [list ServerTimeout $file $script]]]

	if {[catch { puts $Priv(serverChan) $file ; flush $Priv(serverChan) } err]} {
		ServerStop
		return 0
	}
	return 1
}


proc ::application::voice::ServerAlive {} {
	variable Priv

	if {![string length $Priv(serverChan)]} { return 0 }
	if {[catch { eof $Priv(serverChan) } eof]} { return 0 }
	return [expr {!$eof}]
}


proc ::application::voice::ServerStart {} {
	variable Priv

	if {[ServerAlive]} { return 1 }
	ServerStop
	if {[catch { set chan [open "|[list {*}[sttServerArgv]]" r+] } err]} { return 0 }
	fconfigure $chan -blocking 0 -buffering line
	set Priv(serverChan) $chan
	set Priv(serverOut) ""
	fileevent $chan readable [namespace code ServerReadable]
	return 1
}


proc ::application::voice::ServerReadable {} {
	variable Priv

	set chan $Priv(serverChan)
	if {![string length $chan]} { return }

	if {[eof $chan]} {
		# the transcriber died: report to whoever is waiting, then forget it
		ServerStop
		ServerDeliver [list ok 0 error "the speech-to-text process stopped"]
		return
	}
	append Priv(serverOut) [read $chan]
	while {[string first "\n" $Priv(serverOut)] >= 0} {
		set line [string range $Priv(serverOut) 0 [expr {[string first "\n" $Priv(serverOut)] - 1}]]
		set Priv(serverOut) [string range $Priv(serverOut) [expr {[string first "\n" $Priv(serverOut)] + 1}] end]
		if {[string length [string trim $line]] || [string length $Priv(serverScript)]} {
			ServerDeliver [list ok 1 text $line]
			return
		}
	}
	return
}


proc ::application::voice::ServerDeliver {result} {
	variable Priv

	if {[string length $Priv(serverDeadline)]} {
		catch { after cancel $Priv(serverDeadline) }
		set Priv(serverDeadline) {}
	}
	set Priv(serverBusy) 0
	set script $Priv(serverScript)
	set Priv(serverScript) {}
	set Priv(serverOut) ""
	if {[llength $script]} { {*}$script $result }
	return
}


proc ::application::voice::ServerTimeout {file script} {
	variable Priv

	# the model is loaded on first use, so a cold start can take a while;
	# if it never answers, kill it and let the one-shot path try
	ServerStop
	set argv [sttArgv $file]
	if {[llength $argv]} {
		RunAsync $argv $script
	} else {
		{*}$script [list ok 0 error "transcription timed out"]
	}
	return
}


proc ::application::voice::ServerStop {} {
	variable Priv

	set Priv(serverBusy) 0
	set Priv(serverScript) {}
	set Priv(serverOut) ""
	if {[string length $Priv(serverChan)]} {
		catch { fileevent $Priv(serverChan) readable {} }
		catch { close $Priv(serverChan) }
		set Priv(serverChan) {}
	}
	catch { after cancel $Priv(serverDeadline) }
	set Priv(serverDeadline) {}
	return
}


# ======================================================================
# Text to speech (optional)
# ======================================================================
proc ::application::voice::Speak {text} {
	variable Settings
	variable mc

	set text [string trim $text]
	if {![string length $text]} { return 0 }
	if {$Settings(ttsMode) eq "off"} { return 0 }

	set engine [ttsEngine]
	if {$engine eq ""} { return 0 }

	set dir [TempDir]
	file mkdir $dir
	set wav [file join $dir speech.wav]

	switch -- $engine {
		piper {
			if {[catch {
				set chan [open "|piper --model $Settings(ttsVoice) --output_file $wav" w]
				fconfigure $chan -encoding utf-8
				puts $chan $text
				close $chan
			} err]} {
				return 0
			}
		}
		espeak-ng {
			if {[catch { exec espeak-ng -w $wav -s 165 $text } err]} { return 0 }
		}
		default {
			# a template: %t is the text
			set argv [SplitTemplate $engine $text]
			if {[catch { exec {*}$argv } err]} { return 0 }
			return 1
		}
	}

	Play $wav
	Message $mc::Speaking
	return 1
}


proc ::application::voice::Play {wav} {
	set player [player]
	if {$player eq ""} { return 0 }
	set null [expr {$::tcl_platform(platform) eq "windows" ? "NUL" : "/dev/null"}]
	switch -- $player {
		paplay { set argv [list paplay $wav] }
		aplay  { set argv [list aplay -q $wav] }
		default { set argv [list ffplay -nodisp -autoexit -loglevel quiet $wav] }
	}
	catch { exec {*}$argv < $null > $null 2> $null & }
	return 1
}


# ======================================================================
# Status, for the assistant tool voice_status and the dialog.
# ======================================================================
proc ::application::voice::status {} {
	variable Settings
	variable Priv

	set have [engines]
	set out {}
	lappend out "voice assistant: [expr {$Priv(recording) ? "recording" : ($Priv(busy) ? "transcribing" : "idle")}]"

	set rec [recorder]
	lappend out "recorder: [expr {$rec ne "" ? $rec : "none found (install ffmpeg/arecord/sox)"}]"

	set stt [sttEngine]
	if {$stt eq "script"} {
		lappend out "speech to text: faster-whisper ($Settings(sttModel), $Settings(sttDevice), \
			[expr {$Settings(sttServer) ? "model kept loaded" : "one process per utterance"}])"
	} elseif {$stt ne ""} {
		lappend out "speech to text: $stt"
	} else {
		lappend out "speech to text: none found -- 'pip install faster-whisper', or set SCIDB_AI_STT"
	}

	set tts [ttsEngine]
	lappend out "speech output: [expr {$tts ne "" ? "$tts (mode: $Settings(ttsMode))" : "off"}]"

	lappend out "engines found: [join [lsort [lmap k [dict keys $have] { if {[dict get $have $k]} { set k } }]] {, }]"
	return [join $out \n]
}


proc ::application::voice::available {} {
	return [expr {[recorder] ne "" && [sttEngine] ne ""}]
}

# vi:set ts=3 sw=3:
