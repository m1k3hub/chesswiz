#!/usr/bin/env tclsh
# Parse assistant Actions from tcl/app-assistant.tcl and tcl/app-assistant-jobs.tcl
# Output: canonical JSON (sorted keys) per tool to stdout

set srcdir [file dirname [file dirname [file dirname [file normalize $argv0]]]]

proc jsonEscape {s} {
    set s [string map [list "\\" "\\\\" "\"" "\\\""] $s]
    set s [string map [list "\n" "\\n" "\t" "\\t" "\r" "\\r"] $s]
    return $s
}

namespace eval ::parse {}

set f [open [file join $srcdir tcl app-assistant.tcl] r]
set content [read $f]
close $f

set idx [string first "variable Actions \{" $content]
if {$idx < 0} { error "Cannot find 'variable Actions' in app-assistant.tcl" }

set braceStart [string first "\{" $content $idx]
set depth 0
set pos $braceStart
set len [string length $content]
while {$pos < $len} {
    set ch [string index $content $pos]
    if {$ch eq "\{"} { incr depth }
    if {$ch eq "\}"} {
        incr depth -1
        if {$depth == 0} break
    }
    incr pos
}
set actionsStmt [string range $content $idx $pos]
namespace eval ::parse $actionsStmt

set f2 [open [file join $srcdir tcl app-assistant-jobs.tcl] r]
set content2 [read $f2]
close $f2

set idx2 [string first "dict set Actions run_job " $content2]
if {$idx2 >= 0} {
    set braceStart2 [string first "\{" $content2 $idx2]
    set depth2 0
    set pos2 $braceStart2
    set len2 [string length $content2]
    while {$pos2 < $len2} {
        set ch2 [string index $content2 $pos2]
        if {$ch2 eq "\{"} { incr depth2 }
        if {$ch2 eq "\}"} {
            incr depth2 -1
            if {$depth2 == 0} break
        }
        incr pos2
    }
    set dictCmd [string range $content2 $idx2 $pos2]
    set dictCmd [string map [list "dict set Actions " "dict set ::parse::Actions "] $dictCmd]
    eval $dictCmd
}

set tools {}
foreach {name val} $::parse::Actions {
    lassign $val confirm debug what description parameters handler
    dict set tools $name [dict create \
        confirm $confirm debug $debug description $description \
        handler $handler name $name params_schema $parameters \
        tool_menu_hint $what]
}

set count [dict size $tools]
set confirmCount 0
set debugCount 0
foreach {name val} $tools {
    if {[dict get $val confirm]} { incr confirmCount }
    if {[dict get $val debug]} { incr debugCount }
}

puts "\["
set names [lsort [dict keys $tools]]
set i 0
set total [llength $names]
foreach name $names {
    set val [dict get $tools $name]
    set confirm [dict get $val confirm]
    set debug [dict get $val debug]
    set desc [jsonEscape [dict get $val description]]
    set handler [jsonEscape [dict get $val handler]]
    set schema [string trimleft [string trimright [dict get $val params_schema]]]
    set hint [jsonEscape [dict get $val tool_menu_hint]]
    set jname [jsonEscape $name]

    set comma ","
    incr i
    if {$i == $total} { set comma "" }

    puts "  \{"
    puts "    \"confirm\": $confirm,"
    puts "    \"debug\": $debug,"
    puts "    \"description\": \"$desc\","
    puts "    \"handler\": \"$handler\","
    puts "    \"name\": \"$jname\","
    puts "    \"params_schema\": $schema,"
    puts "    \"tool_menu_hint\": \"$hint\""
    puts "  \}$comma"
}
puts "\]"

puts stderr "Total tools: $count (confirm: $confirmCount, debug: $debugCount)"
