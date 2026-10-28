# Read-only handler entry observations for public evaluation runs. The caller
# owns the output directory; this never changes dispatch or scoring.
namespace eval ::EvalObserve {variable Events {}}
proc ::EvalObserve::Record {kind name command} {
    if {![info exists ::EvalHarness::Active] || !$::EvalHarness::Active} return
    set ns [expr {[namespace exists ::BoundsEval] ? "::BoundsEval" : "::RequestEval"}]
    if {![info exists ${ns}::Item]} return
    set row [::list item [set ${ns}::Item] attempt $::EvalHarness::Attempt kind $kind name $name command $command]
    lappend ::EvalObserve::Events $row
    set f [open [file join $::env(SCIDB_EVAL_WORK) handler-trace.tcllist] a]
    puts $f $row
    close $f
}
proc ::EvalObserve::DispatchStep {command op} {
    if {[lindex $command 0] ne "uplevel" || [llength $command] != 3} return
    # Evaluated in ::action: an unqualified list would call ::action::list.
    if {[catch {uplevel 1 {::list $id $handler $validatedArgs}} locals]} return
    lassign $locals id handler arguments
    if {[lindex $command 2] eq [::list {*}$handler $arguments]} {
        Record registry-handler $id $command
    }
}
proc ::EvalObserve::LegacyStep {command op} {
    if {[catch {uplevel 1 {::list $name $handler $checked}} locals]} return
    lassign $locals name handler checked
    if {$command eq [::list {*}$handler {*}[dict values $checked]]} {
        Record assistant-handler $name $command
    }
}
trace add execution ::action::Dispatch enterstep ::EvalObserve::DispatchStep
if {[llength [info commands ::application::assistant::RealRunTool]]} {
    trace add execution ::application::assistant::RealRunTool enterstep ::EvalObserve::LegacyStep
}

proc ::EvalObserve::ToolEnter {command op} {
    Record full-tool-result [lindex $command 1] [lrange $command 1 end]
}
trace add execution ::application::assistant::ToolReply enter ::EvalObserve::ToolEnter
