# ======================================================================
# ::capability -- one capability check for optional modules.
#
# Menu builders and context menus ask ::capability::present <module>
# instead of scattering [info commands]/[info procs] guards through the
# builders (PROPOSAL section 4, R14/R15). Tests and stripped builds can
# force a module absent with ::capability::override.
# ======================================================================

package require Tcl 8.5

namespace eval ::capability {
	variable Modules [dict create]
	variable Overrides [dict create]
}

# Probe scripts run at #0. A module is present when its probe returns a
# true value; an unknown module is present (nothing to guard).
proc ::capability::Define {module probe} {
	variable Modules
	dict set Modules $module $probe
}

proc ::capability::DefineAll {} {
	variable Modules
	set Modules [dict create]
	Define ai          {expr {[llength [info commands ::application::ai::analyze]] > 0 && [::application::ai::Ready $::application::ai::Config(provider)]}}
	Define assistant   {expr {[llength [info commands ::application::assistant::show]] > 0}}
	Define models      {expr {[llength [info commands ::application::ai::models::show]] > 0}}
	Define brief       {expr {[llength [info commands ::ai::brief::ask]] > 0}}
	Define studyplan   {expr {[llength [info commands ::ai::studyplan::run]] > 0}}
	Define training    {expr {[llength [info commands ::ai::cql::training]] > 0}}
	Define quality     {expr {[llength [info commands ::ai::cql::qualityReport]] > 0}}
	Define event       {expr {[llength [info commands ::ai::event::report]] > 0}}
	Define trend       {expr {[llength [info commands ::ai::trend::report]] > 0}}
	Define factcheck   {expr {[llength [info commands ::ai::factcheck::current]] > 0}}
	Define annotate    {expr {[llength [info commands ::ai::annotate::toggle]] > 0}}
	Define review      {expr {[llength [info commands ::gamereview::run]] > 0}}
	Define chooseengine {expr {[llength [info commands ::ai::engine::chooseDialog]] > 0}}
	Define voice       {expr {[llength [info commands ::application::voice::toggle]] > 0}}
	Define download    {expr {[llength [info commands ::application::download::openActive]] > 0}}
	Define playengine  {expr {[llength [info commands ::playengine::open]] > 0}}
	Define ics         {expr {[llength [info commands ::ics::open]] > 0}}
	Define lichess     {expr {[llength [info commands ::lichess::open]] > 0}}
	Define lichess_social  {expr {[llength [info commands ::lichess::social::open]] > 0}}
	Define lichess_tv      {expr {[llength [info commands ::lichess::tv::open]] > 0}}
	Define lichess_events  {expr {[llength [info commands ::lichess::events::open]] > 0}}
	Define lichess_puzzles {expr {[llength [info commands ::lichess::puzzles::open]] > 0}}
	Define stream_overlay {expr {[llength [info commands ::stream::open]] > 0}}
	Define enginematch {expr {[llength [info commands ::enginematch::open]] > 0}}
	Define guessmove   {expr {[llength [info commands ::guessmove::start]] > 0}}
	Define endtrainer  {expr {[llength [info commands ::endtrainer::open]] > 0}}
	Define reptrainer  {expr {[llength [info commands ::reptrainer::open]] > 0}}
	Define playerdata  {expr {[llength [info commands ::playerdata::updateFide]] > 0}}
	Define filetypes   {expr {[llength [info commands ::menu::AssignFileTypes]] > 0}}
	Define legacyfonts {expr {[llength [info procs ::font::installChessBaseFonts]] > 0}}
	Define board3d     {expr {[llength [info commands ::board3d::openViewer]] > 0}}
	Define webgl3d     {expr {[llength [info commands ::board3d::openWebGLViewer]] > 0}}
	Define embed3d     {expr {[llength [info commands ::board3d::toggleEmbed]] > 0}}
	Define stream      {expr {[llength [info commands ::application::media::OpenStream]] > 0}}
	Define insights    {expr {[llength [info commands ::insights::show]] > 0}}
	Define playercard  {expr {[llength [info commands ::playercard::show]] > 0}}
	Define explorer    {expr {[llength [info commands ::application::explorer::positionChanged]] > 0}}
	Define tablebase   {expr {[llength [info commands ::tablebase::toggle]] > 0}}
	Define print       {expr {[llength [info commands ::print::game]] > 0}}
	Define report      {expr {[llength [info commands ::application::report::show]] > 0}}
	return
}

proc ::capability::Override {module value} {
	variable Overrides
	dict set Overrides $module [expr {$value ? 1 : 0}]
}

proc ::capability::ClearOverrides {} {
	variable Overrides
	set Overrides [dict create]
}

proc ::capability::present {module} {
	variable Modules
	variable Overrides
	if {[dict exists $Overrides $module]} { return [dict get $Overrides $module] }
	if {![dict exists $Modules $module]} { return 1 }
	if {[catch { uplevel #0 [dict get $Modules $module] } answer]} { return 0 }
	return [expr {$answer ? 1 : 0}]
}

::capability::DefineAll

# Action ownership is independent of visible/enabled predicates. This covers
# aliases as well as their menu rows, so an omitted predicate cannot advertise
# an operation whose implementation is missing.
namespace eval ::capability {
	variable ActionModules {
		ai {c2.explain_move c3.ask_about_game c6.explain_line c11.draft_comment c11.explain_comment explain_position menu.analysis.analyze menu.analysis.explain.comment menu.analysis.explain.line menu.analysis.explain.position}
		annotate {annotate_game menu.analysis.annotate}
		assistant {menu.tools.assistant menu.view.panes.assistant}
		board3d {view.board3d.open}
		brief {opponent_brief menu.training.brief}
		chooseengine {menu.analysis.review_engine}
		download {download_games menu.tools.download}
		embed3d {view.board3d.embed}
		endtrainer {menu.training.endgame}
		enginematch {menu.training.engine_match}
		event {menu.db.reports.timecontrol}
		explorer {c9.explorer.source c9.pane.explorer menu.analysis.explorer menu.view.panes.explorer}
		factcheck {factcheck_annotations menu.analysis.factcheck}
		filetypes {menu.tools.file_types}
		guessmove {menu.training.guess}
		ics {menu.training.play_online}
		insights {c5.insights c5.player.insights}
		legacyfonts {install_chessbase_fonts menu.tools.legacy_fonts}
		lichess {menu.training.play_lichess}
		lichess_events {menu.training.lichess_events}
		lichess_puzzles {menu.training.lichess_puzzles}
		lichess_social {menu.training.lichess_social}
		lichess_tv {menu.training.lichess_tv}
		models {menu.tools.choose_model}
		playengine {open_play_engine menu.training.play_engine}
		playercard {c5.player_card menu.tools.player_card}
		playerdata {update_player_data}
		print {print}
		quality {check_results menu.training.check_results}
		report {menu.view.panes.report}
		reptrainer {menu.training.repertoire}
		review {menu.analysis.game_review}
		stream {c7.open_stream c9.media.stream open_stream}
		stream_overlay {menu.training.stream}
		studyplan {study_plan menu.training.studyplan}
		tablebase {c9.tablebase menu.analysis.tablebase.local menu.analysis.tablebase.online menu.analysis.tablebase.show menu.board.tablebase.local menu.board.tablebase.online menu.board.tablebase.show}
		training {training_set menu.training.training_set}
		trend {menu.db.reports.trends}
		voice {menu.tools.voice}
		webgl3d {view.board3d.webgl}
	}
	# An action can remain useful when just one argument choice is absent.
	variable ArgumentModules {open_view {kind {player_card playercard}}}
}

proc ::capability::actionAvailable {id {arguments {}}} {
	variable ActionModules
	variable ArgumentModules
	dict for {module ids} $ActionModules {
		if {$id in $ids && ![present $module]} {return 0}
	}
	if {[dict exists $ArgumentModules $id]} {
		dict for {param values} [dict get $ArgumentModules $id] {
			if {![dict exists $arguments $param]} {continue}
			set value [dict get $arguments $param]
			if {[dict exists $values $value] && ![present [dict get $values $value]]} {return 0}
		}
	}
	return 1
}

proc ::capability::availableArgs {id spec} {
	variable ArgumentModules
	if {![dict exists $ArgumentModules $id]} {return $spec}
	set result {}
	set changed 0
	foreach param $spec {
		lassign $param name opts
		if {[dict exists $ArgumentModules $id $name] && [dict exists $opts enum]} {
			set values {}
			foreach value [dict get $opts enum] {
				if {[actionAvailable $id [dict create $name $value]]} {lappend values $value}
			}
			if {$values ne [dict get $opts enum]} {set changed 1}
			dict set opts enum $values
		}
		lappend result [list $name $opts]
	}
	if {!$changed} {return $spec}
	return $result
}
