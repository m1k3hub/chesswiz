# ======================================================================
# Labelled error groups for calibrating the triage classifier.
#
# The first 30 come from the error log and its triaged file; the rest
# are hand-written. Reviewed 2026-10-06 by Claude at the user's request
# (not yet by a person). Each case is
# {state gold}: state is ::application::triage::GroupText of the group,
# exactly what the classifier sees; gold is bug, environment, user or noise.
# The comment above each case gives its id and who labelled it before (llm =
# the language model; classifier = settled by System One, so not evidence).
# Relabelled cases say why. calibrate-systemone.tcl refuses
# --features triage until TriageReviewed is 1.
#
# About 40 per class. Paths in the logged states are anonymised.
# ======================================================================

namespace eval ::scidb::calibrate {
	variable TriageReviewed 1
}

# The state GroupText gives a group seen once.
proc ::scidb::calibrate::Case {source message detail gold} {
	set detail [string map {\\n \n} $detail]
	return [list "source: $source\noccurrences: 1 (first 2026-10-01 12:00:00, last 2026-10-01 12:00:00)\nmessage: $message\ndetail:\n$detail" $gold]
}

proc ::scidb::calibrate::TriageCases {} {
	set cases {}
	# 9b37e61e llm: environment -> user. was environment: the player is not in that event, a request the app rightly refused
	lappend cases {{source: assistant
occurrences: 1 (first 2026-09-25 22:04:43, last 2026-09-25 22:04:43)
message: prepare_against: no player matching 'Carlsen' in Festival Biel 2015
detail:
no player matching 'Carlsen' in Festival Biel 2015
    while executing
"error "no player matching '$text' in [::util::databaseName $base no]" "
    (procedure "ResolvePlayer" line 7)
    invoked from within
"ResolvePlayer $base $variant $name"
    (procedure "::application::assistant::DoPrepareAgainst" line 8)
    invoked from within
"{*}$handler {*}[dict values $checked]"} user}
	# 1e7bb5c1 llm: environment -> user. was environment: '-tc' is no Scidb option, so the argument was taken for a file name
	lappend cases {{source: dialog
occurrences: 2 (first 2026-09-27 06:41:44, last 2026-09-27 07:06:44)
message: Cannot open file '/home/user/src/scidb/-tc'.
detail:
} user}
	# 1a579361 llm: bug
	lappend cases {{source: background
occurrences: 1 (first 2026-09-27 18:56:27, last 2026-09-27 18:56:27)
message: Item glm-5.3-flash:cloud] not found
detail:
Item glm-5.3-flash:cloud] not found
    while executing
"$tree see $Priv(name)]"
    (procedure "Fill" line 22)
    invoked from within
"Fill"
    (procedure "::application::ai::models::show" line 105)
    invoked from within
"::application::ai::models::show .application"
    invoked from within
"$m.__menu__ $command {*}$args"
    (procedure "::tk::menu::WidgetProc" line 40)
    invoked from within
"::tk::menu::WidgetProc .application.nb.menu_main.entries.mExtras $command {*}$args"
    (procedure ".application.nb.menu_main.entries.mExtras" line 1)
    invoked from within
".application.nb.menu_main.entries.mExtras invoke active"
    ("uplevel" body line 1)
    invoked from within
"uplevel #0 [list $w invoke active]"
    (procedure "tk::MenuInvoke" line 61)
    invoked from within
"tk::MenuInvoke .application.nb.menu_main.entries.mExtras 1"
    (command bound to event)} bug}
	# b5dfbcad llm: environment -> bug. was environment: applySettings passes \[lindex \[setting classifier\] 1\], the word 'settings'
	lappend cases {source:\ background\noccurrences:\ 1\ (first\ 2026-09-27\ 18:57:41,\ last\ 2026-09-27\ 18:57:41)\nmessage:\ unknown\ System\ One\ backend\ 'settings'\ (kev,\ simple-jev,\ plumb,\ jev,\ vercel\ or\ off)\ndetail:\nunknown\ System\ One\ backend\ 'settings'\ (kev,\ simple-jev,\ plumb,\ jev,\ vercel\ or\ off)\n\ \ \ \ while\ executing\n\"error\ \"unknown\ System\ One\ backend\ '\$value'\ (\[join\ \[dict\ keys\ \$Backends\]\ \{,\ \}\]\ or\ off)\"\"\n\ \ \ \ (procedure\ \"::ai::systemone::configure\"\ line\ 9)\n\ \ \ \ invoked\ from\ within\n\"::ai::systemone::configure\ -backend\ \[lindex\ \[setting\ classifier\]\ 1\]\"\n\ \ \ \ (procedure\ \"applySettings\"\ line\ 8)\n\ \ \ \ invoked\ from\ within\n\"applySettings\"\n\ \ \ \ (procedure\ \"::application::ai::chooseClassifier\"\ line\ 5)\n\ \ \ \ invoked\ from\ within\n\"::application::ai::chooseClassifier\ \$Priv(classifier)\"\n\ \ \ \ (procedure\ \"Apply\"\ line\ 8)\n\ \ \ \ invoked\ from\ within\n\"Apply\"\n\ \ \ \ (in\ namespace\ inscope\ \"::application::ai::models\"\ script\ line\ 1)\n\ \ \ \ invoked\ from\ within\n\"::namespace\ inscope\ ::application::ai::models\ Apply\"\n\ \ \ \ invoked\ from\ within\n\".application.__aimodels__.ok\ invoke\ \"\n\ \ \ \ invoked\ from\ within\n\".application.__aimodels__.ok\ instate\ !disabled\ \{\ .application.__aimodels__.ok\ invoke\ \}\ \"\n\ \ \ \ invoked\ from\ within\n\".application.__aimodels__.ok\ instate\ pressed\ \{\ .application.__aimodels__.ok\ state\ !pressed\;\ .application.__aimodels__.ok\ instate\ !disabled\ \{\ .applicat...\"\n\ \ \ \ (command\ bound\ to\ event) bug}
	# 899185ed llm: bug
	lappend cases {{source: background
occurrences: 1 (first 2026-09-27 22:01:51, last 2026-09-27 22:01:51)
message: Item deepseek-v4.1-flash:cloud] not found
detail:
Item deepseek-v4.1-flash:cloud] not found
    while executing
"$tree see $Priv(name)]"
    (procedure "Fill" line 22)
    invoked from within
"Fill"
    (procedure "::application::ai::models::show" line 105)
    invoked from within
"::application::ai::models::show .application"
    invoked from within
"$m.__menu__ $command {*}$args"
    (procedure "::tk::menu::WidgetProc" line 40)
    invoked from within
"::tk::menu::WidgetProc .application.nb.menu_main.entries.mExtras $command {*}$args"
    (procedure ".application.nb.menu_main.entries.mExtras" line 1)
    invoked from within
".application.nb.menu_main.entries.mExtras invoke active"
    ("uplevel" body line 1)
    invoked from within
"uplevel #0 [list $w invoke active]"
    (procedure "tk::MenuInvoke" line 61)
    invoked from within
"tk::MenuInvoke .application.nb.menu_main.entries.mExtras 1"
    (command bound to event)} bug}
	# fa6c8770 classifier: environment -> bug. was environment (classifier): an empty window path is a code defect
	lappend cases {{source: background
occurrences: 4 (first 2026-09-27 22:53:31, last 2026-09-30 13:41:23)
message: bad window path name ""
detail:
bad window path name ""
    while executing
"__place_winfo_orig toplevel {}"
    ("uplevel" body line 1)
    invoked from within
"uplevel 1 __place_winfo_orig $args"
    (procedure "winfo" line 39)
    invoked from within
"winfo toplevel $parent"
    (procedure "addRecentlyUsedToMenu" line 5)
    invoked from within
"addRecentlyUsedToMenu [winfo parent [winfo parent $parent]] $m"
    (procedure "::application::database::PopupMenu" line 138)
    invoked from within
"::application::database::PopupMenu .application 100 100 $base"
    ("after" script)} bug}
	# afa9ecb7 llm: bug
	lappend cases {{source: background
occurrences: 1 (first 2026-09-27 22:55:50, last 2026-09-27 22:55:50)
message: invalid command name ".application.__aimodels__.top.clist.tree"
detail:
invalid command name ".application.__aimodels__.top.clist.tree"
    while executing
"__unknown__orig {*}$args"
    (procedure "::unknown" line 12)
    invoked from within
"$w identify row $x $y"
    (procedure "ttk::treeview::DoubleClick" line 2)
    invoked from within
"ttk::treeview::DoubleClick .application.__aimodels__.top.clist.tree 44 88 "
    (command bound to event)} bug}
	# d435abbb llm: bug
	lappend cases {{source: background
occurrences: 1 (first 2026-09-27 22:57:33, last 2026-09-27 22:57:33)
message: list element in quotes followed by ":" instead of space
detail:
list element in quotes followed by ":" instead of space
    while executing
"llength $errorInfo"
    (procedure "Dock" line 22)
    invoked from within
"Dock $twm $frame"
    (procedure "::twm::HeaderRelease" line 42)
    invoked from within
"::twm::HeaderRelease .application.nb.board .application.nb.board.__frame__assistant__6"
    (command bound to event)} bug}
	# bd145bca classifier: environment -> bug. was environment (classifier): ::twm::HeaderPress grabs without checking the frame is viewable
	lappend cases {{source: background
occurrences: 1 (first 2026-09-27 22:58:18, last 2026-09-27 22:58:18)
message: grab failed: window not viewable
detail:
grab failed: window not viewable
    while executing
"__grab__shadow {*}$args"
    (procedure "grab" line 5)
    invoked from within
"grab $w"
    (procedure "ttk::grabWindow" line 3)
    invoked from within
"ttk::grabWindow $frame"
    (procedure "::twm::HeaderPress" line 25)
    invoked from within
"::twm::HeaderPress .application.nb.board .application.nb.board.__frame__assistant__6 2059 1187"
    (command bound to event)} bug}
	# 062cc731 llm: bug
	lappend cases {{source: log
occurrences: 4 (first 2026-09-30 13:37:00, last 2026-10-03 15:57:25)
message: Aborted due to an internal error
detail:
} bug}
	# 67cfedc9 llm: bug
	lappend cases {{source: background
occurrences: 3 (first 2026-09-30 17:10:21, last 2026-09-30 17:12:42)
message: can't read "Options(repertoire:db)": no such element in array
detail:
can't read "Options(repertoire:db)": no such element in array
    while executing
"list ToggleNoveltyHighlighting $table $Options(repertoire:db)"
    (procedure "PopupMenu" line 41)
    invoked from within
"PopupMenu .application.nb.board.__frame__tree__4.tree.mw.info.table 566 867"
    (in namespace inscope "::application::tree" script line 1)
    invoked from within
"::namespace inscope ::application::tree {PopupMenu .application.nb.board.__frame__tree__4.tree.mw.info.table 566 867}"
    (command bound to event)} bug}
	# 9bef0fb6 llm: bug
	lappend cases {{source: log
occurrences: 6 (first 2026-09-30 17:10:21, last 2026-10-03 20:53:13)
message: can't read "Options(repertoire:db)": no such element in array
detail:
loadArray1
PopupMenu .application.nb.board.__frame__tree__4.tree.mw.info.table 566 867
::namespace inscope ::application::tree {PopupMenu .application.nb.board.__frame__tree__4.tree.mw.info.table 566 867}
2} bug}
	# 2f827ddf llm: bug
	lappend cases {{source: background
occurrences: 3 (first 2026-09-30 17:10:29, last 2026-09-30 17:12:58)
message: can't read "Options(style:column)": no such variable
detail:
can't read "Options(style:column)": no such variable
    while executing
"::scidb::game::setupStyle  $position  {*}$thresholds  $Options(style:column)  $Options(style:move)  $paragraphSpacing  $showDiagrams  $showMoveInfo  $..."
    (procedure "::pgn::setup::setupStyle" line 30)
    invoked from within
"::pgn::setup::setupStyle browser $position"
    (procedure "::browser::open" line 25)
    invoked from within
"::browser::open $topl $base $variant $info $view $index [{*}$Vars(positioncmd)] "
    ("uplevel" body line 1)
    invoked from within
"uplevel 1 $cmd"
    invoked from within
"::widget::busyOperation  { ::browser::open $topl $base $variant $info $view $index [{*}$Vars(positioncmd)] }"
    (procedure "Open(browse)" line 13)
    invoked from within
"Open(browse) .application.nb.board.__frame__dbgames__3.dbgames.table 24"
    (in namespace inscope "::gamestable" script line 1)
    invoked from within
"::namespace inscope ::gamestable {Open(browse) .application.nb.board.__frame__dbgames__3.dbgames.table 24}"
    invoked from within
"$m.__menu__ $command {*}$args"
    (procedure "::tk::menu::WidgetProc" line 40)
    invoked from within
"::tk::menu::WidgetProc .application.nb.board.__frame__dbgames__3.dbgames.table.top.table.menu $command {*}$args"
    (procedure ".application.nb.board.__frame__dbgames__3.dbgames.table.top...." line 1)
    invoked from within
".application.nb.board.__frame__dbgames__3.dbgames.table.top.table.menu invoke active"
    ("uplevel" body line 1)
    invoked from within
... (35 lines)} bug}
	# 65dc11a0 llm: bug
	lappend cases {{source: log
occurrences: 46 (first 2026-09-30 17:10:29, last 2026-10-03 15:53:05)
message: can't read "Options(style:column)": no such variable
detail:
::widget::busyOperation { ::browser::open $topl $base $variant $info $view $index [{*}$Vars(positioncmd)] }
Open(browse) .application.nb.board.__frame__dbgames__3.dbgames.table 24
::namespace inscope ::gamestable {Open(browse) .application.nb.board.__frame__dbgames__3.dbgames.table 24}
::tk::menu::WidgetProc .application.nb.board.__frame__dbgames__3.dbgames.table.top.table.menu invoke active
::tk::menu::WidgetProc .application.nb.board.__frame__dbgames__3.dbgames.table.top.table.menu invoke active
.application.nb.board.__frame__dbgames__3.dbgames.table.top.table.menu invoke active
1
tk::MenuInvoke .application.nb.board.__frame__dbgames__3.dbgames.table.top.table.menu 1} bug}
	# c2d25d97 llm: noise
	lappend cases {{source: dialog
occurrences: 2 (first 2026-09-30 20:56:35, last 2026-09-30 21:16:47)
message: Engine terminated with exit code 0.
detail:
} noise}
	# 716bc701 llm: noise
	lappend cases {{source: log
occurrences: 2 (first 2026-09-30 20:56:35, last 2026-09-30 21:16:47)
message: Engine terminated with exit code 0.
detail:
} noise}
	# 4600c333 llm: bug
	lappend cases {{source: log
occurrences: 2 (first 2026-09-30 20:56:35, last 2026-09-30 21:16:47)
message: precondition violation: isConnected()
detail:
(func) send
(file) app_engine.cpp:1095
(what) precondition violation: isConnected()
(type) mstl::precondition_violation_exception
=== Backtrace ============================================
 
 
 
 
 
 
 
 
 TclNRRunCallbacks
 
 TclNRRunCallbacks
 
 Tcl_EvalEx
 Tk_BindEvent
 TkBindEventProc
 Tk_HandleEvent
 
 Tcl_ServiceEvent
 Tcl_DoOneEvent
 Tk_MainLoop
 Tk_MainEx
 main
==========================================================
::scidb::engine::kill 0
::engine::kill 1
... (35 lines)} bug}
	# 8a0b206d llm: bug -> environment. was bug: one game of 1.96 million fails to decode -- damaged data, not the decoder
	lappend cases {{source: log
occurrences: 5 (first 2026-10-03 00:17:05, last 2026-10-03 00:25:07)
message: Game 1,964,682: Decoding of this game was not possible
detail:
} environment}
	# 261926ed llm: bug
	lappend cases {{source: log
occurrences: 3 (first 2026-10-03 02:37:00, last 2026-10-03 15:53:04)
message: precondition violation: index < NumberOfVariants
detail:
(func) fromIndex
(file) ../db/db_common.ipp:586
(what) precondition violation: index < NumberOfVariants
(type) mstl::precondition_violation_exception
=== Backtrace ============================================
 
 
 
 
 
 
 
 TclNRRunCallbacks
 
 Tcl_EvalEx
 Tk_BindEvent
 TkBindEventProc
 Tk_HandleEvent
 
 Tcl_ServiceEvent
 Tcl_DoOneEvent
 
 TclNRRunCallbacks
 
 TclNRRunCallbacks
 
 Tcl_EvalEx
 Tk_BindEvent
 TkBindEventProc
 Tk_HandleEvent
... (51 lines)} bug}
	# fb242561 classifier: user
	lappend cases {{source: dialog
occurrences: 17 (first 2026-10-03 15:51:46, last 2026-10-03 15:53:02)
message: ::scidb::view::search rating: invalid rating range
detail:
} user}
	# c73bdeb6 classifier: user
	lappend cases {{source: log
occurrences: 18 (first 2026-10-03 15:51:46, last 2026-10-03 19:29:16)
message: ::scidb::view::search rating: invalid rating range
detail:
} user}
	# ed947856 llm: bug
	lappend cases {source:\ background\noccurrences:\ 44\ (first\ 2026-10-03\ 15:53:04,\ last\ 2026-10-03\ 15:53:05)\nmessage:\ can't\ read\ \"dlg\":\ no\ such\ variable\ndetail:\ncan't\ read\ \"dlg\":\ no\ such\ variable\n\ \ \ \ while\ executing\n\"if\ \{\".plainsearch_home_user_chess_Mega_Database_2010_sciNormal.ask.label\"\ eq\ \"\$dlg\"\}\ \{::namespace\ inscope\ ::application::datab...\"\n\ \ \ \ (command\ bound\ to\ event) bug}
	# a76861c4 llm: bug
	lappend cases {source:\ background\noccurrences:\ 3\ (first\ 2026-10-03\ 15:55:25,\ last\ 2026-10-03\ 15:57:25)\nmessage:\ wrong\ #\ args:\ should\ be\ \"info\ line\"\ndetail:\nwrong\ #\ args:\ should\ be\ \"info\ line\"\n\ \ \ \ invoked\ from\ within\n\"::scidb::db::open\ /home/user/chess_master_db/master_collection_2010_present.pgn\ ::import::Log\ log\ ::progress::DoCmd\ .application.nb.databa...\"\n\ \ \ \ (\"eval\"\ body\ line\ 1)\n\ \ \ \ invoked\ from\ within\n\"eval\ \$cmd\ \[namespace\ current\]::DoCmd\ \$parent\ \$args\"\n\ \ \ \ (procedure\ \"::progress::start\"\ line\ 7)\n\ \ \ \ invoked\ from\ within\n\"::progress::start\ .application.nb.database.main\ \{::scidb::db::open\ /home/user/chess_master_db/master_collection_2010_present.pgn\ ::import:...\"\n\ \ \ \ (\"uplevel\"\ body\ line\ 1)\n\ \ \ \ invoked\ from\ within\n\"uplevel\ 1\ \$cmd\ \"\n\ \ \ \ invoked\ from\ within\n\"::util::catchException\ \$cmd\ result\ \"\n\ \ \ \ invoked\ from\ within\n\"Open\ \$parent\ \$file\ \$msg\ \$encoding\ \$type\ \"\n\ \ \ \ (\"uplevel\"\ body\ line\ 1)\n\ \ \ \ invoked\ from\ within\n\"uplevel\ 1\ \$cmd\"\n\ \ \ \ invoked\ from\ within\n\"::remote::busyOperation\ \{\ Open\ \$parent\ \$file\ \$msg\ \$encoding\ \$type\ \}\"\n\ \ \ \ (procedure\ \"::import::open\"\ line\ 2)\n\ \ \ \ invoked\ from\ within\n\"::import::open\ .application.nb.database.main\ /home/user/chess_master_db/master_collection_2010_present.pgn\ \{Opening\ database\ 'master_colle...\"\n\ \ \ \ (\"uplevel\"\ body\ line\ 1)\n\ \ \ \ invoked\ from\ within\n\"uplevel\ 1\ \$cmd\ \"\n\ \ \ \ invoked\ from\ within\n\"::util::catchException\ \$cmd\"\n\ \ \ \ (procedure\ \"::application::database::openBase\"\ line\ 80)\n...\ (44\ lines) bug}
	# 5fd3bc4b llm: bug
	lappend cases {{source: log
occurrences: 131 (first 2026-10-03 15:55:25, last 2026-10-03 19:13:01)
message: wrong # args: should be "info line"
detail:
(func) invoke
(file) tcl_base.cpp:744
(what) wrong # args: should be "info line"
(type) tcl::Error
=== Backtrace ============================================
 
 
 
 
 
 
 
 
 
 
 
 
 TclNRRunCallbacks
 
 TclNRRunCallbacks
 
 Tcl_EvalEx
 Tk_BindEvent
 TkBindEventProc
 Tk_HandleEvent
 
 Tcl_ServiceEvent
 Tcl_DoOneEvent
 Tk_MainLoop
 Tk_MainEx
... (38 lines)} bug}
	# 267fe47c classifier: user
	lappend cases {{source: assistant
occurrences: 7 (first 2026-10-03 18:42:46, last 2026-10-03 19:11:34)
message: search_games: ::scidb::view::search rating: invalid rating range
detail:
::scidb::view::search rating: invalid rating range
    while executing
"::scidb::view::search $base $variant $view null none $query "
    (procedure "SearchView" line 12)
    invoked from within
"SearchView $base $variant $view $criteria"
    (procedure "::application::assistant::DoSearchGames" line 10)
    invoked from within
"{*}$handler {*}[dict values $checked]"} user}
	# 5e64b36e llm: bug
	lappend cases {source:\ background\noccurrences:\ 128\ (first\ 2026-10-03\ 18:43:20,\ last\ 2026-10-03\ 19:13:01)\nmessage:\ wrong\ #\ args:\ should\ be\ \"::TreeCtrl::PercentsCmd\ T\ char\ object\ event\ detail\ charMap\"\ndetail:\nwrong\ #\ args:\ should\ be\ \"::TreeCtrl::PercentsCmd\ T\ char\ object\ event\ detail\ charMap\"\n\ \ \ \ while\ executing\n\"::TreeCtrl::PercentsCmd\ .rating__home_user_chess_Mega\ Database\ 2010_sci_Normal.results.table.top.table.t\ C\ Table\ Item\ enter\ \{C...\"\n\ \ \ \ (expanding\ percents) bug}
	# d5dd4d9c llm: bug
	lappend cases {source:\ background\noccurrences:\ 2\ (first\ 2026-10-03\ 19:12:10,\ last\ 2026-10-03\ 19:13:01)\nmessage:\ can't\ read\ \"Vars(tooltipvar:)\":\ no\ such\ element\ in\ array\ndetail:\ncan't\ read\ \"Vars(tooltipvar:)\":\ no\ such\ element\ in\ array\n\ \ \ \ while\ executing\n\"llength\ \$Vars(tooltipvar:\$id)\"\n\ \ \ \ (procedure\ \"Tooltip\"\ line\ 15)\n\ \ \ \ invoked\ from\ within\n\"Tooltip\ \$table\ show\ \$item\"\n\ \ \ \ (procedure\ \"VisitHeader\"\ line\ 5)\n\ \ \ \ invoked\ from\ within\n\"VisitHeader\ \{.rating__home_user_chess_Mega\ Database\ 2010_sci_Normal.results.table.top.table\}\ enter\ C\ I\"\n\ \ \ \ (in\ namespace\ inscope\ \"::table\"\ script\ line\ 1)\n\ \ \ \ invoked\ from\ within\n\"::namespace\ inscope\ ::table\ \{VisitHeader\ \{.rating__home_user_chess_Mega\ Database\ 2010_sci_Normal.results.table.top.table\}\ ente...\"\n\ \ \ \ (<Header-enter>\ binding\ on\ Table) bug}
	# 25dd5123 classifier: user
	lappend cases {source:\ background\noccurrences:\ 1\ (first\ 2026-10-03\ 19:29:16,\ last\ 2026-10-03\ 19:29:16)\nmessage:\ ::scidb::view::search\ rating:\ invalid\ rating\ range\ndetail:\n::scidb::view::search\ rating:\ invalid\ rating\ range\n\ \ \ \ while\ executing\n\"::scidb::view::search\ \ \$RatingSearchData(\$dlg,file)\ \ \$RatingSearchData(\$dlg,variant)\ \ \$RatingSearchData(\$dlg,view)\ \ null\ \ none\ \ \$query\"\n\ \ \ \ (procedure\ \"RunRatingSearch\"\ line\ 23)\n\ \ \ \ invoked\ from\ within\n\"RunRatingSearch\ \{.rating__home_user_chess_Mega\ Database\ 2010_sci_Normal\}\"\n\ \ \ \ (in\ namespace\ inscope\ \"::application::database\"\ script\ line\ 1)\n\ \ \ \ invoked\ from\ within\n\"::namespace\ inscope\ ::application::database\ \{RunRatingSearch\ \{.rating__home_user_chess_Mega\ Database\ 2010_sci_Normal\}\}\"\n\ \ \ \ invoked\ from\ within\n\".rating__home_user_chess_Mega\\\ Database\\\ 2010_sci_Normal.controls.search\ invoke\ \"\n\ \ \ \ invoked\ from\ within\n\".rating__home_user_chess_Mega\\\ Database\\\ 2010_sci_Normal.controls.search\ instate\ !disabled\ \{\ .rating__home_user...\"\n\ \ \ \ invoked\ from\ within\n\".rating__home_user_chess_Mega\\\ Database\\\ 2010_sci_Normal.controls.search\ instate\ pressed\ \{\ .rating__home_user...\"\n\ \ \ \ (command\ bound\ to\ event) user}
	# e252adf6 llm: bug
	lappend cases {{source: log
occurrences: 19 (first 2026-10-03 19:59:33, last 2026-10-03 19:59:42)
message: precondition violation: index < count(type)
detail:
(func) index
(file) app_view.cpp:321
(what) precondition violation: index < count(type)
(type) mstl::precondition_violation_exception
=== Backtrace ============================================
 
 
 
 
 
 
 TclNRRunCallbacks
 
 Tcl_EvalEx
 Tk_BindEvent
 TkBindEventProc
 Tk_HandleEvent
 
 
 TclNRRunCallbacks
 
 Tcl_EvalEx
 Tk_BindEvent
 TkBindEventProc
 Tk_HandleEvent
 
 
 TclNRRunCallbacks
 
 Tcl_EvalEx
... (54 lines)} bug}
	# a5e94d0f llm: bug
	lappend cases {source:\ background\noccurrences:\ 1\ (first\ 2026-10-03\ 20:53:13,\ last\ 2026-10-03\ 20:53:13)\nmessage:\ can't\ read\ \"Priv(importCodes)\":\ no\ such\ element\ in\ array\ndetail:\ncan't\ read\ \"Priv(importCodes)\":\ no\ such\ element\ in\ array\n\ \ \ \ while\ executing\n\"::ai::import::Text\ \$Priv(importCodes)\"\n\ \ \ \ (procedure\ \"::import::logResult\"\ line\ 60)\n\ \ \ \ invoked\ from\ within\n\"::import::logResult\ \$total\ \$illegal\ \$mc::NoGamesCopied\ \$mc::CopiedGames\ \$accepted\ \$rejected\"\n\ \ \ \ (procedure\ \"CopyDatabase\"\ line\ 108)\n\ \ \ \ invoked\ from\ within\n\"CopyDatabase\ .application.nb.database.main.switcher\ /tmp/scidb-rating-master_collection_2010_present-1791075171813.sci\ \{/tmp/scidb-rating-Mega\ Databas...\"\n\ \ \ \ (in\ namespace\ inscope\ \"::database::switcher\"\ script\ line\ 1)\n\ \ \ \ invoked\ from\ within\n\"::namespace\ inscope\ ::database::switcher\ \{CopyDatabase\ .application.nb.database.main.switcher\ /tmp/scidb-rating-master_collection_2010_present-1791075...\"\n\ \ \ \ (\"after\"\ script) bug}

	# --- Hand-written cases (not from the log), labelled by the author of
	# --- this file, to give every class about 40 examples. Wording follows
	# --- real Scidb messages; Case builds the same text GroupText does.

	# environment: outside Scidb's code -- files, disks, network, permissions,
	# missing programs, damaged data
	foreach {source message detail} {
		dialog {Cannot open file '/home/u/chess/twic1601.pgn': permission denied} {}
		dialog {Cannot open file '/media/usb/Mega2024.sci'.} {couldn't open "/media/usb/Mega2024.sci": no such file or directory}
		background {error writing "file14": no space left on device} {error writing "file14": no space left on device\n    while executing\n"puts -nonewline $chan $data"\n    (procedure "::archive::WriteChunk" line 9)}
		log {Database '/home/u/bases/corr.sci' is read-only} {}
		background {couldn't open socket: connection refused} {couldn't open socket: connection refused\n    while executing\n"socket -async $host $port"\n    (procedure "::ai::provider::HttpOpen" line 14)}
		background {couldn't open socket: host is unreachable} {couldn't open socket: host is unreachable\n    (procedure "::fide::download::Start" line 22)}
		assistant {ollama: request timed out after 120 s} {timeout waiting for http://127.0.0.1:11434/api/chat}
		background {HTTP 503 Service Unavailable from lichess.org} {(procedure "::lichess::opening::Fetch" line 31)}
		background {tls handshake failed: certificate has expired} {(procedure "::http::Event" line 7)}
		dialog {Engine 'Stockfish 18' could not be started: /usr/local/bin/stockfish: not found} {}
		log {Engine 'Komodo' crashed (signal 11)} {}
		dialog {The tablebase directory '/srv/syzygy' does not exist.} {}
		log {Game 412,007: Decoding of this game was not possible} {}
		dialog {File '/home/u/Downloads/games.cbv' is not a valid ChessBase archive (truncated).} {}
		background {error reading "file9": I/O error} {error reading "file9": I/O error\n    (procedure "::import::ReadBlock" line 4)}
		dialog {Cannot create directory '/opt/scidb/photos': permission denied} {}
		log {font 'DejaVu Sans' not found, using fixed} {}
		dialog {The audio device is busy (ALSA: device or resource busy).} {}
		background {child process exited abnormally} {gzip: stdin: unexpected end of file\n    (procedure "::util::Gunzip" line 6)}
		dialog {The ECO file '/usr/share/scidb/eco.bin' is damaged.} {}
		log {lock file '/home/u/bases/Big.sci.lock' held by another process} {}
		background {can't find package tls} {can't find package tls\n    while executing\n"package require tls"\n    (procedure "::ai::provider::Https" line 3)}
		assistant {provider error: 401 Unauthorized (check the API key)} {}
		assistant {provider error: 429 rate limit exceeded} {}
		log {The FIDE rating list download stopped at 38%: connection reset by peer} {}
		dialog {Cannot save '/run/media/u/CARD/notes.pgn': read-only file system} {}
		log {libmpv: no hardware decoder available, falling back to software} {}
		dialog {Cannot open file '/home/u/Desktop/club.si4': file is too short to be a Scid database.} {}
		background {X connection to :0 broken (explicit kill or server shutdown).} {}
		dialog {The database was created by a newer Scidb version (format 105) and cannot be opened.} {}
		log {Engine 'Lc0' failed to load its network file: weights.pb.gz not found} {}
		dialog {Out of memory while loading 9 million games.} {}
		log {wikipedia lookup failed: DNS resolution for de.wikipedia.org failed} {}
		background {couldn't execute "xdg-open": no such file or directory} {(procedure "::web::open" line 12)}
		dialog {Cannot open file '/mnt/nas/bases/Corr.cbh': stale NFS file handle} {}
		log {clock skew detected: game dates from the future in /home/u/bases/online.sci} {}
		dialog {The printer 'HP_LaserJet' is not available.} {}
		log {Engine 'Dragon' license expired} {}
	} { lappend cases [Case $source $message $detail environment] }

	# user: input the application correctly refused
	foreach {source message detail} {
		dialog {::scidb::view::search date: invalid date '2026-13-01'} {}
		dialog {Illegal move: Nf3-f5} {}
		dialog {The FEN is not valid: two white kings.} {}
		dialog {Please enter a name for the new database.} {}
		dialog {A database named 'Club' is already open.} {}
		assistant {search_games: no player matching 'Kasparoff'} {no player matching 'Kasparoff'}
		assistant {open_base: no database matching 'tactics 2019'} {}
		dialog {The ECO code 'Z42' does not exist.} {}
		dialog {Elo must be between 0 and 4000.} {}
		dialog {Cannot delete the clipbase.} {}
		dialog {The game number 900,000 is out of range (1 to 41,233).} {}
		dialog {The tournament has no rounds; add players first.} {}
		dialog {The time control '40/120+30x' cannot be read.} {}
		assistant {prepare_against: 'Firouzja' has no games with Black in this database} {}
		dialog {The PGN on the clipboard contains no game.} {}
		dialog {CQL: syntax error at line 3: unknown filter 'checkk'} {}
		dialog {You cannot paste a variation into a read-only database.} {}
		dialog {The import file must be PGN, CBV, CBH or SCI.} {}
		dialog {Search by rating: the lower bound (2700) exceeds the upper bound (2500).} {}
		assistant {find_position: the position has 33 pieces} {}
		dialog {Tag name 'White Elo' must not contain spaces.} {}
		dialog {Cannot rename the database to an existing file name.} {}
		dialog {The engine option 'Hash' must be at most 32768.} {}
		dialog {A player name must not be empty.} {}
		dialog {The pattern '*[' is not a valid wildcard.} {}
		dialog {Cannot merge a database into itself.} {}
		dialog {The opening tree needs a position, not an empty board.} {}
		assistant {set_option: 'board.size' accepts 30 to 120, not 400} {}
		log {::scidb::view::search event: an empty event name matches every game; refine the search} {}
		dialog {The date range ends before it starts.} {}
		dialog {The move number 0 does not exist.} {}
		dialog {This variant (Shuffle chess) does not allow castling with that rook.} {}
	} { lappend cases [Case $source $message $detail user] }

	# noise: harmless, nothing to fix
	foreach {source message detail} {
		log {Engine terminated with exit code 0.} {}
		log {font cache refreshed twice} {}
		log {tree cache rebuilt for 'Mega2024'} {}
		log {engine 'Stockfish 18' restarted after option change} {}
		log {startup took 2.4 s} {}
		log {network status: online} {}
		log {clipbase cleared} {}
		log {theme 'Dark' loaded} {}
		log {autosave written (12 games)} {}
		log {FIDE list already current; nothing to download} {}
		log {engine 'Lc0' info: using 2 threads} {}
		log {the last session was restored} {}
		log {window geometry adjusted to fit the screen} {}
		log {spell checker: no dictionary for 'xx'; checking skipped} {}
		log {mpv: end of file reached} {}
		log {ECO table loaded (2014 lines)} {}
		log {import finished: 3,120 games, 0 rejected} {}
		log {tablebase probe skipped: 8 pieces on the board} {}
		log {database '/home/u/bases/Club.sci' compacted} {}
		log {engine analysis stopped by the user} {}
		dialog {Engine terminated with exit code 0.} {}
		log {photo index refreshed: 0 new photos} {}
		log {AI provider switched to 'ollama'} {}
		log {the opening book 'gm2600' was reloaded} {}
		log {old log file rotated} {}
		log {classifier warm-up took 310 ms} {}
		log {recent files list trimmed to 20 entries} {}
		log {clock synchronised with the engine} {}
		log {printing cancelled} {}
		log {tooltip delay changed to 500 ms} {}
		log {update check: Scidb is up to date} {}
		log {an empty search returned 0 games} {}
		log {board flipped} {}
		log {engine 'Stockfish 18' uci ok in 120 ms} {}
		log {3 duplicate games marked, none deleted} {}
		log {language set to English} {}
	} { lappend cases [Case $source $message $detail noise] }

	# bug: defects in Scidb's own code
	foreach {source message detail} {
		background {can't read "Vars(board)": no such variable} {can't read "Vars(board)": no such variable\n    (procedure "::application::board::Resize" line 7)}
		background {invalid command name ".application.nb.games.list.t"} {invalid command name ".application.nb.games.list.t"\n    (procedure "::gamebar::Update" line 15)}
		log {precondition violation: m_index < m_size} {(func) at}
		background {expected integer but got ""} {expected integer but got ""\n    (procedure "::pgn::setup::ApplyFontSize" line 4)}
		background {wrong # args: should be "::move::addVariation position ?mode?"} {(procedure "::move::PasteVariation" line 11)}
		log {Aborted due to an internal error} {assertion "pos.isValid()" failed in Board::doMove}
		background {can't use non-numeric string as operand of "+"} {(procedure "::tree::ComputePercentage" line 9)}
		background {bad option "-textvar": must be -text, -textvariable, ...} {(procedure "::dialog::choosecolor::Build" line 33)}
		background {list index out of range} {(procedure "::application::pgn::GotoMove" line 18)}
		background {can't set "Priv(timer)": variable is array} {(procedure "::engine::Schedule" line 3)}
		background {key "games" not known in dictionary} {(procedure "::application::assistant::Summarize" line 21)}
		log {Segmentation fault in db::Database::loadGame} {}
		background {divide by zero} {(procedure "::stats::Performance" line 14)}
		background {can't read "info(event)": no such element in array} {(procedure "::gameinfo::Format" line 6)}
		background {unknown option "-yscrollcommand"} {(procedure "::scrolledframe::Build" line 22)}
		background {invalid bareword "Draw"} {in expression "$result eq Draw"\n    (procedure "::crosstable::Score" line 5)}
		log {the PGN writer emitted an unmatched '(' in game 22} {}
		background {after cancel: bad argument "after#"} {(procedure "::tooltip::Hide" line 2)}
	} { lappend cases [Case $source $message $detail bug] }
	return $cases
}
