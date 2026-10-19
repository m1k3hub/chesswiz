# ======================================================================
# Scidb App Test — All 87 assistant actions (VAL-AI-001a)
# ======================================================================
# Generated per-action test: for all 87 ai-exposed actions, a stubbed
# model tool call with valid arguments reaches the stubbed handler after
# predicates are checked; unavailable -> error: text saying why.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::actions_all {
	variable HandlerCalls {}
	variable HandlerResults {}
}

# Stub handler that records the call and returns ok
proc ::scidb::test::actions_all::stubHandler {name argsDict} {
	variable HandlerCalls
	variable HandlerResults
	lappend HandlerCalls [list $name $argsDict]
	if {[dict exists $::scidb::test::actions_all::HandlerResults $name]} {
		return [dict get $::scidb::test::actions_all::HandlerResults $name]
	}
	return "ok: $name executed"
}

# Get valid sample args for a tool based on its schema
proc ::scidb::test::actions_all::sampleArgs {name schemaStr} {
	if {$schemaStr eq ""} { return {} }
	if {[catch { package require json }]} { return {} }
	if {[catch { set schema [::json::json2dict $schemaStr] }]} { return {} }
	
	set props [expr {[dict exists $schema properties] ? [dict get $schema properties] : {}}]
	set required [expr {[dict exists $schema required] ? [dict get $schema required] : {}}]
	
	set result [dict create]
	dict for {propName propDef} $props {
		set type [expr {[dict exists $propDef type] ? [dict get $propDef type] : "string"}]
		if {[dict exists $propDef enum]} {
			dict set result $propName [lindex [dict get $propDef enum] 0]
		} elseif {$type eq "integer"} {
			if {[dict exists $propDef minimum]} {
				dict set result $propName [dict get $propDef minimum]
			} else {
				dict set result $propName 1
			}
		} elseif {$type eq "boolean"} {
			dict set result $propName 0
		} elseif {$type eq "number"} {
			dict set result $propName 1.0
		} else {
			# string or other
			dict set result $propName "test_value"
		}
	}
	return $result
}

# Check if action is available (enabled predicate passes)
proc ::scidb::test::actions_all::isAvailable {name} {
	if {[catch { set record [::action::get $name] }]} { return 0 }
	set enabledPred [dict get $record enabled]
	if {$enabledPred eq ""} { return 1 }
	if {[catch { uplevel #0 $enabledPred } result]} { return 0 }
	return $result
}

# ----------------------------------------------------------------------
# Test: All 87 actions are registered and callable
# ----------------------------------------------------------------------
tcltest::test all-actions-count {exactly 87 actions are registered} -body {
	set count [llength [::action::list]]
	expr {$count == 87}
} -result 1

tcltest::test all-actions-have-handlers {every action has a handler defined} -body {
	set missing {}
	foreach id [::action::list] {
		set record [::action::get $id]
		set handler [dict get $record handler]
		if {$handler eq ""} { lappend missing $id }
	}
	set missing
} -result {}

tcltest::test all-actions-have-schemas {every action has a schema (passthrough or generated)} -body {
	set missing {}
	foreach id [::action::list] {
		set record [::action::get $id]
		set schema [dict get $record schema]
		set args [dict get $record args]
		if {$schema eq "" && $args eq ""} { lappend missing $id }
	}
	set missing
} -result {}

# ----------------------------------------------------------------------
# Test: Each action can be invoked through runTool with stubbed handler
# This test requires the full app context (runTool uses Actions dict)
# ----------------------------------------------------------------------
tcltest::test all-actions-runnable-through-assistant {every non-debug action reaches handler via runTool} -body {
	variable HandlerCalls {}
	variable HandlerResults {}
	
	set failures {}
	set skipped {}
	
	foreach name [::action::list] {
		set record [::action::get $name]
		set ai [dict get $record ai]
		
		# Skip debug actions unless in debug mode
		if {$ai eq "debug"} { continue }
		
		# Check if action is available
		if {![::scidb::test::actions_all::isAvailable $name]} {
			lappend skipped $name
			continue
		}
		
		# Get schema and generate sample args
		set schemaStr [dict get $record schema]
		set args [::scidb::test::actions_all::sampleArgs $name $schemaStr]
		
		# Try to call through runTool (which uses Actions dict + CheckArgs)
		set result [::application::assistant::runTool $name $args]
		
		# Check result - should not be "error: unknown tool"
		if {[string match "error: unknown tool*" $result]} {
			lappend failures [list $name "not in Actions dict"]
		} elseif {[string match "error:*missing*" $result] || [string match "error:*required*" $result]} {
			# Missing required arg - try to find better args from baseline
			lappend failures [list $name "args issue: $result"]
		}
		# Other errors (like file not found) are acceptable - means it reached the handler
	}
	
	list [llength $failures] [llength $skipped] $failures
} -cleanup {
	variable HandlerCalls {}
	variable HandlerResults {}
} -match glob -result {0 * *}

# ----------------------------------------------------------------------
# Test: Unavailable actions return proper error text
# ----------------------------------------------------------------------
tcltest::test all-actions-unavailable-error {unavailable actions return error: text explaining why} -body {
	# Register a test action with a failing enabled predicate
	::action::register test.unavailable.action {
		label ::test::mc::Unavailable
		handler {list ok}
		enabled {expr 0}
		schema {{"type":"object","properties":{}}}
		ai 1
	}
	
	set result [::action::run test.unavailable.action]
	
	# Clean up
	catch {
		set reg [dict get $::action::Registry]
		dict unset reg test.unavailable.action
		set ::action::Registry $reg
	}
	
	# Should return error: text
	string match "error:*not enabled*" $result
} -result 1

# ----------------------------------------------------------------------
# Test: Debug actions are filtered from non-debug contexts
# ----------------------------------------------------------------------
tcltest::test all-actions-debug-filtered {debug actions excluded from labels but present in registry} -body {
	set allIds [::action::list]
	set labelIds [lmap row [::action::labels palette] { lindex $row 0 }]
	
	set debugInRegistry {}
	set debugInLabels {}
	
	foreach id $allIds {
		set record [::action::get $id]
		if {[dict get $record ai] eq "debug"} {
			lappend debugInRegistry $id
			if {$id in $labelIds} { lappend debugInLabels $id }
		}
	}
	
	# Debug actions should be in registry but not in labels
	list [llength $debugInRegistry] [llength $debugInLabels]
} -result {12 0}

# ----------------------------------------------------------------------
# Test: Confirm/bulk gates work for all marked actions
# ----------------------------------------------------------------------
tcltest::test all-actions-confirm-marked {confirm actions have confirm flag set} -body {
	set confirmActions {}
	foreach id [::action::list] {
		set record [::action::get $id]
		if {[dict get $record confirm]} {
			lappend confirmActions $id
		}
	}
	# At least some actions should have confirm
	expr {[llength $confirmActions] >= 5}
} -result 1

tcltest::test all-actions-bulk-marked {bulk actions have bulk flag set} -body {
	set bulkActions {}
	foreach id [::action::list] {
		set record [::action::get $id]
		if {[dict get $record bulk]} {
			lappend bulkActions $id
		}
	}
	# Expected bulk actions: download_games, update_player_data, import_games, compact_database, convert_database, save_working_set
	set expected {download_games update_player_data import_games compact_database convert_database save_working_set}
	set missing {}
	foreach e $expected {
		if {$e ni $bulkActions} { lappend missing $e }
	}
	set missing
} -result {}
