# ======================================================================
# Evidence run for VAL-PAL-002: the Ask field in every layout.
# Run through tests/run_app_tests.tcl under Xvfb at the matching screen
# size; ASK_EVIDENCE_GEOM and ASK_EVIDENCE_TAG name the shot. Output:
# tests/tmp-app/menu-redesign/ask-evidence/<tag>.png and .txt
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::ev {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app menu-redesign ask-evidence]
	variable Geom $::env(ASK_EVIDENCE_GEOM)
	variable Tag $::env(ASK_EVIDENCE_TAG)
}

proc ::scidb::test::ev::Rect {w} {
	if {![winfo exists $w]} { return {} }
	set x [winfo rootx $w]
	set y [winfo rooty $w]
	return [list $x $y [expr {$x + [winfo width $w]}] [expr {$y + [winfo height $w]}]]
}

proc ::scidb::test::ev::Overlap {a b} {
	if {![llength $a] || ![llength $b]} { return 0 }
	lassign $a ax1 ay1 ax2 ay2
	lassign $b bx1 by1 bx2 by2
	return [expr {[llength $a] && $ax1 < $bx2 && $bx1 < $ax2 && $ay1 < $by2 && $by1 < $ay2}]
}

proc ::scidb::test::ev::TabOrder {} {
	set chain {}
	set w [tk_focusNext .application]
	set seen {}
	while {$w ne "" && [lsearch -exact $seen $w] < 0 && [llength $chain] < 12} {
		lappend seen $w
		lappend chain $w
		set w [tk_focusNext $w]
	}
	return $chain
}

proc ::scidb::test::ev::Write {lines} {
	file mkdir $::scidb::test::ev::Dir
	set path [file join $::scidb::test::ev::Dir "$::scidb::test::ev::Tag.txt"]
	set f [open $path w]
	puts $f [join $lines \n]
	close $f
	return $path
}

tcltest::test ask-evidence {capture the Ask field in this layout} -body {
	set Geom $::scidb::test::ev::Geom
	set Tag $::scidb::test::ev::Tag

	wm deiconify .
	after 300
	update
	set focusStartup [focus]
	catch { destroy .tipoftheday }
	after 100
	update

	# the stub speech path, so the microphone is part of the evidence
	::application::speech::configure stub {return "open the last game"}
	::application::ask::SyncMic

	if {[catch { wm geometry .application $Geom+0+0 }]} { wm geometry . $Geom+0+0 }
	after 300
	update

	if {$Tag eq "fullscreen"} {
		catch { ::menu::viewFullscreen toggle }
		catch { wm attributes .application -fullscreen 1 }
		after 300
		update
	}
	if {$Tag eq "board" || $Tag eq "board-only"} {
		catch { ::application::openPane board }
		catch { .application.nb select .application.nb.board }
		after 300
		update
	}

	set field [::scidb::test::ev::Rect .application.nb.ask]
	set entry [::scidb::test::ev::Rect [::application::ask::Entry]]
	set mic [::scidb::test::ev::Rect [::application::ask::Mic]]
	set board [::scidb::test::ev::Rect [::application::ask::BoardWidget]]
	set screenW [winfo screenwidth .]
	set screenH [winfo screenheight .]

	set onScreen [expr {[llength $field] \
		&& [lindex $field 0] >= 0 && [lindex $field 1] >= 0 \
		&& [lindex $field 2] <= $screenW && [lindex $field 3] <= $screenH}]
	set overlapsBoard [::scidb::test::ev::Overlap $field $board]
	set micOnScreen [expr {![llength $mic] || ([lindex $mic 0] >= 0 && [lindex $mic 2] <= $screenW)}]
	set micPacked [expr {[lsearch -exact [pack slaves .application.nb.ask] [::application::ask::Mic]] >= 0}]
	set micInside [expr {[llength $mic] && [llength $field] \
		&& [lindex $mic 0] >= [lindex $field 0] && [lindex $mic 2] <= [lindex $field 2]}]
	set placeholder [expr {[winfo manager .application.nb.ask.placeholder] eq "place"}]

	catch {::menu::fullscreen?} fullscreenState
	catch {::application::activeTab} activeTabState
	set state [list \
		"tag=$Tag" "geom=$Geom" "screen=${screenW}x${screenH}" \
		"wm_state=[wm state .application]" \
		"fullscreen=$fullscreenState" "tab=$activeTabState" \
		"wm_fullscreen=[expr {[catch {wm attributes .application -fullscreen} f] ? "?" : $f}]" \
		"focus_startup=$focusStartup" "dialog_open=[::application::ask::DialogOpen]" \
		"field=$field" "entry=$entry" "mic=$mic" "board=$board" \
		"field_on_screen=$onScreen" "field_overlaps_board=$overlapsBoard" \
		"mic_packed=$micPacked" "mic_on_screen=$micOnScreen" "mic_inside_field=$micInside" \
		"placeholder=$placeholder" "entry_textvariable=[set ::application::ask::Query]" \
		"tab_order=[::scidb::test::ev::TabOrder]"]
	::scidb::test::ev::Write $state

	set png [file join $::scidb::test::ev::Dir "$Tag.png"]
	catch { file delete -force $png }
	catch { exec import -window root $png }

	list $onScreen $overlapsBoard $micPacked $micOnScreen $micInside [file exists $png]
} -result {1 0 1 1 1 1}

tcltest::cleanupTests
