# Registry adapters for command grammar operations that span existing surfaces.
if {[llength [info commands ::util::source]]} {::util::source command-actions}
namespace eval ::commandline {variable Serial 0}
proc ::commandline::Get {arguments key {default {}}} {
 if {[dict exists $arguments $key]} {return [dict get $arguments $key]}
 return $default
}
proc ::commandline::RegisterActions {} {
 # Internal command adapters are not offered as model tools or duplicate menu rows.
 foreach {name keys label} {
  database.select {database} {Switch database}
  database.close {database} {Close database}
  import {files database} {Import games}
  export {scope format filename} {Export games}
  export.replace {scope format filename} {Replace exported file}
  twic {issue} {Download TWIC}
  compact {database} {Compact database}
  convert {database format} {Convert database}
  similar {number} {Find similar games}
  find {player color result opponent eco from to event site min_elo both_min_elo pattern} {Find games}
  setup {opening after} {Set up opening}
  player_stats {name} {Player statistics}
  structure_profile {player} {Player structures}
  review {games player} {Review my games}
  my_score {player} {My score}
  study {player} {Study plan}
  stop {engine} {Stop engine}
  set_threads {engine threads} {Set engine threads}
  repertoire_check {player} {Check repertoire against my games}
  best {engine} {Best move}
  play {engine time_control color} {Play engine}
  training {source pattern player} {Create puzzles}
  tournament {system engine_count time_control opening} {Run tournament}
  tab {tab} {Go to tab}
  open_result {result_index} {Open search result}
 } {
  set id command.$name
  if {[dict exists $::action::Registry $id]} {continue}
  set spec {}
  foreach key $keys {lappend spec [list $key {type string default {}}]}
  ::action::register $id [dict create label $label object {} what $label doc $label \
   args $spec handler [list ::commandline::Action $name] ai 0 operator 0 visible {expr {0}} confirm [expr {$name eq "export.replace"}]]
 }
}
proc ::commandline::RequireSuccess {result} {
 if {[string match {error:*} $result] || [string match {declined*} $result]} {error $result}
 return $result
}
proc ::commandline::SelectDatabase {base} {
 if {$base eq ""} {return}
 if {$base ni [AppSource database ""]} {error "database is no longer open"}
 ::application::database::switchToBase $base
}
# Destructive actions ask first. The answer must come before any active
# database switch, so a declined import/compact leaves the user where they
# were. Returns the validated arguments, or {} when the user declines.
proc ::commandline::ConfirmAction {id arguments} {
 set validation [::action::validateArgs $id $arguments]
 if {[lindex $validation 0] eq "error"} {error [lindex $validation 1]}
 set checked [lindex $validation 1]
 set record [::action::get $id]
 if {![dict get $record confirm] && ![dict get $record bulk]} {return $checked}
 set what [dict get $record what]
 if {$what eq ""} {
  set what "perform action '$id'"
 } elseif {[catch {set what [format $what {*}[dict values $checked]]}]} {
  set what "perform action '$id'"
 }
 set ask [expr {[dict get $record bulk] ? $::action::BulkHook : $::action::ConfirmHook}]
 if {$ask ne ""} {
  if {[catch {uplevel #0 [list $ask $what]} answer]} {set answer 0}
  if {!$answer} {return declined}
 }
 return $checked
}
proc ::commandline::ShowReport {title text} {
 if {[llength [info commands ::application::ai::showReport]] == 0} {return}
 set html "<p><b>[::application::ai::escape $title]</b></p><pre>[::application::ai::escape $text]</pre>"
 catch {::application::ai::showReport .application $title [::application::ai::htmlData $html]}
 return
}
proc ::commandline::Me {arguments} {
 set player [Get $arguments player]
 if {$player eq ""} {error "First use 'I am <player>' to select your name."}
 return $player
}
proc ::commandline::Action {name arguments} {
 switch -- $name {
  database.select {SelectDatabase [Get $arguments database]; return {}}
  database.close {return [::application::database::closeBase .application [Get $arguments database]]}
  import {
   set checked [ConfirmAction import_games [dict create files [list [Get $arguments files]]]]
   if {$checked eq "declined"} {return declined}
   SelectDatabase [Get $arguments database]
   return [::action::RunApproved import_games $checked]
  }
  compact {
   set checked [ConfirmAction compact_database {}]
   if {$checked eq "declined"} {return declined}
   SelectDatabase [Get $arguments database]
   return [::action::RunApproved compact_database $checked]
  }
  convert {
   set checked [ConfirmAction convert_database {}]
   if {$checked eq "declined"} {return declined}
   SelectDatabase [Get $arguments database]
   return [::application::assistant::DoConvertDatabase [Get $arguments format]]
  }
  export {return [Export $arguments]}
  export.replace {return [Export $arguments 1]}
  twic {
   set issue [Get $arguments issue]
   if {$issue eq ""} {return [::action::run download_games {source twic}]}
   return [::action::run download_games [dict create source url url "https://theweekinchess.com/zips/twic${issue}g.zip"]]
  }
  similar {
   set number [Get $arguments number]
   if {$number eq ""} {
    lassign [::scidb::game::sink? [::scidb::game::current]] base variant index
    if {$base ne [::scidb::db::get name] || $index < 0} {error "The board game must belong to the active database."}
    set number [expr {$index+1}]
   }
   return [::action::run similar_games [dict create number $number]]
  }
  setup {return [Setup $arguments]}
  player_stats {
   set name [Get $arguments name]
   set text [::application::assistant::DoPlayerStats $name]
   ShowReport "Player statistics: $name" $text
   return "the statistics of $name are open in the Report pane"
  }
  structure_profile {
   set player [Get $arguments player]
   set text [::application::assistant::DoStructureProfile $player "" 200]
   ShowReport "Player structures: $player" $text
   return "the structure profile of $player is open in the Report pane"
  }
  find {
   # Route through the registered search_games action so CheckArgs normalizes
   # colour, ECO ranges and player-relative results before BuildQuery sees them.
   set result [::action::run search_games $arguments]
   if {[string match "error:*" $result]} {return $result}
   set shown [::application::assistant::DoShowSearch]
   return "$result\n$shown"
  }
  repertoire_check {
   return [::action::run repertoire_check [dict create player [Me $arguments]]]
  }
  my_score {return [::action::run player_stats [dict create name [Me $arguments]]]}
  review - study {
   return [::action::run study_plan [dict create player [Me $arguments] games [expr {[Get $arguments games] eq "" ? 10 : [Get $arguments games]}]]]
  }
  set_threads {
   return [::application::assistant::DoSetEngineThreads [Get $arguments engine] [Get $arguments threads]]
  }
  stop {
   set found 0
   foreach pane [::application::assistant::RunningPanes] {
    if {[::engine::engineName $pane] eq [Get $arguments engine]} {
     RequireSuccess [::action::run stop_engine [dict create pane [::application::assistant::PaneLabel $pane]]]
     incr found
    }
   }
   if {!$found} {error "That engine is not running."}
   return "stopped [Get $arguments engine]"
  }
  best {
   set engine [Get $arguments engine]
   if {$engine ne ""} {::ai::engine::choose $engine}
   return [::action::run engine_evaluate]
  }
  play {
   set tc [Get $arguments time_control 10+2]
   if {$tc eq ""} {set tc 10+2}
   lassign [split $tc +] minutes increment
   return [::playengine::StartGame [list -engine [Get $arguments engine] -color [Get $arguments color white] -minutes $minutes -increment $increment]]
  }
  training {
   set args {}
   if {[Get $arguments source] eq "my games"} {dict set args player [Me $arguments]}
   if {[Get $arguments pattern] ne ""} {dict set args pattern [Get $arguments pattern]}
   return [::action::run training_set $args]
  }
  tournament {return [Tournament $arguments]}
  tab {::application::switchTab [Get $arguments tab]; return {}}
  open_result {
   lassign [::application::assistant::ActiveBase] base variant
   if {$base eq ""} {error "no database is open"}
   set n [Get $arguments result_index]
   set count [::scidb::view::count games $base $variant 0]
   if {$n < 1 || $n > $count} {error "the visible game list has only $count games"}
   set number [::scidb::db::get gameNumber $base $variant [expr {$n-1}] 0]
   return [::application::assistant::DoOpenGame [expr {$number+1}] "" ""]
  }
 }
 error "unknown command adapter $name"
}
proc ::commandline::Export {arguments {overwrite 0}} {
 set filename [file normalize [Get $arguments filename]]
 set format [Get $arguments format]
 if {[::scidb::db::get open? $filename]} {error "Cannot replace an open database."}
 if {[file exists $filename] && !$overwrite} {return [::action::run command.export.replace $arguments]}
 lassign [::application::assistant::ActiveBase] base variant
 set view 0; set owned 0
 try {
  if {[Get $arguments scope] eq "database"} {
   set view [::scidb::view::new $base $variant unused unused unused unused master slave]; set owned 1
  }
  switch -- $format {
   pgn {set n [::scidb::view::export $base $variant $view $filename [::export::getPgnFlags] 0 utf-8 0 {} {{* yes}} ::menu::OperationCallback {} ::menu::OperationCallback {}]}
   html {set n [::scidb::view::printHtml $base $variant $view $filename 63 {{* yes}} ::menu::OperationCallback {} ::menu::OperationCallback {}]}
   pdf {set n [::scidb::view::printPdf $base $variant $view $filename 63 ::menu::OperationCallback {} ::menu::OperationCallback {}]}
   default {error "Unsupported export format."}
  }
 } finally {if {$owned} {::scidb::view::close $base $variant $view}}
 return "Exported to $filename"
}
proc ::commandline::OpeningMoves {arguments} {
 variable OpeningLines
 EnsureEco
 set opening [Get $arguments opening]
 set after [Get $arguments after]
 set wanted [::application::assistant::MoveTokens $after]
 set targetMove [lindex $wanted end]
 set lines {}
 if {[dict exists $OpeningLines $opening]} {
  set lines [dict get $OpeningLines $opening]
 } else {
  foreach row [::scidb::ai::ecoLines [regexp -all -inline {[^\s,;:()]+} $opening]] {
   lappend lines [lindex $row 2]
  }
 }
 set choices {}
 set moveNum 0
 set side auto
 if {[regexp {^([0-9]+)\.\.\.} $after -> moveNum]} {
  set side black
 } elseif {[regexp {^([0-9]+)\.[ \t]} $after -> moveNum]} {
  set side white
 } elseif {[regexp {^([0-9]+)\.} $after -> moveNum]} {
  # "5.a6" may be White's "5. a6" without the space or Black's "5...a6"
  # compact spelling. Try White first, then Black, and keep the one that
  # actually has that move in the opening line.
  set side auto
 }
 foreach moves $lines {
  if {$targetMove ne "" && [string first $targetMove $moves] < 0} {continue}
  set tokens [EcoMovesTokens $moves]
  if {[llength $wanted]} {
   if {$moveNum > 0} {
    switch -- $side {
     white {set candidates [list [expr {2*$moveNum-2}]]}
     black {set candidates [list [expr {2*$moveNum-1}]]}
     default {set candidates [list [expr {2*$moveNum-2}] [expr {2*$moveNum-1}]]}
    }
    set at ""
    foreach candidate $candidates {
     if {[lindex $tokens $candidate] eq $targetMove} {set at $candidate; break}
    }
    if {$at eq ""} {continue}
   } else {
    set at [lsearch -exact $tokens $targetMove]
    if {$at < 0} {continue}
   }
   set tokens [lrange $tokens 0 $at]
  }
  lappend choices [list [llength $tokens] $tokens]
 }
 if {![llength $choices]} {error "No line in the opening table reaches that move."}
 set moves [lindex [lindex [lsort -integer -index 0 $choices] 0] 1]
 return [join $moves]
}
proc ::commandline::Setup {arguments} {
 set result [::ai::setup::position -moves [OpeningMoves $arguments]]
 ::application::switchTab board
 return "Opening set up: [dict get $result fen]"
}
proc ::commandline::Tournament {arguments} {
 variable Serial
 set id "command-[pid]-[clock microseconds]-[incr Serial]"
 set args [dict create name {Command tournament} kind engine system [string map {{ } -} [Get $arguments system]] \
  engine_count [Get $arguments engine_count] time_control [Get $arguments time_control 3+2] opening [Get $arguments opening] \
  expected_revision 0 idempotency $id commit 0]
 if {[dict get $args time_control] eq ""} {dict set args time_control 3+2}
 dict set args path [::td::store::DefaultPath [dict get $args name] $id]
 RequireSuccess [::action::run td.create $args]
 dict set args commit 1
 return [::action::run td.create $args]
}
