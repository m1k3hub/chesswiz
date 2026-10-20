# ======================================================================
# ::ai::precedent -- master-practice evidence for the narration prompt.
#
# Bridges the corpus index (scripts/corpus_precedent.py over a PGN corpus) to
# the language layer, so the narrator cites what masters actually played
# instead of the model's memory.
#
#   ::ai::precedent::configure -index /path/to/index.sqlite \
#                              -script /path/to/corpus_precedent.py
#   ::ai::precedent::lookup  <fen> ?-limit N?   -> dict (or {} when unknown)
#   ::ai::precedent::summary <fen> ?-limit N?   -> one-line text for a prompt
#
# The index is built offline; nothing here talks to the network, and a missing
# index simply yields no precedent rather than an error.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-precedent
}

package require Tcl 8.5

namespace eval ai {
namespace eval precedent {

variable Config
array set Config {
	index   ""
	script  ""
	python  "python3"
	limit   4
	timeout 10000
}

# Auto-discovery: a shipped/installed index and script can be pointed at once.
if {[info exists ::env(SCIDB_AI_PRECEDENT_INDEX)]}  { set Config(index)  $::env(SCIDB_AI_PRECEDENT_INDEX) }
if {[info exists ::env(SCIDB_AI_PRECEDENT_SCRIPT)]} { set Config(script) $::env(SCIDB_AI_PRECEDENT_SCRIPT) }
if {[info exists ::env(SCIDB_AI_PRECEDENT_PYTHON)]} { set Config(python) $::env(SCIDB_AI_PRECEDENT_PYTHON) }

} ;# namespace precedent
} ;# namespace ai


proc ::ai::precedent::configure {args} {
	variable Config

	foreach {key value} $args {
		switch -- $key {
			-index   { set Config(index) $value }
			-script  { set Config(script) $value }
			-python  { set Config(python) $value }
			-limit   { set Config(limit) $value }
			-timeout { set Config(timeout) $value }
			default  { error "unknown option $key" }
		}
	}
	return
}


proc ::ai::precedent::available {} {
	variable Config
	return [expr {$Config(index) ne "" && $Config(script) ne ""
	           && [file exists $Config(index)] && [file exists $Config(script)]}]
}


proc ::ai::precedent::lookup {fen args} {
	variable Config
	array set opts [list -limit $Config(limit)]
	array set opts $args

	if {![available]} { return {} }

	if {[catch {package require json}]} { return {} }

	if {[catch {
		::util::execSafe -ignorestderr $Config(python) $Config(script) query \
			--db $Config(index) --fen $fen --limit $opts(-limit)
	} out]} {
		return {}
	}

	if {[catch {set d [json::json2dict $out]}]} { return {} }
	if {![dict exists $d moves] || [llength [dict get $d moves]] == 0} { return {} }

	return $d
}


proc ::ai::precedent::summary {fen args} {
	set d [lookup $fen {*}$args]
	if {[llength $d] == 0} { return "" }

	set games [dict get $d games]
	set side  [expr {[dict get $d sideToMove] eq "black" ? "Black" : "White"}]
	set parts {}

	foreach move [lrange [dict get $d moves] 0 3] {
		lappend parts "[dict get $move move] [dict get $move share]% ([dict get $move scorePct]% for $side)"
	}

	return "$games games: [join $parts {, }]"
}
