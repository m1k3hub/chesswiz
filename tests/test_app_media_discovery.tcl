# Real assistant dispatch over a generated SCI/SCM and a Tk-generated image.
# No private database, media model, action handler or renderer is substituted.
package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::mediaDiscoveryProbe {
    variable dir [file join /tmp chesswiz-media-discovery-[pid]]
}
proc ::mediaDiscoveryProbe::nop {args} {return 0}
# Native SCM fingerprints use the numeric result enum, not PGN result text.
# db::result::Unknown == 0 (db_common.h:319); mediaFiles casts info.result().
# PGN * therefore hashes as 0. Original probe hashed *, so lookup missed.
# Exact FNV-1a-64 companion fingerprint algorithm from permitted fixture builder.
proc ::mediaDiscoveryProbe::fingerprint {} {
    set h 0xcbf29ce484222325
    foreach ch [split {white|black|generated media probe|2026.01.01|1|0} {}] {
        scan $ch %c code
        set h [expr {(($h ^ $code) * 0x100000001b3) & 0xffffffffffffffff}]
    }
    return [format %016llx $h]
}
proc ::mediaDiscoveryProbe::fixture {{duplicate 0}} {
    variable dir
    file mkdir $dir
    set root [file join $dir generated]
    set pgn ${root}.pgn
    set f [open $pgn w]
    puts $f {[Event "Generated Media Probe"]
[Site "Generated"]
[Date "2026.01.01"]
[Round "1"]
[White "White"]
[Black "Black"]
[Result "*"]

1. e4 e5 *}
    close $f
    file mkdir ${root}.media
    set im [image create photo -width 24 -height 24]
    $im put #2c83c4 -to 0 0 24 24
    $im put #eeeeee -to 4 4 20 20
    $im write [file join ${root}.media generated.png] -format png
    image delete $im
    ::scidb::db::open $pgn ::mediaDiscoveryProbe::nop {} ::mediaDiscoveryProbe::nop {}
    set base ${root}.sci
    ::scidb::db::new $base Normal [::application::database::lookupType OpeningsWhite]
    ::scidb::db::attach $base $base
    ::scidb::db::copy $pgn $base {} ::mediaDiscoveryProbe::nop {} ::mediaDiscoveryProbe::nop {}
    ::scidb::db::save $base ::mediaDiscoveryProbe::nop {}
    ::scidb::db::close $pgn
    ::scidb::db::close $base
    set f [open ${root}.scm w]
    puts $f {[Database "Generated Media Probe"]
[MediaDir "generated.media"]
[Encoding "utf-8"]

[Media "M01"]
Type: picture
Path: generated.png
Title: "Generated square image"}
    if {$duplicate} {
        puts $f {
[Media "M02"]
Type: picture
Path: generated.png
Title: "Generated square image"}
    }
    puts $f "\n\[Game \"[fingerprint]\"\]\nMedia: [expr {$duplicate ? "M01, M02" : "M01"}]"
    close $f
    puts [list MEDIA_FIXTURE base $base fingerprint [fingerprint] image [file join ${root}.media generated.png]]
    return $base
}

proc ::mediaDiscoveryProbe::tool {id {cargs {}}} {
    set reply [::application::assistant::runTool $id $cargs]
    if {[string match error:* $reply]} { error $reply }
    return $reply
}
proc ::mediaDiscoveryProbe::setup {{duplicate 0}} {
    ::scidb::test::actions::ready
    set base [fixture $duplicate]
    tool open_database [dict create path $base]
    tool open_game {number 1}
    return $base
}
proc ::mediaDiscoveryProbe::cleanup {base} {
    catch {destroy .mediaPicture}
    set pos [::scidb::game::current]
    ::application::pgn::release $pos
    ::game::release $pos
    ::application::database::closeBase .application $base
    file delete -force $::mediaDiscoveryProbe::dir
}
tcltest::test media-discovery-title {public read discovers an attached title and assistant opens its real image} -setup {
    set base [::mediaDiscoveryProbe::setup]
} -body {
    # No UI/tree inspection or explicit backend update before the public calls.
    set reply [::mediaDiscoveryProbe::tool current_game]
    set entries {}
    foreach line [split $reply \n] {
        if {[string match {index *} $line]} { lappend entries $line }
    }
    set first [lindex $entries 0]
    set before [::scidb::pos::fen]
    set result [::mediaDiscoveryProbe::tool run_action [dict create id media.play_entry \
        arguments [dict create title [dict get $first title]]]]
    update
    puts [list MEDIA_PUBLIC_ENTRIES $entries REPLY $result]
    list [dict get $first index] [dict get $first title] \
        [winfo viewable .mediaPicture] [llength [.mediaPicture.canvas find all]] \
        [expr {$before eq [::scidb::pos::fen]}]
} -cleanup {
    ::mediaDiscoveryProbe::cleanup $base
} -result {1 {Generated square image} 1 1 1}

tcltest::test media-discovery-index {one-based index opens the image; repeated public reads preserve selection} -setup {
    set base [::mediaDiscoveryProbe::setup]
} -body {
    ::mediaDiscoveryProbe::tool run_action {id media.play_entry arguments {index 1}}
    update
    set selected $::application::media::Priv(selectedRow)
    ::mediaDiscoveryProbe::tool current_game
    ::mediaDiscoveryProbe::tool current_game
    list [winfo viewable .mediaPicture] [llength [.mediaPicture.canvas find all]] \
        [expr {$selected ne "" && $selected eq $::application::media::Priv(selectedRow)}]
} -cleanup {
    ::mediaDiscoveryProbe::cleanup $base
} -result {1 1 1}

tcltest::test media-discovery-invalid {invalid, conflicting and missing selectors refuse without opening media} -setup {
    set base [::mediaDiscoveryProbe::setup]
} -body {
    set refused {}
    foreach args {{title Missing} {index 0} {index 2} {index -1} {index bad} {} {title {Generated square image} index 1} {row missing}} {
        set reply [::application::assistant::runTool run_action [dict create id media.play_entry arguments $args]]
        lappend refused [string match error:* $reply]
    }
    list $refused [winfo exists .mediaPicture]
} -cleanup {
    ::mediaDiscoveryProbe::cleanup $base
} -result {{1 1 1 1 1 1 1 1} 0}

tcltest::test media-discovery-duplicate {duplicate titles require an index; legacy UI rows still work} -setup {
    set base [::mediaDiscoveryProbe::setup 1]
} -body {
    set listing [::mediaDiscoveryProbe::tool current_game]
    set reply [::application::assistant::runTool run_action \
        {id media.play_entry arguments {title {Generated square image}}}]
    set refused [string match {error:*more than one*} $reply]
    set unopened [expr {![winfo exists .mediaPicture]}]
    ::mediaDiscoveryProbe::tool run_action {id media.play_entry arguments {index 2}}
    update
    set title [wm title .mediaPicture]
    set row $::application::media::Priv(selectedRow)
    destroy .mediaPicture
    ::mediaDiscoveryProbe::tool run_action [dict create id media.play_entry arguments [dict create row $row]]
    update
    list $refused $unopened [string match {*index 2 title*} $listing] $title [winfo viewable .mediaPicture]
} -cleanup {
    ::mediaDiscoveryProbe::cleanup $base
} -result {1 1 1 {Generated square image} 1}

tcltest::cleanupTests
