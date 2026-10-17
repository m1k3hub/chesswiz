# ======================================================================
# Scidb App Test Suite - Game Number box (games table) regression
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

# Windows report: typing a game number into the "Game Number" toolbar box and
# pressing Enter (or the arrow button) neither loaded nor selected the game.
# games::Goto activated the row but never dispatched the load-selection event,
# and the scrolledtable-level activation is a no-op because focus sits in the
# entry. These tests fire the real user path (Return / button) and check the
# resulting table selection.
namespace eval ::scidb::test::appgn {

variable testDir [file dirname [file normalize [info script]]]
variable tmpDir [file join $testDir tmp-app]
variable openedBases {}

proc setup {} {
    variable tmpDir
    file mkdir $tmpDir
    # Loading a game needs a free game slot (there are nine); games other test
    # files left open would make the load ask, which the test app answers no.
    set current [::scidb::game::current]
    for {set i 0} {$i < $::game::MaxPosition} {incr i} {
        if {$i != $current} { catch { ::game::release $i } }
    }
}

proc tempPath {stem} {
    variable tmpDir
    return [file normalize [file join $tmpDir "${stem}_[pid]_[clock microseconds].pgn"]]
}

# Generate a small multi-game PGN and open it as a database so the games table
# is populated and becomes the current base (the tester's scenario, 40 games
# standing in for the 9000-game file).
proc createGameBase {stem count} {
    variable openedBases
    set file [tempPath $stem]
    set fh [open $file w]
    for {set i 1} {$i <= $count} {incr i} {
        puts $fh "\[Event \"G$i\"\]"
        puts $fh "\[Site \"X\"\]"
        puts $fh "\[Date \"2024.01.01\"\]"
        puts $fh "\[Round \"1\"\]"
        puts $fh "\[White \"W$i\"\]"
        puts $fh "\[Black \"B$i\"\]"
        puts $fh "\[Result \"1-0\"\]"
        puts $fh ""
        puts $fh "1.e4 e5 2.Nf3 Nc6 3.Bb5 a6 1-0"
        puts $fh ""
    }
    close $fh
    ::scidb::db::open $file ignore {} ignore {}
    update idletasks
    lappend openedBases $file
    return $file
}

# The games table + its Game Number entry on the database notebook page.
proc gamesTable {} { return .application.nb.database.contents.games.twm.games.table }
proc gameNumberEntry {} {
    return .application.nb.database.contents.games.twm.games.__tb__games-gameno.__tbw__68.e
}

# Drain pending idle/timer callbacks so a virtual-event dispatch chain completes.
proc flushEvents {{ms 400}} {
    update idletasks
    update
    after $ms
    update idletasks
    update
}

proc ignore {args} { return 0 }

# Close every base this suite opened and remove its file, so re-runs start clean.
proc closeBases {} {
    variable openedBases
    foreach file $openedBases {
        catch { $::application::database::Vars(switcher) remove $file }
        catch { ::scidb::db::close $file }
        catch { file delete -force $file }
    }
    set openedBases {}
}

# Open $stem as a database and make it current, then return the games table.
proc useBase {stem {count 40}} {
    set file [createGameBase $stem $count]
    $::application::database::Vars(switcher) add $file [::scidb::db::get type $file] 1 {}
    ::application::database::switchToBase $file
    update idletasks
    update
    return [gamesTable]
}

# Drive the box as a user does: show its toolbar, focus the entry (clears the
# ghost text), type the digits as key presses, then press Return (or click the
# arrow button).  Plain "insert" + "event generate <Return>" on an unfocused,
# hidden entry never reached <<Find>>/<<FindNext>>.
proc typeNumber {number {how return}} {
    set entry [gameNumberEntry]
    set tb [winfo parent [winfo parent $entry]]
    ::application::switchTab database
    update
    catch { ::toolbar::show $tb }
    catch { destroy .tipoftheday }
    update
    focus -force $entry
    update
    if {[focus] ne $entry} { error "game number entry not focused (focus=[focus])" }
    $entry selection range 0 end
    foreach ch [split $number ""] {
        event generate $entry <KeyPress> -keysym $ch
    }
    update
    if {[$entry get] ne $number} { error "entry holds '[$entry get]', expected '$number'" }
    if {$how eq "return"} {
        event generate $entry <KeyPress-Return> -keysym Return
    } else {
        [winfo parent $entry].r invoke
    }
    flushEvents
}

# Game number (0-based) of the game loaded in the editor, or -1.
# The number of the game loaded from the current base: the current game, or
# else the game slot holding a game of this base (which slot becomes current
# depends on the games earlier test files left open).
proc loadedNumber {} {
    if {![catch { ::scidb::game::link? [::scidb::game::current] } link]
            && [lindex $link 0] eq [::scidb::db::get name]
            && [string is integer -strict [lindex $link 2]]} {
        return [lindex $link 2]
    }
    foreach entry [::game::gameList] {
        lassign $entry name _ number
        if {$name eq [::scidb::db::get name] && [string is integer -strict $number]} { return $number }
    }
    return -1
}

setup

tcltest::test app-gamenumber-01 {Game Number Enter selects the game} -body {
    set table [useBase gameno]

    typeNumber 25
    # game 25 is index 24 in the games table, and it is loaded into the editor
    list [::gamestable::index $table] [loadedNumber]
} -cleanup { closeBases } -result {24 24}

tcltest::test app-gamenumber-02 {Game Number arrow button selects the game} -body {
    set table [useBase gameno_btn]
    typeNumber 30 button
    list [::gamestable::index $table] [loadedNumber]
} -cleanup { closeBases } -result {29 29}

tcltest::test app-gamenumber-03 {Game Number box ignores out-of-range numbers} -body {
    set table [useBase gameno_oor]

    typeNumber 99

    # 99 > 40 games: nothing is selected
    ::gamestable::index $table
} -cleanup { closeBases } -result -1
}

tcltest::cleanupTests
