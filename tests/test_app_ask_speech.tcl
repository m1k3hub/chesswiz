# ======================================================================
# Scidb App Test - speech input enters only through the Ask field
# ======================================================================
# VAL-AI-005/006: a transcript is inserted at the cursor, stays editable
# and is never sent; cancel inserts nothing; the microphone is hidden
# with no path and Preferences says what to install; the Linux path is
# whisper.cpp (CPU only) as an external process with no network and no
# linked audio library, using a real recording fixture.
#
# Deterministic tests use the stub transcript; the real whisper-cli run
# is skipped when the git-ignored build in tests/tmp-app/speech is not
# present.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::speech {
	variable Asked {}
	variable Dir [file join [file dirname [file normalize [info script]]] fixtures]
	variable WhisperDir [file join [file dirname [file normalize [info script]]] tmp-app speech]
}

proc ::scidb::test::speech::Wav {} {
	return [file join $::scidb::test::speech::Dir speech-open-last-game.wav]
}

proc ::scidb::test::speech::WhisperCli {} {
	return [file join $::scidb::test::speech::WhisperDir build bin whisper-cli]
}

proc ::scidb::test::speech::Model {} {
	return [file join $::scidb::test::speech::WhisperDir ggml-base.en.bin]
}

proc ::scidb::test::speech::FixtureText {} {
	set path [file join $::scidb::test::speech::Dir speech-fixture.txt]
	set f [open $path r]
	set data [read $f]
	close $f
	foreach line [split $data \n] {
		set line [string trim $line]
		if {[string match "fixture_text=*" $line]} {
			return [string trim [string range $line 13 end]]
		}
	}
	return ""
}

proc ::scidb::test::speech::WaitIdle {{ms 60000}} {
	set start [clock milliseconds]
	while {[set ::application::speech::Priv(state)] ne "idle"} {
		update
		if {[clock milliseconds] - $start > $ms} { return 0 }
		after 20
	}
	update
	return 1
}

proc ::scidb::test::speech::install {} {
	catch { rename ::application::assistant::ask ::scidb::test::speech::realAsk }
	proc ::application::assistant::ask {request args} {
		lappend ::scidb::test::speech::Asked $request
		return 1
	}
}

proc ::scidb::test::speech::uninstall {} {
	catch { rename ::application::assistant::ask {} }
	catch { rename ::scidb::test::speech::realAsk ::application::assistant::ask }
}

proc ::scidb::test::speech::ClearTemp {} {
	set dir [::application::speech::TempDir]
	if {![file exists $dir]} { return }
	foreach f [glob -nocomplain -directory $dir *] {
		catch { file delete -force $f }
	}
}

proc ::scidb::test::speech::isolated {body} {
	set settings [array get ::application::speech::Settings]
	set priv [array get ::application::speech::Priv]
	variable Asked {}
	install
	catch { ::application::speech::Cancel }
	catch { ::application::ask::HideList }
	set ::application::ask::Query ""
	[::application::ask::Entry] delete 0 end
	catch { update }

	set rc [catch { uplevel 1 $body } result]

	catch { ::application::speech::Cancel }
	uninstall
	array set ::application::speech::Settings $settings
	array set ::application::speech::Priv $priv
	catch { ::application::ask::SyncMic }
	set ::application::ask::Query ""
	catch { [::application::ask::Entry] delete 0 end }
	catch { update }
	if {$rc} { return -code error $result }
	return $result
}

tcltest::testConstraint whisperBuilt [expr {
	[file exists [::scidb::test::speech::WhisperCli]] &&
	[file exists [::scidb::test::speech::Model]] &&
	![catch { exec which strace }]
}]

# Normalise a transcript for comparison: lower case, letters and spaces.
proc ::scidb::test::speech::Words {text} {
	return [string trim [regsub -all {[^a-z0-9 ]+} [string tolower $text] " "]]
}

# ----------------------------------------------------------------------
# The stub transcript path.
# ----------------------------------------------------------------------
tcltest::test speech-stub-inserts-at-cursor {a transcript is inserted at the cursor and not sent} -body {
	::scidb::test::speech::isolated {
		::application::speech::configure stub {return "open the last game"}
		set entry [::application::ask::Entry]
		$entry insert 0 "please "
		$entry icursor end
		::application::speech::toggle
		set recording [set ::application::speech::Priv(state)]
		::application::speech::RecordTimeout $::application::speech::Priv(recordFile)
		set transcribing [set ::application::speech::Priv(state)]
		set micWhile [[::application::ask::Mic] cget -text]
		set idle [::scidb::test::speech::WaitIdle]
		set q $::application::ask::Query
		list $recording $transcribing $micWhile $idle [llength $::scidb::test::speech::Asked] $q
	}
} -result {recording transcribing {Transcribing… click to cancel} 1 0 {please open the last game}}

tcltest::test speech-stub-transcript-is-editable {the inserted transcript stays an editable field value} -body {
	::scidb::test::speech::isolated {
		::application::speech::configure stub {return "open the last game"}
		::application::speech::toggle
		::application::speech::RecordTimeout $::application::speech::Priv(recordFile)
		::scidb::test::speech::WaitIdle
		set entry [::application::ask::Entry]
		$entry insert end " now"
		list [set ::application::ask::Query] [llength $::scidb::test::speech::Asked]
	}
} -result {{open the last game now} 0}

tcltest::test speech-transcript-enter-sends-once {only Enter submits the editable transcript to the assistant} -body {
	::scidb::test::speech::isolated {
		::application::speech::configure stub {return "open the last game"}
		::application::speech::toggle
		::application::speech::RecordTimeout $::application::speech::Priv(recordFile)
		::scidb::test::speech::WaitIdle
		set before $::scidb::test::speech::Asked
		set entry [::application::ask::Entry]
		$entry insert end " please"
		::application::ask::Typed
		# Select the assistant row, below the local action suggestions.
		set ::application::ask::Priv(index) [llength $::application::ask::Priv(rows)]
		focus -force $entry
		update
		event generate $entry <Return>
		update
		list $before $::scidb::test::speech::Asked $::application::ask::Query
	}
} -result {{} {{open the last game please}} {}}

tcltest::test speech-cancel-inserts-nothing {cancelling a transcription inserts nothing} -body {
	::scidb::test::speech::isolated {
		::application::speech::configure stub {return "open the last game"}
		::application::speech::toggle
		::application::speech::RecordTimeout $::application::speech::Priv(recordFile)
		# still transcribing: the stub finish is 120 ms away
		set state [set ::application::speech::Priv(state)]
		::application::speech::Cancel
		after 400
		update
		list $state [set ::application::speech::Priv(state)] $::application::ask::Query \
			[llength $::scidb::test::speech::Asked]
	}
} -result {transcribing idle {} 0}

tcltest::test speech-stub-cleans-temp {the stub path leaves no recording behind in the temp directory} -body {
	::scidb::test::speech::isolated {
		::scidb::test::speech::ClearTemp
		::application::speech::configure stub {return "open the last game"}
		::application::speech::toggle
		::application::speech::RecordTimeout $::application::speech::Priv(recordFile)
		::scidb::test::speech::WaitIdle
		glob -nocomplain [file join [::application::speech::TempDir] *]
	}
} -result {}

tcltest::test speech-session-directory-isolated {each session has its own subdirectory and cleanup touches only its own files} -body {
	::scidb::test::speech::isolated {
		set sessionDir [::application::speech::TempDir]
		set userDir [file dirname $sessionDir]
		set sessionName [file tail $sessionDir]

		# Verify the session directory is a dedicated subdirectory with pid and random token
		set isSubdir [expr {[string match "session-[pid]-*" $sessionName] && [file isdirectory $sessionDir]}]

		# Simulate a concurrent session belonging to the same user
		set randTag [format %06x [expr {int(rand() * 0xffffff)}]]
		set otherDir [file join $userDir "session-[pid]-sim-${randTag}"]
		file mkdir $otherDir
		if {$::tcl_platform(platform) ne "windows"} {
			file attributes $otherDir -permissions 0700
		}
		set otherFile [file join $otherDir "ask-other.wav"]
		set f [open $otherFile w]; puts $f "concurrent-recording"; close $f

		# ClearTemp must only clear files in its own session directory
		::scidb::test::speech::ClearTemp
		set otherSurvived [file exists $otherFile]

		# Running speech stub must leave its own session directory empty without touching otherDir
		::application::speech::configure stub {return "open the last game"}
		::application::speech::toggle
		::application::speech::RecordTimeout $::application::speech::Priv(recordFile)
		::scidb::test::speech::WaitIdle

		set ownLeftover [glob -nocomplain [file join [::application::speech::TempDir] *]]
		set otherStillExists [file exists $otherFile]
		set otherContent ""
		if {$otherStillExists} {
			set f [open $otherFile r]; set otherContent [string trim [read $f]]; close $f
		}
		catch { file delete -force $otherDir }

		list $isSubdir $otherSurvived $ownLeftover $otherStillExists $otherContent
	}
} -result {1 1 {} 1 concurrent-recording}

# ----------------------------------------------------------------------
# Without Whisper, Linux hides the microphone and shows installation help.
# Windows and Aqua keep native speech available without Whisper.
# ----------------------------------------------------------------------
tcltest::test speech-absent-hides-mic {with no speech path the microphone button is not shown} -body {
	::scidb::test::speech::isolated {
		::application::speech::configure \
			whisperCli /nonexistent/whisper-cli \
			whisperModel /nonexistent/model.bin \
			recorder /nonexistent/arecord \
			stub ""
		set available [::application::speech::available]
		set packed [expr {[lsearch -exact [pack slaves .application.nb.ask] [::application::ask::Mic]] >= 0}]
		set hint [::application::speech::hint]
		list $available $packed \
			[expr {[string match {*whisper-cli*} $hint]}] \
			[expr {[string match {*ggml*} $hint]}] \
			[expr {[string match {*arecord*} $hint]}]
	}
} -result [expr {[tk windowingsystem] in {aqua win32} ? {1 1 0 0 0} : {0 0 1 1 1}}]

tcltest::test speech-preferences-says-what-to-install {Preferences > Assistant shows the speech hint and fields} -body {
	::scidb::test::speech::isolated {
		::application::speech::configure \
			whisperCli /nonexistent/whisper-cli \
			whisperModel /nonexistent/model.bin \
			recorder /nonexistent/arecord \
			stub ""
		catch { destroy .application.assistantPreferences }
		::application::ask::Preferences
		update idletasks
		set dlg .application.assistantPreferences
		set title [$dlg.content.title cget -text]
		set hint [$dlg.content.hint cget -text]
		set hasCli [winfo exists $dlg.content.whisperCli.entry]
		set hasModel [winfo exists $dlg.content.whisperModel.entry]
		destroy $dlg
		list $title [expr {[string match {*whisper-cli*} $hint]}] $hasCli $hasModel
	}
} -result [expr {[tk windowingsystem] in {aqua win32} ? {{Speech input} 0 1 1} : {{Speech input} 1 1 1}}]

tcltest::test speech-present-shows-mic {a working path puts the microphone back in the field} -body {
	::scidb::test::speech::isolated {
		::application::speech::configure \
			whisperCli [::scidb::test::speech::WhisperCli] \
			whisperModel [::scidb::test::speech::Model] \
			recorder true \
			stub {return "hi"}
		set available [::application::speech::available]
		::application::ask::SyncMic
		set packed [expr {[lsearch -exact [pack slaves .application.nb.ask] [::application::ask::Mic]] >= 0}]
		list $available $packed
	}
} -result {1 1}

# ----------------------------------------------------------------------
# No linked audio library: recorders and recognisers are subprocesses.
# ----------------------------------------------------------------------
tcltest::test speech-no-linked-audio {the app binary links no audio or speech library} -body {
	set binary [info nameofexecutable]
	if {[tk windowingsystem] eq "aqua"} {
		set linked [exec otool -L $binary]
		# This build links Tk statically; AppKit is its native GUI dependency.
		set guiLibrary *AppKit.framework*
	} elseif {$::tcl_platform(platform) eq "windows"} {
		# Inspect this app's loaded native modules; Tcl/Tk is linked statically.
		set tasklist [file join $::env(SystemRoot) System32 tasklist.exe]
		set linked [exec $tasklist /m /fi "PID eq [pid]" /fo csv /nh]
		set guiLibrary *user32.dll*
	} else {
		set linked [exec ldd $binary]
		set guiLibrary *libtk*
	}
	set found {}
	foreach lib {whisper portaudio vosk pocketsphinx} {
		if {[string match -nocase "*$lib*" $linked]} { lappend found $lib }
	}
	list $found [string match -nocase $guiLibrary $linked]
} -result {{} 1}

tcltest::test speech-source-has-no-cloud-call {the speech module never calls the assistant provider or the network} -body {
	set src [file join [file dirname [file normalize [info script]]] .. tcl app-ask.tcl]
	set f [open $src r]
	set text [read $f]
	close $f
	list [expr {[string match {*::ai::provider*} $text]}] \
		[expr {[string match {*http://*} $text]}] \
		[expr {[string match {*https://*} $text]}]
} -result {0 0 0}

# ----------------------------------------------------------------------
# The real Linux path: whisper.cpp, CPU only, no network, temp cleaned.
# ----------------------------------------------------------------------
tcltest::test speech-whisper-fixture {whisper-cli transcribes the recorded fixture} -constraints whisperBuilt -body {
	set text [::application::speech::transcribeFile [::scidb::test::speech::Wav]]
	list [::scidb::test::speech::Words $text] \
		[::scidb::test::speech::Words [::scidb::test::speech::FixtureText]]
} -result [list [::scidb::test::speech::Words "open the last game"] \
	[::scidb::test::speech::Words "open the last game"]]

tcltest::test speech-whisper-flow {the full whisper path inserts the transcript and deletes its temp files} -constraints whisperBuilt -body {
	::scidb::test::speech::isolated {
		::scidb::test::speech::ClearTemp
		::application::speech::configure \
			whisperCli [::scidb::test::speech::WhisperCli] \
			whisperModel [::scidb::test::speech::Model] \
			recorder true \
			stub ""
		[::application::ask::Entry] delete 0 end
		set ::application::speech::Priv(state) transcribing
		::application::speech::StartTranscribe [::scidb::test::speech::Wav]
		set idle [::scidb::test::speech::WaitIdle]
		set leftover [glob -nocomplain [file join [::application::speech::TempDir] *]]
		list $idle [::scidb::test::speech::Words $::application::ask::Query] \
			[llength $::scidb::test::speech::Asked] $leftover
	}
} -result [list 1 [::scidb::test::speech::Words "open the last game"] 0 {}]

tcltest::test speech-whisper-no-network {whisper-cli makes no network syscall on the fixture} -constraints whisperBuilt -body {
	set log [file join $::scidb::test::speech::WhisperDir strace-network.log]
	catch { file delete -force $log }
	set rc [catch {
		exec strace -f -e trace=network -o $log -- \
			[::scidb::test::speech::WhisperCli] \
			-m [::scidb::test::speech::Model] \
			-f [::scidb::test::speech::Wav] -nt -np 2> /dev/null
	} text]
	set f [open $log r]
	set trace [read $f]
	close $f
	set calls {}
	foreach pattern {socket( connect( sendto( recvfrom( bind( getpeername(} {
		if {[string first $pattern $trace] >= 0} { lappend calls $pattern }
	}
	list $rc $calls
} -result {0 {}}

# ----------------------------------------------------------------------
# sherpa-onnx: preferred over whisper-cli when its tool and model are set.
# ----------------------------------------------------------------------
namespace eval ::scidb::test::speech {
	variable SherpaTools [file join [file dirname [file normalize [info script]]] tmp-app speech-tools]
}
proc ::scidb::test::speech::SherpaCli {} {
	return [lindex [glob -nocomplain [file join $::scidb::test::speech::SherpaTools bin linux-x64 sherpa-onnx * bin sherpa-onnx-offline]] 0]
}
proc ::scidb::test::speech::SherpaParakeet {} {
	return [lindex [glob -nocomplain -types d [file join $::scidb::test::speech::SherpaTools models asr *parakeet*]] 0]
}
proc ::scidb::test::speech::FakeSherpa {} {
	set dir [file join [::application::speech::TempDir] fake-sherpa-[pid]]
	file mkdir [file join $dir model-nemo-parakeet]
	foreach f {encoder.int8.onnx encoder.onnx decoder.int8.onnx joiner.int8.onnx tokens.txt} {
		close [open [file join $dir model-nemo-parakeet $f] w]
	}
	set cli [file join $dir sherpa-onnx-offline]
	set chan [open $cli w]
	puts $chan "#!/bin/sh"
	puts $chan {echo '{"lang": "", "text": "find games Kasparov wins with white", "tokens": [" find"]}'}
	close $chan
	file attributes $cli -permissions 0755
	return [list $cli [file join $dir model-nemo-parakeet] $dir]
}
tcltest::testConstraint sherpaBuilt [expr {
	$::tcl_platform(platform) eq "unix" && $::tcl_platform(os) ne "Darwin" &&
	[::scidb::test::speech::SherpaCli] ne "" && [::scidb::test::speech::SherpaParakeet] ne ""
}]
tcltest::testConstraint linuxOnly [expr {$::tcl_platform(platform) eq "unix" && $::tcl_platform(os) ne "Darwin"}]

tcltest::test speech-sherpa-text {the transcript is the text of the JSON result line, escapes decoded} -body {
	list [::application::speech::SherpaText {{"lang": "", "text": "Open the Réti", "tokens": ["x"]}}] \
		[::application::speech::SherpaText "noise\n{\"text\": \"say \\\"hi\\\"\"}\n"] \
		[::application::speech::SherpaText "no json"]
} -result [list "Open the Réti" {say "hi"} {}]

tcltest::test speech-sherpa-model-folder {a model folder needs encoder, decoder, joiner and tokens; int8 and NeMo are recognised} -constraints linuxOnly -body {
	lassign [::scidb::test::speech::FakeSherpa] cli model dir
	set m [::application::speech::SherpaModel $model]
	set incomplete [file join $dir incomplete]
	file mkdir $incomplete
	close [open [file join $incomplete encoder.onnx] w]
	set r [list [file tail [dict get $m encoder]] [dict get $m type] \
		[dict size [::application::speech::SherpaModel $incomplete]] \
		[dict size [::application::speech::SherpaModel ""]]]
	file delete -force $dir
	set r
} -result {encoder.int8.onnx nemo_transducer 0 0}

tcltest::test speech-sherpa-preferred {with sherpa-onnx set, detect picks it over whisper and the flow inserts its transcript} -constraints linuxOnly -body {
	::scidb::test::speech::isolated {
		lassign [::scidb::test::speech::FakeSherpa] cli model dir
		::application::speech::configure sherpaCli $cli sherpaModel $model \
			whisperCli [::scidb::test::speech::WhisperCli] whisperModel [::scidb::test::speech::Model] \
			recorder true stub ""
		set mode [dict get [::application::speech::detect] mode]
		set wav [file join $dir in.wav]
		file copy [::scidb::test::speech::Wav] $wav
		set ::application::speech::Priv(state) transcribing
		::application::speech::StartTranscribe $wav
		set idle [::scidb::test::speech::WaitIdle]
		file delete -force $dir
		list $mode $idle $::application::ask::Query [llength $::scidb::test::speech::Asked]
	}
} -result {sherpa 1 {find games Kasparov wins with white} 0}

tcltest::test speech-sherpa-hotwords-argv {a hotwords file switches to beam search only when the model has a bpe vocabulary} -constraints linuxOnly -body {
	::scidb::test::speech::isolated {
		lassign [::scidb::test::speech::FakeSherpa] cli model dir
		set hot [file join $dir hot.txt]
		close [open $hot w]
		::application::speech::configure sherpaCli $cli sherpaModel $model hotwords $hot recorder true stub ""
		set a [::application::speech::SherpaArgv [::application::speech::detect] x.wav]
		close [open [file join $model bpe.vocab] w]
		set b [::application::speech::SherpaArgv [::application::speech::detect] x.wav]
		file delete -force $dir
		list [expr {[lsearch -glob $a --hotwords-file=*] >= 0}] [expr {[lsearch -glob $b --hotwords-file=*] >= 0}] \
			[expr {"--model-type=nemo_transducer" in $a}] [lindex $a end]
	}
} -result {0 1 1 x.wav}

tcltest::test speech-sherpa-real {the downloaded sherpa-onnx Parakeet model transcribes the recorded fixture} -constraints sherpaBuilt -body {
	::scidb::test::speech::isolated {
		::application::speech::configure sherpaCli [::scidb::test::speech::SherpaCli] \
			sherpaModel [::scidb::test::speech::SherpaParakeet] recorder true stub ""
		::scidb::test::speech::Words [::application::speech::transcribeFile [::scidb::test::speech::Wav]]
	}
} -result [::scidb::test::speech::Words "open the last game"]

# Constraints: the git-ignored local build.
tcltest::test speech-fixture-description {the speech fixture file names the model and its checksum} -body {
	set f [open [file join $::scidb::test::speech::Dir speech-fixture.txt] r]
	set data [read $f]
	close $f
	list [expr {[string match {*model_sha256=*} $data]}] \
		[expr {[string match {*fixture_wav=*} $data]}] \
		[expr {[string match {*fixture_text=*} $data]}]
} -result {1 1 1}


proc ::scidb::test::speech::HostCase {host body} {
	rename ::application::speech::Host ::application::speech::RealHost
	proc ::application::speech::Host {} [list return $host]
	set rc [catch {uplevel 1 $body} result options]
	rename ::application::speech::Host {}
	rename ::application::speech::RealHost ::application::speech::Host
	return -options $options $result
}

tcltest::test speech-xplat-enumeration {audio enumeration ignores video and handles nonzero ffmpeg exit} -body {
	rename ::exec ::scidb::test::speech::realExec
	proc ::exec {args} {
		return -code error {[dshow @ x] "Camera" (video)
[dshow @ x] "USB Microphone" (audio)
[dshow @ x] Alternative name "@device_cm_foo"
[dshow @ x] "Built-in Mic" (audio)}
	}
	set devices [::application::speech::WindowsAudioDevices ffmpeg]
	rename ::exec {}
	rename ::scidb::test::speech::realExec ::exec
	set devices
} -result {{USB Microphone} {Built-in Mic}}

tcltest::test speech-xplat-recorder {platform input and mono PCM argv without real devices} -body {
	rename ::application::speech::WindowsAudioDevices ::application::speech::RealDevices
	proc ::application::speech::WindowsAudioDevices {recorder} { return [list {USB Microphone}] }
	set result {}
	foreach host {win-x64 macos-universal2 linux-x64} {
		::scidb::test::speech::HostCase $host {
			set a [::application::speech::RecorderArgv [dict create recorder {/tools with spaces/ffmpeg}] {out file.wav}]
			lappend result [lrange $a 4 7] [lrange $a end-6 end]
		}
	}
	rename ::application::speech::WindowsAudioDevices {}
	rename ::application::speech::RealDevices ::application::speech::WindowsAudioDevices
	set result
} -result {{-f dshow -i {audio=USB Microphone}} {-ar 16000 -ac 1 -c:a pcm_s16le {out file.wav}} {-f avfoundation -i :0} {-ar 16000 -ac 1 -c:a pcm_s16le {out file.wav}} {-f pulse -i default} {-ar 16000 -ac 1 -c:a pcm_s16le {out file.wav}}}

tcltest::test speech-xplat-fallback {local sherpa wins on both hosts; missing recorder preserves native dictation} -constraints linuxOnly -body {
	::scidb::test::speech::isolated {
		lassign [::scidb::test::speech::FakeSherpa] cli model dir
		set result {}
		foreach host {win-x64 macos-universal2} {
			::scidb::test::speech::HostCase $host {
				::application::speech::configure sherpaCli $cli sherpaModel $model recorder true stub ""
				lappend result [dict get [::application::speech::detect] mode]
				::application::speech::configure recorder /nonexistent/ffmpeg
				lappend result [dict get [::application::speech::detect] mode]
			}
		}
		file delete -force $dir
		set result
	}
} -result {sherpa windows sherpa mac}

tcltest::test speech-xplat-stop {ffmpeg receives q to finalize its WAV} -body {
	::scidb::test::speech::isolated {
		set path [::application::speech::TempFile .txt]
		set ::application::speech::Priv(recordChan) [open $path w]
		set ::application::speech::Priv(state) recording
		set ::application::speech::Priv(recordPids) {}
		::application::speech::StopRecording
		::application::speech::CloseRecorder
		set f [open $path r]
		set text [string trim [read $f]]
		close $f
		list $text $::application::speech::Priv(state)
	}
} -result {q transcribing}


tcltest::test speech-xplat-bundle {find nested platform binaries and reject missing tools} -constraints linuxOnly -body {
	set root [file join [::application::speech::TempDir] {bundle test}]
	rename ::application::speech::RepoRoot ::application::speech::RealRepoRoot
	proc ::application::speech::RepoRoot {} [list return $root]
	set result {}
	foreach host {win-x64 macos-universal2} {
		::scidb::test::speech::HostCase $host {
			set name sherpa-onnx-offline
			if {$host eq "win-x64"} { append name .exe }
			set path [file join $root tests tmp-app speech-tools bin $host sherpa-onnx version bin $name]
			file mkdir [file dirname $path]
			close [open $path w]
			file attributes $path -permissions 0755
			lappend result [expr {[::application::speech::BundledTool sherpa-onnx-offline] eq $path}]
			lappend result [::application::speech::BundledTool ffmpeg]
		}
	}
	rename ::application::speech::RepoRoot {}
	rename ::application::speech::RealRepoRoot ::application::speech::RepoRoot
	file delete -force $root
	set result
} -result {1 {} 1 {}}

tcltest::test speech-xplat-no-device {an empty device list fails without starting recording} -body {
	rename ::application::speech::WindowsAudioDevices ::application::speech::RealDevices
	proc ::application::speech::WindowsAudioDevices {recorder} { return {} }
	set result [::scidb::test::speech::HostCase win-x64 {
		catch {::application::speech::RecorderArgv [dict create recorder ffmpeg.exe] out.wav} message
		set message
	}]
	rename ::application::speech::WindowsAudioDevices {}
	rename ::application::speech::RealDevices ::application::speech::WindowsAudioDevices
	set result
} -result {No DirectShow audio recording device found}


# Exercise the actual Tk button binding, not the Cancel API.
tcltest::test speech-second-mic-click-cancels {second recording click inserts nothing and never transcribes} -body {
 ::scidb::test::speech::isolated {
  set ::speechRecognised 0
  ::application::speech::configure stub {incr ::speechRecognised; return "must not be inserted"}
  ::application::ask::SyncMic
  update
  set mic [::application::ask::Mic]
  set entry [::application::ask::Entry]
  $entry insert 0 "keep this"
  foreach phase {start cancel} {
   event generate $mic <Enter>
   event generate $mic <ButtonPress-1> -x 3 -y 3
   event generate $mic <ButtonRelease-1> -x 3 -y 3
   update
   if {$phase eq "start"} {set recording $::application::speech::Priv(state)}
  }
  after 500
  update
  list $recording $::application::speech::Priv(state) [$entry get] \
   $::speechRecognised [llength $::scidb::test::speech::Asked]
 }
} -cleanup {unset -nocomplain ::speechRecognised} -result {recording idle {keep this} 0 0}

# These gestures go through the real mapped Mic widget on each platform.
proc ::scidb::test::speech::MicEvent {event} {
 set mic [::application::ask::Mic]
 event generate $mic <Enter>
 event generate $mic $event -x 3 -y 3
 update
}
proc ::scidb::test::speech::Delay {ms} {
 set ::scidb::test::speech::wait 0
 after $ms {set ::scidb::test::speech::wait 1}
 vwait ::scidb::test::speech::wait
}
proc ::scidb::test::speech::GestureSetup {backend seconds} {
 if {$backend eq "whisper"} {
  # Replace the physical microphone with the frozen audio, retaining the
  # recorder process lifetime, StopRecording and real CPU whisper path.
  set recorder [file join $::env(HOME) speech-fixture-recorder]
  set f [open $recorder w]
  puts $f {#!/bin/sh}
  puts $f {for output do :; done}
  puts $f [format {cp '%s' "$output"} [Wav]]
  puts $f {read stop}
  close $f
  file attributes $recorder -permissions 0755
  ::application::speech::configure stub "" sherpaCli /missing/sherpa \
   sherpaModel /missing/model whisperCli [WhisperCli] whisperModel [Model] \
   recorder $recorder maxSeconds $seconds
 } else {
  ::application::speech::configure stub {return "open the last game"} maxSeconds $seconds
 }
 ::application::ask::SyncMic
 update
}
foreach backend {stub whisper} {
 set constraint [expr {$backend eq "whisper" ? "whisperBuilt" : ""}]
 tcltest::test speech-mic-hold-$backend {press records while held; release transcribes and cleans audio} -constraints $constraint -body [string map [list @BACKEND@ $backend] {
  ::scidb::test::speech::isolated {
   ::scidb::test::speech::GestureSetup @BACKEND@ 60
   ::scidb::test::speech::MicEvent <ButtonPress-1>
   set initial $::application::speech::Priv(state)
   set audio $::application::speech::Priv(recordFile)
   ::scidb::test::speech::Delay 1100
   set held $::application::speech::Priv(state)
   set before $::application::ask::Query
   ::scidb::test::speech::MicEvent <ButtonRelease-1>
   set released $::application::speech::Priv(state)
   set idle [::scidb::test::speech::WaitIdle]
   list $initial $held $before $released $idle \
    [::scidb::test::speech::Words $::application::ask::Query] \
    [file exists $audio] [llength $::scidb::test::speech::Asked]
  }
 }] -result {recording recording {} transcribing 1 {open the last game} 0 0}
 tcltest::test speech-mic-timeout-$backend {quick click automatically transcribes on the actual time limit} -constraints $constraint -body [string map [list @BACKEND@ $backend] {
  ::scidb::test::speech::isolated {
   ::scidb::test::speech::GestureSetup @BACKEND@ 1
   ::scidb::test::speech::MicEvent <ButtonPress-1>
   ::scidb::test::speech::MicEvent <ButtonRelease-1>
   set started $::application::speech::Priv(state)
   set audio $::application::speech::Priv(recordFile)
   set idle [::scidb::test::speech::WaitIdle]
   list $started $idle [::scidb::test::speech::Words $::application::ask::Query] \
    [file exists $audio] [llength $::scidb::test::speech::Asked]
  }
 }] -result {recording 1 {open the last game} 0 0}
 tcltest::test speech-mic-cancel-$backend {a second click cancels the recording with no delayed insertion} -constraints $constraint -body [string map [list @BACKEND@ $backend] {
  ::scidb::test::speech::isolated {
   ::scidb::test::speech::GestureSetup @BACKEND@ 1
   [::application::ask::Entry] insert 0 "keep this"
   ::scidb::test::speech::MicEvent <ButtonPress-1>
   ::scidb::test::speech::MicEvent <ButtonRelease-1>
   set audio $::application::speech::Priv(recordFile)
   ::scidb::test::speech::MicEvent <ButtonPress-1>
   ::scidb::test::speech::MicEvent <ButtonRelease-1>
   ::scidb::test::speech::Delay 1500
   list $::application::speech::Priv(state) $::application::ask::Query \
    [file exists $audio] [llength $::scidb::test::speech::Asked]
  }
 }] -result {idle {keep this} 0 0}
}

tcltest::cleanupTests
