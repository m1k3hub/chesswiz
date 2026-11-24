set ::PT0 [clock microseconds]
array set ::PROF {}
proc ::_pcaller {} { if {[info level] > 2} { return [lindex [info level -2] 0] } ; return top }
foreach c {update winfo image font wm raise tkwait grab focus} {
  rename ::$c ::_orig_$c
  proc ::$c args [string map [list @C@ $c] {
    set t [clock microseconds]
    set rc [catch {uplevel 1 [list ::_orig_@C@ {*}$args]} r opts]
    set d [expr {[clock microseconds]-$t}]
    set k "@C@ [lindex $args 0] <- [::_pcaller]"
    if {[info exists ::PROF($k)]} { lassign $::PROF($k) n s; set ::PROF($k) [list [incr n] [expr {$s+$d}]] } else { set ::PROF($k) [list 1 $d] }
    if {$d > 30000} { lappend ::PSLOW [list [expr {($t-$::PT0)/1000}] [expr {$d/1000}] $k] }
    return {*}$opts $r
  }]
}
proc ::profdump {} {
  set out {}
  foreach {k v} [array get ::PROF] { lappend out [list [lindex $v 1] [lindex $v 0] $k] }
  set f [open $::env(PROFOUT) w]
  foreach e [lrange [lsort -integer -decreasing -index 0 $out] 0 60] { puts $f [format "%8.1f ms %6d  %s" [expr {[lindex $e 0]/1000.0}] [lindex $e 1] [lindex $e 2]] }
  puts $f "--- slow (>30ms) at ms:"
  if {[info exists ::PSLOW]} { foreach s $::PSLOW { puts $f $s } }
  close $f
}
set ::argv0 [file normalize src/tkchesswiz]
source tcl/chesswiz
