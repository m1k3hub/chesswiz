# ======================================================================
# Scidb App Test - per-key shortcut editor
# (tcl/app-key-editor.tcl, wired into ::application::ShortcutPreferences)
# ======================================================================
# The pure helpers (key spec normalization, both-case binding, conflict
# detection, the override store) run against the real application; the
# dialog is driven through a capture field. No network, no engine.
# ======================================================================

package require tcltest 2.5

namespace eval ::keyEditorTest {
	variable Scheme $::application::Options(shortcut:scheme)
}

proc ::keyEditorTest::scheme {value} {
	set ::application::Options(shortcut:scheme) $value
}

# The binding an event would run on <w>: the first tag with a binding wins.
proc ::keyEditorTest::effective {w key} {
	foreach tag [bindtags $w] {
		set cmd [bind $tag $key]
		if {$cmd ne ""} { return $cmd }
	}
	return ""
}

# Remove every override and re-install the scheme bindings, so one test
# does not leak its overrides into the next.
proc ::keyEditorTest::restore {} {
	::application::keyEditor::ResetAll
	::keyEditorTest::scheme $::keyEditorTest::Scheme
}


tcltest::test key-editor-normalize {key specs are normalized to modifier-keysym} -body {
	list \
		[::application::keyEditor::NormalizeKeySpec {<Control-Shift-C>}] \
		[::application::keyEditor::NormalizeKeySpec {Control-shift-c}] \
		[::application::keyEditor::NormalizeKeySpec {Shift-Control-c}] \
		[::application::keyEditor::NormalizeKeySpec {F1}] \
		[::application::keyEditor::NormalizeKeySpec {<Prior>}] \
		[::application::keyEditor::NormalizeKeySpec {Control-Alt-0}]
} -result {Control-Shift-C Control-Shift-c Control-Shift-c F1 Prior Control-Alt-0}

tcltest::test key-editor-both-cases {a letter key is bound in both cases for Caps Lock} -body {
	list \
		[::application::keyEditor::BindSpecs {Control-q}] \
		[::application::keyEditor::BindSpecs {Control-Shift-C}] \
		[::application::keyEditor::BindSpecs {F1}] \
		[::application::keyEditor::BindSpecs {exclam}]
} -result {{Control-q Control-Q} {Control-Shift-C Control-Shift-c} F1 exclam}

tcltest::test key-editor-describe {key specs have a readable display form} -body {
	list \
		[::application::keyEditor::DescribeKey {Control-Shift-C}] \
		[::application::keyEditor::DescribeKey {Control-q}] \
		[::application::keyEditor::DescribeKey {Left}] \
		[::application::keyEditor::DescribeKey {Prior}] \
		[::application::keyEditor::DescribeKey {Control-Alt-0}]
} -result {Ctrl+Shift+C Ctrl+Q ← Page↑ Ctrl+Alt+0}

tcltest::test key-editor-capture-spec {a captured key event becomes a key spec} -body {
	list \
		[::application::keyEditor::SpecFromEvent {g} 0x4] \
		[::application::keyEditor::SpecFromEvent {G} 0x5] \
		[::application::keyEditor::SpecFromEvent {F5} 0x4] \
		[::application::keyEditor::SpecFromEvent {Left} 0x4] \
		[::application::keyEditor::SpecFromEvent {space} 0x4] \
		[::application::keyEditor::SpecFromEvent {Return} 0x0] \
		[::application::keyEditor::SpecFromEvent {Delete} 0x4] \
		[::application::keyEditor::SpecFromEvent {exclam} 0x1]
} -result {Control-g Control-Shift-G Control-F5 Control-Left Control-space Return Control-Delete Shift-exclam}

tcltest::test key-editor-actions {the action table lists the expected actions} -setup {
	set actions {}
	foreach entry $::application::keyEditor::Actions {
		lassign $entry action labelVar tag spec cbSpec cmd
		lappend actions $action
	}
} -body {
	list \
		[llength $actions] \
		[expr {"nav-forward" in $actions}] \
		[expr {"board-flip" in $actions}] \
		[expr {"board-null-move" in $actions}] \
		[expr {"game-new" in $actions}] \
		[expr {"game-save" in $actions}] \
		[expr {"game-next" in $actions}] \
		[expr {"annot-comment-after" in $actions}] \
		[expr {"annot-marks" in $actions}] \
		[expr {"app-quit" in $actions}] \
		[expr {"app-find" in $actions}] \
		[expr {"app-help" in $actions}] \
		[expr {"app-log" in $actions}]
} -result {28 1 1 1 1 1 1 1 1 1 1 1 1}

tcltest::test key-editor-action-label {action labels come from the mc namespaces, without mnemonics} -body {
	list \
		[::application::keyEditor::ActionLabel game-new ::gamebar::mc::GameNew] \
		[::application::keyEditor::ActionLabel board-flip ::overview::mc::RotateBoard] \
		[::application::keyEditor::ActionLabel annot-good-move ::annotation::mc::Nag(1)] \
		[::application::keyEditor::ActionLabel app-quit ::menu::mc::Quit] \
		[::application::keyEditor::ActionLabel no-such-action ::gamebar::mc::NoSuchLabel] \
		[::application::keyEditor::ActionLabel game-save ::application::keyEditor::mc::SaveNewGame]
} -result {{New Game} {Rotate Board} {Good move} Quit no-such-action {Save as new game}}

tcltest::test key-editor-current-key {the current key follows the scheme and the override} -setup {
	array unset ::application::keyEditor::Options
} -body {
	::keyEditorTest::scheme chesswiz
	set chesswiz [list \
		[::application::keyEditor::CurrentKey game-save] \
		[::application::keyEditor::CurrentKey game-new] \
		[::application::keyEditor::CurrentKey annot-comment-after] \
		[::application::keyEditor::CurrentKey nav-leave-var] \
		[::application::keyEditor::CurrentKey board-flip]]
	::keyEditorTest::scheme chessbase
	set chessbase [list \
		[::application::keyEditor::CurrentKey annot-comment-after] \
		[::application::keyEditor::CurrentKey nav-leave-var] \
		[::application::keyEditor::CurrentKey game-next] \
		[::application::keyEditor::CurrentKey board-flip] \
		[::application::keyEditor::CurrentKey game-save]]
	list $chesswiz $chessbase
} -cleanup {
	::keyEditorTest::scheme $::keyEditorTest::Scheme
} -result {{Control-s {} Control-c Up {}} {Control-a m F10 Control-f Control-s}}

tcltest::test key-editor-current-key-override {an override wins over the scheme key} -setup {
	::keyEditorTest::scheme chesswiz
} -body {
	::application::keyEditor::SetKey game-save Control-g
	::application::keyEditor::CurrentKey game-save
} -cleanup {
	::keyEditorTest::restore
} -result {Control-g}

tcltest::test key-editor-conflict-override {an override conflicts with another override} -setup {
	array unset ::application::keyEditor::Options
	::application::keyEditor::ApplyOverrides
	set ::application::keyEditor::Options(shortcut:keys,game-save) Control-g
} -body {
	catch {::application::keyEditor::SetKey game-replace Control-g} error
	list [::application::keyEditor::Conflict game-replace Control-g] $error
} -cleanup {
	::keyEditorTest::restore
} -result {{Ctrl+G is already used by Save as new game} {Ctrl+G is already used by Save as new game}}

tcltest::test key-editor-conflict-scheme {an override conflicts with a scheme key of the active scheme} -body {
	::application::keyEditor::Conflict board-flip Control-s
} -result {Ctrl+S is already used by Save as new game}

tcltest::test key-editor-conflict-chessbase-scheme {a ChessBase scheme key conflicts in the ChessBase scheme too} -setup {
	::keyEditorTest::scheme chessbase
} -body {
	::application::keyEditor::Conflict board-null-move Control-f
} -cleanup {
	::keyEditorTest::scheme $::keyEditorTest::Scheme
} -result {Ctrl+F is already used by Rotate Board}

tcltest::test key-editor-conflict-cb-key {a ChessBase scheme key conflicts in the Chesswiz scheme too: overrides survive switches} -setup {
	::keyEditorTest::scheme chesswiz
} -body {
	catch {::application::keyEditor::SetKey nav-forward F10} error
	list [::application::keyEditor::Conflict nav-forward F10] $error
} -cleanup {
	::keyEditorTest::restore
} -result {{F10 is already used by Load next game} {F10 is already used by Load next game}}

tcltest::test key-editor-conflict-outside {a key bound outside the action table conflicts} -setup {
	::keyEditorTest::scheme chesswiz
} -body {
	catch {::application::keyEditor::SetKey game-save Control-Shift-plus} error
	list [string match "*already used by another binding*" $error] \
		[info exists ::application::keyEditor::Options(shortcut:keys,game-save)]
} -cleanup {
	::keyEditorTest::restore
} -result {1 0}

tcltest::test key-editor-conflict-case {conflicts ignore the letter case} -body {
	::application::keyEditor::Conflict game-save Control-Q
} -result {Ctrl+Q is already used by Quit}

tcltest::test key-editor-no-conflict {a free key and the action's own key do not conflict} -setup {
	array unset ::application::keyEditor::Options
	::keyEditorTest::scheme chesswiz
} -body {
	list \
		[::application::keyEditor::Conflict game-save Control-g] \
		[::application::keyEditor::Conflict game-save Control-s] \
		[::application::keyEditor::Conflict game-save Control-S] \
		[::application::keyEditor::Conflict board-null-move Control-0]
} -cleanup {
	::keyEditorTest::restore
} -result {{} {} {} {}}

tcltest::test key-editor-set-unknown {an unknown action is rejected} -body {
	catch {::application::keyEditor::SetKey no-such-action Control-g} error
	list $error [array size ::application::keyEditor::Options]
} -result {{unknown action no-such-action} 0}

tcltest::test key-editor-set-modifier {a modifier alone cannot be bound} -body {
	catch {::application::keyEditor::SetKey game-save Control} error
	list $error [array size ::application::keyEditor::Options]
} -result {{modifier keys cannot be bound alone} 0}


tcltest::test key-editor-override-app-tag {an app action override is bound on .application in both cases} -setup {
	::keyEditorTest::scheme chesswiz
} -body {
	::application::keyEditor::SetKey app-quit Control-j
	list \
		[string match *shutdown* [bind .application <Control-j>]] \
		[string match *shutdown* [bind .application <Control-J>]] \
		[bind .application <Control-q>] \
		[bind .application <Control-Q>]
} -cleanup {
	::keyEditorTest::restore
} -result {1 1 {} {}}

tcltest::test key-editor-override-board-tag {a board action override is bound on the board widgets through FilterKey} -setup {
	::keyEditorTest::scheme chesswiz
	set w $::application::board::Vars(widget:frame)
} -body {
	::application::keyEditor::SetKey game-save Control-g
	list \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-g>]] \
		[string match *FilterKey* [::keyEditorTest::effective $w <Control-g>]] \
		[string match *ShortcutBoardCommand* [::keyEditorTest::effective $w <Control-g>]] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-s>]] \
		[bind .application <Control-g>]
} -cleanup {
	::keyEditorTest::restore
} -result {1 1 0 0 {}}

tcltest::test key-editor-override-keeps-caps-lock {the new key works with Caps Lock in both cases} -setup {
	::keyEditorTest::scheme chesswiz
	set w $::application::board::Vars(widget:frame)
} -body {
	::application::keyEditor::SetKey game-save Control-g
	list \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-g>]] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-G>]]
} -cleanup {
	::keyEditorTest::restore
} -result {1 1}

tcltest::test key-editor-override-chessbase-tag {a ChessBase-only action override is bound on the ChessBaseBoard tag} -setup {
	::keyEditorTest::scheme chessbase
} -body {
	::application::keyEditor::SetKey annot-good-move Control-Key-8
	list \
		[string match *addNag* [bind ChessBaseBoard <Control-Key-8>]] \
		[string match *ShortcutBoardCommand* [bind ChessBaseBoard <Control-Key-8>]] \
		[bind ChessBaseBoard <exclam>] \
		[string match *addNag* [bind ChessBaseBoard <question>]]
} -cleanup {
	::keyEditorTest::restore
	::application::ApplyShortcutScheme
} -result {1 1 {} 1}

tcltest::test key-editor-chessbase-override-chesswiz {a ChessBase-only action override is bound and fires in the Chesswiz scheme} -setup {
	update
	# A pending "after idle" tip-of-the-day would steal focus from the
	# board and block the synthetic key event.
	set ::tips::Options(mode) neverShow
	catch { destroy .tipoftheday }
	if {[::application::pgn::empty?]} { ::menu::gameNew .application }
	set tab [.application.nb select]
	::application::switchTab board
	::keyEditorTest::scheme chesswiz
	set w $::application::board::Vars(widget:frame)
	set rotated [::application::board::rotated?]
} -body {
	::application::keyEditor::SetKey board-flip F5
	set bound [string match *Rotate* [::keyEditorTest::effective $w <F5>]]
	# Let pending idle focus changes settle, then focus the board directly
	# before the synthetic key: key events follow the focus at send time.
	update
	focus -force $w
	event generate $w <KeyPress> -keysym F5
	update
	list $bound \
		[expr {[::application::board::rotated?] != $rotated}] \
		[bind ChessBaseBoard <Control-f>]
} -cleanup {
	if {[::application::board::rotated?] != $rotated} {
		::application::board::Rotate $w
	}
	.application.nb select $tab
	::application::ApplyShortcutScheme
	::keyEditorTest::restore
} -result {1 1 {}}

tcltest::test key-editor-chessbase-override-switch {a ChessBase-only override survives a scheme switch} -setup {
	::keyEditorTest::scheme chesswiz
	set w $::application::board::Vars(widget:frame)
} -body {
	::application::keyEditor::SetKey board-flip F5
	set inChesswiz [string match *Rotate* [::keyEditorTest::effective $w <F5>]]
	::keyEditorTest::scheme chessbase
	set inChessbase [string match *Rotate* [::keyEditorTest::effective $w <F5>]]
	set default [bind ChessBaseBoard <Control-f>]
	::keyEditorTest::scheme chesswiz
	list $inChesswiz $inChessbase $default \
		[string match *Rotate* [::keyEditorTest::effective $w <F5>]] \
		$::application::keyEditor::Options(shortcut:keys,board-flip)
} -cleanup {
	::application::ApplyShortcutScheme
	::keyEditorTest::restore
} -result {1 1 {} 1 F5}

tcltest::test key-editor-chessbase-override-reset {reset removes a ChessBase-only override and restores the scheme default} -setup {
	::keyEditorTest::scheme chesswiz
	set w $::application::board::Vars(widget:frame)
} -body {
	::application::keyEditor::SetKey board-flip F5
	set overridden [string match *Rotate* [::keyEditorTest::effective $w <F5>]]
	::application::keyEditor::ResetAction board-flip
	set removed [expr {![string match *Rotate* [::keyEditorTest::effective $w <F5>]]}]
	set stored [info exists ::application::keyEditor::Options(shortcut:keys,board-flip)]
	::keyEditorTest::scheme chessbase
	list $overridden $removed $stored \
		[string match *Rotate* [::keyEditorTest::effective $w <F5>]] \
		[string match *ShortcutBoardCommand* [bind ChessBaseBoard <Control-f>]]
} -cleanup {
	::application::ApplyShortcutScheme
	::keyEditorTest::restore
} -result {1 1 0 0 1}

tcltest::test key-editor-chessbase-override-conflict {a taken key is reported for a ChessBase-only action} -setup {
	::keyEditorTest::scheme chesswiz
} -body {
	catch {::application::keyEditor::SetKey board-flip Control-s} error
	list $error \
		[info exists ::application::keyEditor::Options(shortcut:keys,board-flip)]
} -cleanup {
	::keyEditorTest::restore
} -result {{Ctrl+S is already used by Save as new game} 0}

tcltest::test key-editor-capture-click-focus {clicking the read-only capture field focuses it} -setup {
	::application::ShortcutPreferences .application
	set dlg .application.shortcutPreferences
	set tree $dlg.content.keys.list.tree
	set entry $dlg.content.keys.capture.entry
	update
	focus -force $tree
	update
} -body {
	event generate $entry <Button-1> -x 5 -y 5
	update
	list \
		[expr {[bind $entry <Button-1>] ne ""}] \
		[expr {[focus] eq $entry}] \
		[$entry cget -state]
} -cleanup {
	catch {destroy .application.shortcutPreferences}
} -result {1 1 readonly}

tcltest::test key-editor-set-same {the scheme key itself drops an existing override} -setup {
	::keyEditorTest::scheme chesswiz
	set w $::application::board::Vars(widget:frame)
} -body {
	set first [::application::keyEditor::SetKey game-save Control-s]
	::application::keyEditor::SetKey game-save Control-g
	set second [::application::keyEditor::SetKey game-save Control-s]
	list $first $second \
		[info exists ::application::keyEditor::Options(shortcut:keys,game-save)] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-s>]] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-g>]]
} -cleanup {
	::keyEditorTest::restore
} -result {{} {} 0 1 0}

tcltest::test key-editor-reset {reset restores the scheme binding of the board widgets} -setup {
	::keyEditorTest::scheme chesswiz
	set w $::application::board::Vars(widget:frame)
} -body {
	::application::keyEditor::SetKey game-save Control-g
	::application::keyEditor::ResetAction game-save
	list \
		[info exists ::application::keyEditor::Options(shortcut:keys,game-save)] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-g>]] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-s>]]
} -cleanup {
	::keyEditorTest::restore
} -result {0 0 1}

tcltest::test key-editor-reset-app {reset restores the .application scheme binding} -setup {
	::keyEditorTest::scheme chesswiz
} -body {
	::application::keyEditor::SetKey app-quit Control-j
	::application::keyEditor::ResetAction app-quit
	list \
		[string match *shutdown* [bind .application <Control-j>]] \
		[string match *shutdown* [bind .application <Control-q>]] \
		[string match *shutdown* [bind .application <Control-Q>]]
} -cleanup {
	::keyEditorTest::restore
} -result {0 1 1}

tcltest::test key-editor-reset-app-find {reset restores the search field binding of the Chesswiz scheme} -setup {
	::keyEditorTest::scheme chesswiz
} -body {
	::application::keyEditor::SetKey app-find Control-k
	set overridden [string match *keyEditor::Find* [bind .application <Control-k>]]
	::application::keyEditor::ResetAction app-find
	list $overridden \
		[string match *TriggerFindNext* [bind .application <Control-f>]] \
		[string match *TriggerFindNext* [bind .application <Control-F>]] \
		[string match *keyEditor::Find* [bind .application <Control-k>]]
} -cleanup {
	::keyEditorTest::restore
} -result {1 1 1 0}

tcltest::test key-editor-reset-all {reset all removes every override and restores every scheme key} -setup {
	::keyEditorTest::scheme chesswiz
	set w $::application::board::Vars(widget:frame)
} -body {
	::application::keyEditor::SetKey game-save Control-g
	::application::keyEditor::SetKey app-log Control-b
	::application::keyEditor::ResetAll
	list \
		[array size ::application::keyEditor::Options] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-g>]] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-s>]] \
		[string match *log* [bind .application <Control-l>]] \
		[string length [bind .application <Control-b>]]
} -cleanup {
	::keyEditorTest::restore
} -result {0 0 1 1 0}

tcltest::test key-editor-scheme-switch-keeps-overrides {switching the scheme keeps the overrides} -setup {
	::keyEditorTest::scheme chesswiz
	set w $::application::board::Vars(widget:frame)
} -body {
	::application::keyEditor::SetKey game-save Control-g
	::keyEditorTest::scheme chessbase
	set inChessbase [list \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-g>]] \
		[bind ChessBaseBoard <Control-s>]]
	::keyEditorTest::scheme chesswiz
	list $inChessbase \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-g>]] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-s>]] \
		[bind .application <Control-s>] \
		$::application::keyEditor::Options(shortcut:keys,game-save)
} -cleanup {
	::keyEditorTest::restore
} -result {{1 {}} 1 0 {} Control-g}

tcltest::test key-editor-persistence {overrides survive the options writer round trip} -setup {
	set file [file join $::scidb::test::app::testDir tmp-app keys options.tcl]
	file mkdir [file dirname $file]
	set w $::application::board::Vars(widget:frame)
	::keyEditorTest::scheme chesswiz
} -body {
	::application::keyEditor::SetKey game-save Control-g
	::application::keyEditor::SetKey app-quit Control-j
	set fd [open $file w]
	::application::keyEditor::WriteOptions $fd
	close $fd
	# simulate a restart: drop the overrides and their bindings, then load
	# the file and apply the scheme again
	array unset ::application::keyEditor::Options
	foreach s {Control-g Control-G} {
		foreach widget $::application::board::Vars(need-binding) { bind $widget <$s> {} }
	}
	foreach s {Control-j Control-J} { bind .application <$s> {} }
	source $file
	::application::ApplyShortcutScheme
	list \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-g>]] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-s>]] \
		[string match *shutdown* [bind .application <Control-j>]] \
		[string match *shutdown* [bind .application <Control-Q>]] \
		$::application::keyEditor::Options(shortcut:keys,game-save) \
		[expr {"::application::keyEditor::WriteOptions" in $::options::WriteCallbacks(options)}]
} -cleanup {
	file delete -force [file dirname $file]
	::keyEditorTest::restore
} -result {1 0 1 0 Control-g 1}

tcltest::test key-editor-dialog {the dialog lists the actions and captures a new key} -setup {
	::application::ShortcutPreferences .application
	set dlg .application.shortcutPreferences
	set tree $dlg.content.keys.list.tree
	set w $::application::board::Vars(widget:frame)
	::keyEditorTest::scheme chesswiz
	update
} -body {
	$tree selection set game-save
	update
	set entry $dlg.content.keys.capture.entry
	focus -force $entry
	update
	event generate $entry <KeyPress> -keysym g -state 0x4
	update
	set shown [$entry get]
	# Apply stores the override and re-binds the key
	$dlg.content.keys.buttons.apply invoke
	update
	list \
		[llength [$tree children {}]] \
		[$tree item game-save -values] \
		$shown \
		$::application::keyEditor::Options(shortcut:keys,game-save) \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-g>]] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-s>]] \
		[::application::keyEditor::CurrentKey game-save]
} -cleanup {
	::keyEditorTest::restore
	catch {destroy .application.shortcutPreferences}
} -result {28 Ctrl+G {New key: Ctrl+G} Control-g 1 0 Control-g}

tcltest::test key-editor-dialog-conflict {the dialog reports a conflict and does not apply it} -setup {
	::application::ShortcutPreferences .application
	set dlg .application.shortcutPreferences
	set tree $dlg.content.keys.list.tree
	set w $::application::board::Vars(widget:frame)
	::keyEditorTest::scheme chesswiz
	update
} -body {
	$tree selection set game-replace
	update
	set entry $dlg.content.keys.capture.entry
	focus -force $entry
	update
	# Ctrl+S is the scheme key of "Save as new game"
	event generate $entry <KeyPress> -keysym s -state 0x4
	update
	$dlg.content.keys.buttons.apply invoke
	update
	list \
		[$dlg.content.keys.status cget -text] \
		[info exists ::application::keyEditor::Options(shortcut:keys,game-replace)] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-s>]]
} -cleanup {
	::keyEditorTest::restore
	catch {destroy .application.shortcutPreferences}
} -result {{Ctrl+S is already used by Save as new game} 0 1}

tcltest::test key-editor-dialog-reset {the dialog resets one row and all rows} -setup {
	::application::ShortcutPreferences .application
	set dlg .application.shortcutPreferences
	set tree $dlg.content.keys.list.tree
	set w $::application::board::Vars(widget:frame)
	::keyEditorTest::scheme chesswiz
	::application::keyEditor::SetKey game-save Control-g
	update
} -body {
	$tree selection set game-save
	update
	$dlg.content.keys.buttons.reset invoke
	update
	set afterRow [list \
		[array size ::application::keyEditor::Options] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-s>]] \
		[$tree item game-save -values]]
	::application::keyEditor::SetKey game-save Control-g
	::application::keyEditor::SetKey app-log Control-b
	$dlg.content.keys.buttons.resetAll invoke
	update
	list $afterRow \
		[array size ::application::keyEditor::Options] \
		[string match *SaveGame* [::keyEditorTest::effective $w <Control-s>]] \
		[string match *log* [bind .application <Control-l>]]
} -cleanup {
	::keyEditorTest::restore
	catch {destroy .application.shortcutPreferences}
} -result {{0 1 Ctrl+S} 0 1 1}


::keyEditorTest::restore
tcltest::cleanupTests
