# Tactics trainer. Chess facts resolve legal moves; engine scores are side-to-move.
namespace eval ::tactics {
    variable progress {}
    variable session {}
    variable puzzles {}
    variable queue {}
    variable message "Open a FEN-based puzzle PGN or build an AI training set."
    variable move ""
    variable selected ""
}

proc ::tactics::progressFile {} {
    return [file join $::scidb::dir::home training tactics.dat]
}
proc ::tactics::readProgress {} {
    variable progress
    set progress {}
    set path [progressFile]
    if {![file exists $path]} { return }
    set f [::open $path r]
    try {
        set data [string trim [read $f]]
        dict for {id record} $data {
            if {$id eq "streak"} {
                if {![string is integer -strict $record] || $record < 0} { error "Invalid tactics streak" }
            } elseif {![dict exists $record status] || [dict get $record status] ni {first retry failed}
                || ![dict exists $record attempts] || ![string is integer -strict [dict get $record attempts]]} {
                error "Invalid tactics progress record"
            }
        }
        set progress $data
    } finally { ::close $f }
}
proc ::tactics::saveProgress {} {
    variable progress
    set path [progressFile]
    file mkdir [file dirname $path]
    set tmp $path.[pid].tmp
    set f [::open $tmp w]
    try { puts $f $progress } finally { ::close $f }
    file rename -force $tmp $path
}
proc ::tactics::facts {fen move} {
    set json [::scidb::ai::moveFacts $move $fen]
    foreach field {uci fenAfter} {
        if {![regexp [format {"%s":"([^"]+)"} $field] $json -> value]} {
            error "Illegal move: $move"
        }
        dict set result $field $value
    }
    return $result
}
# Normalize the entire line before admitting a puzzle, so bad input is explicit.
proc ::tactics::puzzle {fen moves} {
    if {[llength $fen] != 6 || [lindex $fen 1] ni {w b}} { error "Invalid puzzle FEN" }
    set position $fen
    set line {}
    foreach move $moves {
        set fact [facts $position $move]
        lappend line [dict get $fact uci]
        set position [dict get $fact fenAfter]
    }
    if {![llength $line]} { error "Puzzle has no solution" }
    return [dict create id [list $fen $line] fen $fen line $line]
}
# PGN mainline only: annotations and nested variations cannot become answers.
proc ::tactics::parseGame {tags text} {
    if {![dict exists $tags FEN]} { return {} }
    set engine {}
    regexp {\{engine line: ([^\}]*)\}} $text -> engine
    regsub -all {;[^\n]*} $text { } text
    regsub -all {\{[^\}]*\}} $text { } text
    while {[regsub -all {\([^()]*\)} $text { } text]} {}
    if {[regexp {[()\{\}]} $text]} { error "Unbalanced PGN annotation" }
    regsub -all {\$[0-9]+|[0-9]+\.(\.\.)?} $text { } text
    set moves {}
    foreach token [regexp -all -inline {\S+} $text] {
        if {$token in {* 1-0 0-1 1/2-1/2}} { break }
        lappend moves [string trimright $token !?]
    }
    # AITrainingSet writes its PV as UCI in a comment, including the first move.
    if {$engine ne ""} { set moves [regexp -all -inline {\S+} $engine] }
    return [puzzle [dict get $tags FEN] $moves]
}
proc ::tactics::loadPGN {path} {
    set f [::open $path r]
    try { set data [read $f] } finally { ::close $f }
    set tags {}; set text ""; set result {}
    foreach line [split $data \n] {
        if {[regexp {^\s*\[([A-Za-z0-9_]+)\s+"(.*)"\]\s*$} $line -> key value]} {
            if {[string trim $text] ne ""} {
                set p [parseGame $tags $text]
                if {$p ne ""} { lappend result $p }
                set tags {}; set text ""
            }
            dict set tags $key $value
        } else { append text $line \n }
    }
    set p [parseGame $tags $text]
    if {$p ne ""} { lappend result $p }
    if {![llength $result]} { error "No FEN-based puzzles found" }
    return $result
}
proc ::tactics::ordered {items} {
    variable progress
    set failed {}; set other {}
    foreach p $items {
        set id [dict get $p id]
        if {[dict exists $progress $id status] && [dict get $progress $id status] eq "failed"} {
            lappend failed $p
        } else { lappend other $p }
    }
    return [concat $failed $other]
}
proc ::tactics::start {p} {
    variable session
    set session [dict create puzzle $p fen [dict get $p fen] line [dict get $p line] retries 0 state playing]
}
# Compare BOTH child positions at the same depth, negating opponent scores.
# +100cp is the minimum winning advantage; losing/drawn alternatives fail closed.
proc ::tactics::checkMove {fen expected move} {
    set actual [facts $fen $move]
    set solution [facts $fen $expected]
    if {[dict get $actual uci] eq [dict get $solution uci]} {
        return [dict create correct 1 alternate 0 fact $actual]
    }
    set reference [::ai::engine::evaluate [dict get $solution fenAfter] -depth 16 -multipv 1]
    set candidate [::ai::engine::evaluate [dict get $actual fenAfter] -depth 16 -multipv 1]
    set ref [expr {-[dict get $reference cpl]}]
    set cp [expr {-[dict get $candidate cpl]}]
    return [dict create correct [expr {$cp >= 100 && $cp >= $ref - 30}] alternate 1 \
        fact $actual continuation [dict get $candidate pv]]
}
proc ::tactics::finish {status} {
    variable session; variable progress
    if {[dict get $session state] eq "done"} { return }
    if {[dict exists $session outcome] && [dict get $session outcome] eq $status} {
        dict set session state done
        return
    }
    set id [dict get $session puzzle id]
    set count 0
    if {[dict exists $progress $id attempts]} { set count [dict get $progress $id attempts] }
    dict set progress $id [dict create status $status attempts [incr count]]
    set streak 0
    if {[dict exists $progress streak]} { set streak [dict get $progress streak] }
    if {$status eq "first"} { incr streak } else { set streak 0 }
    dict set progress streak $streak
    dict set session state done
    dict set session outcome $status
    saveProgress
}
proc ::tactics::play {move} {
    variable session
    if {[dict get $session state] ne "playing"} { error "Choose Retry, Show solution, or Next" }
    set line [dict get $session line]
    set verdict [checkMove [dict get $session fen] [lindex $line 0] $move]
    if {![dict get $verdict correct]} {
        dict set session state wrong
        # Persist immediately: abandoned failures must return first on restart.
        finish failed
        dict set session state wrong
        return wrong
    }
    set fen [dict get $verdict fact fenAfter]
    set line [lrange $line 1 end]
    if {[dict get $verdict alternate]} { set line [dict get $verdict continuation] }
    if {[llength $line]} {
        set reply [facts $fen [lindex $line 0]]
        set fen [dict get $reply fenAfter]
        set line [lrange $line 1 end]
    }
    dict set session fen $fen
    dict set session line $line
    if {![llength $line]} {
        finish [expr {[dict get $session retries] ? "retry" : "first"}]
        return solved
    }
    return correct
}
proc ::tactics::retry {} {
    variable session
    if {$session eq "" || [dict get $session state] ne "wrong"} { return }
    set retries [expr {[dict get $session retries] + 1}]
    start [dict get $session puzzle]
    dict set session retries $retries
    # a retry starts over: drop the "Wrong move" message
    variable message [ToMove]
    catch render
}
proc ::tactics::score {} {
    variable progress
    set counts [dict create first 0 retry 0 failed 0 streak 0]
    dict for {id record} $progress {
        if {$id eq "streak"} { dict set counts streak $record } else {
            dict incr counts [dict get $record status]
        }
    }
    return "First try: [dict get $counts first]   With retries: [dict get $counts retry]   Failed: [dict get $counts failed]   Streak: [dict get $counts streak]"
}
proc ::tactics::next {} {
    variable queue; variable puzzles; variable session; variable message
    if {$session ne "" && [dict get $session state] eq "playing"} { finish failed }
    if {![llength $queue]} { set queue [ordered $puzzles] }
    if {![llength $queue]} { return }
    start [lindex $queue 0]
    set queue [lrange $queue 1 end]
    set message [ToMove]
    render
}
# The prompt for the side to move of the current puzzle.
proc ::tactics::ToMove {} {
    variable session
    return "[expr {[lindex [dict get $session fen] 1] eq "w" ? "White" : "Black"}] to move. Click source and destination, then Play move; or enter SAN / UCI (append q/r/b/n to promote)."
}
proc ::tactics::openPGN {} {
    variable puzzles; variable queue; variable session
    set path [tk_getOpenFile -parent .tactics -filetypes {{{PGN files} {.pgn}}}]
    if {$path eq ""} { return }
    set loaded [loadPGN $path]
    if {$session ne "" && [dict get $session state] eq "playing"} { finish failed }
    set puzzles $loaded; set queue [ordered $puzzles]; set session {}
    next
}
proc ::tactics::showSolution {} {
    variable session; variable message
    if {$session eq ""} { return }
    finish failed
    set p [dict get $session puzzle]
    set fen [dict get $p fen]
    foreach move [dict get $p line] { set fen [dict get [facts $fen $move] fenAfter] }
    dict set session fen $fen
    set message "Solution: [join [dict get $p line] { }]"
    render
}
proc ::tactics::submit {} {
    variable move; variable message
    set result [play $move]
    set move ""
    set message [dict get {wrong {Wrong move. Retry or Show solution.} correct {Correct. Your turn.} solved {Solved! Choose Next.}} $result]
    render
}
proc ::tactics::guard {command} {
    if {[catch {uplevel #0 $command} err]} { tk_messageBox -parent .tactics -icon error -message $err }
}
proc ::tactics::click {x y} {
    variable selected; variable move
    set cell [expr {[.tactics.board cget -width] / 8}]
    set square "[string index abcdefgh [expr {$x / $cell}]][expr {8 - $y / $cell}]"
    if {$selected eq ""} { set selected $square; return }
    set move $selected$square; set selected ""
    # Entry remains editable for underpromotion (append q/r/b/n).
    focus .tactics.move
}
proc ::tactics::render {} {
    variable session; variable selected
    set selected ""
    if {$session eq ""} { return }
    set c .tactics.board
    $c delete all
    set cell [expr {[$c cget -width] / 8}]
    set row 0
    set glyphs [dict create K \u2654 Q \u2655 R \u2656 B \u2657 N \u2658 P \u2659 k \u265a q \u265b r \u265c b \u265d n \u265e p \u265f]
    foreach rank [split [lindex [dict get $session fen] 0] /] {
        set col 0
        foreach piece [split $rank ""] {
            if {[string is digit -strict $piece]} { set cells $piece; set piece "" } else { set cells 1 }
            for {set i 0} {$i < $cells} {incr i} {
                set x [expr {$col * $cell}]; set y [expr {$row * $cell}]
                $c create rectangle $x $y [expr {$x+$cell}] [expr {$y+$cell}] -fill [expr {($row+$col)%2 ? "#b58863" : "#f0d9b5"}] -outline {}
                if {$piece ne ""} { $c create text [expr {$x+$cell/2}] [expr {$y+$cell/2}] -text [dict get $glyphs $piece] -font [list {DejaVu Sans} [expr {$cell*2/3}]] -fill black }
                incr col
            }
        }
        incr row
    }
    .tactics.score configure -text [score]
}
proc ::tactics::close {} {
    variable session
    if {$session ne "" && [dict get $session state] eq "playing"} { finish failed }
    destroy .tactics
}
proc ::tactics::open {{parent .application}} {
    variable session
    if {[winfo exists .tactics]} { raise .tactics; return }
    readProgress
    set session {}
    toplevel .tactics
    wm title .tactics "Tactics Trainer"
    wm transient .tactics [winfo toplevel $parent]
    wm protocol .tactics WM_DELETE_WINDOW {::tactics::guard ::tactics::close}
    ttk::button .tactics.open -text "Open puzzle PGN..." -command {::tactics::guard ::tactics::openPGN}
    ttk::button .tactics.build -text "AI: Training Set from Games..." -command [list ::ai::cql::training $parent]
    canvas .tactics.board -width 320 -height 320 -highlightthickness 0
    bind .tactics.board <Button-1> {::tactics::click %x %y}
    ttk::label .tactics.status -textvariable ::tactics::message -wraplength 384
    ttk::entry .tactics.move -textvariable ::tactics::move
    bind .tactics.move <Return> {::tactics::guard ::tactics::submit}
    ttk::button .tactics.play -text "Play move" -command {::tactics::guard ::tactics::submit}
    ttk::button .tactics.retry -text Retry -command {::tactics::retry; ::tactics::render}
    ttk::button .tactics.show -text "Show solution" -command {::tactics::guard ::tactics::showSolution}
    ttk::button .tactics.next -text Next -command {::tactics::guard ::tactics::next}
    ttk::label .tactics.score -text [score]
    # Share action rows so the puzzle and all controls fit short work areas.
    # Keep widget paths stable for the puzzle callbacks.
    grid .tactics.open -row 0 -column 0 -pady 1
    grid .tactics.build -row 0 -column 1 -columnspan 2 -pady 1
    grid .tactics.board -row 1 -column 0 -columnspan 3 -pady 1
    grid .tactics.status -row 2 -column 0 -columnspan 3 -pady 1
    grid .tactics.move -row 3 -column 0 -columnspan 2 -pady 1
    grid .tactics.play -row 3 -column 2 -pady 1
    grid .tactics.retry -row 4 -column 0 -pady 1
    grid .tactics.show -row 4 -column 1 -pady 1
    grid .tactics.next -row 4 -column 2 -pady 1
    grid .tactics.score -row 5 -column 0 -columnspan 3 -pady 1
    # Keep the main board visible and register for subsequent layout changes.
    ::util::place::besideBoard .tactics $parent
}
