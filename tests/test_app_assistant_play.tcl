package require tcltest 2.5

tcltest::test assistant-play-dialog-black {the Assistant opens the existing dialog with the user playing Black, without starting a game} -body {
	catch {::playengine::Close}
	set oldColor $::playengine::Options(color)
	set ::playengine::Options(color) white
	set reply [::application::assistant::runTool open_play_engine {color black}]
	set result [list [winfo exists .application.playengine] \
		$::playengine::Priv(dlg:color) $::playengine::Priv(active) \
		[string match {*user's colour set to black*} $reply] \
		[dict get [::action::get open_play_engine] ends-in-dialog] \
		$::playengine::Options(color)]
	::playengine::Close
	set ::playengine::Options(color) $oldColor
	set result
} -result {1 black 0 1 1 white}

tcltest::test assistant-play-bad-colour {unknown colours never open the dialog} -body {
	set reply [::application::assistant::runTool open_play_engine {color purple}]
	list [string match {error:*} $reply] [winfo exists .application.playengine]
} -result {1 0}

tcltest::test assistant-play-default {omitting colour keeps the user's saved preference} -body {
	set oldColor $::playengine::Options(color)
	set ::playengine::Options(color) random
	::application::assistant::runTool open_play_engine {}
	set color $::playengine::Priv(dlg:color)
	::playengine::Close
	set ::playengine::Options(color) $oldColor
	set color
} -result random

tcltest::cleanupTests
