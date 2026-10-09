# ======================================================================
# Scidb App Test — runtime regressions from the 2026-09-24 Tcl audit
#
# Each case exercises a code path that used to raise only when reached
# (undefined variable, invalid subcommand, wrong option name).
# ======================================================================

package require tcltest 2.5

tcltest::test audit-log-exists {::log::exists sees the namespace Log variable} -body {
	expr {[::log::exists] in {0 1}}
} -result 1

tcltest::test audit-twm-frozen-named {frozen? with a twm argument reads Frozen, not frozen} -body {
	::twm::frozen? .no-such-twm
} -result 0

tcltest::test audit-choosefont-geometry {-geometry is stored in the parsed options} -body {
	dict get [::dialog::choosefont::ParseArguments yes -geometry 300x200] geometry
} -result 300x200

tcltest::test audit-choosecolor-usercolors {-usercolors is accepted and normalised to rows of six} -body {
	set ::auditUserColors {red}
	::dialog::choosecolor::ParseArguments -usercolors ::auditUserColors
	llength $::auditUserColors
} -cleanup {
	unset -nocomplain ::auditUserColors
} -result 6

tcltest::test audit-choosecolor-bad-usercolor {an invalid user colour reports the option name} -body {
	set ::auditUserColors {no-such-colour}
	list [catch {::dialog::choosecolor::ParseArguments -usercolors ::auditUserColors} msg] $msg
} -cleanup {
	unset -nocomplain ::auditUserColors
} -result {1 {option "-usercolors": invalid color "no-such-colour"}}

tcltest::test audit-openingreport-fonts {opening-report text tags can be (re)created} -body {
	set t [text .auditOpeningReport]
	# force the create path, including deleting fonts left by earlier calls
	set ::application::tree::openingreport::Fonts {}
	::application::tree::openingreport::setupTextTags $t
	set ::application::tree::openingreport::Fonts {}
	::application::tree::openingreport::setupTextTags $t
	expr {[llength $::application::tree::openingreport::Fonts] > 0}
} -cleanup {
	destroy .auditOpeningReport
} -result 1

tcltest::test audit-trial-mode {trial mode switches on and off again (push and pop take no position)} -body {
	set fen [::scidb::pos::fen]
	::game::flipTrialMode
	set on [::game::trialMode?]
	::game::flipTrialMode
	list $on [::game::trialMode?] [expr {[::scidb::pos::fen] eq $fen}]
} -result {1 0 1}

tcltest::test audit-save-line-keeps-board-game {saving the line to a repertoire works on a copy, not on the game on the board} -setup {
	rename ::application::pgn::saveGame ::auditSaveGame
	proc ::application::pgn::saveGame {mode base} {
		set ::auditSaved [list [::scidb::game::current] [::scidb::game::toPGN modified]]
	}
	set position [::scidb::game::current]
	::scidb::game::move e4; ::scidb::game::go 1
	::scidb::game::move e5; ::scidb::game::go 1
	::scidb::game::move Nf3; ::scidb::game::go 1
	::scidb::game::go -1
} -body {
	set before [::scidb::game::toPGN modified]
	set fen [::scidb::pos::fen]
	::application::database::saveCurrentLineToRepertoire .application base
	lassign $::auditSaved savedAt savedPgn
	list [expr {$savedAt != $position}] [regexp {1\.e4 e5 \*} $savedPgn] \
		[expr {[::scidb::game::toPGN modified] eq $before}] [expr {[::scidb::pos::fen] eq $fen}] \
		[::scidb::game::current]
} -cleanup {
	rename ::application::pgn::saveGame {}
	rename ::auditSaveGame ::application::pgn::saveGame
	unset -nocomplain ::auditSaved
} -result [list 1 1 1 1 [::scidb::game::current]]

tcltest::test audit-game-tags-position-option {game::tags takes a position and -userSuppliedOnly together} -body {
	set pos [::scidb::game::current]
	list [catch { ::scidb::game::tags $pos -userSuppliedOnly yes } r] [catch { ::scidb::game::tags $pos } r] \
		[catch { ::scidb::game::tags -userSuppliedOnly no } r] [catch { ::scidb::game::tags $pos -userSuppliedOnly yes extra } r]
} -result {0 0 0 1}

tcltest::test audit-game-clear-fics {game::clear sets up the FICS start positions the board menu offers} -body {
	set knights [catch { ::scidb::game::clear 4005 } r]
	set fen [lindex [::scidb::pos::fen] 0]
	set bad [catch { ::scidb::game::clear 4016 } r]
	::scidb::game::clear 518
	list $knights [regexp {^[nNkKpP1-8/]+$} $fen] $bad [lindex [::scidb::pos::fen] 0]
} -result {0 1 1 rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR}

tcltest::test audit-toolbar-orientation {a toolbar moved round the sides and back again keeps working} -body {
	::application::switchTab board
	update
	set toolbar ""
	foreach key [array names ::toolbar::Specs side:*] {
		set tb [string range $key 5 end]
		if {[string match *__tb__* $tb] && [winfo exists $tb] && $::toolbar::Specs(enabled:$tb)} { set toolbar $tb; break }
	}
	if {$toolbar eq ""} { return "no toolbar" }
	set home $::toolbar::Specs(side:$toolbar)
	set errors {}
	set side $home
	foreach next {bottom top left right bottom top left right} {
		if {[catch { ::toolbar::MoveCmd $toolbar $next $side } err]} { lappend errors "$side->$next: $err" }
		set side $next
		update
	}
	catch { ::toolbar::MoveCmd $toolbar $home $side }
	update
	set errors
} -result {}

tcltest::test audit-boardgames-gone {a game-list change after the board games pane is gone is ignored} -body {
	set ns ::application::boardgames
	set saved [list [info exists ${ns}::Table] [expr {[info exists ${ns}::Table] ? [set ${ns}::Table] : ""}] \
		[expr {[info exists ${ns}::current] ? [set ${ns}::current] : ""}]]
	set base [::scidb::db::get name]
	set ${ns}::current [list $base Normal]
	set ${ns}::Table .no.such.pane.table
	set stale [catch { ${ns}::GameListChanged 0 $base Normal } err]
	unset ${ns}::Table
	set closed [catch { ${ns}::GameListChanged 0 $base Normal; ${ns}::DatabaseSwitched $base Normal } err]
	lassign $saved had table current
	if {$had} { set ${ns}::Table $table }
	if {$current ne ""} { set ${ns}::current $current }
	list $stale $closed
} -result {0 0}

tcltest::test audit-transpose-trial {a game with castling transposes, and trial mode is left cleanly} -body {
	::application::switchTab board
	set reply [::application::assistant::runTool set_position {moves {1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5 4.O-O Nf6 5.Re1}}]
	if {[string match "error:*" $reply]} { return $reply }
	update
	set out {}
	foreach step {
		{::scidb::game::transpose true}
		{::scidb::game::transpose true}
		{::game::flipTrialMode}
		{::application::assistant::runTool set_position {moves {1.d4}}}
		{::game::flipTrialMode}
	} {
		lappend out [catch { uplevel #0 $step; update } err]
	}
	::scidb::game::clear 518
	::scidb::game::modified [::scidb::game::current] no
	set out
} -result {0 0 0 0 0}

tcltest::test audit-tcombobox-icon-after-close {forgetting an icon must not raise when the combobox is gone} -setup {
	set ::auditBgErrors {}
	rename ::scidb::bgerror ::scidb::auditBgErrorSaved
	proc ::scidb::bgerror {err args} { lappend ::auditBgErrors $err }
	image create photo ::auditIconImg -width 8 -height 8
} -body {
	ttk::tcombobox .auditTcb -placeicon 1 -state readonly -showcolumns name -format "%1"
	.auditTcb addcol image -id flag
	.auditTcb addcol text  -id name
	.auditTcb listinsert [list one ::auditIconImg]
	.auditTcb resize
	pack .auditTcb
	update
	# icon placed; now forget it (the figurines box does this in
	# ShowCountry) and close the dialog before the idle timer fires
	.auditTcb placeicon ::auditIconImg
	update
	.auditTcb forgeticon
	destroy .auditTcb
	after 1500 {set ::auditTcbDone 1}
	vwait ::auditTcbDone
	set ::auditBgErrors
} -cleanup {
	rename ::scidb::bgerror {}
	rename ::scidb::auditBgErrorSaved ::scidb::bgerror
	interp bgerror {} ::scidb::bgerror
	image delete ::auditIconImg
	unset -nocomplain ::auditBgErrors ::auditTcbDone
	catch { destroy .auditTcb }
} -result {}

tcltest::test audit-combobox-focusout-gone {a combobox that loses the focus and is destroyed raises nothing later} -setup {
	set ::auditBgErrors {}
	rename ::scidb::bgerror ::scidb::auditBgErrorSaved
	proc ::scidb::bgerror {err args} { lappend ::auditBgErrors $err }
} -body {
	toplevel .auditCb
	ttk::combobox .auditCb.c -values {a b} -exportselection 0
	pack .auditCb.c
	update
	focus -force .auditCb.c
	update
	event generate .auditCb.c <FocusOut>
	destroy .auditCb
	update
	set ::auditBgErrors
} -cleanup {
	rename ::scidb::bgerror {}
	rename ::scidb::auditBgErrorSaved ::scidb::bgerror
	interp bgerror {} ::scidb::bgerror
	catch { destroy .auditCb }
	unset -nocomplain ::auditBgErrors
} -result {}

tcltest::test audit-board3d-forward-once {a key forwarded from the focused 3D pane is not forwarded back forever} -body {
	toplevel .auditFwd
	canvas .auditFwd.c
	frame .auditFwd.w -takefocus 1 -width 50 -height 50
	pack .auditFwd.c .auditFwd.w
	bind .auditFwd.w <KeyPress> [list ::board3d::ForwardKey .auditFwd.c %K %s]
	update
	focus -force .auditFwd.w
	update
	set rc [catch { ::board3d::ForwardKey .auditFwd.c Escape 0 } err]
	destroy .auditFwd
	list $rc $::board3d::Forwarding
} -result {0 0}

tcltest::test audit-dropdownbutton-clone {a dropdown button can be cloned (a toolbar made floating)} -body {
	toplevel .auditDd
	::dropdownbutton .auditDd.b -text x -background grey -activebackground white
	set rc [catch { .auditDd.b clone .auditDd.c } err]
	set exists [winfo exists .auditDd.c]
	destroy .auditDd
	list $rc $exists
} -result {0 1}


tcltest::test audit-paste-dialog-closed-early {a paste dialog closed while it is built does not fail} -setup {
	::application::pgn::ensureScratchGame
	set frame $::application::pgn::Vars(frame:$::application::pgn::Vars(position))
	# the gamebar closing the position runs during openEdit's update
	rename ::update ::auditRealUpdate
	proc ::update {args} {
		if {[lindex [info level -1] 0] eq "::import::openEdit"} {
			foreach w [info commands $::auditFrame.importOnePgnGame*] { destroy $w }
		}
		uplevel 1 ::auditRealUpdate $args
	}
	set ::auditFrame $frame
} -body {
	list [catch {::import::openEdit $frame 0 -mode game -variant Normal} err] $err
} -cleanup {
	rename ::update {}
	rename ::auditRealUpdate ::update
	unset -nocomplain ::auditFrame
} -result {0 {}}

tcltest::test audit-uri-list-not-a-list {dropped text that is no Tcl list is read line by line} -body {
	set r [::fsbox::parseUriList "file:///a.pgn\r\n\{b.pgn"]
	list [lindex $r 1] [lindex $r 3]
} -result {/a.pgn \{b.pgn}

tcltest::test audit-media-update-after-close {a game switch after the media pane has closed does nothing} -setup {
	set saved $::application::media::Priv(tree)
	set ::application::media::Priv(tree) .noSuchMediaTree
} -body {
	list [catch {::application::media::Update 0} msg] $msg
} -cleanup {
	set ::application::media::Priv(tree) $saved
} -result {0 {}}

tcltest::test audit-searchentry-clone {a toolbar holding a search entry can be made floating} -body {
	toplevel .auditSe
	::searchentry .auditSe.e
	set rc [catch { ::toolbar::MakeClone .auditSe .auditSe .auditSe.c .auditSe.e } err]
	set exists [winfo exists .auditSe.c]
	destroy .auditSe
	list $rc $exists
} -cleanup {
	array unset ::toolbar::Specs clone:.auditSe:*
} -result {0 1}

tcltest::test audit-analysis-pane-beside-floating {a second analysis pane opens while the first is undocked} -setup {
	::application::switchTab board
	set twm [::application::twm board]
	set uid analysis:[expr {$::application::Vars(terminal:number) + 1}]
	::application::assistant::DoPane undock analysis:1
	update idletasks
} -body {
	# the clone failed on the floating window ("bad option fullscreen") and,
	# once past that, was never built
	set rc [catch { ::application::newAnalysisPane 9 } msg]
	update idletasks
	list $rc [info exists ::application::analysis::NumberToTree(9)]
} -cleanup {
	catch { $twm close [$twm leaf $uid] }
	update idletasks
	catch { ::application::assistant::DoPane dock analysis:1 }
	update idletasks
} -result {0 1}

tcltest::test audit-cbh-corrupt-count {a ChessBase index whose game count is corrupt is refused at once} -setup {
	set root [file join [::tcltest::temporaryDirectory] corrupt-[pid]]
	# a valid header record that claims no records at all; the count less
	# one wrapped round to four billion games
	set fh [open $root.cbh wb]
	puts -nonewline $fh [binary format c6Iu1x36 {0 0 0x2c 0 0x2e 1} 0]
	close $fh
	foreach ext {cbg cba cbp cbt cbc cbs cbe} { close [open $root.$ext wb] }
	proc auditCbhCb {cmd args} { switch -- $cmd { ticks { return 100 } interrupted? { return 0 } } ; return }
} -body {
	set rc [catch { ::scidb::db::load $root.cbh auditCbhCb progress -readonly yes } msg]
	list $rc [string match "*Corrupted*" $msg]
} -cleanup {
	catch { ::scidb::db::close $root.cbh }
	rename auditCbhCb {}
	foreach f [glob -nocomplain $root.*] { file delete $f }
} -result {1 1}

tcltest::test audit-treeview-rows-fit-font {tree rows are as tall as the font needs} -body {
	expr {[ttk::style lookup Treeview -rowheight] >= [font metrics TkDefaultFont -linespace]}
} -result 1

tcltest::test audit-prep-opening-without-line {an ECO code with no main line says so instead of leaving the cell empty} -body {
	ttk::treeview .auditPrep -columns {count eco line} -show headings
	::application::database::player::PopulatePrepOpenings .auditPrep {{28 A00 {}} {26 A45 {1.d4 Nf6}}}
	set lines [lmap item [.auditPrep children {}] { lindex [.auditPrep item $item -values] 2 }]
	destroy .auditPrep
	set lines
} -result {{(various first moves)} {1.d4 Nf6}}

tcltest::test audit-nested-error-not-sticky {a nested scidb error caught by a progress callback does not fail the outer command} -setup {
	set sci [file join [::tcltest::temporaryDirectory] nested-[pid].sci]
	proc auditNop {args} {}
	::scidb::db::new $sci Normal [::application::database::lookupType OpeningsWhite]
	::scidb::db::attach $sci $sci
	::scidb::db::save $sci auditNop {}
	::scidb::db::close $sci
	proc auditCb {cmd args} {
		switch -- $cmd {
			ticks { return 100 }
			interrupted? { return 0 }
			start { catch {::scidb::db::count no-such-subcommand} }
		}
		return
	}
} -body {
	# safeCall used to keep the nested error code, so the load reported its
	# own result, the database type "OpeningsWhite", as an error message
	list [catch {::scidb::db::load $sci auditCb .application} msg] $msg
} -cleanup {
	catch {::scidb::db::close $sci}
	rename auditCb {}; rename auditNop {}
	foreach f [glob -nocomplain [file rootname $sci].*] { file delete $f }
} -result {0 OpeningsWhite}

tcltest::test audit-variation-leave-on-mainline {asking for or leaving the variation on the main line answers 0 instead of failing} -body {
	::scidb::game::moveto [::scidb::game::position startKey]
	list [catch {::scidb::game::variation current} a] $a \
		[catch {::scidb::game::variation leave} b] $b \
		[::scidb::game::position isMainline?]
} -result {0 0 0 0 1}

tcltest::test audit-variation-number-out-of-range {a variation number the move does not have is refused, not a precondition failure} -body {
	::scidb::game::moveto [::scidb::game::position startKey]
	lmap sub {first promote remove insert length} {
		catch {::scidb::game::variation $sub 3}
		set ::scidb::intern::errmsg
	}
} -match glob -result {{*invalid variation number 3, the move has*} {*invalid variation number 3,*} {*invalid variation number 3,*} {*invalid variation number 3,*} {*invalid variation number 3,*}}

tcltest::test audit-image-missing-argument {an image command missing its last argument is refused, not read past the end} -body {
	lmap sub {border copy grayscale colorcube} {
		list [catch {::scidb::tk::image $sub} m] [string match "wrong # args*" $m]
	}
} -result {{1 1} {1 1} {1 1} {1 1}}

tcltest::test audit-x11-region-bad-number {a bad coordinate for x11 region is an error, not an abort} -body {
	list [catch {::scidb::tk::x11 region {} {} nosuchphoto}] [winfo exists .]
} -result {1 1}

tcltest::test audit-setup-nags-negative {a negative NAG in the options is refused, not a bitset overrun} -body {
	set r [list [catch {::scidb::game::setupNags {-1}} m] $m]
	::scidb::game::setupNags {}
	set r
} -result {1 {::scidb::game::setupNags: invalid NAG '-1'}}

tcltest::test audit-user-dir-not-from-program-name {the user directory is named after the installation, and search presets live in it} -body {
	set ns ::application::database::searchPresets
	list [expr {[info exists ::env(SCIDB_USERDIR)] || [file tail $::scidb::dir::user] eq ".scidb-beta"}] \
		[expr {[file dirname [set ${ns}::filename]] eq $::scidb::dir::user}]
} -result {1 1}

tcltest::cleanupTests
