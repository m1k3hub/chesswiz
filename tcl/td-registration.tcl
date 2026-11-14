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
proc ::td::registration::Add {state domain {fide 0}} {
    set swiss [expr {[dict get $state system] eq "swiss"}]
    if {[dict get $state status] eq "finished" || (!$swiss && [llength [dict get $state pairings]])} { error "registration is closed" }
    set entry 1
    if {$swiss} {
        foreach p [dict get $state pairings] { set entry [expr {max($entry,[dict get $p round]+1)}] }
        if {$entry > [dict get $state rounds]} { error "no rounds remain for a late entry" }
    }
    set start [expr {[llength [dict get $state players]]+1}]
    if {$fide} {
        set row [Lookup $domain]
        foreach existing [dict get $state players] {
            if {[dict get $existing fide_id] eq [dict get $row fide_id]} { error "FIDE player is already registered" }
        }
        set players [::td::model::MakePlayers [list [dict get $row name]] human $start]
        set players [list [dict merge [lindex $players 0] $row]]
    } else {
        set kind [::td::model::dg $domain kind human]
        if {$swiss && $kind ne "human"} { error "P2 Swiss requires human players" }
        set players [::td::model::MakePlayers [::td::model::dg $domain players {}] $kind $start]
    }
    set added {}
    foreach p $players { dict set p entry_round $entry; lappend added $p }
    dict lappend state players {*}$added
    if {!$swiss} { dict set state rounds [::td::model::Rounds [llength [dict get $state players]] [::td::model::Double [dict get $state system]]] }
    return [list $state [dict create registered [llength $added] entry_round $entry players $added] {} 1]
}
