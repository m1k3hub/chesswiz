# Closing the notation editor pane released the fallback game, but the
# application kept its position; the next new game dereferenced it and
# crashed (Windows sweep: game-last / new_game, 0xC0000005).
package require tcltest
namespace import ::tcltest::*

test editor-close-newgame-no-crash {new game after closing the editor pane} -body {
	set twm [::application::twm board]
	set obj [dict create paneUid editor twm $twm frame [$twm leaf editor]]
	::action::run c9.close [dict create object $obj]
	update
	foreach a {game-first game-last new_game} {
		catch { ::action::run $a }
		update
	}
	# reaching here means the process survived
	expr {[winfo exists .application]}
} -result 1

cleanupTests
