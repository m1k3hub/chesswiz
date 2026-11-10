# ======================================================================
# Scidb App Test — native binding cleanup (review findings BIND-05,
# BIND-06, BIND-07): scaled image copies free their buffers, a truncated
# zlib stream is an error, and a failing progress command cancels.
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::bind {
	variable dir [file join $::env(HOME) bind-cleanup]
}

proc ::scidb::test::bind::Rss {} {
	set f [open /proc/self/status]
	set status [read $f]
	close $f
	regexp {VmRSS:\s+(\d+)} $status _ kb
	return $kb
}

proc ::scidb::test::bind::Tick {args} {}
proc ::scidb::test::bind::Cancel {args} { error "cancelled by the test" }

proc ::scidb::test::bind::Write {path data} {
	set f [open $path wb]
	puts -nonewline $f $data
	close $f
}

proc ::scidb::test::bind::Deflate {data} {
	variable dir
	file mkdir $dir
	Write [file join $dir plain] $data
	set in [open [file join $dir plain] rb]
	set out [open [file join $dir packed] wb]
	::zlib::deflate $in $out ::scidb::test::bind::Tick {}
	close $in
	close $out
	set f [open [file join $dir packed] rb]
	set packed [read $f]
	close $f
	return $packed
}

# inflate <packed> from a file, returning {rc result}
proc ::scidb::test::bind::Inflate {packed cmd} {
	variable dir
	Write [file join $dir in] $packed
	set in [open [file join $dir in] rb]
	set out [open [file join $dir out] wb]
	set rc [catch { ::zlib::inflate $in $out [string length $packed] $cmd {} } msg]
	close $in
	close $out
	return [list $rc $msg]
}

tcltest::test image-copy-scaled-frees {scaled copies with rotation or an alpha mask do not keep their buffers} -setup {
	set src [image create photo -width 200 -height 150]
	$src put #ff0000 -to 0 0 200 150
	set dst [image create photo -width 300 -height 400]
	set blend [image create photo -width 400 -height 300]
	$blend put #00ff00 -to 0 0 400 300
	# warm up the allocator
	for {set i 0} {$i < 10} {incr i} {
		::scidb::tk::image copy $src $dst -rotate 1
		::scidb::tk::image copy $src $blend -alphamask
	}
} -body {
	set before [::scidb::test::bind::Rss]
	# each leaked scaled buffer is 400*300*4 bytes, 480 KB
	for {set i 0} {$i < 100} {incr i} {
		::scidb::tk::image copy $src $dst -rotate 1
		::scidb::tk::image copy $src $blend -alphamask
	}
	set grown [expr {([::scidb::test::bind::Rss] - $before)/1024}]
	expr {$grown < 20 ? 1 : "grew $grown MB"}
} -cleanup {
	image delete $src $dst $blend
} -result 1

tcltest::test zlib-inflate-roundtrip {a complete stream inflates to the original} -body {
	set data [string repeat "chesswiz zlib test " 5000]
	lassign [::scidb::test::bind::Inflate [::scidb::test::bind::Deflate $data] ::scidb::test::bind::Tick] rc msg
	set f [open [file join $::scidb::test::bind::dir out] rb]
	set back [read $f]
	close $f
	list $rc [lindex $msg 0] [expr {$back eq $data}]
} -cleanup {
	file delete -force $::scidb::test::bind::dir
} -result {0 95000 1}

tcltest::test zlib-inflate-truncated {a stream missing its checksum is an error, not a success} -body {
	set packed [::scidb::test::bind::Deflate [string repeat "chesswiz zlib test " 5000]]
	lassign [::scidb::test::bind::Inflate [string range $packed 0 end-4] ::scidb::test::bind::Tick] rc msg
	list $rc [string match "*truncated*" $msg]
} -cleanup {
	file delete -force $::scidb::test::bind::dir
} -result {1 1}

tcltest::test zlib-progress-cancels {an error from the progress command stops inflating and is returned} -body {
	set packed [::scidb::test::bind::Deflate [string repeat "chesswiz zlib test " 5000]]
	::scidb::test::bind::Inflate $packed ::scidb::test::bind::Cancel
} -cleanup {
	file delete -force $::scidb::test::bind::dir
} -result {1 {cancelled by the test}}

tcltest::cleanupTests
