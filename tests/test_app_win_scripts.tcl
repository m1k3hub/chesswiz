# ======================================================================
# Scidb App Test — ::platform::sys::WinScript (review finding B15): the
# Windows helper scripts live in a directory of this process, are written
# once, and never land in the working directory. The proc is plain Tcl,
# so it is tested here with a scratch TEMP.
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::winscript {}

proc ::scidb::test::winscript::isolated {body} {
	set saved [array get ::env {T[EM][MP]*}]
	catch { unset ::platform::sys::WinScriptDir }
	array unset ::platform::sys::WinScripts
	set rc [catch { uplevel 1 $body } result]
	catch { file delete -force $::platform::sys::WinScriptDir }
	catch { unset ::platform::sys::WinScriptDir }
	array unset ::platform::sys::WinScripts
	unset -nocomplain ::env(TEMP) ::env(TMP)
	array set ::env $saved
	if {$rc} { return -code error $result }
	return $result
}

tcltest::test win-script-private-dir {helpers go into a directory of this process} -body {
	::scidb::test::winscript::isolated {
		set tmp [file join $::env(HOME) winscript-temp]
		file mkdir $tmp
		set ::env(TEMP) $tmp
		# a helper another instance wrote under the old shared name
		set f [open [file join $tmp chesswiz-print.vbs] w]; puts $f "other"; close $f
		set a [::platform::sys::WinScript print "body one"]
		set again [::platform::sys::WinScript print "body one"]
		set f [open $a]; set text [read $f]; close $f
		set f [open [file join $tmp chesswiz-print.vbs]]; set other [string trim [read $f]]; close $f
		list [string match "$tmp/chesswiz-[pid]-*" [file dirname $a]] [expr {$a eq $again}] $text $other
	}
} -cleanup {
	file delete -force [file join $::env(HOME) winscript-temp]
} -result {1 1 {body one} other}

tcltest::test win-script-no-cwd {without a temporary directory there is no helper} -body {
	::scidb::test::winscript::isolated {
		unset -nocomplain ::env(TEMP) ::env(TMP)
		list [catch { ::platform::sys::WinScript print "x" } msg] \
			[file exists [file join [pwd] chesswiz-print.vbs]]
	}
} -result {1 0}

tcltest::cleanupTests
