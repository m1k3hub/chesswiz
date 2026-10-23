# The New Game action ids dispatch through ::menu::Invoke, so they must be
# registered like every other action, or ::action::run rejects them.

package require Tcl 8.5
package require tcltest 2.5
namespace import ::tcltest::*

test game-new-action-registered {game.new.normal is in the action registry} -body {
	dict exists $::action::Registry game.new.normal
} -result 1

test game-new-action-variants {all New Game variant ids are registered} -body {
	set missing {}
	foreach id {game.new.normal game.new.three game.new.crazy game.new.variants} {
		if {![dict exists $::action::Registry $id]} { lappend missing $id }
	}
	set missing
} -result {}

test game-new-action-runs {::action::run game.new.normal returns without an error} -body {
	catch { ::action::run game.new.normal }
} -result 0

cleanupTests
