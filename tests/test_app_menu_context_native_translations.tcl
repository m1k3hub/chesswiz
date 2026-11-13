# Preserve the native mc keys used by object menus before the registry move.
# The expected keys below come from the original board/notation/table/comment/
# gamebar builders, independently of context::NativeLabels. Exercise live
# language changes, registry labels, and the actual C1 Flip Board menu row.
package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
set ::scidb::test::nativeTranslationShare $::scidb::dir::share
set ::scidb::dir::share [file normalize [file join [file dirname [info script]] .. tcl]]
set ::scidb::test::nativeTranslationLang $::mc::langID

foreach language {de es it hu sv} {
    tcltest::test context-native-translations-$language {native translated labels survive the C1-C12 registry move} -body {
        ::menu::SwitchLanguage $language
        set bad {}
        foreach {id key} {
            c1.flip_board ::overview::mc::RotateBoard
            c1.copy_fen ::setup::board::mc::CopyFen
            c1.edit_annotation ::application::pgn::mc::EditAnnotation
            c2.replace_move ::move::mc::Action(replace)
            c2.add_variation ::move::mc::Action(variation)
            c2.try_variation ::move::mc::Action(trial)
            c2.promote_variation ::application::pgn::mc::Command(variation:promote)
            c2.remove_variation ::application::pgn::mc::Command(variation:remove)
            c2.comment_before ::comment::mc::CommentBeforeMove
            c2.strip.info ::application::pgn::mc::Command(strip:info)
            c2.strip.language ::comment::mc::Language
            c3.load ::browser::mc::LoadGame
            c3.tournament ::gamestable::mc::ShowTournamentTable
            c3.open_url ::engine::mc::OpenUrl
            c4.close ::mc::Close
            c4.properties ::application::database::mc::Properties
            c4.maintenance ::menu::mc::Maintenance
            c5.player_card ::playertable::mc::ShowPlayerCard
            c5.event_url ::engine::mc::OpenUrl
            c6.add_sequence ::application::analysis::mc::Add(seq)
            c6.best_first ::application::analysis::mc::BestFirstOrder
            c6.lock_engine ::application::analysis::mc::LockEngine
            c8.start_search ::application::tree::mc::StartSearch
            c8.lock_reference ::application::tree::mc::LockReferenceBase
            c9.flip_board ::overview::mc::RotateBoard
            c9.not.font_inc ::font::mc::IncreaseFontSize
            c9.not.font_dec ::font::mc::DecreaseFontSize
            c9.not.markers ::pgn::setup::mc::Display(markers)
            c9.analysis.lines ::application::analysis::mc::LinesPerVariation
            c10.optimize ::table::mc::OptimizeColumns
            c10.fit ::table::mc::FitColumns
            c10.squeeze ::table::mc::SqueezeColumns
            c11.insert_symbol ::comment::mc::InsertSymbol
            c11.copy_text ::comment::mc::CopyText
            c11.format ::comment::mc::Formatting
            c12.copy_game ::gamebar::mc::CopyGame
            c12.copy_clipboard ::gamebar::mc::CopyThisGameToClipboard
            c12.close_tab ::gamebar::mc::CloseGame
        } {
            set expected [set $key]
            set actual [::context::L $id]
            set registry [dict get [::action::get $id] label]
            if {$actual ne $expected || $registry ne $expected} {
                lappend bad [list $id $expected $actual $registry]
            }
        }
        menu .nativeTranslation -tearoff 0
        ::context::Build C1 .nativeTranslation [dict create square e4 fen [::scidb::pos::fen]]
        set flip {}
        for {set i 0} {$i <= [.nativeTranslation index end]} {incr i} {
            if {[.nativeTranslation type $i] eq "separator"} {continue}
            set command [.nativeTranslation entrycget $i -command]
            if {[lindex $command 1] eq "c1.flip_board"} {
                set flip [string trim [.nativeTranslation entrycget $i -label]]
            }
        }
        if {$flip ne $::overview::mc::RotateBoard} {
            lappend bad [list native-C1 $::overview::mc::RotateBoard $flip]
        }
        set bad
    } -cleanup {
        catch {destroy .nativeTranslation}
    } -result {}
}
::menu::SwitchLanguage en
tcltest::test context-native-translations-english {returning to English restores the frozen source labels} -body {
    list [::context::L c1.flip_board] [dict get [::action::get c9.flip_board] label]
} -result {{Flip Board} {Flip Board}}
::menu::SwitchLanguage $::scidb::test::nativeTranslationLang
set ::scidb::dir::share $::scidb::test::nativeTranslationShare
tcltest::cleanupTests
