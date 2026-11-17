# Deterministic, side-effect-free command matching. No provider/model is consulted.
if {[llength [info commands ::util::source]]} { ::util::source command-line }
namespace eval ::commandline {
 variable Source ::commandline::AppSource
 variable Cache {}
 variable EcoIndex {}
 variable EcoTokenMap {}
 variable EcoRanges {}
 variable OpeningLines {}
 variable MotifIndex {}
 # Async handlers (Tablebase, SimilarGames, ...) answer later through
 # ::application::assistant::Resolve; remember the command row for each token
 # so the reply reaches the user instead of being dropped.
 variable Pending {}
}
proc ::commandline::EcoFold {text} {
 return [string map {é e è e á a à a ä a ö o ó o ø o ü u í i ñ n å a ř r} [string tolower $text]]
}
proc ::commandline::Tokenize {text} {
 return [regexp -all -inline {[^\s,;:()]+} [string map [list \x27 "" \u2019 ""] [string tolower $text]]]
}
proc ::commandline::WordListMatch {qwords hwords} {
 foreach word $qwords {
  set found 0
  foreach candidate $hwords {if {[WordMatch $word $candidate]} {set found 1; break}}
  if {!$found} {return 0}
 }
 return 1
}
proc ::commandline::EnsureEco {} {
 variable EcoIndex; variable EcoTokenMap; variable OpeningLines; variable EcoRanges
 if {[llength $EcoIndex]} {return}
 set seen {}
 set families {}
 set EcoTokenMap {}; set OpeningLines {}; set EcoRanges {}
 set idx 0
 foreach letter {a e i o u y} {
  foreach row [::scidb::ai::ecoLines [list $letter] 50000] {
   lassign $row code label moves
   dict lappend OpeningLines $label $moves
   set key [list $code $label]
   if {![dict exists $seen $key]} {
    dict set seen $key 1
    set llow [string map [list \x27 "" \u2019 ""] [EcoFold $label]]
    set parts [split $llow ,]
    set first [string trim [lindex $parts 0]]
    set second [string trim [lindex $parts 1]]
    set third [string trim [lindex $parts 2]]
    set cwords [Tokenize "$code [EcoFold $label]"]
    set lwords [Tokenize [EcoFold $label]]
    set flank [expr {[string index $code 0] eq "A" ? 1 : 0}]
    lappend EcoIndex [list $code $label $llow $first $second $third [string length $label] $flank $cwords $lwords]
    set prefix {}
    foreach component [EcoComponents $label] {
     lappend prefix $component
     dict lappend families $prefix $code
    }
    foreach tok [lsort -unique $cwords] {dict lappend EcoTokenMap $tok $idx}
    incr idx
   }
  }
 }
 # Compile each hierarchy prefix once. Split at gaps and volume boundaries;
 # an ambiguous family must never include unrelated ECO codes between runs.
 dict for {prefix codes} $families {
  set ranges {}; set from {}; set previous {}; set lastNumber -2
  foreach code [lsort -unique $codes] {
   scan [string range $code 1 end] %d number
   if {$from ne "" && ([string index $code 0] ne [string index $previous 0] || $number != $lastNumber+1)} {
    lappend ranges [expr {$from eq $previous ? $from : "$from-$previous"}]
    set from {}
   }
   if {$from eq ""} {set from $code}
   set previous $code; set lastNumber $number
  }
  if {$from ne ""} {lappend ranges [expr {$from eq $previous ? $from : "$from-$previous"}]}
  dict set EcoRanges $prefix $ranges
 }

}
proc ::commandline::EcoCandidates {qwords} {
 variable EcoIndex; variable EcoTokenMap
 if {![llength $qwords]} {
  set all {}
  for {set i 0} {$i < [llength $EcoIndex]} {incr i} {lappend all $i}
  return $all
 }
 set first [lindex $qwords 0]
 set candidates {}
 dict for {tok indices} $EcoTokenMap {
  if {[WordMatch $first $tok]} {lappend candidates {*}$indices}
 }
 return [lsort -unique -integer $candidates]
}
# The comma-separated components of an opening name, lowercased. The opening
# table names a family and its lines hierarchically: "Sicilian, Sicilian
# Defence, Najdorf Variation, ...".
proc ::commandline::EcoComponents {label} {
 set out {}
 foreach part [split $label ,] {lappend out [EcoFold [string trim $part]]}
 return $out
}
# The shortest leading run of components that covers every typed word. This
# keeps "Najdorf" inside the Sicilian family and "King's Indian" out of the
# Réti and Neo-King's Indian names that merely mention it.
proc ::commandline::EcoFamilyPrefix {label qwords} {
 set comps [EcoComponents $label]
 set n [llength $comps]
 for {set k 1} {$k <= [llength $comps]} {incr k} {
  set tokens [Tokenize [join [lrange $comps 0 [expr {$k-1}]] ,]]
  set all 1
  foreach word $qwords {
   set hit 0
   foreach token $tokens {if {[WordMatch $word $token]} {set hit 1; break}}
   if {!$hit} {set all 0; break}
  }
  if {$all} {set n $k; break}
 }
 return [lrange $comps 0 [expr {$n-1}]]
}
# Precomputed, disjoint ranges for a hierarchical opening family.
proc ::commandline::EcoFamilyRanges {prefix} {
 variable EcoRanges
 if {[dict exists $EcoRanges $prefix]} {return [dict get $EcoRanges $prefix]}
 return {}
}
# Whether a label's leading components are exactly the canonical hierarchy
# (Queen's Pawn / Queen's Pawn Game / London System, for example).
proc ::commandline::EcoHasPrefix {label prefix} {
 set comps [EcoComponents $label]
 if {[llength $comps] < [llength $prefix]} {return 0}
 return [expr {[lrange $comps 0 [expr {[llength $prefix]-1}]] eq $prefix}]
}
proc ::commandline::EcoLookup {type query} {
 variable EcoIndex
 EnsureEco
 set values {}
 set explicit [expr {$type eq "eco" && [regexp -nocase {^[A-E][0-9]{0,2}(-[A-E][0-9]{2})?$} [string trim $query]]}]
 if {$explicit} {
  lappend values [string toupper [string map {" " ""} [string trim $query]]]
 }
 set qlow [string map [list \x27 "" \u2019 ""] [EcoFold [string trim $query]]]
 set qwords [Tokenize [EcoFold $query]]
 # Conventional short names disambiguate homonymous subvariations in the
 # ECO catalog. Resolve the canonical hierarchy, not a label-length guess.
 set aliases [dict create london {{queen's pawn} {queen's pawn game} {london system}} \
  sveshnikov {sicilian {sicilian defence} {pelikán (lasker/sveshnikov) variation}}]
 dict set aliases {london system} [dict get $aliases london]
 dict set aliases {sveshnikov variation} [dict get $aliases sveshnikov]
 set canonical {}
 if {[dict exists $aliases $qlow]} {
  set canonical [lmap part [dict get $aliases $qlow] {EcoFold $part}]
  if {$type eq "eco"} {
   set values [EcoFamilyRanges $canonical]
   if {[llength $values]} {return $values}
  }
 }
 set ranked {}
 foreach idx [EcoCandidates $qwords] {
  lassign [lindex $EcoIndex $idx] code label llow first second third len flank codeWords labelWords
  set words [expr {$type eq "eco" ? $codeWords : $labelWords}]
  if {$qlow eq "" || [WordListMatch $qwords $words]} {
   set rank [expr {$qlow eq "" ? 6 : ($qlow eq $first ? 0 : ([string first $qlow $first] == 0 ? 1 : ([string first $qlow $second] == 0 ? 2 : ([string first $qlow $third] == 0 ? 3 : ([string first $qlow $first] >= 0 ? 4 : ([string first $qlow $llow] >= 0 ? 5 : 6))))))}]
   if {$type ne "eco" && $canonical ne "" && [EcoHasPrefix $label $canonical]} {set rank -1}
   lappend ranked [list [expr {$rank * 10000 + $len}] [expr {$type eq "eco" ? $code : $label}] $label]
  }
 }
 set sorted [lsort -integer -index 0 $ranked]
 foreach item $sorted {
  set v [lindex $item 1]
  if {$type eq "eco" && !$explicit && [llength $qwords]} {
   set family [EcoFamilyRanges [EcoFamilyPrefix [lindex $item 2] $qwords]]
   foreach range $family {if {$range ni $values} {lappend values $range}}
   if {[llength $values] >= 8} {break}
   continue
  }
  if {$v ni $values} {lappend values $v}
  if {[llength $values] >= 8} {break}
 }
 return $values
}
proc ::commandline::EnsureMotifs {} {
 variable MotifIndex
 if {[llength $MotifIndex]} {return}
 foreach id [::ai::search::patternIds] {
  set p [::ai::search::pattern $id]
  set label [string tolower [dict get $p label]]
  set text "$id $label"
  if {[info exists ::ai::search::Patterns] && [dict exists $::ai::search::Patterns $id]} {
   append text " " [join [lindex [dict get $::ai::search::Patterns $id] 2]]
  }
  lappend MotifIndex $id $label [Tokenize [string map {_ { }} $text]]
 }
}
proc ::commandline::MotifLookup {query} {
 variable MotifIndex
 EnsureMotifs
 set qlow [string map [list \x27 "" \u2019 ""] [string tolower [string trim $query]]]
 set qwords [Tokenize [string map {_ { }} $query]]
 set ranked {}
 foreach {id label words} $MotifIndex {
  if {![llength $qwords] || [WordListMatch $qwords $words]} {
   set exact [expr {$qlow ne "" && ($qlow eq $id || $qlow eq $label || [string first $qlow $label] == 0) ? 0 : 1}]
   lappend ranked [list $exact $id]
  }
 }
 set sorted [lsort -integer -index 0 $ranked]
 return [lrange [lmap item $sorted {lindex $item 1}] 0 7]
}
proc ::commandline::EcoMovesTokens {moves} {
 regsub -all {\m[0-9]+\.} $moves { } s
 return [regexp -all -inline {[^\s]+} $s]
}
proc ::commandline::Words {text} {
 # Split on whitespace but keep a double-quoted path as one word, so a
 # typed or picked file name with spaces reaches Values intact.
 set out {}
 set word ""
 set quoted 0
 set started 0
 foreach ch [split [string trim $text] {}] {
  if {$ch eq "\""} {set quoted [expr {!$quoted}]; set started 1; continue}
  if {!$quoted && [string is space $ch]} {
   if {$started || $word ne ""} {lappend out $word; set word ""; set started 0}
   continue
  }
  append word $ch
  set started 1
 }
 if {$started || $word ne ""} {lappend out $word}
 return $out
}
proc ::commandline::QuoteArgument {value} {
 if {$value eq "" || [regexp {[\s"]} $value]} {
  return "\"[string map {\" \\\"} $value]\""
 }
 return $value
}
proc ::commandline::FileSlot? {slot} {
 variable Types
 if {![dict exists $Types $slot]} {return 0}
 return [expr {[dict get $Types $slot] in {inputfile pgnfile outputfile filename}}]
}
# X11 file dialogs return {path encoding}; native dialogs return the path
# alone. Never leak the encoding half into the command sentence.
proc ::commandline::PickResult {result} {
 if {[llength $result] == 2} {
  lassign $result path encoding
  if {$encoding eq "" || $encoding eq "AutoDetect" || $encoding in [encoding names]} {
   return $path
  }
 }
 return $result
}
# A file slot names its value with the platform's own picker; tests replace
# the dialog itself (never this procedure) so no window opens off screen.
proc ::commandline::PickFile {slot} {
 variable Types
 set type [dict get $Types $slot]
 set pgn [list [list "PGN files" {.pgn .pgn.gz .zip}] [list "All files" *]]
 set db [list [list "Chess databases" {.sci .si4 .si3 .cbh .scv .pgn .pgn.gz .zip}] [list "All files" *]]
 switch -- $type {
  inputfile {return [PickResult [dialog::openFile -parent .application -title "Open database" -filetypes $db]]}
  pgnfile {return [PickResult [dialog::openFile -parent .application -title "Import games" -filetypes $pgn]]}
  outputfile {
   set types [list [list "PGN files" {.pgn}] [list "HTML files" {.html}] [list "PDF files" {.pdf}] [list "All files" *]]
   return [PickResult [dialog::saveFile -parent .application -title "Export games" -filetypes $types]]
  }
  filename {
   return [PickResult [dialog::saveFile -parent .application -title "Save database" -filetypes [list [list "Scidb databases" {.sci}] [list "All files" *]]]]
  }
 }
 return ""
}
# The visible game list is the last result list; 1 counts from its top.
proc ::commandline::ResultCount {} {
 if {[llength [info commands ::application::assistant::ActiveBase]] == 0} {return 0}
 if {[catch {
  lassign [::application::assistant::ActiveBase] base variant
  if {$base eq ""} {return 0}
  ::scidb::view::count games $base $variant 0
 } count]} {return 0}
 return $count
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
  if {[regexp {^([1-9][0-9]*\.(\.\.)?)?([KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](=[QRBN])?[+#]?|O-O(-O)?)$} $query]} {set values [list $query]}
 } elseif {$type eq "result_index"} {
  if {[regexp {^[0-9]+$} $query] && [string length $query] < 10} {
   scan $query %d n
   if {$n >= 1 && $n <= [ResultCount]} {set values [list $n]}
  }
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
 set stop [llength $words]
 if {[llength $tail]} {
  set nextItem [lindex $tail 0]
  if {[lindex $nextItem 0] eq "?" && [llength $nextItem] > 1} {
   set optFirst [lindex $nextItem 1]
   if {[string index $optFirst 0] ne "@"} {
    for {set k 1} {$k < [llength $words]} {incr k} {
     if {[WordMatch [lindex $words $k] $optFirst]} {set stop $k; break}
    }
   }
  } elseif {[string index $nextItem 0] ne "@"} {
   set foundLit 0
   for {set k 1} {$k < [llength $words]} {incr k} {
    if {[WordMatch [lindex $words $k] $nextItem]} {set stop $k; set foundLit 1; break}
   }
   if {!$foundLit} {return {}}
  }
 }
 set out {}
 for {set n 1} {$n <= $stop} {incr n} {
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
  player - event - site - from - to {set slot $key}
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
 set stop [llength $rest]
 for {set k 1} {$k < [llength $rest]} {incr k} {
  set kw [string tolower [lindex $rest $k]]
  if {$kw in {player event site from to colour color result opening eco motif pattern min both wins win losses loss draws draw wh white bl black}} {
   set stop $k
   break
  }
 }
 set out {}
 for {set n 1} {$n <= $stop} {incr n} {
  foreach v [Values $slot [join [lrange $rest 0 [expr {$n-1}]]]] {
   lappend out {*}[Criteria [lrange $rest $n end] [dict merge $arguments [dict create [Key $slot] $v]] $missing [expr {$score+5}]]
  }
 }
 return [lrange $out 0 23]
}
proc ::commandline::Match {text} {
 variable Table; variable Cache
 set Cache {}; set words [Words $text]; set out {}; set seen {}; set seq 0
 if {![llength $words] || [llength $words] > 50} {return {}}
 foreach entry $Table {
  lassign $entry id action defaults templates
  foreach template $templates {
   foreach parsed [Parse $template $words $defaults] {
    lassign $parsed arguments missing score
    if {$id == 28 && [dict exists $arguments colour]} {
     dict set arguments colour [expr {[dict get $arguments colour] eq "white" ? "black" : "white"}]
    }
    set me [expr {[info exists ::application::ai::Settings(me)] ? $::application::ai::Settings(me) : ""}]
    if {$id in {32 33} || ($id == 27 && $action eq "command.repertoire_check") \
     || ($id == 44 && [dict exists $arguments source] && [dict get $arguments source] eq "my games")} {
     if {$me ne ""} {
      dict set arguments player $me
     }
    }
    if {$action in {search_games command.find} && ![dict exists $arguments player]} {
     if {[dict exists $arguments result] && [dict get $arguments result] eq "draw"} {
      dict set arguments result 1/2-1/2
     } elseif {[dict exists $arguments result] || [dict exists $arguments color] || [dict exists $arguments opponent]} {
      lappend missing player
     }
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
    lappend out [dict create id $id action $action args $arguments missing $missing score $score seq [incr seq] label $label input $text template $template]
   }
  }
 }
 return [lrange [lsort -command ::commandline::Compare $out] 0 23]
}
proc ::commandline::Compare {a b} {
 set c [expr {[dict get $b score]-[dict get $a score]}]
 if {$c} {return $c}
 if {[dict exists $a seq] && [dict exists $b seq]} {
  return [expr {[dict get $a seq]-[dict get $b seq]}]
 }
 return [string compare [dict get $a label] [dict get $b label]]
}
# Native name-index lookups are bounded; never scan game records while typing.
proc ::commandline::AppSource {type query} {
 set values {}
 switch -- $type {
  player - event - site {
   lassign [::application::assistant::ActiveBase] base variant
   set raw [string trim [lindex [split $query ,] 0]]
   if {$raw eq ""} {set raw $query}
   set seen {}; set ranked {}
   foreach prefix [lsort -unique [list $raw [string totitle $raw] [string toupper $raw 0 0]]] {
    if {[catch {::scidb::db::match $type $base $variant 256 $prefix} rows]} {continue}
    foreach row $rows {
     lassign $row freq name
     if {$freq > 0 && ![dict exists $seen $name] && [NameMatch $query $name]} {
      dict set seen $name 1
      set exact [string equal -nocase [string trim [lindex [split $name ,] 0]] $raw]
      lappend ranked [list [expr {$exact ? 1000000+$freq : $freq}] $name]
     }
    }
   }
   set sorted [lsort -integer -decreasing -index 0 $ranked]
   return [lrange [lmap item $sorted {lindex $item 1}] 0 7]
  }
  database {
   set w [::application::database::switcherWidget]
   foreach base [$w bases] {
    if {[NameMatch $query [::util::databaseName $base no]] || $query eq $base} {lappend values $base}
   }
   return $values
  }
  engine {
   catch {info exists ::engine::Engines}
   foreach e $::engine::Engines {lappend values [dict get $e Name]}
  }
  pane {set values [[::application::twm board] leaves]}
  tab {foreach tab [.application.nb tabs] {lappend values [lindex [split $tab .] end]}}
  motif {return [MotifLookup $query]}
  opening - eco {return [EcoLookup $type $query]}
  move {
   if {![catch {::scidb::ai::moveFacts $query} facts]} {return [list $query]}
   return {}
  }
 }
 set out {}
 foreach v $values {if {[NameMatch $query $v]} {lappend out $v}}
 return [lrange [lsort -unique $out] 0 7]
}
proc ::commandline::CriteriaWord {slot} {
 switch -- $slot {
  min_elo {return {min elo}}
  both_min_elo {return {both elo}}
  colour - color - color_ {return colour}
  default {return $slot}
 }
}
proc ::commandline::CompleteText {template arguments {missing {}}} {
 set words {}
 foreach word $template {
  if {[lindex $word 0] eq "?"} {
   set group [lrange $word 1 end]; set include 0
   foreach item $group {if {[string index $item 0] eq "@" && [dict exists $arguments [Key [string range $item 1 end]]]} {set include 1}}
   if {$include} {lappend words [CompleteText $group $arguments $missing]}
  } elseif {[string index $word 0] eq "@"} {
   set slot [string range $word 1 end]; set key [Key $slot]
   if {$slot eq "criteria"} {
    dict for {k v} $arguments {
     # Match normalizes playerless draws for action validation. Completion
     # must serialize the grammar's word so the next keystroke can parse it.
     if {$k eq "result" && $v eq "1/2-1/2"} {set v draw}
     lappend words [CriteriaWord $k] $v
    }
    if {[llength $missing]} {
     set first [lindex $missing 0]
     lappend words [CriteriaWord $first] <$first>
    } elseif {![dict size $arguments]} {
     lappend words player <player>
    }
   } elseif {[dict exists $arguments $key]} {
    set value [dict get $arguments $key]
    if {[FileSlot? $slot]} {set value [QuoteArgument $value]}
    # Match stores the opponent's colour; the sentence the user types is
    # their own side, so put it back before it is matched again.
    if {$key eq "colour"} {set value [expr {$value eq "white" ? "black" : "white"}]}
    lappend words $value
   } else {lappend words <$slot>}
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
 # An async handler returns \x00later:<N> and answers through Resolve. It is
 # not a finished run: never record it as a pick yet, and hide the raw token.
 if {[IsLater $result]} {AwaitLater $result $row; return ""}
 if {![string match "error:*" $result] && ![string match "declined*" $result] && [llength [info commands ::commandline::RecordPick]]} {RecordPick $row}
 return $result
}
proc ::commandline::IsLater {result} {
 return [string match "\x00later:*" $result]
}
proc ::commandline::AwaitLater {token row} {
 variable Pending
 dict set Pending $token $row
}
# Called by ::application::assistant::Resolve for a token that belongs to a
# queued command rather than an assistant turn. Returns 0 when unknown.
proc ::commandline::ResolveLater {token reply} {
 variable Pending
 if {![dict exists $Pending $token]} {return 0}
 set row [dict get $Pending $token]
 catch {dict unset Pending $token}
 catch {set reply [::application::assistant::Scrub $reply]}
 if {[string match "error:*" $reply]} {
  catch {::ui::message $reply error}
 } else {
  catch {::ui::message $reply}
  if {[llength [info commands ::commandline::RecordPick]]} {catch {RecordPick $row}}
 }
 return 1
}
namespace eval ::application::assistant {}
# A separate, tools-free conversation path. Even unsolicited provider tool calls
# are ignored, so model output can never reach the action registry.
proc ::application::assistant::QuestionFacts {text} {
 set facts ""
 catch {set facts [DoCurrentGame]}
 if {[regexp -nocase {annotat|comment|note} $text]
  && [llength [info commands ::ai::factcheck::game]]} {
  if {![catch {set checked [::ai::factcheck::game]}]} {
   append facts "\n\nStored-annotation fact-check ([dict get $checked checked] annotation(s) checked, [dict get $checked flagged] contradicted):"
   foreach finding [dict get $checked findings] {
    append facts "\n- [dict get $finding move]: [dict get $finding text] -> [join [dict get $finding problems] {; }]"
   }
   if {![dict get $checked flagged]} {append facts " none."}
  }
 }
 return $facts
}
proc ::application::assistant::Question {text} {
 variable Priv
 if {$Priv(busy)} {return 0}
 if {[catch {
  ConfigureProvider
  set facts [QuestionFacts $text]
  set messages [list [dict create role system content "Answer this question read-only. You cannot run commands or change data. Chess facts must come from the supplied board record; do not invent evaluations. Board record:\n[Scrub $facts]"] [dict create role user content $text]]
  Append user $text
  SetBusy 1
  ::ai::provider::chatAsync $messages {} ::application::assistant::QuestionReply
 } err]} {
  SetBusy 0
  catch {Append error $err}
  return 0
 }
 return 1
}
proc ::application::assistant::QuestionReply {result} {
 SetBusy 0
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
