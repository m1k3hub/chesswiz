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

proc ::scidb::test::s1::wait {var} {
	set timer [after 5000 [list set $var timeout]]
	vwait $var
	after cancel $timer
	return [set $var]
}


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
} -result {{http://127.0.0.1:8000/v1/systemone Qwen/Qwen3.5-0.8B secret} {https://ai-gateway.vercel.sh/typesafe/v1/systemone typesafe-ai/jev} {http://127.0.0.1:8009/v1/systemone kev-latest} 0 1 {unknown System One backend 'gpt' (kev, simple-jev, plumb, jev, vercel, auto or off)} 1 {question 'q': a choice question needs criteria} 1 {no System One backend is configured}}

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
} -result {0 2 3 4 {plumb 1 -} {jev 0 AI_GATEWAY_API_KEY}}

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
	# point the preferred kev preset at the mock server
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
	foreach b {kev simple-jev plumb} {
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

::tcltest::cleanupTests
return
