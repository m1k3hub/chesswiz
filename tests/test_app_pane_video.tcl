# Production inset chain; the player alone is stubbed, like media_fold.
package require tcltest 2.5
namespace eval ::paneVideo {variable saved {}; variable calls {}; variable began 0}
proc ::paneVideo::wait {ms} {after $ms {set ::paneVideo::tick 1}; vwait ::paneVideo::tick}
proc ::paneVideo::stub {name args body} {
 variable saved
 if {[llength [info commands ::media::mpv::$name]]} {rename ::media::mpv::$name ::paneVideo::saved_$name; lappend saved $name}
 proc ::media::mpv::$name $args $body
}
# The harness opens on Information and Startup2 (an after-1 timer) selects
# that tab once: select the board until the choice sticks and the page is
# mapped and sized. Otherwise every geometry below measures the unmapped
# board, whose panedwindow keeps the pre-reflow extents and never resizes.
proc ::paneVideo::showBoard {{ms 6000}} {
 set nb .application.nb
 update
 after 40
 update
 set deadline [expr {[clock milliseconds] + $ms}]
 while {[clock milliseconds] < $deadline} {
  catch { $nb select .application.nb.board }
  update
  if {[$nb select] eq ".application.nb.board" && [winfo exists $nb.board] \
   && [winfo ismapped $nb.board] && [winfo width $nb.board] > 100} {
   update
   if {[$nb select] eq ".application.nb.board"} {return 1}
  }
  after 25
 }
 return 0
}
proc ::paneVideo::setup {} {
 set ::application::twm::Options(board:layout:name) {}
 ::application::reflow::reset
 if {![::paneVideo::showBoard]} {error {board tab did not become visible}}
 wm geometry .application [::paneVideo::wideGeometry]
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
# A wide window that really fits the screen: a hardcoded 1200x780 is
# clamped by the WM on a 1080 px screen (1060x815, then 1074x780 on the
# return), so the reflow cannot return to the size the wide-sash snapshot
# was keyed to and the board pane is left squeezed.
proc ::paneVideo::wideGeometry {} {
 set w [expr {min(1200, [winfo screenwidth .] - 40)}]
 set h [expr {min(780, [winfo screenheight .] - 40)}]
 return "${w}x${h}+0+0"
}
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
 wm geometry .application [::paneVideo::wideGeometry]
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
 # VAL-MED-009: the expanded video is inset by its frame margin (its ridge
 # border stays visible), rather than placed flush at the pane's 0,0.
 set m $::mediainset::FrameMargin
 set fills [expr {[winfo x $w] == $m && [winfo y $w] == $m \
     && [winfo width $w] == [winfo width $p] - 2*$m && [winfo height $w] == [winfo height $p] - 2*$m}]
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
 wm geometry .application [::paneVideo::wideGeometry]
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

# Regression VAL-CROSS-004: the default window (1007x718) is below
# ShortWidth/ShortHeight, so reflow collapses a pane and snapshots the sashes
# at that size. If the window is enlarged while a pane is collapsed, the
# restore must not place those old absolute coordinates over the new
# arrangement: the board pane would be left at its short-size width and
# swapped video would have no room for its reserve strip. The debounced
# reflow makes the race hard to hit from timing alone, so this drives the
# stale restore directly.
tcltest::test pane-video-008-collapse-resize {restoring a collapse snapshot from another window size leaves the board pane alone} -setup {
 set t [::paneVideo::setup]
 set c $::application::board::Vars(widget:frame)
} -body {
 wm geometry .application 1007x718
 set deadline [expr {[clock milliseconds]+6000}]
 while {![info exists ::application::reflow::S(snapshot)]
  || [set ::application::reflow::S(snapshot)] eq {}} {
  if {[clock milliseconds] > $deadline} {error {short window did not collapse a pane}}
  ::paneVideo::wait 50; update
 }
 set snapshot $::application::reflow::S(snapshot)
 set shortSize [list [winfo width .application] [winfo height .application]]
 wm geometry .application [::paneVideo::wideGeometry]
 set deadline [expr {[clock milliseconds]+6000}]
 while {[winfo width .application] < 1100} {
  if {[clock milliseconds] > $deadline} {error {window did not enlarge}}
  ::paneVideo::wait 50; update
 }
 ::paneVideo::wait 300; update idletasks
 set wide [winfo width $c]
 set ::application::reflow::S(snapshot) $snapshot
 set ::application::reflow::S(snapshotSize) $shortSize
 ::application::reflow::restoreCollapsed
 update idletasks
 set restored [winfo width $c]
 puts "COLLAPSE-RESIZE shortSize=$shortSize wide=$wide restored=$restored"
 list [expr {$wide > 500}] [expr {$restored == $wide}]
} -cleanup {::paneVideo::cleanup} -result {1 1}

tcltest::cleanupTests
