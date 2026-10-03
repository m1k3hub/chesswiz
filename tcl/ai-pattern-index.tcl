# ======================================================================
# ::ai::patternIndex -- the vetted patterns' matches, precomputed per
# database (PATTERN_INDEX_PLAN.md, first version).
#
# A pattern search decodes every game: about three minutes for one pattern
# on 1.2 million games. Evaluating all library patterns in one pass costs
# about the same as evaluating one (the decoding dominates), so the first
# pattern search on a big database builds the index for all of them, and
# every later one is answered from it. The index lives in the user's
# directory, never beside the database (which may be read-only).
#
# An index answers only while it is valid: the same database file (size
# and modification time), the same game count, the database not modified
# since loading, the same CQL engine version, and the same pattern script
# (each pattern carries a checksum of its script). Otherwise the caller
# scans, so the results are always those of a scan.
#
# When the database file changed, the index is brought up to date instead
# of rebuilt where it can be: it keeps a CRC of every game's stored record
# (::scidb::db::fingerprints; Scidb and Scid formats), so only the games
# added since and the games whose record changed are searched again -- a
# weekly download into a big database costs seconds, not minutes. Fewer
# games than before (a compaction), a quarter of them changed, a library
# that changed, or a format without fingerprints: a full build.
#
#   ::ai::patternIndex::wanted <base> <variant>
#       -> whether building pays: a big, unmodified Normal database
#   ::ai::patternIndex::updatable <base> <variant>
#       -> whether an out-of-date index can be brought up to date
#   ::ai::patternIndex::lookup <base> <variant> <id>
#       -> {game first_ply ...} of library pattern <id>, or an error when
#       the database has no valid index for it (check with has)
#   ::ai::patternIndex::has <base> <variant> <id>
#   ::ai::patternIndex::build <base> <variant> <callback>
#       evaluates all library patterns over the whole database (or over the
#       games an update needs) in the background; <callback> gets {ok 1},
#       {ok 0 cancelled 1 error E} or {ok 0 error E}. A build already
#       running for the database takes the callback too. Returns the CQL job
#       (::scidb::cql6::cancel stops it), or "" when there is none.
#   ::ai::patternIndex::cancel <base>
#   ::ai::patternIndex::building <base>
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-pattern-index
}

package require Tcl 8.6

namespace eval ai {
namespace eval patternIndex {

# the smallest database worth an index (SCIDB_AI_PATTERN_INDEX_MIN_GAMES)
variable MinGames 100000
variable Format 2

# an update searches at most this share of the games (else a full build)
variable UpdateShare 0.25

# Loaded[base]: {identity {id {hash pairs} ...} fingerprints}
variable Loaded
array set Loaded {}
# Jobs[base]: {job callbacks}
variable Jobs
array set Jobs {}
# Plans[base]: {identity plan}, the update plan for the database as it is
variable Plans
array set Plans {}

} ;# namespace patternIndex
} ;# namespace ai


proc ::ai::patternIndex::MinGames {} {
	variable MinGames
	if {[info exists ::env(SCIDB_AI_PATTERN_INDEX_MIN_GAMES)]
	 && [string is integer -strict $::env(SCIDB_AI_PATTERN_INDEX_MIN_GAMES)]} {
		return $::env(SCIDB_AI_PATTERN_INDEX_MIN_GAMES)
	}
	return $MinGames
}


proc ::ai::patternIndex::Usable {base variant} {
	if {$variant ne "Normal" || ![llength [info commands ::scidb::cql6::search]]} { return 0 }
	if {[::scidb::cql6::version] eq "cql6 stub 6.2"} { return 0 }
	if {![file isfile $base]} { return 0 }
	if {[catch { ::scidb::db::get unsaved? $base } unsaved] || $unsaved} { return 0 }
	return 1
}


proc ::ai::patternIndex::wanted {base variant} {
	if {![Usable $base $variant]} { return 0 }
	if {[catch { ::scidb::db::count games $base $variant } count]} { return 0 }
	return [expr {$count >= [MinGames]}]
}


# What the index must agree with to answer for <base>.
proc ::ai::patternIndex::Identity {base variant} {
	variable Format
	file stat $base st
	return [list format $Format base [file normalize $base] size $st(size) mtime $st(mtime) \
		games [::scidb::db::count games $base $variant] engine [::scidb::cql6::version]]
}


proc ::ai::patternIndex::Hash {script} {
	return [format %08x [zlib crc32 $script]]
}


proc ::ai::patternIndex::File {base} {
	if {![info exists ::scidb::dir::user]} { return "" }
	set path [file normalize $base]
	set name [format %08x-%s.scp [zlib crc32 $path] [file rootname [file tail $path]]]
	return [file join $::scidb::dir::user ai pattern-index $name]
}


# The index of <base> as {identity patterns fingerprints}, read from its
# file once; {} when there is none or it cannot be read.
proc ::ai::patternIndex::Load {base} {
	variable Loaded

	set key [file normalize $base]
	if {[info exists Loaded($key)]} { return $Loaded($key) }
	set file [File $base]
	if {$file eq "" || ![file isfile $file]} { return {} }
	if {[catch {
		set chan [open $file rb]
		try {
			set identity [encoding convertfrom utf-8 [gets $chan]]
			set index [encoding convertfrom utf-8 [gets $chan]]
			set bytes [gets $chan]
			if {![string is integer -strict $bytes]} { error "not an index of this format" }
			set patterns {}
			foreach {id hash count} $index {
				set data [read $chan [expr {8 * $count}]]
				if {[string length $data] != 8 * $count} { error "truncated" }
				binary scan $data i* pairs
				dict set patterns $id [list $hash $pairs]
			}
			set fingerprints [read $chan $bytes]
			if {[string length $fingerprints] != $bytes} { error "truncated" }
		} finally {
			close $chan
		}
	}]} {
		return {}
	}
	set Loaded($key) [list $identity $patterns $fingerprints]
	return $Loaded($key)
}


# The CRC of every game's record, or "" when the format has none.
proc ::ai::patternIndex::Fingerprints {base variant} {
	if {[catch { ::scidb::db::fingerprints $base $variant } fingerprints]} { return "" }
	return $fingerprints
}


# How to bring the index of <base> up to date: {identity I fingerprints F
# games {number ...}}, the games to search again (changed or added); {}
# when the index is current, missing, or needs a full build.
proc ::ai::patternIndex::Plan {base variant} {
	variable Plans
	variable UpdateShare

	if {![Usable $base $variant]} { return {} }
	set index [Load $base]
	if {![llength $index] || [catch { Identity $base $variant } identity]} { return {} }
	lassign $index old patterns fingerprints
	if {$old eq $identity} { return {} }
	set key [file normalize $base]
	if {[info exists Plans($key)] && [lindex $Plans($key) 0] eq $identity} {
		return [lindex $Plans($key) 1]
	}
	set plan {}
	set count [dict get $identity games]
	set before [dict get $old games]
	set library [dict create]
	foreach id [::ai::search::patternIds] { dict set library $id [Hash [::ai::search::pattern6 $id]] }
	set same [expr {[dict size $library] == [dict size $patterns]}]
	dict for {id entry} $patterns {
		if {![dict exists $library $id] || [dict get $library $id] ne [lindex $entry 0]} { set same 0 }
	}
	if {$same && $fingerprints ne "" && $count >= $before
	 && [dict get $old engine] eq [dict get $identity engine]
	 && [dict get $old format] eq [dict get $identity format]
	 && ![catch { ::scidb::db::fingerprints $base $variant $fingerprints } diff]} {
		lassign $diff now changed
		set games $changed
		for {set n $before} {$n < $count} {incr n} { lappend games $n }
		if {[llength $games] <= max(2000, $UpdateShare * $count)} {
			set plan [dict create identity $identity fingerprints $now games $games]
		}
	}
	set Plans($key) [list $identity $plan]
	return $plan
}


proc ::ai::patternIndex::updatable {base variant} {
	return [expr {[llength [Plan $base $variant]] > 0}]
}


proc ::ai::patternIndex::Valid {base variant} {
	if {![Usable $base $variant]} { return {} }
	set index [Load $base]
	if {![llength $index] || [catch { Identity $base $variant } identity]} { return {} }
	if {[lindex $index 0] ne $identity} { return {} }
	return [lindex $index 1]
}


proc ::ai::patternIndex::has {base variant id} {
	set patterns [Valid $base $variant]
	if {![dict exists $patterns $id]} { return 0 }
	if {[catch { ::ai::search::pattern6 $id } script]} { return 0 }
	return [expr {[lindex [dict get $patterns $id] 0] eq [Hash $script]}]
}


proc ::ai::patternIndex::lookup {base variant id} {
	if {![has $base $variant $id]} { error "no valid pattern index for '$id'" }
	return [lindex [dict get [Valid $base $variant] $id] 1]
}


proc ::ai::patternIndex::building {base} {
	variable Jobs
	return [info exists Jobs([file normalize $base])]
}


proc ::ai::patternIndex::build {base variant callback} {
	variable Jobs

	set key [file normalize $base]
	if {[info exists Jobs($key)]} {
		lset Jobs($key) 1 [linsert [lindex $Jobs($key) 1] end $callback]
		return [lindex $Jobs($key) 0]
	}
	if {![Usable $base $variant]} {
		after 0 [list {*}$callback [dict create ok 0 error "this database cannot be indexed"]]
		return ""
	}
	set ids [::ai::search::patternIds]
	set scripts [lmap id $ids { ::ai::search::pattern6 $id }]
	set plan [Plan $base $variant]
	set view {}
	if {[llength $plan]} {
		set identity [dict get $plan identity]
		set fingerprints [dict get $plan fingerprints]
		set games [dict get $plan games]
		if {![llength $games]} {
			# the file changed, no game did
			set Jobs($key) [list {} [list $callback]]
			after 0 [namespace code [list Built $base $variant $identity $ids $scripts \
				[dict create fingerprints $fingerprints games {} update 1] {} \
				[dict create ok 1 cancelled 0 matches {}]]]
			return ""
		}
	} else {
		set identity [Identity $base $variant]
		set fingerprints [Fingerprints $base $variant]
	}
	if {[catch {
		set options {}
		if {[llength $plan]} {
			set view [::scidb::view::new $base $variant unused unused unused unused master slave]
			::scidb::view::setGames $base $variant $view $games
			lappend options -view $view
		}
		set job [::scidb::cql6::search $base $variant [lindex $scripts 0] \
			-scripts [lrange $scripts 1 end] -compact 1 {*}$options \
			-command [namespace code [list Built $base $variant $identity $ids $scripts \
				[dict create fingerprints $fingerprints games [expr {[llength $plan] ? $games : {}}] \
					update [llength $plan]] $view]]]
	} err]} {
		if {$view ne ""} { catch { ::scidb::view::close $base $variant $view } }
		after 0 [list {*}$callback [dict create ok 0 error $err]]
		return ""
	}
	set Jobs($key) [list $job [list $callback]]
	return $job
}


proc ::ai::patternIndex::cancel {base} {
	variable Jobs
	set key [file normalize $base]
	if {[info exists Jobs($key)]} { catch { ::scidb::cql6::cancel [lindex $Jobs($key) 0] } }
}


# <plan>: {fingerprints F games G update 0|1}; an update merges the
# matches in <games> into the index, a full build replaces it.
proc ::ai::patternIndex::Built {base variant identity ids scripts plan view result} {
	variable Jobs

	if {$view ne ""} { catch { ::scidb::view::close $base $variant $view } }
	set key [file normalize $base]
	set callbacks {}
	if {[info exists Jobs($key)]} {
		set callbacks [lindex $Jobs($key) 1]
		unset Jobs($key)
	}
	# the waiters hear back whatever happens here
	if {[catch { Store $base $variant $identity $ids $scripts $plan $result } answer]} {
		set answer [dict create ok 0 error $answer]
	}
	foreach callback $callbacks { catch { uplevel #0 [list {*}$callback $answer] } }
}


proc ::ai::patternIndex::Store {base variant identity ids scripts plan result} {
	variable Loaded
	variable Plans

	set key [file normalize $base]
	if {![dict get $result ok]} {
		set answer [dict create ok 0 error [dict get $result error]]
	} elseif {[dict get $result cancelled]} {
		set answer [dict create ok 0 cancelled 1 error "the pattern index build was cancelled"]
	} elseif {[catch { Identity $base $variant } now] || $now ne $identity} {
		# the database changed while the build ran
		set answer [dict create ok 0 error "the database changed while it was being indexed"]
	} else {
		# matches are grouped by script: {game first_ply script ...}
		array set pairs {}
		foreach {game ply script} [dict get $result matches] { lappend pairs($script) $game $ply }
		if {[dict get $plan update]} {
			set old [lindex [Load $base] 1]
			set redone [dict create]
			foreach game [dict get $plan games] { dict set redone $game 1 }
		}
		set patterns {}
		set i 0
		foreach id $ids script $scripts {
			set new [expr {[info exists pairs($i)] ? $pairs($i) : {}}]
			if {[dict get $plan update]} {
				# keep the matches of the games not searched again
				set kept {}
				foreach {game ply} [lindex [dict get $old $id] 1] {
					if {![dict exists $redone $game]} { lappend kept $game $ply }
				}
				set new [lsort -integer -stride 2 -index 0 [concat $kept $new]]
			}
			dict set patterns $id [list [Hash $script] $new]
			incr i
		}
		set fingerprints [dict get $plan fingerprints]
		set Loaded($key) [list $identity $patterns $fingerprints]
		unset -nocomplain Plans($key)
		if {[catch { Save $base $identity $patterns $fingerprints } err]} {
			# still answers from memory for this session
			catch { ::log::error "Pattern index" $err }
		}
		set answer [dict create ok 1]
	}
	return $answer
}


proc ::ai::patternIndex::Save {base identity patterns fingerprints} {
	set file [File $base]
	if {$file eq ""} { return }
	file mkdir [file dirname $file]
	set index {}
	dict for {id entry} $patterns {
		lappend index $id [lindex $entry 0] [expr {[llength [lindex $entry 1]] / 2}]
	}
	set chan [open $file.new wb]
	try {
		puts -nonewline $chan [encoding convertto utf-8 "$identity\n$index\n[string length $fingerprints]\n"]
		dict for {id entry} $patterns {
			puts -nonewline $chan [binary format i* [lindex $entry 1]]
		}
		puts -nonewline $chan $fingerprints
	} finally {
		close $chan
	}
	file rename -force $file.new $file
}
