package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::pending {
    proc call {id args} {
        set result [::knowledge::RunAction $id $args]
        if {[string match error:* $result]} {puts stderr $::errorInfo; error $result}
        return $result
    }
    proc choose {id args} {
        variable result
        set result [::knowledge::RunAction $id $args]
        puts "PENDING $id: $result"; flush stdout
        if {[string match error:* $result]} {
            set ::fsbox::action_ refuse_drop
            set ::database::switcher::trigger_ cancel
            set ::move::trigger_ 1
            catch {::tk::MenuUnpost $::application::board::board.popup_confirm}
            set ::move::_wait 0
        }
    }
}
tcltest::test pending-move {real move-insertion modal accepts explicit operation and cancellation} -setup {
    ::scidb::test::actions::ready
    ::scidb::test::pending::call open_database path [::scidb::test::actions::fixture]
    ::scidb::test::pending::call open_game number 1
    ::scidb::game::go start
    set old [array get ::move::Options]
    set ::move::Options(addVarWithoutAsking) 0
    set ::move::Options(askToReplaceMoves) 1
} -body {
    set results {}
    foreach action {variation replace cancel} {
        after 250 [list ::scidb::test::pending::choose move.choice action $action]
        lappend results [::move::ConfirmReplaceMove menu {}] $::scidb::test::pending::result
        update
    }
    lappend results [string match error:* [::knowledge::RunAction move.choice {action cancel}]]
    set results
} -cleanup {array set ::move::Options $old} -result {variation variation replace replace cancel cancel 1}

tcltest::test pending-player-trace {trace opens and closes on a real generated-game player card} -setup {
    ::scidb::test::actions::ready
    set pgn [::scidb::test::actions::fixture]
    ::scidb::test::pending::call open_database path $pgn
    ::playercard::show $pgn Normal 0 white
    update
    set old [array get ::playercard::Options]
} -body {
    set key [lindex [::scidb::test::pending::call playercard.trace] 0]
    set result {}
    foreach kind {html log} {
        foreach enabled {1 1 0 0} {
            lappend result [::scidb::test::pending::call playercard.trace key $key kind $kind enabled $enabled]
        }
    }
    lappend result [string match error:* [::knowledge::RunAction playercard.trace {key absent}]]
    set result
} -cleanup {
    foreach key [::scidb::test::pending::call playercard.trace] {destroy $::playercard::Vars($key)}
    array set ::playercard::Options $old
} -result {1 1 0 0 1 1 0 0 1}

tcltest::test pending-promotion {real native promotion menu applies an underpromotion} -setup {
    ::scidb::test::actions::ready
    ::scidb::test::pending::call set_position fen {7k/P7/8/8/8/8/8/7K w - - 0 1}
    update
} -body {
    after 250 [list ::scidb::test::pending::choose move.promotion piece n]
    set added [::move::DoAddMove 48 56 0]
    update
    list $added $::scidb::test::pending::result [string index [::scidb::pos::board] 56] \
        [string match error:* [::knowledge::RunAction move.promotion {piece q}]]
} -result {1 n N 1}

tcltest::test pending-copy-cancel {native database drag-copy cancellation preserves both databases} -setup {
    ::scidb::test::actions::ready
    set src [::scidb::test::actions::fixture]
    ::scidb::test::pending::call open_database path $src
    set dst [file join $::env(HOME) pending-copy.sci]
    ::scidb::test::pending::call menu.file.new.normal filename $dst
    ::application::switchTab database
    update
    set parent $::application::database::Vars(switcher)
} -body {
    after 250 [list ::scidb::test::pending::choose database.copy_choice parent $parent action cancel]
    ::database::switcher::CopyDatabase $parent $src $dst Normal 0 0
    list $::scidb::test::pending::result [::scidb::db::count games $src Normal] \
        [::scidb::db::count games $dst Normal] \
        [string match error:* [::knowledge::RunAction database.copy_choice [list parent $parent action cancel]]]
} -cleanup {
    catch {::application::database::closeBase .application $dst}
    catch {file delete -force $dst}
    ::application::switchTab board
} -result {cancel 1 0 1}

tcltest::test pending-drop {native drop choice copies real file bytes and cancellation does not move them} -setup {
    ::scidb::test::actions::ready
    set dir [file join $::env(HOME) pending-drop]
    file mkdir $dir [file join $dir target]
    set src [file join $dir generated.txt]
    set ch [open $src w]; puts -nonewline $ch Generated; close $ch
    toplevel .pendingdrop
    ::fsbox::fsbox .pendingdrop.picker open -initialdir $dir -filetypes {{{Text files} {.txt}}}
    pack .pendingdrop.picker -fill both -expand 1
    update
    set w .pendingdrop.picker
} -body {
    after 250 [list ::scidb::test::pending::choose files.drop_choice widget $w action copy]
    set copied [::fsbox::AskAboutAction $w [file join $dir target] [list file://$src] {copy move}]
    update
    set dest [file join $dir target generated.txt]
    set ch [open $dest]; set bytes [read $ch]; close $ch
    after 250 [list ::scidb::test::pending::choose files.drop_choice widget $w action cancel]
    set canceled [::fsbox::AskAboutAction $w $dir [list file://$dest] {copy move}]
    update
    list $copied $bytes $canceled [file exists $src] [file exists $dest] \
        [string match error:* [::knowledge::RunAction files.drop_choice [list widget $w action cancel]]]
} -cleanup {destroy .pendingdrop; file delete -force $dir} -result {copy Generated refuse_drop 1 1 1}

namespace eval ::scidb::test::pending {
    proc tags {} {
        variable tagResult
        set tagResult {}
        set dlg [lindex [call save.tags] 0]
        if {[catch {
            call save.tags dialog $dlg operation set name GeneratedTag value Generated
            call save.tags dialog $dlg operation set name WhiteTeam value GeneratedWhite
            call save.tags dialog $dlg operation set name BlackTeam value GeneratedBlack
            set values [call save.tags dialog $dlg]
            lappend tagResult [dict get $values GeneratedTag] [dict get $values WhiteTeam] [dict get $values BlackTeam]
            set t [set ::${dlg}::Priv(taglist)]
            lappend tagResult [$t item element cget $::dialog::save::Item(GeneratedTag) value elemText -text]
            call save.tags dialog $dlg operation remove name GeneratedTag
            lappend tagResult [info exists ::dialog::save::Lookup(GeneratedTag)] \
                [string match error:* [::knowledge::RunAction save.tags [list dialog $dlg operation remove name White]]]
        } err]} {set tagResult $err}
        ::dialog::save::Withdraw $dlg
    }
}
tcltest::test pending-tags {real save form accepts explicit tag values and removal without inline entry} -setup {
    ::scidb::test::actions::ready
    ::scidb::test::pending::call new_game
    set slot [::scidb::game::current]
} -body {
    after 250 ::scidb::test::pending::tags
    set dlg [::dialog::save::open .application $::scidb::clipbaseName Normal $slot]
    set ::scidb::test::pending::tagResult
} -cleanup {catch {destroy $dlg}} -result {Generated GeneratedWhite GeneratedBlack Generated 0 1}

tcltest::test pending-match-fields {native field selection is idempotent, enumerable, and rejects unknown fields} -setup {
    set old [array get ::dialog::save::Selection]
} -body {
    set result {}
    foreach field {player:fideID event:country} {
        foreach enabled {0 0 1 1} {lappend result [::scidb::test::pending::call save.match_fields field $field enabled $enabled]}
    }
    lappend result [string match error:* [::knowledge::RunAction save.match_fields {field player:invalid enabled 1}]]
    set result
} -cleanup {array set ::dialog::save::Selection $old} -result {0 0 1 1 0 0 1 1 1}

namespace eval ::scidb::test::pending {
    proc noop {args} {}
    proc yes {args} {return 1}
    proc no {args} {return 0}
}
tcltest::test pending-clipbase {real clipboard contents clear only after confirmation, preserving the source} -setup {
    ::scidb::test::actions::ready
    set src [::scidb::test::actions::fixture]
    ::scidb::test::pending::call open_database path $src
    ::scidb::view::copy $src 0 $::scidb::clipbaseName Normal {} ::scidb::test::pending::noop {} ::scidb::test::pending::noop {}
    set old $::action::ConfirmHook
} -body {
    set before [::scidb::db::count games $::scidb::clipbaseName Normal]
    set ::action::ConfirmHook ::scidb::test::pending::no
    ::knowledge::RunAction database.clear_clipbase {}
    set kept [::scidb::db::count games $::scidb::clipbaseName Normal]
    set ::action::ConfirmHook ::scidb::test::pending::yes
    set cleared [::scidb::test::pending::call database.clear_clipbase]
    list [expr {$before>0}] [expr {$kept==$before}] $cleared [::scidb::db::count games $src Normal]
} -cleanup {set ::action::ConfirmHook $old} -result {1 1 0 1}

tcltest::test pending-presets {built-in random and named starting positions create real games, with direct error boundaries} -setup {
    ::scidb::test::actions::ready
} -body {
    set result {}
    foreach preset {Normal Chess960 Symm960 Shuffle 4015 4012} {
        set fen [::scidb::test::pending::call board.start_preset preset $preset]
        lappend result [expr {$fen eq [::scidb::pos::fen]}]
    }
    lappend result [string match error:* [::knowledge::RunAction board.start_preset {preset Invalid}]] \
        [string match error:* [::knowledge::RunAction board.start_preset {preset Normal target setup}]]
    set result
} -result {1 1 1 1 1 1 1 1}

tcltest::test pending-piece-preview {native design configuration changes the actual piece canvas and square images} -setup {
    ::scidb::test::actions::ready
    ::board::acquireWorkingSet piece
    ::board::piece::openConfigDialog .application 64 {} {} {}
    update
} -body {
    set result {}
    foreach piece {k q r b n p} {
        lappend result [dict get [::scidb::test::pending::call board.piece_preview piece $piece] piece]
    }
    foreach layout {ll ld dd dl ldld dldl} {
        lappend result [dict get [::scidb::test::pending::call board.piece_preview layout $layout] layout]
    }
    lappend result [expr {[llength [$::board::piece::Widget(piece,w) find withtag piece]]==1}] \
        [expr {[image width photo_Square(lite,config)]>0}]
    set result
} -cleanup {catch {destroy $::board::piece::Widget(dialog)}} -result {k q r b n p ll ld dd dl ldld dldl 1 1}

tcltest::test pending-layout-group {native layout grouping switches both ways and explicit repeats preserve mode} -setup {
    ::scidb::test::actions::ready
    set twm [::menu::CurrentTWM]
    set uid editor
    set container [$twm parent [$twm leaf $uid]]
    set old [expr {[$twm ismultiwindow $container] ? "multiwindow" : "notebook"}]
} -body {
    set result {}
    foreach mode {notebook notebook multiwindow multiwindow} {
        ::scidb::test::pending::call layout.group pane $uid mode $mode
        update
        set group [$twm parent [$twm leaf $uid]]
        lappend result [expr {[$twm ismultiwindow $group] ? "multiwindow" : "notebook"}]
    }
    lappend result [string match error:* [::knowledge::RunAction layout.group {pane invalid mode notebook}]]
    set result
} -cleanup {catch {::scidb::test::pending::call layout.group pane $uid mode $old};update} -result {notebook notebook multiwindow multiwindow 1}

tcltest::test pending-layout-align {native line alignment uses the real pane height and rejects unsupported panes} -setup {
    ::scidb::test::actions::ready
    set twm [::menu::CurrentTWM]
    set uid {}
    foreach frame [$twm collect visible] {
        set candidate [$twm uid $frame]
        if {[info exists ::application::Vars(align:board:$candidate)] && $::application::Vars(align:board:$candidate)} {set uid $candidate;break}
    }
    if {$uid eq ""} {error "no line-aligning pane"}
} -body {
    set expected [::application::twm::ComputeAlignedHeight $twm $uid]
    set applied [::scidb::test::pending::call layout.align_lines pane $uid]
    update
    list [expr {$expected==$applied}] [expr {[winfo height [$twm leaf $uid]]>0}] \
        [string match error:* [::knowledge::RunAction layout.align_lines {pane invalid}]]
} -result {1 1 1}
tcltest::cleanupTests
