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
  find {player color result opponent eco from to event min_elo both_min_elo pattern} {Find games}
  setup {opening after} {Set up opening}
  trends {} {Opening trends}
  review {games player} {Review my games}
  my_score {player} {My score}
  study {player} {Study plan}
  stop {engine} {Stop engine}
  set_threads {engine threads} {Set engine threads}
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
   args $spec handler [list ::commandline::Action $name] ai 0 operator 0 confirm [expr {$name eq "export.replace"}]]
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
   SelectDatabase [Get $arguments database]
   return [::action::run import_games [dict create files [list [Get $arguments files]]]]
  }
  compact - convert {
   SelectDatabase [Get $arguments database]
   return [::action::run ${name}_database]
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
  trends {
   lassign [::application::assistant::ActiveBase] base variant
   return [::ai::trend::factsText [::ai::trend::facts $base $variant]]
  }
  find {
   set result [::application::assistant::DoSearchGames $arguments]
   if {[string match "error:*" $result]} {return $result}
   set shown [::application::assistant::DoShowSearch]
   return "$result\n$shown"
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
   return [::application::assistant::DoOpenGame [expr {$number+1}]]
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
 regexp {^([0-9]+)\.} $after -> moveNum
 foreach moves $lines {
  if {$targetMove ne "" && [string first $targetMove $moves] < 0} {continue}
  set tokens [EcoMovesTokens $moves]
  if {[llength $wanted]} {
   if {$moveNum > 0} {
    set at [expr {2*$moveNum-2}]
    if {[lindex $tokens $at] ne $targetMove} {continue}
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
