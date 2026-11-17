package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_html_popup_support.tcl
::scidb::test::actions::ready
set ::scidb::test::htmlpop::base [::scidb::test::actions::fixture]
::action::run open_database [dict create path $::scidb::test::htmlpop::base]
proc ::scidb::test::htmlpop::invoke {rows id} {
    foreach row $rows {
        set command [lindex $row 4]
        if {[lindex $command 1] eq $id && [lindex $row 2] ne "disabled"} {
            set reply [uplevel #0 $command]
            if {[string match error:* $reply]} {error $reply}
            update
            return $reply
        }
    }
    error "missing $id"
}
tcltest::test menu-html-card-font {native HTML font rows resize and restore the actual card} -body {
    lassign [::scidb::test::htmlpop::cardRows $::scidb::test::htmlpop::base] dlg rows drawable key
    set before [$dlg.content fontsize?]
    ::scidb::test::htmlpop::invoke $rows html.playercard.font_inc
    set after [$dlg.content fontsize?]
    ::scidb::test::htmlpop::invoke $rows html.playercard.font_dec
    list [expr {$after > $before}] [expr {[$dlg.content fontsize?] == $before}]
} -cleanup {catch {destroy $dlg}} -result {1 1}

tcltest::test menu-html-card-web {web row retains exact parent and URL through real registry validation} -body {
    lassign [::scidb::test::htmlpop::cardRows $::scidb::test::htmlpop::base] dlg rows drawable key
    # Stub only external browser launch; the menu, registry and native URL
    # availability check remain real. No network is needed for this test.
    rename ::web::open ::scidb::test::htmlpop::savedWeb
    proc ::web::open {parent url} {set ::scidb::test::htmlpop::opened [list $parent $url]}
    set ::scidb::test::htmlpop::opened {}
    ::scidb::test::htmlpop::invoke $rows html.playercard.web
    set opened $::scidb::test::htmlpop::opened
    set rejects 0
    foreach row $rows {
        set cmd [lindex $row 4]
        if {[lindex $row 2] eq "disabled" && [lindex $cmd 1] eq "html.playercard.web"} {
            if {![string match error:* [uplevel #0 $cmd]]} {error "disabled URL ran"}
            incr rejects
        }
    }
    list [expr {[lindex $opened 0] eq "$dlg.content"}] [string match *365chess.com* [lindex $opened 1]] [expr {$rejects >= 7}]
} -cleanup {
    catch {rename ::web::open {}}
    catch {rename ::scidb::test::htmlpop::savedWeb ::web::open}
    catch {destroy $dlg}
} -result {1 1 1}

tcltest::test menu-html-card-debug {debug commands are gated both at construction and dispatch} -body {
    lassign [::scidb::test::htmlpop::cardRows $::scidb::test::htmlpop::base 1] dlg rows drawable key
    set traces {}
    foreach row $rows {
        set cmd [lindex $row 4]
        if {[string match html.playercard.trace_* [lindex $cmd 1]]} {
            lappend traces [dict get [::action::get [lindex $cmd 1]] ai]
            if {![string match error:* [uplevel #0 $cmd]]} {error "developer command bypassed gate"}
        }
    }
    set traces
} -cleanup {catch {destroy $dlg}} -result {debug debug}

tcltest::test menu-html-tips {native Tips HTML callback is counted and font effects are preserved} -body {
    set dlg [::tips::open .application]
    update
    set html $::tips::Priv(html)
    set rows [::scidb::test::htmlpop::capture tips [list ::scidb::test::htmlpop::click [winfo parent [$html drawable]]]]
    set before [$html fontsize?]
    ::scidb::test::htmlpop::invoke $rows html.tips.font_inc
    set after [$html fontsize?]
    ::scidb::test::htmlpop::invoke $rows html.tips.font_dec
    list [llength $rows] [expr {$after > $before}] [expr {[$html fontsize?] == $before}]
} -cleanup {catch {destroy $dlg}} -result {2 1 1}

tcltest::test menu-html-information {Information HTML popup is counted and changes its own font} -body {
    ::application::switchTab information
    update
    set html $::application::information::Priv(html)
    set rows [::scidb::test::htmlpop::capture info {::application::information::Mouse3Down}]
    set before [$html fontsize?]
    ::scidb::test::htmlpop::invoke $rows html.info.font_inc
    set after [$html fontsize?]
    ::scidb::test::htmlpop::invoke $rows html.info.font_dec
    list [llength $rows] [expr {$after > $before}] [expr {[$html fontsize?] == $before}]
} -result {2 1 1}

tcltest::test menu-html-help {Help HTML popup and typography/alignment operations are registry actions} -body {
    set dlg [::help::open .application Ask-Field]
    update
    set html $::help::Priv(html)
    # Help uses the toplevel binding and actual pointer hit testing.
    event generate [$html drawable] <Motion> -warp 1 -x 30 -y 30
    update
    set rows [::scidb::test::htmlpop::capture help [list event generate [$html drawable] <ButtonPress-3> -x 30 -y 30]]
    set before [$html fontsize?]
    ::scidb::test::htmlpop::invoke $rows html.help.font_inc
    set after [$html fontsize?]
    ::scidb::test::htmlpop::invoke $rows html.help.font_dec
    ::scidb::test::htmlpop::invoke $rows html.help.align
    list [expr {[llength $rows] >= 10}] [expr {$after > $before}] [expr {[$html fontsize?] == $before}] [set ::html::${html}::Priv(textalign)]
} -cleanup {catch {::help::Destroy}} -result {1 1 1 justify}

tcltest::test menu-html-overview {drawable overview popup is counted and native rotation reverses} -body {
    set base $::scidb::test::htmlpop::base
    set info [::scidb::db::get gameInfo 0 0 $base Normal]
    set nb [::overview::open .application $base Normal $info 0 0]
    update
    set rows [::scidb::test::htmlpop::capture overview [list ::overview::PopupMenu $nb]]
    set before [set ::overview::${nb}::Vars(flip)]
    ::scidb::test::htmlpop::invoke $rows html.overview.rotate
    set after [set ::overview::${nb}::Vars(flip)]
    ::scidb::test::htmlpop::invoke $rows html.overview.rotate
    list [llength $rows] [expr {$after != $before}] [expr {[set ::overview::${nb}::Vars(flip)] == $before}]
} -cleanup {catch {destroy [winfo toplevel $nb]}} -result {7 1 1}


tcltest::test menu-html-tournament {tournament drawable popup updates rendered typography and registered checkbuttons} -body {
    ::crosstable::open .application $::scidb::test::htmlpop::base Normal 0 0 game
    update
    set dlg $::crosstable::Reuse
    set html [set ::crosstable::${dlg}::Vars(html)]
    set rows [::scidb::test::htmlpop::capture crosstable [list ::crosstable::PopupMenu $dlg]]
    set before [$html fontsize?]
    ::scidb::test::htmlpop::invoke $rows html.crosstable.font_inc
    set after [$html fontsize?]
    ::scidb::test::htmlpop::invoke $rows html.crosstable.font_dec
    ::scidb::test::htmlpop::invoke $rows html.crosstable.font_family
    list [expr {[llength $rows] > 20}] [expr {$after > $before}] [expr {[$html fontsize?] == $before}]
} -cleanup {catch {destroy $dlg}} -result {1 1 1}


tcltest::test menu-html-card-trace-effects {developer native checkbuttons open and close their real trace windows} -body {
    lassign [::scidb::test::htmlpop::cardRows $::scidb::test::htmlpop::base 1] dlg rows drawable key
    set old $::application::assistant::Priv(debug)
    set ::application::assistant::Priv(debug) 1
    set result {}
    set menu $dlg.content.popup_web_links.debugging
    foreach i {0 1} kind {html log} {
        $menu invoke $i
        update
        lappend result [winfo exists $dlg.$kind]
        $menu invoke $i
        update
        lappend result [winfo exists $dlg.$kind]
    }
    set result
} -cleanup {
    set ::application::assistant::Priv(debug) $old
    catch {destroy $dlg}
} -result {1 0 1 0}

tcltest::test menu-html-tournament-effects {native Display row redraws HTML and Save HTML exports the actual table} -body {
    set base [::scidb::test::htmlpop::tournamentBase]
    ::crosstable::open .application $base Normal 0 0 game
    update
    set dlg $::crosstable::Reuse
    set rows [::scidb::test::htmlpop::capture crosstable [list ::crosstable::PopupMenu $dlg]]
    set menu .application.__crosstable_popup__.display
    set before [set ::crosstable::${dlg}::Vars(output:html)]
    $menu invoke 0
    update
    set after [set ::crosstable::${dlg}::Vars(output:html)]
    $menu invoke 0
    update
    rename ::dialog::saveFile ::scidb::test::htmlpop::savedSaveFile
    set file [file join $::env(HOME) generated-table.html]
    set ::scidb::test::htmlpop::exportFile $file
    proc ::dialog::saveFile {args} {return [list $::scidb::test::htmlpop::exportFile]}
    ::scidb::test::htmlpop::invoke $rows html.crosstable.save
    set f [open $file];set exported [read $f];close $f
    list [expr {$before ne $after}] [expr {[string length $exported] > 100}] [string match {*Generated White*} $exported]
} -cleanup {
    if {[llength [info commands ::scidb::test::htmlpop::savedSaveFile]]} {
        rename ::dialog::saveFile {}
        rename ::scidb::test::htmlpop::savedSaveFile ::dialog::saveFile
    }
    catch {destroy $dlg}
} -result {1 1 1}

proc ::scidb::test::htmlpop::choosePending {menu surface index} {
    variable rows {}
    walk $menu $surface
    foreach row $rows {
        set cmd [lindex $row 4]
        if {[lindex $cmd 0] ne "::action::run"} {error "raw pending row $row"}
        ::action::get [lindex $cmd 1]
        puts [list HTML_DRAWABLE_ROW {*}$row]
    }
    puts [list HTML_DRAWABLE_CENSUS surface $surface rows [llength $rows] exemptions 0]
    $menu invoke $index
    ::tk::MenuUnpost $menu
}
tcltest::test menu-html-pending-board {native board insertion choice is included in the drawable census} -body {
    ::action::run open_game {number 1}
    ::scidb::game::go start
    set old [array get ::move::Options]
    set ::move::Options(addVarWithoutAsking) 0
    set ::move::Options(askToReplaceMoves) 1
    set menu $::application::board::board.popup_confirm
    set timer [after 200 [list ::scidb::test::htmlpop::choosePending $menu board.choice 1]]
    ::move::ConfirmReplaceMove menu {}
} -cleanup {
    after cancel $timer
    array set ::move::Options $old
} -result variation

tcltest::test menu-html-online-promotion {offline native online-board promotion returns its registered selected piece} -body {
    set view [::online::window::gameTab popup:generated {Generated promotion} ::scidb::test::htmlpop::offline w]
    update
    set timer [after 200 [list ::scidb::test::htmlpop::choosePending $view.promo online.promotion 3]]
    ::online::view::AskPromotion $view
} -cleanup {
    after cancel $timer
    catch {::online::window::closeTab popup:generated}
    catch {destroy .online}
} -result n

proc ::scidb::test::htmlpop::offline {args} {}


tcltest::test menu-html-merge {real merge-window drawable popup includes registry font and notation rows} -body {
    set rows [::scidb::test::htmlpop::mergeRows]
    set ids {}
    foreach row $rows {lappend ids [lindex [lindex $row 4] 1]}
    list [expr {"html.merge.font_inc" in $ids}] [expr {"html.merge.font_dec" in $ids}] [expr {"html.merge.notation" in $ids}]
} -result {1 1 1}

::scidb::test::actions::release
tcltest::cleanupTests
