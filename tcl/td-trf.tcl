# FIDE TRF edge adapter; the journal remains the canonical event store.
if {[llength [info commands ::util::source]]} { ::util::source td-trf }
namespace eval ::td::trf {}
proc ::td::trf::dg {d k {fallback {}}} { if {[dict exists $d $k]} { return [dict get $d $k] }; return $fallback }
proc ::td::trf::Field {text width} {
    if {[regexp {[\r\n\t\x00]} $text] || [string length $text] > $width} { error "TRF field exceeds $width columns or contains control characters: $text" }
    return [format %-*s $width $text]
}
proc ::td::trf::NormalizeTitle {raw} {
    set t [string tolower [string trim $raw]]
    set map {g GM m IM f FM c CM wg WGM wi WIM wf WFM wc WCM wh WH {} {}}
    if {[dict exists $map $t]} { return [dict get $map $t] }
    return [string toupper $t]
}
proc ::td::trf::HeaderVal {text {maxLen 120}} {
    set trimmed [string trimright $text]
    if {[regexp {[\r\n\t\x00]} $trimmed] || [string length $trimmed] > $maxLen} {
        error "TRF header field exceeds $maxLen columns or contains control characters: $trimmed"
    }
    return $trimmed
}
proc ::td::trf::TournamentType {state} {
    if {[dg $state tournament_type] ne ""} { return [HeaderVal [dict get $state tournament_type]] }
    switch -- [dg $state system swiss] {
        round-robin { return "Individual: Round-Robin" }
        double-round-robin { return "Individual: Double Round-Robin" }
        default { return "Individual: Swiss-System" }
    }
}
proc ::td::trf::TimeControlDesc {state} {
    if {[dg $state time_control_desc] ne ""} { return [HeaderVal [dict get $state time_control_desc]] }
    set tc [dg $state time_control {}]
    if {[dict exists $tc base_ms] && [dict exists $tc increment_ms]} {
        set bms [dict get $tc base_ms]
        set ims [dict get $tc increment_ms]
        set bMin [expr {$bms % 60000 == 0 ? $bms / 60000 : [format %g [expr {$bms / 60000.0}]]}]
        set iSec [expr {$ims % 1000 == 0 ? $ims / 1000 : [format %g [expr {$ims / 1000.0}]]}]
        return "$bMin min/player + $iSec s/move"
    }
    return "90 min/player + 30 s/move"
}
proc ::td::trf::EncodedTimeControl {state} {
    if {[dg $state encoded_time_control] ne ""} { return [HeaderVal [dict get $state encoded_time_control]] }
    set tc [dg $state time_control {}]
    if {[dict exists $tc base_ms] && [dict exists $tc increment_ms]} {
        set bms [dict get $tc base_ms]
        set ims [dict get $tc increment_ms]
        set bSec [expr {$bms % 1000 == 0 ? $bms / 1000 : [format %g [expr {$bms / 1000.0}]]}]
        set iSec [expr {$ims % 1000 == 0 ? $ims / 1000 : [format %g [expr {$ims / 1000.0}]]}]
        return "${bSec}+${iSec}"
    }
    return "5400+30"
}
proc ::td::trf::TrfTiebreaks {state} {
    if {[dg $state trf_tiebreaks] ne ""} { return [HeaderVal [dict get $state trf_tiebreaks]] }
    set codes [list PTS]
    set map {
        buchholzCut1 BH/C1
        buchholz BH
        buchholzMedian1 BH/M1
        sonnebornBerger SB
        directEncounter DE
        koya KS
        gamesWon WON
        wins WIN
        gamesWonWithBlack BWG
        progressive PS
        aro ARO
        averageRatingOfOpponents ARO
    }
    foreach tb [dg $state tiebreaks {buchholzCut1 buchholz sonnebornBerger wins}] {
        if {[dict exists $map $tb]} { lappend codes [dict get $map $tb] }
    }
    return [join $codes ,]
}
proc ::td::trf::ToRoundDate {dateStr fallback} {
    set s [string trim $dateStr]
    if {[regexp {^([0-9]{4})[-/.]([0-9]{2})[-/.]([0-9]{2})$} $s -> yyyy mm dd]} {
        return "[string range $yyyy 2 3]/$mm/$dd"
    }
    if {[regexp {^([0-9]{2})[-/.]([0-9]{2})[-/.]([0-9]{4})$} $s -> dd mm yyyy]} {
        return "[string range $yyyy 2 3]/$mm/$dd"
    }
    if {[regexp {^[0-9]{2}/[0-9]{2}/[0-9]{2}$} $s]} { return $s }
    return $fallback
}
proc ::td::trf::Code {p id} {
    if {[dict get $p black] eq ""} {
        if {[dg $p category] eq "pairing-bye"} { return U }
        return [dict get {0 Z 1 H 2 F} [dg $p points 0]]
    }
    if {[dg $p status pending] ne "complete"} { return " " }
    set result [dict get $p result]
    if {$result eq "*"} { return - }
    if {$result eq "1/2-1/2"} { return = }
    set win [expr {($result eq "1-0" && [dict get $p white] eq $id) || ($result eq "0-1" && [dict get $p black] eq $id)}]
    if {![dg $p played 0]} { return [expr {$win ? "+" : "-"}] }
    return [expr {$win ? "1" : "0"}]
}
# through=0 exports all entered rounds; pairingRound adds exclusions for that round.
# checkPending=1 encodes pending non-bye games as '=' so bbpPairings -c can check the round.
proc ::td::trf::Write {state {format trf26} {through -1} {pairingRound 0} {checkPending 0}} {
    if {$format ni {trf16 trf26}} { error "expected trf16 or trf26" }
    set lines [list "012 [HeaderVal [dict get $state name] 80]"]
    foreach {code key} {022 site 032 federation} {
        if {[dg $state $key] ne ""} { lappend lines "$code [HeaderVal [dict get $state $key] 80]" }
    }
    set startDate [HeaderVal [dg $state start_date] 80]
    if {$startDate eq ""} {
        set created [dg $state created 0]
        set startDate [expr {$created > 0 ? [clock format $created -format %Y-%m-%d -gmt 1] : "2026-01-01"}]
    }
    set endDate [HeaderVal [dg $state end_date] 80]
    if {$endDate eq ""} { set endDate $startDate }
    lappend lines "042 $startDate" "052 $endDate"
    set playerList [dg $state players {}]
    set playerCount [llength $playerList]
    set ratedCount 0
    foreach p $playerList {
        set r [string trim [dg $p rating {}]]
        if {[regexp {^[0-9]+$} $r] && [scan $r %d] > 0} { incr ratedCount }
    }
    lappend lines "062 $playerCount" "072 $ratedCount"
    if {[dg $state teams_count] ne ""} { lappend lines "082 [HeaderVal [dict get $state teams_count] 20]" }
    lappend lines "092 [TournamentType $state]"
    set ca [HeaderVal [dg $state chief_arbiter] 80]
    lappend lines [expr {$ca eq "" ? "102" : "102 $ca"}]
    set deputies {}
    foreach dep [dg $state deputy_arbiters {}] {
        set dep [HeaderVal $dep 80]
        if {$dep ne ""} { lappend deputies $dep }
    }
    if {![llength $deputies] && [HeaderVal [dg $state deputy_arbiter] 80] ne ""} {
        lappend deputies [HeaderVal [dict get $state deputy_arbiter] 80]
    }
    if {[llength $deputies]} {
        foreach dep $deputies { lappend lines "112 $dep" }
    } else {
        lappend lines "112"
    }
    lappend lines "122 [TimeControlDesc $state]"
    set rounds [dict get $state rounds]
    if {$rounds > 0} {
        set defRd [ToRoundDate $startDate "26/01/01"]
        set rDates [dg $state round_dates {}]
        set line132 [format "132%86s" ""]
        for {set r 1} {$r <= $rounds} {incr r} {
            set rawRd [lindex $rDates [expr {$r - 1}]]
            set rd [ToRoundDate $rawRd $defRd]
            append line132 [format "  %-8s" [HeaderVal $rd 8]]
        }
        lappend lines [string trimright $line132]
    }
    set colour [dg $state colour_lot white]
    if {$format eq "trf26"} {
        lappend lines "142 $rounds" "152 [string toupper [string index $colour 0]]"
        if {[dg $state trf_tiebreaks_202] ne ""} { lappend lines "202 [HeaderVal [dict get $state trf_tiebreaks_202]]" }
        lappend lines "212 [TrfTiebreaks $state]" "222 [EncodedTimeControl $state]"
    } else {
        lappend lines "XXR $rounds" "XXC ${colour}1"
    }
    set last 0
    foreach p [dict get $state pairings] { set last [expr {max($last,[dict get $p round])}] }
    if {$through >= 0} { set last $through }
    set numbers {}
    foreach player [dict get $state players] { dict set numbers [dict get $player id] [dict get $player number] }
    set rank 0
    set limit [expr {$pairingRound > 0 ? $pairingRound : $last}]
    foreach player [dict get $state players] {
        set id [dict get $player id]
        set n [dict get $player number]
        if {$n < 1 || $n > 9999} { error "TRF pairing number out of range" }
        set matches {}; set score2 0
        for {set r 1} {$r <= $limit} {incr r} {
            set found {}
            foreach p [dict get $state pairings] {
                if {[dict get $p round] == $r && ($id eq [dict get $p white] || $id eq [dict get $p black])} {
                    if {$found ne ""} { error "multiple round entries for $id in round $r" }
                    set found $p
                }
            }
            if {$found eq ""} {
                set excluded [expr {[dg $player withdrawn 0] && $r >= [dg $player withdrawn 0]}]
                set late [expr {$r < [dg $player entry_round 1]}]
                if {$excluded || $late} {
                    append matches "  0000 - Z"
                } elseif {$r <= $last} {
                    append matches "          "
                }
                continue
            }
            if {$r > $last && ([dict get $found black] ne "" || [dg $found category {}] eq "pairing-bye")} {
                continue
            }
            set code [Code $found $id]
            if {$code eq " " && $checkPending && [dict get $found black] ne ""} { set code = }
            set other [expr {$id eq [dict get $found white] ? [dict get $found black] : [dict get $found white]}]
            set no [expr {$other eq "" ? 0 : [dict get $numbers $other]}]
            set c [expr {$other eq "" ? "-" : $id eq [dict get $found white] ? "w" : "b"}]
            append matches [format "  %04d %s %s" $no $c $code]
            # FIDE report preserves played results annulled only for RR standings.
            if {$r <= $last} {
                if {$code in {1 + F U}} { incr score2 2 } elseif {$code in {= H}} { incr score2 }
            }
        }
        set rating [dg $player rating 0]; if {$rating eq ""} { set rating 0 }
        set title [NormalizeTitle [dg $player title]]
        set line "001 [format %4d $n] [Field [dg $player sex] 1][Field $title 3] [Field [dict get $player name] 33] [format %4d $rating] [Field [dg $player federation] 3] [format %11s [dg $player fide_id]] [Field [dg $player born] 10] [format %4.1f [expr {$score2/2.0}]] [format %4d [incr rank]]"
        if {[string length $line] != 89} { error "invalid TRF identity field width" }
        lappend lines "$line$matches"
    }
    return "[join $lines \n]\n"
}

proc ::td::trf::Read {text {through 0}} {
    set name "Imported Tournament"
    set site {}
    set federation {}
    set start_date {}
    set end_date {}
    set reported_players {}
    set reported_rated_players {}
    set teams_count {}
    set tournament_type {}
    set chief_arbiter {}
    set deputy_arbiters {}
    set time_control_desc {}
    set round_dates {}
    set trf_tiebreaks {}
    set trf_tiebreaks_202 {}
    set encoded_time_control {}
    set rounds 0
    set colour_lot white
    set format trf16
    set playerLines {}
    foreach raw [split $text \n] {
        set line [string trimright $raw \r]
        if {$line eq "" || [string match "###*" $line]} { continue }
        set tag [string range $line 0 2]
        set rest [string trim [string range $line 3 end]]
        switch -- $tag {
            012 { if {$rest ne ""} { set name $rest } }
            022 { set site $rest }
            032 { set federation $rest }
            042 { set start_date $rest }
            052 { set end_date $rest }
            062 { set reported_players $rest }
            072 { set reported_rated_players $rest }
            082 { set teams_count $rest }
            092 { set tournament_type $rest }
            102 { set chief_arbiter $rest }
            112 { if {$rest ne ""} { lappend deputy_arbiters $rest } }
            122 { set time_control_desc $rest }
            132 {
                if {[string length $line] > 89} {
                    set round_dates {}
                    for {set pos 89} {$pos < [string length $line]} {incr pos 10} {
                        set tok [string trim [string range $line $pos [expr {$pos + 9}]]]
                        if {$tok ne ""} { lappend round_dates $tok }
                    }
                } elseif {$rest ne ""} {
                    set round_dates [regexp -all -inline {\S+} $rest]
                }
            }
            142 { set format trf26; if {[string is integer -strict $rest]} { set rounds $rest } }
            152 { set format trf26; set colour_lot [expr {[string toupper [string index $rest 0]] eq "B" ? "black" : "white"}] }
            202 { set format trf26; set trf_tiebreaks_202 $rest }
            212 { set format trf26; set trf_tiebreaks $rest }
            222 { set format trf26; set encoded_time_control $rest }
            XXR { if {[string is integer -strict $rest]} { set rounds $rest } }
            XXC { set colour_lot [expr {[string match -nocase "black*" $rest] ? "black" : "white"}] }
            001 { lappend playerLines $line }
        }
    }
    if {![llength $playerLines]} { error "TRF contains no 001 player records" }
    set players {}
    set matchTable [dict create]
    set maxRound 0
    foreach line $playerLines {
        set n [scan [string trim [string range $line 4 7]] %d]
        if {$n eq "" || $n < 1} { error "invalid TRF player number in '$line'" }
        set sex [string trim [string index $line 9]]
        set title [NormalizeTitle [string range $line 10 12]]
        set pname [string trim [string range $line 14 46]]
        if {$pname eq ""} { set pname "Player $n" }
        set ratingRaw [string trim [string range $line 48 51]]
        set rating [expr {[string is integer -strict $ratingRaw] && $ratingRaw > 0 ? $ratingRaw : ""}]
        set fed [string trim [string range $line 53 55]]
        set fideId [string trim [string range $line 57 67]]
        set born [string trim [string range $line 69 78]]
        set pid p$n
        lappend players [dict create id $pid number $n name $pname kind human engine {} rating $rating \
            fide_id $fideId federation $fed title $title sex $sex born $born withdrawn 0 entry_round 1]
        set tail [string range $line 89 end]
        set r 0
        for {set pos 0} {$pos + 10 <= [string length $tail]} {incr pos 10} {
            incr r
            set token [string range $tail $pos [expr {$pos + 9}]]
            dict set matchTable $n $r $token
        }
        if {$r > $maxRound} { set maxRound $r }
    }
    set players [lmap item [lsort -integer -index 0 [lmap p $players {list [dict get $p number] $p}]] {lindex $item 1}]
    if {$rounds <= 0} { set rounds $maxRound }
    set limit [expr {$through > 0 ? min($through, $maxRound) : $maxRound}]
    set pairings {}
    for {set r 1} {$r <= $limit} {incr r} {
        set seen [dict create]
        set board 0
        foreach p $players {
            set n [dict get $p number]
            set pid [dict get $p id]
            if {[dict exists $seen $n]} { continue }
            set token [dg [dg $matchTable $n {}] $r "          "]
            if {[string trim $token] eq ""} { continue }
            set oppRaw [string trim [string range $token 0 5]]
            set colRaw [string trim [string index $token 7]]
            set resRaw [string trim [string index $token 9]]
            if {$oppRaw eq "" || $oppRaw eq "0000" || $oppRaw eq "0"} {
                if {$resRaw in {H F U Z -}} {
                    set cat [expr {$resRaw eq "U" ? "pairing-bye" : $resRaw eq "F" ? "full-point-bye" : $resRaw eq "H" ? "requested-bye" : "zero-point-bye"}]
                    set pts [expr {$resRaw in {F U} ? 2 : $resRaw eq "H" ? 1 : 0}]
                    set bId [expr {$cat eq "pairing-bye" ? "r${r}b${board}" : "bye-$pid-r$r-[llength $pairings]"}]
                    lappend pairings [dict create id $bId round $r board [expr {$cat eq "pairing-bye" ? $board : 0}] \
                        white $pid black {} result * status complete category $cat played 0 count_standings 1 rating 0 points $pts attempt 0 game_id {} pgn {} result_history {}]
                    if {$cat eq "pairing-bye"} { incr board }
                }
                dict set seen $n 1
                continue
            }
            if {![string is integer -strict $oppRaw]} { continue }
            set opp [scan $oppRaw %d]
            if {$opp == $n} { continue }
            dict set seen $n 1
            dict set seen $opp 1
            set white [expr {$colRaw eq "b" ? "p$opp" : $pid}]
            set black [expr {$colRaw eq "b" ? $pid : "p$opp"}]
            set played [expr {$resRaw ni {+ -}}]
            set category [expr {$played ? "played" : "forfeit"}]
            if {$colRaw eq "b"} {
                set result [expr {$resRaw in {1 +} ? "0-1" : $resRaw in {0 -} ? "1-0" : $resRaw eq "=" ? "1/2-1/2" : "*"}]
            } else {
                set result [expr {$resRaw in {1 +} ? "1-0" : $resRaw in {0 -} ? "0-1" : $resRaw eq "=" ? "1/2-1/2" : "*"}]
            }
            set oppToken [dg [dg $matchTable $opp {}] $r "          "]
            set oppRes [string trim [string index $oppToken 9]]
            if {$resRaw eq "-" && $oppRes eq "-"} {
                set result 0-0
                set category double-forfeit
                set played 0
            }
            lappend pairings [dict create id r${r}b${board} round $r board $board white $white black $black \
                result $result status [expr {$result eq "*" && $category ne "double-forfeit" ? "pending" : "complete"}] \
                category $category played $played termination [expr {$played ? "normal" : "abandoned"}] \
                count_standings 1 rating $played attempt 0 game_id {} pgn {} result_history {}]
            incr board
        }
    }
    return [dict create name $name site $site federation $federation start_date $start_date end_date $end_date \
        reported_players $reported_players reported_rated_players $reported_rated_players teams_count $teams_count \
        tournament_type $tournament_type chief_arbiter $chief_arbiter deputy_arbiters $deputy_arbiters \
        time_control_desc $time_control_desc round_dates $round_dates trf_tiebreaks $trf_tiebreaks \
        trf_tiebreaks_202 $trf_tiebreaks_202 encoded_time_control $encoded_time_control \
        rounds $rounds current_round [expr {max(1, $limit)}] colour_lot $colour_lot \
        trf_format $format players $players pairings $pairings]
}

proc ::td::trf::ValidateEligibility {state} {
    set reasons {}
    foreach p [dg $state players {}] {
        if {[dg $p kind human] ne "human"} {
            lappend reasons "non-human seat '[dict get $p name]' ([dg $p kind human]); mixed or engine events are never FIDE-rated"
        }
    }
    if {[dg $state rounds 0] < 1} { lappend reasons "tournament has no scheduled rounds" }
    return [dict create fide_eligible [expr {[llength $reasons] == 0}] reasons $reasons]
}
