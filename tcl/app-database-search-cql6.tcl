# Official CQL 6.2 power-user editor. Searches run asynchronously; the match
# list is virtual, so its cost does not grow with the number of matches.
namespace eval ::application::database {
    variable Cql6SearchData
    variable Cql6SearchSerial 0
    namespace eval mc { set Cql6Search "CQL 6.2 Search" }
}

proc ::application::database::OpenCql6Search {parent file variant} {
    variable Cql6SearchData
    variable Cql6SearchSerial
    set dlg .cql6search[string map {. _ / _ " " _ : _} "$file$variant"]
    if {[winfo exists $dlg]} { raise $dlg; focus $dlg.script; return $dlg }
    if {$variant ne "Normal"} {
        return [::dialog::error -parent $parent -message "CQL 6.2 searches standard chess games."]
    }
    set Cql6SearchData($dlg,file) $file
    set Cql6SearchData($dlg,variant) $variant
    set Cql6SearchData($dlg,epoch) [incr Cql6SearchSerial]
    set Cql6SearchData($dlg,job) {}
    set Cql6SearchData($dlg,timer) {}
    set Cql6SearchData($dlg,results) {}
    set Cql6SearchData($dlg,count) 0
    set Cql6SearchData($dlg,top) 0
    set Cql6SearchData($dlg,visible) 12
    set Cql6SearchData($dlg,selected) -1
    set Cql6SearchData($dlg,variations) 0
    set Cql6SearchData($dlg,threads) 8
    set Cql6SearchData($dlg,status) "Enter a CQL 6.2 script."
    tk::toplevel $dlg -class Scidb
    wm title $dlg "CQL 6.2 — [::util::databaseName $file no]"
    wm protocol $dlg WM_DELETE_WINDOW [namespace code [list Cql6Close $dlg]]
    bind $dlg <Destroy> [namespace code [list Cql6Destroyed $dlg %W]]
    ttk::label $dlg.label -text "CQL 6.2 script"
    text $dlg.script -width 76 -height 12 -wrap word -undo 1
    $dlg.script insert 1.0 "cql() mate"
    ttk::frame $dlg.options
    ttk::checkbutton $dlg.options.vars -text "Search variations" \
        -variable [namespace current]::Cql6SearchData($dlg,variations)
    ttk::label $dlg.options.label -text "Workers"
    ttk::spinbox $dlg.options.workers -from 1 -to 256 -width 4 \
        -textvariable [namespace current]::Cql6SearchData($dlg,threads)
    ttk::button $dlg.options.run -text "Search" -command [namespace code [list Cql6Run $dlg]]
    ttk::button $dlg.options.cancel -text "Cancel" -state disabled -command [namespace code [list Cql6Cancel $dlg]]
    pack $dlg.options.vars $dlg.options.label $dlg.options.workers -side left -padx 4
    pack $dlg.options.cancel $dlg.options.run -side right -padx 4
    ttk::label $dlg.status -textvariable [namespace current]::Cql6SearchData($dlg,status)
    text $dlg.output -height 4 -width 76 -wrap word -state disabled
    ttk::scrollbar $dlg.scroll -orient vertical -command [namespace code [list Cql6Scroll $dlg]]
    Cql6Results $dlg
    grid $dlg.label -row 0 -column 0 -sticky w -padx 8 -pady 4
    grid $dlg.script -row 1 -column 0 -columnspan 2 -sticky nsew -padx 8
    grid $dlg.options -row 2 -column 0 -columnspan 2 -sticky ew -padx 8 -pady 6
    grid $dlg.status -row 3 -column 0 -columnspan 2 -sticky w -padx 8
    grid $dlg.results -row 4 -column 0 -sticky nsew -padx {8 0} -pady 8
    grid $dlg.scroll -row 4 -column 1 -sticky ns -pady 8 -padx {0 8}
    grid $dlg.output -row 5 -column 0 -columnspan 2 -sticky ew -padx 8 -pady {0 8}
    grid columnconfigure $dlg 0 -weight 1
    grid rowconfigure $dlg 1 -weight 1
    grid rowconfigure $dlg 4 -weight 1
    focus $dlg.script
    return $dlg
}

# Matches stay in the engine glue (-paged): a million Tcl objects would stall
# the GUI when created and again when freed.
proc ::application::database::Cql6Run {dlg} {
    variable Cql6SearchData
    if {$Cql6SearchData($dlg,job) ne ""} { return }
    set script [string trim [$dlg.script get 1.0 end]]
    if {[catch {
        set job [::scidb::cql6::search $Cql6SearchData($dlg,file) $Cql6SearchData($dlg,variant) $script \
            -threads $Cql6SearchData($dlg,threads) -variations $Cql6SearchData($dlg,variations) \
            -paged 1 -command [namespace code [list Cql6Finished $dlg $Cql6SearchData($dlg,epoch)]]]
    } error]} { set Cql6SearchData($dlg,status) $error; return }
    set Cql6SearchData($dlg,job) $job
    Cql6Release $dlg
    Cql6Fill $dlg
    $dlg.options.run configure -state disabled
    $dlg.options.cancel configure -state normal
    Cql6Poll $dlg
}

proc ::application::database::Cql6Poll {dlg} {
    variable Cql6SearchData
    if {![info exists Cql6SearchData($dlg,job)] || $Cql6SearchData($dlg,job) eq ""} { return }
    set n [::scidb::cql6::progress $Cql6SearchData($dlg,job)]
    set Cql6SearchData($dlg,status) "Searching… $n games read"
    set Cql6SearchData($dlg,timer) [after 200 [namespace code [list Cql6Poll $dlg]]]
}

proc ::application::database::Cql6Finished {dlg epoch result} {
    variable Cql6SearchData
    if {![info exists Cql6SearchData($dlg,epoch)] || $Cql6SearchData($dlg,epoch) != $epoch} {
        if {[dict exists $result results]} { ::scidb::cql6::release [dict get $result results] }
        return
    }
    after cancel $Cql6SearchData($dlg,timer)
    set Cql6SearchData($dlg,job) {}
    $dlg.options.cancel configure -state disabled
    $dlg.options.run configure -state normal
    if {![dict get $result ok]} {
        set Cql6SearchData($dlg,status) [dict get $result error]
        return
    }
    set Cql6SearchData($dlg,results) [dict get $result results]
    set Cql6SearchData($dlg,count) [dict get $result count]
    $dlg.output configure -state normal
    $dlg.output delete 1.0 end
    $dlg.output insert 1.0 [dict get $result messages]
    $dlg.output configure -state disabled
    set Cql6SearchData($dlg,status) "[dict get $result count] matches in [dict get $result games] games"
    if {[dict get $result cancelled]} { append Cql6SearchData($dlg,status) " (cancelled)" }
    Cql6Fill $dlg
}

# The treeview holds only the visible rows: a ttk::treeview redraw walks all
# of its items, about 40 ms for a million. Item ids are match positions.
proc ::application::database::Cql6Results {dlg} {
    set tree $dlg.results
    ttk::treeview $tree -columns {game ply} -show headings -selectmode browse -height 12
    $tree heading game -text "Game"
    $tree heading ply -text "First matching ply"
    bind $tree <Configure> [namespace code [list Cql6Resize $dlg]]
    bind $tree <<TreeviewSelect>> [namespace code [list Cql6Selected $dlg]]
    bind $tree <Double-Button-1> [namespace code [list Cql6OpenGame $dlg]]
    bind $tree <Return> [namespace code [list Cql6OpenGame $dlg]]
    foreach {key delta} {Down 1 Up -1 Next page Prior -page Home -end End end} {
        bind $tree <$key> "[namespace code [list Cql6Move $dlg $delta]]; break"
    }
    bind $tree <MouseWheel> "[namespace code [list Cql6Scroll $dlg scroll]] \[expr {-%D/40}\] units; break"
    bind $tree <Button-4> "[namespace code [list Cql6Scroll $dlg scroll -3 units]]; break"
    bind $tree <Button-5> "[namespace code [list Cql6Scroll $dlg scroll 3 units]]; break"
}

proc ::application::database::Cql6Fill {dlg} {
    variable Cql6SearchData
    set tree $dlg.results
    set n $Cql6SearchData($dlg,count)
    set visible $Cql6SearchData($dlg,visible)
    set top [expr {max(0, min($Cql6SearchData($dlg,top), $n - $visible))}]
    set Cql6SearchData($dlg,top) $top
    $tree delete [$tree children {}]
    if {$Cql6SearchData($dlg,results) ne ""} {
        set index $top
        foreach {game ply} [::scidb::cql6::matches $Cql6SearchData($dlg,results) $top $visible] {
            if {$ply < 0} { set ply "not annotated" }
            $tree insert {} end -id $index -values [list [expr {$game + 1}] $ply]
            incr index
        }
    }
    set selected $Cql6SearchData($dlg,selected)
    if {[$tree exists $selected]} {
        $tree selection set $selected
        $tree focus $selected
    }
    if {$n == 0} { $dlg.scroll set 0 1 } else {
        $dlg.scroll set [expr {double($top)/$n}] [expr {min(1.0, double($top + $visible)/$n)}]
    }
}

proc ::application::database::Cql6Resize {dlg} {
    variable Cql6SearchData
    set tree $dlg.results
    set first [lindex [$tree children {}] 0]
    if {$first eq "" || [llength [set box [$tree bbox $first]]] < 4} { return }
    lassign $box x y w h
    set visible [expr {max(1, ([winfo height $tree] - $y) / $h)}]
    if {$visible != $Cql6SearchData($dlg,visible)} {
        set Cql6SearchData($dlg,visible) $visible
        Cql6Fill $dlg
    }
}

proc ::application::database::Cql6Scroll {dlg command args} {
    variable Cql6SearchData
    set top $Cql6SearchData($dlg,top)
    switch -- $command {
        moveto { set top [expr {round([lindex $args 0] * $Cql6SearchData($dlg,count))}] }
        scroll {
            lassign $args amount unit
            if {$unit eq "pages"} { set amount [expr {$amount * $Cql6SearchData($dlg,visible)}] }
            incr top $amount
        }
    }
    set Cql6SearchData($dlg,top) $top
    Cql6Fill $dlg
}

proc ::application::database::Cql6Move {dlg delta} {
    variable Cql6SearchData
    set n $Cql6SearchData($dlg,count)
    if {$n == 0} { return }
    set visible $Cql6SearchData($dlg,visible)
    set selected $Cql6SearchData($dlg,selected)
    switch -- $delta {
        page { set selected [expr {$selected + $visible}] }
        -page { set selected [expr {$selected - $visible}] }
        end { set selected [expr {$n - 1}] }
        -end { set selected 0 }
        default { incr selected $delta }
    }
    set selected [expr {max(0, min($n - 1, $selected))}]
    set Cql6SearchData($dlg,selected) $selected
    set top $Cql6SearchData($dlg,top)
    if {$selected < $top} { set top $selected }
    if {$selected >= $top + $visible} { set top [expr {$selected - $visible + 1}] }
    set Cql6SearchData($dlg,top) $top
    Cql6Fill $dlg
}

proc ::application::database::Cql6Selected {dlg} {
    variable Cql6SearchData
    set selected [$dlg.results selection]
    if {[llength $selected]} { set Cql6SearchData($dlg,selected) [lindex $selected 0] }
}

proc ::application::database::Cql6OpenGame {dlg} {
    variable Cql6SearchData
    set selected $Cql6SearchData($dlg,selected)
    if {$selected < 0 || $Cql6SearchData($dlg,results) eq ""} { return }
    set game [lindex [::scidb::cql6::matches $Cql6SearchData($dlg,results) $selected 1] 0]
    if {$game eq ""} { return }
    ::game::new $dlg -base $Cql6SearchData($dlg,file) -variant $Cql6SearchData($dlg,variant) -number $game
}

proc ::application::database::Cql6Release {dlg} {
    variable Cql6SearchData
    if {$Cql6SearchData($dlg,results) ne ""} { ::scidb::cql6::release $Cql6SearchData($dlg,results) }
    set Cql6SearchData($dlg,results) {}
    set Cql6SearchData($dlg,count) 0
    set Cql6SearchData($dlg,top) 0
    set Cql6SearchData($dlg,selected) -1
}

proc ::application::database::Cql6Cancel {dlg} {
    variable Cql6SearchData
    if {$Cql6SearchData($dlg,job) ne ""} { ::scidb::cql6::cancel $Cql6SearchData($dlg,job) }
}
proc ::application::database::Cql6Close {dlg} { destroy $dlg }
proc ::application::database::Cql6Destroyed {dlg widget} {
    variable Cql6SearchData
    if {$widget ne $dlg || ![info exists Cql6SearchData($dlg,job)]} { return }
    Cql6Cancel $dlg
    after cancel $Cql6SearchData($dlg,timer)
    Cql6Release $dlg
    array unset Cql6SearchData $dlg,*
}
