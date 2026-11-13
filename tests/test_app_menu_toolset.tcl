# Compare the effective registry schemas, including generated empty-args tools.
package require tcltest 2.5
package require json
source tests/app_actions_support.tcl
::scidb::test::actions::ready
namespace eval ::scidb::test::toolset {}

# JSON schemas are objects; properties is an object of schemas and items is
# another schema. Sort only object keys, retaining all array/value ordering.
proc ::scidb::test::toolset::Canonical {schema} {
    set result {}
    foreach key [lsort [dict keys $schema]] {
        set value [dict get $schema $key]
        if {$key eq "properties"} {
            set properties {}
            foreach name [lsort [dict keys $value]] {
                dict set properties $name [Canonical [dict get $value $name]]
            }
            set value $properties
        } elseif {$key eq "items"} {
            set value [Canonical $value]
        }
        dict set result $key $value
    }
    return $result
}

tcltest::test menu-toolset-exact-effective-schemas {AI ids, generated tools and frozen approved names agree, with canonical metadata} -setup {
    set savedDebug $::application::assistant::Priv(debug)
    set ::application::assistant::Priv(debug) 1
} -body {
    set f [open tests/fixtures/assistant-tools-baseline.json]
    set baseline [::json::json2dict [read $f]]; close $f
    set expected [lmap record $baseline {dict get $record name}]
    set f [open tests/fixtures/assistant-tools-additions.txt]
    set metadata {}
    foreach line [split [read $f] \n] {
        if {[regexp {^# metadata \{} $line]} {
            lappend metadata [::json::json2dict [string range $line 11 end]]
        }
        if {[string trim $line] ne {} && ![string match #* [string trim $line]]} {
            lappend expected [lindex $line 0]
        }
    }
    close $f
    set generated {}
    foreach tool [::json::json2dict [::application::assistant::toolsJson]] {
        set definition [dict get $tool function]
        set name [dict get $definition name]
        if {[dict exists $generated $name]} {error "duplicate generated tool: $name"}
        dict set generated $name [dict get $definition parameters]
    }
    set exposed {}
    foreach id [::action::list] {
        set r [::action::get $id]
        if {[dict get $r ai] ni {1 debug}} {continue}
        lappend exposed $id
        set schema [dict get $r schema]
        if {$schema eq {}} {set schema [::action::schemaJson [dict get $r args]]}
        # Evidence format consumed by tests/compare_assistant_tools.py.
        puts "CANONICAL|$id|[dict get $r confirm]|[dict get $r ai]|[binary encode base64 -maxlen 0 [encoding convertto utf-8 $schema]]|[binary encode base64 -maxlen 0 [encoding convertto utf-8 [dict get $r toolmenu]]]"
        if {![dict exists $generated $id] || [::scidb::test::toolset::Canonical [dict get $generated $id]] ne [::scidb::test::toolset::Canonical [::action::schemaOf $id]]} {
            error "generated schema differs from effective registry schema: $id"
        }
    }
    if {[lsort $expected] ne [lsort $exposed] || [lsort $exposed] ne [lsort [dict keys $generated]]} {
        error [list toolset-mismatch expected [lsort $expected] exposed [lsort $exposed] generated [lsort [dict keys $generated]]]
    }
    set bad {}
    foreach frozen [concat $baseline $metadata] {
        set id [dict get $frozen name]
        set r [::action::get $id]
        set schema [dict get $frozen params_schema]
        if {$frozen in $metadata} {set schema [::json::json2dict $schema]}
        if {[::scidb::test::toolset::Canonical $schema] ne [::scidb::test::toolset::Canonical [::action::schemaOf $id]]
            || [dict get $r confirm] != [dict get $frozen confirm]
            || ([dict get $r ai] eq "debug") != [dict get $frozen debug]
            || ([dict exists $frozen tool_menu_hint] && [dict get $r toolmenu] ne [dict get $frozen tool_menu_hint])} {
            lappend bad $id
        }
    }
    puts [list EXACT_TOOLSET baseline [llength $baseline] approved [llength $expected] exposed [llength $exposed] generated [dict size $generated] mismatches $bad]
    set bad
} -cleanup {
    set ::application::assistant::Priv(debug) $savedDebug
} -result {}
::tcltest::cleanupTests
