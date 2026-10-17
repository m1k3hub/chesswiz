# ======================================================================
# AI: decision / override journal (System One)
# ======================================================================
# The autotune half of the calibration story (docs/SYSTEM_ONE_FEATURES.md §3.4):
# record what every gate decided, and what the user changed, so thresholds
# can be refit from real labels later.
#
#   ::ai::journal::configure -file PATH        (empty disables; env default)
#   ::ai::journal::logged <feature> <state> <script> <decision>
#       The sink ::ai::decide installs in front of the caller's script: it
#       records the decision, then delivers it unchanged.
#   ::ai::journal::decision <feature> <state> <decision>
#   ::ai::journal::override <feature> <state> <proposed> <corrected>
#   ::ai::journal::read ?file?                 -> list of record dicts
#
# Off by default. Set SCIDB_AI_JOURNAL to a file path (or call configure) to
# record; nothing here ever changes a decision, and a write failure is
# swallowed so the caller never notices.
#
# One record per line, escaped tab-separated:
#   decision <tab> time <tab> backend <tab> feature <tab> state <tab>
#            label <tab> confidence <tab> source
#   override <tab> time <tab> backend <tab> feature <tab> state <tab>
#            proposed <tab> corrected
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-journal
}

package require Tcl 8.5

namespace eval ai {
namespace eval journal {

variable File ""
if {[info exists ::env(SCIDB_AI_JOURNAL)]} { set File $::env(SCIDB_AI_JOURNAL) }

} ;# namespace journal
} ;# namespace ai


proc ::ai::journal::configure {args} {
	variable File
	array set opts {-file ""}
	array set opts $args
	set File $opts(-file)
	return
}


proc ::ai::journal::enabled {} {
	variable File
	return [expr {[string length $File] > 0}]
}


proc ::ai::journal::Escape {s} {
	set s [string map [list "\\" "\\\\"] $s]
	return [string map [list "\n" "\\n" "\r" "\\r" "\t" "\\t"] $s]
}

proc ::ai::journal::Unescape {s} {
	return [string map [list "\\n" "\n" "\\r" "\r" "\\t" "\t" "\\\\" "\\"] $s]
}


proc ::ai::journal::Append {fields} {
	variable File
	if {$File eq ""} { return }
	set line {}
	foreach value $fields { lappend line [Escape $value] }
	if {[catch {
		set chan [open $File a]
		fconfigure $chan -encoding utf-8 -translation binary
		puts $chan [join $line "\t"]
		close $chan
	}]} { return }
	return
}


proc ::ai::journal::decision {feature state decision} {
	set backend ""
	catch { set backend $::ai::systemone::Config(backend) }
	set label ""
	set confidence ""
	set source ""
	if {[dict exists $decision ok] && [dict get $decision ok]} {
		set label [expr {[dict exists $decision label] ? [dict get $decision label] : ""}]
		set confidence [expr {[dict exists $decision confidence] ? [dict get $decision confidence] : ""}]
		set source [expr {[dict exists $decision source] ? [dict get $decision source] : ""}]
	}
	Append [list decision [clock seconds] $backend $feature $state $label $confidence $source]
	return
}


proc ::ai::journal::override {feature state proposed corrected} {
	set backend ""
	catch { set backend $::ai::systemone::Config(backend) }
	Append [list override [clock seconds] $backend $feature $state $proposed $corrected]
	return
}


# The sink ::ai::decide installs before the caller's script. It records and
# then delivers, so a journaling failure cannot affect the decision.
proc ::ai::journal::logged {feature state script decision} {
	catch { ::ai::journal::decision $feature $state $decision }
	uplevel #0 [list {*}$script $decision]
	return
}


# Parse a journal file into a list of dicts. A decision has type/time/
# backend/feature/state/label/confidence/source; an override has type/time/
# backend/feature/state/proposed/corrected.
proc ::ai::journal::read {{file ""}} {
	variable File
	if {$file eq ""} { set file $File }
	if {$file eq "" || ![file exists $file]} { return {} }

	if {[catch { open $file r } chan]} { return {} }
	set text [::read $chan]
	close $chan

	set records {}
	foreach line [split $text "\n"] {
		if {$line eq ""} { continue }
		set f [lmap value [split $line "\t"] { Unescape $value }]
		switch -- [lindex $f 0] {
			decision {
				lappend records [dict create type decision \
					time [lindex $f 1] backend [lindex $f 2] feature [lindex $f 3] \
					state [lindex $f 4] label [lindex $f 5] confidence [lindex $f 6] \
					source [lindex $f 7]]
			}
			override {
				lappend records [dict create type override \
					time [lindex $f 1] backend [lindex $f 2] feature [lindex $f 3] \
					state [lindex $f 4] proposed [lindex $f 5] corrected [lindex $f 6]]
			}
		}
	}
	return $records
}

# vi:set ts=3 sw=3:
