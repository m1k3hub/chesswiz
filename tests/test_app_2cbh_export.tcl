# Exercise the same Save as 2CBH path used by the Export dialog, then read
# through the real codec. Synthetic games only; no proprietary fixtures.
package require tcltest 2.5

namespace eval ::scidb::test::cb2export {
    variable nop {apply {args {return 0}}}
    proc setup {{annotated 0}} {
        variable nop
        variable dir [file normalize [file join $::scidb::test::app::testDir tmp-app cb2-export-[pid]]]
        file delete -force $dir
        file mkdir $dir
        variable src [file join $dir source.pgn]
        variable dst [file join $dir export.2cbh]
        set f [open $src w]
        fconfigure $f -encoding utf-8
        set pgn {[Event "Save as probe"]
[Site "Testville"]
[Date "2026.10.27"]
[Round "3.2"]
[White "Réti, Richard"]
[Black "Black, Bob"]
[Result "*"]
[WhiteTeam "Team A"]
[BlackTeam "Team B"]

1. e4 (1. d4 d5 (1... Nf6)) e5 (1... c5) 2. Nf3 *

[Event "Second game"]
[White "White"]
[Black "Black"]
[Result "1-0"]

1. d4 d5 2. c4 1-0

[Event "Setup game"]
[White "Setup White"]
[Black "Setup Black"]
[SetUp "1"]
[FEN "4k3/8/8/8/8/8/8/R3K2R b KQ - 0 1"]
[Result "*"]

1... Kd7 *}
        if {$annotated} {
            set pgn [string map {{1. d4 d5 2. c4} {1. d4 {Keep this comment} d5 2. c4}} $pgn]
        }
        puts $f $pgn
        close $f
        ::scidb::db::open $src $nop {} $nop {}
        unset -nocomplain ::export::Info(index) ::export::Info(fsbox)
        set ::export::Info(base) $src
        set ::export::Info(variant) Normal
        set ::export::Info(view) 0
        set ::export::Info(extension) pgn
        set ::export::Info(name) Probe
        unset -nocomplain ::export::Info(languages)
        set ::export::Values(Type) cb2
        set ::export::Values(Types) {cb2}
        catch {destroy .cb2export}
        toplevel .cb2export
    }
    proc cleanup {} {
        variable src
        variable dst
        variable dir
        catch {destroy .cb2export}
        catch {::progress::close}
        catch {::log::close}
        foreach base [list $src $dst] {catch {::scidb::db::close $base}}
        file delete -force $dir
    }
}

tcltest::test cb2-export-dialog-roundtrip {Save as exports three games, variations, UTF-8 and a setup; codec reopens them} -setup {
    ::scidb::test::cb2export::setup
} -body {
    set dst $::scidb::test::cb2export::dst
    set nop $::scidb::test::cb2export::nop
    ::export::DoExport .application .cb2export $dst
    set companions {}
    foreach ext {2cbh 2cbg 2cba 2lid ini} {
        lappend companions [file exists [file rootname $dst].$ext]
    }
    ::scidb::db::load $dst $nop {} -readonly 1
    set n [::scidb::db::count games $dst Normal]
    # Decode the complete games through the codec, rather than checking only
    # the index count. PGN output makes both the tags and RAVs observable.
    set pgn [file join $::scidb::test::cb2export::dir decoded.pgn]
    ::scidb::view::export $dst Normal 0 $pgn [::export::getPgnFlags] 0 utf-8 0 {} {} $nop {} $nop {}
    set f [open $pgn r]
    fconfigure $f -encoding utf-8
    set text [read $f]
    close $f
    ::scidb::db::close $dst
    ::scidb::db::load $dst $nop {} -readonly 1
    list $companions $n [::scidb::db::count games $dst Normal] \
        [string match {*Réti, Richard*} $text] \
        [string match {*Team A*} $text] \
        [string match {*Nf6*} $text] \
        [string match {*c5*} $text] \
        [string match {*Kd7*} $text]
} -cleanup {
    ::scidb::test::cb2export::cleanup
} -result {{1 1 1 1 1} 3 3 1 1 1 1 1}

tcltest::test cb2-export-refuses-append {read-only codec offers Save as, never lossy in-place append} -setup {
    ::scidb::test::cb2export::setup
} -body {
    set nop $::scidb::test::cb2export::nop
    set dst $::scidb::test::cb2export::dst
    set rc [catch {::scidb::view::export $::scidb::test::cb2export::src Normal 0 $dst 0 1 utf-8 0 {} {} $nop {} $nop {}} message]
    list $rc [file exists $dst]
} -cleanup {
    ::scidb::test::cb2export::cleanup
} -result {1 0}

tcltest::test cb2-export-refuses-annotation-loss {a later annotated game prevents writing even the first game} -setup {
    ::scidb::test::cb2export::setup 1
} -body {
    set nop $::scidb::test::cb2export::nop
    set dst $::scidb::test::cb2export::dst
    set rc [catch {::scidb::view::export $::scidb::test::cb2export::src Normal 0 $dst 0 0 utf-8 0 {} {} $nop {} $nop {}} message]
    list $rc [glob -nocomplain [file rootname $dst].*]
} -cleanup {
    ::scidb::test::cb2export::cleanup
} -result {1 {}}

tcltest::cleanupTests
