# ======================================================================
# Scidb App Test — a first answer that claims an action no tool did is
# sent back once (tcl/app-assistant.tcl, ClaimsAction / OnReplyImpl)
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

tcltest::test guard-claims {claims of actions are recognised; questions and refusals are not} -body {
	lmap text {
		{I've filtered the game list to 1,000 games.}
		{Here are 3 examples found in the database.}
		{The Najdorf after 6.Bg5 is set.}
		{Thanks, I'll remember you.}
		{Which engine should I use?}
		{I cannot do that with the tools I have.}
		{We use the `find_similar` tool with these settings: ```json {"tolerance": 1} ```}
		{Call find_similar(aspects=pawns) for that.}
		{I'll use the save_working_set tool to keep them.}
		{Thomas, Michael has played 1,234 games in total.}
		{I don't have access to Corti's current scores.}
	} { ::application::assistant::ClaimsAction $text }
} -result {1 1 1 1 0 0 1 1 1 1 1}

proc ::scidb::test::guardAsk {replies request} {
	set cfg [array get ::application::ai::Config provider]
	set ::application::ai::Config(provider) stub
	::ai::provider::configure -name stub -chatResponses $replies
	::application::assistant::clear
	::application::assistant::ask $request
	if {$::application::assistant::Priv(busy)} { vwait ::application::assistant::Priv(busy) }
	array set ::application::ai::Config $cfg
	set roles [lmap m $::application::assistant::Priv(messages) { dict get $m role }]
	set last [dict get [lindex $::application::assistant::Priv(messages) end] content]
	::application::assistant::clear
	list $roles $last
}

tcltest::test guard-nudge {a made-up claim is sent back once; the second answer stands} -match glob -body {
	::scidb::test::guardAsk [list \
		[dict create role assistant content "I've started a new game for you."] \
		[dict create role assistant content "I cannot start a game here."]] "start a new game"
} -result {{system user assistant user assistant} {Chesswiz cannot do that*}}

tcltest::test guard-honest {an answer without claims is not sent back} -body {
	::scidb::test::guardAsk [list [dict create role assistant content "Which database do you mean?"]] "find games"
} -result {{system user assistant} {Which database do you mean?}}

tcltest::cleanupTests
