# ======================================================================
# Tournament Director typed command layer: preview/commit, stale revision,
# idempotency and immutable audit. UI, assistant and runner all call Execute.
# ======================================================================

if {[llength [info commands ::util::source]]} { ::util::source td-command }
package require Tcl 8.6

namespace eval ::td::command { variable Pending [dict create] }

proc ::td::command::dg {d key {default {}}} { if {[dict exists $d $key]} { return [dict get $d $key] }; return $default }

proc ::td::command::DomainArgs {arguments} {
	set domain [dict remove $arguments commit expected_revision idempotency event]
	if {[dict exists $domain path]} { dict unset domain path }
	set out {}
	foreach key [lsort [dict keys $domain]] { lappend out $key [dict get $domain $key] }
	return $out
}

proc ::td::command::Replay {record currentRevision} {
	set result [dict get $record result]
	dict set result idempotent 1
	dict set result revision [dict get $record revision]
	dict set result current_revision $currentRevision
	dict set result seq [dict get $record seq]
	dict set result commit 1
	return $result
}

proc ::td::command::Execute {command arguments} {
	variable Pending
	foreach key {commit expected_revision idempotency} {
		if {![dict exists $arguments $key]} { error "TD command requires '$key'" }
	}
	set key [string trim [dict get $arguments idempotency]]
	if {$key eq ""} { error "TD command requires a nonempty idempotency key" }
	set expected [dict get $arguments expected_revision]
	if {![string is integer -strict $expected] || $expected < 0} { error "expected_revision must be a nonnegative integer" }
	set commit [expr {[dict get $arguments commit] ? 1 : 0}]
	set path [::td::store::Resolve $arguments]
	set info [::td::store::Read $path]
	set domain [DomainArgs $arguments]
	set existing [::td::store::FindKey $info $key]
	if {$existing ne ""} {
		if {[dict get $existing command] ne $command || [dict get $existing args] ne $domain} {
			return -code error -errorcode {CHESSWIZ TD IDEMPOTENCY} "idempotency key '$key' was already used for a different command or arguments"
		}
		set replay [Replay $existing [dict get $info revision]]
		dict set replay path $path
		if {[dict exists $existing after id]} { dict set replay event [dict get $existing after id] }
		return $replay
	}
	set before [dict get $info state]
	set revision [llength [dict get $info records]]
	if {$command ne "create" && $before eq ""} { error "no tournament exists at $path" }
	if {$command eq "create" && $before ne ""} { error "a tournament already exists at $path" }
	if {$expected != $revision} {
		return -code error -errorcode [list CHESSWIZ TD STALE $expected $revision] \
			"stale tournament revision: expected $expected, current $revision"
	}
	set cacheKey [list $path $command $key]
	if {$commit && [dict exists $Pending $cacheKey]} {
		set pending [dict get $Pending $cacheKey]
		if {[dict get $pending revision] == $revision && [dict get $pending domain] eq $domain} {
			set after [dict get $pending after]
			set result [dict get $pending result]
			set target [dict get $pending target]
			set history [dict get $pending history]
		} else {
			dict unset Pending $cacheKey
		}
	}
	if {![info exists after]} {
		lassign [::td::model::Apply $command $info $domain] after result target history
	}
	if {$history ni {0 1}} { error "TD model returned an invalid history flag" }
	if {[catch {dict size $after}]} { error "TD model returned invalid event state" }
	dict set after revision [expr {$revision + 1}]
	if {!$commit} {
		dict set Pending $cacheKey [dict create revision $revision domain $domain after $after result $result target $target history $history]
		set preview [dict create preview 1 commit 0 path $path revision $revision would_revision [expr {$revision + 1}]]
		if {[dict exists $after id]} { dict set preview event [dict get $after id] }
		dict set preview result $result
		return $preview
	}
	if {[dict exists $Pending $cacheKey]} { dict unset Pending $cacheKey }
	set record [::td::store::Append $path $command $key $domain $before $after $result $target $history]
	::td::store::Register $after $path
	dict set result commit 1
	dict set result preview 0
	dict set result revision [expr {$revision + 1}]
	dict set result current_revision [dict get $record revision]
	dict set result seq [dict get $record seq]
	dict set result path $path
	if {[dict exists $after id]} { dict set result event [dict get $after id] }
	dict set result state $after
	return $result
}

proc ::td::command::ClearPreviews {} { variable Pending [dict create] }

# vi:set ts=3 sw=3:
