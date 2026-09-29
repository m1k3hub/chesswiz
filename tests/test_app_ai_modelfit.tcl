# ======================================================================
# Scidb App Test — model-fit recommendations (tcl/ai-modelfit.tcl)
# ======================================================================
# Nothing here asks a model anything: memory is read from a fixture
# meminfo in tests/tmp-app/ and from a gpu command that either sums its
# lines or fails, and the fit is pure arithmetic (params_b * bits/8 GB
# plus 20% overhead, compared with MiB).  The expected values are
# recorded in variables, not recomputed in the test bodies.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::modelfit {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app modelfit_[pid]]
	variable Missing [file join $Dir no-such-meminfo.txt]

	# fixture meminfo and its MemTotal (32768000 kB -> 32000 MiB)
	variable FixtureMeminfo {"MemTotal:       32768000 kB" "MemFree:        16000000 kB" "MemAvailable:   24000000 kB"}
	variable FixtureRam {ram_mb 32000 vram_mb 0}
	# no (or a bad) MemTotal line: no memory, never an error
	variable BadMeminfo {"MemTotal:       soon kB" "Cached:            900 kB"}
	variable NoRam {ram_mb 0 vram_mb 0}
	# nvidia-smi-shaped lines ("24576, 24576" -> both cards summed)
	variable GpuFixture {"24576, 24576"}
	variable GpuRam {ram_mb 32000 vram_mb 49152}

	# the candidate battery and the recorded fits
	variable Fixtures [list \
		{name big params_b 7} {name mid params_b 1.5} \
		{name small params_b 0.7} {name tiny params_b 0.5} \
		{name huge params_b 90}]
	variable GpuMemory {ram_mb 8192 vram_mb 12288}
	variable GpuNames {big mid small tiny huge}
	variable GpuQuants {q8_0 q8_0 q8_0 q8_0 none}
	variable GpuPlacements {gpu gpu gpu gpu none}
	variable MidLine "mid: q8_0 (gpu, 1958.4 MB)"
	variable SmallLine "small: q8_0 (gpu, 913.9 MB)"

	variable CpuMemory {ram_mb 32000 vram_mb 0}
	variable CpuFirst {big q8_0 cpu}
	variable CpuQuant q8_0
	variable CpuPlacements {cpu cpu cpu cpu none}
	variable CpuLine "big: q8_0 (cpu, 9139.2 MB)"

	variable SmallMemory {ram_mb 500 vram_mb 0}
	variable SmallBest {small q3_K_M cpu}
	variable SmallSecondQuant q4_K_M

	variable NoMemory {ram_mb 1 vram_mb 0}
	variable NoneQuants {none none none none none}
	variable NonePlacements {none none none none none}
	variable NoneName huge
	variable NoneSizeMb 0.0
	variable NoneLine "huge: none (none, 0.0 MB)"
}

# Write <lines> into the fixture directory, return the path.
proc ::scidb::test::modelfit::fixture {name lines} {
	variable Dir
	file mkdir $Dir
	set path [file join $Dir $name]
	set chan [open $path w]
	foreach line $lines { puts $chan $line }
	close $chan
	return $path
}

# --- the module (sourced when the app does not ship it yet) -------------

if {[llength [info commands ::ai::modelfit::memory]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl ai-modelfit.tcl]
}

# ----------------------------------------------------------------------

tcltest::test modelfit-meminfo-fixture {MemTotal of the fixture meminfo is the RAM in MiB} -setup {
	set path [::scidb::test::modelfit::fixture meminfo.txt $::scidb::test::modelfit::FixtureMeminfo]
} -body {
	::ai::modelfit::memory -meminfo $path -gpu [list sh -c {exit 0}]
} -cleanup {
	catch { file delete $path }
} -result $::scidb::test::modelfit::FixtureRam

tcltest::test modelfit-meminfo-bad {a bad MemTotal is no memory, not an error} -setup {
	set path [::scidb::test::modelfit::fixture meminfo-bad.txt $::scidb::test::modelfit::BadMeminfo]
} -body {
	::ai::modelfit::memory -meminfo $path -gpu [list sh -c {exit 0}]
} -cleanup {
	catch { file delete $path }
} -result $::scidb::test::modelfit::NoRam

tcltest::test modelfit-meminfo-missing {a missing meminfo file is no memory, not an error} -body {
	::ai::modelfit::memory -meminfo $::scidb::test::modelfit::Missing \
		-gpu [list sh -c {exit 0}]
} -result $::scidb::test::modelfit::NoRam

tcltest::test modelfit-gpu-fails {a failing gpu command is no memory, not an error} -setup {
	set path [::scidb::test::modelfit::fixture meminfo-empty.txt $::scidb::test::modelfit::BadMeminfo]
} -body {
	::ai::modelfit::memory -meminfo $path -gpu [list sh -c {exit 1}]
} -cleanup {
	catch { file delete $path }
} -result $::scidb::test::modelfit::NoRam

tcltest::test modelfit-gpu-sums {the gpu command's whole MiB lines are summed over the cards} -setup {
	set path [::scidb::test::modelfit::fixture meminfo.txt $::scidb::test::modelfit::FixtureMeminfo]
	set gpufx [::scidb::test::modelfit::fixture gpu.csv $::scidb::test::modelfit::GpuFixture]
} -body {
	::ai::modelfit::memory -meminfo $path -gpu [list cat $gpufx]
} -cleanup {
	catch { file delete $path }
	catch { file delete $gpufx }
} -result $::scidb::test::modelfit::GpuRam

tcltest::test modelfit-recommend-gpu-plenty {plenty of video memory: q8_0 on the GPU for every model that fits, best fit first} -body {
	set rows [::ai::modelfit::recommend $::scidb::test::modelfit::GpuMemory $::scidb::test::modelfit::Fixtures]
	list [lmap r $rows {dict get $r name}] [lmap r $rows {dict get $r quant}] \
		[lmap r $rows {dict get $r placement}]
} -result [list $::scidb::test::modelfit::GpuNames \
	$::scidb::test::modelfit::GpuQuants $::scidb::test::modelfit::GpuPlacements]

tcltest::test modelfit-recommend-cpu {no video memory: the fit falls to the system RAM and says so} -body {
	set rows [::ai::modelfit::recommend $::scidb::test::modelfit::CpuMemory $::scidb::test::modelfit::Fixtures]
	list [dict get [lindex $rows 0] name] [dict get [lindex $rows 0] quant] \
		[dict get [lindex $rows 0] placement] [lmap r $rows {dict get $r placement}]
} -result [list {*}$::scidb::test::modelfit::CpuFirst \
	$::scidb::test::modelfit::CpuPlacements]

tcltest::test modelfit-recommend-small-ram {a small RAM pushes the small models to the quants that fit} -body {
	set rows [::ai::modelfit::recommend $::scidb::test::modelfit::SmallMemory \
		[lrange $::scidb::test::modelfit::Fixtures 2 3]]
	lassign $rows first second
	list [dict get $first name] [dict get $first quant] [dict get $first placement] \
		[dict get $second quant]
} -result "$::scidb::test::modelfit::SmallBest $::scidb::test::modelfit::SmallSecondQuant"

tcltest::test modelfit-recommend-none {when nothing fits the quant and placement are none and the size is 0} -body {
	set rows [::ai::modelfit::recommend $::scidb::test::modelfit::NoMemory $::scidb::test::modelfit::Fixtures]
	list \
		[lmap r $rows {dict get $r quant}] \
		[lmap r $rows {dict get $r placement}] \
		[dict get [lindex $rows end] name] [dict get [lindex $rows end] size_mb]
} -result [list $::scidb::test::modelfit::NoneQuants \
	$::scidb::test::modelfit::NonePlacements \
	$::scidb::test::modelfit::NoneName $::scidb::test::modelfit::NoneSizeMb]

tcltest::test modelfit-text {the report block is deterministic and its lines are recorded strings} -body {
	set rows [::ai::modelfit::recommend $::scidb::test::modelfit::GpuMemory \
		[lrange $::scidb::test::modelfit::Fixtures 1 3]]
	set block [::ai::modelfit::text $rows]
	lassign [split $block "\n"] one two
	list \
		[expr {$block eq [::ai::modelfit::text $rows]}] \
		$one $two \
		[string match "*$::scidb::test::modelfit::NoneLine*" \
			[::ai::modelfit::text [::ai::modelfit::recommend \
				$::scidb::test::modelfit::NoMemory \
				[list [lindex $::scidb::test::modelfit::Fixtures 4]]]]]
} -result [list 1 \
	$::scidb::test::modelfit::MidLine $::scidb::test::modelfit::SmallLine 1]

# ----------------------------------------------------------------------

catch { file delete -force $::scidb::test::modelfit::Dir }

::tcltest::cleanupTests
return

