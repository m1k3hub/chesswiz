# ======================================================================
# test_ai_ui.tcl -- the UI rendering helpers and the async generate path.
#
#   xvfb-run -a ./src/tkscidb-beta tests/test_ai_ui.tcl
#
# The full `analyze` command needs the assembled application (report widget,
# menu); here we cover the parts that are testable in isolation.
# ======================================================================

set failures 0

proc check {name cond} {
	global failures
	if {$cond} { puts "PASS: $name" } else { puts "FAIL: $name"; incr failures }
}

set root [file join [file dirname [file normalize [info script]]] ..]
source [file join $root tcl ai-claims.tcl]
source [file join $root tcl ai-provider.tcl]
source [file join $root tcl ai-prompt.tcl]
source [file join $root tcl ai-generate.tcl]
source [file join $root tcl app-ai.tcl]

# App-backed: needs the tkscidb shell. Skip cleanly if sourced elsewhere.
if {[llength [info commands ::scidb::ai::facts]] == 0} {
	puts "SKIP: requires the tkscidb shell (::scidb::ai::* unavailable)"
	puts "AI-UI-FAILURES: 0"
	exit 0
}

set start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

# --- HTML rendering ---------------------------------------------------
check "toHtml command exists" [expr {[llength [info commands ::application::ai::toHtml]] == 1}]
check "toHtml escapes markup" \
	[string match {*&lt;b&gt;*} [::application::ai::toHtml "x <b> y" {}]]
check "toHtml reports verification when clean" \
	[string match {*verified against the facts*} [::application::ai::toHtml "text" {}]]
check "toHtml lists ungrounded claims" \
	[string match {*<li>ungrounded foo</li>*} [::application::ai::toHtml "text" [list "ungrounded foo"]]]
check "toHtml renders the evidence" \
	[string match {*<li>ENGINE: eval=cp 10</li>*} [::application::ai::toHtml "t" {} [list "ENGINE: eval=cp 10"]]]
check "toHtml omits evidence when absent" \
	[expr {![string match {*Evidence*} [::application::ai::toHtml "t" {}]]}]
check "toHtml escapes evidence markup" \
	[string match {*&lt;b&gt;*} [::application::ai::toHtml "t" {} [list "x <b> y"]]]

# --- report payload shape ---------------------------------------------
# The report pane's Load does `dict get $data html`, so showHtmlData must be
# handed a sanitized-document dict, never a raw string.
set hd [::application::ai::htmlData "<p><b>Assessment</b></p><p>hi</p>"]
foreach key {html media anchors unresolved} {
	check "htmlData carries key '$key'" [dict exists $hd $key]
}
check "htmlData preserves the markup" \
	[string match {*<b>Assessment</b>*} [dict get $hd html]]

# The original bug: a raw string reaches `Load`, which does `dict get $data html`
# and dies with "missing value to go with key".
check "raw-string payload reproduces the old failure" \
	[catch {dict get "<p>x</p>" html}]
check "htmlData payload is readable by Load" \
	[expr {![catch {dict get [::application::ai::htmlData "<p>x</p>"] html}]}]

# --- prompt evidence extraction ---------------------------------------
check "evidenceFromText extracts the three blocks" \
	[expr {[llength [::ai::generate::evidenceFromText "FACTS: x\nENGINE: eval=cp 10\nMASTER PRACTICE: 5 games\nANNOTATED EXAMPLES: \"hi\""]] == 3}]
check "evidenceFromText ignores other lines" \
	[expr {[llength [::ai::generate::evidenceFromText "just prose\nLEGAL MOVES: 20"]] == 0}]

# --- async generation (stub) -----------------------------------------
::ai::provider::configure -name stub -responses {"The position is balanced."}
set ::gresult {}
::ai::generate::positionAsync $start [list set ::gresult] -engine 0
vwait ::gresult
check "async generate succeeds" [expr {[dict get $::gresult ok] == 1}]
check "async generate is grounded" [expr {[dict get $::gresult grounded] == 1}]
check "async generate takes one attempt" [expr {[dict get $::gresult attempts] == 1}]
check "async result carries evidence" [dict exists $::gresult evidence]

# --- async retry on an ungrounded claim -------------------------------
::ai::provider::configure -name stub -responses {
	"White has an isolated pawn."
	"The position is balanced."
}
set ::gresult {}
::ai::generate::positionAsync $start [list set ::gresult] -engine 0 -retries 1
vwait ::gresult
check "async retry happens" [expr {[dict get $::gresult attempts] == 2}]
check "async retry recovers" [expr {[dict get $::gresult grounded] == 1}]

puts "AI-UI-FAILURES: $failures"
exit $failures
