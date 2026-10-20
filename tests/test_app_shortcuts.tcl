# ======================================================================
# Scidb App Test - drop-down accelerators and shortcut collisions
# (VAL-REG-003, VAL-BAR-008; decisions D-4 and PROPOSAL section 7.4)
# ======================================================================
# The key-editor ids stay registry ids and keep their saved overrides;
# the drop-down reads its accelerators from the current binding, so a
# rebind or scheme switch moves the label. Ctrl+N remains a hidden alias
# for New Game, New Database/New Game use Ctrl+Shift+N/G, prev/next keep
# both scheme key pairs, and the Edit menu's Ctrl+A/Ctrl+C labels follow
# the focus.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::shortcutTest {
	variable Dir [file dirname [file normalize [info script]]]
}

# The binding an event would run on <w>: the first tag with a binding wins.
proc ::shortcutTest::effective {w key} {
	foreach tag [bindtags $w] {
		set cmd [bind $tag $key]
		if {$cmd ne ""} { return $cmd }
	}
	return ""
}

proc ::shortcutTest::Build {} {
	set menu .testShortcutMenu
	catch { destroy $menu }
	menu $menu -tearoff 0
	::menu::BuildDropdown $menu
	# force the lazy cascades to fill so every row can be inspected
	::menu::Dump $menu
	return $menu
}

proc ::shortcutTest::FindCommand {menu cmd} {
	set n [$menu index end]
	if {$n eq "" || $n eq "none"} { return "" }
	for {set i 0} {$i <= $n} {incr i} {
		set type [$menu type $i]
		if {$type eq "cascade"} {
			set found [::shortcutTest::FindCommand [$menu entrycget $i -menu] $cmd]
			if {$found ne ""} { return $found }
		} elseif {$type in {command checkbutton radiobutton}} {
			set bound ""
			catch { set bound [$menu entrycget $i -command] }
			if {$bound eq $cmd} { return [list $menu $i] }
		}
	}
	return ""
}

proc ::shortcutTest::CommandAccel {id} {
	set menu [::shortcutTest::Build]
	set found [::shortcutTest::FindCommand $menu "::action::run $id"]
	set accel ""
	if {$found ne ""} {
		catch { set accel [lindex $found 0] }
		set accel [$accel entrycget [lindex $found 1] -accelerator]
	}
	destroy $menu
	return $accel
}

proc ::shortcutTest::FindCascade {menu label} {
	set n [$menu index end]
	if {$n eq "" || $n eq "none"} { return "" }
	for {set i 0} {$i <= $n} {incr i} {
		if {[$menu type $i] ne "cascade"} { continue }
		set text [::menu::NormLabel [$menu entrycget $i -label]]
		if {$text eq $label} { return [list $menu $i] }
		set found [::shortcutTest::FindCascade [$menu entrycget $i -menu] $label]
		if {$found ne ""} { return $found }
	}
	return ""
}

proc ::shortcutTest::CascadeAccel {labelName} {
	set menu [::shortcutTest::Build]
	set found [::shortcutTest::FindCascade $menu [::menu::NormLabel [::menu::MC $labelName]]]
	set accel ""
	if {$found ne ""} {
		catch { set accel [lindex $found 0] }
		set accel [$accel entrycget [lindex $found 1] -accelerator]
	}
	destroy $menu
	return $accel
}

# Every accelerator in a built drop-down, as a flat list.
proc ::shortcutTest::AllAccels {menu {resultVar ""}} {
	upvar $resultVar out
	set n [$menu index end]
	if {$n eq "" || $n eq "none"} { return }
	for {set i 0} {$i <= $n} {incr i} {
		set type [$menu type $i]
		if {$type eq "cascade"} {
			set accel ""
			catch { set accel [$menu entrycget $i -accelerator] }
			if {$accel ne ""} { lappend out $accel }
			::shortcutTest::AllAccels [$menu entrycget $i -menu] out
		} elseif {$type in {command checkbutton radiobutton}} {
			set accel ""
			catch { set accel [$menu entrycget $i -accelerator] }
			if {$accel ne ""} { lappend out $accel }
		}
	}
}

proc ::shortcutTest::Restore {} {
	::application::keyEditor::ResetAll
	set ::application::Options(shortcut:scheme) chesswiz
	::application::ApplyShortcutScheme
}


tcltest::test shortcuts-keyeditor-ids-registry {all 28 key-editor ids are unchanged registry ids} -setup {
	set expected {
		nav-back nav-forward nav-fast-back nav-fast-forward nav-start nav-end
		nav-enter-var nav-leave-var board-flip board-null-move game-new
		game-save game-replace game-next game-prev game-first game-last
		annot-comment-after annot-comment-before annot-palette annot-marks
		annot-good-move annot-bad-move app-quit app-find app-help app-log
		app-fullscreen
	}
} -body {
	set missing {}
	set tableIds {}
	foreach entry $::application::keyEditor::Actions {
		lappend tableIds [lindex $entry 0]
	}
	foreach id $expected {
		if {![dict exists $::action::Registry $id]} { lappend missing $id }
	}
	list [llength $expected] [expr {[lsort $tableIds] eq [lsort $expected]}] $missing
} -result {28 1 {}}


tcltest::test shortcuts-saved-overrides {overrides saved before the redesign still apply and drive the menu labels} -setup {
	::shortcutTest::Restore
	set savedOptions $::scidb::file::options
	set ::scidb::file::options \
		[file join $::shortcutTest::Dir fixtures shortcut-options-prechange.tcl]
	::options::sourceFile
	set ::scidb::file::options $savedOptions
	::application::ApplyShortcutScheme
	set board $::application::board::Vars(widget:frame)
} -body {
	list \
		$::application::keyEditor::Options(shortcut:keys,game-save) \
		[::application::keyEditor::CurrentKey game-save] \
		[string match *SaveGame* [::shortcutTest::effective $board <Control-g>]] \
		[string match *SaveGame* [::shortcutTest::effective $board <Control-s>]] \
		[::application::keyEditor::CurrentKey app-quit] \
		[string match *shutdown* [bind .application <Control-j>]] \
		[::application::keyEditor::CurrentKey game-next] \
		[string match *LoadGame* [::shortcutTest::effective $board <F9>]] \
		$::application::keyEditor::Options(shortcut:keys,game-new) \
		[::shortcutTest::CommandAccel game-save] \
		[::shortcutTest::CommandAccel app-quit] \
		[::shortcutTest::CommandAccel game-next] \
		[::shortcutTest::CascadeAccel NewGame]
} -cleanup {
	::shortcutTest::Restore
} -result {Control-g Control-g 1 0 Control-j 1 F9 1 Control-Alt-g Ctrl+G Ctrl+J F9 Ctrl+Alt+G}


tcltest::test shortcuts-rebind-moves-menu-label {rebinding changes the posted menu accelerator and reset restores it} -setup {
	::shortcutTest::Restore
	set menu [::shortcutTest::Build]
	set found [::shortcutTest::FindCommand $menu {::action::run game-save}]
	set before [[lindex $found 0] entrycget [lindex $found 1] -accelerator]
} -body {
	::application::keyEditor::SetKey game-save Control-g
	set rebinding [[lindex $found 0] entrycget [lindex $found 1] -accelerator]
	::application::keyEditor::ResetAction game-save
	set reset [[lindex $found 0] entrycget [lindex $found 1] -accelerator]
	list $before $rebinding $reset
} -cleanup {
	destroy $menu
	::shortcutTest::Restore
} -result {Ctrl+S Ctrl+G Ctrl+S}


tcltest::test shortcuts-new-database-new-game {Ctrl+Shift+N/G are the real New Database/New Game bindings} -setup {
	::shortcutTest::Restore
} -body {
	list \
		[expr {[bind .application <Control-Shift-n>] ne ""}] \
		[expr {[bind .application <Control-Shift-N>] ne ""}] \
		[expr {[bind .application <Control-Shift-g>] ne ""}] \
		[expr {[bind .application <Control-Shift-G>] ne ""}] \
		[::shortcutTest::CascadeAccel NewDatabase] \
		[::shortcutTest::CascadeAccel NewGame]
} -cleanup {
	::shortcutTest::Restore
} -result {1 1 1 1 Ctrl+Shift+N Ctrl+Shift+G}


tcltest::test shortcuts-ctrl-n-hidden-alias {Ctrl+N starts a new game but is shown nowhere} -setup {
	::shortcutTest::Restore
	set ::application::Options(shortcut:scheme) chesswiz
	::application::ApplyShortcutScheme
	set menu [::shortcutTest::Build]
	set accels {}
	::shortcutTest::AllAccels $menu accels
	set paletteAccels {}
	foreach row [::action::labels palette] {
		lappend paletteAccels [lindex $row 2]
	}
	set dropdownAccels {}
	foreach row [::action::labels dropdown] {
		lappend dropdownAccels [lindex $row 2]
	}
} -body {
	set current [::application::keyEditor::CurrentKey game-new]
	set shown [expr {"Control-n" in $accels || "Ctrl+N" in $accels
		|| "Control-n" in $paletteAccels || "Ctrl+N" in $paletteAccels
		|| "Control-n" in $dropdownAccels || "Ctrl+N" in $dropdownAccels}]
	# the hidden alias still runs new game
	::application::switchTab database
	catch { ::application::ShortcutApplicationCommand .application new }
	list \
		[expr {[bind .application <Control-n>] ne ""}] \
		$current \
		$shown \
		[::menu::Accel game-new] \
		[.application.nb select]
} -cleanup {
	destroy $menu
	::shortcutTest::Restore
} -result {1 Control-Shift-G 0 Ctrl+Shift+G .application.nb.board}


tcltest::test shortcuts-prev-next-both-keys {prev/next stay bound to both pairs and show the scheme key} -setup {
	::shortcutTest::Restore
	set board $::application::board::Vars(widget:frame)
} -body {
	set chesswiz [list \
		[::application::keyEditor::CurrentKey game-next] \
		[::application::keyEditor::CurrentKey game-prev] \
		[string match *next* [::shortcutTest::effective $board <F10>]] \
		[string match *prev* [::shortcutTest::effective $board <Control-F10>]] \
		[::shortcutTest::CommandAccel game-next]]
	set ::application::Options(shortcut:scheme) chessbase
	set chessbase [list \
		[::application::keyEditor::CurrentKey game-next] \
		[::application::keyEditor::CurrentKey game-prev] \
		[string match *LoadGame* [bind ChessBaseBoard <F10>]] \
		[string match *LoadGame* [bind ChessBaseBoard <Control-F10>]] \
		[::shortcutTest::CommandAccel game-next]]
	list $chesswiz $chessbase
} -cleanup {
	::shortcutTest::Restore
} -result {{Control-Down Control-Up 1 1 Ctrl+Down} {F10 Control-F10 1 1 F10}}


tcltest::test shortcuts-focus-labels {Ctrl+A/Ctrl+C labels follow the focus} -setup {
	# a startup dialog may still own the focus; drop it and show the board
	catch { destroy .tipoftheday }
	focus -force .application
	update
	::application::switchTab board
	update
	set board $::application::board::Vars(widget:frame)
	toplevel .shortcutTestText
	text .shortcutTestText.t
	pack .shortcutTestText.t -fill both -expand yes
	update
} -body {
	focus -force $board
	update
	set onBoard [list [::menu::Label app-select-all] [::menu::Label app-copy]]
	focus -force .shortcutTestText.t
	update
	set inText [list [::menu::Label app-select-all] [::menu::Label app-copy]]
	focus -force .application
	update
	set noFocus [list [::menu::Label app-select-all] [::menu::Label app-copy]]
	list $onBoard $inText $noFocus
} -cleanup {
	destroy .shortcutTestText
	focus -force .application
} -result {{{Edit annotation} {Edit comment after move}} {{Select All} Copy} {{Select All} Copy}}


tcltest::test shortcuts-chessbase-new-keys {the ChessBase scheme gets the same new keys and labels} -setup {
	::shortcutTest::Restore
	set ::application::Options(shortcut:scheme) chessbase
	::application::ApplyShortcutScheme
} -body {
	list \
		[expr {[bind .application <Control-Shift-n>] ne ""}] \
		[expr {[bind .application <Control-Shift-N>] ne ""}] \
		[expr {[bind .application <Control-Shift-g>] ne ""}] \
		[expr {[bind .application <Control-Shift-G>] ne ""}] \
		[::shortcutTest::CascadeAccel NewDatabase] \
		[::shortcutTest::CascadeAccel NewGame] \
		[::shortcutTest::CommandAccel game-prev] \
		[::application::keyEditor::Conflict game-new Control-Shift-G]
} -cleanup {
	::shortcutTest::Restore
} -result {1 1 1 1 Ctrl+Shift+N Ctrl+Shift+G Ctrl+F10 {}}


tcltest::test shortcuts-conflict-check {the new keys add no key-editor conflicts} -setup {
	::shortcutTest::Restore
} -body {
	set ::application::Options(shortcut:scheme) chesswiz
	set wizDups {}
	set seen {}
	foreach entry $::application::keyEditor::Actions {
		set action [lindex $entry 0]
		set key [::application::keyEditor::CurrentKey $action]
		if {$key eq ""} { continue }
		set norm [::application::keyEditor::NormalizeKeySpec $key]
		if {[dict exists $seen $norm]} {
			lappend wizDups [list $norm [dict get $seen $norm] $action]
		} else {
			dict set seen $norm $action
		}
	}
	set ::application::Options(shortcut:scheme) chessbase
	set cbDups {}
	set seen {}
	foreach entry $::application::keyEditor::Actions {
		set action [lindex $entry 0]
		set key [::application::keyEditor::CurrentKey $action]
		if {$key eq ""} { continue }
		set norm [::application::keyEditor::NormalizeKeySpec $key]
		if {[dict exists $seen $norm]} {
			lappend cbDups [list $norm [dict get $seen $norm] $action]
		} else {
			dict set seen $norm $action
		}
	}
	set ::application::Options(shortcut:scheme) chesswiz
	# The ChessBase scheme already had these two table collisions before
	# the redesign; the redesign must not add any.
	list $wizDups [lsort $cbDups] \
		[::application::keyEditor::Conflict game-new Control-Shift-G] \
		[::application::keyEditor::Conflict game-new Control-n] \
		[::application::keyEditor::Conflict game-save Control-Shift-g]
} -cleanup {
	::shortcutTest::Restore
} -result {{} {{Control-a annot-comment-after annot-palette} {Control-f board-flip app-find}} {} {} {Ctrl+Shift+G is already used by New Game}}


tcltest::cleanupTests
