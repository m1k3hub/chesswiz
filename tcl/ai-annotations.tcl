# ======================================================================
# ::ai::annotations -- human/engine annotation exemplars for a position.
#
# Retrieves how a corpus annotated similar positions, joined by position key
# with the precedent index.  This gives the narrator real annotation
# vocabulary ("Inaccuracy. h5 was best.") grounded in the corpus.
#
#   ::ai::annotations::configure -index /path/annotations.sqlite -script ...
#   ::ai::annotations::lookup  <fen> ?-limit N?  -> dict (or {} when none)
#   ::ai::annotations::summary <fen> ?-limit N?  -> one-line text
#
# A missing index yields {} rather than an error.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-annotations
}

package require Tcl 8.5

namespace eval ai {
namespace eval annotations {

variable Config
array set Config {
	index   ""
	script  ""
	python  "python3"
	limit   2
	english 1
}

if {[info exists ::env(SCIDB_AI_ANNOTATIONS_INDEX)]}  { set Config(index)  $::env(SCIDB_AI_ANNOTATIONS_INDEX) }
if {[info exists ::env(SCIDB_AI_ANNOTATIONS_SCRIPT)]} { set Config(script) $::env(SCIDB_AI_ANNOTATIONS_SCRIPT) }

} ;# namespace annotations
} ;# namespace ai


proc ::ai::annotations::configure {args} {
	variable Config

	foreach {key value} $args {
		switch -- $key {
			-index  { set Config(index) $value }
			-script { set Config(script) $value }
			-python { set Config(python) $value }
			-limit  { set Config(limit) $value }
			-english { set Config(english) $value }
			default { error "unknown option $key" }
		}
	}
	return
}


proc ::ai::annotations::available {} {
	variable Config
	return [expr {$Config(index) ne "" && $Config(script) ne ""
	           && [file exists $Config(index)] && [file exists $Config(script)]}]
}


proc ::ai::annotations::lookup {fen args} {
	variable Config
	array set opts [list -limit $Config(limit)]
	array set opts $args

	if {![available]} { return {} }
	if {[catch {package require json}]} { return {} }

	if {[catch {
		set cmd [list $Config(python) $Config(script) query \
			--db $Config(index) --fen $fen --limit $opts(-limit)]
		if {$Config(english)} { lappend cmd --english }
		::util::execSafe -ignorestderr {*}$cmd
	} out]} {
		return {}
	}

	if {[catch {set d [json::json2dict $out]}]} { return {} }
	if {![dict exists $d annotations] || [llength [dict get $d annotations]] == 0} { return {} }

	return $d
}


proc ::ai::annotations::summary {fen args} {
	set d [lookup $fen {*}$args]
	if {[llength $d] == 0} { return "" }

	set parts {}
	foreach a [lrange [dict get $d annotations] 0 1] {
		set c [dict get $a comment]
		set n [dict get $a nags]
		if {[string length $c] > 90} { set c "[string range $c 0 87]..." }
		if {$c eq ""} { continue }
		lappend parts "\"$c\"[expr {[llength $n] ? " (NAG [join $n {,}])" : ""}]"
	}

	if {[llength $parts] == 0} { return "" }
	return [join $parts {; }]
}
