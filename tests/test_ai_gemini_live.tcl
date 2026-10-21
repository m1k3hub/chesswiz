# Opt in: SCIDB_TEST_GEMINI_LIVE=1 GEMINI_API_KEY=... tkchesswiz this-file
# One real Gemini tool round-trip, through the production async adapter.
set root [file normalize [file join [file dirname [info script]] ..]]
set ::env(SCIDB_AI_EGRESS) off
set ::env(SCIDB_AI_TIER) off
source [file join $root tcl sys-platform.tcl]
source [file join $root tcl ai-provider.tcl]
if {![info exists ::env(SCIDB_TEST_GEMINI_LIVE)]
 || $::env(SCIDB_TEST_GEMINI_LIVE) ne "1" || [::ai::provider::apiKey gemini] eq ""} {
	puts "SKIP: opt in with SCIDB_TEST_GEMINI_LIVE=1 and GEMINI_API_KEY (or GOOGLE_API_KEY)"
	puts "AI-GEMINI-LIVE-FAILURES: 0"
	exit 0
}
proc reply {r} { set ::result $r; set ::done 1 }
proc chat {messages tools} {
	set ::done 0
	::ai::provider::chatAsync $messages $tools reply
	set timer [after 125000 {set ::result {ok 0 error {callback deadline exceeded}}; set ::done 1}]
	vwait ::done
	after cancel $timer
	if {![dict get $::result ok]} { error [dict get $::result error] }
	return [dict get $::result message]
}
set failed [catch {
	set model gemini-3.8-flash
	if {[info exists ::env(SCIDB_TEST_GEMINI_MODEL)]} {set model $::env(SCIDB_TEST_GEMINI_MODEL)}
	::ai::provider::configure -name gemini -model $model -timeout 120000
	set tools {[{"type":"function","function":{"name":"current_game","description":"Return the current chess game players.","parameters":{"type":"object","properties":{}}}}]}
	set messages [list [dict create role user content "Call current_game exactly once, then tell me the two players in one short sentence."]]
	puts "Gemini: requesting tool call"; flush stdout
	set msg [chat $messages $tools]
	if {![dict exists $msg tool_calls] || ![llength [dict get $msg tool_calls]]} { error "Gemini did not call a tool" }
	lappend messages $msg
	foreach call [dict get $msg tool_calls] {
		if {[dict get $call function name] ne "current_game"} { error "unexpected tool" }
		if {![dict exists $call openai_extra_content]} { error "missing thought signature metadata" }
		lappend messages [dict create role tool tool_call_id [dict get $call id] content "White: Giri. Black: Abdusattorov. Event: SuperUnited CRO Rapid 2025."]
	}
	puts "Gemini: returning tool result with thought signature"; flush stdout
	set answer [chat $messages $tools]
	set text [dict get $answer content]
	if {![string match *Giri* $text] || ![string match *Abdusattorov* $text]
	 || [dict exists $answer tool_calls]} { error "did not answer from the tool result: $text" }
	puts "PASS: Gemini tool round-trip: $text"
} error]
if {$failed} { puts "FAIL: [::ai::provider::redactError $error]" }
puts "AI-GEMINI-LIVE-FAILURES: $failed"
exit $failed
