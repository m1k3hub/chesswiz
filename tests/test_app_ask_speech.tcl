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
		::application::speech::toggle
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
		::application::speech::toggle
		::scidb::test::speech::WaitIdle
		set entry [::application::ask::Entry]
		$entry insert end " now"
		list [set ::application::ask::Query] [llength $::scidb::test::speech::Asked]
	}
} -result {{open the last game now} 0}

tcltest::test speech-cancel-inserts-nothing {cancelling a transcription inserts nothing} -body {
	::scidb::test::speech::isolated {
		::application::speech::configure stub {return "open the last game"}
		::application::speech::toggle
		::application::speech::toggle
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
		::application::speech::toggle
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
		catch { exec mkdir -m 0700 -- $otherDir }
		set otherFile [file join $otherDir "ask-other.wav"]
		set f [open $otherFile w]; puts $f "concurrent-recording"; close $f

		# ClearTemp must only clear files in its own session directory
		::scidb::test::speech::ClearTemp
		set otherSurvived [file exists $otherFile]

		# Running speech stub must leave its own session directory empty without touching otherDir
		::application::speech::configure stub {return "open the last game"}
		::application::speech::toggle
		::application::speech::toggle
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
# No path: the microphone is hidden and Preferences says what to install.
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
} -result {0 0 1 1 1}

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
} -result {{Speech input} 1 1 1}

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
	set linked [exec ldd $binary]
	set found {}
	foreach lib {whisper portaudio vosk pocketsphinx} {
		if {[string match -nocase "*$lib*" $linked]} { lappend found $lib }
	}
	list $found [string match -nocase "*libtk*" $linked]
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

# Constraints: the git-ignored local build.
tcltest::test speech-fixture-description {the speech fixture file names the model and its checksum} -body {
	set f [open [file join $::scidb::test::speech::Dir speech-fixture.txt] r]
	set data [read $f]
	close $f
	list [expr {[string match {*model_sha256=*} $data]}] \
		[expr {[string match {*fixture_wav=*} $data]}] \
		[expr {[string match {*fixture_text=*} $data]}]
} -result {1 1 1}

tcltest::cleanupTests
