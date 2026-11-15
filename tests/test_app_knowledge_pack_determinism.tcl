# ======================================================================
# The generated knowledge pack is session-independent (GAP-007).
#
# toolbar.database_switcher.3/.5 label themselves from the active
# database ("Close Database 'Sample games'"). A pack generated for two
# different active databases must still be byte-identical, and the pack
# title must be part of the hash so a title change is drift.
#
#   HOME=$PWD/tests/tmp-app/know-home xvfb-run -a \
#       src/tkchesswiz tests/run_app_tests.tcl -file test_app_knowledge_pack_determinism.tcl
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::packdet {
	variable root [file dirname [file dirname [file normalize [info script]]]]
	variable work [file join [file dirname [file normalize [info script]]] \
		tmp-app "knowledge-determinism-[pid]"]
	variable pack [file join [file dirname [file dirname [file normalize [info script]]]] share knowledge]

	proc ready {} {
		set deadline [expr {[clock milliseconds] + 20000}]
		while {![info exists ::application::Vars(ready)] || !$::application::Vars(ready)} {
			update
			if {[clock milliseconds] > $deadline} { error {startup timed out} }
			after 10
		}
		update
		catch { destroy .tipoftheday }
		update
		::knowledge::Ensure
	}

	proc digest {file} {
		set f [open $file r]
		fconfigure $f -translation binary
		set data [read $f]
		close $f
		return $data
	}

	proc titleOf {dir id} {
		set f [open [file join $dir actions.json] r]
		fconfigure $f -encoding utf-8
		set data [read $f]
		close $f
		set needle "\{\"id\":\"$id\",\"title\":\""
		set i [string first $needle $data]
		if {$i < 0} { return "" }
		set start [expr {$i + [string length $needle]}]
		set end [string first "\"" $data $start]
		return [string range $data $start [expr {$end - 1}]]
	}

	proc cleanup {} {
		variable work
		if {[file isdirectory $work]} {
			foreach f [glob -nocomplain -directory $work *] { catch { file delete -force $f } }
			catch { file delete -force $work }
		}
		return
	}
}

# The app bundle bakes in the installed share directory; read this
# worktree's catalogs so a language switch really loads them.
set ::scidb::test::packdet::savedShare $::scidb::dir::share
set ::scidb::test::packdet::worktreeShare [file normalize [file join \
	[file dirname [file normalize [info script]]] .. tcl]]
if {[file isdirectory [file join $::scidb::test::packdet::worktreeShare lang]]} {
	set ::scidb::dir::share $::scidb::test::packdet::worktreeShare
}

tcltest::test packdet-generation-is-session-independent {the pack is byte-identical whichever database is open} -body {
	::scidb::test::packdet::ready
	set work $::scidb::test::packdet::work
	set pack $::scidb::test::packdet::pack
	file mkdir $work
	set dirA [file join $work a]
	set dirB [file join $work b]
	::knowledge::Generate $dirA
	set baseA [::scidb::db::get name]

	# a second database with a different name drives the toolbar labels
	set file [file join $work "term3 other.sci"]
	::application::database::newBase . normal $file
	update
	set baseB [::scidb::db::get name]
	::knowledge::Generate $dirB

	set same 1
	foreach name {actions.json topics.json registry.sha256 README.txt} {
		if {[::scidb::test::packdet::digest [file join $dirA $name]] ne \
			[::scidb::test::packdet::digest [file join $dirB $name]]} {
			puts "  differs: $name"
			set same 0
		}
	}
	set titles [list [::scidb::test::packdet::titleOf $dirA toolbar.database_switcher.3] \
		[::scidb::test::packdet::titleOf $dirA toolbar.database_switcher.5] \
		[::scidb::test::packdet::titleOf $dirB toolbar.database_switcher.3]]

	catch { ::application::database::CloseBase . $file }
	update
	list $same [expr {$baseA ne $baseB}] {*}$titles
} -result {1 1 {Close current database} {Database read-only mode} {Close current database}}

tcltest::test packdet-repo-pack-is-current {the committed pack has the generic titles and matches the registry} -body {
	::scidb::test::packdet::ready
	set pack $::scidb::test::packdet::pack
	set title3 [::scidb::test::packdet::titleOf $pack toolbar.database_switcher.3]
	set title5 [::scidb::test::packdet::titleOf $pack toolbar.database_switcher.5]
	set drift [::knowledge::Drift $pack]
	set hash [::knowledge::RegistryHash]
	list $title3 $title5 $drift [expr {$hash ne ""}] [string length $hash]
} -result {{Close current database} {Database read-only mode} {} 1 64}

tcltest::test packdet-hash-is-language-independent {the hash follows the text, not the UI language} -body {
	::scidb::test::packdet::ready
	set saved $::mc::langID
	::mc::setLang en
	set en [::knowledge::RegistryHash]
	::mc::setLang de
	set de [::knowledge::RegistryHash]
	::mc::setLang $saved
	list [expr {$en eq $de}] [string length $en]
} -result {1 64}

::tcltest::cleanupTests
