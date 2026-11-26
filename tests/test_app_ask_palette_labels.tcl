# The Ask field's suggestion list shows readable labels, each once.
package require tcltest 2.5

tcltest::test ask-palette-no-duplicate-labels {"flip board" lists Flip Board once, with its key} -body {
	::application::ask::PopulateRows "flip board"
	set labels {}
	set accel {}
	foreach r $::application::ask::Priv(rows) {
		lassign $r id label key
		if {$label eq "Flip Board"} { lappend labels $label; set accel $key }
	}
	list [llength $labels] [expr {$accel ne ""}]
} -result {1 1}

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
