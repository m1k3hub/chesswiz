# ======================================================================
# Scidb App Test - copy and paste between databases (probe, read-only and empty cases)
# ======================================================================
# The game-row context menu and Ctrl+C / Ctrl+V copy through
# ::game::clipboard::copy and paste through ::game::clipboard::paste
# (tcl/game-clipboard.tcl). These tests drive those procs the way the menu
# does, and check that the target database gains the game, that a read-only
# target is refused, and that an empty clipboard is refused.
# ======================================================================
package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::clipboard {

variable testDir [file dirname [file normalize [info script]]]
variable tmpDir [file join $testDir tmp-app]
variable openedFiles {}

proc tempPath {stem ext} {
    variable tmpDir
    file mkdir $tmpDir
    return [file normalize [file join $tmpDir "${stem}_[pid]_[clock microseconds].${ext}"]]
}

proc ignore {args} { return 0 }

# Generate a PGN with $count games and open it as a database.
proc createGameBase {stem count} {
    variable openedFiles
    set file [tempPath $stem pgn]
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
    lappend openedFiles $file
    return $file
}

# Create an empty, writable .sci database and make it current.
proc createSciBase {stem} {
    variable openedFiles
    set file [tempPath $stem sci]
    ::application::database::newBase .application Normal $file
    update idletasks
    lappend openedFiles $file
    return $file
}

proc closeBases {} {
    variable openedFiles
    foreach file $openedFiles {
        catch { $::application::database::Vars(switcher) remove $file }
        catch { ::scidb::db::close $file }
        catch { file delete -force $file }
    }
    set openedFiles {}
}

}

# Copy game #2 of a 3-game PGN, then paste it into an empty writable base.
tcltest::test clipboard-copy-paste {copy one game, paste it into a writable database} -body {
    set src [::scidb::test::clipboard::createGameBase clipsrc 3]
    set dst [::scidb::test::clipboard::createSciBase clipdst]
    ::game::clipboard::copy $src [::scidb::db::get variant? $src] {1}
    set clip [::game::clipboard::count]
    set variant [::scidb::db::get variant? $dst]
    ::game::clipboard::paste $dst $variant
    update idletasks
    list $clip [::scidb::db::count games $dst $variant]
} -cleanup { ::scidb::test::clipboard::closeBases } -result {1 1}

# A database opened read-only (openBase -readonly 1, as the app does) refuses
# the paste with a message and gains no games.
tcltest::test clipboard-readonly-refused {paste into a read-only database is refused} -body {
    set dst [::scidb::test::clipboard::createSciBase clipro]
    set variant [::scidb::db::get variant? $dst]
    set before [::scidb::db::count games $dst $variant]
    catch { $::application::database::Vars(switcher) remove $dst }
    catch { ::scidb::db::close $dst }
    ::application::database::openBase .application $dst no -readonly 1 -switchToBase 0
    update idletasks
    set src [::scidb::test::clipboard::createGameBase clipro_src 1]
    ::game::clipboard::copy $src [::scidb::db::get variant? $src] {0}
    set code [catch { ::game::clipboard::paste $dst [::scidb::db::get variant? $dst] } msg]
    list [::scidb::db::get readonly? $dst [::scidb::db::get variant? $dst]] \
        $code [string match *read-only* $msg] $before \
        [::scidb::db::count games $dst [::scidb::db::get variant? $dst]]
} -cleanup { ::scidb::test::clipboard::closeBases } -result {1 1 1 0 0}

# Paste with nothing copied reports an error and changes nothing.
tcltest::test clipboard-empty-refused {paste with an empty clipboard is refused} -body {
    catch { ::game::clipboard::clear }
    set dst [::scidb::test::clipboard::createSciBase clipempty]
    set code [catch { ::game::clipboard::paste $dst [::scidb::db::get variant? $dst] } msg]
    list $code [expr {[string length $msg] > 0}]
} -cleanup { ::scidb::test::clipboard::closeBases } -result {1 1}

tcltest::cleanupTests
