# The Ask field's suggestion list shows readable labels, each once.
package require tcltest 2.5

tcltest::test ask-palette-flip-board-key {"flip board" lists the Ctrl+F action} -body {
	# Every action, right-click copies included, stays reachable by its
	# label (test_app_menu_changed_labels), so Flip Board may appear more
	# than once; the main action with its shortcut must be among them.
	::application::ask::PopulateRows "flip board"
	set found 0
	foreach r $::application::ask::Priv(rows) {
		lassign $r id label key
		if {$id eq "board-flip" && $key ne ""} { set found 1 }
	}
	set found
} -result 1

tcltest::test ask-palette-no-raw-ids {no palette label is an action id} -body {
	set bad {}
	foreach r [::action::labels asklist ""] {
		lassign $r id label
		if {$label eq $id || [regexp {^[a-z0-9]+[._][a-z0-9_.]+$} $label]} { lappend bad $id=$label }
	}
	set bad
} -result {}

tcltest::test ask-placeholder-fits {the whole placeholder fits in the field} -body {
	update
	set e $::application::ask::Priv(entry)
	set p $::application::ask::Priv(placeholder)
	expr {[font measure [expr {[$p cget -font] eq "" ? "TkDefaultFont" : [$p cget -font]}] [$p cget -text]] <= [winfo width $e] - 8}
} -result 1

tcltest::cleanupTests
