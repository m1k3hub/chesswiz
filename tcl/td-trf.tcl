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
proc ::td::trf::Write {state {format trf26} {through 0} {pairingRound 0} {checkPending 0}} {
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
    if {$through} { set last $through }
    set numbers {}
    foreach player [dict get $state players] { dict set numbers [dict get $player id] [dict get $player number] }
    set rank 0
    foreach player [dict get $state players] {
        set id [dict get $player id]
        set n [dict get $player number]
        if {$n < 1 || $n > 9999} { error "TRF pairing number out of range" }
        set matches {}; set score2 0
        for {set r 1} {$r <= max($last,$pairingRound)} {incr r} {
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
                if {$excluded || $late} { append matches "  0000 - Z" } else { append matches "          " }
                continue
            }
            set code [Code $found $id]
            if {$code eq " " && $checkPending && [dict get $found black] ne ""} { set code = }
            set other [expr {$id eq [dict get $found white] ? [dict get $found black] : [dict get $found white]}]
            set no [expr {$other eq "" ? 0 : [dict get $numbers $other]}]
            set c [expr {$other eq "" ? "-" : $id eq [dict get $found white] ? "w" : "b"}]
            append matches [format "  %04d %s %s" $no $c $code]
            # FIDE report preserves played results annulled only for RR standings.
            if {$code in {1 + F U}} { incr score2 2 } elseif {$code in {= H}} { incr score2 }
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
