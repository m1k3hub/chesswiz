# ======================================================================
# test_ai_annotations.tcl -- annotation exemplars in the narration prompt.
#
#   xvfb-run -a ./src/tkscidb-beta tests/test_ai_annotations.tcl
#
# Builds a tiny annotation index from a synthetic annotated PGN, then checks
# that ::ai::annotations::lookup reads it and the prompt carries the evidence.
# ======================================================================

set failures 0

proc check {name cond} {
	global failures
	if {$cond} { puts "PASS: $name" } else { puts "FAIL: $name"; incr failures }
}

set root [file join [file dirname [file normalize [info script]]] ..]
source [file join $root tcl ai-annotations.tcl]
source [file join $root tcl ai-prompt.tcl]
source [file join $root tcl ai-claims.tcl]

# App-backed: needs the tkscidb shell (::scidb::ai::facts, json).
if {[llength [info commands ::scidb::ai::facts]] == 0} {
	puts "SKIP: requires the tkscidb shell (::scidb::ai::* unavailable)"
	puts "AI-ANNOTATIONS-FAILURES: 0"
	exit 0
}

set extract [file join $root scripts annotation_extract.py]
set index   [file join $root scripts annotation_index.py]
set tmp [file join $root tests tmp-annotations]
file mkdir $tmp
set pgn [file join $tmp ann.pgn]
set jsonl [file join $tmp ann.jsonl]
set db [file join $tmp ann.sqlite]
file delete -force $db

set fh [open $pgn w]
puts $fh {[Event "a"]
[Source "TestBook"]
[Result "1-0"]

1. e4 {A strong first move.} $14 e5 {Symmetric.} 2. Nf3 $36 Nc6 1-0}
close $fh

exec python3 $extract --pgn $pgn --out $jsonl --max-games 10
exec python3 $index build --jsonl $jsonl --db $db

::ai::annotations::configure -index $db -script $index

set start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

set d [::ai::annotations::lookup $start]
check "lookup finds annotations" [expr {[llength $d] > 0}]
check "lookup has the e4 comment" \
	[expr {[llength [dict get $d annotations]] > 0}]

set c [dict get [lindex [dict get $d annotations] 0] comment]
check "comment is the extracted prose" [expr {$c eq "A strong first move."}]

set summary [::ai::annotations::summary $start]
check "summary mentions the note" [string match {*strong first move*} $summary]
check "summary carries the NAG"    [string match {*NAG 14*} $summary]

set prompt [::ai::prompt::position $start -engine 0]
check "prompt carries ANNOTATED EXAMPLES" [string match {*ANNOTATED EXAMPLES:*} $prompt]

# unconfigured index -> no annotations, no block
::ai::annotations::configure -index [file join $tmp missing.sqlite]
check "missing index yields no summary" [expr {[::ai::annotations::summary $start] eq ""}]
set prompt [::ai::prompt::position $start -engine 0]
check "prompt omits ANNOTATED EXAMPLES when unknown" \
	[expr {![string match {*ANNOTATED EXAMPLES:*} $prompt]}]

file delete -force $tmp

puts "AI-ANNOTATIONS-FAILURES: $failures"
exit $failures
