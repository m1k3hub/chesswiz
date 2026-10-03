# ======================================================================
# ::ai::positions -- the position finder's engine side
# (ASSISTANT_COVERAGE_MAP.md §5).
#
# A model drafts a CQL 6.2 script for a player's request; this module runs
# it with the embedded CQL 6.2 engine over a view the caller has narrowed
# by header fields, and turns the matches into positions. CQL decides what
# matches; the model only translated the request, and every result carries
# the script so the player can see and edit it.
#
#   ::ai::positions::normalize <script>
#       -> the script with a cql() header, code fences and blank ends removed
#   ::ai::positions::search <base> <variant> <view> <script> <callback> ?-max N? ?-budget MS?
#       runs the search; <callback> gets {ok 1 matches {game ply ...}
#       complete 0|1 searched N} or {ok 0 error E}. -max stops after N
#       matches (a probe); -budget cancels after MS milliseconds, and the
#       matches found by then come back with complete 0.
#   ::ai::positions::cancel
#   ::ai::positions::position <base> <variant> <game> <ply>
#       -> {fen F move M next N}: the position after <ply> half-moves of the
#       game's main line, the move that led there ("24.Rxd4", "" at the
#       start) and the move played from there ("" at the end)
#   ::ai::positions::savePattern <name> <request> <script> <fens>
#   ::ai::positions::patterns
#       the user's patterns: scripts the user accepted, with the positions
#       they accepted as fixtures (§5.4); a list of dicts {name request cql
#       fens saved}. Never indexed, never vetted: people promote them.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-positions
}

package require Tcl 8.5

namespace eval ai {
namespace eval positions {

# The scratch game slot (ai-cql uses 31, ai-studyplan 30).
variable Slot 29

variable Priv
array set Priv {
	job		{}
	timer		{}
	serial	0
}

} ;# namespace positions
} ;# namespace ai


proc ::ai::positions::normalize {script} {
	set script [string trim $script]
	# a model may wrap the script in a Markdown code fence
	regsub {^```[a-zA-Z]*\s*} $script {} script
	regsub {\s*```$} $script {} script
	set script [string trim $script]
	if {![regexp {^cql\s*\(} $script]} { set script "cql()\n$script" }
	return $script
}


proc ::ai::positions::search {base variant view script callback args} {
	variable Priv

	array set opts {-max 0 -budget 0}
	array set opts $args

	if {$Priv(job) ne ""} {
		after 0 [list {*}$callback [dict create ok 0 error "a position search is already running"]]
		return
	}
	set serial [incr Priv(serial)]
	set options [list -view $view -compact 1]
	if {$opts(-max) > 0} { lappend options -max $opts(-max) }
	if {[catch {
		set Priv(job) [::scidb::cql6::search $base $variant [normalize $script] {*}$options \
			-command [namespace code [list Done $serial $callback]]]
	} err]} {
		set Priv(job) {}
		after 0 [list {*}$callback [dict create ok 0 error $err]]
		return
	}
	if {$opts(-budget) > 0} {
		set Priv(timer) [after $opts(-budget) [namespace code [list Expire $serial]]]
	}
	return
}


proc ::ai::positions::cancel {} {
	variable Priv
	if {$Priv(job) ne ""} { catch { ::scidb::cql6::cancel $Priv(job) } }
}


proc ::ai::positions::Expire {serial} {
	variable Priv
	if {$serial == $Priv(serial)} { cancel }
}


proc ::ai::positions::Done {serial callback result} {
	variable Priv

	if {$serial == $Priv(serial)} {
		after cancel $Priv(timer)
		set Priv(timer) {}
		set Priv(job) {}
	}
	if {![dict get $result ok]} {
		set answer [dict create ok 0 error [dict get $result error]]
	} else {
		set answer [dict create ok 1 \
			matches [dict get $result matches] \
			complete [expr {![dict get $result cancelled]}] \
			searched [dict get $result games]]
	}
	uplevel #0 [list {*}$callback $answer]
}


proc ::ai::positions::position {base variant game ply} {
	variable Slot

	if {![::scidb::game::query $Slot open?]} { ::scidb::game::new $Slot }
	::scidb::game::load $Slot $base $variant $game
	# {key san fen-before-the-move} per ply of the main line
	set plies [::scidb::game::query $Slot mainline]
	set n [llength $plies]
	if {$ply < 0 || $ply > $n} { error "no ply $ply in game [expr {$game + 1}]" }

	if {$ply < $n} {
		lassign [lindex $plies $ply] _ next fen
	} else {
		set next ""
		set fen [::scidb::game::query $Slot fen]
		if {$n > 0} {
			lassign [lindex $plies end] _ san before
			regexp {"fenAfter":"([^"]+)"} [::scidb::ai::moveFacts $san $before] -> fen
		}
	}
	set move ""
	if {$ply > 0} {
		# the number and the side from the position before the move (a game
		# may start anywhere); not through expr, which reads "5.e5" as 500000.0
		lassign [lindex $plies [expr {$ply - 1}]] _ san before
		set number [lindex $before 5]
		if {![string is integer -strict $number]} { set number [expr {($ply - 1) / 2 + 1}] }
		if {[lindex $before 1] eq "b"} {
			set move "$number...$san"
		} else {
			set move "$number.$san"
		}
	}
	return [dict create fen $fen move $move next $next]
}


proc ::ai::positions::PatternFile {} {
	if {![info exists ::scidb::dir::user]} { return "" }
	return [file join $::scidb::dir::user ai patterns.dat]
}


proc ::ai::positions::patterns {} {
	set file [PatternFile]
	if {$file eq "" || ![file readable $file]} { return {} }
	if {[catch {
		set chan [open $file r]
		fconfigure $chan -encoding utf-8
		set data [read $chan]
		close $chan
	}]} { return {} }
	# a damaged file must not break anything that lists the patterns
	return [lmap p $data { if {[catch { dict get $p cql }]} continue; set p }]
}


# Save (or replace, by name) a pattern; returns the number saved.
proc ::ai::positions::savePattern {name request script fens} {
	set file [PatternFile]
	if {$file eq ""} { error "no user folder to save patterns in" }
	set name [string trim $name]
	if {$name eq ""} { error "a pattern needs a name" }
	set all [lmap p [patterns] { if {[dict get $p name] eq $name} continue; set p }]
	lappend all [dict create name $name request $request cql [normalize $script] fens $fens \
		saved [clock format [clock seconds] -format %Y-%m-%d]]
	file mkdir [file dirname $file]
	set chan [open $file.tmp w]
	fconfigure $chan -encoding utf-8
	puts $chan $all
	close $chan
	file rename -force $file.tmp $file
	return [llength $all]
}
