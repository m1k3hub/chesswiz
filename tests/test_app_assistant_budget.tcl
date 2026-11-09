# ======================================================================
# Scidb App Test — assistant request budget (BudgetMessages; review
# finding AI-05): long conversations send a bounded history.
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::budget {}

proc ::scidb::test::budget::Turn {n {toolSize 10}} {
	list \
		[dict create role user content "question $n"] \
		[dict create role assistant content "" tool_calls [list [dict create id c$n]]] \
		[dict create role tool content [string repeat x $toolSize] tool_name search] \
		[dict create role assistant content "answer $n"]
}

proc ::scidb::test::budget::Roles {messages} {
	lmap m $messages { dict get $m role }
}

tcltest::test assistant-budget-short {a short conversation is sent unchanged} -body {
	set msgs [concat [list [dict create role system content sys]] \
		[::scidb::test::budget::Turn 1] [::scidb::test::budget::Turn 2]]
	expr {[::application::assistant::BudgetMessages $msgs] eq $msgs}
} -result 1

tcltest::test assistant-budget-long {old turns drop out, the system prompt and current turn stay} -setup {
	set saved $::application::assistant::HistoryBudget
	set ::application::assistant::HistoryBudget 20000
} -body {
	set msgs [list [dict create role system content sys]]
	for {set i 1} {$i <= 50} {incr i} {
		lappend msgs {*}[::scidb::test::budget::Turn $i 1500]
	}
	lappend msgs [dict create role user content "current question"]
	set sent [::application::assistant::BudgetMessages $msgs]
	set size 0
	foreach m $sent { incr size [string length [dict get $m content]] }
	set users [lmap m $sent { expr {[dict get $m role] eq "user" ? [dict get $m content] : [continue]} }]
	list [dict get [lindex $sent 0] content] [dict get [lindex $sent end] content] \
		[expr {$size <= 20000}] [expr {[llength $sent] < [llength $msgs]}] \
		[lindex $users end-1] [expr {"question 1" ni $users}] \
		[expr {[lindex [::scidb::test::budget::Roles $sent] 1] eq "user"}]
} -cleanup {
	set ::application::assistant::HistoryBudget $saved
} -result {sys {current question} 1 1 {question 50} 1 1}

tcltest::test assistant-budget-tool-pairs {every tool reply is still preceded by its tool call} -setup {
	set saved $::application::assistant::HistoryBudget
	set ::application::assistant::HistoryBudget 5000
} -body {
	set msgs [list [dict create role system content sys]]
	for {set i 1} {$i <= 20} {incr i} { lappend msgs {*}[::scidb::test::budget::Turn $i 900] }
	set sent [::application::assistant::BudgetMessages $msgs]
	set ok 1
	set prev {}
	foreach m $sent {
		if {[dict get $m role] eq "tool" && !([dict get $prev role] in {assistant tool})} { set ok 0 }
		set prev $m
	}
	set ok
} -cleanup {
	set ::application::assistant::HistoryBudget $saved
} -result 1

tcltest::test assistant-budget-old-tool-replies {tool replies of earlier turns are shortened, the current one is not} -body {
	set msgs [concat [list [dict create role system content sys]] \
		[::scidb::test::budget::Turn 1 5000] [::scidb::test::budget::Turn 2 5000]]
	set sent [::application::assistant::BudgetMessages $msgs]
	set tools [lmap m $sent { expr {[dict get $m role] eq "tool" ? [string length [dict get $m content]] : [continue]} }]
	list [expr {[lindex $tools 0] < 2100}] [lindex $tools 1]
} -result {1 5000}

tcltest::cleanupTests
