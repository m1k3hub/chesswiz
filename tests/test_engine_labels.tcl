# ======================================================================
# Headless tests for Manage Engines dialog labels, tooltips, and validation (G29)
# ======================================================================
# Gap G29: Command = the engine executable; Directory = Chesswiz's per-engine
# data/working folder (explained in label and tooltip). No migration of stored
# engines; never move the working directory to the executable's folder.
# Validation: Command must be an existing executable file; Directory must be a
# folder (warn, not silently rewrite, if it looks like a file path).
# Run with: tclsh tests/test_engine_labels.tcl
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

set repoRoot [file dirname [file dirname [file normalize [info script]]]]
set fp [open [file join $repoRoot tcl engine.tcl] r]
set source [read $fp]
close $fp

namespace eval ::engine {
	namespace eval mc {}
}

# Extract ::engine::mc block from tcl/engine.tcl
set mcStart [string first "namespace eval mc {" $source]
if {$mcStart < 0} { error "missing ::engine::mc namespace in engine.tcl" }
set mcScript ""
foreach line [split [string range $source $mcStart end] \n] {
	append mcScript $line \n
	if {[info complete $mcScript]} { break }
}
namespace eval ::engine $mcScript

# Extract relevant procedures from tcl/engine.tcl
foreach name {CheckCommand CheckDirectory SaveEngine UpdateVars LoadSharedConfiguration ProbeEngine setup MigrateEngineCommands WriteEngineOptions} {
	set start [string first "proc $name " $source]
	if {$start < 0} { continue }
	set script ""
	foreach line [split [string range $source $start end] \n] {
		append script $line \n
		if {[info complete $script]} { break }
	}
	namespace eval ::engine $script
}

set scratch [file join [::tcltest::temporaryDirectory] englabels-[pid]]
file mkdir $scratch

proc makeProgram {path {executable 1}} {
	set fh [open $path w]
	puts $fh "#!/bin/sh\necho ok"
	close $fh
	if {$::tcl_platform(platform) eq "unix"} {
		file attributes $path -permissions [expr {$executable ? "0755" : "0644"}]
	}
	return $path
}

tcltest::test engine-labels-mc-01 {Command and Directory labels and tooltips explain executable vs working folder} -body {
	set hasDirLabel [expr {[string match "*Working*" $::engine::mc::Directory] || [string match "*Data*" $::engine::mc::Directory]}]
	set hasCmdTip [info exists ::engine::mc::CommandHint]
	set hasDirTip [info exists ::engine::mc::DirectoryHint]
	set cmdTipOk [expr {$hasCmdTip && [string match "*executable*" $::engine::mc::CommandHint]}]
	set dirTipOk [expr {$hasDirTip && [string match "*working*" [string tolower $::engine::mc::DirectoryHint]] && [string match "*data*" [string tolower $::engine::mc::DirectoryHint]]}]
	list $hasDirLabel $cmdTipOk $dirTipOk
} -result {1 1 1}

tcltest::test engine-labels-dialog-wiring-02 {openAdmininstration wires tooltips onto Command and Directory labels and widgets} -body {
	set hasLCommandTip [regexp {::tooltip::tooltip\s+\$setup\.lcommand\s+(\[namespace current\]::mc::CommandHint|\$mc::CommandHint)} $::source]
	set hasTCommandTip [regexp {::tooltip::tooltip\s+\$setup\.tcommand\s+(\[namespace current\]::mc::CommandHint|\$mc::CommandHint)} $::source]
	set hasLDirTip [regexp {::tooltip::tooltip\s+\$setup\.ldirectory\s+(\[namespace current\]::mc::DirectoryHint|\$mc::DirectoryHint)} $::source]
	set hasEDirTip [regexp {::tooltip::tooltip\s+\$setup\.edirectory\s+(\[namespace current\]::mc::DirectoryHint|\$mc::DirectoryHint)} $::source]
	list $hasLCommandTip $hasTCommandTip $hasLDirTip $hasEDirTip
} -result {1 1 1 1}

tcltest::test engine-labels-no-migration-03 {no migration of stored engine directories and default remains in user engines folder} -body {
	set noMigrateProc [expr {[info procs ::engine::MigrateEngineDirectories] eq ""}]
	set probeUsesUserDir [regexp {set engine\(Directory\)\s+\[file join \$::scidb::dir::user engines \$dir\]} $::source]
	set sharedUsesUserDir [regexp {set engine\(Directory\)\s+\[file normalize \[file join \$::scidb::dir::user engines \$dir\]\]} $::source]
	list $noMigrateProc $probeUsesUserDir $sharedUsesUserDir
} -result {1 1 1}

tcltest::test engine-labels-check-command-04 {CheckCommand requires an existing executable file} -setup {
	set exeFile [makeProgram [file join $scratch good-engine.exe] 1]
	set plainFile [makeProgram [file join $scratch not-exe.txt] 0]
	set subDir [file join $scratch subdir]
	file mkdir $subDir
	set missing [file join $scratch does-not-exist]
} -body {
	if {[info procs ::engine::CheckCommand] eq ""} {
		error "missing ::engine::CheckCommand"
	}
	set ok [::engine::CheckCommand $exeFile]
	set errMissing [::engine::CheckCommand $missing]
	set errDir [::engine::CheckCommand $subDir]
	set errEmpty [::engine::CheckCommand ""]
	if {$::tcl_platform(platform) eq "unix"} {
		set errNotExe [::engine::CheckCommand $plainFile]
	} else {
		set errNotExe "not executable"
	}
	list \
		[expr {$ok eq ""}] \
		[expr {$errMissing ne ""}] \
		[expr {$errDir ne ""}] \
		[expr {$errEmpty ne ""}] \
		[expr {$errNotExe ne ""}]
} -cleanup {
	file delete -force $exeFile $plainFile $subDir
} -result {1 1 1 1 1}

tcltest::test engine-labels-check-directory-05 {CheckDirectory warns on existing files or file-like paths (.exe/.bin/.bat/.cmd/.sh)} -setup {
	set validDir [file join $scratch workdir]
	file mkdir $validDir
	set newDir [file join $scratch new-workdir]
	set existingFile [makeProgram [file join $scratch somefile.txt] 0]
	set exePath [file join $scratch nonexistent-engine.exe]
	set binPath [file join $scratch book.bin]
} -body {
	if {[info procs ::engine::CheckDirectory] eq ""} {
		error "missing ::engine::CheckDirectory"
	}
	set okExisting [::engine::CheckDirectory $validDir]
	set okNew [::engine::CheckDirectory $newDir]
	set okEmpty [::engine::CheckDirectory ""]
	set warnExistingFile [::engine::CheckDirectory $existingFile]
	set warnExePath [::engine::CheckDirectory $exePath]
	set warnBinPath [::engine::CheckDirectory $binPath]
	list \
		[expr {$okExisting eq ""}] \
		[expr {$okNew eq ""}] \
		[expr {$okEmpty eq ""}] \
		[expr {$warnExistingFile ne ""}] \
		[expr {$warnExePath ne ""}] \
		[expr {$warnBinPath ne ""}]
} -cleanup {
	file delete -force $validDir $existingFile
} -result {1 1 1 1 1 1}

tcltest::test engine-labels-save-validation-06 {SaveEngine validates Command and Directory and warns without rewriting stored engine} -setup {
	set exeFile [makeProgram [file join $scratch engine-ok] 1]
	set workDir [file join $scratch engine-work]
	file mkdir $workDir
	set badFile [makeProgram [file join $scratch some-file.txt] 0]
	set ::engine::Errors {}
	namespace eval ::dialog {
		proc error {args} {
			lappend ::engine::Errors $args
			return ok
		}
	}
	proc ::winfo {subcmd w} { return .adminEngines }
	namespace eval ::engine {
		variable Priv
		variable Data
		variable Data_
		variable Engines
		set Priv(countrybox) [namespace current]::DummyCountry
		set Priv(button:save) [namespace current]::DummySaveBtn
		proc DummyCountry {args} { return UNK }
		proc DummySaveBtn {args} {}
		proc DummyList {subcmd args} {
			if {$subcmd eq "curselection"} { return 0 }
		}
		proc SaveEngineList {} {
			variable SavedCount
			incr SavedCount
		}
	}
	set ::engine::SavedCount 0
	set initialEntry [list \
		Name Stockfish \
		Command $exeFile \
		Directory $workDir \
		Country UNK \
		Parameters {} \
		UserDefined 1 \
	]
	set ::engine::Engines [list $initialEntry]
	array set ::engine::Data $initialEntry
} -body {
	# 1. Try saving when Directory is a file path (.exe) -> warns, does not save or rewrite
	set ::engine::Data(Directory) [file join $scratch stockfish.exe]
	::engine::SaveEngine ::engine::DummyList
	set errAfterBadDir [llength $::engine::Errors]
	set storedDirAfterBad [dict get [lindex $::engine::Engines 0] Directory]

	# 2. Try saving when Directory is an existing file -> warns, does not save or rewrite
	set ::engine::Data(Directory) $badFile
	::engine::SaveEngine ::engine::DummyList
	set errAfterExistingFile [llength $::engine::Errors]

	# 3. Try saving when Command is not an existing executable -> warns, does not save
	set ::engine::Data(Directory) $workDir
	set ::engine::Data(Command) [file join $scratch missing-engine]
	::engine::SaveEngine ::engine::DummyList
	set errAfterBadCmd [llength $::engine::Errors]
	set savedBeforeGood $::engine::SavedCount

	# 4. Valid Command and empty Directory -> saves without error (no unset $failed bug)
	set ::engine::Data(Command) $exeFile
	set ::engine::Data(Directory) ""
	::engine::SaveEngine ::engine::DummyList
	set savedAfterEmptyDir $::engine::SavedCount

	# 5. Valid Command and valid Directory -> saves without error
	set ::engine::Data(Directory) $workDir
	::engine::SaveEngine ::engine::DummyList
	set savedAfterGood $::engine::SavedCount

	list \
		$errAfterBadDir \
		[expr {$storedDirAfterBad eq $workDir}] \
		$errAfterExistingFile \
		$errAfterBadCmd \
		$savedBeforeGood \
		$savedAfterEmptyDir \
		$savedAfterGood
} -cleanup {
	file delete -force $exeFile $workDir $badFile
} -result {1 1 2 3 0 1 2}

tcltest::test engine-labels-translations-07 {all language files define updated Directory label and new tooltip/validation entries} -body {
	set langs {
		{deutsch.tcl iso8859-1}
		{english.tcl iso8859-1}
		{espanol.tcl utf-8}
		{italiano.tcl utf-8}
		{magyar.tcl utf-8}
		{svenska.tcl utf-8}
	}
	set missing {}
	foreach item $langs {
		lassign $item fname enc
		set fpath [file join $::repoRoot tcl lang $fname]
		set fh [open $fpath r]
		fconfigure $fh -encoding $enc
		set content [read $fh]
		close $fh
		foreach key {Command Directory CommandHint DirectoryHint InvalidCommand NotADirectory} {
			if {![regexp "::engine::mc::$key\\s+\"\[^\"]+\"" $content]} {
				lappend missing "$fname:$key"
			}
		}
	}
	return $missing
} -result {}

file delete -force $scratch
tcltest::cleanupTests
