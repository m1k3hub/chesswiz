# ======================================================================
# A language switch reaches every new label (GAP-006).
#
# The Donate button, the Donate menu row, the Tournament Director menu
# row, the Tournament Director action labels, and the Assistant
# preference labels must all follow ::mc::setLang at event time, not keep
# the text they were built with. Every one of the six catalogs must
# define the keys: a missing key silently falls back to English.
#
# Run alone through run_app_tests.tcl under Xvfb:
#   HOME=$PWD/tests/tmp-app/seal-home xvfb-run -a \
#       src/tkchesswiz tests/run_app_tests.tcl -file test_app_menu_language_switch_seal.tcl
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::seal {
	variable TdKeys {
		Create Register PairRound Start Stop EnterResult CorrectResult
		OverridePairing Withdraw Bye Publish Finish Undo Redo Status
		Standings Crosstable Audit Export Workspace
	}
	variable TdIds {
		td.create td.register td.pair_round td.start td.stop td.enter_result
		td.correct_result td.override_pairing td.withdraw td.bye td.publish
		td.finish td.undo td.redo td.status td.standings td.crosstable
		td.audit td.export td.workspace
	}
	variable AppKeys {Donate DonateTip}
	variable AskKeys {StartupAssistant PathSherpa PathSherpaModel PathHotwords}
	variable MenuKeys {Donate TournamentDirector FocusFollowsSize OpeningLine EnginePlay}
    variable OnlineKeys {
        Resign ResignConfirm OfferDraw AcceptDraw DeclineDraw Takeback Abort
        ClaimVictory Flip Live Chat Send Analyse CloseTab AutoQueen Premove
        Illegal NotYourTurn Promote
    }
    variable OnlineControls {
        resign actions.resign Resign draw actions.draw OfferDraw
        takeback actions.takeback Takeback abort actions.abort Abort
        claim actions.claim ClaimVictory flip actions.flip Flip live live Live
        accept offer.accept AcceptDraw decline offer.decline DeclineDraw
        analyse result.analyse Analyse close result.close CloseTab
        chat chat.send Send autoqueen autoqueen AutoQueen
    }

	proc ready {} {
		set deadline [expr {[clock milliseconds] + 20000}]
		while {![info exists ::application::Vars(ready)] || !$::application::Vars(ready)} {
			update
			if {[clock milliseconds] > $deadline} { error {startup timed out} }
			after 10
		}
		update
		catch { destroy .tipoftheday }
		update
	}

	proc get {var} {
		if {![info exists ::$var]} { return "" }
		return [set ::$var]
	}

	# Every key the six catalogs must translate, as a fully qualified
	# variable name. The English values are the fallback baseline.
	proc keys {} {
		variable AppKeys
		variable AskKeys
		variable MenuKeys
		variable TdKeys
        variable OnlineKeys
		set out {}
		foreach k $AppKeys { lappend out ::application::mc::$k }
		foreach k $MenuKeys { lappend out ::menu::mc::$k }
		foreach k $AskKeys { lappend out ::application::ask::mc::$k }
		foreach k $TdKeys { lappend out ::td::actions::mc::$k }
        foreach k $OnlineKeys { lappend out ::online::view::mc::$k }
		return $out
	}

	# Returns {missingKeys englishFallbacks}; a language that does not
	# define a key leaves the previous value in place, so load English
	# first and compare.
	proc catalogCheck {lang} {
		::mc::setLang en
		set english [dict create]
		foreach var [keys] { dict set english $var [get $var] }
		::mc::setLang $lang
		set missing {}
		set same {}
		foreach var [keys] {
			set value [get $var]
			if {$value eq ""} {
				lappend missing $var
			} elseif {$value eq [dict get $english $var]} {
				lappend same $var
			}
		}
		list $missing $same
	}

	proc tdLabels {} {
		variable TdIds
		set out {}
		foreach id $TdIds { lappend out [dict get [::action::get $id] label] }
		return $out
	}
}

# The app bundle bakes in the installed share directory. Read the
# catalogs of this worktree instead, so the test verifies what we are
# about to commit rather than a stale install.
set ::scidb::test::seal::savedShare $::scidb::dir::share
set ::scidb::test::seal::worktreeShare [file normalize [file join \
	[file dirname [file normalize [info script]]] .. tcl]]
if {[file isdirectory [file join $::scidb::test::seal::worktreeShare lang]]} {
	set ::scidb::dir::share $::scidb::test::seal::worktreeShare
}

tcltest::test seal-catalogs-define-every-key {all six catalogs translate the new labels} -body {
	::scidb::test::seal::ready
	set saved $::mc::langID
	set report {}
	foreach lang {de es it hu sv} {
		lassign [::scidb::test::seal::catalogCheck $lang] missing same
		lappend report [list $lang $missing $same]
	}
	::mc::setLang $saved
	foreach row $report {
		if {[llength [lindex $row 1]] || [llength [lindex $row 2]]} {
			puts "  [lindex $row 0]: missing=[lindex $row 1] english=[lindex $row 2]"
		}
	}
	set bad 0
	foreach row $report {
		if {[llength [lindex $row 1]] || [llength [lindex $row 2]]} { incr bad }
	}
	set bad
} -result {0}

tcltest::test seal-donate-strip-relabels-and-reflows {the Donate button re-reads the catalog and the strip is re-placed} -body {
	::scidb::test::seal::ready
	set saved $::mc::langID
	set w $::application::Vars(donate)
	if {![winfo exists $w]} { error "no Donate button at $w" }
	::menu::SwitchLanguage English
	update idletasks
	set beforeText [$w cget -text]
	set beforeX [winfo x $w]
	set beforeWidth [winfo width $w]
	::menu::SwitchLanguage Deutsch
	update idletasks
	set afterText [$w cget -text]
	set afterX [winfo x $w]
	set afterWidth [winfo width $w]
	set tip $::application::mc::DonateTip
	# PlaceMenues keeps the button two pixels left of the drop-down: that
	# invariant can only hold if the strip was re-placed after the new
	# width was read.
	set main $::application::Vars(menu:main)
	set gap [expr {[winfo x $main] - ([winfo x $w] + [winfo reqwidth $w])}]
	::mc::setLang $saved
	update idletasks
	# the German button is a different width and must move left of the
	# drop-down; the same text would mean the binding never read the catalog
	list $beforeText $afterText [expr {$afterText ne $beforeText}] \
		[expr {$afterX ne $beforeX || $afterWidth ne $beforeWidth}] $gap $tip
} -result [list "\u2665 Donate" "Spenden" 1 1 2 \
	"Unterstützen Sie Chesswiz mit einer Spende (PayPal oder Ko-fi)"]

tcltest::test seal-menu-rows-follow-the-language {the Donate and Tournament Director rows are re-read at switch time} -body {
	::scidb::test::seal::ready
	set saved $::mc::langID
	::menu::SwitchLanguage English
	::menu::RegisterExtras
	set en [list [::menu::MC Donate] [::menu::MC TournamentDirector] \
		[dict get [::action::get menu.help.donate] label]]
	::menu::SwitchLanguage Deutsch
	::menu::RegisterExtras
	set de [list [::menu::MC Donate] [::menu::MC TournamentDirector] \
		[dict get [::action::get menu.help.donate] label]]
	::mc::setLang $saved
	list $en $de
} -result [list [list "Donate" "Tournament Director\u2026" "Donate"] \
	[list "Spenden" "Turnierleiter..." "Spenden"]]

tcltest::test seal-td-action-labels-relabel {every td.* action label is read from the catalog at event time} -body {
	::scidb::test::seal::ready
	set saved $::mc::langID
	::mc::setLang en
	set en [::scidb::test::seal::tdLabels]
	::mc::setLang de
	set de [::scidb::test::seal::tdLabels]
	::mc::setLang $saved
	list [llength $en] [expr {[lsearch -exact $en "Create tournament"] >= 0}] \
		[expr {[lsearch -exact $de "Turnier erstellen"] >= 0}] \
		[expr {[lsearch -exact $en "Turnier erstellen"] < 0}] \
		[expr {[lsearch -exact $de "Create tournament"] < 0}]
} -result {20 1 1 1 1}

tcltest::test seal-assistant-preferences-relabel {the Assistant preferences relabel on a switch} -body {
	::scidb::test::seal::ready
	set saved $::mc::langID
	::mc::setLang en
	catch { destroy .application.assistantPreferences }
	::application::ask::Preferences
	set dlg .application.assistantPreferences
	set startup $dlg.content.startup
	set sherpa $dlg.content.sherpaCli.label
	set hotwords $dlg.content.hotwords.label
	set before [list [$startup cget -text] [$sherpa cget -text] [$hotwords cget -text]]
	::mc::setLang de
	update idletasks
	set after [list [$startup cget -text] [$sherpa cget -text] [$hotwords cget -text]]
	destroy $dlg
	::mc::setLang $saved
	list $before $after
} -result [list [list "Show assistant at startup" "sherpa-onnx-offline path" "Hotwords file (optional)"] \
	[list "Assistent beim Start anzeigen" "Pfad zu sherpa-onnx-offline" "Hotwords-Datei (optional)"]]

tcltest::test seal-language-return-restores-english {switching back to English restores every English label} -body {
	::scidb::test::seal::ready
	set saved $::mc::langID
	::mc::setLang en
	set english $::application::mc::Donate
	::mc::setLang de
	::mc::setLang en
	set back $::application::mc::Donate
	set td $::td::actions::mc::Create
	::mc::setLang $saved
	list $english $back $td
} -result [list "\u2665 Donate" "\u2665 Donate" "Create tournament"]

tcltest::test seal-online-live-controls {all 13 actions and existing controls follow every language and return to English} -setup {
    ::scidb::test::seal::ready
    set saved $::mc::langID
    ::mc::setLang en
    # Bound the host like the real Online window; otherwise Aqua geometry
    # propagation can continuously resize the responsive board.
    toplevel .sealOnline
    wm geometry .sealOnline 900x650
    ::online::view::create .sealOnline.view {error {unexpected backend call}} w
    pack .sealOnline.view -fill both -expand 1
    update
    set english {}
    foreach key $::scidb::test::seal::OnlineKeys {
        dict set english $key [set ::online::view::mc::$key]
    }
} -body {
    set bad {}
    foreach lang {de es it hu sv en} {
        ::mc::setLang $lang
        update idletasks
        foreach {id path key} $::scidb::test::seal::OnlineControls {
            set expected [set ::online::view::mc::$key]
            set label [dict get [::action::get toolbar.online.$id] label]
            set text [.sealOnline.view.side.$path cget -text]
            if {$text ne $expected || $label ne $expected} {
                lappend bad [list $lang $id $expected $label $text]
            }
            if {$lang ne "en" && $expected eq [dict get $english $key]} {
                lappend bad [list $lang $id untranslated]
            }
        }
        if {[.sealOnline.view.side.chat cget -text] ne $::online::view::mc::Chat} {
            lappend bad [list $lang chat-title]
        }
    }
    foreach key $::scidb::test::seal::OnlineKeys {
        if {[set ::online::view::mc::$key] ne [dict get $english $key]} {
            lappend bad [list en $key not-restored]
        }
    }
    list [expr {[llength $::scidb::test::seal::OnlineControls] / 3}] $bad
} -cleanup {
    destroy .sealOnline
    ::mc::setLang $saved
} -result {13 {}}

tcltest::test seal-additional-menu-labels {the additional menu actions translate and reset} -setup {
    set saved $::mc::langID
} -body {
    set results {}
    foreach lang {en de en} {
        ::mc::setLang $lang
        ::menu::RegisterExtras
        set labels {}
        foreach id {view.focus_follows_size opening_line engine_play} {
            lappend labels [dict get [::action::get $id] label]
        }
        lappend results $labels
    }
    list [expr {[lindex $results 0] eq [lindex $results 2]}] [lindex $results 1]
} -cleanup {
    ::mc::setLang $saved
} -result [list 1 [list "Fokus folgt der Größe beim Ändern der Fenstergröße" \
    "Eine Eröffnungsvariante nachschlagen" "Die Engine spielen lassen"]]

# This file reads the worktree catalogs instead of the installed share
# directory. Menu files share one process, so put the installed path back:
# later player-card HTML resolves its scripts and CSS through it.
if {[info exists ::scidb::test::seal::savedShare]} {
	set ::scidb::dir::share $::scidb::test::seal::savedShare
}

::tcltest::cleanupTests
