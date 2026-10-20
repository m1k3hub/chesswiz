# ======================================================================
# Scidb App Test - Ask field through real X key events (VAL-PAL-003)
# ======================================================================
# The contract is about keys, not procs: every assertion here sends the
# key through X with xdotool to the verified focused window, so Tk's real
# bindtag chain runs (the KeyRelease after KeyPress included).
# Run under Xvfb with a window manager (openbox) for real focus.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::askkeys {
	variable Ran {}
	variable ids {}
}

proc ::scidb::test::askkeys::ran {tag args} {
	lappend ::scidb::test::askkeys::Ran $tag
	return $tag
}

proc ::scidb::test::askkeys::action {id label tag} {
	::action::register $id [dict create \
		label $label object {} \
		handler [list ::scidb::test::askkeys::ran $tag] \
		what "" doc ""]
	lappend ::scidb::test::askkeys::ids $id
	return $id
}

proc ::scidb::test::askkeys::cleanup {} {
	foreach id $::scidb::test::askkeys::ids {
		catch { dict unset ::action::Registry $id }
	}
	set ::scidb::test::askkeys::ids {}
	set ::scidb::test::askkeys::Ran {}
	catch { destroy .tipoftheday }
	catch { ::application::ask::HideList }
	set ::application::ask::Query ""
	catch { ::application::ask::Entry delete 0 end }
	unset -nocomplain ::application::ask::Priv(filtered)
	catch { ::application::ask::PlaceholderState }
	foreach w {.application.__asktest_comment__ .application.__asktest_engine__
		.application.__asktest_pgn_text} {
		catch { destroy $w }
	}
	return
}

# X focus is on the toplevel; Tk focus is on the widget. Verify both.
proc ::scidb::test::askkeys::FocusWidget {w} {
	focus -force $w
	update
	set top [winfo toplevel $w]
	set id [expr {[winfo id $top]}]
	set got ""
	catch { set got [exec xdotool getwindowfocus] }
	if {$got ne $id} {
		catch { exec xdotool windowfocus $id }
		update
		# X focus landed on the toplevel; put Tk focus back on the widget
		# (a plain windowfocus would apply the toplevel's default focus).
		focus -force $w
		update
	}
	return [list [focus] $got $id]
}

proc ::scidb::test::askkeys::Key {spec} {
	exec xdotool key --clearmodifiers {*}$spec
	update
	return
}

proc ::scidb::test::askkeys::Typed {text} {
	set entry [::application::ask::Entry]
	$entry delete 0 end
	$entry insert 0 $text
	unset -nocomplain ::application::ask::Priv(filtered)
	::application::ask::Typed ""
	FocusWidget $entry
	update
	return
}

proc ::scidb::test::askkeys::Editor {path class} {
	catch { destroy $path }
	toplevel $path -class Scidb
	set t [text $path.text -width 40 -height 4]
	pack $t -fill both -expand yes
	catch { ::scidb::tk::misc setClass $t $class }
	update
	return $t
}

# ----------------------------------------------------------------------
# Up/Down keep the selection through the KeyRelease.
# ----------------------------------------------------------------------
tcltest::test ask-real-down-down-up-keeps-selection {real Down/Down/Up survive their KeyReleases} -body {
	::scidb::test::askkeys::cleanup
	::scidb::test::askkeys::Typed "new"
	set seen {}
	lappend seen $::application::ask::Priv(index)
	::scidb::test::askkeys::Key Down
	lappend seen $::application::ask::Priv(index)
	::scidb::test::askkeys::Key Down
	lappend seen $::application::ask::Priv(index)
	::scidb::test::askkeys::Key Up
	lappend seen $::application::ask::Priv(index)
	set visible [::application::ask::ListVisible]
	set answer [list $seen $visible]
	::scidb::test::askkeys::cleanup
	set answer
} -result {{0 1 2 1} 1}

tcltest::test ask-real-enter-runs-selected-row {real Down then Enter runs the second row} -body {
	::scidb::test::askkeys::cleanup
	::scidb::test::askkeys::action test.askkeys.a "Zqx Alpha" A
	::scidb::test::askkeys::action test.askkeys.b "Zqx Beta" B
	::scidb::test::askkeys::Typed "zqx"
	set rows $::application::ask::Priv(rows)
	set second [lindex [lindex $rows 1] 0]
	set tag [expr {$second eq "test.askkeys.a" ? "A" : "B"}]
	::scidb::test::askkeys::Key Down
	::scidb::test::askkeys::Key Return
	set result [list [expr {[llength $rows] == 2}] \
		[expr {[lindex $::scidb::test::askkeys::Ran 0] eq $tag}]]
	::scidb::test::askkeys::cleanup
	set result
} -result {1 1}

# ----------------------------------------------------------------------
# Ctrl+Shift+K from every kind of application toplevel; Ctrl+K keeps
# kill-line in the multi-line editors.
# ----------------------------------------------------------------------
tcltest::test ask-real-ctrl-shift-k-comment-toplevel {Ctrl+Shift+K focuses Ask from a Comment toplevel; Ctrl+K kill-lines} -body {
	::scidb::test::askkeys::cleanup
	set t [::scidb::test::askkeys::Editor .application.__asktest_comment__ Comment]
	$t insert 1.0 "hello world"
	$t mark set insert 1.5
	set f [::scidb::test::askkeys::FocusWidget $t]
	::scidb::test::askkeys::Key {ctrl+shift+k}
	set afterShift [focus]
	::scidb::test::askkeys::FocusWidget $t
	$t insert end ""
	$t mark set insert 1.5
	::scidb::test::askkeys::Key {ctrl+k}
	set afterK [focus]
	set text [$t get 1.0 end-1c]
	set result [list [lindex $f 0] $afterShift $afterK $text]
	::scidb::test::askkeys::cleanup
	set result
} -result {.application.__asktest_comment__.text .application.nb.ask.entry .application.__asktest_comment__.text hello}

tcltest::test ask-real-ctrl-shift-k-engine-console {Ctrl+Shift+K focuses Ask from the Script engine console; Ctrl+K kill-lines} -body {
	::scidb::test::askkeys::cleanup
	set t [::scidb::test::askkeys::Editor .application.__asktest_engine__ Script]
	$t insert 1.0 "engine line here"
	$t mark set insert 1.7
	set f [::scidb::test::askkeys::FocusWidget $t]
	::scidb::test::askkeys::Key {ctrl+shift+k}
	set afterShift [focus]
	::scidb::test::askkeys::FocusWidget $t
	$t insert end ""
	$t mark set insert 1.7
	::scidb::test::askkeys::Key {ctrl+k}
	set afterK [focus]
	set text [$t get 1.0 end-1c]
	set result [list [winfo class $t] [lindex $f 0] $afterShift $afterK $text]
	::scidb::test::askkeys::cleanup
	set result
} -result {Script .application.__asktest_engine__.text .application.nb.ask.entry .application.__asktest_engine__.text {engine }}

tcltest::test ask-real-ctrl-shift-k-pgn-text {Ctrl+Shift+K focuses Ask from the PGN Text; Ctrl+K kill-lines} -body {
	::scidb::test::askkeys::cleanup
	catch { destroy .application.__asktest_pgn_text }
	set t [text .application.__asktest_pgn_text -width 40 -height 4]
	place $t -x 0 -y 0 -width 240 -height 60
	update
	$t insert 1.0 "pgn text line"
	$t mark set insert 1.4
	set f [::scidb::test::askkeys::FocusWidget $t]
	::scidb::test::askkeys::Key {ctrl+shift+k}
	set afterShift [focus]
	::scidb::test::askkeys::FocusWidget $t
	$t insert end ""
	$t mark set insert 1.4
	::scidb::test::askkeys::Key {ctrl+k}
	set afterK [focus]
	set text [$t get 1.0 end-1c]
	set result [list [winfo class $t] [lindex $f 0] $afterShift $afterK $text]
	::scidb::test::askkeys::cleanup
	set result
} -result {Text .application.__asktest_pgn_text .application.nb.ask.entry .application.__asktest_pgn_text {pgn }}

::tcltest::cleanupTests
