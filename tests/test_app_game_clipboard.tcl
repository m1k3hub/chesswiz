# ======================================================================
# Scidb App Test — copy and paste games between databases (VAL-CTX-005)
# ======================================================================
# Decision 006: the game clipboard remembers exactly the copied games
# (base, variant, numbers). Paste copies only those, into the database
# of the focused game list; the Clipbase is never the source. Read-only
# and unsupported-variant targets are disabled with an explanation, and
# Paste is hidden until something has been copied. Both operations are
# registry actions so the assistant has the same rules and the bulk
# confirm gate.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::clip {}

proc ::scidb::test::clip::nop {args} { return 0 }

proc ::scidb::test::clip::pgn {file games} {
	set fh [open $file w]
	for {set i 0} {$i < $games} {incr i} {
		puts $fh "\[Event \"Event $i\"\]\n\[White \"W$i\"\]\n\[Black \"B$i\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 2. Nf3 Nc6 *\n"
	}
	close $fh
	return $file
}

# A writable sci base with <games> unrelated games, attached in memory.
proc ::scidb::test::clip::base {dir name games} {
	file mkdir $dir
	set file [file join $dir ${name}_[pid].sci]
	file delete {*}[glob -nocomplain [file rootname $file].*]
	set pgn [pgn ${file}.pgn $games]
	::scidb::db::open $pgn ::scidb::test::clip::nop {} ::scidb::test::clip::nop {}
	::scidb::db::new $file Normal [::application::database::lookupType OpeningsWhite]
	::scidb::db::attach $file $file
	::scidb::db::copy $pgn $file {} ::scidb::test::clip::nop {} ::scidb::test::clip::nop {}
	::scidb::db::save $file ::scidb::test::clip::nop {}
	::scidb::db::close $pgn
	file delete $pgn
	return $file
}

proc ::scidb::test::clip::cleanup {dir} {
	catch { ::game::clipboard::clear }
	catch { set ::action::BulkHook $::scidb::test::clip::SavedBulk }
	file delete -force $dir
}

# The Paste row of a C3 menu: {} when hidden, else {label state}.
proc ::scidb::test::clip::PasteRow {base variant} {
	set menu .clippaste
	catch { destroy $menu }
	menu $menu -tearoff 0
	::context::Build C3 $menu [dict create path .cliplist base $base \
		variant $variant view 0 index 0 column number sortable 1 count 1]
	set row {}
	set end [$menu index end]
	for {set i 0} {$i <= $end} {incr i} {
		if {[$menu type $i] ne "command"} { continue }
		set label [string trimleft [$menu entrycget $i -label] " "]
		if {[string match "Paste Game(s)*" $label]} {
			set row [list $label [$menu entrycget $i -state]]
		}
	}
	destroy $menu
	return $row
}

set ::scidb::test::clip::dir [file join [::tcltest::temporaryDirectory] clipboard-[pid]]
file mkdir $::scidb::test::clip::dir
set ::scidb::test::clip::SavedBulk {}
catch { set ::scidb::test::clip::SavedBulk $::action::BulkHook }
set ::scidb::test::clip::Messages {}

proc ::scidb::test::clip::Status {text} {
	lappend ::scidb::test::clip::Messages $text
	return
}

# The bulk-confirm hooks: the tests run as the file is sourced, so these
# must exist before the first test that names them.
proc ::scidb::test::clip::Decline {args} { return 0 }
proc ::scidb::test::clip::Confirm {args} { return 1 }

tcltest::test clipboard-registry {game.copy and game.paste are assistant tools} -body {
	list [dict exists $::action::Registry game.copy] \
		[dict exists $::action::Registry game.paste] \
		[dict get [::action::get game.copy] ai] \
		[dict get [::action::get game.paste] ai]
} -result {1 1 1 1}

tcltest::test clipboard-single {copying one game and pasting adds exactly one} -setup {
	set dir $::scidb::test::clip::dir
	::game::clipboard::clear
	set src [::scidb::test::clip::base $dir src 3]
	set dst [::scidb::test::clip::base $dir dst 1]
	set before [::scidb::db::count games $dst Normal]
	set clipBefore [::scidb::db::count games $::scidb::clipbaseName Normal]
	set savedMessageCommands [info commands ::ui::message]
} -body {
	set copied [::game::clipboard::copy $src Normal {0}]
	set pasted [::game::clipboard::paste $dst Normal]
	list $copied $pasted \
		[expr {[::scidb::db::count games $dst Normal] == $before + 1}] \
		[expr {[::scidb::db::count games $::scidb::clipbaseName Normal] == $clipBefore}] \
		[::game::clipboard::count] \
		[llength [::game::clipboard::entries]]
} -cleanup {
	::scidb::test::clip::cleanup $dir
} -result {1 1 1 1 1 1}

tcltest::test clipboard-multi {copying three games and pasting adds exactly three} -setup {
	set dir $::scidb::test::clip::dir
	::game::clipboard::clear
	set src [::scidb::test::clip::base $dir src2 4]
	set dst [::scidb::test::clip::base $dir dst2 1]
	set before [::scidb::db::count games $dst Normal]
	set ::action::BulkHook [list ::scidb::test::clip::Confirm]
} -body {
	::game::clipboard::copy $src Normal {0 1 2}
	set pasted [::game::clipboard::paste $dst Normal]
	list $pasted [expr {[::scidb::db::count games $dst Normal] == $before + 3}] \
		[::game::clipboard::count]
} -cleanup {
	::scidb::test::clip::cleanup $dir
} -result {3 1 3}

tcltest::test clipboard-bulk-confirm {a bulk paste obeys the confirm gate} -setup {
	set dir $::scidb::test::clip::dir
	::game::clipboard::clear
	set src [::scidb::test::clip::base $dir src3 3]
	set dst [::scidb::test::clip::base $dir dst3 1]
	set before [::scidb::db::count games $dst Normal]
	::game::clipboard::copy $src Normal {0 1 2}
	set ::action::BulkHook [list ::scidb::test::clip::Decline]
} -body {
	set err [catch {::game::clipboard::paste $dst Normal} reply]
	list $err [expr {[::scidb::db::count games $dst Normal] == $before}] \
		[string match "*declined*" $reply]
} -cleanup {
	::scidb::test::clip::cleanup $dir
} -result {1 1 1}

tcltest::test clipboard-only-the-copied-games {paste copies the remembered game, not the Clipbase} -setup {
	set dir $::scidb::test::clip::dir
	::game::clipboard::clear
	set src [::scidb::test::clip::base $dir src4 3]
	set dst [::scidb::test::clip::base $dir dst4 1]
	# Unrelated content in the Clipbase must not travel with the paste.
	set clipBefore [::scidb::db::count games $::scidb::clipbaseName Normal]
	::game::clipboard::copy $src Normal {1}
} -body {
	::game::clipboard::paste $dst Normal
	set count [::scidb::db::count games $dst Normal]
	# view::new is not usable right after view::copy (the destination
	# cursor is rebuilt), so read the raw game rows (view -1).
	set info [::scidb::db::get gameInfo [expr {$count - 1}] -1 $dst Normal]
	list [expr {[lsearch -exact $info W1] >= 0}] \
		[expr {[lsearch -exact $info W0] < 0}] \
		[expr {[::scidb::db::count games $::scidb::clipbaseName Normal] == $clipBefore}]
} -cleanup {
	::scidb::test::clip::cleanup $dir
} -result {1 1 1}

tcltest::test clipboard-empty {nothing copied: Paste is hidden and paste refuses} -setup {
	set dir $::scidb::test::clip::dir
	::game::clipboard::clear
} -body {
	list [::game::clipboard::hidden?] \
		[string match "*Nothing has been copied*" [::game::clipboard::reason]] \
		[::scidb::test::clip::PasteRow $dir Normal] \
		[catch {::game::clipboard::paste $dir Normal}]
} -cleanup {
	::scidb::test::clip::cleanup $dir
} -result {1 1 {} 1}

tcltest::test clipboard-readonly {a read-only target disables Paste with a reason} -setup {
	set dir $::scidb::test::clip::dir
	::game::clipboard::clear
	set src [::scidb::test::clip::base $dir src5 2]
	set dst [::scidb::test::clip::base $dir dst5 1]
	::game::clipboard::copy $src Normal {0 1}
	set before [::scidb::db::count games $dst Normal]
	set oldReadonly [::scidb::db::get readonly? $dst]
	::scidb::db::set readonly $dst 1
} -body {
	set reason [::game::clipboard::reason $dst Normal]
	set row [::scidb::test::clip::PasteRow $dst Normal]
	list [string match "*read-only*" $reason] \
		[expr {[lindex $row 1] eq "disabled"}] \
		[string match "*$reason*" [lindex $row 0]] \
		[catch {::game::clipboard::paste $dst Normal}] \
		[expr {[::scidb::db::count games $dst Normal] == $before}]
} -cleanup {
	catch { ::scidb::db::set readonly $dst $oldReadonly }
	::scidb::test::clip::cleanup $dir
} -result {1 1 1 1 1}

tcltest::test clipboard-assistant-paste {the assistant's game.paste reaches the same handler} -setup {
	set dir $::scidb::test::clip::dir
	::game::clipboard::clear
	set src [::scidb::test::clip::base $dir src6 2]
	set dst [::scidb::test::clip::base $dir dst6 1]
	::game::clipboard::copy $src Normal {0}
	set before [::scidb::db::count games $dst Normal]
} -body {
	set reply [::application::assistant::runTool game.paste [dict create base $dst]]
	list [expr {[::scidb::db::count games $dst Normal] == $before + 1}] \
		[string match "Pasted 1 game*" $reply]
} -cleanup {
	::scidb::test::clip::cleanup $dir
} -result {1 1}

tcltest::test clipboard-status-count {the status message says how many were pasted} -setup {
	set dir $::scidb::test::clip::dir
	::game::clipboard::clear
	set src [::scidb::test::clip::base $dir src7 3]
	set dst [::scidb::test::clip::base $dir dst7 1]
	::game::clipboard::copy $src Normal {0 1 2}
	set ::action::BulkHook [list ::scidb::test::clip::Confirm]
} -body {
	rename ::ui::message ::scidb::test::clip::RealMessage
	rename ::scidb::test::clip::Status ::ui::message
	set ::scidb::test::clip::Messages {}
	set pasted [::game::clipboard::paste $dst Normal]
	set messages $::scidb::test::clip::Messages
	rename ::ui::message ::scidb::test::clip::Status
	rename ::scidb::test::clip::RealMessage ::ui::message
	list $pasted [expr {[lsearch -glob $messages "*Pasted 3 game*"] >= 0}]
} -cleanup {
	::scidb::test::clip::cleanup $dir
} -result {3 1}


tcltest::cleanupTests
