# Optional ChessBase shortcuts in the real application.
package require tcltest 2.5

namespace eval ::keymapTest {
	variable Scheme $::application::Options(shortcut:scheme)
}

proc ::keymapTest::scheme {value} {
	set ::application::Options(shortcut:scheme) $value
}

proc ::keymapTest::effective {w key} {
	foreach tag [bindtags $w] {
		set cmd [bind $tag $key]
		if {$cmd ne ""} { return $cmd }
	}
	return ""
}

# Setup is an actual preferences dialog, not a second shortcut configuration.
tcltest::test keymap-preferences {the Setup menu exposes both persisted choices} -body {
	::application::ShortcutPreferences .application
	set dlg .application.shortcutPreferences
	set menu .keymapMenu
	menu $menu
	::menu::build $menu
	set found 0
	for {set i 0} {$i <= [$menu.mSetup index end]} {incr i} {
		if {[$menu.mSetup type $i] eq "command" &&
			[$menu.mSetup entrycget $i -command] eq "::application::ShortcutPreferences .application"} {
			set found 1
		}
	}
	list $found [$dlg.content.chesswiz cget -value] \
		[$dlg.content.chessbase cget -value] \
		[$dlg.content.chessbase cget -variable]
} -cleanup {
	catch {destroy .application.shortcutPreferences}
	catch {destroy .keymapMenu}
} -result {1 chesswiz chessbase ::application::Options(shortcut:scheme)}

tcltest::test keymap-roundtrip {overrides restore defaults without a restart} -setup {
	::keymapTest::scheme chesswiz
	set w $::application::board::Vars(widget:frame)
	set before [::keymapTest::effective $w <Control-a>]
	set find [bind .application <Control-f>]
} -body {
	::keymapTest::scheme chessbase
	set result [list [string match *editComment* [::keymapTest::effective $w <Control-a>]] \
		[string match *ShortcutApplicationCommand* [bind .application <Control-f>]] \
		[string match *scroll* [::keymapTest::effective $w <Prior>]]]
	::keymapTest::scheme chesswiz
	lappend result [expr {$before eq [::keymapTest::effective $w <Control-a>]}] \
		[expr {$find eq [bind .application <Control-f>]}] [llength [bind ChessBaseBoard]]
	set result
} -cleanup { ::keymapTest::scheme chesswiz } -result {1 1 1 1 1 0}

tcltest::test keymap-repeat-language {language rebinding and repeated selection preserve restoration} -setup {
	::keymapTest::scheme chesswiz
	set w $::application::board::Vars(widget:frame)
	set before [::keymapTest::effective $w <Control-a>]
	set find [bind .application <Control-f>]
} -body {
	::keymapTest::scheme chessbase
	::application::board::bindKeys
	::keymapTest::scheme chessbase
	set changed [string match *editComment* [::keymapTest::effective $w <Control-a>]]
	::keymapTest::scheme chesswiz
	list $changed [expr {$before eq [::keymapTest::effective $w <Control-a>]}] \
		[expr {$find eq [bind .application <Control-f>]}]
} -cleanup { ::keymapTest::scheme chesswiz } -result {1 1 1}

tcltest::test keymap-board-event {Ctrl+F flips the actual board and stops at the overlay} -setup {
	update
	catch { destroy .tipoftheday }
	# GotFocus deliberately redirects focus away from an empty game editor.
	if {[::application::pgn::empty?]} { ::menu::gameNew .application }
	::application::switchTab board
	::keymapTest::scheme chessbase
	set w $::application::board::Vars(widget:frame)
	set rotated [::application::board::rotated?]
	focus -force $w
	update
	catch { destroy .tipoftheday ; focus -force $w ; update }
} -body {
	if {[focus] ne $w} { error "board focus redirected to [focus] (tags: [bindtags [focus]])" }
	event generate $w <Control-f>
	update
	set changed [expr {$rotated != [::application::board::rotated?]}]
	::keymapTest::scheme chesswiz
	list $changed [string match *Rotate* [::keymapTest::effective $w <Control-f>]]
} -cleanup {
	if {$rotated != [::application::board::rotated?]} { ::application::board::Rotate $w }
	::keymapTest::scheme chesswiz
} -result {1 0}

tcltest::test keymap-notation {notation participates in the same overlay} -body {
	::keymapTest::scheme chessbase
	set w $::application::pgn::Vars(pgn:0)
	list [expr {"ChessBaseBoard" in [bindtags $w]}] \
		[string match *editComment* [::keymapTest::effective $w <Control-a>]]
} -cleanup { ::keymapTest::scheme chesswiz } -result {1 1}

tcltest::test keymap-entry {editable fields keep select-all and typed punctuation} -setup {
	::keymapTest::scheme chessbase
	# Packing after the expanding notebook can leave an entry without any pixels.
	toplevel .application.keymapEditing
	set w .application.keymapEditing.entry
	ttk::entry $w
	pack $w
	update
	$w insert 0 hello
	focus -force $w
	update
} -body {
	if {![winfo viewable $w] || [focus] ne $w} { error "entry is not mapped and focused" }
	event generate $w <Control-a>
	set selected [$w selection present]
	$w selection clear
	$w icursor end
	event generate $w <KeyPress-exclam>
	list $selected [$w get] [expr {"ChessBaseBoard" ni [bindtags $w]}]
} -cleanup {
	destroy .application.keymapEditing
	::keymapTest::scheme chesswiz
} -result {1 hello! 1}

tcltest::test keymap-editable-overlay {an editable text with the board tag keeps punctuation and selection} -setup {
	::keymapTest::scheme chessbase
	toplevel .application.keymapEditing
	set w .application.keymapEditing.text
	text $w
	pack $w
	$w insert end hello
	bindtags $w [linsert [bindtags $w] 0 ChessBaseBoard]
	update
	focus -force $w
	update
} -body {
	event generate $w <Control-a>
	set selected [expr {[$w tag ranges sel] ne ""}]
	$w tag remove sel 1.0 end
	$w mark set insert end-1c
	event generate $w <KeyPress-exclam>
	event generate $w <KeyPress-question>
	list $selected [$w get 1.0 end-1c]
} -cleanup {
	destroy .application.keymapEditing
	::keymapTest::scheme chesswiz
} -result {1 hello!?}

tcltest::test keymap-database-context {database Ctrl+F dispatches the existing search with the current variant} -setup {
	::keymapTest::scheme chessbase
	set tab [.application.nb select]
	::application::switchTab database
	rename ::application::database::OpenAdvancedSearch ::keymapTest::realSearch
	proc ::application::database::OpenAdvancedSearch {args} { set ::keymapTest::Search $args }
} -body {
	set rc [catch {::application::ShortcutApplicationCommand .application search}]
	list $rc [expr {$::keymapTest::Search eq [list .application \
		[::scidb::db::get name] [::application::database::currentVariant]]}]
} -cleanup {
	rename ::application::database::OpenAdvancedSearch {}
	rename ::keymapTest::realSearch ::application::database::OpenAdvancedSearch
	.application.nb select $tab
	::keymapTest::scheme chesswiz
} -result {3 1}


tcltest::test keymap-new-widget {new board widgets inherit the currently selected scheme} -setup {
	::keymapTest::scheme chessbase
	set w .application.keymapBoard
	tk::frame $w
	set saved $::application::board::Vars(need-binding)
} -body {
	::application::board::needBinding $w
	set result [string match *editComment* [::keymapTest::effective $w <Control-a>]]
	::keymapTest::scheme chesswiz
	list $result [::keymapTest::effective $w <Control-a>]
} -cleanup {
	set ::application::board::Vars(need-binding) $saved
	destroy $w
	::keymapTest::scheme chesswiz
} -result {1 {}}

tcltest::test keymap-persistence {options writer serializes the scheme and loading applies it} -setup {
	set file [file join $::scidb::test::app::testDir tmp-app keymap options.tcl]
	file mkdir [file dirname $file]
} -body {
	::keymapTest::scheme chessbase
	set fd [open $file w]
	::application::WriteShortcutOptions $fd
	close $fd
	::keymapTest::scheme chesswiz
	source $file
	list $::application::Options(shortcut:scheme) \
		[string match *editComment* [bind ChessBaseBoard <Control-a>]] \
		[expr {"::application::WriteShortcutOptions" in $::options::WriteCallbacks(options)}]
} -cleanup {
	file delete -force [file dirname $file]
	::keymapTest::scheme chesswiz
} -result {chessbase 1 1}

::keymapTest::scheme $::keymapTest::Scheme
tcltest::cleanupTests
