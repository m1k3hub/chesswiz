# Deterministic, side-effect-free command matching. No provider/model is consulted.
if {[llength [info commands ::util::source]]} { ::util::source command-line }
namespace eval ::commandline {
 variable Source ::commandline::AppSource
 variable Cache {}
}
proc ::commandline::Words {text} {
 return [regexp -all -inline {[^\s]+} [string trim $text]]
}
proc ::commandline::Key {slot} {
 variable Keys
 if {[dict exists $Keys $slot]} {return [dict get $Keys $slot]}
 return $slot
}
proc ::commandline::WordMatch {typed word} {
 set typed [string tolower $typed]; set word [string tolower $word]
 if {[string first $typed $word] == 0} {return 1}
 # One mistyped character in a word of four or more letters, never a free value.
 if {[string length $typed] < 4 || abs([string length $typed]-[string length $word]) > 1} {return 0}
 set i 0; set j 0; set errors 0
 while {$i < [string length $typed] && $j < [string length $word]} {
  if {[string index $typed $i] ne [string index $word $j]} {
   if {[incr errors] > 1} {return 0}
   if {[string length $typed] > [string length $word]} {incr i; continue}
   if {[string length $typed] < [string length $word]} {incr j; continue}
  }
  incr i; incr j
 }
 return [expr {$errors + ([string length $typed]-$i) + ([string length $word]-$j) <= 1}]
}
proc ::commandline::NameMatch {query value} {
 set hay [Words [string map {, { } _ { } : { }} [string tolower $value]]]
 foreach word [Words [string map {, { } _ { }} [string tolower $query]]] {
  set found 0
  foreach candidate $hay {if {[WordMatch $word $candidate]} {set found 1; break}}
  if {!$found} {return 0}
 }
 return 1
}
proc ::commandline::Values {slot query} {
 variable Types; variable Enums; variable Source; variable Cache
 set type [dict get $Types $slot]
 set cachekey [list $type $query]
 if {[dict exists $Cache $cachekey]} {return [dict get $Cache $cachekey]}
 set values {}
 if {[dict exists $Enums $type]} {
  foreach value [dict get $Enums $type] {if {[NameMatch $query $value]} {lappend values $value}}
 } elseif {$type in {integer rating year}} {
  if {[regexp {^[0-9]+$} $query] && [string length $query] < 10} {
   scan $query %d n
   if {($type eq "integer" && $n > 0) || ($type eq "rating" && $n <= 4000) || ($type eq "year" && $n >= 1000 && $n <= 9999)} {set values [list $n]}
  }
 } elseif {$type eq "time_control"} {
  if {[regexp {^[1-9][0-9]{0,3}\+[0-9]{1,3}$} $query]} {set values [list $query]}
 } elseif {$type eq "opening_move"} {
  if {[regexp {^([1-9][0-9]*\.)?([KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](=[QRBN])?[+#]?|O-O(-O)?)$} $query]} {set values [list $query]}
 } elseif {$type in {inputfile pgnfile outputfile filename}} {
  set q [string trim $query \" ]
  if {$q ne "" && ![regexp {[\x00-\x1f]} $q]} {
   if {$type in {outputfile filename} || [file isfile $q]} {
    if {$type ne "pgnfile" || [regexp -nocase {\.(pgn|pgn.gz|zip)$} $q]} {set values [list $q]}
   }
  }
 } else {
  # The source must return app-owned values; failures produce no invented candidates.
  catch {set values [{*}$Source $type $query]}
 }
 dict set Cache $cachekey [lrange $values 0 7]
 return [dict get $Cache $cachekey]
}
# A parse is {arguments missing score}. Only complete consumption can be runnable.
proc ::commandline::Parse {template words arguments {missing {}} {score 0}} {
 if {![llength $template]} {
  if {[llength $words]} {return {}}
  return [list [list $arguments $missing $score]]
 }
 set head [lindex $template 0]; set tail [lrange $template 1 end]
 if {[lindex $head 0] eq "?"} {
  set out [Parse $tail $words $arguments $missing $score]
  if {[llength $words]} {lappend out {*}[Parse [concat [lrange $head 1 end] $tail] $words $arguments $missing $score]}
  return $out
 }
 if {$head eq "@criteria"} {return [Criteria $words $arguments $missing $score]}
 if {[string index $head 0] ne "@"} {
  if {![llength $words]} {return [Parse $tail {} $arguments $missing $score]}
  if {![WordMatch [lindex $words 0] $head]} {return {}}
  return [Parse $tail [lrange $words 1 end] $arguments $missing [expr {$score+10}]]
 }
 set slot [string range $head 1 end]; set key [Key $slot]
 if {![llength $words] || [lindex $words 0] eq "<$slot>"} {
  return [Parse $tail [lrange $words 1 end] $arguments [concat $missing $slot] $score]
 }
 set out {}
 for {set n 1} {$n <= [llength $words]} {incr n} {
  set query [join [lrange $words 0 [expr {$n-1}]]]
  foreach value [Values $slot $query] {
   set next [dict merge $arguments [dict create $key $value]]
   lappend out {*}[Parse $tail [lrange $words $n end] $next $missing [expr {$score+5+$n}]]
  }
 }
 return [lrange $out 0 23]
}
proc ::commandline::Criteria {words arguments missing score} {
 if {![llength $words]} {
  if {![dict size $arguments]} {lappend missing player}
  return [list [list $arguments $missing $score]]
 }
 set key [string tolower [lindex $words 0]]; set consumed 1
 switch -- $key {
  player - event - from - to {set slot $key}
  colour - color {set slot color}
  result {set slot result}
  opening - eco {set slot eco}
  motif - pattern {set slot pattern}
  min {if {[lindex $words 1] ne "elo"} {return {}}; set slot min_elo; set consumed 2}
  both {if {[lindex $words 1] ne "elo"} {return {}}; set slot both_min_elo; set consumed 2}
  wins - win {return [Criteria [lrange $words 1 end] [dict merge $arguments {result win}] $missing $score]}
  losses - loss {return [Criteria [lrange $words 1 end] [dict merge $arguments {result loss}] $missing $score]}
  draws - draw {return [Criteria [lrange $words 1 end] [dict merge $arguments {result draw}] $missing $score]}
  wh - white {return [Criteria [lrange $words 1 end] [dict merge $arguments {color white}] $missing $score]}
  bl - black {return [Criteria [lrange $words 1 end] [dict merge $arguments {color black}] $missing $score]}
  default {set slot player; set consumed 0}
 }
 if {[dict exists $arguments [Key $slot]]} {return {}}
 set rest [lrange $words $consumed end]
 if {![llength $rest]} {return [list [list $arguments [concat $missing $slot] $score]]}
 set out {}
 for {set n 1} {$n <= [llength $rest]} {incr n} {
  foreach v [Values $slot [join [lrange $rest 0 [expr {$n-1}]]]] {
   lappend out {*}[Criteria [lrange $rest $n end] [dict merge $arguments [dict create [Key $slot] $v]] $missing [expr {$score+5}]]
  }
 }
 return [lrange $out 0 23]
}
proc ::commandline::Match {text} {
 variable Table; variable Cache
 set Cache {}; set words [Words $text]; set out {}; set seen {}
 if {![llength $words] || [llength $words] > 50} {return {}}
 foreach entry $Table {
  lassign $entry id action defaults templates
  foreach template $templates {
   foreach parsed [Parse $template $words $defaults] {
    lassign $parsed arguments missing score
    if {$id == 28 && [dict exists $arguments colour]} {
     dict set arguments colour [expr {[dict get $arguments colour] eq "white" ? "black" : "white"}]
    }
    if {$id in {32 33 44} && ($id != 44 || [dict get $arguments source] eq "my games")} {
     if {[info exists ::application::ai::Settings(me)] && $::application::ai::Settings(me) ne ""} {
      dict set arguments player $::application::ai::Settings(me)
     }
    }
    if {$action eq "search_games" && [dict exists $arguments result] && ![dict exists $arguments player]} {
     if {[dict get $arguments result] eq "draw"} {dict set arguments result 1/2-1/2} else {lappend missing player}
    }
    if {$id == 22 && ![llength $missing] && $::commandline::Source eq "::commandline::AppSource" && [llength [info commands ::commandline::OpeningMoves]]} {
     if {[catch {OpeningMoves $arguments}]} {continue}
    }
    set identity [list $id $action $arguments $missing]
    if {[dict exists $seen $identity]} {continue}
    dict set seen $identity 1
    set label [join [lmap word $template {if {[string index $word 0] eq "@" || [lindex $word 0] eq "?"} continue; set word}]]
    dict for {key value} $arguments {
     set displayKey [expr {$id == 28 && $key eq "colour" ? "opponent_colour" : $key}]
     append label "  $displayKey=$value"
    }
    foreach slot $missing {append label "  <$slot>"}
    lappend out [dict create id $id action $action args $arguments missing $missing score $score label $label input $text template $template]
   }
  }
 }
 return [lrange [lsort -command ::commandline::Compare $out] 0 23]
}
proc ::commandline::Compare {a b} {
 set c [expr {[dict get $b score]-[dict get $a score]}]
 if {$c} {return $c}
 return [string compare [dict get $a label] [dict get $b label]]
}
# Native name-index lookups are bounded; never scan game records while typing.
proc ::commandline::AppSource {type query} {
 set values {}
 switch -- $type {
  player - event - site {
   lassign [::application::assistant::ActiveBase] base variant
   foreach row [::scidb::db::match $type $base $variant 8 $query] {
    if {[lindex $row 0] > 0} {lappend values [lindex $row 1]}
   }
  }
  database {
   set w [::application::database::switcherWidget]
   foreach base [$w bases] {
    if {[NameMatch $query [::util::databaseName $base no]] || $query eq $base} {lappend values $base}
   }
   return $values
  }
  engine {foreach e $::engine::Engines {lappend values [dict get $e Name]}}
  pane {set values [[::application::twm board] leaves]}
  tab {foreach tab [.application.nb tabs] {lappend values [lindex [split $tab .] end]}}
  motif {
   foreach id [::ai::search::patternIds] {
    set p [::ai::search::pattern $id]
    if {[NameMatch $query $id] || [NameMatch $query [dict get $p label]]} {lappend values $id}
   }
   return [lrange $values 0 7]
  }
  opening - eco {
   set lookup [expr {$query eq "" ? "a" : $query}]
   foreach row [::scidb::ai::ecoLines [regexp -all -inline {[^\s,;:()]+} $lookup]] {
    lassign $row code label moves
    if {$type eq "eco"} {lappend values $code} else {lappend values $label}
   }
   if {$type eq "eco" && [regexp -nocase {^[A-E][0-9]{0,2}$} $query]} {
    if {![catch {::scidb::misc::lookup opening [string toupper $query] Normal} entry] && [llength $entry]} {lappend values [string toupper $query]}
   }
   if {$type eq "opening"} {return [lrange [lsort -command ::commandline::ShortName [lsort -unique $values]] 0 7]}
   return [lrange [lsort -unique $values] 0 7]
  }
  move {
   if {![catch {::scidb::ai::moveFacts $query} facts]} {return [list $query]}
   return {}
  }
 }
 set out {}
 foreach v $values {if {[NameMatch $query $v]} {lappend out $v}}
 return [lrange [lsort -unique $out] 0 7]
}
proc ::commandline::CompleteText {template arguments} {
 set words {}
 foreach word $template {
  if {[lindex $word 0] eq "?"} {
   set group [lrange $word 1 end]; set include 0
   foreach item $group {if {[string index $item 0] eq "@" && [dict exists $arguments [Key [string range $item 1 end]]]} {set include 1}}
   if {$include} {lappend words [CompleteText $group $arguments]}
  } elseif {[string index $word 0] eq "@"} {
   set slot [string range $word 1 end]; set key [Key $slot]
   if {$slot eq "criteria"} {
    dict for {k v} $arguments {lappend words $k $v}
    if {![dict size $arguments]} {lappend words player <player>}
   } elseif {[dict exists $arguments $key]} {lappend words [dict get $arguments $key]} else {lappend words <$slot>}
  } else {lappend words $word}
 }
 return [join $words]
}
proc ::commandline::Run {row} {
 if {[llength [dict get $row missing]]} {return "declined: complete the missing slot"}
 # Re-resolve against current state; stale names, aliases and illegal moves never run.
 set valid 0
 foreach candidate [Suggest [dict get $row input]] {
  if {[dict get $candidate action] eq [dict get $row action] && [dict get $candidate args] eq [dict get $row args] && ![llength [dict get $candidate missing]]} {set valid 1; break}
 }
 if {!$valid} {return "declined: the command's values changed; choose again"}
 set result [::action::run [dict get $row action] [dict get $row args]]
 if {![string match "error:*" $result] && ![string match "declined*" $result] && [llength [info commands ::commandline::RecordPick]]} {RecordPick $row}
 return $result
}
namespace eval ::application::assistant {}
# A separate, tools-free conversation path. Even unsolicited provider tool calls
# are ignored, so model output can never reach the action registry.
proc ::application::assistant::Question {text} {
 variable Priv
 if {$Priv(busy)} {return 0}
 ConfigureProvider
 set facts ""
 catch {set facts [DoCurrentGame]}
 set messages [list [dict create role system content "Answer this question read-only. You cannot run commands or change data. Chess facts must come from the supplied board record; do not invent evaluations. Board record:\n$facts"] [dict create role user content $text]]
 Append user $text
 ::ai::provider::chatAsync $messages {} ::application::assistant::QuestionReply
 return 1
}
proc ::application::assistant::QuestionReply {result} {
 if {![dict get $result ok]} {Append info [dict get $result error]; return}
 set message [dict get $result message]
 if {[dict exists $message tool_calls] && [llength [dict get $message tool_calls]]} {
  Append info "Questions cannot run commands. Use Commands to choose an action."
  return
 }
 if {[dict exists $message content]} {Append assistant [dict get $message content]}
}

proc ::commandline::ShortName {a b} {
 return [expr {[string length $a]-[string length $b]}]
}

# Plain Tcl consumers can use the matcher without loading persistence or Tk.
proc ::commandline::Suggest {text} {return [Match $text]}
