# Production inset chain; the player alone is stubbed, like media_fold.
package require tcltest 2.5
namespace eval ::paneVideo {variable saved {}; variable calls {}; variable began 0}
proc ::paneVideo::wait {ms} {after $ms {set ::paneVideo::tick 1}; vwait ::paneVideo::tick}
proc ::paneVideo::stub {name args body} {
 variable saved
 if {[llength [info commands ::media::mpv::$name]]} {rename ::media::mpv::$name ::paneVideo::saved_$name; lappend saved $name}
 proc ::media::mpv::$name $args $body
}
proc ::paneVideo::setup {} {
 .application.nb select .application.nb.board
 set ::application::twm::Options(board:layout:name) {}
 ::application::reflow::reset
 wm geometry .application 1200x780+0+0
 wait 450
 variable saved {}; variable calls {}; variable began [clock milliseconds]
 stub available? {} {return 1}
 stub launch {path wid {ms 0}} {lappend ::paneVideo::calls [list launch $path $wid]; return 1}
 stub state {} {return playing}
 stub duration {} {return 600}
 stub time {} {return [expr {([clock milliseconds]-$::paneVideo::began)/1000.0}]}
 stub stop {} {lappend ::paneVideo::calls stop}
 set ok [::application::media::PlayInProcess /generated-pane-video.mp4]
 wait 500
 if {!$ok} {error {production playback did not start}}
 return [::application::twm board]
}
proc ::paneVideo::cleanup {} {
 ::application::media::Stop
 foreach n $::paneVideo::saved {rename ::media::mpv::$n {}; rename ::paneVideo::saved_$n ::media::mpv::$n}
 set ::paneVideo::saved {}
 ::application::focuszoom::disable [::application::twm board]
 ::application::reflow::reset
}
proc ::paneVideo::rect {w} {return [list [winfo rootx $w] [winfo rooty $w] [winfo width $w] [winfo height $w]]}
proc ::paneVideo::geometry {tag} {
 set pane [::mediainset::Pane]; set c $::application::board::Vars(widget:frame)
 set w $pane.mediainset
 lassign [$c bbox board] x0 y0 x1 y1
 set bx [expr {[winfo rootx $c]+$x0}]; set by [expr {[winfo rooty $c]+$y0}]
 lassign [rect $w] vx vy vw vh
 set overlap [expr {max(0,min($bx+$x1-$x0,$vx+$vw)-max($bx,$vx))*max(0,min($by+$y1-$y0,$vy+$vh)-max($by,$vy))}]
 puts "PANE-VIDEO $tag board=[list $bx $by [expr {$x1-$x0}] [expr {$y1-$y0}]] inset=[rect $w] canvas=[rect $c] reserve=[::application::board::reserveRect] overlap=$overlap time=[::media::mpv::time]"
 if {[info exists ::env(PANE_EVIDENCE)]} {catch {exec import -window root [file join $::env(PANE_EVIDENCE) $tag.png]}}
 return $overlap
}

# Full overlap of the inset with the board plus its side-to-move and
# material decorations, the metric VAL-PANE-008 is stated in.
proc ::paneVideo::overlapAll {tag} {
 set c $::application::board::Vars(widget:frame)
 set w [::mediainset::Pane].mediainset
 set over [::paneVideo::geometry $tag]
 foreach tg {stm material} {
  set box [$c bbox $tg]
  if {[llength $box] != 4} {continue}
  lassign $box x y xx yy
  lassign [::paneVideo::rect $w] vx vy vw vh
  set rx [expr {$x+[winfo rootx $c]}]; set ry [expr {$y+[winfo rooty $c]}]
  incr over [expr {max(0,min($rx+$xx-$x,$vx+$vw)-max($rx,$vx))*max(0,min($ry+$yy-$y,$vy+$vh)-max($ry,$vy))}]
 }
 return $over
}
tcltest::test pane-video-008-reflow {inset native surface and playback survive actual wide/tall reflow with zero overlap} -setup {
 set t [::paneVideo::setup]
 set w [::mediainset::Pane].mediainset.video; set id [winfo id $w]
 set time [::media::mpv::time]
} -body {
 set result [list [::paneVideo::geometry wide]]
 wm geometry .application 740x780
 ::paneVideo::wait 650
 lappend result [::application::reflow::mode] [::paneVideo::geometry tall]
 wm geometry .application 1200x780
 ::paneVideo::wait 650
 lappend result [::application::reflow::mode] [::paneVideo::geometry wide-return]
 lappend result [expr {[winfo id $w] eq $id}] [expr {[::media::mpv::time] > $time}] [llength $::paneVideo::calls]
 set result
} -cleanup {::paneVideo::cleanup} -result {0 tall 0 wide 0 1 1 1}

tcltest::test pane-video-008-zoom-swap {click focus zoom, maximise and swapped resize all keep production inset playback and reserve} -setup {
 set t [::paneVideo::setup]
 set id [winfo id [::mediainset::Pane].mediainset.video]
} -body {
 set ::application::focuszoom::duration 150
 ::application::focuszoom::enable $t
 event generate [$t leaf board] <ButtonPress-1>
 ::paneVideo::wait 650
 set result [list [::paneVideo::geometry focus-zoom]]
 ::application::focuszoom::disable $t
 $t zoom [$t leaf board]
 ::paneVideo::wait 500
 lappend result [::paneVideo::geometry maximised]
 $t zoom {}
 ::paneVideo::wait 500
 ::mediainset::swap
 wm geometry .application 1120x750
 ::paneVideo::wait 650
 set p [::mediainset::Pane]; set c $::application::board::Vars(widget:frame); set w $p.mediainset
 set fills [expr {[winfo width $w] == [winfo width $p] && [winfo height $w] == [winfo height $p]}]
 set small [expr {[winfo ismapped $c] && [winfo width $c] < [winfo width $p]/2 && [winfo height $c] < [winfo height $p]/2}]
 if {[info exists ::env(PANE_EVIDENCE)]} {catch {exec import -window root [file join $::env(PANE_EVIDENCE) swapped.png]}}
 puts "PANE-VIDEO swapped pane=[::paneVideo::rect $p] inset=[::paneVideo::rect $w] small=[::paneVideo::rect $c] fills=$fills"
 ::mediainset::swap
 ::paneVideo::wait 650
 lappend result $fills $small [::paneVideo::geometry unswapped] [expr {[winfo id $w.video] eq $id}] [llength $::paneVideo::calls]
 set result
} -cleanup {::paneVideo::cleanup} -result {0 0 1 1 0 1 1}

tcltest::test pane-video-008-tall-strip {wide->tall->wide reflow keeps a real reserve strip: bottom on a tall canvas, right when wide, overlap 0 with board and decorations} -setup {
 set t [::paneVideo::setup]
 set c $::application::board::Vars(widget:frame)
 proc ::paneVideo::check {tag} {
  set c $::application::board::Vars(widget:frame); set w [::mediainset::Pane].mediainset
  set over [::paneVideo::geometry $tag]
  foreach tag {stm material} {
   set box [$c bbox $tag]
   if {[llength $box] != 4} {continue}
   lassign $box x y xx yy
   lassign [::paneVideo::rect $w] vx vy vw vh
   set rx [expr {$x+[winfo rootx $c]}]; set ry [expr {$y+[winfo rooty $c]}]
   incr over [expr {max(0,min($rx+$xx-$x,$vx+$vw)-max($rx,$vx))*max(0,min($ry+$yy-$y,$vy+$vh)-max($ry,$vy))}]
  }
  lassign [::application::board::reserveRect] rx ry rw rh
  set side $::application::board::ReserveSide
  set tallCanvas [expr {[winfo height $c] > 1.1*[winfo width $c]}]
  puts "PANE-VIDEO-STRIP mode=[::application::reflow::mode] side=$side canvas=[winfo width $c]x[winfo height $c] tallCanvas=$tallCanvas"
  list $over [expr {$rw*$rh > 0 && [winfo ismapped $w]}] [expr {$side eq "bottom" || !$tallCanvas}]
 }
} -body {
 set sw [winfo screenwidth .]; set sh [winfo screenheight .]
 set result [::paneVideo::check strip-wide]
 lappend result $::application::board::ReserveSide
 set wideWidth [winfo width $c]
 wm geometry .application [expr {min(720,$sw-40)}]x[expr {min(1750,$sh-60)}]
 ::paneVideo::wait 1000; update idletasks
 lappend result [::application::reflow::mode] {*}[::paneVideo::check strip-tall]
 wm geometry .application 1200x780
 ::paneVideo::wait 1000; update idletasks
 lappend result [::application::reflow::mode] {*}[::paneVideo::check strip-wide-return] $::application::board::ReserveSide [expr {[winfo width $c] == $wideWidth}]
 lappend result [llength $::paneVideo::calls]
} -cleanup {::paneVideo::cleanup} -result {0 1 1 right tall 0 1 1 wide 0 1 1 right 1 1}

# Regression VAL-PANE-008: on a short (collapsing) window the wide sash
# snapshot used to be skipped, so a tall excursion came back to a squeezed
# board canvas with no feasible reserve and the video fell over the board.
tcltest::test pane-video-008-short-reflow {a short (collapsing) window keeps the reserve and its wide size through wide->tall->wide} -setup {
 set t [::paneVideo::setup]
 wm geometry .application 1040x740
 ::paneVideo::wait 800; update idletasks
 set c $::application::board::Vars(widget:frame)
 set wideWidth [winfo width $c]
} -body {
 set sh [winfo screenheight .]
 set result [list [::paneVideo::overlapAll short-wide]]
 wm geometry .application 620x[expr {min(1000,$sh-60)}]
 ::paneVideo::wait 1000; update idletasks
 lappend result [::application::reflow::mode] [::paneVideo::overlapAll short-tall]
 wm geometry .application 1040x740
 ::paneVideo::wait 1000; update idletasks
 lappend result [::application::reflow::mode] [::paneVideo::overlapAll short-wide-return]
 lassign [::application::board::reserveRect] rx ry rw rh
 lappend result [expr {$rw*$rh > 0}] [expr {[winfo width $c] == $wideWidth}]
 set result
} -cleanup {::paneVideo::cleanup} -result {0 tall 0 wide 0 1 1}

# Regression VAL-PANE-008: focus zoom must not squeeze the board pane below
# the point where the media reserve still fits, or the inset overlays it.
tcltest::test pane-video-008-short-zoom {focus zoom on a short window keeps the media reserve beside the board} -setup {
 set t [::paneVideo::setup]
 wm geometry .application 1040x740
 ::paneVideo::wait 800; update idletasks
 set ::application::focuszoom::duration 0
 ::application::focuszoom::enable $t
} -body {
 set leaf [$t leaf editor]
 foreach w [concat [list $leaf] [winfo children $leaf]] {
  if {![winfo exists $w] || ![winfo ismapped $w]} {continue}
  event generate $w <ButtonPress-1> -x 5 -y 5
  event generate $w <ButtonRelease-1> -x 5 -y 5
  break
 }
 ::paneVideo::wait 600; update idletasks
 set over [::paneVideo::overlapAll short-zoom-editor]
 lassign [::application::board::reserveRect] rx ry rw rh
 set over [list $over [expr {$rw*$rh > 0}]]
 set over
} -cleanup {::paneVideo::cleanup} -result {0 1}

tcltest::cleanupTests
