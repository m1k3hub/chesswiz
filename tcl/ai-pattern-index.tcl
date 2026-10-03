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
#   ::ai::patternIndex::wanted <base> <variant>
#       -> whether building pays: a big, unmodified Normal database
#   ::ai::patternIndex::lookup <base> <variant> <id>
#       -> {game first_ply ...} of library pattern <id>, or an error when
#       the database has no valid index for it (check with has)
#   ::ai::patternIndex::has <base> <variant> <id>
#   ::ai::patternIndex::build <base> <variant> <callback>
#       evaluates all library patterns over the whole database in the
#       background; <callback> gets {ok 1}, {ok 0 cancelled 1 error E} or
#       {ok 0 error E}. A build already running for the database takes the
#       callback too. Returns the CQL job (::scidb::cql6::cancel stops it),
#       or "" when there is none.
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
variable Format 1

# Loaded[base]: {identity {id {hash pairs} ...}}
variable Loaded
array set Loaded {}
# Jobs[base]: {job callbacks}
variable Jobs
array set Jobs {}

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


# The index of <base> as {identity patterns}, read from its file once;
# {} when there is none or it cannot be read.
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
			set patterns {}
			foreach {id hash count} $index {
				set data [read $chan [expr {8 * $count}]]
				if {[string length $data] != 8 * $count} { error "truncated" }
				binary scan $data i* pairs
				dict set patterns $id [list $hash $pairs]
			}
		} finally {
			close $chan
		}
	}]} {
		return {}
	}
	set Loaded($key) [list $identity $patterns]
	return $Loaded($key)
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
	set identity [Identity $base $variant]
	if {[catch {
		set job [::scidb::cql6::search $base $variant [lindex $scripts 0] \
			-scripts [lrange $scripts 1 end] -compact 1 \
			-command [namespace code [list Built $base $variant $identity $ids $scripts]]]
	} err]} {
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


proc ::ai::patternIndex::Built {base variant identity ids scripts result} {
	variable Jobs

	set key [file normalize $base]
	set callbacks {}
	if {[info exists Jobs($key)]} {
		set callbacks [lindex $Jobs($key) 1]
		unset Jobs($key)
	}
	# the waiters hear back whatever happens here
	if {[catch { Store $base $variant $identity $ids $scripts $result } answer]} {
		set answer [dict create ok 0 error $answer]
	}
	foreach callback $callbacks { catch { uplevel #0 [list {*}$callback $answer] } }
}


proc ::ai::patternIndex::Store {base variant identity ids scripts result} {
	variable Loaded

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
		set patterns {}
		set i 0
		foreach id $ids script $scripts {
			dict set patterns $id [list [Hash $script] [expr {[info exists pairs($i)] ? $pairs($i) : {}}]]
			incr i
		}
		set Loaded($key) [list $identity $patterns]
		if {[catch { Save $base $identity $patterns } err]} {
			# still answers from memory for this session
			catch { ::log::error "Pattern index" $err }
		}
		set answer [dict create ok 1]
	}
	return $answer
}


proc ::ai::patternIndex::Save {base identity patterns} {
	set file [File $base]
	if {$file eq ""} { return }
	file mkdir [file dirname $file]
	set index {}
	dict for {id entry} $patterns {
		lappend index $id [lindex $entry 0] [expr {[llength [lindex $entry 1]] / 2}]
	}
	set chan [open $file.new wb]
	try {
		puts -nonewline $chan [encoding convertto utf-8 "$identity\n$index\n"]
		dict for {id entry} $patterns {
			puts -nonewline $chan [binary format i* [lindex $entry 1]]
		}
	} finally {
		close $chan
	}
	file rename -force $file.new $file
}
