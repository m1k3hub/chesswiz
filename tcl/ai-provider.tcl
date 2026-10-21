# ======================================================================
# ::ai::provider -- provider-agnostic text completion for the language layer.
#
# Providers: `ollama` (local models and Ollama's cloud models; the
# application's default is kimi-k3:cloud, docs/ai/ASSISTANT_COVERAGE_MAP.md
# P6), `anthropic`, the OpenAI-compatible presets `openai`, `fireworks`,
# `qwen` (Qwen token plan) and `gemini`, and `stub` (deterministic, for
# tests, and the module's own default). Every provider speaks the same
# completion and chat calls; nothing here ever uploads a database.
#
#   ::ai::provider::configure -name ollama -model NAME
#   ::ai::provider::complete <prompt> ?-system <text>?
#
# `json`/`http` are required lazily so a missing tcllib package cannot break
# application startup.
#
# Shadow labelling (audit A9/A10): before a completion entry point sends a
# request, two System One gates -- the cloud egress gate (::ai::egress::decide,
# cloud providers only) and the tier router (::ai::tier::decide, every
# provider) -- are asked what they make of the prompt/request and the answer
# is only recorded, in the decision journal (::ai::journal). The request is
# built and sent exactly as before, at the same time: the gates run after 0
# and their answer reaches nothing but the journal. Nothing here holds,
# redirects or rewrites a request; 'active' routing is not implemented yet.
#
# Modes, one per feature, 'off' skipping the gate entirely:
#   SCIDB_AI_EGRESS   off | shadow   (default shadow; A9)
#   SCIDB_AI_TIER     off | shadow   (default shadow; A10)
# A gate that is absent, or that raises, leaves the request untouched.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-provider
}

package require Tcl 8.5

namespace eval ai {
namespace eval provider {

variable Config
array set Config {
	name      stub
	model     ""
	endpoint  ""
	timeoutMs 120000
	responses {}
	index     0
	system    ""
	options   {}
	think     auto
	chatResponses {}
	chatIndex 0
	keys      {}
	effort    medium
	anthropicTools ""
	callIds   0
}

# The provider and model are choices, never literals in a code path. The
# environment supplies the standalone defaults (SCIDB_AI_PROVIDER /
# SCIDB_AI_MODEL); the application overwrites both from its saved settings
# or the command line before any request is issued.
if {[info exists ::env(SCIDB_AI_PROVIDER)] && $::env(SCIDB_AI_PROVIDER) ne ""} {
	set Config(name) $::env(SCIDB_AI_PROVIDER)
}
if {[info exists ::env(SCIDB_AI_MODEL)] && $::env(SCIDB_AI_MODEL) ne ""} {
	set Config(model) $::env(SCIDB_AI_MODEL)
}

# The audit A9/A10 shadow gates: 'shadow' asks and records, 'off' does not
# ask. 'active' is deliberately not implemented (the gates only label); an
# unknown value leaves the default. Both are on by default so a session
# collects calibration data without being asked.
variable EgressMode shadow
variable TierMode   shadow

if {[info exists ::env(SCIDB_AI_EGRESS)] && $::env(SCIDB_AI_EGRESS) in {off shadow}} {
	set EgressMode $::env(SCIDB_AI_EGRESS)
}
if {[info exists ::env(SCIDB_AI_TIER)] && $::env(SCIDB_AI_TIER) in {off shadow}} {
	set TierMode $::env(SCIDB_AI_TIER)
}

} ;# namespace provider
} ;# namespace ai


proc ::ai::provider::need {pkg} {
	if {[catch {package require $pkg}]} {
		error "ai::provider requires the Tcl package '$pkg' (tcllib)"
	}
	return
}


proc ::ai::provider::configure {args} {
	variable Config

	# a new provider gets its own default endpoint unless one is given
	if {[dict exists $args -name] && [dict get $args -name] ne $Config(name)
	 && ![dict exists $args -endpoint]} {
		set Config(endpoint) ""
	}

	foreach {key value} $args {
		switch -- $key {
			-name      { set Config(name) $value }
			-model     { set Config(model) $value }
			-endpoint  { set Config(endpoint) $value }
			-timeout   { set Config(timeoutMs) $value }
			-responses { set Config(responses) $value ; set Config(index) 0 }
			-chatResponses { set Config(chatResponses) $value ; set Config(chatIndex) 0 }
			-system    { set Config(system) $value }
			-options   { set Config(options) $value }
			-think     { set Config(think) $value }
			-keys      { set Config(keys) $value }
			-effort    { set Config(effort) $value }
			default    { error "unknown option $key" }
		}
	}

	variable Endpoint
	if {$Config(endpoint) eq "" && [info exists Endpoint($Config(name))]} {
		set Config(endpoint) $Endpoint($Config(name))
	}
	return
}


proc ::ai::provider::jsonEscape {s} {
	set out ""

	foreach ch [split $s ""] {
		switch -- $ch {
			"\"" { append out "\\\"" }
			"\\" { append out "\\\\" }
			"\n" { append out "\\n" }
			"\r" { append out "\\r" }
			"\t" { append out "\\t" }
			default {
				if {[scan $ch %c cp] == 1 && $cp < 0x20} {
					append out [format "\\u%04x" $cp]
				} else {
					append out $ch
				}
			}
		}
	}
	return $out
}


proc ::ai::provider::jsonObject {pairs} {
	set out "{"
	set first 1

	foreach {k v} $pairs {
		if {!$first} { append out "," }
		set first 0
		append out "\"[jsonEscape $k]\":"
		if {[string is integer -strict $v] || [string is double -strict $v]
		 || $v eq "true" || $v eq "false"} {
			append out $v
		} else {
			append out "\"[jsonEscape $v]\""
		}
	}

	append out "}"
	return $out
}


# The https handler for ::http: a plain ::tls::socket does not send SNI,
# and many hosts (including api.typesafe.ai) reject the async handshake
# without it. The http package calls the registered command as
# <handler> ?sockopt ...? <host> <port>, so pull the host out and pass it
# as the server name as well.
proc ::ai::provider::tlsSocket {args} {
	set host [lindex $args end-1]
	set port [lindex $args end]
	set opts [lrange $args 0 end-2]
	return [::tls::socket -servername $host {*}$opts $host $port]
}


# Issue a JSON POST.  The http package writes -query as raw bytes (and sizes
# Content-Length by character count), so the body must be UTF-8 encoded here
# or any non-ASCII text corrupts the request.  https needs the tls package.
proc ::ai::provider::request {url body args} {
	variable Config
	variable TlsRegistered

	need http
	if {[string match -nocase https://* $url] && ![info exists TlsRegistered]} {
		need tls
		::platform::sys::tlsInit
		::http::register https 443 ::ai::provider::tlsSocket
		set TlsRegistered 1
	}

	return [::http::geturl $url \
		-type "application/json; charset=utf-8" \
		-query [encoding convertto utf-8 $body] \
		-timeout $Config(timeoutMs) \
		-binary 1 \
		{*}$args]
}


# The response body as a string. JSON is UTF-8 by definition (RFC 8259),
# but Ollama answers "application/json" without a charset, which http
# would decode as ISO-8859-1 -- so the request asks for the raw bytes.
proc ::ai::provider::body {token} {
	return [encoding convertfrom utf-8 [::http::data $token]]
}


# Asynchronous request; <done> gets the token.  Synchronous failures (no
# http/tls package, unresolvable host) are reported through <failed>, called
# with the error message, so the caller's callback always runs.
proc ::ai::provider::requestAsync {url body done failed {headers {}}} {
	if {[catch {request $url $body -command $done -headers $headers} err]} {
		after 0 [list {*}$failed $err]
	}
	return
}


# A request that never got a reply (no connection, timeout) means the
# provider is down: the caller may try a backup model ("down 1").
proc ::ai::provider::failAsync {script err} {
	uplevel #0 [list {*}$script [list ok 0 error $err down 1]]
}


# ----------------------------------------------------------------------
# Shadow labelling (audit A9/A10).  Each gate is asked what it makes of
# an outgoing request and its answer is recorded in the decision journal;
# nothing here returns anything, blocks anything or edits a request.  The
# gates are asked through 'after 0', so a classifier that is slow (or
# never answers) cannot delay the send that is already under way.
# ----------------------------------------------------------------------

# Is the configured provider one that leaves this machine?  The local-first
# default (stub, or the local ollama daemon) is not; the remote adapters are.
# A stub is a test stand-in, never a send, so it is not cloud either.
proc ::ai::provider::cloudProvider {} {
	variable Config

	variable Compatible
	if {$Config(name) eq "anthropic" || $Config(name) in $Compatible} { return 1 }
	# Ollama forwards its cloud models
	return [expr {$Config(name) eq "ollama" && [string match *cloud* [model]]}]
}

# Record one gate's answer against the provider that actually served the
# request.  The feature/state keys are what the calibration reads back
# (::ai::journal::read); the script is handed the gate's own decision.
proc ::ai::provider::ShadowSink {feature state decision} {
	catch { ::ai::journal::decision $feature $state $decision }
	return
}

# A9: ask the cloud egress gate about a prompt that is about to leave for a
# cloud provider.  The prompt is the gate's state: judging what a prompt
# carries takes the prompt.  Local traffic is private by construction here,
# so it is not labelled.
proc ::ai::provider::shadowEgress {prompt} {
	variable EgressMode

	if {$EgressMode eq "off"} { return }
	if {[llength [info commands ::ai::egress::decide]] == 0} { return }
	if {![cloudProvider]} { return }

	catch {
		::ai::egress::decide $prompt \
			[namespace code [list ::ai::provider::ShadowSink egress $prompt]]
	}
	return
}

# A10: ask the tier router about the request and the tools it may touch.
# Every provider is labelled, so the tier a request wanted can be compared
# with the provider that served it.  The state is the router's own summary
# (::ai::tier::State), not the raw request.
proc ::ai::provider::shadowTier {request tools} {
	variable TierMode

	if {$TierMode eq "off"} { return }
	if {[llength [info commands ::ai::tier::decide]] == 0} { return }

	set state $request
	catch { set state [::ai::tier::State $request $tools] }
	catch {
		::ai::tier::decide $request $tools \
			[namespace code [list ::ai::provider::ShadowSink tier $state]]
	}
	return
}

# Ask both gates about one outgoing request.  Called by the completion entry
# points just before they send; the send itself is not touched.
proc ::ai::provider::shadow {prompt {tools ""}} {
	if {[string trim $prompt] eq ""} { return }
	after 0 [namespace code [list shadowEgress $prompt]]
	after 0 [namespace code [list shadowTier $prompt $tools]]
	return
}

# The request a chat carries: its last user message, which is what the tier
# router judges.  A message without a readable role or content is skipped.
proc ::ai::provider::requestText {messages} {
	for {set i [expr {[llength $messages] - 1}]} {$i >= 0} {incr i -1} {
		set msg [lindex $messages $i]
		if {[catch { dict get $msg role } role] || $role ne "user"} { continue }
		return [expr {[dict exists $msg content] ? [dict get $msg content] : ""}]
	}
	return ""
}


proc ::ai::provider::post {body args} {
	variable Config
	array set opts [list -headers {} -url ""]
	array set opts $args

	set url [expr {$opts(-url) ne "" ? $opts(-url) : $Config(endpoint)}]
	set token [request $url $body -headers $opts(-headers)]

	set status [::http::status $token]
	set code [::http::ncode $token]
	set data [body $token]
	::http::cleanup $token

	if {$status ne "ok" || $code != 200} {
		error "ai::provider: HTTP $code $status from $url"
	}
	return $data
}


proc ::ai::provider::complete {prompt args} {
	variable Config
	array set opts [list -system $Config(system)]
	array set opts $args

	# A9/A10: label the outgoing prompt (shadow only; see the header).
	shadow $prompt

	switch -- $Config(name) {
		stub      { return [stub $prompt] }
		ollama    { return [ollama $prompt $opts(-system)] }
		openai - fireworks - qwen - gemini { return [openai $prompt $opts(-system)] }
		anthropic { return [anthropic $prompt $opts(-system)] }
		default   { error "ai::provider: unknown provider '$Config(name)'" }
	}
}


proc ::ai::provider::stub {prompt} {
	variable Config

	if {[llength $Config(responses)] == 0} {
		return "(stub provider: no -responses configured)"
	}

	set i $Config(index)
	if {$i >= [llength $Config(responses)]} {
		set i [expr {[llength $Config(responses)] - 1}]
	} else {
		incr Config(index)
	}
	return [lindex $Config(responses) $i]
}


# ----------------------------------------------------------------------
# Asynchronous completion.  The callback <script> is invoked with a single
# dict: {ok 1 text ...} on success, or {ok 0 error ...} on failure.
# ----------------------------------------------------------------------

proc ::ai::provider::completeAsync {prompt script args} {
	variable Config
	array set opts [list -system $Config(system)]
	array set opts $args

	# A9/A10: label the outgoing prompt (shadow only; see the header).
	shadow $prompt

	switch -- $Config(name) {
		stub   { after 0 [list {*}$script [list ok 1 text [stub $prompt]]] }
		ollama { ollamaAsync $prompt $opts(-system) $script }
		anthropic - openai - fireworks - qwen - gemini {
			set messages {}
			if {$opts(-system) ne ""} { lappend messages [dict create role system content $opts(-system)] }
			lappend messages [dict create role user content $prompt]
			cloudChatAsync $messages "" $script text
		}
		default {
			after 0 [list {*}$script [list ok 0 error "async not supported for provider '$Config(name)'"]]
		}
	}
	return
}


proc ::ai::provider::ollamaAsync {prompt system script} {
	variable Config
	if {[catch {need json} err]} {
		after 0 [list [namespace current]::failAsync $script $err]
		return
	}

	requestAsync $Config(endpoint) [ollamaBody $prompt $system] \
		[namespace code [list ::ai::provider::onOllama $script]] \
		[namespace code [list ::ai::provider::failAsync $script]]
	return
}


proc ::ai::provider::onOllama {script token} {
	set status [::http::status $token]
	set code [::http::ncode $token]
	set data [body $token]
	::http::cleanup $token

	if {$status ne "ok" || $code != 200} {
		set down [expr {$status ne "ok" || $code == 429 || $code >= 500}]
		uplevel #0 [list {*}$script [list ok 0 error "HTTP $code $status" down $down]]
		return
	}

	if {[catch {set d [json::json2dict $data] ; set text [dict get $d response]} e]} {
		uplevel #0 [list {*}$script [list ok 0 error $e]]
		return
	}

	uplevel #0 [list {*}$script [list ok 1 text $text]]
	return
}


# Whether an Ollama request asks the model to think: true, false, "" (the
# server's default), or auto -- think when the model can. Thinking made the
# assistant call the right tool far more often (kimi-k3: 98% against 88% of
# the request corpus, tests/run_assistant_corpus.tcl).
proc ::ai::provider::Think {} {
	variable Config
	if {$Config(think) ne "auto"} { return $Config(think) }
	return [expr {[OllamaThinks [model]] ? "true" : ""}]
}


# Whether Ollama says <model> can think (/api/show capabilities); asked once
# per model, and "no" when the server does not answer.
proc ::ai::provider::OllamaThinks {model} {
	variable Config
	variable Thinks

	if {[info exists Thinks($model)]} { return $Thinks($model) }
	set Thinks($model) 0
	set base [regsub {/api/.*$} $Config(endpoint) {}]
	if {$base eq "" || $model eq ""} { return 0 }
	catch {
		need http
		need json
		set token [::http::geturl $base/api/show -timeout 3000 -binary 1 \
			-type application/json -query [encoding convertto utf-8 "\{\"model\":\"[jsonEscape $model]\"\}"]]
		if {[::http::ncode $token] == 200} {
			set d [json::json2dict [body $token]]
			if {[dict exists $d capabilities] && "thinking" in [dict get $d capabilities]} {
				set Thinks($model) 1
			}
		}
		::http::cleanup $token
	}
	return $Thinks($model)
}


proc ::ai::provider::ollamaBody {prompt system} {
	variable Config

	set body "{\"model\":\"[jsonEscape [model]]\",\"prompt\":\"[jsonEscape $prompt]\",\"stream\":false"
	if {[set think [Think]] ne ""} {
		append body ",\"think\":$think"
	}
	if {$system ne ""} {
		append body ",\"system\":\"[jsonEscape $system]\""
	}
	if {[llength $Config(options)]} {
		append body ",\"options\":[jsonObject $Config(options)]"
	}
	append body "}"
	return $body
}


proc ::ai::provider::ollama {prompt system} {
	need json

	set data [post [ollamaBody $prompt $system]]
	set d [json::json2dict $data]
	if {![dict exists $d response]} {
		error "ai::provider: unexpected Ollama response"
	}
	return [dict get $d response]
}


# ----------------------------------------------------------------------
# Cloud providers: Anthropic (Messages API) and OpenAI (Chat Completions).
#
# Both speak the same internal message format as the Ollama chat: dicts
# with role (system|user|assistant|tool) and content; an assistant message
# may carry tool_calls ({id function {name arguments}}), and a tool message
# answers the calls in order (tool_call_id when known). The adapters
# translate that format at the edge, so the assistant and the features
# never see a provider's wire format.
#
# The key comes from the environment (ANTHROPIC_API_KEY, OPENAI_API_KEY)
# or from configure -keys (the application's key file).
# ----------------------------------------------------------------------

namespace eval ai {
namespace eval provider {

# Per provider: the model used when none is chosen, the environment
# variables that may hold the key (first set one wins), the endpoint and
# the name shown to the user. The OpenAI-compatible presets all go through
# the openai adapter.
variable DefaultModel
array set DefaultModel {
	ollama    kimi-k3:cloud
	anthropic claude-opus-5-5
	openai    ""
	fireworks accounts/fireworks/models/glm-5p3
	qwen      qwen3.8-max
	gemini    ""
}

variable KeyEnv
array set KeyEnv {
	anthropic ANTHROPIC_API_KEY
	openai    OPENAI_API_KEY
	fireworks FIREWORKS_API_KEY
	qwen      {QWEN_TOKEN_PLAN_API_KEY QWEN_API_KEY}
	gemini    {GEMINI_API_KEY GOOGLE_API_KEY}
}

variable Endpoint
array set Endpoint {
	ollama    http://localhost:11434/api/generate
	anthropic https://api.anthropic.com/v1/messages
	openai    https://api.openai.com/v1/chat/completions
	fireworks https://api.fireworks.ai/inference/v1/chat/completions
	qwen      https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/chat/completions
	gemini    https://generativelanguage.googleapis.com/v1beta/openai/chat/completions
}

variable Label
array set Label {
	ollama    Ollama
	anthropic Anthropic
	openai    OpenAI
	fireworks Fireworks
	qwen      "Qwen token plan"
	gemini    Gemini
}

# The providers spoken through the OpenAI Chat Completions adapter.
variable Compatible {openai fireworks qwen gemini}

# Claude models that take output_config.effort, and those that take the
# server-side refusal fallback in its "default" form.
variable EffortModels {^claude-(opus|fable|mythos)-|^claude-sonnet-(5|4-6)}
variable FallbackModels {claude-fable-5-1 claude-opus-5-5 claude-opus-5 claude-sonnet-5-5}

} ;# namespace provider
} ;# namespace ai


proc ::ai::provider::model {} {
	variable Config
	variable DefaultModel

	if {$Config(model) ne ""} { return $Config(model) }
	if {[info exists DefaultModel($Config(name))]} { return $DefaultModel($Config(name)) }
	return ""
}


# The API key of a cloud provider: the environment first, then the key the
# application configured. Empty when there is none.
proc ::ai::provider::apiKey {provider} {
	variable Config
	variable KeyEnv

	if {[info exists KeyEnv($provider)]} {
		foreach var $KeyEnv($provider) {
			if {[info exists ::env($var)] && [string length $::env($var)]} { return $::env($var) }
		}
	}
	if {[dict exists $Config(keys) $provider]} { return [dict get $Config(keys) $provider] }
	return ""
}


proc ::ai::provider::label {provider} {
	variable Label
	return [expr {[info exists Label($provider)] ? $Label($provider) : $provider}]
}


proc ::ai::provider::NeedKey {provider} {
	variable KeyEnv

	set key [apiKey $provider]
	if {$key eq ""} {
		error "no API key for [label $provider]: enter one in Extras > AI: Choose Model (or set [lindex $KeyEnv($provider) 0])"
	}
	return $key
}


# ----------------------------------------------------------------------
# Raw JSON spans. json::json2dict loses the types of what it decodes (the
# string "1990" and the number 1990 come back alike), so text that must go
# back to a server unchanged -- an Anthropic reply's content, whose
# thinking blocks are signed, and the JSON Schemas of the tools -- is kept
# as the exact text it arrived as. These helpers cut a JSON text into the
# raw texts of its members or elements; they never re-encode anything.
# ----------------------------------------------------------------------

proc ::ai::provider::JsonNext {text i} {
	if {![regexp -start $i -indices {\S} $text pos]} { error "truncated JSON" }
	return [lindex $pos 0]
}


# The index just after the JSON value that starts at or after <i>.
proc ::ai::provider::JsonSkip {text i} {
	set i [JsonNext $text $i]
	set c [string index $text $i]

	if {$c eq "\""} {
		if {![regexp -start $i -indices {\A"(?:[^"\\]|\\.)*"} $text span]} {
			error "bad JSON string at $i"
		}
		return [expr {[lindex $span 1] + 1}]
	}
	if {$c eq "\{" || $c eq "\["} {
		set close [expr {$c eq "\{" ? "\}" : "\]"}]
		incr i
		while {1} {
			set i [JsonNext $text $i]
			set c [string index $text $i]
			if {$c eq $close} { return [expr {$i + 1}] }
			if {$c eq "," || $c eq ":"} { incr i; continue }
			set i [JsonSkip $text $i]
		}
	}
	if {![regexp -start $i -indices {[-+0-9.eEa-z]+} $text span] || [lindex $span 0] != $i} {
		error "bad JSON value at $i"
	}
	return [expr {[lindex $span 1] + 1}]
}


# A JSON object as a list {key rawValue ...}: keys decoded, values raw.
proc ::ai::provider::jsonMembers {text} {
	set i [JsonNext $text 0]
	if {[string index $text $i] ne "\{"} { error "not a JSON object" }
	incr i
	set out {}
	while {1} {
		set i [JsonNext $text $i]
		set c [string index $text $i]
		if {$c eq "\}"} { return $out }
		if {$c eq ","} { incr i; continue }
		set end [JsonSkip $text $i]
		set key [lindex [json::json2dict "\[[string range $text $i [expr {$end - 1}]]\]"] 0]
		set i [JsonNext $text $end]
		if {[string index $text $i] ne ":"} { error "bad JSON object" }
		set start [JsonNext $text [expr {$i + 1}]]
		set i [JsonSkip $text $start]
		lappend out $key [string range $text $start [expr {$i - 1}]]
	}
}


# A JSON array as a list of the raw texts of its elements.
proc ::ai::provider::jsonElements {text} {
	set i [JsonNext $text 0]
	if {[string index $text $i] ne "\["} { error "not a JSON array" }
	incr i
	set out {}
	while {1} {
		set i [JsonNext $text $i]
		set c [string index $text $i]
		if {$c eq "\]"} { return $out }
		if {$c eq ","} { incr i; continue }
		set end [JsonSkip $text $i]
		lappend out [string range $text $i [expr {$end - 1}]]
		set i $end
	}
}


# The decoded value of a raw JSON string literal ("" for anything else).
proc ::ai::provider::jsonString {raw} {
	if {[string index [string trim $raw] 0] ne "\""} { return "" }
	return [lindex [json::json2dict "\[$raw\]"] 0]
}


# The type of a raw content block.
proc ::ai::provider::BlockType {raw} {
	set m [jsonMembers $raw]
	return [expr {[dict exists $m type] ? [jsonString [dict get $m type]] : ""}]
}


# Tool ids for calls that came without one (a history begun on Ollama).
proc ::ai::provider::CallId {call} {
	variable Config
	if {[dict exists $call id] && [dict get $call id] ne ""} { return [dict get $call id] }
	return "toolu_scidb_[incr Config(callIds)]"
}


# ----------------------------------------------------------------------
# Anthropic
# ----------------------------------------------------------------------

# The tools of the Ollama/OpenAI format ([{"type":"function","function":
# {name description parameters}}]) as Anthropic tools; names, descriptions
# and schemas are carried over as raw text.
proc ::ai::provider::anthropicTools {tools} {
	set out {}
	foreach def [jsonElements $tools] {
		set fn [jsonMembers [dict get [jsonMembers $def] function]]
		set desc [expr {[dict exists $fn description] ? [dict get $fn description] : "\"\""}]
		set params [expr {[dict exists $fn parameters] ? [dict get $fn parameters] : "{\"type\":\"object\"}"}]
		lappend out "{\"name\":[dict get $fn name],\"description\":$desc,\"input_schema\":$params}"
	}
	return "\[[join $out ,]\]"
}


# The blocks of a raw assistant content array that may go back to the
# server. After a refusal fallback, the thinking and tool_use blocks before
# the last fallback marker belong to the declined attempt and are left out.
proc ::ai::provider::ReplayBlocks {raw} {
	set blocks [jsonElements $raw]
	set types [lmap b $blocks { BlockType $b }]
	set last [lsearch -exact -all $types fallback]
	if {![llength $last]} { return $blocks }
	set last [lindex $last end]
	set out {}
	foreach b $blocks t $types k [lsearch -all $types *] {
		if {$k < $last && $t in {thinking redacted_thinking tool_use}} { continue }
		lappend out $b
	}
	return $out
}


# The internal messages as {system messagesJson}: system messages are
# joined into the system prompt, tool replies become tool_result blocks in
# the next user turn, and consecutive turns of one role are merged.
proc ::ai::provider::anthropicMessages {messages} {
	set system {}
	set turns {}		;# {role blocks} ...
	set pending {}		;# tool_use ids still owed a result
	set results {}

	foreach msg $messages {
		set role [dict get $msg role]
		set content [expr {[dict exists $msg content] ? [dict get $msg content] : ""}]

		if {$role eq "system"} {
			if {$content ne ""} { lappend system $content }
			continue
		}
		if {$role eq "tool"} {
			if {[dict exists $msg tool_call_id] && [set k [lsearch -exact $pending [dict get $msg tool_call_id]]] >= 0} {
				set id [lindex $pending $k]
				set pending [lreplace $pending $k $k]
			} elseif {[llength $pending]} {
				set pending [lassign $pending id]
			} else {
				continue	;# a reply to no call
			}
			if {$content eq ""} { set content "(no output)" }
			lappend results [format {{"type":"tool_result","tool_use_id":"%s","content":"%s"}} \
				[jsonEscape $id] [jsonEscape $content]]
			continue
		}

		# A user or assistant turn ends the tool replies; a call that got
		# none (an interrupted loop) is answered so the history stays valid.
		foreach id $pending {
			lappend results [format {{"type":"tool_result","tool_use_id":"%s","content":"(not run)","is_error":true}} \
				[jsonEscape $id]]
		}
		set pending {}
		if {[llength $results]} {
			lappend turns user $results
			set results {}
		}

		if {$role eq "assistant"} {
			set calls [expr {[dict exists $msg tool_calls] ? [dict get $msg tool_calls] : {}}]
			if {[dict exists $msg raw]} {
				set blocks [ReplayBlocks [dict get $msg raw]]
				foreach call $calls { lappend pending [dict get $call id] }
			} else {
				set blocks {}
				if {[string trim $content] ne ""} {
					lappend blocks [format {{"type":"text","text":"%s"}} [jsonEscape $content]]
				}
				foreach call $calls {
					set id [CallId $call]
					set fn [dict get $call function]
					set args [expr {[dict exists $fn arguments] ? [dict get $fn arguments] : {}}]
					lappend blocks [format {{"type":"tool_use","id":"%s","name":"%s","input":%s}} \
						[jsonEscape $id] [jsonEscape [dict get $fn name]] [jsonObject $args]]
					lappend pending $id
				}
			}
			if {![llength $blocks]} { set blocks [list {{"type":"text","text":"(no answer)"}}] }
			lappend turns assistant $blocks
		} else {
			if {[string trim $content] eq ""} { set content "(empty)" }
			lappend turns user [list [format {{"type":"text","text":"%s"}} [jsonEscape $content]]]
		}
	}

	foreach id $pending {
		lappend results [format {{"type":"tool_result","tool_use_id":"%s","content":"(not run)","is_error":true}} \
			[jsonEscape $id]]
	}
	if {[llength $results]} { lappend turns user $results }

	# merge consecutive turns of one role
	set out {}
	set lastRole ""
	set acc {}
	foreach {role blocks} $turns {
		if {$role eq $lastRole} {
			lappend acc {*}$blocks
			continue
		}
		if {$lastRole ne ""} { lappend out [format {{"role":"%s","content":[%s]}} $lastRole [join $acc ,]] }
		set lastRole $role
		set acc $blocks
	}
	if {$lastRole ne ""} { lappend out [format {{"role":"%s","content":[%s]}} $lastRole [join $acc ,]] }

	return [list [join $system "\n\n"] "\[[join $out ,]\]"]
}


proc ::ai::provider::HasToolTurns {messages} {
	foreach msg $messages {
		if {[dict get $msg role] eq "tool"} { return 1 }
		if {[dict exists $msg tool_calls] && [llength [dict get $msg tool_calls]]} { return 1 }
	}
	return 0
}


# The request body. <tools> is the Ollama/OpenAI tools JSON, or "" for a
# turn that must answer in prose. A history with tool turns still needs the
# definitions, so such a turn sends the last ones with tool_choice none.
proc ::ai::provider::anthropicBody {messages tools {maxTokens 16000}} {
	variable Config
	variable EffortModels
	variable FallbackModels

	set model [model]
	lassign [anthropicMessages $messages] system msgs

	set body "\{\"model\":\"[jsonEscape $model]\",\"max_tokens\":$maxTokens"
	if {$system ne ""} {
		append body [format {,"system":[{"type":"text","text":"%s"}]} [jsonEscape $system]]
	}
	append body ",\"messages\":$msgs"

	set choice auto
	if {$tools ne ""} {
		set Config(anthropicTools) [anthropicTools $tools]
	} elseif {[HasToolTurns $messages] && $Config(anthropicTools) ne ""} {
		set choice none
	}
	if {$tools ne "" || $choice eq "none"} {
		append body ",\"tools\":$Config(anthropicTools),\"tool_choice\":{\"type\":\"$choice\"}"
	}
	if {$Config(effort) ne "" && [regexp $EffortModels $model]} {
		append body ",\"output_config\":{\"effort\":\"[jsonEscape $Config(effort)]\"}"
	}
	if {$model in $FallbackModels} {
		append body ",\"fallbacks\":\"default\""
	}
	# the prompt prefix (tools, system, earlier turns) is cached
	append body ",\"cache_control\":{\"type\":\"ephemeral\"}\}"
	return $body
}


proc ::ai::provider::anthropicHeaders {} {
	variable FallbackModels

	set headers [list x-api-key [NeedKey anthropic] anthropic-version 2023-06-01]
	if {[model] in $FallbackModels} {
		lappend headers anthropic-beta server-side-fallback-2026-07-01
	}
	return $headers
}


# The configured endpoint (configure sets each provider's default; a test
# points it at a local server).
proc ::ai::provider::anthropicUrl {} {
	variable Config
	if {$Config(endpoint) ne ""} { return $Config(endpoint) }
	return https://api.anthropic.com/v1/messages
}


# A Messages API response as an internal assistant message. The raw
# content stays with the message (key raw) so the next request sends it
# back unchanged.
proc ::ai::provider::anthropicReply {data} {
	set top [jsonMembers $data]
	set stop [expr {[dict exists $top stop_reason] ? [jsonString [dict get $top stop_reason]] : ""}]
	set raw [expr {[dict exists $top content] ? [dict get $top content] : "\[\]"}]
	set blocks [ReplayBlocks $raw]

	set texts {}
	set calls {}
	foreach b $blocks {
		switch -- [BlockType $b] {
			text {
				lappend texts [dict get [json::json2dict $b] text]
			}
			tool_use {
				set d [json::json2dict $b]
				set input [expr {[dict exists $d input] ? [dict get $d input] : {}}]
				lappend calls [dict create id [dict get $d id] \
					function [dict create name [dict get $d name] arguments $input]]
			}
		}
	}

	set msg [dict create role assistant content [join $texts "\n"] stop_reason $stop]
	switch -- $stop {
		refusal {
			dict set msg content "The model declined this request."
			return $msg
		}
		max_tokens {
			# a call cut off mid-way must not run
			dict append msg content "\n(The answer was cut off.)"
			return $msg
		}
	}
	dict set msg raw "\[[join $blocks ,]\]"
	if {[llength $calls]} { dict set msg tool_calls $calls }
	return $msg
}


# The message of an error response, for the user.
proc ::ai::provider::CloudError {provider code data} {
	set text ""
	catch {
		set d [json::json2dict $data]
		# Gemini can wrap an error object in an array.
		if {[string index [string trimleft $data] 0] eq "\["} { set d [lindex $d 0] }
		if {[dict exists $d error message]} { set text [dict get $d error message] }
	}
	switch -- $code {
		401 - 403 {
			return "$provider rejected the API key ($text). Enter a valid key in Extras > AI: Choose Model."
		}
		429 { return "$provider is busy or the account's limit is reached ($text). Try again shortly." }
	}
	if {$text eq ""} { set text [string range [string trim $data] 0 2000] }
	if {$text eq ""} { set text "no details" }
	return "$provider: HTTP $code: $text"
}


proc ::ai::provider::anthropicChat {messages tools} {
	need json
	set token [request [anthropicUrl] [anthropicBody $messages $tools] -headers [anthropicHeaders]]
	set code [::http::ncode $token]
	set status [::http::status $token]
	set data [body $token]
	::http::cleanup $token
	if {$status ne "ok" || $code != 200} { error [CloudError Anthropic $code $data] }
	return [anthropicReply $data]
}


proc ::ai::provider::anthropic {prompt system} {
	set messages {}
	if {$system ne ""} { lappend messages [dict create role system content $system] }
	lappend messages [dict create role user content $prompt]
	return [dict get [anthropicChat $messages ""] content]
}


# ----------------------------------------------------------------------
# OpenAI (Chat Completions). Its tools format is the one the assistant
# builds, so tools pass through as they are.
# ----------------------------------------------------------------------

proc ::ai::provider::openaiMessages {messages} {
	set out {}
	set pending {}

	foreach msg $messages {
		set role [dict get $msg role]
		set content [expr {[dict exists $msg content] ? [dict get $msg content] : ""}]

		switch -- $role {
			tool {
				if {[dict exists $msg tool_call_id]} {
					set id [dict get $msg tool_call_id]
					set k [lsearch -exact $pending $id]
					if {$k >= 0} { set pending [lreplace $pending $k $k] }
				} elseif {[llength $pending]} {
					set pending [lassign $pending id]
				} else {
					continue
				}
				lappend out [format {{"role":"tool","tool_call_id":"%s","content":"%s"}} \
					[jsonEscape $id] [jsonEscape $content]]
			}
			assistant {
				set calls [expr {[dict exists $msg tool_calls] ? [dict get $msg tool_calls] : {}}]
				set enc {}
				foreach call $calls {
					set id [CallId $call]
					set fn [dict get $call function]
					set args [expr {[dict exists $fn arguments] ? [dict get $fn arguments] : {}}]
					set encoded [format {{"id":"%s","type":"function","function":{"name":"%s","arguments":"%s"}}} \
						[jsonEscape $id] [jsonEscape [dict get $fn name]] [jsonEscape [jsonObject $args]]]
					# Gemini signs each function call. Keep the opaque JSON span;
					# forwarding its extension to other providers is unsupported.
					if {[Current] eq "gemini" && [dict exists $call openai_extra_content]} {
						set encoded [string range $encoded 0 end-1]
						append encoded ,\"extra_content\": [dict get $call openai_extra_content] \}
					}
					lappend enc $encoded
					lappend pending $id
				}
				if {[llength $enc]} {
					lappend out [format {{"role":"assistant","content":"%s","tool_calls":[%s]}} \
						[jsonEscape $content] [join $enc ,]]
				} else {
					lappend out [format {{"role":"assistant","content":"%s"}} [jsonEscape $content]]
				}
			}
			default {
				lappend out [format {{"role":"%s","content":"%s"}} [jsonEscape $role] [jsonEscape $content]]
			}
		}
	}
	return "\[[join $out ,]\]"
}


proc ::ai::provider::openaiReply {data} {
	set d [json::json2dict $data]
	set m [dict get [lindex [dict get $d choices] 0] message]
	set content [expr {[dict exists $m content] && [dict get $m content] ne "null" ? [dict get $m content] : ""}]
	set msg [dict create role assistant content $content]
	if {[dict exists $m tool_calls] && [dict get $m tool_calls] ne "null"} {
		set calls {}
		# Decode arguments for tool execution, retain provider metadata as JSON.
		set top [jsonMembers $data]
		set choice [jsonMembers [lindex [jsonElements [dict get $top choices]] 0]]
		set rawMessage [jsonMembers [dict get $choice message]]
		foreach c [dict get $m tool_calls] rawCall [jsonElements [dict get $rawMessage tool_calls]] {
			set fn [dict get $c function]
			set args {}
			catch { set args [json::json2dict [dict get $fn arguments]] }
			set call [dict create id [dict get $c id] \
				function [dict create name [dict get $fn name] arguments $args]]
			set fields [jsonMembers $rawCall]
			if {[dict exists $fields extra_content]} {
				dict set call openai_extra_content [dict get $fields extra_content]
			}
			lappend calls $call
		}
		if {[llength $calls]} { dict set msg tool_calls $calls }
	}
	return $msg
}


proc ::ai::provider::openaiBody {messages tools} {
	variable Config
	set model [model]
	if {$model eq ""} { error "no [label [Current]] model chosen: pick one in Extras > AI: Choose Model" }
	set body "\{\"model\":\"[jsonEscape $model]\",\"messages\":[openaiMessages $messages]"
	if {$tools ne ""} { append body ",\"tools\":$tools" }
	# GLM on Fireworks thinks for minutes unbounded; medium answers in seconds
	if {[Current] eq "fireworks" && $Config(effort) ne ""} {
		append body ",\"reasoning_effort\":\"[jsonEscape $Config(effort)]\""
	}
	return "$body\}"
}


proc ::ai::provider::openaiUrl {} {
	variable Config
	if {$Config(endpoint) ne ""} { return $Config(endpoint) }
	return https://api.openai.com/v1/chat/completions
}


# The configured provider, or openai when it is not an OpenAI-compatible one
# (the adapter's own calls from tests).
proc ::ai::provider::Current {} {
	variable Config
	variable Compatible
	return [expr {$Config(name) in $Compatible ? $Config(name) : "openai"}]
}


proc ::ai::provider::openaiChat {messages tools} {
	need json
	set headers [list Authorization "Bearer [NeedKey [Current]]"]
	set token [request [openaiUrl] [openaiBody $messages $tools] -headers $headers]
	set code [::http::ncode $token]
	set status [::http::status $token]
	set data [body $token]
	::http::cleanup $token
	if {$status ne "ok" || $code != 200} { error [CloudError [label [Current]] $code $data] }
	return [openaiReply $data]
}


proc ::ai::provider::openai {prompt system} {
	set messages {}
	if {$system ne ""} { lappend messages [dict create role system content $system] }
	lappend messages [dict create role user content $prompt]
	return [dict get [openaiChat $messages ""] content]
}


# The chat models an OpenAI-compatible preset offers (GET .../models).
# <script> gets {ok 1 models {id ...}} (sorted; embedding, reranking,
# image and speech models left out) or {ok 0 error E}.
proc ::ai::provider::modelsAsync {provider script {timeoutMs 8000}} {
	variable Endpoint
	variable TlsRegistered

	if {[catch {
		need http
		need json
		set key [NeedKey $provider]
		set url [string map {/chat/completions /models} $Endpoint($provider)]
		if {[string match -nocase https://* $url] && ![info exists TlsRegistered]} {
			need tls
			::platform::sys::tlsInit
			::http::register https 443 ::ai::provider::tlsSocket
			set TlsRegistered 1
		}
		::http::geturl $url -headers [list Authorization "Bearer $key"] -timeout $timeoutMs \
			-binary 1 -command [namespace code [list OnModelList $provider $script]]
	} err]} {
		after 0 [list [namespace current]::failAsync $script $err]
	}
	return
}


proc ::ai::provider::OnModelList {provider script token} {
	set status [::http::status $token]
	set code [::http::ncode $token]
	set data [body $token]
	::http::cleanup $token

	if {$status ne "ok" || $code != 200} {
		set err [expr {$status ne "ok" ? "[label $provider]: $status" : [CloudError [label $provider] $code $data]}]
		uplevel #0 [list {*}$script [list ok 0 error $err]]
		return
	}
	if {[catch {
		set ids {}
		foreach m [dict get [json::json2dict $data] data] {
			set id [dict get $m id]
			# Gemini lists "models/<name>"; requests take the bare name
			regsub {^models/} $id {} id
			if {[regexp -nocase {embed|rerank|image|tts|audio|realtime|whisper|vision-exp|aqa} $id]} { continue }
			lappend ids $id
		}
		set ids [lsort -unique $ids]
	} err]} {
		uplevel #0 [list {*}$script [list ok 0 error "[label $provider]: unreadable model list ($err)"]]
		return
	}
	uplevel #0 [list {*}$script [list ok 1 models $ids]]
	return
}


# ----------------------------------------------------------------------
# Asynchronous cloud requests. <script> gets {ok 1 message M} (chat) or
# {ok 1 text T} (completion), or {ok 0 error E}.
# ----------------------------------------------------------------------

proc ::ai::provider::cloudChatAsync {messages tools script {mode chat}} {
	variable Config

	set provider $Config(name)
	if {[catch {
		need json
		if {$provider eq "anthropic"} {
			set url [anthropicUrl]
			set body [anthropicBody $messages $tools]
			set headers [anthropicHeaders]
		} else {
			set url [openaiUrl]
			set body [openaiBody $messages $tools]
			set headers [list Authorization "Bearer [NeedKey [Current]]"]
		}
	} err]} {
		after 0 [list [namespace current]::failAsync $script $err]
		return
	}

	requestAsync $url $body \
		[namespace code [list ::ai::provider::OnCloud $provider $mode $script]] \
		[namespace code [list ::ai::provider::cloudUnavailable $script]] \
		$headers
	return
}


# Error bodies may quote credentials. Scrub before logging or displaying them.
proc ::ai::provider::redactError {text} {
	foreach provider {anthropic openai fireworks qwen gemini} {
		set key [apiKey $provider]
		if {$key ne ""} { set text [string map [list $key {[redacted]}] $text] }
	}
	return [string range $text 0 8191]
}

proc ::ai::provider::cloudUnavailable {script error} {
	set error [redactError $error]
	catch { ::application::assistant::RecordError provider $error }
	uplevel #0 [list {*}$script [list ok 0 error $error down 1]]
}


proc ::ai::provider::OnCloud {provider mode script token} {
	set status [::http::status $token]
	set code [::http::ncode $token]
	set data [body $token]
	::http::cleanup $token

	set name [label $provider]
	if {$status ne "ok" || $code != 200} {
		set err [expr {$status ne "ok" ? "$name: $status" : [CloudError $name $code $data]}]
		set err [redactError $err]
		catch { ::application::assistant::RecordError provider $err [redactError $data] }
		# busy (429), a server fault (5xx) or no reply at all: a backup may serve
		set down [expr {$status ne "ok" || $code == 429 || $code >= 500}]
		set summary [expr {$status ne "ok" ? "$name: $status" : "$name: HTTP $code"}]
		uplevel #0 [list {*}$script [list ok 0 error $err down $down summary $summary]]
		return
	}
	if {[catch {
		set msg [expr {$provider eq "anthropic" ? [anthropicReply $data] : [openaiReply $data]}]
	} err]} {
		uplevel #0 [list {*}$script [list ok 0 error "$name: unreadable reply ($err)"]]
		return
	}
	if {$mode eq "text"} {
		uplevel #0 [list {*}$script [list ok 1 text [dict get $msg content]]]
	} else {
		uplevel #0 [list {*}$script [list ok 1 message $msg]]
	}
	return
}


# ----------------------------------------------------------------------
# Chat with tools (Ollama /api/chat).  A "message" is a dict with at least
# role and content; assistant messages may also carry tool_calls.  Returns
# the assistant message dict.
# ----------------------------------------------------------------------

proc ::ai::provider::encodeToolCalls {toolCalls} {
	set out "\["
	set first 1

	foreach call $toolCalls {
		if {!$first} { append out "," }
		set first 0
		set fn [dict get $call function]
		set name [dict get $fn name]
		set args [expr {[dict exists $fn arguments] ? [dict get $fn arguments] : {}}]
		append out "{\"function\":{\"name\":\"[jsonEscape $name]\",\"arguments\":[jsonObject $args]}}"
	}

	append out "\]"
	return $out
}


proc ::ai::provider::encodeMessages {messages} {
	set out "\["
	set first 1

	foreach msg $messages {
		if {!$first} { append out "," }
		set first 0
		append out "{\"role\":\"[jsonEscape [dict get $msg role]]\""
		if {[dict exists $msg content]} {
			append out ",\"content\":\"[jsonEscape [dict get $msg content]]\""
		}
		if {[dict exists $msg tool_calls]} {
			append out ",\"tool_calls\":[encodeToolCalls [dict get $msg tool_calls]]"
		}
		if {[dict exists $msg tool_name]} {
			append out ",\"tool_name\":\"[jsonEscape [dict get $msg tool_name]]\""
		}
		append out "}"
	}

	append out "\]"
	return $out
}


proc ::ai::provider::chatBody {messages tools} {
	variable Config

	set body "{\"model\":\"[jsonEscape [model]]\",\"messages\":[encodeMessages $messages],\"stream\":false"
	if {[set think [Think]] ne ""} {
		append body ",\"think\":$think"
	}
	if {$tools ne ""} {
		append body ",\"tools\":$tools"
	}
	if {[llength $Config(options)]} {
		append body ",\"options\":[jsonObject $Config(options)]"
	}
	append body "}"
	return $body
}


# The chat endpoint for providers that split generate/chat URLs.
proc ::ai::provider::chatUrl {} {
	variable Config
	return [string map {/api/generate /api/chat} $Config(endpoint)]
}


proc ::ai::provider::chat {messages tools args} {
	variable Config
	array set opts [list -chatResponses {}]
	array set opts $args

	# A9/A10: label the outgoing request and the tools it may touch.
	shadow [requestText $messages] $tools

	switch -- $Config(name) {
		stub   { return [stubChat] }
		ollama {
			need json
			set data [post [chatBody $messages $tools] -url [chatUrl]]
			set d [json::json2dict $data]
			if {![dict exists $d message]} { error "ai::provider: no message in chat response" }
			return [dict get $d message]
		}
		anthropic { return [anthropicChat $messages $tools] }
		openai - fireworks - qwen - gemini { return [openaiChat $messages $tools] }
		default { error "ai::provider: chat not supported for provider '$Config(name)'" }
	}
}


proc ::ai::provider::stubChat {} {
	variable Config

	if {[llength $Config(chatResponses)] == 0} {
		return [dict create role assistant content "(stub chat: no -chatResponses configured)"]
	}

	set i $Config(chatIndex)
	if {$i >= [llength $Config(chatResponses)]} {
		set i [expr {[llength $Config(chatResponses)] - 1}]
	} else {
		incr Config(chatIndex)
	}
	return [lindex $Config(chatResponses) $i]
}


proc ::ai::provider::chatAsync {messages tools script} {
	variable Config

	# A9/A10: label the outgoing request and the tools it may touch.
	shadow [requestText $messages] $tools

	switch -- $Config(name) {
		stub { after 0 [list {*}$script [list ok 1 message [stubChat]]] }
		ollama {
			if {[catch {need json} err]} {
				after 0 [list [namespace current]::failAsync $script $err]
				return
			}
			requestAsync [chatUrl] [chatBody $messages $tools] \
				[namespace code [list ::ai::provider::onOllamaChat $script]] \
				[namespace code [list ::ai::provider::failAsync $script]]
		}
		anthropic - openai - fireworks - qwen - gemini { cloudChatAsync $messages $tools $script }
		default {
			after 0 [list {*}$script [list ok 0 error "chat not supported for provider '$Config(name)'"]]
		}
	}
	return
}


# Some models served by Ollama (kimi-k3) put their reasoning into the
# content with role markers when thinking is off; keep the response only.
proc ::ai::provider::StripReasoning {text} {
	set k [string last "<|open|>response<|sep|>" $text]
	if {$k >= 0} { set text [string range $text [expr {$k + 23}] end] }
	return [string trim [regsub -all {<\|(?:open|close|sep)\|>} $text {}]]
}


proc ::ai::provider::onOllamaChat {script token} {
	set status [::http::status $token]
	set code [::http::ncode $token]
	set data [body $token]
	::http::cleanup $token

	if {$status ne "ok" || $code != 200} {
		set down [expr {$status ne "ok" || $code == 429 || $code >= 500}]
		uplevel #0 [list {*}$script [list ok 0 error "HTTP $code $status" down $down]]
		return
	}

	if {[catch {set d [json::json2dict $data] ; set message [dict get $d message]} e]} {
		uplevel #0 [list {*}$script [list ok 0 error $e]]
		return
	}
	if {[dict exists $message content]} {
		dict set message content [StripReasoning [dict get $message content]]
	}

	uplevel #0 [list {*}$script [list ok 1 message $message]]
	return
}


# ----------------------------------------------------------------------
# The models an Ollama server offers (/api/tags): a list of dicts
# {name remote tools size}. <remote> is 1 for cloud models (the server
# forwards them), <tools> 1 when the model supports tool calling.
# ----------------------------------------------------------------------

proc ::ai::provider::ollamaModels {{base http://localhost:11434} {timeoutMs 3000}} {
	need http

	set token [::http::geturl $base/api/tags -timeout $timeoutMs -binary 1]
	set status [::http::status $token]
	set code [::http::ncode $token]
	set data [body $token]
	::http::cleanup $token

	if {$status ne "ok" || $code != 200} {
		error "ai::provider: HTTP $code $status from $base/api/tags"
	}
	return [parseModels $data]
}


# Callback receives {ok 1 models LIST} or {ok 0 error MESSAGE}.
# The chooser must not keep its menu callback waiting for the HTTP reply.
proc ::ai::provider::ollamaModelsAsync {script {base http://localhost:11434} {timeoutMs 3000}} {
	if {[catch {
		need http
		::http::geturl $base/api/tags -timeout $timeoutMs -binary 1 \
			-command [namespace code [list OnModels $script]]
	} error]} {
		after 0 [list {*}$script [dict create ok 0 error $error]]
	}
	return
}


proc ::ai::provider::OnModels {script token} {
	set code [catch {
		set status [::http::status $token]
		set httpCode [::http::ncode $token]
		if {$status ne "ok" || $httpCode != 200} { error "HTTP $httpCode $status" }
		parseModels [body $token]
	} result]
	::http::cleanup $token
	if {$code} {
		{*}$script [dict create ok 0 error $result]
	} else {
		{*}$script [dict create ok 1 models $result]
	}
}


proc ::ai::provider::parseModels {data} {
	need json
	set models {}
	foreach m [dict get [json::json2dict $data] models] {
		set caps [expr {[dict exists $m capabilities] ? [dict get $m capabilities] : {}}]
		lappend models [dict create \
			name   [dict get $m name] \
			remote [expr {[dict exists $m remote_host] && [string length [dict get $m remote_host]]}] \
			tools  [expr {"tools" in $caps}] \
			size   [expr {[dict exists $m size] ? [dict get $m size] : 0}] \
			details [expr {[dict exists $m details] ? [dict get $m details] : {}}] \
		]
	}
	return [lsort -index 1 -dictionary $models]
}

# Persisted accounts to load even when no legacy key file remains.
proc ::ai::provider::credentialAccounts {} {
	variable KeyEnv
	return [array names KeyEnv]
}
