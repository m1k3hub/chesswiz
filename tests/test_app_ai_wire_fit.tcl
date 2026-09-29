# ======================================================================
# Scidb App Test — the model-fit wire in the chooser (tcl/app-ai-models.tcl,
# audit row E2): the parameter size read from an /api/tags entry, and the
# Fit column's advice (quant + placement per local model with a known
# size) built from ::ai::modelfit.  The advice never changes the choice;
# without the rules module the column is not built at all.
# ======================================================================
# Modelled on tests/test_app_ai_models.tcl.  The pure procs are called
# directly, so no dialog is opened and no server is asked anything:
# ::ai::modelfit::memory is stubbed here with a fixture memory and
# renamed back after the test, and the real ::ai::modelfit::recommend
# does the arithmetic.  The module is sourced when the app does not ship
# it yet.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::wirefit {}

# --- the /api/tags rows and the sizes they must yield --------------------

# "8.0B" comes from details.parameter_size; the rest from the name tag;
# a cloud model, a name with no size tag and a nonsense size read as 0.
proc ::scidb::test::wirefit::Models {} {
	return [list \
		[dict create name "qwen3:8b" remote 0 tools 1 size 1 \
			details [dict create parameter_size "8.0B"]] \
		[dict create name "gemma3:1.5b" remote 0 tools 0 size 1] \
		[dict create name "tiny:300m" remote 0 tools 0 size 1] \
		[dict create name "llama3" remote 0 tools 1 size 1] \
		[dict create name "glm-5.3:cloud" remote 1 tools 1 size 1 \
			details [dict create parameter_size "355B"]]]
}

# The fixture machine: 32000 MiB RAM, no video memory -- the fit falls to
# the CPU.  The recorded advice is in the fit dicts below.
set ::scidb::test::wirefit::Memory {ram_mb 32000 vram_mb 0}
set ::scidb::test::wirefit::BigFit "q8_0 (cpu)"
set ::scidb::test::wirefit::SmallFit "q8_0 (cpu)"

# --- the module (sourced when the app does not ship it yet) -------------

if {[llength [info commands ::application::ai::models::ParamsB]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl app-ai-models.tcl]
}

# ----------------------------------------------------------------------

tcltest::test wirefit-params-details {details.parameter_size is read as billions} -body {
	list [::application::ai::models::ParamsB [lindex [::scidb::test::wirefit::Models] 0]] \
		[::application::ai::models::ParamsB [lindex [::scidb::test::wirefit::Models] 4]]
} -result {8.0 355.0}

tcltest::test wirefit-params-name {a size tag in the name is read when there are no details} -body {
	list [::application::ai::models::ParamsB [lindex [::scidb::test::wirefit::Models] 1]] \
		[::application::ai::models::ParamsB [lindex [::scidb::test::wirefit::Models] 2]]
} -result {1.5 0.3}

tcltest::test wirefit-params-none {a name with no size tag reads as no size, not an error} -body {
	::application::ai::models::ParamsB [lindex [::scidb::test::wirefit::Models] 3]
} -result 0.0

tcltest::test wirefit-advice {the advice names the quant and placement for each sized local model} -setup {
	rename ::ai::modelfit::memory ::scidb::test::wirefit::realMemory
	proc ::ai::modelfit::memory {args} { return $::scidb::test::wirefit::Memory }
} -body {
	set advice [::application::ai::models::FitAdvice [::scidb::test::wirefit::Models]]
	list [dict get $advice "qwen3:8b"] [dict get $advice "gemma3:1.5b"] \
		[dict exists $advice "llama3"] [dict exists $advice "glm-5.3:cloud"]
} -cleanup {
	rename ::ai::modelfit::memory {}
	rename ::scidb::test::wirefit::realMemory ::ai::modelfit::memory
} -result [list $::scidb::test::wirefit::BigFit $::scidb::test::wirefit::SmallFit 0 0]

tcltest::test wirefit-degrade {without the rules module the advice is empty} -setup {
	rename ::ai::modelfit::memory ::scidb::test::wirefit::realMemory
	rename ::ai::modelfit::recommend ::scidb::test::wirefit::realRecommend
} -body {
	::application::ai::models::FitAdvice [::scidb::test::wirefit::Models]
} -cleanup {
	rename ::scidb::test::wirefit::realMemory ::ai::modelfit::memory
	rename ::scidb::test::wirefit::realRecommend ::ai::modelfit::recommend
} -result {}

# ----------------------------------------------------------------------

::tcltest::cleanupTests
return
