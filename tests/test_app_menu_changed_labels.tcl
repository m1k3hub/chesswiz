# Baseline 08ba7f1bb serialized registry delta; regenerated at W-labels-root HEAD (142 IDs).
# W-term4: GAP-003 drops required-argument rows from the bare Ask list, so
# opening_line and menu.view.layout.fold are not Ask-visible (140 IDs).
# Exercise every changed ID through live states and the actual typed Ask list.
# Native labels are read independently from mc variables / widget tooltips.
package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::changedLabels {
    variable ids {
        c5.sort.event.event.ascending
        c5.sort.event.event.descending
        c5.sort.event.eventCountry.ascending
        c5.sort.event.eventCountry.descending
        c5.sort.event.eventDate.ascending
        c5.sort.event.eventDate.descending
        c5.sort.event.eventMode.ascending
        c5.sort.event.eventMode.descending
        c5.sort.event.eventType.ascending
        c5.sort.event.eventType.descending
        c5.sort.event.frequency.ascending
        c5.sort.event.frequency.descending
        c5.sort.event.site.ascending
        c5.sort.event.site.descending
        c5.sort.event.timeMode.ascending
        c5.sort.event.timeMode.descending
        c5.sort.player.federation.ascending
        c5.sort.player.federation.descending
        c5.sort.player.federationId.ascending
        c5.sort.player.federationId.descending
        c5.sort.player.firstName.ascending
        c5.sort.player.firstName.descending
        c5.sort.player.frequency.ascending
        c5.sort.player.frequency.descending
        c5.sort.player.lastName.ascending
        c5.sort.player.lastName.descending
        c5.sort.player.playerInfo.ascending
        c5.sort.player.playerInfo.descending
        c5.sort.player.rating1.ascending
        c5.sort.player.rating1.descending
        c5.sort.player.rating2.ascending
        c5.sort.player.rating2.descending
        c5.sort.player.ratingType.ascending
        c5.sort.player.ratingType.descending
        c5.sort.player.sex.ascending
        c5.sort.player.sex.descending
        c5.sort.player.title.ascending
        c5.sort.player.title.descending
        c5.sort.player.type.ascending
        c5.sort.player.type.descending
        c5.sort_ascending
        c5.sort_descending
        engine_play
        menu.analysis.explain.move
        menu.file.recent.clear
        menu.help.donate
        menu.help.donate_kofi
        menu.help.donate_paypal
        menu.help.support
        menu.training.brief
        menu.training.check_results
        menu.training.engine_match
        menu.training.lichess_events
        menu.training.lichess_puzzles
        menu.training.lichess_social
        menu.training.lichess_tv
        menu.training.play_lichess
        menu.training.play_online
        menu.training.stream
        menu.training.studyplan
        menu.training.training_set
        menu.view.layout.manage
        set_position
        toolbar.analysis_control.0
        toolbar.analysis_control.1
        toolbar.analysis_control.12
        toolbar.analysis_control.2
        toolbar.analysis_control.3
        toolbar.analysis_control.4
        toolbar.analysis_control.5
        toolbar.analysis_control.8
        toolbar.analysis_control.9
        toolbar.analysis_info.2
        toolbar.board_control.0
        toolbar.board_control.1
        toolbar.board_control.2
        toolbar.board_control.3
        toolbar.board_control.4
        toolbar.board_control.5
        toolbar.board_control.7
        toolbar.board_control.8
        toolbar.board_database.0
        toolbar.board_database.1
        toolbar.board_database.2
        toolbar.board_database.3
        toolbar.board_database.4
        toolbar.board_database.5
        toolbar.board_layout.0
        toolbar.board_layout.1
        toolbar.board_layout.2
        toolbar.board_tools.0
        toolbar.database_clipbase.0
        toolbar.database_clipbase.1
        toolbar.database_clipbase.2
        toolbar.database_clipbase.3
        toolbar.database_clipbase.4
        toolbar.database_clipbase.5
        toolbar.database_switcher.0
        toolbar.database_switcher.1
        toolbar.database_switcher.2
        toolbar.database_switcher.3
        toolbar.database_switcher.4
        toolbar.database_switcher.5
        toolbar.editor_display.0
        toolbar.editor_display.1
        toolbar.editor_display.2
        toolbar.editor_display.4
        toolbar.editor_display.5
        toolbar.editor_game.0
        toolbar.editor_game.1
        toolbar.editor_history.0
        toolbar.editor_history.1
        toolbar.editor_languages.0
        toolbar.games_control.0
        toolbar.games_control.1
        toolbar.games_control.2
        toolbar.games_control.3
        toolbar.games_control.4
        toolbar.games_layout.0
        toolbar.games_layout.1
        toolbar.online.abort
        toolbar.online.accept
        toolbar.online.analyse
        toolbar.online.autoqueen
        toolbar.online.chat
        toolbar.online.claim
        toolbar.online.close
        toolbar.online.decline
        toolbar.online.draw
        toolbar.online.flip
        toolbar.online.live
        toolbar.online.resign
        toolbar.online.takeback
        toolbar.playertable_options.0
        toolbar.tree_control.0
        toolbar.tree_control.1
        toolbar.tree_control.3
        toolbar.tree_control.4
        toolbar.tree_switcher.0
        view.focus_follows_size
    }
    proc offlineBackend {args} {return {}}
proc oracleLabel {id} {
 if {$id in {c5.sort_ascending c5.sort_descending}} {
  return [set ::gamestable::mc::Sort[string totitle [lindex [split $id _] end]]]
 }
 if {[regexp {^c5\.sort\.(player|event)\.([^.]+)\.} $id -> kind column]} {
  # Native table heading keys, independent of the registry's resolver/map.
  if {$kind eq "player"} {
   set keys {lastName playertable::F_LastName firstName playertable::F_FirstName federationId playertable::F_FederationId type playertable::T_Type sex playertable::T_Sex rating1 playertable::T_Rating1 rating2 playertable::T_Rating2 ratingType playertable::T_RatingType federation playertable::T_Federation title playertable::F_Title playerInfo playertable::T_PlayerInfo frequency playertable::F_Frequency}
  } else {
   set keys {event gamestable::F_Event eventType gamestable::T_EventType eventDate gamestable::F_EventDate eventMode gamestable::F_EventMode timeMode gamestable::T_TimeMode eventCountry gamestable::T_EventCountry site gamestable::F_Site frequency playertable::F_Frequency}
  }
  lassign [split [dict get $keys $column] :] ns _ key
  return [set ::${ns}::mc::$key]
 }
 foreach key [array names ::toolbar::Specs registry:*] {
  if {$::toolbar::Specs($key) ne $id} {continue}
  set suffix [string range $key 9 end]
  set var $::toolbar::Specs(tooltipvar:$suffix)
  if {$var ne "" && [info exists $var]} {return [string trim [string map {& {}} [set $var]]]}
  return [string trim [string map {& {}} $::toolbar::Specs(tooltip:$suffix)]]
 }
 set map {engine_play EnginePlay menu.analysis.explain.move ExplainMove menu.file.recent.clear ClearHistory menu.help.donate Donate menu.help.donate_kofi DonateKofi menu.help.donate_paypal DonatePayPal menu.help.support SupportChesswiz menu.training.brief OpponentBrief menu.training.check_results CheckGameResults menu.training.engine_match EngineMatch menu.training.lichess_events LichessEvents menu.training.lichess_puzzles LichessPuzzles menu.training.lichess_social LichessSocial menu.training.lichess_tv LichessTv menu.training.play_lichess PlayLichess menu.training.play_online PlayOnline menu.training.stream StreamOverlay menu.training.studyplan StudyPlan menu.training.training_set TrainingSetFromGames opening_line OpeningLine set_position SetStartPosition view.focus_follows_size FocusFollowsSize}
 if {[dict exists $map $id]} {return [set ::menu::mc::[dict get $map $id]]}
 if {$id eq "menu.view.layout.fold"} {return $::application::twm::mc::FoldAllTitleBars}
 if {$id eq "menu.view.layout.manage"} {return $::application::twm::mc::ManageLayouts}
 if {[string match toolbar.online.* $id]} {
  set key [lindex [split $id .] end]
  set name [dict get {resign Resign draw OfferDraw takeback Takeback abort Abort claim ClaimVictory flip Flip live Live accept AcceptDraw decline DeclineDraw analyse Analyse close CloseTab chat Send autoqueen AutoQueen} $key]
  return [set ::online::view::mc::$name]
 }
 error "no native oracle $id"
}

proc rememberAsk {} {
 variable ids; variable askSeen; variable proof; variable stage; variable lang
 foreach row [::action::labels asklist] {
  set id [lindex $row 0]
  if {$id ni $ids || [dict exists $askSeen $id]} {continue}
  # Exercise the actual entry widget and its KeyRelease filter binding.
  set entry [::application::ask::Entry]
  focus -force $entry
  $entry delete 0 end
  $entry insert 0 [lindex $row 1]
  event generate $entry <KeyRelease> -keysym a
  update idletasks
  set actual [lmap r $::application::ask::Priv(rows) {lindex $r 0}]
  if {$id ni $actual} {error "typed Ask missing $id at $stage: $actual"}
  set typedRow [lsearch -inline -index 0 $::application::ask::Priv(rows) $id]
  if {[lindex $typedRow 1] ne [lindex $row 1]} {error "typed Ask label differs: $lang $id $typedRow $row"}
  set native [oracleLabel $id]
  set registry [dict get [::action::get $id] label]
  puts [list LOCALIZED_ENTRY $lang $id native $native registry $registry ask [lindex $row 1] equal [expr {$native eq $registry && $native eq [lindex $row 1]}]]
  if {$native ne $registry || $native ne [lindex $row 1]} {error "label mismatch: $lang $id native=$native registry=$registry ask=[lindex $row 1]"}
  set state [::menu::state $id]
  if {![dict get $state visible] || ![dict get $state enabled]} {error "Ask lists unavailable $id: $state"}
  dict set askSeen $id 1
  dict set proof $id [list $stage $state [::context::CurrentObjectFor $id]]
  puts [list TYPED_ASK $id stage $stage state $state label [lindex $row 1]]
  if {[string match toolbar.online.* $id]} {
   set key [lindex [split $id .] end]
   set labelName [dict get {resign Resign draw OfferDraw takeback Takeback abort Abort claim ClaimVictory flip Flip live Live accept AcceptDraw decline DeclineDraw analyse Analyse close CloseTab chat Send autoqueen AutoQueen} $key]
   set native [set ::online::view::mc::$labelName]
   puts [list LOCALIZED_ONLINE $lang $id native $native registry [dict get [::action::get $id] label] ask [lindex $row 1] equal [expr {$native eq [lindex $row 1]}]]
  }
  ::application::ask::HideList
 }
}
    proc check {language} {
        variable ids; variable askSeen; variable proof; variable stage; variable lang
        set lang $language
        set askSeen {}; set proof {}; set stage startup
        ::menu::SwitchLanguage $lang
        update
rememberAsk

set w [::online::window::gameTab reseal:proof {Generated game} [namespace current]::offlineBackend w]
::online::view::setGame $w White Black startpos {e2e4 e7e5}
::online::view::Show $w 0
::online::view::actions $w {resign 1 draw 1 takeback 1 abort 1 claim 1}
::online::view::offer $w {Draw offered}
update
set stage online-live-offer; rememberAsk
::online::view::result $w {Game finished}
set stage online-finished; rememberAsk
::online::window::closeTab reseal:proof
catch {wm withdraw .online}
variable base
if {![info exists base]} {
 set base [::scidb::test::actions::fixture]
 ::action::run open_database [list path $base]
}
::action::run open_game {number 1 move 1 after white}
::application::switchTab board
update
set stage generated-game-board; rememberAsk
# A saved layout is a real precondition for the menu's saved-only manager.
set twm [::menu::CurrentTWM]
set reply [::knowledge::RunAction menu.view.layout.save_as {name {Generated REG011 layout} overwrite 1}]
if {[string match error:* $reply]} {error $reply}
set stage saved-layout; rememberAsk
# Named sorts follow the native selected table and its user-visible columns.
::application::switchTab database
update
foreach kind {player event} {
 ::application::database::select[string totitle $kind] $base Normal 0
 for {set i 0} {$i < 10} {incr i} {after 30;update}
 set manager $::application::database::Vars($kind).twm
 set frame [set ::application::database::${kind}::${manager}::Vars(frame:$kind)]
 set table $frame
 if {$kind eq "player"} {append table .table}
 set columns {}
 foreach id $ids {if {[string match c5.sort.$kind.* $id]} {lappend columns [lindex [split $id .] 3]}}
 foreach column [lsort -unique $columns] {::table::showColumn $table.top.table $column}
 update
 menu .entrynative -tearoff 0
 ::${kind}table::PopupMenu $table .entrynative $base Normal 0 [expr {$kind eq "player" ? "lastName" : "event"}]
 set stage $kind-all-columns; rememberAsk
 set object [::context::CurrentObject C5]
 foreach column [lsort -unique $columns] {
  ::table::hideColumn $table.top.table $column
  foreach direction {ascending descending} {
   set id c5.sort.$kind.$column.$direction
   set state [::menu::state $id $object]
   if {[dict get $state visible] || [dict get $state enabled]} {error "hidden column leaks $id: $state"}
   if {$id in [lmap row [::action::labels asklist] {lindex $row 0}]} {error "hidden column remains in Ask: $id"}
   puts [list HIDDEN_COLUMN_GUARD $id state $state]
  }
  ::table::showColumn $table.top.table $column
 }
 destroy .entrynative
}
        set missing {}
        foreach id $ids {
            if {![dict exists $askSeen $id]} {lappend missing $id}
        }
        puts "CHANGED_LABELS $lang checked=[dict size $askSeen] expected=[llength $ids] missing=$missing"
        if {[llength $missing]} {error "changed labels not exercised: $missing"}
        return [dict size $askSeen]
    }
}
::scidb::test::actions::ready
::knowledge::Ensure
foreach lang {de es it hu sv} {
    tcltest::test changed-labels-$lang {all changed native mc, registry and typed Ask labels agree} -setup {
        set savedLanguage $::mc::langID
        # This inventory deliberately covers model-dependent labels too.
        set savedProvider $::application::ai::Config(provider)
        set ::application::ai::Config(provider) stub
    } -body [list ::scidb::test::changedLabels::check $lang] -cleanup {
        ::application::ask::HideList
        catch {destroy .entrynative}
        ::menu::SwitchLanguage $savedLanguage
        set ::application::ai::Config(provider) $savedProvider
    } -result 140
}
if {[info exists ::scidb::test::changedLabels::base]} {
    # Only our generated, unmodified game is open. Close it without the
    # normal interactive release-all question, then restore user options.
    set savedReleaseQuestion $::game::Options(askAgain:releaseAll)
    set savedReleaseAnswer $::game::Options(answer:releaseAll)
    set ::game::Options(askAgain:releaseAll) 0
    set ::game::Options(answer:releaseAll) 1
    try {
        ::application::database::closeBase .application $::scidb::test::changedLabels::base
    } finally {
        set ::game::Options(askAgain:releaseAll) $savedReleaseQuestion
        set ::game::Options(answer:releaseAll) $savedReleaseAnswer
    }
}
tcltest::cleanupTests
