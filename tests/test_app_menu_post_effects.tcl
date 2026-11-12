# Native effects for the dynamically posted Game rows (REG-009).
package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
namespace eval ::scidb::test::posted {}
set postedBase [::scidb::test::actions::fixture]
::action::run open_database [dict create path $postedBase]
set postedSource [::game::new .application -base $postedBase -variant Normal -number 0 -lock 1]
::application::pgn::select $postedSource
update
::scidb::game::copy game $::scidb::clipbaseName $postedSource original
set postedClip [expr {[::scidb::db::count games $::scidb::clipbaseName Normal]-1}]
::menu::gameNew .application
set postedPrimary [::scidb::game::current]
::scidb::game::import $postedPrimary {1. d4 d5 *} {} {} -encoding utf-8 -variation 0
update
if {$postedSource == $postedPrimary} {error {fixture did not create two distinct game tabs}}
foreach {id source} [list menu.game.merge_clip [list $::scidb::clipbaseName Normal $postedClip] menu.game.merge_tab [::scidb::game::sink? $postedSource]] {
 tcltest::test posted-effect-$id {merge row opens the real preview with its intended secondary game} -body {
  ::scidb::game::switch $postedPrimary
  set reply [::action::invoke $id]
  update
  set mapped [expr {[winfo exists .mergeDialog] && [winfo ismapped .mergeDialog]}]
  set selected [expr {$source in $::merge::Priv(secondaries)}]
  puts [list POSTED_EFFECT $id mapped $mapped primary $::merge::Priv(primary) secondaries $::merge::Priv(secondaries) expected $source reply $reply]
  list [string match error:* $reply] $mapped [expr {$::merge::Priv(primary) == $postedPrimary}] $selected
 } -cleanup {if {[winfo exists .mergeDialog]} {.mergeDialog.cancel invoke};update} -result {0 1 1 1}
}

proc ::scidb::test::posted::closeImporter {position dialog} {
 if {[winfo exists $dialog] && [winfo ismapped $dialog]} {
  set ::scidb::test::posted::importer 1
  ::import::Close $position $dialog
 } else {set ::scidb::test::posted::timer [after 100 [list ::scidb::test::posted::closeImporter $position $dialog]]}
}
tcltest::test posted-effect-paste-tab {paste row opens the actual PGN importer for the current tab} -body {
 ::scidb::game::switch $postedPrimary
 clipboard clear
 clipboard append {1. c4 e5 *}
 set dialog $::application::pgn::Vars(frame:$postedPrimary).importOnePgnGame$postedPrimary
 set ::scidb::test::posted::importer 0
 set ::scidb::test::posted::timer [after 100 [list ::scidb::test::posted::closeImporter $postedPrimary $dialog]]
 set reply [::action::invoke menu.game.paste_tab]
 puts [list POSTED_EFFECT menu.game.paste_tab dialog $dialog observed $::scidb::test::posted::importer reply $reply]
 list [string match error:* $reply] $::scidb::test::posted::importer
} -cleanup {after cancel $::scidb::test::posted::timer;catch {::import::Close $postedPrimary $dialog};update} -result {0 1}

tcltest::test posted-effect-history {recent history loads the real generated history entry} -body {
 ::scidb::game::switch $postedPrimary
 set expected [lindex [lindex $::game::History 0] 1]
 set reply [::action::invoke menu.game.history.recent]
 update
 set link [::scidb::game::link? [::scidb::game::current]]
 # History keys contain base, codec, game number, variant.
 lassign $expected base codec number variant
 puts [list POSTED_EFFECT menu.game.history.recent link $link expected [list $base $variant $number] reply $reply]
 list [string match error:* $reply] [expr {[lrange $link 0 2] eq [list $base $variant $number]}]
} -result {0 1}
::tcltest::cleanupTests
