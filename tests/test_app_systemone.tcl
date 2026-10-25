# ======================================================================
# Scidb App Test — System One client (tcl/ai-systemone.tcl) and its use in
# error triage (tcl/app-error-triage.tcl)
# ======================================================================
# A mock /v1/systemone server in this process records each request and
# answers from a script; the language model is the stub provider.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5
package require json

namespace eval ::scidb::test::s1 {
	variable Server {}
	variable Port 0
	variable Replies {}
	variable Requests {}
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app systemone_[pid]]
}

# Replies: a list of {code body}, one per request, the last one repeating.
proc ::scidb::test::s1::start {replies} {
	variable Server
	variable Port
	variable Replies $replies
	variable Requests {}
	set Server [socket -server ::scidb::test::s1::Accept -myaddr 127.0.0.1 0]
	set Port [lindex [fconfigure $Server -sockname] 2]
	::ai::systemone::configure -backend kev -endpoint http://127.0.0.1:$Port/v1/systemone -apiKey ""
}

proc ::scidb::test::s1::stop {} {
	variable Server
	catch { close $Server }
	::ai::systemone::configure -backend off
}

# Non-blocking: an asynchronous client writes its body from the event loop,
# which a blocking read here would stall.
proc ::scidb::test::s1::Accept {chan addr port} {
	variable Buffer
	set Buffer($chan) ""
	fconfigure $chan -translation binary -blocking 0
	fileevent $chan readable [list ::scidb::test::s1::Serve $chan]
}

proc ::scidb::test::s1::Serve {chan} {
	variable Buffer
	variable Replies
	variable Requests

	append Buffer($chan) [::read $chan]
	set end [string first "\r\n\r\n" $Buffer($chan)]
	if {$end < 0} {
		if {[eof $chan]} { close $chan; unset Buffer($chan) }
		return
	}
	set lines [split [string range $Buffer($chan) 0 $end-1] \n]
	set request [string trim [lindex $lines 0]]
	set headers {}
	foreach line [lrange $lines 1 end] {
		if {[regexp {^([^:]+):\s*(.*?)\s*$} $line _ key value]} { dict set headers [string tolower $key] $value }
	}
	set length [expr {[dict exists $headers content-length] ? [dict get $headers content-length] : 0}]
	set body [string range $Buffer($chan) $end+4 end]
	if {[string length $body] < $length} { return }
	unset Buffer($chan)
	fileevent $chan readable {}
	lappend Requests [dict create request $request headers $headers body [encoding convertfrom utf-8 $body]]

	lassign [lindex $Replies 0] code reply
	if {[llength $Replies] > 1} { set Replies [lrange $Replies 1 end] }
	set reply [encoding convertto utf-8 $reply]
	fconfigure $chan -blocking 1
	puts -nonewline $chan "HTTP/1.1 $code X\r\nContent-Type: application/json\r\nContent-Length: [string length $reply]\r\nConnection: close\r\n\r\n$reply"
	close $chan
}

proc ::scidb::test::s1::choice {name confidence} {
	return [list 200 "{\"model\":\"kev-latest\",\"answers\":{\"verdict\":{\"type\":\"choice\",\"choice\":\"$name\",\"confidence\":$confidence,\"probabilities\":{\"$name\":0.9}}},\"latency_ms\":5}"]
}

# A choice answer with a full distribution, <probs> as {"name":p,...}.
proc ::scidb::test::s1::choiceDist {name confidence probs} {
	return [list 200 "{\"model\":\"kev-latest\",\"answers\":{\"verdict\":{\"type\":\"choice\",\"choice\":\"$name\",\"confidence\":$confidence,\"probabilities\":{$probs}}},\"latency_ms\":5}"]
}

proc ::scidb::test::s1::wait {var} {
	set timer [after 5000 [list set $var timeout]]
	vwait $var
	after cancel $timer
	return [set $var]
}


tcltest::test provider-tls-sni {the https handler passes the host as the SNI server name} -body {
	catch { package require tls }
	rename ::tls::socket ::scidb::test::s1::realTlsSocket
	proc ::tls::socket {args} { set ::scidb::test::s1::TlsArgs $args ; return fake-socket }
	set result [::platform::sys::tlsSocket api.typesafe.ai 443]
	set args $::scidb::test::s1::TlsArgs
	rename ::tls::socket {}
	rename ::scidb::test::s1::realTlsSocket ::tls::socket
	list $result $args
} -result {fake-socket {-servername api.typesafe.ai api.typesafe.ai 443}}

tcltest::test systemone-body {questions are encoded in the /v1/systemone shape} -setup {
	::ai::systemone::configure -backend kev
} -body {
	set body [::ai::systemone::body "line one\n\"quoted\"" {
		verdict {type choice instructions "Which?" criteria {bug "a defect" noise "harmless"}}
		urgent  {type noul instructions "Urgent?"}
		level   {type score criteria {low medium high}}
	}]
	set d [json::json2dict $body]
	list [dict get $d model] [dict get $d state] \
		[dict get $d questions verdict] [dict get $d questions urgent] [dict get $d questions level]
} -cleanup {
	::ai::systemone::configure -backend off
} -result {kev-latest {line one
"quoted"} {type choice instructions Which? criteria {bug {a defect} noise harmless}} {type noul instructions Urgent?} {type score criteria {low medium high}}}

tcltest::test systemone-backends {kev and simple-jev presets; off disables; bad questions are refused} -body {
	set saved [expr {[info exists ::env(SIMPLE_JEV_API_KEY)] ? $::env(SIMPLE_JEV_API_KEY) : ""}]
	set ::env(SIMPLE_JEV_API_KEY) secret
	::ai::systemone::configure -backend simple-jev
	set jev [list $::ai::systemone::Config(endpoint) $::ai::systemone::Config(model) $::ai::systemone::Config(apiKey)]
	::ai::systemone::configure -backend vercel
	set vercel [list $::ai::systemone::Config(endpoint) $::ai::systemone::Config(model)]
	::ai::systemone::configure -backend kev
	set kev [list $::ai::systemone::Config(endpoint) $::ai::systemone::Config(model)]
	::ai::systemone::configure -backend off
	set off [::ai::systemone::enabled]
	set ::env(SIMPLE_JEV_API_KEY) $saved
	list $jev $vercel $kev $off \
		[catch { ::ai::systemone::configure -backend gpt } err] $err \
		[catch { ::ai::systemone::body x {q {type choice}} } err] $err \
		[catch { ::ai::systemone::evaluate x {q {type noul}} } err] $err
} -result {{http://127.0.0.1:8000/v1/systemone Qwen/Qwen3.5-0.8B secret} {https://ai-gateway.vercel.sh/typesafe/v1/systemone typesafe-ai/jev} {http://127.0.0.1:8009/v1/systemone kev-latest} 0 1 {unknown System One backend 'gpt' (imajev, kev, simple-jev, plumb, jev, vercel, typesafe, auto or off)} 1 {question 'q': a choice question needs criteria} 1 {no System One backend is configured}}

tcltest::test systemone-env-overrides {presets and probe order are overridable by the environment} -body {
	set savedBackends $::ai::systemone::Backends
	set savedOrder $::ai::systemone::ProbeOrder
	foreach v {SCIDB_AI_PLUMB_URL SCIDB_AI_PLUMB_MODEL SCIDB_AI_PROBE_ORDER} {
		set existed($v) [info exists ::env($v)]
		set prior($v) [expr {$existed($v) ? $::env($v) : ""}]
	}
	set ::env(SCIDB_AI_PLUMB_URL) http://127.0.0.1:1234/v1/systemone
	set ::env(SCIDB_AI_PLUMB_MODEL) custom-model
	set ::env(SCIDB_AI_PROBE_ORDER) plumb,kev
	::ai::systemone::ApplyEnv
	set url [dict get $::ai::systemone::Backends plumb endpoint]
	set model [dict get $::ai::systemone::Backends plumb model]
	set order $::ai::systemone::ProbeOrder
	set ::ai::systemone::Backends $savedBackends
	set ::ai::systemone::ProbeOrder $savedOrder
	foreach v {SCIDB_AI_PLUMB_URL SCIDB_AI_PLUMB_MODEL SCIDB_AI_PROBE_ORDER} {
		if {$existed($v)} { set ::env($v) $prior($v) } else { unset -nocomplain ::env($v) }
	}
	list $url $model $order
} -result {http://127.0.0.1:1234/v1/systemone custom-model {plumb kev}}

tcltest::test systemone-evaluate {evaluate posts the request and returns the answers} -setup {
	::scidb::test::s1::start [list [::scidb::test::s1::choice noise 0.8]]
	::ai::systemone::configure -apiKey k123
} -body {
	set answers [::ai::systemone::evaluate "some state" {verdict {type choice criteria {bug "" noise ""}}}]
	set r [lindex $::scidb::test::s1::Requests 0]
	list [dict get $answers verdict choice] [dict get $answers verdict confidence] \
		[dict get $r request] [dict get $r headers authorization] \
		[dict get [json::json2dict [dict get $r body]] state]
} -cleanup {
	::scidb::test::s1::stop
} -result {noise 0.8 {POST /v1/systemone HTTP/1.1} {Bearer k123} {some state}}

tcltest::test systemone-errors {HTTP errors and a server that is not there are reported} -setup {
	::scidb::test::s1::start [list {422 {{"detail":"criteria must have 1..255 options"}}}]
} -body {
	set bad [catch { ::ai::systemone::evaluate x {q {type noul}} } err1]
	::scidb::test::s1::stop
	# nothing listens on the old port any more
	::ai::systemone::configure -backend kev -endpoint http://127.0.0.1:$::scidb::test::s1::Port/v1/systemone
	::ai::systemone::evaluateAsync x {q {type noul}} {set ::scidb::test::s1::async}
	set async [::scidb::test::s1::wait ::scidb::test::s1::async]
	::ai::systemone::configure -backend off
	list $bad [string match "System One HTTP 422 from *: {\"detail\":\"criteria must have 1..255 options\"}" $err1] \
		[dict get $async ok] [string length [dict get $async error]]
} -match glob -result {1 1 0 [1-9]*}


# --- triage with a classifier ---------------------------------------------

proc ::scidb::test::s1::triageSetup {} {
	variable Dir
	variable Saved
	file delete -force $Dir
	file mkdir $Dir
	set Saved [list $::application::assistant::ErrorLogFile $::application::triage::Auto]
	set ::application::assistant::ErrorLogFile [file join $Dir errors.log]
	set ::application::triage::Auto 0
	# a noise group, then a bug group
	::application::assistant::RecordError log "font cache refreshed twice"
	::application::assistant::RecordError background {can't read "Vars(table)": no such variable} \
		"can't read\n    (procedure \"::application::tree::Update\" line 12)"
}

proc ::scidb::test::s1::triageCleanup {} {
	variable Dir
	variable Saved
	lassign $Saved ::application::assistant::ErrorLogFile ::application::triage::Auto
	file delete -force $Dir
}

# Triage with <llm> as the language model's answer; returns the -done result.
proc ::scidb::test::s1::triage {llm} {
	variable Result {}
	set cfg ::application::ai::Config
	set saved [array get $cfg provider]
	set ${cfg}(provider) stub
	::ai::provider::configure -name stub -responses [list $llm]
	if {[::application::triage::run -done {set ::scidb::test::s1::Result}]} {
		wait ::scidb::test::s1::Result
	}
	array set $cfg $saved
	return $Result
}

proc ::scidb::test::s1::readFile {file} {
	set fh [open $file]; set text [::read $fh]; close $fh
	return $text
}

tcltest::test systemone-triage-split {the classifier settles noise; the bug goes on to the language model} -setup {
	::scidb::test::s1::triageSetup
	lassign [lmap g [::application::triage::groups] { lindex $g 0 }] noise bug
	::scidb::test::s1::start [list [::scidb::test::s1::choice noise 0.91] [::scidb::test::s1::choice bug 0.77]]
} -body {
	set result [::scidb::test::s1::triage "\[{\"id\":\"$bug\",\"verdict\":\"bug\",\"severity\":\"medium\",\"summary\":\"tree pane reads Vars(table) too early\",\"where\":\"::application::tree::Update\",\"suggestion\":\"guard it\"}\]"]
	set issue [::scidb::test::s1::readFile [file join $::scidb::test::s1::Dir issues $bug.md]]
	list [llength $::scidb::test::s1::Requests] [expr {[dict get $result bugs] eq [list $bug]}] \
		[string match "triaged 2 error group(s), 1 bug(s), 1 settled by the classifier\n$noise noise (classifier, confidence 0.91)\n$bug bug medium: *" [dict get $result summary]] \
		[string match "*- classifier: bug 0.77 (kev *)*" $issue] \
		[expr {[lsearch -inline [split [::scidb::test::s1::readFile [file join $::scidb::test::s1::Dir triaged]] \n] "$noise *"] eq "$noise noise classifier 0.91"}] \
		[string first $noise [::application::triage::Prompt $::application::triage::Priv(batch)]]
} -cleanup {
	::scidb::test::s1::stop
	::scidb::test::s1::triageCleanup
} -result {2 1 1 1 1 -1}

tcltest::test systemone-triage-unsure {a low-confidence verdict only advises} -setup {
	::scidb::test::s1::triageSetup
	lassign [lmap g [::application::triage::groups] { lindex $g 0 }] noise bug
	::scidb::test::s1::start [list [::scidb::test::s1::choice noise 0.3]]
} -body {
	set result [::scidb::test::s1::triage "\[{\"id\":\"$noise\",\"verdict\":\"noise\"},{\"id\":\"$bug\",\"verdict\":\"environment\"}\]"]
	list [dict get $result triaged] [string match "*settled by the classifier*" [dict get $result summary]]
} -cleanup {
	::scidb::test::s1::stop
	::scidb::test::s1::triageCleanup
} -result {2 0}

tcltest::test systemone-triage-not-bug {not-a-bug spread over several classes still settles} -setup {
	::scidb::test::s1::triageSetup
	lassign [lmap g [::application::triage::groups] { lindex $g 0 }] noise bug
	::scidb::test::s1::start [list \
		[::scidb::test::s1::choiceDist noise 0.45 {"noise":0.45,"environment":0.40,"bug":0.15}] \
		[::scidb::test::s1::choiceDist bug 0.35 {"bug":0.35,"environment":0.34,"user":0.31}]]
} -body {
	set result [::scidb::test::s1::triage "\[{\"id\":\"$bug\",\"verdict\":\"environment\"}\]"]
	set triaged [split [::scidb::test::s1::readFile [file join $::scidb::test::s1::Dir triaged]] \n]
	list [string match "*settled by the classifier*" [dict get $result summary]] \
		[expr {[lsearch -inline $triaged "$noise *"] eq "$noise noise classifier 0.45"}] \
		[expr {[lsearch -inline $triaged "$bug *"] eq "$bug environment classifier 0.35"}]
} -cleanup {
	::scidb::test::s1::stop
	::scidb::test::s1::triageCleanup
} -result {1 1 1}

tcltest::test systemone-triage-down {without a reachable classifier the language model takes everything} -setup {
	::scidb::test::s1::triageSetup
	lassign [lmap g [::application::triage::groups] { lindex $g 0 }] noise bug
	::scidb::test::s1::start {}
	::scidb::test::s1::stop
	::ai::systemone::configure -backend kev -endpoint http://127.0.0.1:$::scidb::test::s1::Port/v1/systemone
} -body {
	set result [::scidb::test::s1::triage "\[{\"id\":\"$noise\",\"verdict\":\"noise\"},{\"id\":\"$bug\",\"verdict\":\"user\"}\]"]
	list [dict get $result triaged] [string match "*\nclassifier unavailable (kev *): *" [dict get $result summary]]
} -cleanup {
	::ai::systemone::configure -backend off
	::scidb::test::s1::triageCleanup
} -result {2 1}

# ----------------------------------------------------------------------
# Backend presets: plumb (local, port 8090), jev (cloud, through Vercel's
# AI Gateway; vercel is the same server under its older name) and off.
# ----------------------------------------------------------------------

proc ::scidb::test::s1::restoreConfig {config} {
	array set ::ai::systemone::Config $config
}

tcltest::test systemone-backends {the backend presets carry endpoint, model and locality} -body {
	set config [array get ::ai::systemone::Config]
	set rows {}
	foreach b [::ai::systemone::backends] {
		lappend rows [list [dict get $b name] [dict get $b local] \
			[expr {[dict get $b key] eq "" ? "-" : [dict get $b key]}]]
	}
	::scidb::test::s1::restoreConfig $config
	set names [lmap r $rows { lindex $r 0 }]
	list [lsearch -exact $names kev] [lsearch -exact $names plumb] \
		[lsearch -exact $names jev] [lsearch -exact $names vercel] \
		[lindex $rows [lsearch -exact -index 0 $rows plumb]] \
		[lindex $rows [lsearch -exact -index 0 $rows jev]]
} -result {1 3 4 5 {plumb 1 -} {jev 0 AI_GATEWAY_API_KEY}}

tcltest::test systemone-plumb-configure {the plumb preset points at the local port 8090, no key} -body {
	set config [array get ::ai::systemone::Config]
	::ai::systemone::configure -backend plumb
	set result [list [::ai::systemone::enabled] [::ai::systemone::describe]]
	::scidb::test::s1::restoreConfig $config
	set result
} -result {1 {plumb (plumb-4b-v5 at http://127.0.0.1:8090/v1/systemone)}}

tcltest::test systemone-jev-configure {the jev preset reads its key from the environment} -setup {
	set config [array get ::ai::systemone::Config]
} -body {
	set ::env(AI_GATEWAY_API_KEY) test-key
	::ai::systemone::configure -backend jev
	set withKey [list [::ai::systemone::describe] $::ai::systemone::Config(apiKey)]
	unset ::env(AI_GATEWAY_API_KEY)
	::ai::systemone::configure -backend jev
	set withoutKey $::ai::systemone::Config(apiKey)
	::scidb::test::s1::restoreConfig $config
	list [lindex $withKey 0] [lindex $withKey 1] $withoutKey
} -cleanup {
	unset -nocomplain ::env(AI_GATEWAY_API_KEY)
} -result {{jev (typesafe-ai/jev at https://ai-gateway.vercel.sh/typesafe/v1/systemone)} test-key {}}

# --- auto discovery --------------------------------------------------------

tcltest::test systemone-discover {auto finds the first local server that answers} -setup {
	set ::scidb::test::s1::SavedBackends $::ai::systemone::Backends
	::scidb::test::s1::start [list [::scidb::test::s1::choice noise 0.9]]
	# nothing at imajev (probed first); kev is the mock server
	dict set ::ai::systemone::Backends imajev endpoint http://127.0.0.1:1/v1/systemone
	dict set ::ai::systemone::Backends kev endpoint http://127.0.0.1:$::scidb::test::s1::Port/v1/systemone
	::ai::systemone::configure -backend auto
} -body {
	set found [::ai::systemone::discover]
	list $found [::ai::systemone::enabled] [::ai::systemone::describe]
} -cleanup {
	::scidb::test::s1::stop
	set ::ai::systemone::Backends $::scidb::test::s1::SavedBackends
	::ai::systemone::configure -backend off
} -match glob -result {kev 1 {kev (kev-latest at http://127.0.0.1:*/v1/systemone)}}

tcltest::test systemone-discover-none {auto with nothing listening is off} -setup {
	set ::scidb::test::s1::SavedBackends $::ai::systemone::Backends
	foreach b {imajev kev simple-jev plumb} {
		dict set ::ai::systemone::Backends $b endpoint http://127.0.0.1:1/v1/systemone
	}
	::ai::systemone::configure -backend auto
} -body {
	list [::ai::systemone::discover] [::ai::systemone::enabled] [::ai::systemone::describe]
} -cleanup {
	set ::ai::systemone::Backends $::scidb::test::s1::SavedBackends
	::ai::systemone::configure -backend off
} -result {{} 0 {auto (no local server found)}}

tcltest::test systemone-autostart-explicit {an explicit backend is never discovered over} -setup {
	::ai::systemone::configure -backend plumb
} -body {
	::ai::systemone::autostart
	list [::ai::systemone::enabled] $::ai::systemone::Config(backend)
} -cleanup {
	::ai::systemone::configure -backend off
} -result {1 plumb}

tcltest::test systemone-autostart-deferred {auto discovery never blocks the caller} -setup {
	set ::scidb::test::s1::SavedBackends $::ai::systemone::Backends
	foreach b {imajev kev simple-jev plumb} {
		dict set ::ai::systemone::Backends $b endpoint http://127.0.0.1:1/v1/systemone
	}
	::ai::systemone::configure -backend auto
} -body {
	::ai::systemone::autostart
	::ai::systemone::autostart
	set pending [llength [after info]]
	set before $::ai::systemone::Resolved
	set ms [lindex [time { ::ai::systemone::discover }] 0]
	list $before [expr {$ms < 1000000}] [expr {$pending >= 1}]
} -cleanup {
	after cancel $::ai::systemone::AutoJob
	set ::ai::systemone::Backends $::scidb::test::s1::SavedBackends
	::ai::systemone::configure -backend off
} -result {0 1 1}

# --- ::ai::decide: one gated decision -------------------------------------

proc ::scidb::test::s1::decide {question args} {
	variable Decision
	unset -nocomplain Decision
	::ai::decide verdict "some state" $question {set ::scidb::test::s1::Decision} {*}$args
	return [wait ::scidb::test::s1::Decision]
}

set ::scidb::test::s1::Verdict {type choice criteria {bug "a defect" noise "harmless"}}

tcltest::test systemone-valid {only answers of the asked shape are valid} -body {
	set c $::scidb::test::s1::Verdict
	set n {type noul}
	list [::ai::systemone::valid $c {choice noise confidence 0.8}] \
		[::ai::systemone::valid $c {choice zugzwang confidence 0.8}] \
		[::ai::systemone::valid $c {choice noise confidence 1.5}] \
		[::ai::systemone::valid $c {choice noise confidence high}] \
		[::ai::systemone::valid $c {choice noise}] \
		[::ai::systemone::valid $n {noul 0.3}] \
		[::ai::systemone::valid $n {noul -0.1}] \
		[::ai::systemone::valid $n {choice noise confidence 0.8}] \
		[::ai::systemone::valid {type score criteria {a b}} {score 1.5 confidence 0.5}]
} -result {1 0 0 0 0 1 0 0 0}

tcltest::test systemone-decide-gate {confident answers decide; unsure, unknown and absent ones fall back} -setup {
	::scidb::test::s1::start [list \
		[::scidb::test::s1::choice noise 0.9] \
		[::scidb::test::s1::choice noise 0.4] \
		[::scidb::test::s1::choice zugzwang 0.99] \
		{500 {oops}}]
} -body {
	set q $::scidb::test::s1::Verdict
	set out {}
	foreach i {1 2 3 4} {
		lappend out [::scidb::test::s1::decide $q -fallback {string cat bug}]
	}
	::scidb::test::s1::stop
	lappend out [::scidb::test::s1::decide $q -fallback {string cat bug}]
	lappend out [::scidb::test::s1::decide $q]
} -result {{ok 1 label noise confidence 0.9 source classifier} {ok 1 label bug confidence {} source rules} {ok 1 label bug confidence {} source rules} {ok 1 label bug confidence {} source rules} {ok 1 label bug confidence {} source rules} {ok 0}}

tcltest::test systemone-qualified {a classifier decides only the tasks it passed calibration for} -setup {
	set savedEnv $::env(SCIDB_AI_UNCALIBRATED)
	set ::env(SCIDB_AI_UNCALIBRATED) 0
	set savedT $::ai::systemone::Thresholds
	::scidb::test::s1::start [list [::scidb::test::s1::choice noise 0.99]]
	::ai::systemone::LoadOnce
	set ::ai::systemone::Thresholds {comment_kind {kev 0.85}}
} -body {
	list [::ai::systemone::qualified comment_kind] [::ai::systemone::qualified duplicate] \
		[::scidb::test::s1::decide $::scidb::test::s1::Verdict -fallback {string cat bug}]
} -cleanup {
	::scidb::test::s1::stop
	set ::ai::systemone::Thresholds $savedT
	set ::env(SCIDB_AI_UNCALIBRATED) $savedEnv
} -result {1 0 {ok 1 label bug confidence {} source rules}}

tcltest::test systemone-decide-noul {a noul decides yes or no at the threshold} -setup {
	::scidb::test::s1::start [list \
		{200 {{"answers":{"verdict":{"type":"noul","noul":0.35}}}}}]
} -body {
	list [::scidb::test::s1::decide {type noul} -threshold 0.3] \
		[::scidb::test::s1::decide {type noul} -threshold 0.5]
} -cleanup {
	::scidb::test::s1::stop
} -result {{ok 1 label 1 confidence 0.35 source classifier} {ok 1 label 0 confidence 0.35 source classifier}}

tcltest::test systemone-threshold {environment, then the per-backend table, then the default} -setup {
	set saved $::ai::systemone::Thresholds
	::ai::systemone::configure -backend kev
} -body {
	set out [list [::ai::systemone::threshold verdict 0.6]]
	set ::ai::systemone::Thresholds {verdict {kev 0.8 plumb 0.5}}
	lappend out [::ai::systemone::threshold verdict 0.6]
	set ::env(SCIDB_AI_VERDICT_MIN_CONFIDENCE) 0.9
	lappend out [::ai::systemone::threshold verdict 0.6]
	set ::env(SCIDB_AI_VERDICT_MIN_CONFIDENCE) junk
	lappend out [::ai::systemone::threshold verdict 0.6]
} -cleanup {
	unset -nocomplain ::env(SCIDB_AI_VERDICT_MIN_CONFIDENCE)
	set ::ai::systemone::Thresholds $saved
	::ai::systemone::configure -backend off
} -result {0.6 0.8 0.9 0.8}

tcltest::test systemone-triage-unknown-label {a label that was not offered never settles a group} -setup {
	::scidb::test::s1::triageSetup
	lassign [lmap g [::application::triage::groups] { lindex $g 0 }] noise bug
	::scidb::test::s1::start [list [::scidb::test::s1::choice harmless 0.95]]
} -body {
	set result [::scidb::test::s1::triage "\[{\"id\":\"$noise\",\"verdict\":\"noise\"},{\"id\":\"$bug\",\"verdict\":\"environment\"}\]"]
	list [dict get $result triaged] [string match "*settled by the classifier*" [dict get $result summary]]
} -cleanup {
	::scidb::test::s1::stop
	::scidb::test::s1::triageCleanup
} -result {2 0}

# --- event-type bucketing (tcl/ai-event.tcl) -------------------------------

proc ::scidb::test::s1::nop {args} { return 0 }

proc ::scidb::test::s1::answer {id name confidence} {
	return [list 200 "{\"model\":\"kev-latest\",\"answers\":{\"$id\":{\"type\":\"choice\",\"choice\":\"$name\",\"confidence\":$confidence}},\"latency_ms\":5}"]
}

proc ::scidb::test::s1::level {id value confidence} {
	return [list 200 "{\"model\":\"kev-latest\",\"answers\":{\"$id\":{\"type\":\"score\",\"score\":$value,\"confidence\":$confidence}},\"latency_ms\":5}"]
}

proc ::scidb::test::s1::eventFixture {} {
	variable Dir
	file delete -force $Dir
	file mkdir $Dir
	set file [file join $Dir events.pgn]
	set fh [open $file w]
	fconfigure $fh -encoding utf-8
	foreach {event tc} {
		"Blitz Arena" "300+0"
		"Classical Cup" "7200+30"
		"Titled Arena Bullet" "-"
		"Some Mystery Open" "-"
	} {
		puts $fh "\[Event \"$event\"\]\n\[Site \"X\"\]\n\[Date \"2024.01.01\"\]\n\[Round \"1\"\]"
		puts $fh "\[White \"W\"\]\n\[Black \"B\"\]\n\[Result \"*\"\]\n\[TimeControl \"$tc\"\]\n"
		puts $fh "\n1. e4 e5 *\n"
	}
	close $fh
	::scidb::db::open $file ::scidb::test::s1::nop {} ::scidb::test::s1::nop {}
	return $file
}

tcltest::test systemone-event-rulemix {the deterministic mix over a set of games} -setup {
	set f [::scidb::test::s1::eventFixture]
} -body {
	set numbers {}
	set view [::scidb::view::new $f Normal unused unused unused unused master slave]
	::scidb::view::search $f Normal $view reset none
	for {set row 0} {$row < [::scidb::view::count games $f Normal $view]} {incr row} {
		lappend numbers [::scidb::db::get gameNumber $f Normal $row $view]
	}
	set mix [::ai::event::RuleMix $f Normal $numbers]
	list [dict get $mix classical] [dict get $mix blitz] [dict get $mix bullet] [dict get $mix unclear]
} -cleanup {
	::scidb::db::close $f
	file delete -force $::scidb::test::s1::Dir
} -result {1 1 1 1}

tcltest::test systemone-event-rule-unit {TimeControl parsing and event words} -body {
	list [::ai::event::BaseSeconds "300+0"] [::ai::event::BaseSeconds "40/7200:1800"] \
		[::ai::event::BaseSeconds "-"] \
		[::ai::event::Rule {TimeControl 60+0}] [::ai::event::Rule {TimeControl 600+5}] \
		[::ai::event::Rule {TimeControl 1800+0}] [::ai::event::Rule {Event "Titled Arena Blitz"}] \
		[::ai::event::Rule {Event "Winter Open"}] [::ai::event::Rule {Event "ICCF" TimeControl -}]
} -result {300 7200 {} bullet rapid classical blitz {} correspondence}

tcltest::test systemone-event-rule {the rule buckets the games; the rest is unclear with no classifier} -setup {
	::ai::systemone::configure -backend off
	set f [::scidb::test::s1::eventFixture]
} -body {
	set ::scidb::test::s1::Event {}
	::ai::event::profile $f Normal -done {set ::scidb::test::s1::Event}
	set p [::scidb::test::s1::wait ::scidb::test::s1::Event]
	set c [dict get $p classes]
	list [dict get $p games] [dict get $c classical] [dict get $c blitz] [dict get $c bullet] [dict get $c unclear] \
		[::ai::event::ProfileText $p]
} -cleanup {
	::scidb::db::close $f
	file delete -force $::scidb::test::s1::Dir
} -result {4 1 1 1 1 {Time controls of 4 game(s): classical 1, blitz 1, bullet 1, unclear 1.}}

tcltest::test systemone-event-rule-only {the residual is unclear; the classifier is not consulted} -setup {
	set f [::scidb::test::s1::eventFixture]
	::scidb::test::s1::start [list [::scidb::test::s1::answer event_type rapid 0.9]]
} -body {
	set ::scidb::test::s1::Event {}
	::ai::event::profile $f Normal -done {set ::scidb::test::s1::Event}
	set p [::scidb::test::s1::wait ::scidb::test::s1::Event]
	set c [dict get $p classes]
	list [dict get $c rapid] [dict get $c unclear] [llength $::scidb::test::s1::Requests]
} -cleanup {
	::scidb::test::s1::stop
	::scidb::db::close $f
	file delete -force $::scidb::test::s1::Dir
} -result {0 1 0}

tcltest::test systemone-event-assistant {event_types goes through CheckArgs and answers} -setup {
	set f [::scidb::test::s1::eventFixture]
	::scidb::test::s1::start [list [::scidb::test::s1::answer event_type training 0.8]]
} -body {
	set tok [::application::assistant::DoEventTypes "" 500]
	list [::application::assistant::CheckArgs event_types {}] \
		[::application::assistant::CheckArgs event_types {games 50}] \
		[catch {::application::assistant::CheckArgs event_types {games 0}} e] $e \
		[string range $tok 1 6]
} -cleanup {
	::scidb::test::s1::stop
	::scidb::db::close $f
	file delete -force $::scidb::test::s1::Dir
} -result {{player {} games 500} {player {} games 50} 1 {games must be an integer between 1 and 10000} later:}

# --- comment language tagging (tcl/ai-language.tcl) ------------------------

tcltest::test systemone-player-select {the classifier picks a roster candidate; code copies the row} -setup {
	::scidb::test::s1::start [list [::scidb::test::s1::answer q "Carlsen, Magnus" 0.9]]
} -body {
	::application::assistant::SelectPlayer "magnus carlsen" \
		{{1 {Carlsen, Magnus} 100} {2 {Carlsen, M.} 5}}
} -cleanup {
	::scidb::test::s1::stop
} -result {1 {Carlsen, Magnus}}

tcltest::test systemone-player-none {none of the candidates -> the caller keeps its fallback} -setup {
	::scidb::test::s1::start [list [::scidb::test::s1::answer q none 0.9]]
} -body {
	::application::assistant::SelectPlayer "someone else" \
		{{1 {Carlsen, Magnus} 100} {2 {Carlsen, M.} 5}}
} -cleanup {
	::scidb::test::s1::stop
} -result {}

tcltest::test systemone-player-lowconfidence {a weak pick is an abstention} -setup {
	::scidb::test::s1::start [list [::scidb::test::s1::answer q "Carlsen, M." 0.2]]
} -body {
	::application::assistant::SelectPlayer "carlsen m" \
		{{1 {Carlsen, Magnus} 100} {2 {Carlsen, M.} 5}}
} -cleanup {
	::scidb::test::s1::stop
} -result {}

tcltest::test systemone-player-threshold {a pick below the measured gate is an abstention} -setup {
	::scidb::test::s1::start [list [::scidb::test::s1::answer q "Carlsen, Magnus" 0.7]]
} -body {
	::application::assistant::SelectPlayer "carlsen" \
		{{1 {Carlsen, Magnus} 100} {2 {Carlsen, M.} 5}}
} -cleanup {
	::scidb::test::s1::stop
} -result {}

tcltest::test systemone-player-off {no classifier -> the caller keeps its fallback} -body {
	::ai::systemone::configure -backend off
	::application::assistant::SelectPlayer "magnus" {{1 {Carlsen, Magnus} 100}}
} -result {}

tcltest::test systemone-language-rule {scripts decide; Latin and shared scripts defer to the classifier} -body {
	list [::ai::language::Rule "1. e4 e5"] \
		[::ai::language::Rule "\u041a\u043e\u0440\u043e\u043b\u044c"] \
		[::ai::language::Rule "\u039f \u03b2\u03b1\u03c3\u03b9\u03bb\u03b9\u03ac\u03c2"] \
		[::ai::language::Rule "\u05d4\u05de\u05dc\u05da"] \
		[::ai::language::Rule "\u0627\u0644\u0645\u0644\u0643"] \
		[::ai::language::Rule "\u30c1\u30a7\u30c3\u30af"] \
		[::ai::language::Rule "\uccb4\ud06c\uba54\uc774\ud2b8"] \
		[::ai::language::Rule "\u738b\u624b"] \
		[::ai::language::Rule "the king is exposed"] \
		[::ai::language::Rule "\u2658\u2657\u2655"]
} -result {{} {} el he ar ja ko {} {} xx}

tcltest::test systemone-language-detect {the classifier decides a Latin text} -setup {
	::scidb::test::s1::start [list [::scidb::test::s1::answer language de 0.9]]
} -body {
	set ::scidb::test::s1::Lang {}
	::ai::language::detect "der K\u00f6nig ist gefangen" {set ::scidb::test::s1::Lang}
	set r [::scidb::test::s1::wait ::scidb::test::s1::Lang]
	list [dict get $r label] [dict get $r source]
} -cleanup {
	::scidb::test::s1::stop
} -result {de classifier}

tcltest::test systemone-language-rulepath {a script decides with no request} -body {
	set ::scidb::test::s1::Lang {}
	::ai::language::detect "\u039f \u03b2\u03b1\u03c3\u03b9\u03bb\u03b9\u03ac\u03c2" {set ::scidb::test::s1::Lang}
	set r [::scidb::test::s1::wait ::scidb::test::s1::Lang]
	list [dict get $r label] [dict get $r source]
} -result {el rules}

tcltest::test systemone-language-assistant {detect_language checks args and answers} -setup {
	::scidb::test::s1::start [list [::scidb::test::s1::answer language fr 0.8]]
} -body {
	set tok [::application::assistant::DoDetectLanguage "le roi est nu"]
	list [::application::assistant::CheckArgs detect_language {text "le roi"}] \
		[catch {::application::assistant::CheckArgs detect_language {}} e] $e \
		[string range $tok 1 6]
} -cleanup {
	::scidb::test::s1::stop
} -result {{text {le roi}} 1 {missing argument 'text'} later:}

# --- import doctor (tcl/ai-import.tcl) -------------------------------------

tcltest::test systemone-import-rule {known codes map to a category; unknown codes do not} -body {
	list [::ai::import::Rule InvalidMove] \
		[::ai::import::Rule SeemsNotToBePgnText] \
		[::ai::import::Rule EncodingFailed] \
		[::ai::import::Rule MissingResultTag] \
		[::ai::import::Rule BogusCode]
} -result {illegal-moves not-pgn encoding missing-tags {}}

tcltest::test systemone-import-text {the rule-only doctor groups the messages} -body {
	set expected [join [list \
		"Import doctor:" \
		"  the file's character encoding is wrong (1 message(s)): pick the source's character encoding in the import dialog" \
		"  some moves could not be played (1 message(s)): the PGN is corrupt, or the game is a variant; check the moves" \
		"  an unclassified problem (1 message(s)): review the messages above"] \n]
	expr {[::ai::import::Text {InvalidMove EncodingFailed InvalidMove BogusCode}] eq $expected}
} -result 1

tcltest::test systemone-import-diagnose {the classifier answers when a code is unknown} -setup {
	::scidb::test::s1::start [list [::scidb::test::s1::answer import_diagnosis bad-fen 0.9]]
} -body {
	set ::scidb::test::s1::Diag {}
	::ai::import::diagnose {BogusCode} {set ::scidb::test::s1::Diag}
	set r [::scidb::test::s1::wait ::scidb::test::s1::Diag]
	list [dict get $r label] [dict get $r source] [llength $::scidb::test::s1::Requests]
} -cleanup {
	::scidb::test::s1::stop
} -result {bad-fen classifier 1}

tcltest::test systemone-import-rulepath {known codes decide without the classifier} -body {
	set ::scidb::test::s1::Diag {}
	::ai::import::diagnose {InvalidMove MissingResultTag} {set ::scidb::test::s1::Diag}
	set r [::scidb::test::s1::wait ::scidb::test::s1::Diag]
	list [dict get $r label] [dict get $r source]
} -result {{} rules}

tcltest::test systemone-import-assistant {diagnose_import checks args and answers} -setup {
	::scidb::test::s1::start [list [::scidb::test::s1::answer import_diagnosis truncated 0.8]]
} -body {
	set tok [::application::assistant::DoDiagnoseImport {InvalidMove SeemsNotToBePgnText}]
	list [::application::assistant::CheckArgs diagnose_import {codes {InvalidMove SeemsNotToBePgnText}}] \
		[catch {::application::assistant::CheckArgs diagnose_import {}} e] $e \
		[string range $tok 1 6]
} -cleanup {
	::scidb::test::s1::stop
} -result {{codes {InvalidMove SeemsNotToBePgnText}} 1 {missing argument 'codes'} later:}

# --- comment kind (tcl/ai-comment.tcl) -------------------------------------

tcltest::test systemone-comment-rule {keywords map to a kind; unknown words defer} -body {
	list [::ai::comment::Rule "the fork wins a rook"] \
		[::ai::comment::Rule "a typical pawn ending"] \
		[::ai::comment::Rule "White is clearly better"] \
		[::ai::comment::Rule "develops and prepares to castle"] \
		[::ai::comment::Rule "the point is to pressure e5"] \
		[::ai::comment::Rule "a blunder, only move was Kf8"] \
		[::ai::comment::Rule "zugzwang"] \
		[::ai::comment::Rule "hello world"]
} -result {tactics endgame evaluation opening plan warning endgame {}}

tcltest::test systemone-comment-rule-symbols {evaluation symbols; must/check alone are not a kind} -body {
	list [::ai::comment::Rule "+- with a clear plan"] \
		[::ai::comment::Rule "black is =+ here"] \
		[::ai::comment::Rule "you must see this"] \
		[::ai::comment::Rule "check the line"] \
		[::ai::comment::Rule "a discovered check wins"]
} -result {evaluation evaluation {} {} tactics}

tcltest::test systemone-comment-classifier {the classifier decides when the words do not} -setup {
	::scidb::test::s1::start [list [::scidb::test::s1::answer comment_kind plan 0.9]]
} -body {
	set ::scidb::test::s1::Kind {}
	::ai::comment::kind "this keeps the tension" {set ::scidb::test::s1::Kind}
	set r [::scidb::test::s1::wait ::scidb::test::s1::Kind]
	list [dict get $r label] [dict get $r source]
} -cleanup {
	::scidb::test::s1::stop
} -result {plan classifier}

tcltest::test systemone-comment-rulepath {the keyword rule decides without the classifier} -body {
	set ::scidb::test::s1::Kind {}
	::ai::comment::kind "a knight fork" {set ::scidb::test::s1::Kind}
	set r [::scidb::test::s1::wait ::scidb::test::s1::Kind]
	list [dict get $r label] [dict get $r source]
} -result {tactics rules}

tcltest::test systemone-comment-assistant {comment_kind checks args and answers} -setup {
	::scidb::test::s1::start [list [::scidb::test::s1::answer comment_kind plan 0.9]]
} -body {
	set tok [::application::assistant::DoCommentKind "keeps the tension"]
	list [::application::assistant::CheckArgs comment_kind {text "keeps the tension"}] \
		[catch {::application::assistant::CheckArgs comment_kind {}} e] $e \
		[string range $tok 1 6]
} -cleanup {
	::scidb::test::s1::stop
} -result {{text {keeps the tension}} 1 {missing argument 'text'} later:}

# --- the score primitive (previously unhandled) -----------------------------

tcltest::test systemone-score-valid {valid checks the score shape} -body {
	set q [dict create type score criteria {low medium high}]
	list [::ai::systemone::valid $q {score 0.5 confidence 0.9}] \
		[::ai::systemone::valid $q {score 1.5 confidence 0.9}] \
		[::ai::systemone::valid $q {score 0.5 confidence 1.5}] \
		[::ai::systemone::valid $q {choice low confidence 0.9}]
} -result {1 0 0 0}

tcltest::test systemone-score-level {a score maps to an ordered level} -setup {
	::scidb::test::s1::start [list [::scidb::test::s1::level quality 0.8 0.9]]
} -body {
	set ::scidb::test::s1::Score {}
	::ai::decide quality x {type score criteria {low medium high}} \
		{set ::scidb::test::s1::Score}
	set d [::scidb::test::s1::wait ::scidb::test::s1::Score]
	list [dict get $d label] [dict get $d confidence] [dict get $d source]
} -cleanup {
	::scidb::test::s1::stop
} -result {high 0.8 classifier}

tcltest::test systemone-score-gate {a low-confidence score falls back} -setup {
	::scidb::test::s1::start [list [::scidb::test::s1::level quality 0.8 0.3]]
} -body {
	set ::scidb::test::s1::Score {}
	::ai::decide quality x {type score criteria {low medium high}} \
		{set ::scidb::test::s1::Score} -fallback {expr {"low"}}
	set d [::scidb::test::s1::wait ::scidb::test::s1::Score]
	list [dict get $d label] [dict get $d source]
} -cleanup {
	::scidb::test::s1::stop
} -result {low rules}

# Regression: ::import defines its own `info` proc, so a bare [info commands]
# inside it calls that proc and fails with 'wrong # args: should be "info line"'.
# The import doctor's hook at the end of ::import::logResult used to do so,
# which broke the log step of every file import.
tcltest::test import-log-result-doctor-hook {logResult reaches the import doctor through ::info, not the shadowing proc} -body {
	set body [info body ::import::logResult]
	list \
		[expr {[llength [info commands ::import::info]] > 0}] \
		[string match {*\[::info commands ::ai::import::Text\]*} $body] \
		[string match {*\[info commands ::ai::import::Text\]*} $body]
} -result {1 1 0}

::tcltest::cleanupTests
return
