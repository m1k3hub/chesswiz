# Registration copies local FIDE data into the event; never downloads a list.
if {[llength [info commands ::util::source]]} { ::util::source td-registration }
namespace eval ::td::registration {}
proc ::td::registration::Lookup {arguments} {
    set id [::td::model::dg $arguments fide_id {}]
    set name [::td::model::dg $arguments name {}]
    if {$id ne ""} {
        if {![string is integer -strict $id] || $id <= 0} { error "invalid FIDE ID" }
        set row [::scidb::player::lookup -fide $id]
    } else {
        if {[string trim $name] eq ""} { error "supply a FIDE ID or exact name" }
        set row [::scidb::player::lookup -name $name]
    }
    if {$row eq ""} { error "player not found in the installed rating list" }
    return [dict create name [dict get $row name] fide_id [dict get $row fideID] rating [dict get $row elo] \
        federation [dict get $row federation] title [lindex [dict get $row titles] 0] \
        sex [::td::model::dg $row sex] born [::td::model::dg $row born] \
        rating_source {installed FIDE player data} rating_snapshot [clock seconds]]
}
proc ::td::registration::Add {state domain {fide 0} {info {}}} {
    set swiss [expr {[dict get $state system] eq "swiss"}]
    if {[dict get $state status] eq "finished" || (!$swiss && [llength [dict get $state pairings]])} { error "registration is closed" }
    set entry 1
    if {$swiss} {
        foreach p [dict get $state pairings] {
            if {[dict get $p black] ne "" || [::td::model::dg $p category {}] eq "pairing-bye"} {
                set entry [expr {max($entry, [dict get $p round] + 1)}]
            }
        }
        set reqEntry [::td::model::dg $domain entry_round 0]
        if {$reqEntry ne "" && $reqEntry != 0} {
            if {![string is integer -strict $reqEntry] || $reqEntry < 1} {
                error "entry_round must be a positive round number"
            }
            if {$reqEntry < $entry} {
                error "late entry cannot enter in round $reqEntry; earliest unpaired round is $entry"
            }
            if {$reqEntry > [dict get $state rounds]} {
                error "entry_round $reqEntry exceeds scheduled rounds ([dict get $state rounds])"
            }
            set entry $reqEntry
        }
        if {$entry > [dict get $state rounds]} { error "no rounds remain for a late entry" }
    }
    set start [expr {[llength [dict get $state players]]+1}]
    if {$fide} {
        if {[dict exists $info recorded_result players] && [llength [dict get $info recorded_result players]] == 1} {
            set row [lindex [dict get $info recorded_result players] 0]
        } else {
            set row [Lookup $domain]
        }
        foreach existing [dict get $state players] {
            if {[dict get $existing fide_id] eq [dict get $row fide_id]} { error "FIDE player is already registered" }
        }
        set players [::td::model::MakePlayers [list [dict get $row name]] human $start]
        set players [list [dict merge [lindex $players 0] $row]]
    } else {
        set kind [::td::model::dg $domain kind human]
        if {$swiss && $kind ne "human"} { error "P2 Swiss requires human players" }
        set players [::td::model::MakePlayers [::td::model::dg $domain players {}] $kind $start]
        if {[llength $players] == 1} {
            set p0 [lindex $players 0]
            set rtg [::td::model::dg $domain rating 0]
            if {[string is integer -strict $rtg] && $rtg > 0} { dict set p0 rating $rtg }
            foreach k {fide_id federation title sex born} {
                if {[::td::model::dg $domain $k {}] ne ""} { dict set p0 $k [dict get $domain $k] }
            }
            set players [list $p0]
        }
    }
    set added {}
    foreach p $players { dict set p entry_round $entry; lappend added $p }
    dict lappend state players {*}$added
    if {!$swiss} { dict set state rounds [::td::model::Rounds [llength [dict get $state players]] [::td::model::Double [dict get $state system]]] }
    return [list $state [dict create registered [llength $added] entry_round $entry players $added] {} 1]
}
