# Named paste/merge/history effects retain the existing real-surface oracles.
source tests/test_app_menu_post_effects.tcl
source tests/app_menu_reseal_effect_support.tcl

tcltest::test reg6-posted-paste-clip {posted clipboard paste copies the remembered generated game into the selected database} -body {
 ::game::clipboard::copy $postedBase Normal {0}
 ::application::database::switchToBase $::scidb::clipbaseName
 ::application::database::SwitchVariant Normal
 set before [::scidb::db::count games $::scidb::clipbaseName Normal]
 set reply [::reg5effect::postInvoke menu.game.paste_clip]
 set after [::scidb::db::count games $::scidb::clipbaseName Normal]
 set tags [::scidb::db::get tags [expr {$after-1}] $::scidb::clipbaseName Normal]
 puts [list EFFECT menu.game.paste_clip before $before after $after tags $tags reply $reply]
 list [string match error:* $reply] [expr {$after == $before+1}] [expr {[list White {Generated White}] in $tags}]
} -result {0 1 1}

tcltest::test reg6-posted-iccf {native ICCF menu opens the actual editable settings form} -body {
 ::reg5effect::postInvoke menu.tools.iccf
 set dlg .application.iccfSettings
 list [winfo ismapped $dlg] [wm title $dlg] [$dlg.f.user cget -textvariable] [$dlg.f.pass cget -show] [$dlg.f.endpt cget -textvariable]
} -cleanup {
 if {[winfo exists .application.iccfSettings]} {.application.iccfSettings.btns.cancel invoke}
} -result {1 {ICCF XFCC Settings} ::iccf::xfcc::Config(username) * ::iccf::xfcc::Config(endpoint)}
::scidb::test::actions::cleanup
::tcltest::cleanupTests
