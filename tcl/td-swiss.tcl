# Dutch pairing is delegated exclusively to the pinned bbpPairings helper.
if {[llength [info commands ::util::source]]} { ::util::source td-swiss }
namespace eval ::td::swiss { variable Counter 0; variable Jobs; variable Timeout 10000 }

proc ::td::swiss::Executable {} {
    if {[info exists ::env(SCIDB_BBP_PAIRINGS)]} {
        set path $::env(SCIDB_BBP_PAIRINGS)
        if {[file executable $path] && [file isfile $path]} { return $path }
        error "configured bbpPairings helper is unavailable"
    }
    set suffix [expr {$::tcl_platform(platform) eq "windows" ? ".exe" : ""}]
    foreach path [list [file join [pwd] build bbp-native bbpPairings$suffix] [file join [file dirname [info nameofexecutable]] bbpPairings$suffix]] {
        if {[file executable $path] && [file isfile $path]} { return $path }
    }
    set path [auto_execok bbpPairings$suffix]
    if {$path ne ""} { return [lindex $path 0] }
    error "Dutch Swiss requires the bbpPairings v6.0.0 helper; round robin remains available"
}
proc ::td::swiss::Readable {id pipe} {
    variable Jobs
    if {[catch {read $pipe} data]} { set Jobs($id,error) $data; set Jobs($id,done) 1; return }
    append Jobs($id,data) $data
    if {[string length $Jobs($id,data)] > 4000000} { Expire $id $pipe; return }
    if {[eof $pipe]} { set Jobs($id,done) 1 }
}
proc ::td::swiss::Expire {id pipe} {
    variable Jobs
    set Jobs($id,error) "bbpPairings exceeded time or output limit"
    foreach child [pid $pipe] {
        if {$::tcl_platform(platform) eq "windows"} { catch {exec taskkill /PID $child /T /F} } else { catch {exec kill -KILL -- $child} }
    }
    set Jobs($id,done) 1
}
# No shell interpolation; all files are disposable and all errors are surfaced.
proc ::td::swiss::Run {trf {mode -p}} {
    variable Counter; variable Jobs; variable Timeout
    if {$mode ni {-p -c}} { error "unsupported helper operation" }
    set executable [Executable]
    set input [file tempfile filename td-bbp-]
    set pipe {}
    set timer {}
    set id [incr Counter]
    try {
        fconfigure $input -encoding utf-8 -translation lf
        puts -nonewline $input $trf
        close $input
        set pipe [open [list | $executable --dutch $filename $mode 2>@1] r]
        fconfigure $pipe -blocking 0 -encoding utf-8
        set Jobs($id,data) {}
        set Jobs($id,error) {}
        set Jobs($id,done) 0
        fileevent $pipe readable [list ::td::swiss::Readable $id $pipe]
        set timer [after $Timeout [list ::td::swiss::Expire $id $pipe]]
        vwait ::td::swiss::Jobs($id,done)
        fileevent $pipe readable {}
        fconfigure $pipe -blocking 1
        set failed [catch {close $pipe} detail]
        set pipe {}
        if {$Jobs($id,error) ne ""} { error $Jobs($id,error) }
        if {$failed} { error "bbpPairings failed: $Jobs($id,data) ($detail)" }
        return [string trim $Jobs($id,data)]
    } finally {
        if {$timer ne ""} { after cancel $timer }
        if {$pipe ne ""} { catch {close $pipe} }
        catch {close $input}
        file delete $filename
        array unset Jobs $id,*
    }
}
proc ::td::swiss::Parse {text eligible} {
    set lines [split [string trim $text] \n]
    set count [string trim [lindex $lines 0]]
    if {![string is integer -strict $count] || $count < 1 || [llength $lines] != $count+1} { error "invalid bbpPairings output: $text" }
    set seen {}; set pairs {}
    foreach line [lrange $lines 1 end] {
        if {![regexp {^\s*([0-9]+)\s+([0-9]+)\s*$} $line -> w b]} { error "invalid helper pairing" }
        foreach n [list $w $b] {
            if {$n == 0} { continue }
            if {$n ni $eligible || $n in $seen} { error "helper returned an unknown or duplicate player" }
            lappend seen $n
        }
        if {$w == 0 || $w == $b} { error "invalid helper seats" }
        lappend pairs [list $w $b]
    }
    if {[lsort -integer $seen] ne [lsort -integer $eligible]} { error "helper omitted an eligible player" }
    return $pairs
}
proc ::td::swiss::Pair {state round} {
    set eligible {}; set ids {}
    foreach player [dict get $state players] {
        set id [dict get $player id]; set no [dict get $player number]
        dict set ids $no $id
        if {[::td::model::dg $player withdrawn 0]} { continue }
        set excluded 0
        foreach p [::td::model::Pairings $state $round] { if {[dict get $p white] eq $id || [dict get $p black] eq $id} { set excluded 1 } }
        if {!$excluded} { lappend eligible $no }
    }
    if {![llength $eligible]} { return {} }
    set text [::td::trf::Write $state trf26 [expr {$round-1}] $round]
    set pairs [Parse [Run $text] $eligible]
    set out {}; set board 0
    foreach pair $pairs {
        lassign $pair w b
        set bye [expr {$b == 0}]
        set p [dict create id r${round}b${board} round $round board $board white [dict get $ids $w] black [expr {$bye ? "" : [dict get $ids $b]}] \
            result * status [expr {$bye ? "complete" : "pending"}] category [expr {$bye ? "pairing-bye" : ""}] \
            played 0 count_standings 1 rating 0 attempt 0 game_id {} pgn {} result_history {}]
        if {$bye} { dict set p points 2 }
        lappend out $p
        incr board
    }
    return $out
}
proc ::td::swiss::PairRound {state domain} {
    if {[dict get $state status] eq "finished"} { error "event is finished" }
    set last 0
    foreach p [dict get $state pairings] {
        if {[dict get $p black] ne "" || [dict get $p category] eq "pairing-bye"} { set last [expr {max($last,[dict get $p round])}] }
    }
    set next [expr {$last+1}]
    set requested [::td::model::dg $domain round 0]
    if {$requested && $requested != $next} { error "Swiss rounds must be paired sequentially; next is $next" }
    if {$next > [dict get $state rounds]} { error "all scheduled rounds are paired" }
    foreach p [dict get $state pairings] {
        if {[dict get $p round] <= $last && [dict get $p status] ne "complete"} { error "enter all previous round results before pairing" }
    }
    set pairs [Pair $state $next]
    dict lappend state pairings {*}$pairs
    dict set state current_round $next
    dict set state status active
    return [list $state [dict create paired [llength $pairs] round $next] {} 1]
}
proc ::td::swiss::CheckRound {state {round 0}} {
    if {!$round} { set round [::td::model::dg $state current_round 1] }
    set violations {}
    set roundPairings [::td::model::Pairings $state $round]
    set seen {}
    foreach p $roundPairings {
        foreach side {white black} {
            set pid [dict get $p $side]
            if {$pid eq ""} { continue }
            if {$pid in $seen} {
                lappend violations [dict create code C4-DUPLICATE player $pid detail "player $pid appears more than once in round $round"]
            }
            lappend seen $pid
        }
    }
    foreach p $roundPairings {
        set w [dict get $p white]
        set b [dict get $p black]
        if {$b eq ""} {
            if {[::td::model::dg $p category {}] eq "pairing-bye"} {
                foreach q [dict get $state pairings] {
                    if {[dict get $q round] >= $round} { continue }
                    if {[dict get $q white] eq $w && [dict get $q black] eq "" && [::td::model::dg $q category {}] in {pairing-bye full-point-bye}} {
                        lappend violations [dict create code C2-REPEAT-PAB pairing [dict get $p id] player $w detail "player $w already received a pairing-allocated or full-point bye before round $round"]
                    }
                    if {([dict get $q white] eq $w || [dict get $q black] eq $w) && ![::td::model::dg $q played 0] && [::td::model::Points $q $w] eq "2 1"} {
                        lappend violations [dict create code C2-FORFEIT-WIN-PAB pairing [dict get $p id] player $w detail "player $w already scored a forfeit win before round $round"]
                    }
                }
            }
            continue
        }
        # C1: two players shall not play each other more than once (played games).
        foreach q [dict get $state pairings] {
            if {[dict get $q round] >= $round || ![::td::model::dg $q played 0]} { continue }
            if {([dict get $q white] eq $w && [dict get $q black] eq $b) || ([dict get $q white] eq $b && [dict get $q black] eq $w)} {
                lappend violations [dict create code C1-REMATCH pairing [dict get $p id] white $w black $b detail "rematch of played game [dict get $q id] (round [dict get $q round])"]
            }
        }
        # C3: non-topscorers with the same absolute colour preference shall not meet (check three consecutive same colours or +/-2 colour difference).
        if {$round < [dict get $state rounds]} {
            foreach {side pid req} [list white $w W black $b B] {
                set hist {}
                foreach q [dict get $state pairings] {
                    if {[dict get $q round] >= $round || ![::td::model::dg $q played 0] || [dict get $q black] eq ""} { continue }
                    if {[dict get $q white] eq $pid} { lappend hist W } elseif {[dict get $q black] eq $pid} { lappend hist B }
                }
                set wCount [llength [lsearch -all -exact $hist W]]
                set bCount [llength [llength [lsearch -all -exact $hist B]]]
                set bCount [llength [lsearch -all -exact $hist B]]
                set diff [expr {$wCount - $bCount}]
                set last2 [lrange $hist end-1 end]
                set absPref {}
                if {$diff > 1 || $last2 eq {W W}} { set absPref B }
                if {$diff < -1 || $last2 eq {B B}} { set absPref W }
                if {$absPref ne "" && $absPref ne $req} {
                    lappend violations [dict create code C3-ABSOLUTE-COLOUR pairing [dict get $p id] player $pid detail "player $pid has absolute colour preference $absPref but is assigned $req"]
                }
            }
        }
    }
    set bbpReport {}
    set bbpDiscrepancy 0
    if {[dict get $state system] eq "swiss" && ![llength [lsearch -all -inline -glob [lmap v $violations {dict get $v code}] C4-*]]} {
        if {![catch {::td::trf::Write $state trf26 $round 0 1} trf] && ![catch {Run $trf -c} out]} {
            set bbpReport $out
            if {[string match "*Checker pairings*" $out] || [string match "*No valid pairing exists*" $out]} {
                set bbpDiscrepancy 1
                lappend violations [dict create code C04-QUALITY-DISCREPANCY round $round detail "bbpPairings -c reported pairing discrepancy from Dutch C.04.3 order"]
            }
        }
    }
    return [dict create round $round compliant [expr {[llength $violations] == 0}] violations $violations bbp_discrepancy $bbpDiscrepancy bbp_report $bbpReport]
}
