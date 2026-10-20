# ======================================================================
# Scidb App Test Suite -- Manage Engines dialog labels, tooltips, validation (G29)
# ======================================================================
# Gap G29: Command = the engine executable; Directory = Chesswiz's per-engine
# data/working folder (explained in label and tooltip). No migration of stored
# engines; never move the working directory to the executable's folder.
# Validation: Command must be an existing executable file; Directory must be a
# folder (warn, not silently rewrite, if it looks like a file path).
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::englabels {
	variable savedEngines {}
	variable savedFile {}
	variable isolatedFile {}
	variable errors {}
}

proc ::scidb::test::englabels::program {path {executable 1}} {
	set fh [open $path w]
	puts $fh "#!/bin/sh\necho ok"
	close $fh
	if {$::tcl_platform(platform) eq "unix"} {
		file attributes $path -permissions [expr {$executable ? "0755" : "0644"}]
	}
	return $path
}

proc ::scidb::test::englabels::isolate {} {
	variable savedEngines
	variable savedFile
	variable isolatedFile
	set savedEngines $::engine::Engines
	set savedFile $::scidb::file::engines
	set isolatedFile [file join [::tcltest::temporaryDirectory] engines-g29-app-[pid].dat]
	set ::engine::Engines {}
	set ::scidb::file::engines $isolatedFile
}

proc ::scidb::test::englabels::restore {} {
	variable savedEngines
	variable savedFile
	variable isolatedFile
	catch { destroy .application.adminEngines }
	catch {
		set ::engine::Engines $savedEngines
		set ::scidb::file::engines $savedFile
		file delete -force $isolatedFile
	}
	if {[llength $savedEngines]} {
		::options::hookWriter ::engine::WriteEngineOptions engines
	}
}

proc ::scidb::test::englabels::stubError {} {
	variable errors
	set errors {}
	if {[info commands ::dialog::error] ne ""} {
		rename ::dialog::error ::scidb::test::englabels::_realDialogError
	}
	proc ::dialog::error {args} {
		lappend ::scidb::test::englabels::errors $args
		return ok
	}
}

proc ::scidb::test::englabels::unstubError {} {
	catch { rename ::dialog::error {} }
	if {[info commands ::scidb::test::englabels::_realDialogError] ne ""} {
		rename ::scidb::test::englabels::_realDialogError ::dialog::error
	}
}

tcltest::test app-engine-labels-dialog-01 {Manage Engines dialog displays Working / Data Folder label, tooltips, and preserves stored Directory without migration} -setup {
	::scidb::test::englabels::isolate
	::scidb::test::englabels::stubError
	# Ensure the worktree's language file is loaded even if /usr/local/share/chesswiz/lang has an older installed copy
	set wtShare [file normalize [file join [file dirname [info script]] .. tcl]]
	set savedShare $::scidb::dir::share
	set ::scidb::dir::share $wtShare
	::mc::selectLang English
	set ::scidb::dir::share $savedShare
	set scratch [file join [::tcltest::temporaryDirectory] g29-app-[pid]]
	file mkdir [file join $scratch user engines stockfish-chesswiz.exe]
	file mkdir [file join $scratch bin]
	set exe [::scidb::test::englabels::program [file join $scratch bin stockfish-chesswiz.exe] 1]
	set storedDir [file join $scratch user engines stockfish-chesswiz.exe]
	set entry [dict create \
		Name Stockfish Identifier Stockfish Command $exe \
		Parameters {} Protocol UCI Variants standard UserDefined 1 \
		Directory $storedDir]
	set fp [open $::scidb::file::engines w]
	puts $fp [list set ::engine::Engines [list $entry]]
	close $fp
	catch {
		wm state .application normal
		wm geometry .application "[winfo screenwidth .]x[winfo screenheight .]+0+0"
	}
	after 200; update
} -body {
	::engine::setup
	set storedAfterSetup [dict get [lindex $::engine::Engines 0] Directory]
	set dlg .application.adminEngines
	set ::scidb::test::englabels::dialogResult {}
	after 600 [list apply {{dlg scratch exe storedDir} {
		set setup $dlg.top.nb.setup
		set lcmdText [$setup.lcommand cget -text]
		set ldirText [$setup.ldirectory cget -text]
		set tipLcmd [::tooltip::tooltip $setup.lcommand]
		set tipTcmd [::tooltip::tooltip $setup.tcommand]
		set tipLdir [::tooltip::tooltip $setup.ldirectory]
		set tipEdir [::tooltip::tooltip $setup.edirectory]
		set initialDir $::engine::Data(Directory)

		# Attempt to save a file-like path (.exe that is not an existing folder) -> warns, does not overwrite
		set ::engine::Data(Directory) [file join $scratch bad-file.exe]
		::engine::SaveEngine $dlg.top.list
		set errsAfterBadDir [llength $::scidb::test::englabels::errors]
		set storedAfterBadDir [dict get [lindex $::engine::Engines 0] Directory]

		# Attempt to save with invalid Command -> warns, does not overwrite
		set ::engine::Data(Directory) $storedDir
		set ::engine::Data(Command) [file join $scratch missing.exe]
		::engine::SaveEngine $dlg.top.list
		set errsAfterBadCmd [llength $::scidb::test::englabels::errors]

		# Restore valid Command and save valid Directory -> succeeds
		set newWorkDir [file join $scratch valid-workdir]
		set ::engine::Data(Command) $exe
		set ::engine::Data(Directory) $newWorkDir
		::engine::SaveEngine $dlg.top.list
		set errsAfterGood [llength $::scidb::test::englabels::errors]
		set storedAfterGood [dict get [lindex $::engine::Engines 0] Directory]

		set ::scidb::test::englabels::dialogResult [list \
			[expr {$lcmdText eq "Command"}] \
			[expr {[string match "*Working*" $ldirText] && [string match "*Data*" $ldirText]}] \
			[expr {[string match "*engine executable*" [set $tipLcmd]] && $tipLcmd eq $tipTcmd && [string match "*Chesswiz*per-engine data*" [set $tipLdir]] && $tipLdir eq $tipEdir}] \
			[expr {$initialDir eq $storedDir}] \
			$errsAfterBadDir \
			[expr {$storedAfterBadDir eq $storedDir}] \
			$errsAfterBadCmd \
			$errsAfterGood \
			[expr {$storedAfterGood eq [file normalize $newWorkDir]}] \
			[file isdirectory $newWorkDir]]
		catch { destroy $dlg }
		after cancel $::engine::Priv(after)
	}} $dlg $scratch $exe $storedDir]
	::engine::openAdmininstration .application
	list [expr {$storedAfterSetup eq $storedDir}] {*}$::scidb::test::englabels::dialogResult
} -cleanup {
	::scidb::test::englabels::unstubError
	::scidb::test::englabels::restore
	catch { file delete -force $scratch }
} -result {1 1 1 1 1 1 1 2 2 1 1}

tcltest::cleanupTests
