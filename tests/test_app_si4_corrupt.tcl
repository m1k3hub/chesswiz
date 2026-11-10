# ======================================================================
# Scidb App Test — corrupt Scid 4 bases (review findings DB-12, DB-13):
# an index that declares more games than it holds is rejected before
# allocating them, and a name may only reuse bytes of the previous name.
# The fixture tests/data/si4/endings.* is from Scid vs PC (GPL).
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::si4 {
	variable fixture [file join [file dirname [file normalize [info script]]] data si4]
	variable dir [file join $::env(HOME) si4-corrupt]
}

# copy the fixture to <name>.*, then overwrite bytes of one file
proc ::scidb::test::si4::Copy {name} {
	variable fixture
	variable dir
	file mkdir $dir
	foreach ext {si4 sn4 sg4} {
		file copy -force [file join $fixture endings.$ext] [file join $dir $name.$ext]
	}
	return [file join $dir $name.si4]
}

proc ::scidb::test::si4::Patch {path offset bytes {cut 0}} {
	set f [open $path rb]
	set data [read $f]
	close $f
	set data [string replace $data $offset [expr {$offset + [string length $bytes] + $cut - 1}] $bytes]
	set f [open $path wb]
	puts -nonewline $f $data
	close $f
}

proc ::scidb::test::si4::Open {path} {
	set rc [catch { ::scidb::db::load $path {list} {} -readonly 1 } msg]
	catch { ::scidb::db::close $path }
	return [list $rc $msg]
}

tcltest::test si4-intact {the unmodified fixture opens} -body {
	lindex [::scidb::test::si4::Open [::scidb::test::si4::Copy intact]] 0
} -cleanup {
	file delete -force $::scidb::test::si4::dir
} -result 0

tcltest::test si4-game-count {an index declaring 16 million games is rejected by its size} -body {
	set si4 [::scidb::test::si4::Copy count]
	# the game count is a big-endian 24-bit value at offset 14
	::scidb::test::si4::Patch $si4 14 [binary format cu3 {255 255 255}]
	lassign [::scidb::test::si4::Open $si4] rc msg
	list $rc [string match "*declares 16777215 games*" $msg]
} -cleanup {
	file delete -force $::scidb::test::si4::dir
} -result {1 1}

tcltest::test si4-name-prefix {a name reusing more bytes than the previous name had is rejected} -body {
	set si4 [::scidb::test::si4::Copy prefix]
	# site 3 ("problem solved": length 14, prefix 8, suffix "solved" at 86)
	# becomes length 20, prefix 20, no suffix; site 2 has only 14 bytes
	::scidb::test::si4::Patch [file rootname $si4].sn4 84 [binary format cc 20 20] 6
	lassign [::scidb::test::si4::Open $si4] rc msg
	list $rc [string match "*namebase file is broken*" $msg]
} -cleanup {
	file delete -force $::scidb::test::si4::dir
} -result {1 1}

tcltest::cleanupTests
