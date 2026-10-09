# ======================================================================
# test_ai_provider_cloud.tcl -- unit tests for the cloud adapters of
# tcl/ai-provider.tcl (Anthropic Messages API, OpenAI Chat Completions,
# and the OpenAI-compatible presets: openai, fireworks, qwen, gemini).
#
#   xvfb-run -a src/tkchesswiz tests/test_ai_provider_cloud.tcl
#
# The end-to-end tests talk to a minimal HTTP/1.1 mock server bound to
# 127.0.0.1 on an ephemeral port; no request ever leaves the machine.
# ======================================================================

# tcltest configures itself from ::argv; the shell hands the script there.
set ::argv {}
set ::argc 0

# Keep the A9/A10 shadow gates from asking any classifier about these
# requests (the provider re-reads the environment when sourced below).
set ::env(SCIDB_AI_EGRESS) off
set ::env(SCIDB_AI_TIER) off

# The tests own the key environment: save and drop what the runner set,
# so apiKey() sees only what a test puts there.
array set SavedEnv {}
foreach v {ANTHROPIC_API_KEY OPENAI_API_KEY FIREWORKS_API_KEY
	QWEN_TOKEN_PLAN_API_KEY QWEN_API_KEY GEMINI_API_KEY GOOGLE_API_KEY} {
	if {[info exists ::env($v)]} {
		set SavedEnv($v) $::env($v)
		unset ::env($v)
	}
}

package require tcltest 2.5
namespace import tcltest::*

# a hang must still show where it hangs
catch {fconfigure stdout -buffering none}

if {[catch {package require json}]} {
	puts "SKIP: requires the tcllib 'json' package (run under src/tkchesswiz)"
	puts "AI-PROVIDER-CLOUD-FAILURES: 0"
	catch {::tcltest::cleanupTests}
	exit 0
}
package require http

# A real bug in ai-provider.tcl found by this suite gets its tests marked
# with this constraint (off), not a fixed expectation, so the suite stays
# green while the bug is on the record.
testConstraint knownBug 0

set root [file join [file dirname [file normalize [info script]]] ..]
source [file join $root tcl ai-provider.tcl]


# ----------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------

proc Assert {cond {label ""}} {
	if {![uplevel 1 [list expr $cond]]} {
		error "assertion failed: $label"
	}
}

# A minimal HTTP/1.1 server on 127.0.0.1: records each request as
# {method url headers body} (::Mock(requests), header names lower-cased)
# and answers $::Mock(code) with $::Mock(body), then closes.
array set ::Mock [list requests {} code 200 body "{}"]

proc MockStart {} {
	if {[info exists ::Mock(sock)]} { return $::Mock(port) }
	set s [socket -server MockAccept -myaddr 127.0.0.1 0]
	lassign [fconfigure $s -sockname] host family port
	set ::Mock(sock) $s
	set ::Mock(port) $port
	return $port
}

proc MockReset {} {
	set ::Mock(requests) {}
	set ::Mock(code) 200
	set ::Mock(body) "{}"
}

proc MockAccept {chan addr port} {
	fconfigure $chan -translation binary -blocking 0 -buffering none
	set ::Mock(buf-$chan) ""
	fileevent $chan readable [list MockRead $chan]
}

proc MockRead {chan} {
	if {[eof $chan]} {
		fileevent $chan readable {}
		catch {close $chan}
		catch {unset ::Mock(buf-$chan)}
		return
	}
	append ::Mock(buf-$chan) [read $chan]
	set buf $::Mock(buf-$chan)
	set sep [string first "\r\n\r\n" $buf]
	if {$sep < 0} { return }
	set head [string range $buf 0 [expr {$sep - 1}]]
	set body [string range $buf [expr {$sep + 4}] end]

	set len 0
	foreach line [split $head "\r\n"] {
		if {[regexp -nocase {^Content-Length:[ \t]*([0-9]+)$} $line -> n]} { set len $n }
	}
	if {[string bytelength $body] < $len} { return }
	fileevent $chan readable {}
	catch {unset ::Mock(buf-$chan)}

	set lines [split $head "\r\n"]
	set hdrs {}
	foreach line [lrange $lines 1 end] {
		if {[regexp {^([^:]+):[ \t]*(.*)$} $line -> k v]} {
			lappend hdrs [string tolower $k] $v
		}
	}
	lassign [lindex $lines 0] method url
	lappend ::Mock(requests) [list $method $url $hdrs [encoding convertfrom utf-8 $body]]

	set reason [expr {$::Mock(code) == 200 ? "OK" : "Error"}]
	set resp [format "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" \
		$::Mock(code) $reason [string bytelength $::Mock(body)]]
	fconfigure $chan -blocking 1
	catch {
		puts -nonewline $chan "$resp[encoding convertto utf-8 $::Mock(body)]"
		flush $chan
		close $chan
	}
}

# The async callback sink; result dicts land in ::E2E(result).
proc E2ESink {r} {
	global E2E
	set E2E(result) $r
	set E2E(done) 1
}

# Runs <call> (which must end in delivering to E2ESink) and waits for the
# callback; an 'after' guard turns a lost callback into TIMEOUT instead
# of hanging the suite.
proc AsyncRun {call {ms 10000}} {
	global E2E
	set E2E(result) {}
	set E2E(done) 0
	uplevel 1 $call
	set t [after $ms {set ::E2E(result) TIMEOUT; set ::E2E(done) 1}]
	vwait ::E2E(done)
	after cancel $t
	return $E2E(result)
}

set Fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

# The assistant's Ollama/OpenAI tools format, one full tool and one bare.
set ToolsJson "\[{\"type\":\"function\",\"function\":{\"name\":\"chess_engine\",\"description\":\"Analyze with \\\"Stockfish\\\".\",\"parameters\":{\"type\":\"object\",\"properties\":{\"fen\":{\"type\":\"string\"},\"depth\":{\"type\":\"integer\"}},\"required\":\[\"fen\"\]}}},{\"type\":\"function\",\"function\":{\"name\":\"lookup\"}}]"


# ----------------------------------------------------------------------
# 1. raw JSON spans: nothing is ever re-encoded
# ----------------------------------------------------------------------

test aipc-members-raw-1.1 {jsonMembers keeps raw value spans and decodes keys} -body {
	set mt {{"n":1990,"s":"1990","big":2500,"pi":-2.5e-3,"t":true,"f":false,"z":null,"q":"he said \"hi\" \\ done","a":[1,{"deep":["x"]},[2,[3]]],"u":"caf\u00e9 é","e":{},"o":{"k":"v","l":[null,true]}}}
	set m [::ai::provider::jsonMembers $mt]

	Assert {[dict keys $m] eq {n s big pi t f z q a u e o}} "member order"
	# the string "1990" stays a string, the number 1990 stays a number
	Assert {[dict get $m s] eq "\"1990\""} "quoted span kept"
	Assert {[dict get $m n] eq "1990"} "bare span kept"
	Assert {[dict get $m big] eq "2500"}
	Assert {[dict get $m pi] eq "-2.5e-3"}
	Assert {[dict get $m t] eq "true"}
	Assert {[dict get $m f] eq "false"}
	Assert {[dict get $m z] eq "null"}
	# escaped quotes and backslashes come back byte-identical
	Assert {[dict get $m q] eq "\"he said \\\"hi\\\" \\\\ done\""} "escapes kept"
	# nested arrays/objects come back as the exact span
	Assert {[dict get $m a] eq "\[1,{\"deep\":\[\"x\"\]},\[2,\[3\]\]\]"} "nested span kept"
	# unicode: both the escape form and the literal byte come back intact
	Assert {[dict get $m u] eq "\"caf\\u00e9 é\""} "unicode span kept"
	Assert {[::ai::provider::jsonString [dict get $m u]] eq "café é"} "unicode decodes"
	Assert {[dict get $m e] eq "\{\}"} "empty object span"
	Assert {[dict get $m o] eq "{\"k\":\"v\",\"l\":\[null,true\]}"} "sub-object span"
	return OK
} -result OK

test aipc-members-jsonstring-1.2 {jsonString decodes strings and only strings} -body {
	Assert {[::ai::provider::jsonString "\"1990\""] eq "1990"} "string decodes"
	Assert {[::ai::provider::jsonString "1990"] eq ""} "number is no string"
	Assert {[::ai::provider::jsonString "true"] eq ""} "literal is no string"
	Assert {[::ai::provider::jsonString "\"a\\\"b\""] eq "a\"b"} "escaped quote decodes"
	Assert {[::ai::provider::jsonString "\"caf\\u00e9\""] eq "café"} "escape decodes"
	return OK
} -result OK

test aipc-elements-raw-1.3 {jsonElements keeps each element's raw span} -body {
	set arr "\[1,\"two\",\{\},\[\],{\"a\":\[2,\[3,\"x\\\"\"\],{\"b\":\"y}z{w\"}\]},true,false,null,\"caf\\u00e9\",\"a\\\\b\"]"
	set el [::ai::provider::jsonElements $arr]
	set want [list "1" "\"two\"" "\{\}" "\[\]" \
		"{\"a\":\[2,\[3,\"x\\\"\"\],{\"b\":\"y}z{w\"}\]}" \
		"true" "false" "null" "\"caf\\u00e9\"" "\"a\\\\b\""]

	Assert {[llength $el] == [llength $want]} "element count"
	foreach got $el exp $want {
		Assert {$got eq $exp} "span $exp"
	}
	return OK
} -result OK

test aipc-jsonskip-1.4 {JsonSkip steps over strings with braces and over objects} -body {
	# a string holding braces and a comma must not end the value
	# (\} and \{ so the test body's brace word stays balanced)
	set st "\"a\}b\{c\",rest"
	set end [::ai::provider::JsonSkip $st 0]
	Assert {[string range $st $end end] eq ",rest"} "string span"

	# an object whose string holds a brace
	set ot "{\"x\":\"a{b]c,}\",\"y\":1}TRAIL"
	set end [::ai::provider::JsonSkip $ot 0]
	Assert {[string range $ot $end end] eq "TRAIL"} "object span"

	# leading whitespace is skipped
	set wt "  \n \[1,\[2\]\]X"
	set end [::ai::provider::JsonSkip $wt 0]
	Assert {[string range $wt $end end] eq "X"} "whitespace"

	# an escaped quote does not end a string early
	set qt "\"say \\\"hi\\\"\"Y"
	set end [::ai::provider::JsonSkip $qt 0]
	Assert {[string range $qt $end end] eq "Y"} "escaped quote"
	return OK
} -result OK


# ----------------------------------------------------------------------
# 2. anthropicTools
# ----------------------------------------------------------------------

test aipc-anthropic-tools-2.1 {tools convert, schema text unchanged} -body {
	global ToolsJson
	set got [::ai::provider::anthropicTools $ToolsJson]

	set want "\[{\"name\":\"chess_engine\",\"description\":\"Analyze with \\\"Stockfish\\\".\",\"input_schema\":{\"type\":\"object\",\"properties\":{\"fen\":{\"type\":\"string\"},\"depth\":{\"type\":\"integer\"}},\"required\":\[\"fen\"\]}},{\"name\":\"lookup\",\"description\":\"\",\"input_schema\":{\"type\":\"object\"}}]"
	Assert {$got eq $want} "exact conversion"
	# the parameters span arrived byte-identical in input_schema
	set schema "{\"type\":\"object\",\"properties\":{\"fen\":{\"type\":\"string\"},\"depth\":{\"type\":\"integer\"}},\"required\":\[\"fen\"\]}"
	Assert {[string first $schema $got] >= 0} "schema unchanged"

	set tools [json::json2dict $got]
	Assert {[llength $tools] == 2} "tool count"
	set t0 [lindex $tools 0]
	Assert {[dict get $t0 name] eq "chess_engine"}
	Assert {[dict get $t0 description] eq "Analyze with \"Stockfish\"."}
	Assert {[dict get $t0 input_schema type] eq "object"}
	Assert {[llength [dict get $t0 input_schema required]] == 1}
	# a tool without description/parameters gets the empty defaults
	set t1 [lindex $tools 1]
	Assert {[dict get $t1 name] eq "lookup"}
	Assert {[dict get $t1 description] eq ""}
	Assert {[dict get $t1 input_schema type] eq "object"}
	return OK
} -result OK

test aipc-anthropic-tools-2.2 {an empty tools array stays empty} -body {
	Assert {[::ai::provider::anthropicTools "\[\]"] eq "\[\]"}
	return OK
} -result OK


# ----------------------------------------------------------------------
# 3. anthropicMessages
# ----------------------------------------------------------------------

test aipc-messages-system-3.1 {system messages join into the system prompt} -body {
	set hist [list \
		[dict create role system content "You are Scidb."] \
		[dict create role system content "Be terse."] \
		[dict create role user content "hi"]]
	lassign [::ai::provider::anthropicMessages $hist] sys out

	Assert {$sys eq "You are Scidb.\n\nBe terse."} "system joined"
	set p [json::json2dict $out]
	Assert {[llength $p] == 1} "no system turn"
	Assert {[dict get [lindex $p 0] role] eq "user"}
	Assert {[dict get [lindex [dict get [lindex $p 0] content] 0] text] eq "hi"}
	return OK
} -result OK

test aipc-messages-tool-order-3.2 {tool replies become tool_results by order} -body {
	global Fen
	set callA [dict create id toolu_a function [dict create name chess_engine arguments [dict create fen $Fen depth 8]]]
	set callB [dict create id toolu_b function [dict create name lookup arguments {}]]
	set hist [list \
		[dict create role user content "Best move?"] \
		[dict create role assistant content "Let me look." tool_calls [list $callA $callB]] \
		[dict create role tool content "eval 0.4"] \
		[dict create role tool content "no match"] \
		[dict create role user content "Thanks"]]
	lassign [::ai::provider::anthropicMessages $hist] sys out
	set p [json::json2dict $out]

	Assert {[llength $p] == 3} "turn count"
	Assert {[dict get [lindex $p 0] role] eq "user"}
	Assert {[dict get [lindex $p 1] role] eq "assistant"}
	Assert {[dict get [lindex $p 2] role] eq "user"}

	set ac [dict get [lindex $p 1] content]
	Assert {[llength $ac] == 3} "text + two tool_use"
	Assert {[dict get [lindex $ac 0] type] eq "text"}
	Assert {[dict get [lindex $ac 0] text] eq "Let me look."}
	Assert {[dict get [lindex $ac 1] type] eq "tool_use"}
	Assert {[dict get [lindex $ac 1] id] eq "toolu_a"}
	Assert {[dict get [lindex $ac 1] name] eq "chess_engine"}
	Assert {[dict get [lindex $ac 1] input fen] eq $Fen}
	Assert {[dict get [lindex $ac 1] input depth] == 8}
	Assert {[dict get [lindex $ac 2] id] eq "toolu_b"}

	# results ride in the next user turn and merge with the text that follows
	set uc [dict get [lindex $p 2] content]
	Assert {[llength $uc] == 3} "two results + text"
	Assert {[dict get [lindex $uc 0] type] eq "tool_result"}
	Assert {[dict get [lindex $uc 0] tool_use_id] eq "toolu_a"}
	Assert {[dict get [lindex $uc 0] content] eq "eval 0.4"}
	Assert {![dict exists [lindex $uc 0] is_error]} "a good result has no is_error"
	Assert {[dict get [lindex $uc 1] tool_use_id] eq "toolu_b"}
	Assert {[dict get [lindex $uc 1] content] eq "no match"}
	Assert {[dict get [lindex $uc 2] type] eq "text"}
	Assert {[dict get [lindex $uc 2] text] eq "Thanks"}
	return OK
} -result OK

test aipc-messages-tool-by-id-3.3 {tool_call_id picks the right tool_use, mixed with order} -body {
	set callA [dict create id toolu_a function [dict create name a arguments {}]]
	set callB [dict create id toolu_b function [dict create name b arguments {}]]
	set hist [list \
		[dict create role user content "q"] \
		[dict create role assistant content "" tool_calls [list $callA $callB]] \
		[dict create role tool content "second" tool_call_id toolu_b] \
		[dict create role tool content "first-by-order"]]
	lassign [::ai::provider::anthropicMessages $hist] sys out
	set uc [dict get [lindex [json::json2dict $out] 2] content]

	# the first reply names toolu_b explicitly; the second takes the
	# remaining pending call (toolu_a) by order
	Assert {[dict get [lindex $uc 0] tool_use_id] eq "toolu_b"}
	Assert {[dict get [lindex $uc 0] content] eq "second"}
	Assert {[dict get [lindex $uc 1] tool_use_id] eq "toolu_a"}
	Assert {[dict get [lindex $uc 1] content] eq "first-by-order"}
	return OK
} -result OK

test aipc-messages-merge-3.4 {consecutive user turns merge into one} -body {
	set hist [list \
		[dict create role user content "a"] \
		[dict create role user content "b"] \
		[dict create role user content "c"]]
	lassign [::ai::provider::anthropicMessages $hist] sys out
	set p [json::json2dict $out]

	Assert {[llength $p] == 1} "one turn"
	set uc [dict get [lindex $p 0] content]
	Assert {[llength $uc] == 3} "three blocks"
	Assert {[dict get [lindex $uc 0] text] eq "a"}
	Assert {[dict get [lindex $uc 1] text] eq "b"}
	Assert {[dict get [lindex $uc 2] text] eq "c"}
	return OK
} -result OK

test aipc-messages-not-run-3.5 {an unreplied tool call gets an is_error result} -body {
	set callX [dict create id toolu_x function [dict create name x arguments {}]]
	# interrupted mid-loop: the next user turn answers the open call first
	set hist [list \
		[dict create role user content "q"] \
		[dict create role assistant content "" tool_calls [list $callX]] \
		[dict create role user content "why?"]]
	lassign [::ai::provider::anthropicMessages $hist] sys out
	set uc [dict get [lindex [json::json2dict $out] 2] content]
	Assert {[llength $uc] == 2} "result + text"
	Assert {[dict get [lindex $uc 0] type] eq "tool_result"}
	Assert {[dict get [lindex $uc 0] tool_use_id] eq "toolu_x"}
	Assert {[dict get [lindex $uc 0] content] eq "(not run)"}
	Assert {[dict get [lindex $uc 0] is_error]} "is_error set"
	Assert {[dict get [lindex $uc 1] text] eq "why?"}

	# and at the end of the history too
	set hist2 [list \
		[dict create role user content "q"] \
		[dict create role assistant content "" tool_calls [list $callX \
			[dict create id toolu_y function [dict create name y arguments {}]]]]]
	lassign [::ai::provider::anthropicMessages $hist2] sys2 out2
	set p2 [json::json2dict $out2]
	set last [lindex $p2 end]
	Assert {[dict get $last role] eq "user"} "trailing result turn"
	set lc [dict get $last content]
	Assert {[llength $lc] == 2}
	Assert {[dict get [lindex $lc 0] tool_use_id] eq "toolu_x"}
	Assert {[dict get [lindex $lc 1] tool_use_id] eq "toolu_y"}
	Assert {[dict get [lindex $lc 1] is_error]}
	return OK
} -result OK

test aipc-messages-raw-3.6 {raw assistant content is replayed unchanged} -body {
	set raw "\[{\"type\":\"thinking\",\"thinking\":\"Hmm \\\"mate?\\\"\",\"signature\":\"c2lnLWFiYw\"},{\"type\":\"text\",\"text\":\"Done\"}]"
	set call [dict create id toolu_r function [dict create name chess_engine arguments {}]]
	set hist [list \
		[dict create role user content "q"] \
		[dict create role assistant content "" raw $raw tool_calls [list $call]] \
		[dict create role tool tool_call_id toolu_r content "ran"]]
	lassign [::ai::provider::anthropicMessages $hist] sys out

	# every raw block appears byte-identical in the outgoing messages
	foreach b [::ai::provider::jsonElements $raw] {
		Assert {[string first $b $out] >= 0} "raw span kept"
	}
	# and the tool reply still lands on the replayed call's id
	set uc [dict get [lindex [json::json2dict $out] 2] content]
	Assert {[dict get [lindex $uc 0] tool_use_id] eq "toolu_r"}
	Assert {[dict get [lindex $uc 0] content] eq "ran"}
	return OK
} -result OK

test aipc-messages-placeholders-3.7 {empty turns and replies get their placeholders} -body {
	set hist [list \
		[dict create role user content ""] \
		[dict create role assistant content ""] \
		[dict create role user content " "] \
		[dict create role assistant content "" tool_calls [list \
			[dict create id toolu_e function [dict create name e arguments {}]]]] \
		[dict create role tool tool_call_id toolu_e content ""] \
		[dict create role user content "next"]]
	lassign [::ai::provider::anthropicMessages $hist] sys out
	set p [json::json2dict $out]
	Assert {[llength $p] == 5} "turn count"
	Assert {[dict get [lindex [dict get [lindex $p 0] content] 0] text] eq "(empty)"} "empty user"
	Assert {[dict get [lindex [dict get [lindex $p 1] content] 0] text] eq "(no answer)"} "empty assistant"
	Assert {[dict get [lindex [dict get [lindex $p 4] content] 0] content] eq "(no output)"} "empty tool"

	# a tool reply owed to nothing is dropped
	lassign [::ai::provider::anthropicMessages [list [dict create role tool content "orphan"]]] sys2 out2
	Assert {$out2 eq "\[\]"} "orphan dropped"
	return OK
} -result OK


# ----------------------------------------------------------------------
# 4. ReplayBlocks
# ----------------------------------------------------------------------

test aipc-replay-blocks-4.1 {blocks before the last fallback thin out} -body {
	set raw "\[{\"type\":\"thinking\",\"thinking\":\"old\",\"signature\":\"s1\"},{\"type\":\"redacted_thinking\",\"data\":\"Zm9v\"},{\"type\":\"fallback\",\"marker\":1},{\"type\":\"text\",\"text\":\"kept\"},{\"type\":\"tool_use\",\"id\":\"toolu_late\",\"name\":\"n\",\"input\":\{\}}]"
	set els [::ai::provider::jsonElements $raw]
	set kept [::ai::provider::ReplayBlocks $raw]

	# the declined attempt's thinking/tool_use before the marker are gone;
	# the marker itself and everything from it on survive verbatim
	Assert {[llength $kept] == 3} "three kept"
	Assert {[lindex $kept 0] eq [lindex $els 2]} "fallback kept"
	Assert {[lindex $kept 1] eq [lindex $els 3]} "text kept"
	Assert {[lindex $kept 2] eq [lindex $els 4]} "late tool_use kept"
	return OK
} -result OK

test aipc-replay-blocks-4.2 {only the LAST fallback marker counts} -body {
	set raw "\[{\"type\":\"thinking\",\"thinking\":\"t1\"},{\"type\":\"fallback\",\"marker\":1},{\"type\":\"text\",\"text\":\"mid\"},{\"type\":\"thinking\",\"thinking\":\"t3\"},{\"type\":\"tool_use\",\"id\":\"late\",\"name\":\"n\",\"input\":\{\}},{\"type\":\"fallback\",\"marker\":2},{\"type\":\"tool_use\",\"id\":\"after\",\"name\":\"n\",\"input\":\{\}}]"
	set els [::ai::provider::jsonElements $raw]
	set kept [::ai::provider::ReplayBlocks $raw]

	Assert {[llength $kept] == 4} "four kept"
	Assert {[lindex $kept 0] eq [lindex $els 1]} "first fallback"
	Assert {[lindex $kept 1] eq [lindex $els 2]} "text between"
	Assert {[lindex $kept 2] eq [lindex $els 5]} "last fallback"
	Assert {[lindex $kept 3] eq [lindex $els 6]} "after last"
	return OK
} -result OK

test aipc-replay-blocks-4.3 {no fallback keeps every block} -body {
	set raw "\[{\"type\":\"thinking\",\"a\":\[1,{\"b\":2}\]},{\"type\":\"tool_use\",\"id\":\"x\"},{\"type\":\"text\",\"text\":\"t\"}]"
	set kept [::ai::provider::ReplayBlocks $raw]
	Assert {[llength $kept] == 3} "all kept"
	foreach b [::ai::provider::jsonElements $raw] k $kept {
		Assert {$b eq $k} "span kept"
	}
	return OK
} -result OK


# ----------------------------------------------------------------------
# 5. anthropicBody and anthropicHeaders
# ----------------------------------------------------------------------

test aipc-body-5.1 {the body is valid JSON and carries the core fields} -body {
	::ai::provider::configure -name anthropic -model claude-opus-5-5
	set hist [list [dict create role system content "SYS"] [dict create role user content "hi"]]
	set b [::ai::provider::anthropicBody $hist ""]
	set d [json::json2dict $b]

	Assert {[dict get $d model] eq "claude-opus-5-5"}
	Assert {[dict get $d max_tokens] == 16000} "default max_tokens"
	set d2 [json::json2dict [::ai::provider::anthropicBody $hist "" 64]]
	Assert {[dict get $d2 max_tokens] == 64} "explicit max_tokens"
	Assert {[llength [dict get $d system]] == 1}
	Assert {[dict get [lindex [dict get $d system] 0] type] eq "text"}
	Assert {[dict get [lindex [dict get $d system] 0] text] eq "SYS"}
	Assert {[llength [dict get $d messages]] == 1} "system left the turns"
	Assert {[dict get $d cache_control type] eq "ephemeral"} "prompt is cached"
	Assert {![dict exists $d tools]} "no tools asked"
	Assert {![dict exists $d tool_choice]}
	Assert {[dict get $d fallbacks] eq "default"} "opus is on the fallback list"
	Assert {[dict get $d output_config effort] eq "medium"} "default effort"
	return OK
} -result OK

test aipc-body-5.2 {tools go out auto; a prose turn keeps them with none} -body {
	global ToolsJson Fen
	::ai::provider::configure -name anthropic -model claude-opus-5-5

	# a turn with tools: the converted definitions and tool_choice auto
	set hist [list [dict create role user content "Best move?"]]
	set b [::ai::provider::anthropicBody $hist $ToolsJson]
	set d [json::json2dict $b]
	Assert {[llength [dict get $d tools]] == 2} "tools converted"
	Assert {[dict get [lindex [dict get $d tools] 0] name] eq "chess_engine"}
	Assert {[dict exists [lindex [dict get $d tools] 0] input_schema]} "input_schema"
	Assert {[dict get $d tool_choice type] eq "auto"}
	set rawTools $::ai::provider::Config(anthropicTools)
	Assert {[string first "\"tools\":$rawTools," $b] >= 0} "raw definitions in the body"

	# a prose turn (tools "") over a history with tool turns still needs
	# the definitions, so the last ones go out with tool_choice none
	set thist [list \
		[dict create role user content "Best move?"] \
		[dict create role assistant content "" tool_calls [list \
			[dict create id toolu_a function [dict create name chess_engine arguments [dict create fen $Fen depth 8]]]]] \
		[dict create role tool tool_call_id toolu_a content "eval 0.4"] \
		[dict create role assistant content "e4 is best."]]
	set b2 [::ai::provider::anthropicBody $thist ""]
	Assert {[string first "\"tools\":$rawTools,\"tool_choice\":\{\"type\":\"none\"\}" $b2] >= 0} "tools with none"
	Assert {[dict get [json::json2dict $b2] tool_choice type] eq "none"}

	# a prose turn over a plain history sends no tools at all
	set b3 [::ai::provider::anthropicBody $hist ""]
	set d3 [json::json2dict $b3]
	Assert {![dict exists $d3 tools]} "no tools in a plain turn"
	Assert {![dict exists $d3 tool_choice]}
	return OK
} -result OK

test aipc-body-5.3 {effort only for models that take it} -body {
	::ai::provider::configure -name anthropic -model claude-opus-5-5 -effort high
	set hist [list [dict create role user content "hi"]]
	set d [json::json2dict [::ai::provider::anthropicBody $hist ""]]
	Assert {[dict get $d output_config effort] eq "high"} "opus takes effort"

	::ai::provider::configure -effort ""
	set d [json::json2dict [::ai::provider::anthropicBody $hist ""]]
	Assert {![dict exists $d output_config]} "effort off"

	::ai::provider::configure -effort medium -model claude-haiku-4-5
	set d [json::json2dict [::ai::provider::anthropicBody $hist ""]]
	Assert {![dict exists $d output_config]} "haiku takes no effort"
	Assert {![dict exists $d fallbacks]} "haiku is not on the fallback list"
	return OK
} -result OK

test aipc-headers-5.4 {headers: key, version, beta only for fallback models} -body {
	::ai::provider::configure -name anthropic -model claude-opus-5-5 -keys {anthropic hdr-key}
	set h [::ai::provider::anthropicHeaders]
	Assert {[dict get $h x-api-key] eq "hdr-key"}
	Assert {[dict get $h anthropic-version] eq "2023-06-01"}
	Assert {[dict get $h anthropic-beta] eq "server-side-fallback-2026-07-01"}

	::ai::provider::configure -model claude-haiku-4-5
	set h2 [::ai::provider::anthropicHeaders]
	Assert {[dict get $h2 x-api-key] eq "hdr-key"}
	Assert {![dict exists $h2 anthropic-beta]} "no beta header for haiku"
	return OK
} -result OK


# ----------------------------------------------------------------------
# 6. anthropicReply
# ----------------------------------------------------------------------

test aipc-reply-tooluse-6.1 {tool_use becomes a tool_calls message} -body {
	global Fen
	set data "{\"id\":\"msg_9\",\"type\":\"message\",\"role\":\"assistant\",\"stop_reason\":\"tool_use\",\"content\":\[{\"type\":\"text\",\"text\":\"Let me check.\"},{\"type\":\"tool_use\",\"id\":\"toolu_9\",\"name\":\"chess_engine\",\"input\":{\"fen\":\"$Fen\",\"depth\":8}}]}"
	set msg [::ai::provider::anthropicReply $data]

	Assert {[dict get $msg role] eq "assistant"}
	Assert {[dict get $msg content] eq "Let me check."}
	Assert {[dict get $msg stop_reason] eq "tool_use"}
	set calls [dict get $msg tool_calls]
	Assert {[llength $calls] == 1} "one call"
	set c [lindex $calls 0]
	Assert {[dict get $c id] eq "toolu_9"}
	Assert {[dict get $c function name] eq "chess_engine"}
	Assert {[dict get $c function arguments fen] eq $Fen}
	Assert {[dict get $c function arguments depth] == 8}
	# the raw content rides along for the replay
	set top [::ai::provider::jsonMembers $data]
	Assert {[dict get $msg raw] eq [dict get $top content]} "raw kept"
	return OK
} -result OK

test aipc-reply-refusal-6.2 {a refusal carries no tool calls} -body {
	set data "{\"stop_reason\":\"refusal\",\"content\":\[{\"type\":\"text\",\"text\":\"no.\"},{\"type\":\"tool_use\",\"id\":\"toolu_x\",\"name\":\"n\",\"input\":\{\}}]}"
	set msg [::ai::provider::anthropicReply $data]

	Assert {[dict get $msg stop_reason] eq "refusal"}
	Assert {[dict get $msg content] eq "The model declined this request."}
	Assert {![dict exists $msg tool_calls]} "no calls from a refusal"
	Assert {![dict exists $msg raw]} "no replay of a declined attempt"
	return OK
} -result OK

test aipc-reply-maxtokens-6.3 {a cut-off answer runs no tool call} -body {
	set data "{\"stop_reason\":\"max_tokens\",\"content\":\[{\"type\":\"text\",\"text\":\"partial\"},{\"type\":\"tool_use\",\"id\":\"toolu_z\",\"name\":\"n\",\"input\":\{\}}]}"
	set msg [::ai::provider::anthropicReply $data]

	Assert {[dict get $msg stop_reason] eq "max_tokens"}
	Assert {[dict get $msg content] eq "partial\n(The answer was cut off.)"}
	Assert {![dict exists $msg tool_calls]} "no calls after max_tokens"
	return OK
} -result OK

test aipc-clouderror-6.4 {CloudError speaks about the key on 401/403} -body {
	set d401 "{\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"invalid x-api-key\"}}"
	set e [::ai::provider::CloudError Anthropic 401 $d401]
	Assert {[string match "*rejected the API key*" $e]} "401 blames the key"
	Assert {[string match "*invalid x-api-key*" $e]} "server message kept"
	set e [::ai::provider::CloudError Anthropic 403 $d401]
	Assert {[string match "*API key*" $e]} "403 blames the key"
	Assert {[string match "*busy*" [::ai::provider::CloudError OpenAI 429 "{\"error\":{\"message\":\"slow down\"}}"]]} "429 busy"
	Assert {[::ai::provider::CloudError Anthropic 500 "{\"error\":{\"message\":\"boom\"}}"] eq "Anthropic: HTTP 500: boom"} "other codes"
	Assert {[::ai::provider::CloudError Anthropic 500 "not json"] eq "Anthropic: HTTP 500: no details"} "unreadable body"
	return OK
} -result OK


# ----------------------------------------------------------------------
# 7. OpenAI adapter
# ----------------------------------------------------------------------

test aipc-openai-messages-7.1 {tool calls go out with ids and JSON-string arguments} -body {
	set hist [list \
		[dict create role system content "Be brief."] \
		[dict create role user content "Best move?"] \
		[dict create role assistant content "" tool_calls [list \
			[dict create id call_7 function [dict create name chess_engine arguments [dict create depth 8]]]]] \
		[dict create role tool tool_call_id call_7 content "eval +0.3"] \
		[dict create role assistant content "e4."]]
	set out [::ai::provider::openaiMessages $hist]
	set p [json::json2dict $out]

	Assert {[llength $p] == 5} "five messages"
	Assert {[dict get [lindex $p 0] role] eq "system"}
	Assert {[dict get [lindex $p 0] content] eq "Be brief."}
	Assert {[dict get [lindex $p 2] role] eq "assistant"}
	set tc [dict get [lindex $p 2] tool_calls]
	Assert {[llength $tc] == 1}
	set c [lindex $tc 0]
	Assert {[dict get $c id] eq "call_7"} "id kept"
	Assert {[dict get $c type] eq "function"}
	Assert {[dict get $c function name] eq "chess_engine"}
	# arguments travel as a JSON-encoded string
	Assert {[dict get $c function arguments] eq "{\"depth\":8}"} "arguments is a string"
	Assert {[dict get [json::json2dict [dict get $c function arguments]] depth] == 8} "and parses back"
	set t [lindex $p 3]
	Assert {[dict get $t role] eq "tool"}
	Assert {[dict get $t tool_call_id] eq "call_7"} "tool_call_id kept"
	Assert {[dict get $t content] eq "eval +0.3"}
	Assert {[dict get [lindex $p 4] content] eq "e4."} "plain assistant"
	Assert {![dict exists [lindex $p 4] tool_calls]}
	return OK
} -result OK

test aipc-openai-messages-7.2 {a reply without id takes the first pending call} -body {
	set hist [list \
		[dict create role assistant content "" tool_calls [list \
			[dict create id call_1 function [dict create name a arguments {}]] \
			[dict create id call_2 function [dict create name b arguments {}]]]] \
		[dict create role tool content "out1"] \
		[dict create role tool content "out2" tool_call_id call_2] \
		[dict create role tool content "orphan"]]
	set p [json::json2dict [::ai::provider::openaiMessages $hist]]

	Assert {[llength $p] == 3} "orphan dropped"
	Assert {[dict get [lindex $p 1] tool_call_id] eq "call_1"} "by order"
	Assert {[dict get [lindex $p 1] content] eq "out1"}
	Assert {[dict get [lindex $p 2] tool_call_id] eq "call_2"} "by id"
	Assert {[dict get [lindex $p 2] content] eq "out2"}
	return OK
} -result OK

test aipc-openai-reply-7.3 {openaiReply decodes arguments} -body {
	set data "{\"id\":\"c1\",\"choices\":\[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":\[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"chess_engine\",\"arguments\":\"{\\\"depth\\\":8}\"}}]}}]}"
	set msg [::ai::provider::openaiReply $data]
	Assert {[dict get $msg role] eq "assistant"}
	Assert {[dict get $msg content] eq ""} "null content is empty"
	set calls [dict get $msg tool_calls]
	Assert {[llength $calls] == 1}
	Assert {[dict get [lindex $calls 0] id] eq "call_1"}
	Assert {[dict get [lindex $calls 0] function name] eq "chess_engine"}
	Assert {[dict get [lindex $calls 0] function arguments depth] == 8} "arguments decoded"

	set data2 "{\"choices\":\[{\"message\":{\"role\":\"assistant\",\"content\":\"Hello\"}}]}"
	set msg2 [::ai::provider::openaiReply $data2]
	Assert {[dict get $msg2 content] eq "Hello"}
	Assert {![dict exists $msg2 tool_calls]} "prose only"
	return OK
} -result OK

test aipc-openai-body-7.4 {openaiBody needs a model and passes tools through} -body {
	global ToolsJson
	::ai::provider::configure -name openai -model gpt-mock
	set hist [list [dict create role user content "hi"]]
	set b [::ai::provider::openaiBody $hist ""]
	set d [json::json2dict $b]
	Assert {[dict get $d model] eq "gpt-mock"}
	Assert {[llength [dict get $d messages]] == 1}
	Assert {![dict exists $d tools]}

	set b2 [::ai::provider::openaiBody $hist $ToolsJson]
	Assert {[string first "\"tools\":$ToolsJson" $b2] >= 0} "tools pass through verbatim"
	Assert {[llength [dict get [json::json2dict $b2] tools]] == 2}

	::ai::provider::configure -model ""
	set rc [catch {::ai::provider::openaiBody $hist ""} err]
	Assert {$rc == 1} "no model errors"
	Assert {[string match "*no OpenAI model*" $err]} "with guidance"
	return OK
} -result OK


# ----------------------------------------------------------------------
# 8. end to end against the local mock server
# ----------------------------------------------------------------------

test aipc-e2e-anthropic-chat-8.1 {chatAsync over HTTP with headers and tool_calls} -body {
	global ToolsJson
	MockStart
	MockReset
	set ::Mock(body) "{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"stop_reason\":\"tool_use\",\"content\":\[{\"type\":\"text\",\"text\":\"Checking.\"},{\"type\":\"tool_use\",\"id\":\"toolu_e2e\",\"name\":\"chess_engine\",\"input\":{\"fen\":\"start\",\"depth\":8}}]}"
	::ai::provider::configure -name anthropic -model claude-opus-5-5 \
		-endpoint "http://127.0.0.1:$::Mock(port)/v1/messages" -keys {anthropic test-key}

	set hist [list [dict create role user content "Best move?"]]
	set r [AsyncRun {::ai::provider::chatAsync $hist $ToolsJson E2ESink}]
	Assert {$r ne "TIMEOUT"} "callback fired"
	Assert {[dict get $r ok]} "ok ($r)"
	set msg [dict get $r message]
	Assert {[dict get $msg role] eq "assistant"}
	Assert {[dict get $msg content] eq "Checking."}
	set calls [dict get $msg tool_calls]
	Assert {[llength $calls] == 1}
	Assert {[dict get [lindex $calls 0] id] eq "toolu_e2e"}
	Assert {[dict get [lindex $calls 0] function name] eq "chess_engine"}
	Assert {[dict get [lindex $calls 0] function arguments depth] == 8}

	# what actually reached the wire
	Assert {[llength $::Mock(requests)] == 1} "one request"
	lassign [lindex $::Mock(requests) 0] method url hdrs body
	Assert {$method eq "POST"}
	Assert {$url eq "/v1/messages"}
	Assert {[dict get $hdrs x-api-key] eq "test-key"} "x-api-key sent"
	Assert {[dict get $hdrs anthropic-version] eq "2023-06-01"} "version sent"
	Assert {[dict get $hdrs anthropic-beta] eq "server-side-fallback-2026-07-01"} "beta header"
	set bd [json::json2dict $body]
	Assert {[dict get $bd model] eq "claude-opus-5-5"}
	Assert {[llength [dict get $bd tools]] == 2} "tools on the wire"
	Assert {[dict get $bd tool_choice type] eq "auto"}
	Assert {[dict get [lindex [dict get $bd messages] 0] role] eq "user"}
	Assert {[string match "*Best move?*" $body]}
	return OK
} -result OK

test aipc-e2e-anthropic-complete-8.2 {completeAsync delivers the text} -body {
	MockStart
	MockReset
	set ::Mock(body) "{\"stop_reason\":\"end_turn\",\"content\":\[{\"type\":\"text\",\"text\":\"Hello there.\"}]}"
	::ai::provider::configure -name anthropic -model claude-opus-5-5 \
		-endpoint "http://127.0.0.1:$::Mock(port)/v1/messages" -keys {anthropic test-key}
	set r [AsyncRun {::ai::provider::completeAsync "ping" E2ESink}]
	Assert {$r ne "TIMEOUT"} "callback fired"
	Assert {[dict get $r ok]} "ok ($r)"
	Assert {[dict get $r text] eq "Hello there."}

	Assert {[llength $::Mock(requests)] == 1}
	lassign [lindex $::Mock(requests) 0] method url hdrs body
	set bd [json::json2dict $body]
	Assert {[dict get [lindex [dict get $bd messages] 0] role] eq "user"}
	Assert {[string match "*ping*" $body]}
	Assert {![dict exists $bd tools]} "a completion carries no tools"
	return OK
} -result OK

test aipc-e2e-anthropic-401-8.3 {a 401 delivers ok 0 blaming the API key} -body {
	MockStart
	MockReset
	set ::Mock(code) 401
	set ::Mock(body) "{\"type\":\"error\",\"error\":{\"type\":\"authentication_error\",\"message\":\"invalid x-api-key\"}}"
	::ai::provider::configure -name anthropic -model claude-opus-5-5 \
		-endpoint "http://127.0.0.1:$::Mock(port)/v1/messages" -keys {anthropic test-key}
	set hist [list [dict create role user content "hello"]]
	set r [AsyncRun {::ai::provider::chatAsync $hist "" E2ESink}]
	set ::Mock(code) 200

	Assert {$r ne "TIMEOUT"} "callback fired"
	Assert {![dict get $r ok]} "not ok"
	set err [dict get $r error]
	Assert {[string match "*API key*" $err]} "mentions the API key"
	Assert {[string match "*invalid x-api-key*" $err]} "server message kept"
	Assert {[string match "*Choose Model*" $err]} "says where to fix it"
	return OK
} -result OK

test aipc-e2e-openai-chat-8.4 {openai chatAsync sends Authorization Bearer} -body {
	MockStart
	MockReset
	set ::Mock(body) "{\"id\":\"c1\",\"choices\":\[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":\[{\"id\":\"call_e2e\",\"type\":\"function\",\"function\":{\"name\":\"chess_engine\",\"arguments\":\"{\\\"depth\\\":8}\"}}]}}]}"
	::ai::provider::configure -name openai -model gpt-mock \
		-endpoint "http://127.0.0.1:$::Mock(port)/v1/chat/completions" -keys {openai oai-key}

	set hist [list [dict create role user content "Best move?"]]
	set r [AsyncRun {::ai::provider::chatAsync $hist $ToolsJson E2ESink}]
	Assert {$r ne "TIMEOUT"} "callback fired"
	Assert {[dict get $r ok]} "ok ($r)"
	set msg [dict get $r message]
	set calls [dict get $msg tool_calls]
	Assert {[llength $calls] == 1}
	Assert {[dict get [lindex $calls 0] id] eq "call_e2e"}
	Assert {[dict get [lindex $calls 0] function arguments depth] == 8} "arguments decoded"

	Assert {[llength $::Mock(requests)] == 1}
	lassign [lindex $::Mock(requests) 0] method url hdrs body
	Assert {$method eq "POST"}
	Assert {$url eq "/v1/chat/completions"}
	Assert {[dict get $hdrs authorization] eq "Bearer oai-key"} "bearer header"
	set bd [json::json2dict $body]
	Assert {[dict get $bd model] eq "gpt-mock"}
	Assert {[llength [dict get $bd tools]] == 2} "tools pass through"
	return OK
} -result OK


# ----------------------------------------------------------------------
# 9. apiKey
# ----------------------------------------------------------------------

test aipc-apikey-9.1 {the environment wins over -keys} -body {
	::ai::provider::configure -name anthropic -keys {anthropic file-key openai oai-file}
	set ::env(ANTHROPIC_API_KEY) env-key
	set a [::ai::provider::apiKey anthropic]
	unset ::env(ANTHROPIC_API_KEY)
	set b [::ai::provider::apiKey anthropic]
	# an empty environment value does not shadow the key file
	set ::env(ANTHROPIC_API_KEY) ""
	set c [::ai::provider::apiKey anthropic]
	unset ::env(ANTHROPIC_API_KEY)
	set d [::ai::provider::apiKey openai]
	return [list $a $b $c $d]
} -result [list env-key file-key file-key oai-file]

test aipc-apikey-missing-9.2 {no key reports through chatAsync without a request} -body {
	MockStart
	MockReset
	::ai::provider::configure -name anthropic -model claude-opus-5-5 -keys {}
	set hist [list [dict create role user content "hello"]]
	set r [AsyncRun {::ai::provider::chatAsync $hist "" E2ESink}]
	Assert {$r ne "TIMEOUT"} "callback fired"
	Assert {![dict get $r ok]} "not ok"
	Assert {[string match "*API key*" [dict get $r error]]} "mentions the API key"
	Assert {[string match "*ANTHROPIC_API_KEY*" [dict get $r error]]} "and the env var"
	Assert {[llength $::Mock(requests)] == 0} "nothing hit the wire"

	# the same for a completion
	set r [AsyncRun {::ai::provider::completeAsync "ping" E2ESink}]
	Assert {![dict get $r ok]} "not ok"
	Assert {[string match "*API key*" [dict get $r error]]}
	Assert {[llength $::Mock(requests)] == 0} "nothing hit the wire"
	return OK
} -result OK

test aipc-apikey-openai-missing-9.3 {openai without a key reports ok 0} -body {
	::ai::provider::configure -name openai -model gpt-mock -keys {}
	set hist [list [dict create role user content "hello"]]
	set r [AsyncRun {::ai::provider::chatAsync $hist "" E2ESink}]
	Assert {![dict get $r ok]} "not ok"
	Assert {[string match "*API key*" [dict get $r error]]}
	Assert {[string match "*OPENAI_API_KEY*" [dict get $r error]]}
	Assert {[llength $::Mock(requests)] == 0}
	return OK
} -result OK


# ----------------------------------------------------------------------
# 10. the presets: configure -name picks endpoint and default model
# ----------------------------------------------------------------------

test aipc-preset-endpoint-10.1 {configure -name takes the endpoint from the Endpoint array} -body {
	foreach p {fireworks qwen gemini openai anthropic ollama} {
		# route through a name with no preset so the fresh-name branch
		# of configure drops the old endpoint before the new default
		::ai::provider::configure -name stub -model ""
		::ai::provider::configure -name $p
		Assert {$::ai::provider::Config(endpoint) eq $::ai::provider::Endpoint($p)} \
			"$p endpoint from the array ($::ai::provider::Config(endpoint))"
		Assert {$::ai::provider::Config(endpoint) ne ""} "$p has an endpoint"
	}
	return OK
} -result OK

test aipc-preset-model-10.2 {model falls back to the per-provider DefaultModel} -body {
	foreach {p want} {
		ollama    kimi-k3:cloud
		fireworks accounts/fireworks/models/glm-5p3
		qwen      qwen3.8-max
		gemini    ""
		anthropic claude-opus-5-5
		openai    ""
	} {
		::ai::provider::configure -name stub -model ""
		::ai::provider::configure -name $p
		Assert {[::ai::provider::model] eq $want} "$p default model"
		# an explicit choice still wins over the preset default
		if {$want ne ""} {
			::ai::provider::configure -model "chosen-$p"
			Assert {[::ai::provider::model] eq "chosen-$p"} "$p explicit model"
			::ai::provider::configure -model ""
			Assert {[::ai::provider::model] eq $want} "$p back to the default"
		}
	}
	return OK
} -result OK


# ----------------------------------------------------------------------
# 11. apiKey with a list of environment variables
# ----------------------------------------------------------------------

test aipc-apikey-envlist-11.1 {the first set env var wins, -keys is the fallback} -body {
	::ai::provider::configure -name qwen -keys {}
	# qwen: QWEN_TOKEN_PLAN_API_KEY first, then QWEN_API_KEY
	set ::env(QWEN_API_KEY) q-plain
	set a [::ai::provider::apiKey qwen]
	set ::env(QWEN_TOKEN_PLAN_API_KEY) q-plan
	set b [::ai::provider::apiKey qwen]
	set ::env(QWEN_TOKEN_PLAN_API_KEY) ""	;# empty does not count
	set c [::ai::provider::apiKey qwen]
	unset ::env(QWEN_TOKEN_PLAN_API_KEY)
	unset ::env(QWEN_API_KEY)
	set d [::ai::provider::apiKey qwen]

	# gemini: GEMINI_API_KEY first, then GOOGLE_API_KEY; -keys underneath
	::ai::provider::configure -keys {qwen q-file gemini g-file}
	set e [::ai::provider::apiKey qwen]
	set ::env(GOOGLE_API_KEY) g-google
	set f [::ai::provider::apiKey gemini]
	set ::env(GEMINI_API_KEY) g-primary
	set g [::ai::provider::apiKey gemini]
	unset ::env(GEMINI_API_KEY)
	unset ::env(GOOGLE_API_KEY)
	set h [::ai::provider::apiKey gemini]
	return [list $a $b $c $d $e $f $g $h]
} -result [list q-plain q-plan q-plain "" q-file g-google g-primary g-file]

test aipc-apikey-needkey-11.2 {NeedKey names the label and the first env var} -body {
	::ai::provider::configure -name qwen -keys {}
	set rc [catch {::ai::provider::NeedKey qwen} err]
	Assert {$rc == 1} "no key errors"
	Assert {[string match "*Qwen token plan*" $err]} "the label"
	Assert {[string match "*QWEN_TOKEN_PLAN_API_KEY*" $err]} "the first env var"
	set rc [catch {::ai::provider::NeedKey gemini} err]
	Assert {$rc == 1} "no key errors"
	Assert {[string match "*Gemini*" $err]} "the gemini label"
	Assert {[string match "*GEMINI_API_KEY*" $err]} "the first gemini env var"
	return OK
} -result OK


# ----------------------------------------------------------------------
# 12. cloudProvider
# ----------------------------------------------------------------------

test aipc-cloudprovider-12.1 {cloudProvider knows the presets and ollama's cloud models} -body {
	# anthropic and every OpenAI-compatible preset leave the machine
	foreach p {anthropic openai fireworks qwen gemini} {
		::ai::provider::configure -name stub -model ""
		::ai::provider::configure -name $p
		Assert {[::ai::provider::cloudProvider] == 1} "$p is cloud"
	}
	# ollama: only its cloud models are forwarded
	::ai::provider::configure -name stub -model ""
	::ai::provider::configure -name ollama -model kimi-k3:cloud
	Assert {[::ai::provider::cloudProvider] == 1} "ollama cloud model"
	::ai::provider::configure -model qwen3.5:9b
	Assert {[::ai::provider::cloudProvider] == 0} "ollama local model"
	::ai::provider::configure -model ""
	Assert {[::ai::provider::cloudProvider] == 1} "ollama default model is cloud"
	# the stub never sends
	::ai::provider::configure -name stub
	Assert {[::ai::provider::cloudProvider] == 0} "stub is not cloud"
	return OK
} -result OK


# ----------------------------------------------------------------------
# 13. end to end: the compatible presets through the openai adapter
# ----------------------------------------------------------------------

test aipc-e2e-fireworks-13.1 {fireworks rides the openai adapter with its key and label} -body {
	MockStart
	MockReset
	set ::Mock(body) "{\"id\":\"c1\",\"choices\":\[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":\[{\"id\":\"call_fw\",\"type\":\"function\",\"function\":{\"name\":\"chess_engine\",\"arguments\":\"{\\\"depth\\\":8}\"}}]}}]}"
	::ai::provider::configure -name fireworks -model "" \
		-endpoint "http://127.0.0.1:$::Mock(port)/v1/chat/completions" -keys {fireworks fw-key}

	set hist [list [dict create role user content "Best move?"]]
	set r [AsyncRun {::ai::provider::chatAsync $hist $ToolsJson E2ESink}]
	Assert {$r ne "TIMEOUT"} "callback fired"
	Assert {[dict get $r ok]} "ok ($r)"
	set calls [dict get [dict get $r message] tool_calls]
	Assert {[llength $calls] == 1} "one call"
	Assert {[dict get [lindex $calls 0] id] eq "call_fw"}
	Assert {[dict get [lindex $calls 0] function arguments depth] == 8} "arguments decoded"

	Assert {[llength $::Mock(requests)] == 1} "one request"
	lassign [lindex $::Mock(requests) 0] method url hdrs body
	Assert {$method eq "POST" && $url eq "/v1/chat/completions"} "openai adapter URL"
	Assert {[dict get $hdrs authorization] eq "Bearer fw-key"} "the fireworks key"
	set bd [json::json2dict $body]
	Assert {[dict get $bd model] eq "accounts/fireworks/models/glm-5p3"} "preset model on the wire"
	Assert {[llength [dict get $bd tools]] == 2} "tools pass through"

	# completeAsync rides the same adapter and delivers the text
	MockReset
	set ::Mock(body) "{\"choices\":\[{\"message\":{\"role\":\"assistant\",\"content\":\"From Fireworks.\"}}]}"
	set r [AsyncRun {::ai::provider::completeAsync "ping" E2ESink}]
	Assert {[dict get $r ok]} "ok ($r)"
	Assert {[dict get $r text] eq "From Fireworks."}
	lassign [lindex $::Mock(requests) 0] method url hdrs body
	Assert {[dict get $hdrs authorization] eq "Bearer fw-key"} "the fireworks key"
	Assert {![dict exists [json::json2dict $body] tools]} "a completion carries no tools"

	# errors are labelled with the preset's Label
	MockReset
	set ::Mock(code) 500
	set ::Mock(body) "{\"error\":{\"message\":\"boom\"}}"
	set r [AsyncRun {::ai::provider::chatAsync $hist "" E2ESink}]
	set ::Mock(code) 200
	Assert {$r ne "TIMEOUT"} "callback fired"
	Assert {![dict get $r ok]} "not ok"
	Assert {[dict get $r error] eq "Fireworks: HTTP 500: boom"} "labelled Fireworks"
	return OK
} -result OK

test aipc-e2e-qwen-13.2 {qwen sends its first env key and errors are labelled} -body {
	MockStart
	MockReset
	set ::Mock(body) "{\"choices\":\[{\"message\":{\"role\":\"assistant\",\"content\":\"Qwen says hi.\"}}]}"
	::ai::provider::configure -name qwen -model "" \
		-endpoint "http://127.0.0.1:$::Mock(port)/v1/chat/completions" -keys {}
	set ::env(QWEN_TOKEN_PLAN_API_KEY) q-plan-env
	set rc [catch {
		set hist [list [dict create role user content "hi"]]
		set r [AsyncRun {::ai::provider::chatAsync $hist "" E2ESink}]
	} err]
	unset ::env(QWEN_TOKEN_PLAN_API_KEY)
	if {$rc} { return -code error $err }
	Assert {$r ne "TIMEOUT"} "callback fired"
	Assert {[dict get $r ok]} "ok ($r)"
	Assert {[dict get [dict get $r message] role] eq "assistant"} "chat mode carries a message"
	Assert {[dict get [dict get $r message] content] eq "Qwen says hi."}

	Assert {[llength $::Mock(requests)] == 1} "one request"
	lassign [lindex $::Mock(requests) 0] method url hdrs body
	Assert {$method eq "POST" && $url eq "/v1/chat/completions"} "openai adapter URL"
	Assert {[dict get $hdrs authorization] eq "Bearer q-plan-env"} "the token-plan env key"
	set bd [json::json2dict $body]
	Assert {[dict get $bd model] eq "qwen3.8-max"} "preset model on the wire"

	# completeAsync with the -keys fallback
	MockReset
	set ::Mock(body) "{\"choices\":\[{\"message\":{\"role\":\"assistant\",\"content\":\"Qwen text.\"}}]}"
	::ai::provider::configure -keys {qwen q-file-key}
	set r [AsyncRun {::ai::provider::completeAsync "ping" E2ESink}]
	Assert {[dict get $r ok]} "ok ($r)"
	Assert {[dict get $r text] eq "Qwen text."}
	lassign [lindex $::Mock(requests) 0] method url hdrs body
	Assert {[dict get $hdrs authorization] eq "Bearer q-file-key"} "the -keys fallback"

	# errors are labelled with 'Qwen token plan'
	MockReset
	set ::Mock(code) 500
	set ::Mock(body) "{\"error\":{\"message\":\"boom\"}}"
	set r [AsyncRun {::ai::provider::completeAsync "ping" E2ESink}]
	set ::Mock(code) 200
	Assert {![dict get $r ok]} "not ok"
	Assert {[dict get $r error] eq "Qwen token plan: HTTP 500: boom"} "labelled Qwen token plan"
	return OK
} -result OK

test aipc-e2e-gemini-nokey-13.3 {gemini without a key reports ok 0 and never sends} -body {
	MockStart
	MockReset
	::ai::provider::configure -name gemini -model gemini-mock \
		-endpoint "http://127.0.0.1:$::Mock(port)/v1/chat/completions" -keys {}
	set hist [list [dict create role user content "hello"]]
	set r [AsyncRun {::ai::provider::chatAsync $hist "" E2ESink}]
	Assert {$r ne "TIMEOUT"} "callback fired"
	Assert {![dict get $r ok]} "not ok"
	set err [dict get $r error]
	Assert {[string match "*API key*" $err]} "mentions the API key"
	Assert {[string match "*GEMINI_API_KEY*" $err]} "and the first env var"
	Assert {[string match "*Gemini*" $err]} "with the label"
	Assert {[llength $::Mock(requests)] == 0} "nothing hit the wire"

	set r [AsyncRun {::ai::provider::completeAsync "ping" E2ESink}]
	Assert {$r ne "TIMEOUT"} "callback fired"
	Assert {![dict get $r ok]} "not ok"
	Assert {[string match "*GEMINI_API_KEY*" [dict get $r error]]} "the env var named"
	Assert {[llength $::Mock(requests)] == 0} "nothing hit the wire"
	return OK
} -result OK


# ----------------------------------------------------------------------
# 14. modelsAsync against the mock server
# ----------------------------------------------------------------------

test aipc-models-async-14.1 {modelsAsync lists, filters and strips model ids} -body {
	MockStart
	MockReset
	set ::Mock(body) "{\"data\":\[{\"id\":\"accounts/fireworks/models/glm-5p3\"},{\"id\":\"qwen3-embedding-8b\"},{\"id\":\"models/gemini-x\"},{\"id\":\"a-reranker\"}]}"
	set saved $::ai::provider::Endpoint(fireworks)
	set ::ai::provider::Endpoint(fireworks) "http://127.0.0.1:$::Mock(port)/v1/chat/completions"
	::ai::provider::configure -name fireworks -keys {fireworks m-key}
	set r [AsyncRun {::ai::provider::modelsAsync fireworks E2ESink}]
	set reqs $::Mock(requests)
	set ::ai::provider::Endpoint(fireworks) $saved
	Assert {$::ai::provider::Endpoint(fireworks) eq $saved} "endpoint restored"

	Assert {$r ne "TIMEOUT"} "callback fired"
	Assert {[dict get $r ok]} "ok ($r)"
	# sorted; embedding and reranker gone; the gemini 'models/' prefix stripped
	Assert {[dict get $r models] eq {accounts/fireworks/models/glm-5p3 gemini-x}} \
		"sorted and filtered ([dict get $r models])"

	Assert {[llength $reqs] == 1} "one request"
	lassign [lindex $reqs 0] method url hdrs body
	Assert {$method eq "GET"} "a list is a GET"
	Assert {$url eq "/v1/models"} "chat/completions mapped to models"
	Assert {[dict get $hdrs authorization] eq "Bearer m-key"} "key sent"
	return OK
} -result OK

test aipc-models-async-14.2 {a 401 model list blames the API key, labelled} -body {
	MockStart
	MockReset
	set ::Mock(code) 401
	set ::Mock(body) "{\"error\":{\"message\":\"bad key\"}}"
	set saved $::ai::provider::Endpoint(qwen)
	set ::ai::provider::Endpoint(qwen) "http://127.0.0.1:$::Mock(port)/v1/chat/completions"
	::ai::provider::configure -name qwen -keys {qwen q-key}
	set r [AsyncRun {::ai::provider::modelsAsync qwen E2ESink}]
	set ::ai::provider::Endpoint(qwen) $saved
	set ::Mock(code) 200
	Assert {$::ai::provider::Endpoint(qwen) eq $saved} "endpoint restored"

	Assert {$r ne "TIMEOUT"} "callback fired"
	Assert {![dict get $r ok]} "not ok"
	set err [dict get $r error]
	Assert {[string match "*API key*" $err]} "mentions the API key"
	Assert {[string match "*Qwen token plan*" $err]} "with the label"
	Assert {[string match "*bad key*" $err]} "server message kept"
	return OK
} -result OK

test aipc-models-async-14.3 {modelsAsync without a key reports ok 0 and never sends} -body {
	MockStart
	MockReset
	::ai::provider::configure -name gemini -model gemini-mock -keys {}
	set r [AsyncRun {::ai::provider::modelsAsync gemini E2ESink}]
	Assert {$r ne "TIMEOUT"} "callback fired"
	Assert {![dict get $r ok]} "not ok"
	Assert {[string match "*API key*" [dict get $r error]]} "mentions the API key"
	Assert {[string match "*GEMINI_API_KEY*" [dict get $r error]]} "and the env var"
	Assert {[llength $::Mock(requests)] == 0} "nothing hit the wire"
	return OK
} -result OK


# ----------------------------------------------------------------------

catch {close $::Mock(sock)}
test aipc-strip-reasoning {reasoning markers leaked into an Ollama reply are dropped} -body {
	list [::ai::provider::StripReasoning "I will run it.<|close|>think<|sep|><|open|>response<|sep|>Done: 50 games."] \
		[::ai::provider::StripReasoning "plain answer"]
} -result {{Done: 50 games.} {plain answer}}

test aipc-think {think: explicit values pass through; auto asks the model's capabilities once} -body {
	set saved $::ai::provider::Config(think)
	set out {}
	foreach v {true false {}} { set ::ai::provider::Config(think) $v; lappend out [::ai::provider::Think] }
	set ::ai::provider::Config(think) auto
	::ai::provider::configure -name ollama -model thinker:1b
	set ::ai::provider::Thinks(thinker:1b) 1
	lappend out [::ai::provider::Think]
	::ai::provider::configure -model plain:1b
	set ::ai::provider::Thinks(plain:1b) 0
	lappend out [::ai::provider::Think]
	set ::ai::provider::Config(think) $saved
	::ai::provider::configure -name stub -model ""
	set out
} -result {true false {} true {}}

foreach v [array names SavedEnv] { set ::env($v) $SavedEnv($v) }

set failed $::tcltest::numTests(Failed)
puts "AI-PROVIDER-CLOUD-FAILURES: $failed"
flush stdout
::tcltest::cleanupTests
exit $failed
