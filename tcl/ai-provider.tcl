# ======================================================================
# ::ai::provider -- provider-agnostic text completion for the language layer.
#
# Local-first: the default is a `stub` (deterministic, for tests), and `ollama`
# drives a locally running model.  Remote adapters (`openai`, `anthropic`) exist
# but are opt-in; nothing here sends a database anywhere without being asked.
#
#   ::ai::provider::configure -name ollama -model granite4.2:3b
#   ::ai::provider::complete <prompt> ?-system <text>?
#
# `json`/`http` are required lazily so a missing tcllib package cannot break
# application startup.
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
	model     "deepseek-v4.1-flash:cloud"
	endpoint  ""
	timeoutMs 120000
	responses {}
	index     0
	system    ""
	options   {}
	think     false
	chatResponses {}
	chatIndex 0
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
			default    { error "unknown option $key" }
		}
	}

	if {$Config(endpoint) eq ""} {
		switch -- $Config(name) {
			ollama    { set Config(endpoint) "http://localhost:11434/api/generate" }
			openai    { set Config(endpoint) "https://api.openai.com/v1/chat/completions" }
			anthropic { set Config(endpoint) "https://api.anthropic.com/v1/messages" }
		}
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


# Issue a JSON POST.  The http package writes -query as raw bytes (and sizes
# Content-Length by character count), so the body must be UTF-8 encoded here
# or any non-ASCII text corrupts the request.  https needs the tls package.
proc ::ai::provider::request {url body args} {
	variable Config
	variable TlsRegistered

	need http
	if {[string match -nocase https://* $url] && ![info exists TlsRegistered]} {
		need tls
		::http::register https 443 ::tls::socket
		set TlsRegistered 1
	}

	return [::http::geturl $url \
		-type "application/json; charset=utf-8" \
		-query [encoding convertto utf-8 $body] \
		-timeout $Config(timeoutMs) \
		{*}$args]
}


# Asynchronous request; <done> gets the token.  Synchronous failures (no
# http/tls package, unresolvable host) are reported through <failed>, called
# with the error message, so the caller's callback always runs.
proc ::ai::provider::requestAsync {url body done failed} {
	if {[catch {request $url $body -command $done} err]} {
		after 0 [list {*}$failed $err]
	}
	return
}


proc ::ai::provider::failAsync {script err} {
	uplevel #0 [list {*}$script [list ok 0 error $err]]
}


proc ::ai::provider::post {body args} {
	variable Config
	array set opts [list -headers {} -url ""]
	array set opts $args

	set url [expr {$opts(-url) ne "" ? $opts(-url) : $Config(endpoint)}]
	set token [request $url $body -headers $opts(-headers)]

	set status [::http::status $token]
	set code [::http::ncode $token]
	set data [::http::data $token]
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

	switch -- $Config(name) {
		stub      { return [stub $prompt] }
		ollama    { return [ollama $prompt $opts(-system)] }
		openai    { return [openai $prompt $opts(-system)] }
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

	switch -- $Config(name) {
		stub   { after 0 [list {*}$script [list ok 1 text [stub $prompt]]] }
		ollama { ollamaAsync $prompt $opts(-system) $script }
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
	set data [::http::data $token]
	::http::cleanup $token

	if {$status ne "ok" || $code != 200} {
		uplevel #0 [list {*}$script [list ok 0 error "HTTP $code $status"]]
		return
	}

	if {[catch {set d [json::json2dict $data] ; set text [dict get $d response]} e]} {
		uplevel #0 [list {*}$script [list ok 0 error $e]]
		return
	}

	uplevel #0 [list {*}$script [list ok 1 text $text]]
	return
}


proc ::ai::provider::ollamaBody {prompt system} {
	variable Config

	set body "{\"model\":\"[jsonEscape $Config(model)]\",\"prompt\":\"[jsonEscape $prompt]\",\"stream\":false"
	if {[string length $Config(think)]} {
		append body ",\"think\":$Config(think)"
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


proc ::ai::provider::openai {prompt system} {
	variable Config
	need json

	set apiKey [expr {[info exists ::env(OPENAI_API_KEY)] ? $::env(OPENAI_API_KEY) : ""}]
	if {$apiKey eq ""} { error "ai::provider: set OPENAI_API_KEY for the openai provider" }

	set msgs "\["
	if {$system ne ""} {
		append msgs "{\"role\":\"system\",\"content\":\"[jsonEscape $system]\"},"
	}
	append msgs "{\"role\":\"user\",\"content\":\"[jsonEscape $prompt]\"}\]"

	set body "{\"model\":\"[jsonEscape $Config(model)]\",\"messages\":$msgs}"
	set data [post $body -headers [list Authorization "Bearer $apiKey"]]
	set d [json::json2dict $data]
	return [dict get [lindex [dict get $d choices] 0] message content]
}


proc ::ai::provider::anthropic {prompt system} {
	variable Config
	need json

	set apiKey [expr {[info exists ::env(ANTHROPIC_API_KEY)] ? $::env(ANTHROPIC_API_KEY) : ""}]
	if {$apiKey eq ""} { error "ai::provider: set ANTHROPIC_API_KEY for the anthropic provider" }

	set body "{\"model\":\"[jsonEscape $Config(model)]\",\"max_tokens\":1024,\"messages\":\[{\"role\":\"user\",\"content\":\"[jsonEscape $prompt]\"}\]"
	if {$system ne ""} {
		append body ",\"system\":\"[jsonEscape $system]\""
	}
	append body "}"

	set headers [list x-api-key $apiKey anthropic-version "2023-06-01"]
	set data [post $body -headers $headers]
	set d [json::json2dict $data]
	return [dict get [lindex [dict get $d content] 0] text]
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

	set body "{\"model\":\"[jsonEscape $Config(model)]\",\"messages\":[encodeMessages $messages],\"stream\":false"
	if {[string length $Config(think)]} {
		append body ",\"think\":$Config(think)"
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

	switch -- $Config(name) {
		stub   { return [stubChat] }
		ollama {
			need json
			set data [post [chatBody $messages $tools] -url [chatUrl]]
			set d [json::json2dict $data]
			if {![dict exists $d message]} { error "ai::provider: no message in chat response" }
			return [dict get $d message]
		}
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
		default {
			after 0 [list {*}$script [list ok 0 error "chat not supported for provider '$Config(name)'"]]
		}
	}
	return
}


proc ::ai::provider::onOllamaChat {script token} {
	set status [::http::status $token]
	set code [::http::ncode $token]
	set data [::http::data $token]
	::http::cleanup $token

	if {$status ne "ok" || $code != 200} {
		uplevel #0 [list {*}$script [list ok 0 error "HTTP $code $status"]]
		return
	}

	if {[catch {set d [json::json2dict $data] ; set message [dict get $d message]} e]} {
		uplevel #0 [list {*}$script [list ok 0 error $e]]
		return
	}

	uplevel #0 [list {*}$script [list ok 1 message $message]]
	return
}
