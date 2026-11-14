package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
namespace eval ::scidb::test::buildcost {variable prefixes {}}
proc ::scidb::test::buildcost::count {command operation} {
    dict incr ::scidb::test::buildcost::prefixes [lindex $command 1]
}
foreach {cid object expected} {
    C9 {paneUid editor frame .application} {c9.not.display c9.not.font c9.not.move_notation c9.not.move_info c9.not.language c9.layout}
    C11 {base generated index 0 ply 1 widget .buildcosttext} {c11.insert_symbol c11.insert_emoticon c11.format c11.copy_text c11.translate_comment c11.switch_language c11.add_language}
} {
    tcltest::test menu-context-build-once-$cid {a real post constructs each dynamic prefix once; full state still checks children} -body {
        catch {destroy .buildcosttext}; text .buildcosttext
        menu .buildcost -tearoff 0
        set ::scidb::test::buildcost::prefixes {}
        trace add execution ::context::CascadePrefix enter ::scidb::test::buildcost::count
        ::context::Post $cid .buildcost $object 300 200
        update idletasks
        trace remove execution ::context::CascadePrefix enter ::scidb::test::buildcost::count
        if {![winfo ismapped .buildcost]} {error {menu did not post}}
        set counts $::scidb::test::buildcost::prefixes
        foreach id $expected {
            if {![dict exists $counts $id] || [dict get $counts $id] != 1} {error "duplicate or missing prefix: $id $counts"}
        }
        if {$cid eq "C11"} {
            # Empty Copy Text is still disabled outside a build; skipping
            # the duplicate visibility query must not alter Ask/dispatch.
            if {[dict get [::menu::state c11.copy_text $object] enabled]} {error {empty Copy Text enabled}}
            if {![dict get [::menu::state c11.insert_symbol $object] enabled]} {error {symbol menu disabled}}
        }
        list [dict size $counts] [llength $expected]
    } -cleanup {
        catch {trace remove execution ::context::CascadePrefix enter ::scidb::test::buildcost::count}
        catch {grab release .buildcost};catch {destroy .buildcost};catch {destroy .buildcosttext}
    } -result [list [llength $expected] [llength $expected]]
}
tcltest::cleanupTests
