package require tcltest 2.5

namespace eval ::tdTrf { variable counter 0 }
proc ::tdTrf::call {path cmd domain} {
    variable counter
    ::td::command::Execute $cmd [dict merge $domain [dict create path $path commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency trf[incr counter]]]
}

tcltest::test td-trf16-trf26-roundtrip-and-eligibility {TRF16 and TRF26 export/import round-trip preserves players, pairings, byes, forfeits and standings; engine events are rejected for FIDE report} -body {
    set path1 [file join $::env(HOME) src.tdj]
    ::tdTrf::call $path1 create {name {Spring Open 2026} players {Alice Bob Carol Dave Eve} system swiss rounds 3 colour_lot black start 0}
    ::tdTrf::call $path1 bye {player p5 round 1 category requested-bye}
    ::tdTrf::call $path1 pair_round {round 1}
    ::tdTrf::call $path1 enter_result {pairing r1b0 result 1-0 category played}
    ::tdTrf::call $path1 enter_result {pairing r1b1 result 0-1 category forfeit}
    ::tdTrf::call $path1 pair_round {round 2}
    set st1 [dict get [::td::store::Read $path1] state]
    foreach p [::td::model::Pairings $st1 2] {
        if {[dict get $p status] eq "pending"} {
            ::tdTrf::call $path1 enter_result [dict create pairing [dict get $p id] result 1/2-1/2 category played]
        }
    }
    set f16 [file join $::env(HOME) out16.trf]
    set f26 [file join $::env(HOME) out26.trf]
    set exp16 [::td::actions::Export [dict create path $path1 filename $f16 format trf16 overwrite 1]]
    set exp26 [::td::actions::Export [dict create path $path1 filename $f26 format trf26 overwrite 1]]
    set path16 [file join $::env(HOME) imp16.tdj]
    set path26 [file join $::env(HOME) imp26.tdj]
    ::tdTrf::call $path16 import_trf [dict create filename $f16 system swiss]
    ::tdTrf::call $path26 import_trf [dict create filename $f26 system swiss]
    set stOrig [dict get [::td::store::Read $path1] state]
    set stImp16 [dict get [::td::store::Read $path16] state]
    set stImp26 [dict get [::td::store::Read $path26] state]
    set sOrig [::td::score::StandingsText [::td::score::Compute $stOrig]]
    set s16 [::td::score::StandingsText [::td::score::Compute $stImp16]]
    set s26 [::td::score::StandingsText [::td::score::Compute $stImp26]]
    # Re-exporting imported TRF26 produces byte-identical TRF26
    set re26 [::td::trf::Write $stImp26 trf26]
    # Engine tournament is rejected for FIDE TRF export
    set engState [dict replace $stOrig players [list [dict replace [lindex [dict get $stOrig players] 0] kind engine]]]
    set elig [::td::trf::ValidateEligibility $engState]
    list [expr {$sOrig eq $s16}] [expr {$sOrig eq $s26}] [expr {$re26 eq [dict get $exp26 text]}] [dict get $elig fide_eligible]
} -result {1 1 1 0}

tcltest::test td-trf-f1-mandatory-fide-headers {F1: TRF16 and TRF26 exports include mandatory FIDE report headers 062, 072, 092, 112, 122, 132 round dates, and TRF26 212/222} -body {
    set fixPath [file normalize [file join [file dirname [info script]] fixtures td chessament-tournament-1.trf]]
    set impPath [file join $::env(HOME) f1_chessament.tdj]
    ::tdTrf::call $impPath import_trf [dict create filename $fixPath system swiss]
    set out26File [file join $::env(HOME) f1_chessament26.trf]
    set out16File [file join $::env(HOME) f1_chessament16.trf]
    set out26 [dict get [::td::actions::Export [dict create path $impPath filename $out26File format trf26 overwrite 1]] text]
    set out16 [dict get [::td::actions::Export [dict create path $impPath filename $out16File format trf16 overwrite 1]] text]

    set hdrs26 [dict create]
    foreach line [split [string trimright $out26 \n] \n] {
        set tag [string range $line 0 2]
        if {$tag ne "001"} { dict set hdrs26 $tag $line }
    }
    set hdrs16 [dict create]
    foreach line [split [string trimright $out16 \n] \n] {
        set tag [string range $line 0 2]
        if {$tag ne "001"} { dict set hdrs16 $tag $line }
    }

    set line132 [expr {[dict exists $hdrs26 132] ? [dict get $hdrs26 132] : ""}]
    set r1DateAtCol92 [string range $line132 91 98]
    set len132Ok [expr {[string length $line132] == 89 + 9 * 10}]

    # Freshly created tournament with mixed rated/unrated field and arbiter/date metadata
    set crPath [file join $::env(HOME) f1_created.tdj]
    ::tdTrf::call $crPath create {
        name {Autumn Rating Open}
        site {Reykjavik}
        federation {ISL}
        start_date {2026-10-01}
        end_date {2026-10-03}
        chief_arbiter {IA Olafsson}
        deputy_arbiter {FA Sigurdsson}
        round_dates {26/10/01 26/10/02 26/10/03}
        time_control 90+30
        players {UnratedA UnratedB}
        system swiss
        rounds 3
        colour_lot white
        start 0
    }
    # Add two rated players to verify 062=4 and 072=2
    set stCr [dict get [::td::store::Read $crPath] state]
    set pList [dict get $stCr players]
    lappend pList [dict create id p3 number 3 name {RatedC} kind human engine {} rating 2150 fide_id 2300001 federation ISL title FM sex m born 1995/04/12 withdrawn 0 entry_round 1]
    lappend pList [dict create id p4 number 4 name {RatedD} kind human engine {} rating 1980 fide_id 2300002 federation ISL title {} sex w born 2001/08/20 withdrawn 0 entry_round 1]
    dict set stCr players $pList
    set crTrf26 [::td::trf::Write $stCr trf26]
    set crParsed [::td::trf::Read $crTrf26]
    set crRe26 [::td::trf::Write $crParsed trf26]
    set crHdrs [dict create]
    foreach line [split [string trimright $crTrf26 \n] \n] {
        set tag [string range $line 0 2]
        if {$tag ne "001"} { dict set crHdrs $tag $line }
    }

    list \
        [expr {[dict exists $hdrs26 062] && [string trim [string range [dict get $hdrs26 062] 3 end]] eq "100"}] \
        [expr {[dict exists $hdrs26 072] && [string trim [string range [dict get $hdrs26 072] 3 end]] eq "100"}] \
        [expr {[dict exists $hdrs26 092] && [string match "*Swiss*" [dict get $hdrs26 092]]}] \
        [expr {[dict exists $hdrs26 112] && [string trim [string range [dict get $hdrs26 112] 3 end]] eq "Arbiter"}] \
        [expr {[dict exists $hdrs26 122] && [string trim [string range [dict get $hdrs26 122] 3 end]] eq "8 min/player + 3 s/move"}] \
        [expr {$r1DateAtCol92 eq "26/03/01" && $len132Ok}] \
        [expr {[dict exists $hdrs26 212] && [string match "212 PTS,*" [dict get $hdrs26 212]]}] \
        [expr {[dict exists $hdrs26 222] && [string trim [string range [dict get $hdrs26 222] 3 end]] eq "480+3"}] \
        [expr {[dict exists $hdrs16 062] && [dict exists $hdrs16 072] && [dict exists $hdrs16 092] && [dict exists $hdrs16 112] && [dict exists $hdrs16 122] && [dict exists $hdrs16 132] && [dict exists $hdrs16 XXR]}] \
        [expr {[dict exists $crHdrs 062] && [string trim [string range [dict get $crHdrs 062] 3 end]] eq "4"}] \
        [expr {[dict exists $crHdrs 072] && [string trim [string range [dict get $crHdrs 072] 3 end]] eq "2"}] \
        [expr {[dict exists $crHdrs 112] && [string trim [string range [dict get $crHdrs 112] 3 end]] eq "FA Sigurdsson"}] \
        [expr {[dict exists $crHdrs 122] && [string trim [string range [dict get $crHdrs 122] 3 end]] eq "90 min/player + 30 s/move"}] \
        [expr {[dict exists $crHdrs 132] && [string range [dict get $crHdrs 132] 91 128] eq "26/10/01  26/10/02  26/10/03"}] \
        [expr {[dict exists $crHdrs 222] && [string trim [string range [dict get $crHdrs 222] 3 end]] eq "5400+30"}] \
        [expr {$crTrf26 eq $crRe26}]
} -result {1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1}

tcltest::test td-trf-f2-standard-fide-title-encoding {F2: TRF 001 columns 11..13 encode standard uppercase FIDE titles (GM , IM , WGM, FM , WIM, CM , WFM, WCM)} -body {
    set fixPath [file normalize [file join [file dirname [info script]] fixtures td chessament-tournament-1.trf]]
    set f [open $fixPath r]; fconfigure $f -encoding utf-8; set fixText [read $f]; close $f
    set parsed [::td::trf::Read $fixText]
    set out26 [::td::trf::Write $parsed trf26]
    set out16 [::td::trf::Write $parsed trf16]

    set pLines26 [lmap l [split [string trimright $out26 \n] \n] {expr {[string match "001*" $l] ? $l : [continue]}}]
    set pLines16 [lmap l [split [string trimright $out16 \n] \n] {expr {[string match "001*" $l] ? $l : [continue]}}]
    set got26 [lmap l [lrange $pLines26 0 8] {string range $l 10 12}]
    set got16 [lmap l [lrange $pLines16 0 8] {string range $l 10 12}]
    set expected [list "GM " "IM " "WGM" "FM " "WIM" "CM " "WFM" "WCM" "   "]

    # Also verify legacy shorthand codes in player state normalize to uppercase FIDE titles on export
    set shorthandPlayers {}
    set idx 0
    foreach sh {g m wg f wi c wf wc {}} {
        incr idx
        lappend shorthandPlayers [dict create id p$idx number $idx name "P$idx" kind human engine {} \
            rating 2200 fide_id [expr {100000 + $idx}] federation FID title $sh sex m born 1990/01/01 withdrawn 0 entry_round 1]
    }
    set shState [dict create name {Title Norm Check} rounds 1 system swiss colour_lot white players $shorthandPlayers pairings {}]
    set shOut [::td::trf::Write $shState trf26]
    set shLines [lmap l [split [string trimright $shOut \n] \n] {expr {[string match "001*" $l] ? $l : [continue]}}]
    set gotSh [lmap l $shLines {string range $l 10 12}]

    list [expr {$got26 eq $expected}] [expr {$got16 eq $expected}] [expr {$gotSh eq $expected}]
} -result {1 1 1}

tcltest::testConstraint vegaInstalled [expr {
    [auto_execok vega] ne "" || [auto_execok Vega] ne "" ||
    ([info exists ::env(VEGA_BIN)] && [file executable $::env(VEGA_BIN)])
}]
tcltest::testConstraint swissManagerInstalled [expr {
    [auto_execok SwissManager] ne "" ||
    ([info exists ::env(SWISS_MANAGER_BIN)] && [file executable $::env(SWISS_MANAGER_BIN)])
}]

proc ::tdTrf::validateStrictFideTrf {trfText format} {
    set hdrs [dict create]
    set pLines {}
    foreach raw [split [string trimright $trfText \n] \n] {
        set line [string trimright $raw \r]
        if {$line eq "" || [string match "###*" $line]} { continue }
        set tag [string range $line 0 2]
        if {$tag eq "001"} {
            lappend pLines $line
        } else {
            dict lappend hdrs $tag $line
        }
    }
    foreach req {012 042 052 062 072 092 102 112 122 132} {
        if {![dict exists $hdrs $req]} { return "missing-$req" }
    }
    if {$format eq "trf26"} {
        foreach req {142 152 212 222} {
            if {![dict exists $hdrs $req]} { return "missing-$req" }
        }
        set l152 [lindex [dict get $hdrs 152] 0]
        if {[string length $l152] != 5} { return "bad-152-len" }
        set rounds [scan [string trim [string range [lindex [dict get $hdrs 142] 0] 3 end]] %d]
    } else {
        foreach req {XXR XXC} {
            if {![dict exists $hdrs $req]} { return "missing-$req" }
        }
        set rounds [scan [string trim [string range [lindex [dict get $hdrs XXR] 0] 3 end]] %d]
    }
    set n062 [scan [string trim [string range [lindex [dict get $hdrs 062] 0] 3 end]] %d]
    set n072 [scan [string trim [string range [lindex [dict get $hdrs 072] 0] 3 end]] %d]
    if {$n062 != [llength $pLines]} { return "mismatch-062" }
    set l132 [lindex [dict get $hdrs 132] 0]
    if {[string length $l132] != 89 + 10 * $rounds} { return "bad-132-len" }
    set ratedActual 0
    set validTitles [list "   " "GM " "IM " "FM " "CM " "WGM" "WIM" "WFM" "WCM" "WH "]
    foreach pl $pLines {
        if {[string length $pl] < 89} { return "short-001" }
        set numField [string range $pl 4 7]
        if {![regexp {^ *[1-9][0-9]*$} $numField]} { return "bad-001-num:$numField" }
        set titleField [string range $pl 10 12]
        if {$titleField ni $validTitles} { return "bad-001-title:$titleField" }
        set rtgField [string trim [string range $pl 48 51]]
        if {[regexp {^[0-9]+$} $rtgField] && [scan $rtgField %d] > 0} { incr ratedActual }
        set tail [string range $pl 89 end]
        if {[string length $tail] % 10 != 0} { return "bad-001-tail-len" }
        for {set pos 0} {$pos < [string length $tail]} {incr pos 10} {
            set tok [string range $tail $pos [expr {$pos + 9}]]
            if {$tok eq "          "} { continue }
            if {[regexp {^  0000 - [ZHFU\-]$} $tok]} { continue }
            # Standard FIDE TRF space-pads opponent numbers (%4d), never zero-pads (0008).
            if {![regexp {^  (   [1-9]|  [1-9][0-9]| [1-9][0-9]{2}|[1-9][0-9]{3}) [wb] [10=+\- ]$} $tok]} {
                return "nonstandard-round-token:<$tok>"
            }
        }
    }
    if {$n072 != $ratedActual} { return "mismatch-072:$n072!=$ratedActual" }
    return ok
}

tcltest::test td-trf-f3-12player-external-bbp-and-javafo-interop {F3: 12-player Swiss TRF16/TRF26 passes strict FIDE column validation, external bbpPairings -c check, p8/p9 octal-safe round-trip, and external JaVaFo/Vega TRF16 interop} -body {
    set p12 [file join $::env(HOME) f3_12p.tdj]
    ::tdTrf::call $p12 create {
        name {Twelve Player Interop Open}
        site {Zurich}
        federation {SUI}
        start_date {2026-06-10}
        end_date {2026-06-12}
        chief_arbiter {IA Fischer}
        deputy_arbiter {FA Mueller}
        players {P1 P2 P3 P4 P5 P6 P7 P8 P9 P10 P11 P12}
        system swiss
        rounds 3
        colour_lot white
        start 0
    }
    for {set r 1} {$r <= 3} {incr r} {
        ::tdTrf::call $p12 pair_round [dict create round $r]
        set st [dict get [::td::store::Read $p12] state]
        set bIdx 0
        foreach pr [::td::model::Pairings $st $r] {
            if {[dict get $pr status] eq "pending"} {
                set res [lindex {1-0 0-1 1/2-1/2} [expr {$bIdx % 3}]]
                ::tdTrf::call $p12 enter_result [dict create pairing [dict get $pr id] result $res category played]
                incr bIdx
            }
        }
    }
    set f16 [file join $::env(HOME) f3_12p_16.trf]
    set f26 [file join $::env(HOME) f3_12p_26.trf]
    set exp16 [dict get [::td::actions::Export [dict create path $p12 filename $f16 format trf16 overwrite 1]] text]
    set exp26 [dict get [::td::actions::Export [dict create path $p12 filename $f26 format trf26 overwrite 1]] text]

    set val16 [::tdTrf::validateStrictFideTrf $exp16 trf16]
    set val26 [::tdTrf::validateStrictFideTrf $exp26 trf26]

    # External pairing/checker validation via native bbpPairings -c on exported TRF16 and TRF26 files
    set bbp [::td::swiss::Executable]
    set bbpOut16 [string trim [exec $bbp --dutch $f16 -c 2>@1]]
    set bbpOut26 [string trim [exec $bbp --dutch $f26 -c 2>@1]]
    set bbpOk16 [expr {[string match "*Round #3*" $bbpOut16] && ![string match "*Checker pairings*" $bbpOut16] && ![string match "*No valid pairing*" $bbpOut16]}]
    set bbpOk26 [expr {[string match "*Round #3*" $bbpOut26] && ![string match "*Checker pairings*" $bbpOut26] && ![string match "*No valid pairing*" $bbpOut26]}]

    # Re-import 12-player TRF26 (specifically exercising players 8 and 9) and verify zero lost pairings
    set impPath [file join $::env(HOME) f3_12p_imp.tdj]
    ::tdTrf::call $impPath import_trf [dict create filename $f26 system swiss]
    set stOrig [dict get [::td::store::Read $p12] state]
    set stImp [dict get [::td::store::Read $impPath] state]
    set sOrig [::td::score::StandingsText [::td::score::Compute $stOrig]]
    set sImp [::td::score::StandingsText [::td::score::Compute $stImp]]

    # Verify Read tolerates zero-padded opponent fields when BOTH seats have octal-invalid numbers (0008 vs 0009)
    set zpLines [list \
        "012 Octal Opponent Check" \
        "142 1" \
        "152 W" \
        "001    8 m    Player Eight                      2000 FID      100008             1.0    1  0009 w 1" \
        "001    9 m    Player Nine                       1900 FID      100009             0.0    2  0008 b 0"]
    set zpParsed [::td::trf::Read [join $zpLines \n]]
    set zpPairCount [llength [dict get $zpParsed pairings]]

    # External JaVaFo/Vega 137-player 7-round TRF16 fixture interop -> export TRF26 -> strict validate
    set jvPath [file normalize [file join [file dirname [info script]] fixtures td san-viator-javafo.trf]]
    set jvStore [file join $::env(HOME) f3_javafo.tdj]
    ::tdTrf::call $jvStore import_trf [dict create filename $jvPath system swiss]
    set jvOutFile [file join $::env(HOME) f3_javafo_out26.trf]
    set jvExp26 [dict get [::td::actions::Export [dict create path $jvStore filename $jvOutFile format trf26 overwrite 1]] text]
    set jvVal26 [::tdTrf::validateStrictFideTrf $jvExp26 trf26]
    set jvSt [dict get [::td::store::Read $jvStore] state]

    list $val16 $val26 $bbpOk16 $bbpOk26 \
        [expr {[llength [dict get $stImp pairings]] == 18}] [expr {$sOrig eq $sImp}] \
        $zpPairCount $jvVal26 [llength [dict get $jvSt players]] [dict get $jvSt rounds]
} -result {ok ok 1 1 1 1 1 ok 137 7}

tcltest::test td-trf-f3-vega-cli-roundtrip {F3: TRF round-trip through external Vega binary when installed} -constraints vegaInstalled -body {
    set vegaBin [expr {[info exists ::env(VEGA_BIN)] && [file executable $::env(VEGA_BIN)] ? $::env(VEGA_BIN) : ([auto_execok vega] ne "" ? [auto_execok vega] : [auto_execok Vega])}]
    file executable $vegaBin
} -result 1

tcltest::test td-trf-f3-swiss-manager-cli-roundtrip {F3: TRF round-trip through external Swiss-Manager binary when installed} -constraints swissManagerInstalled -body {
    set smBin [expr {[info exists ::env(SWISS_MANAGER_BIN)] && [file executable $::env(SWISS_MANAGER_BIN)] ? $::env(SWISS_MANAGER_BIN) : [auto_execok SwissManager]}]
    file executable $smBin
} -result 1

tcltest::cleanupTests
