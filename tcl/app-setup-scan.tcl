# ======================================================================
# Setup scan: look for what the user would otherwise configure by hand
# (speech input, chess engines, chess fonts, game files) and say, step by
# step in the assistant pane, what was found and what was set up.
#
#   ::application::setupscan::run          the scan, now (the Information
#                                          tab's link starts it)
#   ::application::setupscan::firstStart   the scan once, on the first start
#
# Engines that answer as UCI/WinBoard engines are added to the engine list;
# speech paths are filled in. Fonts and game files are only reported: a
# font cannot be installed from here, and opening a database is the user's
# choice. Each step runs from the event loop, so the window stays live and
# every line shows as soon as it is known.
# ======================================================================

namespace eval application {
namespace eval setupscan {

# rejected: programs that did not answer as engines, never tried again
array set Options { done 0 rejected {} }
array set Priv { running 0 }

variable Steps {ai speech engines fonts databases}

# Only names no ordinary program uses: "obsidian", "dragon", "fruit", "seer"
# or "clover" would start a notes app or a game to ask it "uci".
variable EngineNames {
	stockfish lc0 komodo berserk ethereal rubichess caissa koivisto igel
	arasan crafty toga2 glaurung texel
}

} ;# namespace setupscan
} ;# namespace application


proc ::application::setupscan::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}
if {[llength [info commands ::options::hookWriter]]} {
	::options::hookWriter ::application::setupscan::WriteOptions
}


# One line of running information: the assistant pane when it is there,
# else the log.
proc ::application::setupscan::Say {line} {
	if {[info exists ::application::assistant::Priv(text)]
	 && [winfo exists $::application::assistant::Priv(text)]
	 && [llength [info commands ::application::assistant::Append]]} {
		::application::assistant::Append info $line
	} else {
		catch { ::log::info $line }
	}
	update idletasks
}


# glob that skips what cannot be read (/opt holds root-only folders)
proc ::application::setupscan::Glob {args} {
	if {[catch { glob -nocomplain {*}$args } files]} { return {} }
	return $files
}


proc ::application::setupscan::firstStart {} {
	variable Options
	if {$Options(done)} { return }
	# never in the test harness (each test app is a "first start" that would
	# probe engine programs) or when switched off
	if {[namespace exists ::scidb::test::app] || [info exists ::env(CHESSWIZ_NO_SETUP_SCAN)]} { return }
	set Options(done) 1
	run
}


proc ::application::setupscan::run {} {
	variable Priv
	variable Steps
	if {$Priv(running)} { return }
	set Priv(running) 1
	Say "Looking for what Chesswiz can set up for you: the AI model, speech input, chess engines, chess fonts and game files…"
	after 50 [list ::application::setupscan::Next $Steps]
}


proc ::application::setupscan::Next {steps} {
	variable Priv
	if {![llength $steps]} {
		set Priv(running) 0
		Say "Done. Run this again any time from the Information tab."
		return
	}
	set step [lindex $steps 0]
	if {[catch { Step[string totitle $step] } err]} {
		Say "The $step check failed: $err"
	}
	after 50 [list ::application::setupscan::Next [lrange $steps 1 end]]
}


# --- AI model ----------------------------------------------------------

# How each provider is set up, for the advice when no good model is ready.
variable AiSetup {
	ollama		"install Ollama (ollama.com) and sign in, free"
	gemini		"a free Gemini key from aistudio.google.com"
	fireworks	"a Fireworks API key (paid)"
	qwen		"a Qwen token plan key (paid)"
	anthropic	"an Anthropic API key (paid)"
	openai		"an OpenAI API key (paid)"
}

proc ::application::setupscan::StepAi {} {
	if {$::application::ai::Settings(chosen)} {
		Say "AI model: you chose [::ai::provider::label $::application::ai::Config(provider)] $::application::ai::Config(model); kept."
		return
	}
	# the test harness never reaches the network
	if {[namespace exists ::scidb::test::app]} { return }
	Say "AI model: looking for the most capable cloud model that is ready with the least setup…"
	# the search answers later; the other steps go on meanwhile
	::application::ai::findModel ::application::setupscan::AiFound
}

proc ::application::setupscan::AiFound {result} {
	variable AiSetup
	if {[dict get $result ok]} {
		Say "AI model: using [::ai::provider::label [dict get $result provider]] [dict get $result model]. To use another, or one on this computer, choose it in Extras > AI: Choose Model."
		return
	}
	set advice {}
	foreach {provider model} [dict get $result setup] {
		if {[dict exists $AiSetup $provider]} { lappend advice "[dict get $AiSetup $provider] (for $model)" }
	}
	if {[llength $advice]} {
		Say "AI model: none is ready. Easiest first: [join $advice {; }]. Then run this again. Or run a model on this computer: Extras > AI: Choose Model."
	} else {
		Say "AI model: none found ([dict get $result error]). Choose one in Extras > AI: Choose Model, in the cloud or on this computer."
	}
}


# --- speech input ------------------------------------------------------

proc ::application::setupscan::StepSpeech {} {
	Say "Speech input: looking for whisper.cpp and a model…"
	if {[::application::speech::available]} {
		Say "Speech input: already working."
		return
	}
	set found [::application::speech::search]
	set d [::application::speech::detect]
	if {[dict get $d available]} {
		catch { ::application::ask::SyncMic }
		Say "Speech input: ready, found [join $found { and }]. Click the microphone in the Ask field to dictate."
		return
	}
	set missing [dict get $d reason]
	regexp {Missing: (.*?)\.?$} $missing -> missing
	Say "Speech input: off (missing: $missing). Install whisper.cpp and a model, then run this again."
}


# --- chess engines -------------------------------------------------------

# Folders searched besides PATH, with their subfolders: where engines are
# put on each platform. On Windows an engine usually sits unpacked in its
# own folder (Downloads\stockfish\stockfish-windows-x86-64-avx2.exe).
proc ::application::setupscan::EngineBases {} {
	set home [file normalize ~]
	if {$::tcl_platform(platform) eq "windows"} {
		set bases {}
		foreach var {ProgramFiles ProgramFiles(x86) LOCALAPPDATA} {
			if {[info exists ::env($var)]} {
				set dir [file normalize $::env($var)]
				if {$var eq "LOCALAPPDATA"} { set dir [file join $dir Programs] }
				lappend bases $dir
			}
		}
		foreach d {Downloads Desktop Documents engines chess Chess} { lappend bases [file join $home $d] }
		return $bases
	}
	return [list [file join $home engines] [file join $home chess engines] [file join $home Chess Engines] /opt]
}

proc ::application::setupscan::EngineWhere {} {
	if {$::tcl_platform(platform) eq "windows"} {
		return "PATH, Program Files, Downloads, Desktop and Documents"
	}
	return "PATH, /usr/games, ~/bin, ~/engines and /opt"
}

proc ::application::setupscan::EngineCandidates {} {
	variable EngineNames
	variable Options
	set home [file normalize ~]
	set dirs [split $::env(PATH) [expr {$::tcl_platform(platform) eq "windows" ? ";" : ":"}]]
	# snap wrappers start sandboxed desktop apps, never a chess engine
	set dirs [lmap d $dirs { if {[string match /snap/* $d]} continue; set d }]
	if {$::tcl_platform(platform) ne "windows"} {
		lappend dirs /usr/games /usr/local/games [file join $home bin] [file join $home .local bin]
	}
	set pattern [join $EngineNames |]
	foreach base [EngineBases] {
		lappend dirs $base
		foreach sub [Glob -types d [file join $base *]] {
			lappend dirs $sub
			# a folder named after an engine may hold it one level further down
			if {[regexp -nocase "^($pattern)" [file tail $sub]]} {
				lappend dirs {*}[Glob -types d [file join $sub *]]
			}
		}
	}
	set seen {}
	set known {}
	foreach e $::engine::Engines {
		if {[dict exists $e Command]} { lappend known [file normalize [dict get $e Command]] }
	}
	# one engine of a kind: the first program found per name, in PATH order
	set result [dict create]
	set dirs [lmap d $dirs { if {$d in $seen} continue; lappend seen $d; set d }]
	foreach dir $dirs {
		foreach file [Glob -types {f x} [file join $dir *]] {
			set tail [string tolower [file rootname [file tail $file]]]
			foreach name $EngineNames {
				# the name alone or with a version/build suffix: stockfish,
				# stockfish-17, stockfish_x86-64-avx2; not stockfishgui
				if {$tail ne $name && ![regexp "^${name}\[-_.0-9\]" $tail]} continue
				set path [file normalize $file]
				if {$path ni $known && $path ni $Options(rejected) && ![dict exists $result $name]} {
					dict set result $name $path
				}
				break
			}
		}
	}
	return $result
}

proc ::application::setupscan::StepEngines {} {
	variable Options
	Say "Chess engines: looking in [EngineWhere]…"
	set have [llength $::engine::Engines]
	# a kind already in the list (Stockfish, Lc0, ...) is not added again
	set listed [string tolower [lmap e $::engine::Engines {
		set n [expr {[dict exists $e Name] ? [dict get $e Name] : ""}]
		if {[dict exists $e Identifier]} { append n " " [dict get $e Identifier] }
		set n
	}]]
	set candidates {}
	foreach {kind path} [EngineCandidates] {
		if {[string first $kind $listed] >= 0} {
			Say "Chess engines: [string totitle $kind] is already in the engine list; skipped $path."
		} else {
			lappend candidates $path
		}
	}
	if {![llength $candidates]} {
		Say "Chess engines: no new engine found; $have already in the engine list."
		return
	}
	if {[::engine::adminIsOpen?]} {
		Say "Chess engines: found [llength $candidates], but the Manage Engines dialog is open; close it and run this again."
		return
	}
	set added 0
	foreach path [lrange $candidates 0 9] {
		Say "Chess engines: trying $path…"
		if {[catch { ::engine::install $path } name]} {
			Say "Chess engines: $path was not added ($name); it will not be tried again."
			lappend Options(rejected) $path
		} else {
			Say "Chess engines: added $name."
			incr added
		}
	}
	Say "Chess engines: $added added; [llength $::engine::Engines] in the engine list."
}


# --- chess fonts -------------------------------------------------------

proc ::application::setupscan::StepFonts {} {
	Say "Chess fonts: checking…"
	set figurines [expr {![catch { ::font::haveFigurines? } f] && $f}]
	set symbols [expr {![catch { ::font::haveSymbols? } s] && $s}]
	if {$figurines && $symbols} {
		Say "Chess fonts: figurine and symbol fonts are installed."
		return
	}
	set missing {}
	if {!$figurines} { lappend missing "figurines (moves show letters, e.g. Nf3)" }
	if {!$symbols} { lappend missing "annotation symbols" }
	Say "Chess fonts: missing [join $missing { and }]. Chesswiz still works; reinstalling it restores its fonts."
}


# --- game files --------------------------------------------------------

proc ::application::setupscan::StepDatabases {} {
	set home [file normalize ~]
	set dirs [list $home]
	foreach d {Documents Downloads Desktop chess Chess databases} {
		set dir [file join $home $d]
		if {[file isdirectory $dir]} {
			lappend dirs $dir {*}[Glob -types d [file join $dir *]]
		}
	}
	Say "Game files: looking in your home, Documents, Downloads and Desktop folders…"
	set known {}
	catch {
		foreach entry [::application::database::recentFiles] { lappend known [file normalize [lindex $entry 1]] }
	}
	set files {}
	foreach dir $dirs {
		foreach pattern {*.sci *.si4 *.cbh *.cbv *.pgn *.pgn.gz} {
			foreach file [Glob -types f [file join $dir $pattern]] {
				set file [file normalize $file]
				if {$file ni $known} { lappend files [list [file mtime $file] $file] }
			}
		}
	}
	if {![llength $files]} {
		Say "Game files: none found that you have not opened already."
		return
	}
	set files [lsort -integer -decreasing -index 0 [lsort -unique $files]]
	set names [lmap f [lrange $files 0 4] { string map [list $home ~] [lindex $f 1] }]
	set more [expr {[llength $files] > 5 ? " and [expr {[llength $files] - 5}] more" : ""}]
	Say "Game files: found [llength $files] not opened yet, newest first: [join $names {, }]$more. Open one with File > Open."
}

# vi:set ts=3 sw=3:
