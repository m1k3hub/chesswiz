# ======================================================================
# ::ai::systemone -- client for "System One" decision models.
#
# A System One model does not write text: it reads a state and answers typed
# questions with probabilities -- choice (one of named options), noul (yes or
# no), score (ordered levels). TypeSafe's Jev defines the wire contract
# (POST /v1/systemone); the open-weights servers below serve the same contract
# on this machine, so one client talks to all of them:
#
#   kev         http://127.0.0.1:8009/v1/systemone, no key   (local, preferred)
#   simple-jev  http://127.0.0.1:8000/v1/systemone, no key   (local)
#   plumb       http://127.0.0.1:8090/v1/systemone, no key   (local; see below)
#   jev/vercel  Jev through Vercel's AI Gateway, AI_GATEWAY_API_KEY (cloud)
#
# When nothing is chosen -- no --ai-classifier, no SCIDB_AI_CLASSIFIER, no
# saved setting -- the default is "auto": ::ai::systemone::autostart probes
# the local backends in ProbeOrder (kev, simple-jev, plumb) and uses the
# first that answers a trivial typed question, so ::ai::systemone::enabled is
# the truth about what is reachable, not merely what is configured. Nothing
# answering leaves the classifier off. A cloud backend is never probed: it
# needs a deliberate choice and a key.
#
#   ::ai::systemone::configure -backend auto|kev|...|off   (auto discovers)
#   ::ai::systemone::evaluate <state> <questions>          -> answers dict
#   ::ai::systemone::evaluateAsync <state> <questions> <script>
#
# No endpoint, model, key or port is fixed in code: every preset field can
# be overridden by the environment, by the preset's upper-cased name:
#   SCIDB_AI_KEV_URL / _MODEL / _KEY
#   SCIDB_AI_SIMPLE_JEV_URL / _MODEL / _KEY
#   SCIDB_AI_PLUMB_URL / _MODEL / _KEY
#   SCIDB_AI_TYPESAFE_URL / _MODEL / _KEY  (TypeSafe's own API, jev-latest)
#   SCIDB_AI_VERCEL_URL / _MODEL / _KEY   (and the same for jev)
#   SCIDB_AI_PROBE_ORDER=kev,plumb,...    (auto discovery order)
# The generic SCIDB_AI_CLASSIFIER, SCIDB_AI_CLASSIFIER_URL and
# SCIDB_AI_CLASSIFIER_MODEL still override the resolved backend itself.
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
	typesafe {endpoint https://api.typesafe.ai/v1/systemone model jev-latest key TYPESAFE_API_KEY}
}

variable Config
array set Config {
	backend   ""
	endpoint  ""
	model     ""
	apiKey    ""
	timeoutMs 30000
}

# Auto mode: no explicit choice, so autostart discovers a local server. An
# explicit configure -backend NAME (or off) sets Auto 0 for the session.
variable Auto 1
variable Resolved 0
variable ProbeOrder {kev simple-jev plumb}

} ;# namespace systemone
} ;# namespace ai


# Apply the environment overrides to the presets (see the header). This
# keeps the preset table as *defaults*, never as the only option: a server
# on a different port, or a different model of the same protocol, is
# reachable without editing code.
proc ::ai::systemone::ApplyEnv {} {
	variable Backends
	variable ProbeOrder

	foreach name [dict keys $Backends] {
		set tag [string toupper [string map {- _} $name]]
		foreach {field suffix} {endpoint _URL model _MODEL key _KEY} {
			set var SCIDB_AI_${tag}${suffix}
			if {[info exists ::env($var)] && $::env($var) ne ""} {
				dict set Backends $name $field $::env($var)
			}
		}
	}

	if {[info exists ::env(SCIDB_AI_PROBE_ORDER)] && $::env(SCIDB_AI_PROBE_ORDER) ne ""} {
		set ProbeOrder [split $::env(SCIDB_AI_PROBE_ORDER) ,]
	}
	return
}

::ai::systemone::ApplyEnv


# Apply a known backend's endpoint, model and key. Shared by an explicit
# `configure -backend NAME` and by discovery.
proc ::ai::systemone::SetBackend {name} {
	variable Config
	variable Backends

	set b [dict get $Backends $name]
	set Config(backend) $name
	set Config(endpoint) [dict get $b endpoint]
	set Config(model) [dict get $b model]
	if {[dict exists $b key] && [string length [dict get $b key]]} {
		set var [dict get $b key]
		set Config(apiKey) [expr {[info exists ::env($var)] ? $::env($var) : ""}]
	} else {
		set Config(apiKey) ""
	}
	return
}


proc ::ai::systemone::configure {args} {
	variable Config
	variable Backends
	variable Auto
	variable Resolved
	variable Loaded
	variable ThresholdFile

	foreach {key value} $args {
		switch -- $key {
			-backend {
				if {$value eq "auto"} {
					# auto: the app will discover a local server
					set Auto 1
					set Resolved 0
					set Config(backend) ""
					set Config(endpoint) ""
					set Config(model) ""
					set Config(apiKey) ""
					continue
				}
				if {$value ni [concat [dict keys $Backends] {off {}}]} {
					error "unknown System One backend '$value' ([join [dict keys $Backends] {, }], auto or off)"
				}
				# an explicit choice turns discovery off for the session
				set Auto 0
				set Resolved 1
				if {$value eq "off" || ![string length $value]} {
					set Config(backend) ""
				} else {
					SetBackend $value
				}
			}
			-endpoint { set Config(endpoint) $value }
			-model    { set Config(model) $value }
			-apiKey   { set Config(apiKey) $value }
			-timeout  { set Config(timeoutMs) $value }
			default   { error "unknown option $key" }
		}
	}
	LoadOnce
	return
}


proc ::ai::systemone::enabled {} {
	variable Config
	return [expr {[string length $Config(backend)] > 0}]
}


proc ::ai::systemone::describe {} {
	variable Config
	variable Auto
	if {![enabled]} {
		return [expr {$Auto ? "auto (no local server found)" : "off"}]
	}
	return "$Config(backend) ($Config(model) at $Config(endpoint))"
}


# Is <name> really a System One server? A plain connect is not enough --
# port 8000 in particular is a common developer port -- so after a quick
# connect this asks one trivial typed question and requires a well-formed
# answer. The connect makes an absent server fail at once, so the longer
# request timeout only applies to something that is actually listening
# (which may still be loading its model).
proc ::ai::systemone::Reachable {name} {
	variable Config
	variable Backends

	set endpoint [dict get $Backends $name endpoint]
	if {![regexp {^https?://([^/:]+):([0-9]+)} $endpoint -> host port]} { return 0 }
	if {[catch { set chan [socket $host $port] }]} { return 0 }
	catch { close $chan }

	set saved [array get Config]
	set ok 0
	if {![catch {
		SetBackend $name
		set Config(timeoutMs) 5000
		evaluate "probe" [dict create probe [dict create type noul \
			instructions "Is this a reachable System One server?"]]
	}]} {
		set ok 1
	}
	array set Config $saved
	return $ok
}


# Find a local server: the first backend in ProbeOrder that answers. None
# answering leaves the classifier off, so nothing is classified.
proc ::ai::systemone::discover {} {
	variable Config
	variable ProbeOrder
	variable Resolved

	set Resolved 1
	foreach name $ProbeOrder {
		if {[Reachable $name]} {
			SetBackend $name
			return $name
		}
	}
	set Config(backend) ""
	set Config(endpoint) ""
	set Config(model) ""
	set Config(apiKey) ""
	return ""
}


# Called by the app once the settings are in effect: in auto mode, look for
# a local server. An explicit option, environment variable or saved choice
# has already turned Auto off, so this is a no-op for those.
proc ::ai::systemone::autostart {} {
	variable Auto
	variable Resolved

	if {!$Auto || $Resolved} { return }
	discover
	return
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


# A synchronous, bounded selection from a fixed candidate set, for callers
# that cannot be made asynchronous (resolving a name while building a query).
# <question> must be a choice question; returns the chosen label, or "" on
# any abstention: no classifier, an error, a timeout, a label outside the
# criteria, or confidence below the (per-backend calibrated) threshold. The
# caller falls back to its own behaviour on "".
proc ::ai::systemone::chooseSync {feature state question args} {
	variable Config
	array set opts {-timeout 3000 -threshold 0.6}
	array set opts $args

	if {![enabled] || ![qualified $feature]} { return "" }
	if {[dict get $question type] ne "choice"} { error "chooseSync needs a choice question" }

	set saved $Config(timeoutMs)
	set Config(timeoutMs) $opts(-timeout)
	set rc [catch { evaluate $state [dict create q $question] } answers]
	set Config(timeoutMs) $saved
	if {$rc || ![dict exists $answers q]} { return "" }

	set answer [dict get $answers q]
	if {![valid $question $answer]} { return "" }
	if {[dict get $answer confidence] < [threshold $feature $opts(-threshold)]} { return "" }
	return [dict get $answer choice]
}


# The same bounded synchronous contract for several choice questions in one
# request. Returns a dict id -> label for the answers that are valid and at or
# above the (per-backend calibrated) threshold; an id is absent on any
# abstention. Used to fill several closed-set tool arguments at once.
proc ::ai::systemone::chooseManySync {feature state questions args} {
	variable Config
	array set opts {-timeout 3000 -threshold 0.6}
	array set opts $args

	if {![enabled]} { return {} }
	if {![dict size $questions]} { return {} }

	set saved $Config(timeoutMs)
	set Config(timeoutMs) $opts(-timeout)
	set rc [catch { evaluate $state $questions } answers]
	set Config(timeoutMs) $saved
	if {$rc} { return {} }

	set out {}
	dict for {id question} $questions {
		if {![dict exists $question type] || [dict get $question type] ne "choice"} { continue }
		if {![dict exists $answers $id]} { continue }
		set answer [dict get $answers $id]
		if {![valid $question $answer]} { continue }
		if {[dict get $answer confidence] < [threshold $feature $opts(-threshold)]} { continue }
		dict set out $id [dict get $answer choice]
	}
	return $out
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
# One gated decision: the shared reliability contract in one place.
#
#   ::ai::systemone::valid <question> <answer>
#       1 when <answer> has the shape <question> asked for: a choice from
#       the offered criteria with a confidence in [0,1], or a noul in
#       [0,1]. Anything else is abstention, never a guess.
#
#   ::ai::systemone::threshold <feature> <default>
#       SCIDB_AI_<FEATURE>_MIN_CONFIDENCE, else the (feature, backend)
#       entry in Thresholds, else <default>. Thresholds are per model
#       (research note §6.2), so a backend without calibrated numbers
#       falls back to the caller's default.
#
#   ::ai::decide <feature> <state> <question> <script> ?-fallback CMD? ?-threshold T?
#       Asks one question. <script> gets
#           {ok 1 label L confidence C source classifier}
#       when the classifier answered validly and confidently enough, else
#           {ok 1 label L confidence {} source rules}
#       with L from evaluating the command prefix CMD, else {ok 0}.
#       For a noul question L is 1 or 0 (p >= threshold) and C is p.
#       No classifier, a timeout, an error, a malformed reply or an
#       unknown label all end in the fallback.
# ----------------------------------------------------------------------

namespace eval ::ai::systemone {
	# feature -> backend -> threshold; filled by ::ai::systemone::loadThresholds
	# from a calibration file, and empty until then (the callers' defaults hold).
	variable Thresholds {}
	variable Loaded 0

	# SCIDB_AI_THRESHOLDS overrides; otherwise a file beside this module.
	variable ThresholdFile [expr {
		[info exists ::env(SCIDB_AI_THRESHOLDS)] ? $::env(SCIDB_AI_THRESHOLDS) :
		[file join [file dirname [file normalize [info script]]] ai-thresholds.tsv]}]

}


proc ::ai::systemone::valid {question answer} {
	if {[catch {
		switch -- [dict get $question type] {
			choice {
				set ok [expr {[dict get $answer choice] in [dict keys [dict get $question criteria]]}]
				set p [dict get $answer confidence]
			}
			noul {
				set ok 1
				set p [dict get $answer noul]
			}
			score {
				set value [dict get $answer score]
				set ok [expr {[string is double -strict $value] && $value >= 0.0 && $value <= 1.0}]
				set p [dict get $answer confidence]
			}
			default { set ok 0 }
		}
	}]} {
		return 0
	}
	if {!$ok || ![string is double -strict $p]} { return 0 }
	return [expr {$p >= 0.0 && $p <= 1.0}]
}


# Read the thresholds file once. The installed program is one script in
# bin/, so the file is looked for in the share directory as well.
proc ::ai::systemone::LoadOnce {} {
	variable Loaded
	variable ThresholdFile

	if {$Loaded} { return }
	set Loaded 1
	if {![info exists ::env(SCIDB_AI_THRESHOLDS)] && ![file exists $ThresholdFile]
	 && [info exists ::scidb::dir::share]} {
		set ThresholdFile [file join $::scidb::dir::share ai-thresholds.tsv]
	}
	catch { loadThresholds $ThresholdFile }
}


# Whether the classifier in use may decide <feature>: only a task it passed
# calibration for (an entry in the thresholds file), or one the user opened
# with SCIDB_AI_<FEATURE>_MIN_CONFIDENCE. Every other task goes to the
# rules or the language model; SCIDB_AI_UNCALIBRATED=1 lifts the rule.
proc ::ai::systemone::qualified {feature} {
	variable Thresholds
	variable Config

	LoadOnce
	if {[info exists ::env(SCIDB_AI_UNCALIBRATED)] && $::env(SCIDB_AI_UNCALIBRATED)} { return 1 }
	set var SCIDB_AI_[string toupper $feature]_MIN_CONFIDENCE
	if {[info exists ::env($var)] && [string is double -strict $::env($var)]} { return 1 }
	return [dict exists $Thresholds $feature $Config(backend)]
}


proc ::ai::systemone::threshold {feature default} {
	variable Thresholds
	variable Config

	set var SCIDB_AI_[string toupper $feature]_MIN_CONFIDENCE
	if {[info exists ::env($var)] && [string is double -strict $::env($var)]} {
		return $::env($var)
	}
	if {[dict exists $Thresholds $feature $Config(backend)]} {
		return [dict get $Thresholds $feature $Config(backend)]
	}
	return $default
}


# Load per-(feature, backend) thresholds from a TSV written by
# ::ai::calibrate::write: one "feature<TAB>backend<TAB>threshold" per line,
# '#' comments allowed. Merges into Thresholds and returns the count read.
# A missing file is silent (the callers' defaults then hold).
proc ::ai::systemone::loadThresholds {file} {
	variable Thresholds

	if {$file eq "" || ![file exists $file]} { return 0 }
	if {[catch { open $file r } chan]} { return 0 }

	set count 0
	set text [read $chan]
	close $chan
	foreach line [split $text "\n"] {
		set line [string trim $line]
		if {$line eq "" || [string index $line 0] eq "#"} { continue }
		lassign [split $line "\t"] feature backend value
		if {$feature eq "" || $backend eq "" || ![string is double -strict $value]} { continue }
		dict set Thresholds $feature $backend $value
		incr count
	}
	return $count
}


proc ::ai::decide {feature state question script args} {
	array set opts {-fallback {} -threshold 0.6}
	array set opts $args

	# Record the decision (if journaling is on) without touching it: the
	# journal sink forwards to the caller's script unchanged.
	set sink $script
	if {[llength [info commands ::ai::journal::logged]]} {
		set sink [list ::ai::journal::logged $feature $state $script]
	}

	if {[llength [info commands ::ai::systemone::enabled]] == 0
	 || ![::ai::systemone::enabled] || ![::ai::systemone::qualified $feature]} {
		::ai::systemone::Decided $feature $question $sink [array get opts] [list ok 0]
		return
	}
	set questions [dict create $feature $question]
	if {[catch {
		::ai::systemone::evaluateAsync $state $questions \
			[list ::ai::systemone::Decided $feature $question $sink [array get opts]]
	}]} {
		::ai::systemone::Decided $feature $question $sink [array get opts] [list ok 0]
	}
	return
}


proc ::ai::systemone::Decided {feature question script opts result} {
	set threshold [threshold $feature [dict get $opts -threshold]]
	set decision {}
	if {[dict get $result ok]
	 && ![catch { dict get $result answers $feature } answer]
	 && [valid $question $answer]} {
		if {[dict get $question type] eq "noul"} {
			set p [dict get $answer noul]
			set decision [list ok 1 label [expr {$p >= $threshold}] confidence $p source classifier]
		} elseif {[dict get $question type] eq "score"} {
			if {[dict get $answer confidence] >= $threshold} {
				set levels [dict get $question criteria]
				set n [llength $levels]
				set s [dict get $answer score]
				set i [expr {$n > 1 ? int(round($s * ($n - 1))) : 0}]
				if {$i < 0} { set i 0 }
				if {$i >= $n} { set i [expr {$n - 1}] }
				set decision [list ok 1 label [lindex $levels $i] confidence $s source classifier]
			}
		} elseif {[dict get $answer confidence] >= $threshold} {
			set decision [list ok 1 label [dict get $answer choice] \
				confidence [dict get $answer confidence] source classifier]
		}
	}
	if {![llength $decision]} {
		set fallback [dict get $opts -fallback]
		if {[llength $fallback] && ![catch { uplevel #0 $fallback } label]} {
			set decision [list ok 1 label $label confidence {} source rules]
		} else {
			set decision [list ok 0]
		}
	}
	after 0 [list {*}$script $decision]
	return
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
	set backend auto
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
