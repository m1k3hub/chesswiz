# ======================================================================
# Scidb App Test Suite -- G25: a tooltip keeps its delay
# ======================================================================
# REPORT F-03 (tests/tmp-app/laptop-loop/REPORT.md:139-143): a tooltip was
# mapped 201 s after the tooltip window had been created, which looked like
# tooltips missing in a session. The window is created (and withdrawn) once at
# startup, so that number only says that the first hover that survived came
# 200 s into the session. The hovers before it were dropped, and this is why:
# <Enter> arms the tooltip with "after $delay", and any hide cancelled it ...
# while nothing armed it again as long as the pointer stayed on the widget:
#   - a <Leave> that arrives after the <Enter> of the next widget (Windows
#     delivers crossing events in that order),
#   - the handler of a widget the pointer has already left - the information
#     page's tkhtml onmouseout (::application::information::MouseLeave) runs
#     ::tooltip::hide for every node the pointer leaves,
#   - a menu that unposted, or "after 10 { ::tooltip::hide }" (gamebar).
# The tooltip of that hover then never appeared, and the next hover had to
# happen before any tooltip was seen at all.
#
# The tests below hover a widget (the pointer has to be inside it: Show checks
# that), ask for the tooltip the way the <Enter> binding does and ask for a
# hide from another widget's handler shortly afterwards - once with the event
# loop busy with other after-events. The tooltip has to be mapped with the
# message that was asked for within the configured delay + 200 ms.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]

namespace eval ::scidb::test::tipdelay {
	variable dummy 0
	variable busy 0
	variable ticks 0
	variable delay 500
	variable msg "tooltip delay test"
}

proc ::scidb::test::tipdelay::pump {ms} {
	after $ms {set ::scidb::test::tipdelay::dummy 1}
	vwait ::scidb::test::tipdelay::dummy
	set ::scidb::test::tipdelay::dummy 0
}

# Other after-events of the application: a chain that keeps the event loop
# busy while the tooltip is asked for. "after 0" is no good - such a chain
# never lets "update" return.
proc ::scidb::test::tipdelay::spin {} {
	variable busy
	variable ticks

	if {!$busy} { return }
	incr ticks

	set sum 0
	for {set i 0} {$i < 500} {incr i} { incr sum $i }
	after 1 ::scidb::test::tipdelay::spin
}

proc ::scidb::test::tipdelay::startLoad {} {
	variable busy
	variable ticks

	set busy 1
	set ticks 0
	after 0 ::scidb::test::tipdelay::spin
	::scidb::test::tipdelay::pump 100
}

proc ::scidb::test::tipdelay::stopLoad {} {
	variable busy

	set busy 0
	::scidb::test::tipdelay::pump 100
}

proc ::scidb::test::tipdelay::tipText {} {
	set label [::tooltip::wname].top.label-0
	if {[catch {$label cget -text} text]} { return "" }
	return $text
}

proc ::scidb::test::tipdelay::hover {} {
	set w .tipdelay.b

	update
	event generate $w <Motion> -warp 1 -x [expr {[winfo width $w] / 2}] -y [expr {[winfo height $w] / 2}]
	update
	set containing [winfo containing {*}[winfo pointerxy $w]]

	if {![string match $w* $containing]} {
		return -code error "the pointer is on \"$containing\", not on $w"
	}
	return $w
}

# Milliseconds until the tooltip mapped, or -1. The tooltip window is created
# at startup, so only "is it mapped" tells whether it is on screen.
proc ::scidb::test::tipdelay::waitMap {ms} {
	set start [clock milliseconds]
	while {[clock milliseconds] - $start < $ms} {
		after 5 {set ::scidb::test::tipdelay::dummy 1}
		vwait ::scidb::test::tipdelay::dummy
		set ::scidb::test::tipdelay::dummy 0
		if {[winfo ismapped [::tooltip::wname]]} {
			set elapsed [expr {[clock milliseconds] - $start}]
			puts "EVIDENCE tooltip-map elapsedMs=$elapsed budgetMs=$ms"
			return $elapsed
		}
	}
	return -1
}

proc ::scidb::test::tipdelay::setup {} {
	variable delay
	variable ticks

	::scidb::test::wait::ready
	set delay [::tooltip::delay]
	set busy 0
	set ticks 0
	update
	toplevel .tipdelay -class TipDelayTest
	wm geometry .tipdelay +40+40
	button .tipdelay.b -text "tooltip delay"
	pack .tipdelay.b
	::tooltip::tooltip .tipdelay.b $::scidb::test::tipdelay::msg
	raise .tipdelay
	::scidb::test::wait::until {[winfo ismapped .tipdelay.b] && [winfo width .tipdelay.b] > 1}
}

proc ::scidb::test::tipdelay::cleanup {} {
	variable busy

	set busy 0
	catch { ::tooltip::hide 0 1 }
	::scidb::test::tipdelay::pump 50
	catch { destroy .tipdelay }
	::scidb::test::tipdelay::pump 50
}

# mapped within the delay, with the message that was asked for
proc ::scidb::test::tipdelay::check {budget elapsed} {
	variable msg

	if {$elapsed < 0} { return "the tooltip did not map within ${budget}ms" }
	if {$elapsed > $budget} { return "the tooltip mapped after ${elapsed}ms, budget is ${budget}ms" }
	set text [::scidb::test::tipdelay::tipText]
	if {$text ne $msg} { return "the tooltip reads \"$text\", not \"$msg\"" }
	return ok
}

tcltest::test tipdelay-map {the tooltip maps within its configured delay} -setup {
	::scidb::test::tipdelay::setup
} -body {
	set w [::scidb::test::tipdelay::hover]
	::tooltip::show $w $::scidb::test::tipdelay::msg
	set budget [expr {$::scidb::test::tipdelay::delay + 200}]
	::scidb::test::tipdelay::check $budget [::scidb::test::tipdelay::waitMap $budget]
} -cleanup {
	::scidb::test::tipdelay::cleanup
} -result ok

# The <Enter> of the widget the pointer is on is followed by the hide of
# another widget's leave handler (see the head of this file): the tooltip of
# this hover must not be taken away by it.
tcltest::test tipdelay-late-hide {a late hide from another widget keeps the tooltip of this hover} -setup {
	::scidb::test::tipdelay::setup
} -body {
	set w [::scidb::test::tipdelay::hover]
	::tooltip::show $w $::scidb::test::tipdelay::msg
	::scidb::test::tipdelay::pump 100
	::tooltip::hide
	set budget [expr {$::scidb::test::tipdelay::delay + 200}]
	::scidb::test::tipdelay::check $budget [::scidb::test::tipdelay::waitMap $budget]
} -cleanup {
	::scidb::test::tipdelay::cleanup
} -result ok

# Same, with the event loop busy: the delay is the delay, not the time the
# other after-events leave.
tcltest::test tipdelay-busy {the tooltip maps on time while other after-events are busy} -setup {
	::scidb::test::tipdelay::setup
} -body {
	set w [::scidb::test::tipdelay::hover]
	::scidb::test::tipdelay::startLoad
	::tooltip::show $w $::scidb::test::tipdelay::msg
	::scidb::test::tipdelay::pump 100
	::tooltip::hide
	set budget [expr {$::scidb::test::tipdelay::delay + 200}]
	set elapsed [::scidb::test::tipdelay::waitMap $budget]
	set result [::scidb::test::tipdelay::check $budget $elapsed]
	if {$::scidb::test::tipdelay::ticks < 50} {
		return "the event loop was not busy ([::scidb::test::tipdelay::ticks] other after-events)"
	}
	return $result
} -cleanup {
	::scidb::test::tipdelay::stopLoad
	::scidb::test::tipdelay::cleanup
} -result ok

# What has to be taken away is still taken away: a press hides the tooltip
# (the binding, and disable while a toolbar is dragged, pass force).
tcltest::test tipdelay-forced-hide {a forced hide takes the pending tooltip away} -setup {
	::scidb::test::tipdelay::setup
} -body {
	set w [::scidb::test::tipdelay::hover]
	::tooltip::show $w $::scidb::test::tipdelay::msg
	::scidb::test::tipdelay::pump 100
	::tooltip::hide 0 1
	list [::scidb::test::tipdelay::waitMap 700] [winfo ismapped [::tooltip::wname]]
} -cleanup {
	::scidb::test::tipdelay::cleanup
} -result {-1 0}

::tcltest::cleanupTests
