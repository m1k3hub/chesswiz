# ======================================================================
# Test suite for German UI string translations (Task de)
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::de {}

set ::scidb::test::de::savedShare $::scidb::dir::share
set ::scidb::test::de::worktreeShare [file normalize [file join \
	[file dirname [file normalize [info script]]] .. tcl]]
if {[file isdirectory [file join $::scidb::test::de::worktreeShare lang]]} {
	set ::scidb::dir::share $::scidb::test::de::worktreeShare
}

proc ::scidb::test::de::ReadLangEntries {langFile enc} {
	set fh [open $langFile r]
	fconfigure $fh -encoding $enc
	set entries [dict create]
	while {[gets $fh line] >= 0} {
		set line [string trim $line]
		if {$line eq "" || [string index $line 0] eq "#"} { continue }
		if {[catch {lindex $line 0} var] || $var eq ""} {
			set parts [regexp -inline {^(\S+)\s+(.*)$} $line]
			if {[llength $parts] >= 3} {
				set var [lindex $parts 1]
				set val [lindex $parts 2]
				dict set entries $var $val
			}
			continue
		}
		set val [lindex $line 1]
		dict set entries $var $val
	}
	close $fh
	return $entries
}

set ::scidb::test::de::enPath [file join $::scidb::dir::share lang english.tcl]
set ::scidb::test::de::dePath [file join $::scidb::dir::share lang deutsch.tcl]

tcltest::test deutsch-english-keys-coverage {every string key in english.tcl is defined in deutsch.tcl} -body {
	set enDict [::scidb::test::de::ReadLangEntries $::scidb::test::de::enPath iso8859-1]
	set deDict [::scidb::test::de::ReadLangEntries $::scidb::test::de::dePath iso8859-1]

	set missingKeys {}
	dict for {key val} $enDict {
		# Normalize malformed keys if any (e.g. missing closing paren in english.tcl)
		if {$key eq "::export::mc::Option(pgn,use_strict_pgn_standard"} {
			set key "::export::mc::Option(pgn,use_strict_pgn_standard)"
		}
		if {![dict exists $deDict $key]} {
			lappend missingKeys $key
		}
	}
	set missingKeys [lsort $missingKeys]
	if {[llength $missingKeys] > 0} {
		puts "Missing keys from english.tcl in deutsch.tcl: $missingKeys"
	}
	llength $missingKeys
} -result 0

tcltest::test deutsch-new-ui-namespaces-coverage {new UI string keys are present in deutsch.tcl} -body {
	set deDict [::scidb::test::de::ReadLangEntries $::scidb::test::de::dePath iso8859-1]

	set requiredKeys {
		::application::mc::ShortcutPreferences
		::application::mc::ShortcutScheme
		::application::mc::ShortcutChesswiz
		::application::mc::ShortcutChessBase
		::application::twm::mc::Pane(report)
		::application::twm::mc::Pane(assistant)
		::application::database::mc::CannotReadFile
		::playerdict::mc::Region(r)
		::info::mc::BasedOnScidb
		::menu::mc::Three-check
		{::menu::mc::variant list}
		::application::ask::mc::Placeholder
		::application::ask::mc::AskAssistant
		::application::ask::mc::Send
		::application::ask::mc::Mic
		::application::ask::mc::Recording
		::application::ask::mc::Transcribing
		::application::ask::mc::Heard
		::application::ask::mc::NothingHeard
		::application::ask::mc::AssistantPrefs
		::application::speech::mc::Install
		::application::speech::mc::InstallMac
		::application::speech::mc::InstallWin
		::application::speech::mc::Listening
		::application::speech::mc::Working
		::application::speech::mc::Nothing
		::application::speech::mc::Failed
		::application::speech::mc::NoRecord
		::application::assistant::mc::Send
		::application::assistant::mc::Clear
		::application::assistant::mc::Thinking
		::application::assistant::mc::Ready
		::application::assistant::mc::UsingBackup
		::application::assistant::mc::AllDown
		::application::assistant::mc::Confirm
		::application::assistant::mc::Denied
		::application::assistant::mc::Greeting
		::application::assistant::mc::DebugGreeting
		::application::assistant::mc::Plan
		::application::assistant::mc::PlanConfirm
		::application::assistant::mc::PlanDeclined
		::application::assistant::mc::PlanStepFailed
		::application::assistant::mc::PlanStepSkipped
		::application::assistant::mc::TooManyRounds
		::application::assistant::offers::mc::Summary
		::application::assistant::offers::mc::FindPositions
		::application::assistant::offers::mc::Duplicates
		::application::assistant::offers::mc::Review
		::application::assistant::offers::mc::WentWrong
		::application::assistant::offers::mc::GamesLike
		::application::assistant::offers::mc::Explain
		::application::assistant::offers::mc::SamePosition
		::application::assistant::offers::mc::PositionsLike
		::application::assistant::offers::mc::Compact
		::application::assistant::offers::mc::Trend
		::application::assistant::offers::mc::Maintenance
		::application::assistant::offers::mc::Annotate
		::application::assistant::offers::mc::OpeningReport
		::application::assistant::offers::mc::Lesson
		::application::assistant::offers::mc::AskAbout
		::application::assistant::offers::mc::AskAboutGame
		::application::assistant::offers::mc::AskAboutBoard
		::application::ai::models::mc::Title
		::application::ai::models::mc::LanguageModel
		::application::ai::models::mc::Ollama
		::application::ai::models::mc::Fireworks
		::application::ai::models::mc::Qwen
		::application::ai::models::mc::Gemini
		::application::ai::models::mc::Claude
		::application::ai::models::mc::OpenAI
		::application::ai::models::mc::Listing
		::application::ai::models::mc::ListFailed
		::application::ai::models::mc::ApiKey
		::application::ai::models::mc::KeyStored
		::application::ai::models::mc::KeyFromEnv
		::application::ai::models::mc::NoModel
		::application::ai::models::mc::Classifier
		::application::ai::models::mc::Model
		::application::ai::models::mc::Where
		::application::ai::models::mc::Tools
		::application::ai::models::mc::Fit
		::application::ai::models::mc::Local
		::application::ai::models::mc::Cloud
		::application::ai::models::mc::Yes
		::application::ai::models::mc::No
		::application::ai::models::mc::NoSize
		::application::ai::models::mc::Memory
		::application::ai::models::mc::Name
		::application::ai::models::mc::Fetching
		::application::ai::models::mc::Found
		::application::ai::models::mc::Unreachable
		::application::ai::models::mc::NoTools
		::application::ai::models::mc::Overridden
		::application::ai::models::mc::Option
		::application::ai::models::mc::Environment
		::application::ai::models::mc::Off
		::application::ai::models::mc::OffNote
		::application::ai::models::mc::Auto
		::application::ai::models::mc::AutoNote
		::application::ai::models::mc::ClassifierNote
		::application::ai::models::mc::Recommended
		::application::ai::models::mc::PlumbNote
		::application::ai::models::mc::KeyNote
		::application::ai::models::mc::Backups
		::application::ai::models::mc::Backup1
		::application::ai::models::mc::Backup2
		::application::ai::models::mc::BackupNote
	}

	set missing {}
	foreach k $requiredKeys {
		if {![dict exists $deDict $k]} {
			lappend missing $k
		}
	}
	if {[llength $missing] > 0} {
		puts "Missing new UI keys in deutsch.tcl: $missing"
	}
	llength $missing
} -result 0

tcltest::test deutsch-runtime-values {runtime language switch to German loads translated values} -body {
	set old $::mc::langID
	::mc::setLang de

	set checks [list \
		[set ::application::mc::ShortcutPreferences] \
		[set ::application::twm::mc::Pane(report)] \
		[set ::application::twm::mc::Pane(assistant)] \
		[set ::application::ask::mc::Placeholder] \
		[set ::application::assistant::mc::Send] \
		[set ::application::assistant::offers::mc::Summary] \
		[set ::application::ai::models::mc::Title] \
		[set ::menu::mc::Three-check] \
	]

	::mc::setLang $old
	# Check that values are not English defaults
	set isNotEnglish 1
	if {[lindex $checks 0] eq "Keyboard Preferences"} { set isNotEnglish 0 }
	if {[lindex $checks 1] eq "Report" && [lindex $checks 2] eq "Assistant"} { set isNotEnglish 0 }
	if {[string match "*Ctrl+K*" [lindex $checks 3]]} { set isNotEnglish 0 }
	if {[lindex $checks 4] eq "Send"} { set isNotEnglish 0 }
	if {[lindex $checks 5] eq "What's in this database?"} { set isNotEnglish 0 }
	if {[lindex $checks 6] eq "AI Models"} { set isNotEnglish 0 }
	if {[lindex $checks 7] eq "Three-check"} { set isNotEnglish 0 }
	set isNotEnglish
} -result 1

tcltest::test deutsch-no-competitor-names {new translations contain no CQL, ChessBase, or competitor names} -body {
	set deDict [::scidb::test::de::ReadLangEntries $::scidb::test::de::dePath iso8859-1]

	set newKeysToCheck {
		::application::mc::ShortcutPreferences
		::application::mc::ShortcutScheme
		::application::mc::ShortcutChesswiz
		::application::mc::ShortcutChessBase
		::application::ask::mc::Placeholder
		::application::ask::mc::AskAssistant
		::application::speech::mc::Install
		::application::assistant::mc::Greeting
		::application::assistant::mc::DebugGreeting
		::application::assistant::offers::mc::FindPositions
		::application::ai::models::mc::Title
	}

	set bad {}
	foreach k $newKeysToCheck {
		if {[dict exists $deDict $k]} {
			set val [dict get $deDict $k]
			if {[regexp -nocase {\m(chessbase|fritz|cql)\M} $val m]} {
				lappend bad "$k:$m"
			}
		}
	}
	set bad
} -result {}

if {[info exists ::scidb::test::de::savedShare]} {
	set ::scidb::dir::share $::scidb::test::de::savedShare
}

tcltest::cleanupTests
