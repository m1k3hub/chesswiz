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

# These cases assert native X events and X focus, including KeyRelease.
# Aqua/Win32 cannot run xdotool; synthetic Tk events would change that contract.
tcltest::testConstraint x11Keys [expr {
    [tk windowingsystem] eq "x11" && [llength [auto_execok xdotool]] > 0}]

namespace eval ::scidb::test::askkeys {
	variable Ran {}
	variable ids {}
	variable Added {}
	variable CommentResult {}
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
		.application.__asktest_pgn_text .application.__comment__} {
		catch { destroy $w }
	}
	foreach id $::scidb::test::askkeys::Added {
		catch { ::gamebar::remove $::application::pgn::Vars(gamebar) $id }
	}
	set ::scidb::test::askkeys::Added {}
	update
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
tcltest::test ask-real-down-down-up-keeps-selection {real Down/Down/Up survive their KeyReleases} -constraints x11Keys -body {
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

tcltest::test ask-real-enter-runs-selected-row {real Down then Enter runs the second row} -constraints x11Keys -body {
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

proc ::scidb::test::askkeys::FocusX {w} {
	focus -force $w
	update
	set top [winfo toplevel $w]
	set id [winfo id $top]
	catch { exec xdotool windowfocus $id }
	update
	focus -force $w
	update
	# The KeyRelease/selection idles of the previous shortcut may run after
	# the first update; settle them and put the focus back.
	after 50
	update
	focus -force $w
	update
	return [focus]
}

proc ::scidb::test::askkeys::NewGame {} {
	::menu::gameNew .application
	update
	set gb $::application::pgn::Vars(gamebar)
	set id [::gamebar::selected $gb]
	lappend ::scidb::test::askkeys::Added $id
	set slot [::scidb::game::current]
	::scidb::game::import $slot "1. e4 e5 2. Nf3 Nc6 *" {} {} -encoding utf-8 -variation 0
	::scidb::game::go 2
	update
	return $id
}

proc ::scidb::test::askkeys::FindClass {w class} {
	foreach child [winfo children $w] {
		if {[winfo class $child] eq $class} { return $child }
		set found [::scidb::test::askkeys::FindClass $child $class]
		if {$found ne ""} { return $found }
	}
	return ""
}

# Runs inside ::comment::open's tkwait: real dialog, real X keys.
proc ::scidb::test::askkeys::CommentProbe {} {
	variable CommentResult
	set result {}
	catch {
		set dlg .application.__comment__
		set t [::scidb::test::askkeys::FindClass $dlg Comment]
		if {$t eq ""} { set result {nodialog}; error nodialog }
		$t configure -state normal
		$t delete 1.0 end
		$t insert 1.0 "hello world"
		$t mark set insert 1.5
		set ::application::ask::Query "prior query"
		set f0 [::scidb::test::askkeys::FocusX $t]
		::scidb::test::askkeys::Key {ctrl+shift+k}
		set afterShift [focus]
		set textShift [$t get 1.0 end-1c]
		::scidb::test::askkeys::FocusX $t
		$t mark set insert 1.5
		::scidb::test::askkeys::Key {ctrl+k}
		set afterK [focus]
		set textK [$t get 1.0 end-1c]
		::scidb::test::askkeys::FocusX $t
		$t delete 1.0 end
		$t insert 1.0 "king"
		$t mark set insert end
		::scidb::test::askkeys::Key {ctrl+shift+u}
		set textKing [$t get 1.0 end-1c]
		catch { destroy .application.__asktest_figmenu }
		menu .application.__asktest_figmenu -tearoff 0
		::comment::MakeSymbolMenu $t .application.__asktest_figmenu
		set accel ""
		catch { set accel [.application.__asktest_figmenu.figurine entrycget 0 -accelerator] }
		set prec [::application::keyEditor::Conflict game-new Control-Shift-K]
		set result [list [winfo class $t] 			[expr {[lindex $f0 0] eq $t}] 			[expr {$afterShift eq [::application::ask::Entry]}] $textShift 			[expr {$afterK eq $t}] $textK $textKing $accel 			[expr {$prec eq $::application::keyEditor::mc::KeyAskPrecedence}]]
	} err
	catch { destroy .application.__asktest_figmenu }
	catch { destroy .application.__comment__ }
	set CommentResult $result
	return
}

# ----------------------------------------------------------------------
# Ctrl+Shift+K from every kind of application toplevel; Ctrl+K keeps
# kill-line in the multi-line editors.
# ----------------------------------------------------------------------
tcltest::test ask-real-ctrl-shift-k-comment-toplevel {Ctrl+Shift+K focuses Ask from a Comment toplevel; Ctrl+K kill-lines} -constraints x11Keys -body {
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

tcltest::test ask-real-ctrl-shift-k-engine-console {Ctrl+Shift+K focuses Ask from the Script engine console; Ctrl+K kill-lines} -constraints x11Keys -body {
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

tcltest::test ask-real-ctrl-shift-k-pgn-text {Ctrl+Shift+K focuses Ask from the PGN Text; Ctrl+K kill-lines} -constraints x11Keys -body {
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


# The real dialog: ::application::pgn::editComment opens
# .application.__comment__ itself, with the editor's own figurine bindings.
tcltest::test ask-real-comment-dialog-ask-wins {real comment dialog: Ctrl+Shift+K focuses Ask, Ctrl+K kill-lines, Ctrl+Shift+U inserts the king} -constraints x11Keys -body {
	::scidb::test::askkeys::cleanup
	::scidb::test::askkeys::NewGame
	set ::scidb::test::askkeys::CommentResult {}
	after 700 ::scidb::test::askkeys::CommentProbe
	catch { ::application::pgn::editComment before }
	set result $::scidb::test::askkeys::CommentResult
	::scidb::test::askkeys::cleanup
	set result
} -result {Comment 1 1 {hello world} 1 hello king♔ Ctrl-Shift-U 1}

::tcltest::cleanupTests
