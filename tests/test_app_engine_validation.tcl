# G29 / laptop run146: exercise the real OK button, with no engine launch.
package require tcltest 2.5

namespace eval ::scidb::test::engineValidation {}

proc ::scidb::test::engineValidation::open {} {
    ::ai::engine::chooseDialog .application
    update idletasks
    return .application.__aiengine__
}

tcltest::test engine-choice-invalid-path {OK keeps invalid executable selections open with an inline error} -setup {
    set savedEngines $::engine::Engines
    set savedChoice $::ai::engine::Options(engine)
    set scratch [file join $::scidb::test::app::testDir tmp-app g29-validation-[pid]]
    file mkdir $scratch
    set plain [file join $scratch plain]
    set f [open $plain w]; puts $f {not an executable}; close $f
    if {$::tcl_platform(platform) eq "unix"} { file attributes $plain -permissions 0644 }
    set ::engine::Engines [list [dict create Name Missing Protocol UCI Command C:/no/such/engine.exe Parameters {}]]
    set ::ai::engine::Options(engine) ""
} -body {
    set results {}
    set invalidValues [list C:/no/such/engine.exe $scratch Missing]
    if {$::tcl_platform(platform) eq "unix"} { lappend invalidValues $plain }
    foreach value $invalidValues {
        set dlg [::scidb::test::engineValidation::open]
        $dlg.top.engine set $value
        $dlg.ok invoke
        update idletasks
        lappend results [expr {[winfo exists $dlg] && [winfo exists $dlg.top.error] &&
            [winfo ismapped $dlg.top.error] && [$dlg.top.error cget -text] ne "" &&
            $::ai::engine::Options(engine) eq ""}]
        catch {destroy $dlg}
    }
    expr {0 ni $results}
} -cleanup {
    catch {destroy .application.__aiengine__}
    set ::engine::Engines $savedEngines
    set ::ai::engine::Options(engine) $savedChoice
    file delete -force $scratch
} -result 1

tcltest::test engine-choice-correction {a valid configured engine can be chosen after an inline error} -setup {
    set savedEngines $::engine::Engines
    set savedChoice $::ai::engine::Options(engine)
    # The running application is an existing native executable, including on Windows.
    set executable [info nameofexecutable]
    set ::engine::Engines [list [dict create Name Valid Protocol UCI Command $executable Parameters {}]]
    set ::ai::engine::Options(engine) ""
} -body {
    set dlg [::scidb::test::engineValidation::open]
    $dlg.top.engine set $executable
    $dlg.ok invoke
    set rejectedPath [expr {[winfo exists $dlg] && [$dlg.top.error cget -text] eq $::engine::mc::ChooseConfigured}]
    $dlg.top.engine set Valid
    $dlg.ok invoke
    list $rejectedPath [winfo exists $dlg] $::ai::engine::Options(engine)
} -cleanup {
    catch {destroy .application.__aiengine__}
    set ::engine::Engines $savedEngines
    set ::ai::engine::Options(engine) $savedChoice
} -result {1 0 Valid}

# The bundled Mac UCI preset omits WinBoard profiles. Re-probing the same
# command must normalize that record, and must store merged profiles under
# the actual array key when an older profile does exist.
tcltest::test engine-reprobe-sparse-profiles {re-probing a sparse UCI preset preserves complete profile fields} -setup {
    set savedEngines $::engine::Engines
    rename ::engine::ProbeEngine ::scidb::test::engineValidation::realProbe
    proc ::engine::ProbeEngine {parent entry protocols} {
        return $::scidb::test::engineValidation::probeResult
    }
    set ::scidb::test::engineValidation::probeResult [dict merge $::engine::EmptyEngine {
        Name Reprobe Command generated-reprobe Protocol UCI
        Profiles:UCI {Default {}}
        Profiles:WB {Default {{Hash spin 16 16 1 64}}}
    }]
} -body {
    set entry $::scidb::test::engineValidation::probeResult
    set ::engine::Engines [list [dict remove $entry Profiles:WB]]
    set added [::engine::ProbeNewEngine .application $entry {UCI}]
    set sparse [lindex $::engine::Engines 0]
    dict set entry Profiles:WB {Legacy {{Hash spin 8 8 1 64}}}
    set ::engine::Engines [list $entry]
    ::engine::ProbeNewEngine .application $entry {UCI}
    set merged [dict get [lindex $::engine::Engines 0] Profiles:WB]
    list $added [dict get $sparse Profiles:WB] [lindex $merged 0] [lindex $merged 1 0 2]
} -cleanup {
    rename ::engine::ProbeEngine {}
    rename ::scidb::test::engineValidation::realProbe ::engine::ProbeEngine
    set ::engine::Engines $savedEngines
} -result {1 {} Default 16}

tcltest::cleanupTests
