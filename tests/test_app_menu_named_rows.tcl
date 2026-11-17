# Live native row adapters must retain filtered-view effects through the registry.
package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
namespace eval ::scidb::test::namedrows {variable timer {}}
proc ::scidb::test::namedrows::nop {args} {}
proc ::scidb::test::namedrows::walk {w} {
    set out [list $w]
    foreach child [winfo children $w] {lappend out {*}[walk $child]}
    return $out
}
proc ::scidb::test::namedrows::choose {dlg deadline} {
    variable timer
    if {[winfo exists $dlg] && [grab current] eq $dlg} {
        $dlg.top.input delete 0 end
        $dlg.top.input insert 0 {Generated row workset}
        $dlg.ok invoke
    } elseif {[clock milliseconds] < $deadline} {
        set timer [after 20 [list [namespace current]::choose $dlg $deadline]]
    }
}
proc ::scidb::test::namedrows::base {} {
    set dir [file join $::scidb::test::actions::Dir named-rows]
    file mkdir $dir
    set pgn [file join $dir source.pgn]
    set ch [open $pgn w]
    for {set i 1} {$i <= 3} {incr i} {
        set ann [expr {$i == 3 ? {} : {Generated Annotator}}]
        puts $ch "\[Event \"Generated $i\"\]\n\[Site \"Test\"\]\n\[White \"White$i\"\]\n\[Black \"Black$i\"\]\n\[Result \"*\"\]\n\[Annotator \"$ann\"\]"
        if {$i == 3} {
            puts $ch "\[SetUp \"1\"\]\n\[FEN \"8/8/8/8/4K3/8/4k3/8 w - - 0 1\"\]"
            puts $ch "\n*\n"
        } else {puts $ch "\n1. e4 e5 *\n"}
    }
    close $ch
    ::scidb::db::open $pgn [namespace current]::nop {} [namespace current]::nop {}
    set base [file join $dir rows.sci]
    ::application::database::newBase .application Normal $base
    ::scidb::db::copy $pgn $base {} [namespace current]::nop {} [namespace current]::nop {}
    ::scidb::db::close $pgn
    ::scidb::db::save $base [namespace current]::nop {}
    ::application::database::closeBase .application $base
    ::application::database::openBase .application $base no
    update
    return $base
}
set ::scidb::test::namedrows::source [::scidb::test::namedrows::base]
# Dismiss only informational completion messages; export, search, switcher,
# native views and the editable Save Working Set dialog all remain real.
rename ::dialog::info ::scidb::test::namedrows::savedInfo
proc ::dialog::info {args} {return ok}
foreach kind {annotator position} {
    tcltest::test menu-named-row-$kind {live native row menu filters and opens/saves the same games via registry actions} -body {
        set base $::scidb::test::namedrows::source
        ::application::database::switchToBase $base
        ::application::switchTab database
        $::application::database::Vars(contents) select $::application::database::Vars($kind)
        update
        after 100
        update
        set path .application.nb.database.contents.$kind.twm
        ::application::database::${kind}::InitBase $path $base Normal
        update
        set table {}
        foreach w [::scidb::test::namedrows::walk .application] {
            if {![info exists ::scrolledtable::${w}::(popupcmd)]} {continue}
            set cb [set ::scrolledtable::${w}::(popupcmd)]
            if {[string match "*::${kind} *PopupMenu*" $cb]} {set table $w;break}
        }
        if {$table eq {} || ![winfo viewable $table]} {error "no mapped registered $kind popup"}
        set callback [set ::scrolledtable::${table}::(popupcmd)]
        menu .namedrow -tearoff 0
        # Find the populated group, without depending on row sorting.
        upvar #0 ::application::database::${kind}::${path}::Vars vars
        set view $vars($base:Normal:view)
        set index -1
        for {set n 0} {$n < [::scidb::view::count ${kind}s $base Normal $view]} {incr n} {
            set row [::scidb::db::get $kind $n $view $base Normal]
            if {($kind eq "annotator" && [lindex $row 0] eq "Generated Annotator")
                || ($kind eq "position" && [lindex $row 0] == 518)} {set index $n;break}
        }
        if {$index < 0} {error "missing populated $kind row"}
        {*}$callback $path .namedrow $base Normal $index $kind
        .namedrow post 100 100
        update
        if {![winfo ismapped .namedrow]} {error "native row menu did not map"}
        ::tk::MenuUnpost .namedrow
        set ids {}
        set labels {}
        set commands {}
        for {set n 0} {$n <= [.namedrow index end]} {incr n} {
            if {[.namedrow type $n] eq "separator"} {continue}
            set cmd [.namedrow entrycget $n -command]
            if {[lindex $cmd 0] ne "::action::run"} {error "raw row callback: $cmd"}
            lappend ids [lindex $cmd 1]
            if {[lindex $cmd 1] ne "context.ask"} {
                lappend commands $cmd
                lappend labels [string trim [.namedrow entrycget $n -label]]
            }
        }
        if {$labels ne [list $::application::database::mc::RepertoireOpenInSwitcher $::application::database::mc::SaveWorkingSet]} {
            error "native filtered row labels changed: $labels"
        }
        puts [list NATIVE_NAMED_ROW kind $kind table $table mapped [winfo viewable $table] callback $callback ids $ids]
        set counts {}
        foreach cmd $commands {
            # Menu callbacks defer dispatch until idle; run the exact command
            # with only that scheduling option removed to observe its reply.
            set args [dict remove [lindex $cmd 2] defer]
            if {[lindex $cmd 1] eq "c5.filtered.save_working_set"} {
                set dlg [::application::database::WorkingSetDialogName $path]
                set ::scidb::test::namedrows::timer [after 20 [list ::scidb::test::namedrows::choose $dlg [expr {[clock milliseconds]+5000}]]]
            }
            set reply [::action::run [lindex $cmd 1] $args]
            after cancel $::scidb::test::namedrows::timer
            if {[string match error:* $reply]} {error $reply}
            set target [::menu::CurrentBase]
            if {$target eq $base} {error "did not open filtered database: $reply"}
            lappend counts [::scidb::db::count games $target Normal]
            ::application::database::closeBase .application $target
            ::application::database::switchToBase $base
        }
        # Empty space must not borrow the preceding row.
        menu .namedempty -tearoff 0
        {*}$callback $path .namedempty $base Normal outside $kind
        list $ids $counts [.namedempty index end] [::scidb::db::count games $base Normal]
    } -cleanup {
        catch {destroy .namedrow};catch {destroy .namedempty}
        after cancel $::scidb::test::namedrows::timer
    } -result {{context.ask c5.filtered.open_switcher c5.filtered.save_working_set} {2 2} none 3}
}
proc ::scidb::test::namedrows::webRows {menu routed} {
    set rows {}
    if {[$menu index end] in {{} none}} {return $rows}
    for {set i 0} {$i <= [$menu index end]} {incr i} {
        if {[$menu type $i] eq "cascade"} {
            lappend rows {*}[webRows [$menu entrycget $i -menu] $routed]
        } elseif {[$menu type $i] eq "command"} {
            set cmd [$menu entrycget $i -command]
            if {$routed} {
                if {[lindex $cmd 0] ne "::action::run"} {error "raw dictionary callback: $cmd"}
                if {[lindex $cmd 1] ne "c5.player_url"} {continue}
                set url [dict get [lindex $cmd 2] object webUrl]
            } else {set url [lindex $cmd 2]}
            lappend rows [list [$menu entrycget $i -label] [$menu entrycget $i -state] \
                [$menu entrycget $i -image] $url]
        }
    }
    return $rows
}
tcltest::test menu-named-player-dictionary {live dictionary callback preserves every web choice through C5 registry actions} -body {
    ::playerdict::open .application
    update
    set table $::playerdict::Priv(table)
    set callback [set ::scrolledtable::${table}::(popupcmd)]
    set info [::scidb::player::info 0 -web 1]
    menu .dictold -tearoff 0
    menu .dictnew -tearoff 0
    ::playercard::buildWebMenu $table .dictold $info
    {*}$callback [winfo parent [winfo parent $table]] .dictnew {} {} 0 {}
    set before [::scidb::test::namedrows::webRows .dictold 0]
    set after [::scidb::test::namedrows::webRows .dictnew 1]
    list [expr {[llength $before] >= 8}] [expr {$before eq $after}]
} -cleanup {
    catch {destroy .dictold};catch {destroy .dictnew}
    catch {destroy $::playerdict::Priv(dialog)}
} -result {1 1}
rename ::dialog::info {}
rename ::scidb::test::namedrows::savedInfo ::dialog::info
catch {::application::database::closeBase .application $::scidb::test::namedrows::source}
file delete -force [file join $::scidb::test::actions::Dir named-rows]
::scidb::test::actions::release
tcltest::cleanupTests
