# ======================================================================
# Scidb App Test — malformed CBV archives (review findings DB-01, DB-02):
# a member name with "../" must not write outside the extraction folder,
# and a member table larger than the file is rejected before it is read.
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::cbv {
	variable dir [file join $::env(HOME) cbv-archive]
}

# header: size 8, entry count, record size 172, version 1; then the records
proc ::scidb::test::cbv::Write {path count records payload} {
	set f [open $path wb]
	puts -nonewline $f [binary format ssss 8 $count 172 1]
	puts -nonewline $f $records
	puts -nonewline $f $payload
	close $f
}

proc ::scidb::test::cbv::Record {name size} {
	set rec [binary format a132ii $name $size $size]
	return [binary format a172 $rec]
}

proc ::scidb::test::cbv::Open {path} {
	set rc [catch { ::scidb::db::load $path {list} {} -readonly 1 } msg]
	catch { ::scidb::db::close $path }
	return [list $rc $msg]
}

tcltest::test cbv-member-escape {a member named ../x is refused, nothing is written outside} -setup {
	set dir $::scidb::test::cbv::dir
	file mkdir $dir
	set cbv [file join $dir escape.cbv]
	# the archive is extracted into a new /tmp/scidb-cbv-XXXXXX, so ../ is /tmp
	set name chesswiz-escaped-[pid].txt
	::scidb::test::cbv::Write $cbv 1 [::scidb::test::cbv::Record ../$name 16] [string repeat x 16]
} -body {
	lassign [::scidb::test::cbv::Open $cbv] rc msg
	list $rc [file exists /tmp/$name] [string match "*not a plain file name*" $msg]
} -cleanup {
	file delete -force $dir /tmp/$name
} -result {1 0 1}

tcltest::test cbv-truncated-table {an entry table past the end of the file is rejected} -setup {
	set dir $::scidb::test::cbv::dir
	file mkdir $dir
	set cbv [file join $dir short.cbv]
	::scidb::test::cbv::Write $cbv 5 {} {}
} -body {
	lassign [::scidb::test::cbv::Open $cbv] rc msg
	list $rc [string match "*member table extends past end of file*" $msg]
} -cleanup {
	file delete -force $dir
} -result {1 1}

# review findings DB-06/DB-07: incomplete blocks are errors, not empty output
tcltest::test cbv-truncated-block {a member ending inside a block header is rejected} -setup {
	set dir $::scidb::test::cbv::dir
	file mkdir $dir
	set cbv [file join $dir block.cbv]
	::scidb::test::cbv::Write $cbv 1 [::scidb::test::cbv::Record a.cbh 3] xxx
} -body {
	lassign [::scidb::test::cbv::Open $cbv] rc msg
	list $rc [string match "*block header is truncated*" $msg]
} -cleanup {
	file delete -force $dir
} -result {1 1}

tcltest::test cbv-truncated-huffman {Huffman data that runs out is rejected, not padded with zero bits} -setup {
	set dir $::scidb::test::cbv::dir
	file mkdir $dir
	set cbv [file join $dir huffman.cbv]
	# block of 4 bytes: Huffman flag, decoded size 100, one byte of tree
	set block [binary format ssccc 4 0 2 0 100][binary format c 0]
	::scidb::test::cbv::Write $cbv 1 [::scidb::test::cbv::Record a.cbh 8] $block
} -body {
	lassign [::scidb::test::cbv::Open $cbv] rc msg
	list $rc [string match "*Huffman block is truncated*" $msg]
} -cleanup {
	file delete -force $dir
} -result {1 1}

tcltest::cleanupTests
