# ======================================================================
# Scidb App Test — options-file transactions (review finding UI-05): a
# writer that fails leaves no open channel and no temporary file, the
# options file stays as it was, and the next save works.
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

proc ::scidb::test::FailingWriter {chan} { error "writer failed" }

proc ::scidb::test::Temps {} {
	set file $::scidb::file::options
	return [glob -nocomplain $file.$::options::TempSuffix]
}

tcltest::test options-writer-fails {a failing writer is aborted cleanly; the next save works} -setup {
	::options::startTransaction
	::options::saveOptionsFile
	::options::endTransaction
	set f [open $::scidb::file::options r]
	set before [read $f]
	close $f
	::options::hookWriter ::scidb::test::FailingWriter
} -body {
	set chans [llength [chan names]]
	set rc [catch {
		::options::startTransaction
		::options::saveOptionsFile
		::options::endTransaction
	} msg]
	set leaked [expr {[llength [chan names]] - $chans}]
	set temps [llength [::scidb::test::Temps]]
	set f [open $::scidb::file::options r]
	set kept [expr {[read $f] eq $before}]
	close $f
	::options::unhookWriter ::scidb::test::FailingWriter
	set again [catch {
		::options::startTransaction
		::options::saveOptionsFile
		::options::endTransaction
	}]
	list $rc $msg $leaked $temps $kept $again [llength [::scidb::test::Temps]]
} -cleanup {
	::options::unhookWriter ::scidb::test::FailingWriter
} -result {1 {writer failed} 0 0 1 0 0}

tcltest::cleanupTests
