# ======================================================================
# Tournament Director append-only event store (journal-v1).
# Tcl sqlite3 is not present in every bundle, so each event is a sequence of
# base64-encoded, CRC-protected records. Records contain before/after state,
# immutable audit data, idempotency results and undo/redo targets.
# ======================================================================

if {[llength [info commands ::util::source]]} { ::util::source td-store }
package require Tcl 8.6

namespace eval ::td::store {
	variable Header "TD-JOURNAL-1\n"
	variable Paths [dict create]
	variable Current {}
	variable Busy [dict create]
}

proc ::td::store::Backend {} { return journal-v1 }
proc ::td::store::dg {d key {default {}}} { if {[dict exists $d $key]} { return [dict get $d $key] }; return $default }

proc ::td::store::DefaultPath {name key} {
	set root [file join $::env(HOME) .chesswiz tournaments]
	catch {if {[info exists ::scidb::dir::user]} {set root [file join $::scidb::dir::user tournaments]}}
	set slug [string tolower $name]
	regsub -all {[^a-z0-9]+} $slug - slug
	set slug [string trim $slug -]
	if {$slug eq ""} { set slug event }
	set crc [format %08x [zlib crc32 "$slug|$key"]]
	return [file normalize [file join $root "$slug-$crc.tdj"]]
}

proc ::td::store::Register {state path} {
	variable Paths
	variable Current
	if {$state ne {} && [dict exists $state id]} { dict set Paths [dict get $state id] $path }
	set Current $path
}

proc ::td::store::SetCurrent {path} { variable Current; set Current $path }
proc ::td::store::CurrentPath {} { variable Current; return $Current }
proc ::td::store::ResetCache {} { variable Paths [dict create]; variable Current {} }

proc ::td::store::Resolve {arguments} {
	variable Paths
	variable Current
	if {[dict exists $arguments path] && [dict get $arguments path] ne ""} {
		return [file normalize [dict get $arguments path]]
	}
	if {[dict exists $arguments event] && [dict get $arguments event] ne ""} {
		set id [dict get $arguments event]
		if {[dict exists $Paths $id]} { return [dict get $Paths $id] }
		error "unknown tournament event '$id'; supply its journal path"
	}
	if {$Current ne ""} { return $Current }
	error "no tournament selected; supply path or event"
}

proc ::td::store::Encode {record} {
	set bytes [encoding convertto utf-8 $record]
	set encoded [binary encode base64 -maxlen 0 $bytes]
	return [list [dict get $record seq] [dict get $record revision] [zlib crc32 $bytes] $encoded]
}

proc ::td::store::Decode {line} {
	lassign $line seq revision crc encoded
	if {![string is integer -strict $seq] || ![string is integer -strict $revision] || ![string is integer -strict $crc]} { error "bad journal framing" }
	set bytes [binary decode base64 $encoded]
	if {[zlib crc32 $bytes] != $crc} { error "journal checksum mismatch" }
	set record [encoding convertfrom utf-8 $bytes]
	if {[catch {dict size $record} n] || $n < 8} { error "invalid journal record" }
	if {[dict get $record seq] != $seq || [dict get $record revision] != $revision} { error "journal sequence mismatch" }
	return $record
}

proc ::td::store::Pop {listVar} {
	upvar $listVar values
	set value [lindex $values end]
	set values [lrange $values 0 end-1]
	return $value
}

proc ::td::store::Read {path} {
	set empty [dict create path $path state {} records {} undo {} redo {} revision 0 valid_bytes 0 repair 0]
	if {![file exists $path]} { return $empty }
	set chan [open $path rb]
	set data [read $chan]
	close $chan
	set header $::td::store::Header
	if {[string length $data] == 0} { return $empty }
	if {[string range $data 0 [expr {[string length $header]-1}]] ne $header} { error "$path is not a TD journal" }
	set records {}
	set state {}
	set undo {}
	set redo {}
	set offset [string length $header]
	set validBytes $offset
	set repair 0
	set lines [split [string range $data $offset end] \n]
	set last [llength $lines]
	set index 0
	foreach line $lines {
		incr index
		set hasNewline [expr {$index < $last}]
		if {$line eq ""} {
			if {$hasNewline || $index != $last} { error "$path contains an empty journal record" }
			continue
		}
		if {[catch {Decode $line} record]} {
			if {$index == $last} { set repair 1; break }
			error "$path is corrupt before the journal tail: $record"
		}
		set seq [llength $records]
		incr seq
		if {[dict get $record seq] != $seq} { error "$path has a non-contiguous journal sequence" }
		lappend records $record
		set state [dict get $record after]
		set command [dict get $record command]
		if {$command eq "undo"} {
			if {![llength $undo]} { error "journal undo underflow" }
			set target [Pop undo]
			if {[dict get $record target] != $target} { error "journal undo target mismatch" }
			lappend redo $target
		} elseif {$command eq "redo"} {
			if {![llength $redo]} { error "journal redo underflow" }
			set target [Pop redo]
			if {[dict get $record target] != $target} { error "journal redo target mismatch" }
			lappend undo $target
		} elseif {[dg $record history 1]} {
			lappend undo $seq
			set redo {}
		}
		incr offset [string length $line]
		if {$hasNewline} { incr offset }
		set validBytes $offset
		if {!$hasNewline} { set repair 1 }
	}
	if {$state ne {} && (![dict exists $state revision] || ![dict exists $state id])} { error "$path has no valid event state" }
	return [dict create path $path state $state records $records undo $undo redo $redo \
		revision [expr {$state eq {} ? 0 : [dict get $state revision]}] valid_bytes $validBytes repair $repair]
}

proc ::td::store::Repair {path info} {
	if {![dict get $info repair]} { return }
	set chan [open $path rb]
	set bytes [read $chan [dict get $info valid_bytes]]
	close $chan
	set temp "$path.repair.[pid].tmp"
	set out [open $temp wb]
	puts -nonewline $out $bytes
	if {[string length $bytes] && [string index $bytes end] ne "\n"} { puts -nonewline $out "\n" }
	close $out
	file rename -force $temp $path
	catch {file attributes $path -permissions 0o600}
}

proc ::td::store::Append {path command key args before after result target history} {
	variable Busy
	if {[dict exists $Busy $path]} { error "a journal command is already active for $path" }
	dict set Busy $path 1
	try {
		set info [Read $path]
		set records [dict get $info records]
		foreach record $records {
			if {[dict get $record key] eq $key && $key ne ""} { error "idempotency key '$key' already has a journal record" }
		}
		set seq [expr {[llength $records] + 1}]
		set revision [expr {[dict get $info revision] + 1}]
		dict set after revision $revision
		set record [dict create version 1 seq $seq revision $revision command $command key $key \
			args $args before $before after $after result $result target $target history $history \
			created [clock seconds]]
		set line [Encode $record]
		file mkdir [file dirname $path]
		if {![file exists $path] || [file size $path] == 0} {
			set temp "$path.create.[pid].tmp"
			set out [open $temp wb]
			puts -nonewline $out $::td::store::Header
			close $out
			file rename -force $temp $path
			catch {file attributes $path -permissions 0o600}
		} else {
			Repair $path $info
		}
		set out [open $path ab]
		puts $out $line
		flush $out
		close $out
		return $record
	} finally {
		dict unset Busy $path
	}
}

proc ::td::store::FindKey {info key} {
	foreach record [dict get $info records] {
		if {[dict get $record key] eq $key} { return $record }
	}
	return {}
}

proc ::td::store::Audit {path} { return [dict get [Read $path] records] }
proc ::td::store::Games {state} { return [dg $state games {}] }

# vi:set ts=3 sw=3:
