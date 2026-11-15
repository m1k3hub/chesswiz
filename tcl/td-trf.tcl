# FIDE TRF edge adapter; the journal remains the canonical event store.
if {[llength [info commands ::util::source]]} { ::util::source td-trf }
namespace eval ::td::trf {}
proc ::td::trf::dg {d k {fallback {}}} { if {[dict exists $d $k]} { return [dict get $d $k] }; return $fallback }
proc ::td::trf::Field {text width} {
    if {[regexp {[\r\n\t\x00]} $text] || [string length $text] > $width} { error "TRF field exceeds $width columns or contains control characters: $text" }
    return [format %-*s $width $text]
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
    set lines [list "012 [Field [dict get $state name] 80]"]
    foreach {code key} {022 site 032 federation 042 start_date 052 end_date 102 chief_arbiter} {
        if {[dg $state $key] ne ""} { lappend lines "$code [Field [dict get $state $key] 80]" }
    }
    set rounds [dict get $state rounds]
    set colour [dg $state colour_lot white]
    if {$format eq "trf26"} { lappend lines "142 $rounds" "152 [string toupper [string index $colour 0]]" } else { lappend lines "XXR $rounds" "XXC ${colour}1" }
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
        set title [string tolower [dg $player title]]
        set title [string map {wgm wg wim wi wfm wf wcm wc gm g im m fm f cm c} $title]
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
    set chief_arbiter {}
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
            102 { set chief_arbiter $rest }
            142 { set format trf26; if {[string is integer -strict $rest]} { set rounds $rest } }
            152 { set format trf26; set colour_lot [expr {[string toupper [string index $rest 0]] eq "B" ? "black" : "white"}] }
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
        set titleRaw [string tolower [string trim [string range $line 10 12]]]
        set title [dict get [dict merge [dict create $titleRaw [string toupper $titleRaw]] {g GM m IM f FM c CM wg WGM wi WIM wf WFM wc WCM {} {}}] $titleRaw]
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
        chief_arbiter $chief_arbiter rounds $rounds current_round [expr {max(1, $limit)}] colour_lot $colour_lot \
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
