# ======================================================================
# Scidb App Test — comment language override hook (tcl/comment.tcl)
# ======================================================================
# The classifier proposes a language; if the user switches to a different one,
# NoteLanguageOverride records it in the decision journal for autotune.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::clang {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app lang_[pid]]
}

proc ::scidb::test::clang::clear {} {
	unset -nocomplain ::comment::Vars(detectedLang) ::comment::Vars(detectedText) \
		::comment::Vars(detectText)
}

tcltest::test lang-override-recorded {a switch away from the detected language is recorded} -body {
	set dir $::scidb::test::clang::Dir
	file delete -force $dir
	file mkdir $dir
	set file [file join $dir journal.txt]
	::scidb::test::clang::clear
	::ai::journal::configure -file $file
	set ::comment::Vars(detectedLang) de
	set ::comment::Vars(detectedText) "Der Springer gabelt Koenig und Turm."
	::comment::NoteLanguageOverride en
	set recs [::ai::journal::read $file]
	::ai::journal::configure -file ""
	list [llength $recs] [dict get [lindex $recs 0] type] \
		[dict get [lindex $recs 0] feature] [dict get [lindex $recs 0] proposed] \
		[dict get [lindex $recs 0] corrected] \
		[expr {[info exists ::comment::Vars(detectedLang)] ? 1 : 0}]
} -result {1 override language de en 0}

tcltest::test lang-override-same {switching to the proposed language records nothing} -body {
	set file [file join $::scidb::test::clang::Dir journal2.txt]
	file delete -force $file
	::scidb::test::clang::clear
	::ai::journal::configure -file $file
	set ::comment::Vars(detectedLang) de
	set ::comment::Vars(detectedText) "text"
	::comment::NoteLanguageOverride de
	set n [expr {[file exists $file] ? [llength [::ai::journal::read $file]] : 0}]
	::ai::journal::configure -file ""
	::scidb::test::clang::clear
	set n
} -result {0}

tcltest::test lang-override-none {no detection marker means nothing is recorded} -body {
	set file [file join $::scidb::test::clang::Dir journal3.txt]
	file delete -force $file
	::scidb::test::clang::clear
	::ai::journal::configure -file $file
	::comment::NoteLanguageOverride en
	set n [expr {[file exists $file] ? [llength [::ai::journal::read $file]] : 0}]
	::ai::journal::configure -file ""
	set n
} -result {0}
