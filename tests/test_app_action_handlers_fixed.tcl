# Test suite for action handlers audited in knowcheck.md
# Tests all 12 actions:
#   menu.file.new.variants, menu.db.readonly, menu.analysis.explain.comment,
#   menu.game.merge_tab, c2.new_main_line, c3.sort_desc, c4.new.pgn,
#   c7.open_stream, c8.search.slow, c10.fit, c11.detect_language, c12.new.chess960

package require Tcl 8.5
package require tcltest 2.5
namespace import ::tcltest::*

namespace eval ::scidb::test::knowfix {
    variable root [file dirname [file dirname [file normalize [info script]]]]
    variable testDir [file join $root tests tmp-app knowfix-[pid]]
    variable base [file join $testDir fixture.sci]
    variable table ""

    proc nop {args} { return 0 }

    proc setup {} {
        variable testDir
        variable base
        variable table

        file mkdir $testDir
        set pgn [file join $testDir sample.pgn]
        set f [open $pgn w]
        puts $f {
[Event "Knowfix Open"]
[Site "Fixture City"]
[Date "2026.10.01"]
[Round "1"]
[White "Alice"]
[Black "Bob"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 (3... Nf6 4. O-O) 4. Ba4 {Fine move} 1-0

[Event "Knowfix Open"]
[Site "Fixture City"]
[Date "2026.10.01"]
[Round "2"]
[White "Bob"]
[Black "Alice"]
[Result "0-1"]

1. d4 d5 2. c4 e6 0-1
}
        close $f

        catch { ::scidb::db::close $pgn }
        catch { ::scidb::db::close $base }
        ::scidb::db::open $pgn [namespace current]::nop {} [namespace current]::nop {}
        ::scidb::db::new $base Normal [::application::database::lookupType Unspecific]
        ::scidb::db::attach $base $base
        ::scidb::db::copy $pgn $base {} [namespace current]::nop {} [namespace current]::nop {}
        ::scidb::db::save $base [namespace current]::nop {}
        ::scidb::db::close $base
        ::scidb::db::close $pgn

        ::action::run open_database [list path $base]
        ::action::run open_game {number 1}
        update

        set twm $::application::database::Vars(games).twm
        set table [set ::application::database::games::${twm}::Priv(table)]
    }

    proc cleanup {} {
        variable testDir
        variable base
        set pos 0
        catch {
            foreach entry [::game::gameList] {
                if {[lindex $entry 0] ne {}} {
                    catch { ::application::pgn::release $pos }
                    catch { ::game::release $pos }
                }
                incr pos
            }
        }
        catch { ::application::database::closeBase .application $base }
        catch { file delete -force $testDir }
    }
}

::scidb::test::knowfix::setup

# ----------------------------------------------------------------------
# 1. menu.file.new.variants
# ----------------------------------------------------------------------
test knowfix-1-menu-file-new-variants {menu.file.new.variants delegates to Normal (duplicate of new.normal)} -body {
    set calledWith ""
    proc ::menu::testDbNew {parent variant} {
        set ::scidb::test::knowfix::calledDbNewVariant $variant
        return 1
    }
    rename ::menu::dbNew ::menu::savedDbNew
    rename ::menu::testDbNew ::menu::dbNew
    catch {
        ::action::run menu.file.new.variants
    }
    rename ::menu::dbNew ::menu::testDbNew
    rename ::menu::savedDbNew ::menu::dbNew
    set ::scidb::test::knowfix::calledDbNewVariant
} -result {Normal}

# ----------------------------------------------------------------------
# 2. menu.db.readonly
# ----------------------------------------------------------------------
test knowfix-2-menu-db-readonly {menu.db.readonly toggles readonly flag of current database} -body {
    set base $::scidb::test::knowfix::base
    set roBefore [::scidb::db::get readonly? $base]
    ::action::run menu.db.readonly
    set roAfter1 [::scidb::db::get readonly? $base]
    ::action::run menu.db.readonly
    set roAfter2 [::scidb::db::get readonly? $base]
    list $roBefore $roAfter1 $roAfter2
} -result {0 1 0}

# ----------------------------------------------------------------------
# 3. menu.analysis.explain.comment
# ----------------------------------------------------------------------
test knowfix-3-menu-analysis-explain-comment {menu.analysis.explain.comment delegates to explainComment} -body {
    set called 0
    proc ::application::ai::testExplainComment {parent pos} {
        set ::scidb::test::knowfix::explainPos $pos
        incr ::scidb::test::knowfix::explainCalled
        return
    }
    rename ::application::ai::explainComment ::application::ai::savedExplainComment
    rename ::application::ai::testExplainComment ::application::ai::explainComment
    set ::scidb::test::knowfix::explainCalled 0
    set ::scidb::test::knowfix::explainPos ""
    catch {
        # Navigate to move 4 which has {Fine move} comment
        ::scidb::game::go 7
        ::action::run menu.analysis.explain.comment
    }
    rename ::application::ai::explainComment ::application::ai::testExplainComment
    rename ::application::ai::savedExplainComment ::application::ai::explainComment
    list $::scidb::test::knowfix::explainCalled $::scidb::test::knowfix::explainPos
} -result {1 after}

# ----------------------------------------------------------------------
# 4. menu.game.merge_tab and menu.game.merge_clip
# ----------------------------------------------------------------------
test knowfix-4-menu-game-merge-tab {menu.game.merge_tab merges from an open game tab} -body {
    set base $::scidb::test::knowfix::base
    ::application::pgn::lock 0
    ::game::lockChanged 0 1
    set second [::game::new .application -base $base -variant Normal -number 1]
    ::application::pgn::select 0
    set currentSlot [::scidb::game::current]

    set ::scidb::test::knowfix::mergeSecondary ""
    proc ::merge::testOpenDialog {parent primary secondary} {
        set ::scidb::test::knowfix::mergeSecondary $secondary
        return
    }
    rename ::merge::openDialog ::merge::savedOpenDialog
    rename ::merge::testOpenDialog ::merge::openDialog

    catch {
        ::action::run menu.game.merge_tab
    }

    set tabSecondary $::scidb::test::knowfix::mergeSecondary

    catch {
        ::action::run menu.game.merge_clip
    }

    set clipSecondary $::scidb::test::knowfix::mergeSecondary

    rename ::merge::openDialog ::merge::testOpenDialog
    rename ::merge::savedOpenDialog ::merge::openDialog

    list [expr {$tabSecondary ne "" && $tabSecondary != $currentSlot}] [expr {$tabSecondary != $clipSecondary}]
} -result {1 1}

# ----------------------------------------------------------------------
# 5. c2.new_main_line
# ----------------------------------------------------------------------
test knowfix-5-c2-new-main-line {c2.new_main_line promotes variation to mainline} -body {
    # Open game 1, go to move 3, enter variation
    ::action::run open_game {number 1}
    ::scidb::game::go start
    ::scidb::game::go 5
    ::scidb::game::go variation 0
    ::scidb::game::go 1
    set inVarBefore [::scidb::game::position isMainline?]
    set slot [::scidb::game::current]
    set obj [dict create parent .application position $slot gameSlot $slot id $slot]
    ::action::run c2.new_main_line [list object $obj]
    set inVarAfter [::scidb::game::position isMainline?]
    list $inVarBefore $inVarAfter
} -result {0 1}

# ----------------------------------------------------------------------
# 6. c3.sort_desc
# ----------------------------------------------------------------------
test knowfix-6-c3-sort-desc {c3.sort_desc sorts descending} -body {
    set table $::scidb::test::knowfix::table
    set obj [dict create path $table column white sortable 1]
    # Should execute without error
    ::action::run c3.sort_desc [list object $obj]
    expr {1}
} -result {1}

# ----------------------------------------------------------------------
# 7. c4.new.pgn
# ----------------------------------------------------------------------
test knowfix-7-c4-new-pgn {c4.new.pgn creates a new PGN database when file is provided} -body {
    set base $::scidb::test::knowfix::base
    set testDir $::scidb::test::knowfix::testDir
    set pgnFile [file join $testDir created.pgn]
    set obj [dict create parent .application file $pgnFile]
    ::action::run c4.new.pgn [list object $obj]
    set exists [file exists $pgnFile]
    catch { ::application::database::switchToBase $base }
    catch { ::application::database::CloseBase .application $pgnFile }
    set exists
} -result {1}

# ----------------------------------------------------------------------
# 8. c7.open_stream
# ----------------------------------------------------------------------
test knowfix-8-c7-open-stream {c7.open_stream opens the media stream dialog} -body {
    set obj [dict create parent .application]
    ::action::run c7.open_stream [list object $obj]
    set dlg .application.__mediastream__
    set exists [winfo exists $dlg]
    catch { destroy $dlg }
    set exists
} -result {1}

# ----------------------------------------------------------------------
# 9. c8.search.slow
# ----------------------------------------------------------------------
test knowfix-9-c8-search-slow {c8.search.slow sets search mode to slow} -body {
    set ::application::tree::Options(search:mode) fast
    set obj [dict create parent .application]
    ::action::run c8.search.slow [list object $obj]
    set ::application::tree::Options(search:mode)
} -result {slow}

# ----------------------------------------------------------------------
# 10. c10.fit
# ----------------------------------------------------------------------
test knowfix-10-c10-fit {c10.fit fits columns on gametable} -body {
    set table $::scidb::test::knowfix::table
    set obj [dict create parent .application table [::scrolledtable::table $table] column white]
    ::action::run c10.fit [list object $obj]
    expr {1}
} -result {1}

# ----------------------------------------------------------------------
# 11. c11.detect_language
# ----------------------------------------------------------------------
test knowfix-11-c11-detect-language {c11.detect_language delegates to comment::DetectLanguage} -body {
    set called 0
    proc ::comment::testDetectLanguage {parent} {
        incr ::scidb::test::knowfix::detectCalled
        return
    }
    rename ::comment::DetectLanguage ::comment::savedDetectLanguage
    rename ::comment::testDetectLanguage ::comment::DetectLanguage
    set ::scidb::test::knowfix::detectCalled 0
    catch {
        set obj [dict create parent .application]
        ::action::run c11.detect_language [list object $obj]
    }
    rename ::comment::DetectLanguage ::comment::testDetectLanguage
    rename ::comment::savedDetectLanguage ::comment::DetectLanguage
    set ::scidb::test::knowfix::detectCalled
} -result {1}

# ----------------------------------------------------------------------
# 12. c12.new.chess960
# ----------------------------------------------------------------------
test knowfix-12-c12-new-chess960 {c12.new.chess960 creates a new Chess960 game} -body {
    catch { ::scidb::game::modified [::scidb::game::current] no }
    set obj [dict create parent .application]
    ::action::run c12.new.chess960 [list object $obj]
    update
    expr {[::scidb::game::query idn] > 0}
} -result {1}

::scidb::test::knowfix::cleanup
cleanupTests
