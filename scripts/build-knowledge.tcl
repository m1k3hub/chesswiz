# ======================================================================
# Generate the Chesswiz knowledge pack (share/knowledge/) from the live
# action registry and the hand-written topic pages (VAL-KNOW-002).
#
#   xvfb-run -a src/tkchesswiz scripts/build-knowledge.tcl --out share/knowledge
#
# Deterministic: two runs over the same registry write byte-identical
# files. `--check` compares the pack with the registry instead, and exits
# non-zero when the pack is stale (used by `make knowledge-check`).
# ======================================================================

set root [file dirname [file dirname [file normalize [info script]]]]

# Tk destroys .application during exit; its normal Destroy binding calls
# exit again without a status. Remove that UI-only hook for this CLI.
proc knowledgeBuildExit {status} {
    if {[winfo exists .application]} { bind .application <Destroy> {} }
    ::exit $status
}

set argvCopy $argv
set argcCopy $argc
set argv {--single-process}
set argc 1
set ::env(SCIDB_AI_TRIAGE) 0
set ::env(SCIDB_ERROR_LOG) [file join $root tests tmp-app knowledge-errors.log]
source -encoding utf-8 [file join $root tcl chesswiz]
set ::scidb::dir::setup 0
set argv $argvCopy
set argc $argcCopy

array set opt {-out "" -check 0}
for {set i 0} {$i < [llength $argv]} {incr i} {
	switch -- [lindex $argv $i] {
		--out { incr i; set opt(-out) [lindex $argv $i] }
		--check { set opt(-check) 1 }
		default {
			puts stderr "build-knowledge.tcl: unknown option [lindex $argv $i]"
			knowledgeBuildExit 2
		}
	}
}
if {$opt(-out) eq ""} { set opt(-out) [file join $root share knowledge] }

set deadline [expr {[clock milliseconds] + 20000}]
while {![info exists ::application::Vars(ready)] || !$::application::Vars(ready)} {
	update
	if {[clock milliseconds] > $deadline} {
		puts stderr "build-knowledge.tcl: startup timed out"
		knowledgeBuildExit 1
	}
	after 10
}
update
catch { destroy .tipoftheday }
update

if {[catch { ::knowledge::Ensure } err]} {
	puts stderr "build-knowledge.tcl: $err"
	knowledgeBuildExit 1
}

if {$opt(-check)} {
	set stale [::knowledge::Drift $opt(-out)]
	if {$stale ne ""} {
		puts stderr $stale
		knowledgeBuildExit 1
	}
	puts "knowledge pack is current: $opt(-out)"
	knowledgeBuildExit 0
}

if {[catch { ::knowledge::Generate $opt(-out) } path]} {
	puts stderr "build-knowledge.tcl: $path"
	knowledgeBuildExit 1
}
puts "knowledge pack: $path"
puts "actions: [llength [::knowledge::PackIds]]"
puts "topics: [llength [::knowledge::PackTopicList]]"
puts "hash: [::knowledge::RegistryHash]"
knowledgeBuildExit 0
