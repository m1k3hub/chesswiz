# ======================================================================
# Similar-game retrieval (B8): native exact mainline prefix retrieval.
#
# candidates BASE VARIANT NUMBER ?-limit N? ?-max G? ?-seconds S?
# returns dicts {white black result year shared}, plus number natively.
# NUMBER is zero-based. Native ties use ascending database number.
# shared is the longest common ply prefix from the SAME starting position,
# not overlap after transposition or from an arbitrary reference FEN.
# Empty games and zero overlap are omitted; the reference is excluded.
#
# Native retrieval scans once with a bounded heap and local decoded games.
# The Tcl fallback below is used for older binaries and custom readers.
# Each fallback game is decoded once with game::dump (no editor mutation).
# The collision-free fingerprint is {starting FEN, first ply}; matching
# buckets are verified against the stored move lists. For G games and P
# total plies, build time/space is O(G+P). A query costs O(B*L+B*N log N)
# for B bucket entries, maximum prefix length L and requested limit N;
# a common opening can put all G games in one bucket. No all-pairs scan.
#
# Default caps: first 10000 database records, five seconds per call.
# The following cache/event-loop behavior applies only to the fallback.
# Partial builds resume on subsequent calls; results cover only the built
# prefix and time-bounded query. -max applies even to a larger warm cache.
# Calls return synchronously but service events via after/vwait between
# records (one record per slice). A native decode cannot be preempted;
# the time budget is checked between records, not a hard realtime bound.
# Reentrant retrieval is rejected. Database notifications and lastChange
# invalidate the cache, including same-count edits and close/reopen.
#
# Test seam: -reader CMD receives BASE VARIANT count|stamp|game ?NUMBER?.
# game returns {start KEY moves LIST white W black B result R year Y},
# or {} for deleted records. Custom readers must change stamp on edits.
# ======================================================================

package require Tcl 8.5

namespace eval ::ai::similar {
	variable Index
	variable Buckets
	variable Busy 0
	variable Epoch 0
	variable Subscribed 0
	variable Wake 0
	variable View
}

proc ::ai::similar::invalidate {args} {
	variable Index
	variable Buckets
	variable Epoch
	array unset Index
	array unset Buckets
	incr Epoch
}

# Private views have an unfiltered, unsorted mapping to database numbers.
proc ::ai::similar::IndexRead {base variant op {number 0}} {
	variable View
	switch -- $op {
		count { return [::scidb::db::count games $base $variant] }
		stamp { return [::scidb::db::get lastChange $base $variant] }
		game {
			if {[::scidb::db::get deleted? $number -1 $base $variant]} { return {} }
			set tags {}
			foreach pair [::scidb::db::get tags $number $base $variant] { dict set tags {*}$pair }
			lassign [::scidb::game::dump $base $variant $View $number] ok text
			if {$ok != 1} { error "cannot read game $number ($ok)" }
			regsub -all {[0-9]+\.+} $text {} text
			set record [dict create start standard moves [regexp -all -inline {\S+} $text]]
			if {[dict exists $tags FEN]} {
				# Counters do not affect the initial position or move identity.
				dict set record start [lrange [dict get $tags FEN] 0 3]
			}
			foreach {field tag} {white White black Black result Result year Date} {
				set value {}
				if {[dict exists $tags $tag]} { set value [dict get $tags $tag] }
				if {$field eq "year"} { set value [lindex [split $value .] 0] }
				dict set record $field $value
			}
			return $record
		}
	}
	error "unknown reader operation: $op"
}

proc ::ai::similar::IndexPause {} {
	variable Wake
	after 1 [list incr [namespace current]::Wake]
	vwait [namespace current]::Wake
}

proc ::ai::similar::IndexKey {record} {
	return [list [dict get $record start] [lindex [dict get $record moves] 0]]
}

proc ::ai::similar::IndexCompare {a b} {
	set delta [expr {[dict get $b shared] - [dict get $a shared]}]
	if {$delta} { return $delta }
	foreach field {white black} {
		set delta [string compare [dict get $a $field] [dict get $b $field]]
		if {$delta} { return $delta }
	}
	return 0
}

proc ::ai::similar::IndexCollect {base variant number reader max limit seconds} {
	variable Index
	variable Buckets
	variable Epoch
	set epoch $Epoch
	set deadline [expr {[clock milliseconds] + int(1000*$seconds)}]
	set count [{*}$reader $base $variant count]
	if {$number >= $count} { error "game number out of range" }
	set stamp [{*}$reader $base $variant stamp]
	set key [list $base $variant $reader]
	if {![info exists Index($key)] || [dict get $Index($key) stamp] ne [list $stamp $count]} {
		foreach old [array names Buckets] {
			if {[lindex $old 0] eq $key} { unset Buckets($old) }
		}
		set Index($key) [dict create stamp [list $stamp $count] next 0 records {} buckets {}]
	}
	upvar 0 Index($key) index
	set stop [expr {min($max, $count)}]
	while {[dict get $index next] < $stop && [clock milliseconds] < $deadline} {
		set n [dict get $index next]
		set record [{*}$reader $base $variant game $n]
		if {[llength $record] && [llength [dict get $record moves]]} {
			dict set index records $n $record
			set bucket [list $key [IndexKey $record]]
			lappend Buckets($bucket) $n
		}
		dict incr index next
		IndexPause
		if {$epoch != $Epoch} { error "database changed during retrieval" }
	}
	set reference {}
	if {[dict exists $index records $number]} {
		set reference [dict get $index records $number]
	} elseif {[clock milliseconds] < $deadline} {
		set reference [{*}$reader $base $variant game $number]
	}
	set rows {}
	if {[llength $reference] && [llength [dict get $reference moves]]} {
		set bucket [list $key [IndexKey $reference]]
		if {[info exists Buckets($bucket)]} {
			foreach n $Buckets($bucket) {
				if {[clock milliseconds] >= $deadline} { break }
				if {$n == $number || $n >= $stop} { continue }
				set record [dict get $index records $n]
				set shared 0
				foreach a [dict get $reference moves] b [dict get $record moves] {
					if {$a eq "" || $b eq "" || $a ne $b} { break }
					incr shared
				}
				set row [dict remove $record start moves]
				dict set row shared $shared
				lappend rows $row
				set rows [lrange [lsort -command ::ai::similar::IndexCompare $rows] 0 [expr {$limit-1}]]
				IndexPause
				if {$epoch != $Epoch} { error "database changed during retrieval" }
			}
		}
	}
	if {$stamp ne [{*}$reader $base $variant stamp] || $count != [{*}$reader $base $variant count]} {
		invalidate
		error "database changed during retrieval"
	}
	return $rows
}

proc ::ai::similar::candidates {base variant gameNumber args} {
	variable Busy
	variable Subscribed
	variable View
	array set opts {-limit 10 -max 10000 -seconds 5 -reader ::ai::similar::IndexRead}
	if {[llength $args] % 2} { error "expected option/value pairs" }
	foreach {key value} $args {
		if {![info exists opts($key)]} { error "unknown option $key" }
		set opts($key) $value
	}
	foreach value [list $gameNumber $opts(-limit) $opts(-max)] {
		if {![string is integer -strict $value] || $value < 0} { error "expected nonnegative integer" }
	}
	if {![string is double -strict $opts(-seconds)] || !($opts(-seconds) >= 0) || $opts(-seconds) > 3600} {
		error "-seconds must be between 0 and 3600"
	}
	if {$Busy} { error "similar-game retrieval already running" }
	if {!$opts(-limit) || !$opts(-max) || !$opts(-seconds)} { return {} }
	if {$opts(-reader) eq "::ai::similar::IndexRead"
		&& [llength [info commands ::scidb::db::similar]]} {
		return [::scidb::db::similar $base $variant $gameNumber \
			-limit $opts(-limit) -max $opts(-max) -seconds $opts(-seconds)]
	}
	set Busy 1
	set View {}
	set rc [catch {
		if {$opts(-reader) eq "::ai::similar::IndexRead"} {
			if {!$Subscribed} {
				::scidb::db::subscribe dbInfo ::ai::similar::invalidate ::ai::similar::invalidate
				set Subscribed 1
			}
			set View [::scidb::view::new $base $variant unused unused unused unused master slave]
			::scidb::view::search $base $variant $View reset none
		}
		IndexCollect $base $variant $gameNumber $opts(-reader) $opts(-max) $opts(-limit) $opts(-seconds)
	} result options]
	if {$View ne ""} { catch { ::scidb::view::close $base $variant $View } }
	set Busy 0
	if {$rc} { invalidate }
	return -options $options $result
}

# vi:set ts=3 sw=3:
