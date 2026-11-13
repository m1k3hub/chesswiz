package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
namespace eval ::scidb::test::nativeclip {}
proc ::scidb::test::nativeclip::pixel {table row} {
    for {set y 2} {$y<[winfo height $table.t]} {incr y 2} {
        if {[lindex [::table::identify $table 80 $y] 0] eq $row} {return [list 80 $y]}
    }
    error "row $row is not mapped"
}
proc ::scidb::test::nativeclip::click {table row {control 0}} {
    lassign [pixel $table $row] x y
    event generate $table.t <Motion> -warp 1 -x $x -y $y
    update
    set state [expr {$control ? 4 : 0}]
    event generate $table.t <ButtonPress-1> -time [expr {[clock milliseconds]&0x7fffffff}] -state $state -x $x -y $y
    event generate $table.t <ButtonRelease-1> -time [expr {[clock milliseconds]&0x7fffffff}] -state $state -x $x -y $y
    update
    puts [list SELECTION row $row control $control binding [bind $table.t <Control-ButtonPress-1>] raw [$table.t selection get] rowTags [lmap item [$table.t selection get] {$table.t item tag names $item}] primary [::scrolledtable::selection [winfo parent [winfo parent $table]]]]
}
set pgn [file join $::env(HOME) native-copy.pgn]
set f [open $pgn w]
for {set i 0} {$i<4} {incr i} {
    puts $f "\[Event \"Generated $i\"\]\n\[White \"Generated White $i\"\]\n\[Black \"Generated Black $i\"\]\n\[Result \"*\"\]\n\n1. e4 e5 *\n"
}
close $f
set src [file join $::env(HOME) native-copy.sci]
::action::run menu.file.new.normal [dict create filename $src]
::action::run menu.file.import.pgn [dict create filename $pgn]
::application::database::switchToBase $src
::application::switchTab database
update
set manager $::application::database::Vars(games).twm
set path [set ::application::database::games::${manager}::Priv(table)]
set table [::scrolledtable::table $path]
::gamestable::select $path none
update
tcltest::test context-native-copy-three {Ctrl-click3 rows is a native selection and C3 copies exactly3 with plural menu label} -body {
    foreach row {0 1 2} {::scidb::test::nativeclip::click $table $row 1}
    set object [::context::CurrentObject C3]
    menu .nativeClip -tearoff 0
    ::context::Build C3 .nativeClip $object
    set label {}
    for {set i 0} {$i<=[.nativeClip index end]} {incr i} {
        if {[.nativeClip type $i] eq "command" && [lrange [.nativeClip entrycget $i -command] 0 1] eq {::action::run c3.copy_game}} {set label [string trim [.nativeClip entrycget $i -label]]}
    }
    set reply [::action::run c3.copy_game [dict create object $object]]
    list [dict get $object count] $label $reply [::game::clipboard::count] [lindex [lindex [::game::clipboard::entries] 0] 2]
} -cleanup {destroy .nativeClip} -result {3 {Copy Games} 3 3 {0 1 2}}
tcltest::test context-native-copy-toggle {Ctrl-click removes just that row from the native copy selection} -body {
    ::scidb::test::nativeclip::click $table 1 1
    ::action::run c3.copy_game [dict create object [::context::CurrentObject C3]]
    list [::game::clipboard::count] [lindex [lindex [::game::clipboard::entries] 0] 2]
} -result {2 {0 2}}
tcltest::test context-native-copy-single-again {normal click returns to one row and C3 copies only that row} -body {
    ::scidb::test::nativeclip::click $table 0
    ::action::run c3.copy_game [dict create object [::context::CurrentObject C3]]
    list [::game::clipboard::count] [lindex [lindex [::game::clipboard::entries] 0] 2]
} -result {1 0}
tcltest::test context-native-copy-clear {toggling the last row clears the selected object and refuses contextual copy} -body {
    ::scidb::test::nativeclip::click $table 0 1
    list [::context::CurrentObject C3] [string match error:* [::action::run c3.copy_game]]
} -result {{} 1}
tcltest::test context-native-copy-after-clear {a new Ctrl-click after clearing copies only its new row} -body {
    ::scidb::test::nativeclip::click $table 1 1
    ::action::run c3.copy_game [dict create object [::context::CurrentObject C3]]
    list [::game::clipboard::count] [lindex [lindex [::game::clipboard::entries] 0] 2]
} -result {1 1}
set incompatible [file join $::env(HOME) native-three.sci]
::action::run menu.file.new.three [dict create filename $incompatible]
tcltest::test context-native-copy-variant-guard {unsupported target disables the shared Paste action and refuses assistant mutation with a reason} -body {
    set object [dict create base $incompatible variant ThreeCheck]
    set reason [::context::WhyDisabled c3.paste_games $object]
    set reply [::application::assistant::runTool game.paste [dict create base $incompatible variant ThreeCheck]]
    list [dict get [::menu::state c3.paste_games $object] enabled] [::context::Enabled c3.paste_games $object] \
        [string match {*variant*not supported*} $reason] [string match error:* $reply] [::scidb::db::count games $incompatible ThreeCheck]
} -result {0 0 1 1 0}
::game::clipboard::clear
::tcltest::cleanupTests
