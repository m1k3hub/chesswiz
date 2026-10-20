# ======================================================================
# Drop-down rows are registry actions from startup
# ======================================================================
# Laptop runs 182/183: ::action::run menu.view.panes.editor answered
# "unknown action id" because the drop-down registered its rows only on
# the first post. The assistant drives the app by action id, so every
# drop-down row must be runnable before anyone opens the menu.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

tcltest::test menu-rows-registered-before-first-post {menu.* actions exist without posting the drop-down} -body {
	# the drop-down widget is created on the first post: make sure it was not
	set posted [expr {[info exists ::application::Vars(menu:entries)] \
		&& [winfo exists $::application::Vars(menu:entries)]}]
	set ids [lsearch -all -inline -glob [::action::list] menu.*]
	set missing {}
	foreach id {menu.file.open menu.view.panes.editor menu.analysis.annotate menu.analysis.engine_toggle} {
		if {[catch { ::action::get $id }]} { lappend missing $id }
	}
	list $posted [expr {[llength $ids] > 100}] $missing
} -result {0 1 {}}

tcltest::test menu-row-runs-by-id-before-first-post {a drop-down row runs through ::action::run before the first post} -body {
	set before [::menu::PaneChecked editor]
	set r1 [::action::run menu.view.panes.editor]
	update
	set mid [::menu::PaneChecked editor]
	set r2 [::action::run menu.view.panes.editor]
	update
	list [expr {$mid != $before}] [expr {[::menu::PaneChecked editor] == $before}] \
		[string match error:* $r1] [string match error:* $r2]
} -result {1 1 0 0}

tcltest::cleanupTests
