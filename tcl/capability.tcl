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
	Define ai          {expr {[llength [info commands ::application::ai::analyze]] > 0}}
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
	Define enginematch {expr {[llength [info commands ::enginematch::open]] > 0}}
	Define guessmove   {expr {[llength [info commands ::guessmove::start]] > 0}}
	Define endtrainer  {expr {[llength [info commands ::endtrainer::open]] > 0}}
	Define reptrainer  {expr {[llength [info commands ::reptrainer::open]] > 0}}
	Define playerdata  {expr {[llength [info commands ::playerdata::updateFide]] > 0}}
	Define filetypes   {expr {[llength [info procs ::menu::AssignFileTypes]] > 0}}
	Define legacyfonts {expr {[llength [info procs ::font::installChessBaseFonts]] > 0}}
	Define board3d     {expr {[llength [info commands ::board3d::openViewer]] > 0}}
	Define webgl3d     {expr {[llength [info commands ::board3d::openWebGLViewer]] > 0}}
	Define embed3d     {expr {[llength [info commands ::board3d::toggleEmbed]] > 0}}
	Define stream      {expr {[llength [info commands ::application::media::OpenStream]] > 0}}
	Define insights    {expr {[llength [info commands ::insights::show]] > 0}}
	Define playercard  {expr {[llength [info commands ::playercard::show]] > 0}}
	Define explorer    {expr {[llength [info commands ::application::explorer::positionChanged]] > 0}}
	Define tablebase   {expr {[llength [info commands ::tablebase::toggle]] > 0}}
	Define print       {expr {[llength [info commands ::print::open]] > 0}}
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
