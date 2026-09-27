# ======================================================================
# ::ai::systemone -- client for "System One" decision models.
#
# A System One model does not write text: it reads a state and answers typed
# questions with probabilities -- choice (one of named options), noul (yes or
# no), score (ordered levels). TypeSafe's Jev defines the wire contract
# (POST /v1/systemone); the open-weights servers below serve the same contract
# on this machine, so one client talks to all of them:
#
#   kev         http://127.0.0.1:8009/v1/systemone, no key   (local, the default)
#   simple-jev  http://127.0.0.1:8000/v1/systemone, no key   (local)
#   plumb       http://127.0.0.1:8090/v1/systemone, no key   (local; see below)
#   jev/vercel  Jev through Vercel's AI Gateway, AI_GATEWAY_API_KEY (cloud)
#
#   ::ai::systemone::configure -backend kev
#   ::ai::systemone::evaluate <state> <questions>          -> answers dict
#   ::ai::systemone::evaluateAsync <state> <questions> <script>
#
# <questions> is a dict  id -> {type choice|noul|score instructions TEXT
# criteria C}, where C is a dict name -> description for choice (and noul's
# optional {false ... true ...}), a list of levels for score. An answer is a
# dict: {type choice choice NAME confidence C probabilities {NAME P ...}},
# {type noul noul P}, or {type score score S confidence C probabilities ...}.
#
# The backend is chosen in Extras > AI: Choose Model (saved in the options
# file as ::application::ai::Settings(classifier)); for one session it is
# overridden by, in this order, the --ai-classifier option and the
# SCIDB_AI_CLASSIFIER environment variable. SCIDB_AI_CLASSIFIER_URL and
# SCIDB_AI_CLASSIFIER_MODEL override endpoint and model; AI_GATEWAY_API_KEY
# (jev/vercel), KEV_API_KEY and SIMPLE_JEV_API_KEY (a local server that
# requires one) are read from the environment only, never stored.
#
# Scidb does not start the local servers; run them beside the app:
#   kev:        github.com/jaredpalmer/kev
#               uv sync --extra serve
#               KEV_DTYPE=fp16 uv run --extra serve python -m kev.serve \
#                   --run jaredpalmer/kev-0.8b --port 8009
#               (fp16 on GPUs without bf16, e.g. Turing and Pascal;
#               kev-4b/-9b need ~8/18 GB.)
#   simple-jev: github.com/featherless-ai/simple-jev
#               hf_server.py --model Qwen/Qwen3.5-0.8B --port 8000
#   plumb:      scripts/serve-plumb-classifier.sh downloads the model from
#               Hugging Face (crh225/plumb-4b-GGUF, Q8_0 ~4.5 GB; Apache-2.0;
#               JevBench v1.4.2.1 rank 1 of the open systems) and serves it
#               with llama.cpp and a /v1/systemone shim on port 8090.
#               Plumb-4B is the strongest open decision model that fits an
#               8 GB card in one pass.
# While no server answers, callers fall back: triage hands everything to the
# language model.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-systemone
}

package require Tcl 8.5

namespace eval ai {
namespace eval systemone {

variable Backends {
	kev {endpoint http://127.0.0.1:8009/v1/systemone model kev-latest key KEV_API_KEY}
	simple-jev {endpoint http://127.0.0.1:8000/v1/systemone model Qwen/Qwen3.5-0.8B key SIMPLE_JEV_API_KEY}
	plumb {endpoint http://127.0.0.1:8090/v1/systemone model plumb-4b-v5}
	jev {endpoint https://ai-gateway.vercel.sh/typesafe/v1/systemone model typesafe-ai/jev key AI_GATEWAY_API_KEY}
	vercel {endpoint https://ai-gateway.vercel.sh/typesafe/v1/systemone model typesafe-ai/jev key AI_GATEWAY_API_KEY}
}

variable Config
array set Config {
	backend   ""
	endpoint  ""
	model     ""
	apiKey    ""
	timeoutMs 30000
}

} ;# namespace systemone
} ;# namespace ai


proc ::ai::systemone::configure {args} {
	variable Config
	variable Backends

	foreach {key value} $args {
		switch -- $key {
			-backend {
				if {$value ni [concat [dict keys $Backends] {off {}}]} {
					error "unknown System One backend '$value' ([join [dict keys $Backends] {, }] or off)"
				}
				set Config(backend) [expr {$value eq "off" ? "" : $value}]
				if {[string length $Config(backend)]} {
					set b [dict get $Backends $Config(backend)]
					set Config(endpoint) [dict get $b endpoint]
					set Config(model) [dict get $b model]
					if {[dict exists $b key] && [string length [dict get $b key]]} {
						set var [dict get $b key]
						set Config(apiKey) [expr {[info exists ::env($var)] ? $::env($var) : ""}]
					} else {
						set Config(apiKey) ""
					}
				}
			}
			-endpoint { set Config(endpoint) $value }
			-model    { set Config(model) $value }
			-apiKey   { set Config(apiKey) $value }
			-timeout  { set Config(timeoutMs) $value }
			default   { error "unknown option $key" }
		}
	}
	return
}


proc ::ai::systemone::enabled {} {
	variable Config
	return [expr {[string length $Config(backend)] > 0}]
}


proc ::ai::systemone::describe {} {
	variable Config
	if {![enabled]} { return "off" }
	return "$Config(backend) ($Config(model) at $Config(endpoint))"
}


# The request body.
proc ::ai::systemone::body {state questions} {
	variable Config

	set qs {}
	dict for {id q} $questions {
		set type [dict get $q type]
		if {$type ni {choice noul score}} { error "question '$id': unknown type '$type'" }
		set fields [list "\"type\":\"$type\""]
		if {[dict exists $q instructions]} {
			lappend fields "\"instructions\":[String [dict get $q instructions]]"
		}
		if {[dict exists $q criteria]} {
			set criteria [dict get $q criteria]
			if {$type eq "score"} {
				set items [lmap level $criteria { String $level }]
				lappend fields "\"criteria\":\[[join $items ,]\]"
			} else {
				set items {}
				dict for {name text} $criteria { lappend items "[String $name]:[String $text]" }
				lappend fields "\"criteria\":{[join $items ,]}"
			}
		} elseif {$type ne "noul"} {
			error "question '$id': a $type question needs criteria"
		}
		lappend qs "[String $id]:{[join $fields ,]}"
	}
	if {![llength $qs]} { error "at least one question is needed" }
	return "{\"model\":[String $Config(model)],\"state\":[String $state],\"questions\":{[join $qs ,]}}"
}


proc ::ai::systemone::String {s} {
	return "\"[::ai::provider::jsonEscape $s]\""
}


proc ::ai::systemone::Headers {} {
	variable Config
	if {![string length $Config(apiKey)]} { return {} }
	return [list Authorization "Bearer $Config(apiKey)"]
}


# The answers of a response body, or an error.
proc ::ai::systemone::Answers {code status data} {
	variable Config

	if {$status ne "ok"} { error "System One $status at $Config(endpoint)" }
	if {$code != 200} {
		set detail [string range [string trim $data] 0 300]
		error "System One HTTP $code from $Config(endpoint): $detail"
	}
	::ai::provider::need json
	set reply [json::json2dict $data]
	if {![dict exists $reply answers]} { error "System One reply without answers" }
	return [dict get $reply answers]
}


proc ::ai::systemone::evaluate {state questions} {
	variable Config

	if {![enabled]} { error "no System One backend is configured" }
	set token [Request $state $questions]
	set status [::http::status $token]
	set code [::http::ncode $token]
	set data [::ai::provider::body $token]
	::http::cleanup $token
	return [Answers $code $status $data]
}


# <script> is called with {ok 1 answers A} or {ok 0 error TEXT}.
proc ::ai::systemone::evaluateAsync {state questions script} {
	if {![enabled]} {
		after 0 [list {*}$script [list ok 0 error "no System One backend is configured"]]
		return
	}
	if {[catch { Request $state $questions -command [namespace code [list OnReply $script]] } err]} {
		after 0 [list {*}$script [list ok 0 error $err]]
	}
	return
}


proc ::ai::systemone::OnReply {script token} {
	set status [::http::status $token]
	set code [::http::ncode $token]
	set data [::ai::provider::body $token]
	::http::cleanup $token
	if {[catch { Answers $code $status $data } answers]} {
		set result [list ok 0 error $answers]
	} else {
		set result [list ok 1 answers $answers]
	}
	uplevel #0 [list {*}$script $result]
}


proc ::ai::systemone::Request {state questions args} {
	variable Config

	set body [body $state $questions]
	# the provider's request honours its own timeout; ours applies here
	set saved $::ai::provider::Config(timeoutMs)
	set ::ai::provider::Config(timeoutMs) $Config(timeoutMs)
	set rc [catch { ::ai::provider::request $Config(endpoint) $body -headers [Headers] {*}$args } token]
	set ::ai::provider::Config(timeoutMs) $saved
	if {$rc} { error $token }
	return $token
}


# ----------------------------------------------------------------------
# Backend metadata for the chooser dialog: a list of dicts
# {name endpoint model local key}, <local> 1 when the server runs on this
# machine. Aliases are listed too (jev and vercel share an endpoint); the
# dialog decides which rows to show.
# ----------------------------------------------------------------------

proc ::ai::systemone::backends {} {
	variable Backends
	set result {}
	dict for {name b} $Backends {
		set endpoint [dict get $b endpoint]
		lappend result [dict create \
			name     $name \
			endpoint $endpoint \
			model    [dict get $b model] \
			local    [expr {[regexp {^https?://(127\.0\.0\.1|localhost|\[::1\])} $endpoint] ? 1 : 0}] \
			key      [expr {[dict exists $b key] ? [dict get $b key] : ""}] \
		]
	}
	return $result
}


apply {{} {
	set backend kev
	if {[info exists ::env(SCIDB_AI_CLASSIFIER)]} { set backend $::env(SCIDB_AI_CLASSIFIER) }
	if {[catch { ::ai::systemone::configure -backend $backend }]} {
		::ai::systemone::configure -backend kev
	}
	if {[info exists ::env(SCIDB_AI_CLASSIFIER_URL)]} {
		::ai::systemone::configure -endpoint $::env(SCIDB_AI_CLASSIFIER_URL)
	}
	if {[info exists ::env(SCIDB_AI_CLASSIFIER_MODEL)]} {
		::ai::systemone::configure -model $::env(SCIDB_AI_CLASSIFIER_MODEL)
	}
}}

# vi:set ts=3 sw=3:
