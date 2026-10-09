# ======================================================================
# Calibrate the System One gates against a live backend.
#
#   xvfb-run -a src/tkchesswiz scripts/calibrate-systemone.tcl \
#       --backend plumb --url http://127.0.0.1:11435/v1/systemone \
#       --model plumb-4b-v5:latest --features comment_kind,event_type \
#       --out tcl/ai-thresholds.tsv
#
# --timeout MS raises the per-request timeout for a slow local server.
#
# Prints, per feature, the recommended (threshold coverage accuracy) on the
# labelled battery (tests/fixtures/systemone-battery.tcl), and with --out
# merges one line per (feature, backend) into the thresholds file that
# ::ai::systemone::loadThresholds reads.
#
# Defaults come from the environment when a flag is absent:
#   SCIDB_AI_CAL_BACKEND, SCIDB_AI_CAL_URL, SCIDB_AI_CAL_MODEL,
#   SCIDB_AI_CAL_FEATURES, SCIDB_AI_CAL_TARGET, SCIDB_AI_CAL_OUT,
#   SCIDB_AI_CAL_CACHE
# ======================================================================

set root [file dirname [file dirname [file normalize [info script]]]]

# app-error-triage gives the triage question; it must not schedule a run
set ::env(SCIDB_AI_TRIAGE) 0
namespace eval ::application::assistant { variable ErrorLogFile "" }

foreach module {ai-provider ai-systemone ai-batch ai-calibrate \
	ai-comment ai-event ai-language app-error-triage} {
	catch { ::util::source $module }
	source [file join $root tcl $module.tcl]
}
source [file join $root tests fixtures systemone-battery.tcl]
source [file join $root tests fixtures triage-battery.tcl]

proc envOr {name default} {
	expr {[info exists ::env($name)] && $::env($name) ne "" ? $::env($name) : $default}
}

set opt(-backend)     [envOr SCIDB_AI_CAL_BACKEND plumb]
set opt(-url)         [envOr SCIDB_AI_CAL_URL ""]
set opt(-model)       [envOr SCIDB_AI_CAL_MODEL ""]
set opt(-features)    [envOr SCIDB_AI_CAL_FEATURES "comment_kind,event_type"]
set opt(-target)      [envOr SCIDB_AI_CAL_TARGET 0.9]
set opt(-out)         [envOr SCIDB_AI_CAL_OUT ""]
set opt(-cache)       [envOr SCIDB_AI_CAL_CACHE ""]
set opt(-concurrency) 2
set opt(-timeout)     ""
foreach {flag value} $::argv {
	switch -- $flag {
		--backend     { set opt(-backend) $value }
		--url         { set opt(-url) $value }
		--model       { set opt(-model) $value }
		--features    { set opt(-features) $value }
		--target      { set opt(-target) $value }
		--out         { set opt(-out) $value }
		--cache       { set opt(-cache) $value }
		--concurrency { set opt(-concurrency) $value }
		--timeout     { set opt(-timeout) $value }
		default       { puts stderr "unknown option $flag" ; exit 2 }
	}
}

set features [split $opt(-features) ,]
if {"triage" in $features && !$::scidb::calibrate::TriageReviewed} {
	puts stderr "the triage labels are a draft (tests/fixtures/triage-battery.tcl); review them and set TriageReviewed 1"
	exit 1
}

::ai::systemone::configure -backend $opt(-backend)
if {$opt(-url) ne ""}   { ::ai::systemone::configure -endpoint $opt(-url) }
if {$opt(-model) ne ""} { ::ai::systemone::configure -model $opt(-model) }
if {$opt(-timeout) ne ""} { ::ai::systemone::configure -timeout $opt(-timeout) }

if {![::ai::systemone::enabled]} {
	puts stderr "no System One backend configured"
	exit 1
}

puts "backend=$opt(-backend) endpoint=$::ai::systemone::Config(endpoint) model=$::ai::systemone::Config(model)"
puts "features=[join $features {, }] target=$opt(-target)"

set ::done 0
set ::result {}
set battery [::scidb::calibrate::Battery]
dict set battery triage [::scidb::calibrate::TriageCases]
::ai::calibrate::run $features $battery {apply {{result} {
	set ::result $result
	set ::done 1
}}} -target $opt(-target) -concurrency $opt(-concurrency) -cache $opt(-cache)

set timer [after 900000 {set ::done timeout}]
vwait ::done
after cancel $timer

if {$::done ne "1"} {
	puts stderr "calibration did not finish: $::done"
	exit 1
}
if {![dict get $::result ok]} {
	puts stderr "calibration failed: [dict get $::result error]"
	exit 1
}

set report [dict get $::result report]
set target $opt(-target)
set calibrated {}
foreach feature $features {
	set row [dict get $report $feature]
	set accuracy [dict get $row accuracy]
	set target [dict get $row target]
	if {$opt(-out) eq ""} { continue }
	if {$accuracy + 1e-9 >= $target} {
		::ai::calibrate::write $opt(-out) $feature $opt(-backend) [dict get $row threshold]
		lappend calibrated $feature
	} else {
		# a failed calibration must not leave a stale threshold behind
		::ai::calibrate::drop $opt(-out) $feature $opt(-backend)
	}
}

puts ""
puts [format "%-16s %9s %9s %9s %6s %6s" feature threshold coverage accuracy total errors]
foreach feature $features {
	set row [dict get $report $feature]
	puts [format "%-16s %9.3f %9.3f %9.3f %6d %6d" $feature \
		[dict get $row threshold] [dict get $row coverage] [dict get $row accuracy] \
		[dict get $row total] [dict get $row errors]]
}
puts ""
foreach feature $features {
	set accuracy [dict get [dict get $report $feature] accuracy]
	set target [dict get [dict get $report $feature] target]
	if {$accuracy + 1e-9 >= $target} {
		puts "calibrated: $feature (accuracy [format %.3f $accuracy] >= target $target)"
	} else {
		puts "NOT calibrated: $feature (accuracy [format %.3f $accuracy] < target $target); its gate is left unchanged"
	}
}
if {$opt(-out) ne ""} { puts "\nwrote $opt(-out): [join $calibrated {, }]" }
exit 0
