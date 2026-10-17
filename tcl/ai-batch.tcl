# ======================================================================
# AI: batch System One (one question over many states)
# ======================================================================
# The database-wide features (event bucketing, comment language, comment
# kind, import triage) ask one bounded question over thousands of states.
# Asking them one ::ai::decide at a time re-sends a shared state once per
# game and has no resume story. This module is the missing foundation
# (docs/SYSTEM_ONE_FEATURES.md §3.3): a queue over evaluateAsync with
#
#   * a concurrency cap,
#   * de-duplication by state (identical states share one request),
#   * resume from a sidecar cache (one appended record per answer),
#   * a progress callback,
#   * a silent drop to the per-item fallback when the classifier is off,
#     errors, or disappears partway.
#
# It is deliberately policy-free: it returns each item's *raw* answer (or
# an error), and the caller applies ::ai::systemone::valid and its own
# threshold exactly as ::ai::decide would. Nothing here decides a label,
# writes data, or touches the board.
#
#   ::ai::batch::run <items> <question> <script> ?options?
#
#   <items>    a list of {key state} pairs. The key is the caller's handle;
#              the state is what the model reads (use [list $text $text]
#              when the text is its own handle).
#   <question> one question dict (the same for every state), e.g.
#              {type choice instructions "..." criteria {...}}.
#   <script>   called once, asynchronously, with
#                  {ok 1 results {key {ok 1 answer A source classifier|cache}} ...}
#              where A is the raw answer dict for <question>, or
#                  {ok 1 results {key {ok 0 error TEXT}} ...}
#              for a state that failed (the caller's fallback applies).
#
#   Options:
#     -concurrency N   maximum in-flight requests (default 2; >= 1)
#     -cache FILE      sidecar file for resume (empty disables it)
#     -progress CMD    called on every resolved state as {CMD done total}
#
# The cache is append-only and keyed by (endpoint, model, question, state),
# so a changed backend or question never reuses a stale answer, and a run
# interrupted by a crash resumes from the last persisted answer.
#
# `run` returns a run id immediately; the script fires from the event loop.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-batch
}

package require Tcl 8.5

namespace eval ai {
namespace eval batch {

variable Runs
array set Runs {seq 0}

} ;# namespace batch
} ;# namespace ai


# --- cache record encoding: keep every field on one line ---------------
proc ::ai::batch::Escape {s} {
	set s [string map [list "\\" "\\\\"] $s]
	return [string map [list "\n" "\\n" "\r" "\\r" "\t" "\\t"] $s]
}

proc ::ai::batch::Unescape {s} {
	# a single pass: at a backslash the two-character escape matches first
	return [string map [list "\\n" "\n" "\\r" "\r" "\\t" "\t" "\\\\" "\\"] $s]
}


# The cache identity of one state: it must change when the backend, the
# model or the question changes, or a stale answer would be reused.
proc ::ai::batch::CacheKey {run state} {
	return "[dict get $run endpoint]|[dict get $run model]|[dict get $run question]|$state"
}


proc ::ai::batch::LoadCache {runVar} {
	upvar $runVar run
	set path [dict get $run cacheFile]
	if {$path eq "" || ![file exists $path]} { return }

	set cache {}
	if {[catch {
		set chan [open $path r]
		fconfigure $chan -encoding utf-8 -translation binary
		set text [read $chan]
		close $chan
	}]} { return }

	foreach line [split $text "\n"] {
		if {$line eq "" || [string index $line 0] eq "#"} { continue }
		set tab [string first "\t" $line]
		if {$tab < 0} { continue }
		set key [Unescape [string range $line 0 [expr {$tab - 1}]]]
		set value [Unescape [string range $line [expr {$tab + 1}] end]]
		dict set cache $key $value
	}
	dict set run cache $cache
	return
}


proc ::ai::batch::CacheAppend {run key answer} {
	set path [dict get $run cacheFile]
	if {$path eq ""} { return }
	if {[catch {
		set chan [open $path a]
		fconfigure $chan -encoding utf-8 -translation binary
		puts $chan "[Escape $key]\t[Escape $answer]"
		close $chan
	}]} { return }
	return
}


# --- the run -----------------------------------------------------------
proc ::ai::batch::run {items question script args} {
	array set opts {-concurrency 2 -cache "" -progress {} -id q}
	array set opts $args
	if {$opts(-concurrency) < 1} { set opts(-concurrency) 1 }

	set pairs {}
	foreach item $items {
		# always an explicit {key state}: a bare string cannot be told from a
		# pair (a two-word comment would be split), so it is refused
		if {[llength $item] != 2} { error "batch item must be {key state}: $item" }
		lappend pairs [list [lindex $item 0] [lindex $item 1]]
	}

	variable Runs
	set id [incr Runs(seq)]
	set run [dict create \
		script      $script \
		question    $question \
		questionId  $opts(-id) \
		concurrency $opts(-concurrency) \
		cacheFile   $opts(-cache) \
		progress    $opts(-progress) \
		endpoint    $::ai::systemone::Config(endpoint) \
		model       $::ai::systemone::Config(model) \
		byState     {} \
		queue       {} \
		active      0 \
		results     {} \
		cache       {} \
		total       [llength $pairs] \
		done        0]

	# group keys by their state, so a shared state answers every key
	set seen {}
	set byState {}
	foreach pair $pairs {
		lassign $pair key state
		if {[dict exists $byState $state]} {
			dict set byState $state [linsert [dict get $byState $state] end $key]
		} else {
			dict set byState $state [list $key]
		}
		if {$state ni $seen} { lappend seen $state }
	}
	dict set run byState $byState

	LoadCache run
	set cache [dict get $run cache]
	foreach state $seen {
		set key [CacheKey $run $state]
		if {[dict exists $cache $key]} {
			set answer [dict get $cache $key]
			foreach handle [dict get $run byState $state] {
				dict set run results $handle [list ok 1 answer $answer source cache]
			}
			dict incr run done [llength [dict get $run byState $state]]
		} else {
			dict lappend run queue $state
		}
	}

	set Runs($id) $run
	# always resolve asynchronously: a caller may register its vwait after
	# run returns (a fully cached run must not call back before then)
	after 0 [list ::ai::batch::Pump $id]
	return $id
}


proc ::ai::batch::Pump {id} {
	variable Runs
	if {![info exists Runs($id)]} { return }
	set run $Runs($id)

	if {![::ai::systemone::enabled]} {
		Drain $id "no System One backend is configured"
		return
	}

	while {[dict get $run active] < [dict get $run concurrency] \
		&& [llength [dict get $run queue]]} {
		set state [lindex [dict get $run queue] 0]
		dict set run queue [lrange [dict get $run queue] 1 end]
		dict incr run active

		if {[catch {
			::ai::systemone::evaluateAsync $state [dict create [dict get $run questionId] [dict get $run question]] \
				[list ::ai::batch::OnOne $id $state]
		} err]} {
			# a synchronous refusal (bad question): fail this state only
			dict incr run active -1
			foreach handle [dict get $run byState $state] {
				dict set run results $handle [list ok 0 error $err]
				dict incr run done
			}
		}
	}

	set Runs($id) $run
	if {[dict get $run active] == 0 && [llength [dict get $run queue]] == 0} {
		Finish $id
	}
	return
}


# The classifier turned off, or a request failed synchronously: every queued
# state falls back; the caller sees {ok 0} per item.
proc ::ai::batch::Drain {id reason} {
	variable Runs
	set run $Runs($id)
	foreach state [dict get $run queue] {
		foreach handle [dict get $run byState $state] {
			dict set run results $handle [list ok 0 error $reason]
			dict incr run done
		}
	}
	dict set run queue {}
	set Runs($id) $run
	Finish $id
	return
}


proc ::ai::batch::OnOne {id state result} {
	variable Runs
	if {![info exists Runs($id)]} { return }
	set run $Runs($id)
	dict incr run active -1

	if {[dict get $result ok] && ![catch { dict get $result answers [dict get $run questionId] } answer]} {
		set key [CacheKey $run $state]
		dict set run cache $key $answer
		CacheAppend $run $key $answer
		foreach handle [dict get $run byState $state] {
			dict set run results $handle [list ok 1 answer $answer source classifier]
			dict incr run done
		}
	} else {
		set err [expr {[dict exists $result error] ? [dict get $result error] : "System One error"}]
		foreach handle [dict get $run byState $state] {
			dict set run results $handle [list ok 0 error $err]
			dict incr run done
		}
	}

	set Runs($id) $run
	Progress $id
	Pump $id
	return
}


proc ::ai::batch::Progress {id} {
	variable Runs
	set run $Runs($id)
	set cmd [dict get $run progress]
	if {[llength $cmd]} {
		catch { uplevel #0 [list {*}$cmd [dict get $run done] [dict get $run total]] }
	}
	return
}


proc ::ai::batch::Finish {id} {
	variable Runs
	if {![info exists Runs($id)]} { return }
	set run $Runs($id)
	unset Runs($id)
	after 0 [list {*}[dict get $run script] [list ok 1 results [dict get $run results]]]
	return
}

# vi:set ts=3 sw=3:
