# Local pick history and exact aliases. This file reads data, never sources scripts.
if {[llength [info commands ::util::source]]} {::util::source command-learning}
namespace eval ::commandline {
 variable Picks {}
 variable Aliases {}
 variable Loaded 0
 variable LearningFile {}
}
proc ::commandline::Phrase {text} {return [string tolower [join [Words $text]]]}
proc ::commandline::LearningPath {} {
 variable LearningFile
 if {$LearningFile ne ""} {return $LearningFile}
 if {[info exists ::scidb::dir::config]} {return [file join $::scidb::dir::config command-line.data]}
 return [file join $::env(HOME) .chesswiz command-line.data]
}
proc ::commandline::LoadLearning {} {
 variable Loaded; variable Picks; variable Aliases
 if {$Loaded} {return}
 set Loaded 1
 set path [LearningPath]
 if {![file readable $path] || [file size $path] > 1048576} {return}
 set channel [open $path r]
 try {set data [read $channel]} finally {close $channel}
 if {[catch {
  if {[dict get $data version] != 1} {error version}
  set picks [dict get $data picks]; set aliases [dict get $data aliases]
  if {[dict size $picks] > 1000 || [dict size $aliases] > 200} {error size}
  dict for {key stats} $picks {
   if {[llength $key] != 4 || [llength $stats] != 2} {error history}
   foreach n $stats {if {![string is wideinteger -strict $n] || $n < 0} {error number}}
  }
  dict for {phrase row} $aliases {
   foreach field {input id action args} {dict get $row $field}
   dict size [dict get $row args]
  }
 }]} {return}
 set Picks $picks; set Aliases $aliases
}
proc ::commandline::SaveLearning {} {
 variable Picks; variable Aliases
 set path [LearningPath]
 file mkdir [file dirname $path]
 set channel [file tempfile tmp [file join [file dirname $path] command-XXXXXX]]
 try {
  fconfigure $channel -encoding utf-8 -translation lf
  puts $channel [dict create version 1 picks $Picks aliases $Aliases]
  close $channel
  set channel {}
  file rename -force $tmp $path
 } finally {
  if {$channel ne ""} {close $channel}
  if {[file exists $tmp]} {file delete $tmp}
 }
}
proc ::commandline::PickKey {row} {
 set arguments {}
 foreach key [lsort [dict keys [dict get $row args]]] {dict set arguments $key [dict get $row args $key]}
 return [list [Phrase [dict get $row input]] [dict get $row id] [dict get $row action] $arguments]
}
proc ::commandline::RecordPick {row} {
 variable Picks
 LoadLearning
 set key [PickKey $row]
 set count 0
 if {[dict exists $Picks $key]} {set count [lindex [dict get $Picks $key] 0]}
 dict set Picks $key [list [expr {$count+1}] [clock microseconds]]
 if {[dict size $Picks] > 1000} {
  set oldest {}; set time [clock microseconds]
  dict for {k stats} $Picks {if {[lindex $stats 1] <= $time} {set oldest $k; set time [lindex $stats 1]}}
  dict unset Picks $oldest
 }
 # A persistence failure must not change the outcome of an already-run action.
 catch {SaveLearning}
}
proc ::commandline::SameTarget {a b} {
 if {[dict get $a id] ne [dict get $b id] || [dict get $a action] ne [dict get $b action]} {return 0}
 set aa [dict get $a args]; set bb [dict get $b args]
 if {[dict size $aa] != [dict size $bb]} {return 0}
 dict for {k v} $aa {if {![dict exists $bb $k] || [dict get $bb $k] ne $v} {return 0}}
 return 1
}
proc ::commandline::AddAlias {phrase row} {
 variable Aliases
 LoadLearning
 set phrase [Phrase $phrase]
 if {$phrase eq "" || [string length $phrase] > 120} {error "Use an alias of 1–120 characters."}
 if {[llength [dict get $row missing]]} {error "Complete the command before saving an alias."}
 if {[dict exists $row origin]} {dict set row input [dict get $row origin]}
 set valid 0
 foreach candidate [Match [dict get $row input]] {if {[SameTarget $row $candidate]} {set valid 1; break}}
 if {!$valid} {error "This command has changed. Choose it again."}
 if {[dict size $Aliases] >= 200 && ![dict exists $Aliases $phrase]} {error "Remove an alias before adding another."}
 dict set Aliases $phrase [dict create input [dict get $row input] id [dict get $row id] action [dict get $row action] args [dict get $row args]]
 SaveLearning
}
proc ::commandline::RemoveAlias {phrase} {
 variable Aliases
 LoadLearning
 dict unset Aliases [Phrase $phrase]
 SaveLearning
}
proc ::commandline::Suggest {text} {
 variable Aliases; variable Picks
 LoadLearning
 set phrase [Phrase $text]
 if {[dict exists $Aliases $phrase]} {
  set target [dict get $Aliases $phrase]
  set rows {}
  foreach row [Match [dict get $target input]] {
   if {[SameTarget $row $target]} {
    dict set row origin [dict get $row input]
    dict set row input $text
    dict set row label "$phrase → [dict get $row label]"
    lappend rows $row
   }
  }
  # An unavailable exact alias does not fall through to a different command.
  return $rows
 }
 set rows [Match $text]
 set ranked {}
 foreach row $rows {
  set key [PickKey $row]; set stats {0 0}
  if {[dict exists $Picks $key]} {set stats [dict get $Picks $key]}
  dict set row frequency [lindex $stats 0]
  dict set row recent [lindex $stats 1]
  lappend ranked $row
 }
 return [Rerank $text [lsort -command ::commandline::LearnedCompare $ranked]]
}
proc ::commandline::LearnedCompare {a b} {
 foreach key {frequency recent} {
  set av [dict get $a $key]; set bv [dict get $b $key]
  if {$av != $bv} {return [expr {$av < $bv ? 1 : -1}]}
 }
 return [Compare $a $b]
}
