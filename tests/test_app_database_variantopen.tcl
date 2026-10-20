# Native variant databases must open without saved layout/table preferences.
package require tcltest 2.5

namespace eval ::scidb::test::variantopen {
variable dir [file normalize [file join [file dirname [info script]] tmp-app variantopen-[pid]]]
file mkdir $dir
proc nop {args} {}

foreach variant {Crazyhouse ThreeCheck Normal Antichess Losers Bughouse} {
    tcltest::test app-db-variantopen-$variant {open a native database with default table options} -setup {
        set base [file join $dir $variant.sci]
        # These two variants exercise empty native lists; the others also
        # verify a rendered game row, using the backend PGN importer.
        set hasGame [expr {$variant ni {Antichess Bughouse}}]
        set pgn $base.pgn
        if {$hasGame} {
            set chan [open $pgn w]
            puts $chan [format {[Event "Generated variant test"]
[White "GeneratedWhite"]
[Black "GeneratedBlack"]
[Result "*"]
[Variant "%s"]

1. e4 e5 *
} $variant]
            close $chan
            ::scidb::db::open $pgn [namespace current]::nop {} [namespace current]::nop {}
        }
        ::scidb::db::new $base $variant [::application::database::lookupType Unspecific]
        ::scidb::db::attach $base $base
        if {$hasGame} {
            ::scidb::db::copy $pgn $base {} [namespace current]::nop {} [namespace current]::nop {}
            ::scidb::db::close $pgn
        }
        ::scidb::db::save $base [namespace current]::nop {}
        ::scidb::db::close $base
    } -body {
        set opened [::application::database::openBase .application $base 0]
        ::application::switchTab database
        update
        set twm [::application::twm games]
        set table [set ::application::database::games::${twm}::Priv(table)]
        set tree [::scrolledtable::tablePath $table]
        list $opened [expr {[::scrolledtable::base $table] eq $base}] \
            [::scrolledtable::variant $table] [winfo ismapped $tree] \
            [::scidb::db::count games $base $variant] \
            [expr {!$hasGame || [string match *GeneratedWhite* [$tree item text [$tree item firstchild root]]]}]

    } -cleanup {
        catch { $::application::database::Vars(switcher) remove $base }
        catch { ::scidb::db::close $base }
        catch { ::scidb::db::close $pgn }
    } -result [list 1 1 $variant 1 [expr {$variant ni {Antichess Bughouse}}] 1]
}
tcltest::test app-db-variantopen-options {missing snapshots preserve defaults and can be saved and restored} -setup {
    set snapshots {}
    foreach callback $::options::TableSaveCallbacks {
        set ns [namespace qualifiers $callback]
        dict set snapshots $ns [array get ${ns}::TableOptions]
        array unset ${ns}::TableOptions
    }
} -body {
    set before [::scrolledtable::getOptions db:games:games]
    foreach twm $::application::Vars(twm) {
        if {![winfo exists $twm]} { continue }
        ::options::restore $twm normal
        ::options::restore $twm dropchess
        ::options::restore $twm antichess
    }
    set unchanged [::table::equal $before [::scrolledtable::getOptions db:games:games]]
    set twm [::application::twm games]
    set needsSave [expr {![::options::compare $twm normal]}]
    ::options::save $twm normal
    ::options::restore $twm normal
    list $unchanged $needsSave [::options::compare $twm normal]
} -cleanup {
    dict for {ns values} $snapshots {
        array unset ${ns}::TableOptions
        array set ${ns}::TableOptions $values
    }
} -result {1 1 true}

file delete -force $dir
tcltest::cleanupTests
}
