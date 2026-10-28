# ======================================================================
# Scidb App Test — All 93 assistant actions (VAL-AI-001a)
# The later unsupported report-print alias was removed with its dead leaf;
# the frozen baseline tools remain unchanged.
# ======================================================================
# Generated per-action test: for all 93 ai-exposed actions, a stubbed
# model tool call with valid arguments reaches the stubbed handler after
# predicates are checked; unavailable -> error: text saying why.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::actions_all {
	variable HandlerCalls {}
}

source [file join [file dirname [info script]] app_actions_support.tcl]

# Replace the actual Do* command, so both the assistant and the registry's
# adapter still run their real validation/gates before reaching the stub.
proc ::scidb::test::actions_all::stubHandler {name args} {
    variable HandlerCalls
    lappend HandlerCalls [list $name $args]
    return "reached:$name"
}

proc ::scidb::test::actions_all::reach {name} {
    variable HandlerCalls {}
    set savedLog $::application::assistant::ErrorLogFile
    set ::application::assistant::ErrorLogFile [file join $::scidb::test::actions::Dir errors.log]
    set args [::scidb::test::actions::sampleArgs $name]
    set command [lindex [dict get $::application::assistant::Actions $name] 5]
    if {[llength $command] != 1} { error "unsupported handler prefix: $command" }
    set savedDebug $::application::assistant::Priv(debug)
    set ::application::assistant::Priv(debug) 0
    set savedConfirm $::application::assistant::Priv(confirm)
    set savedReqConfirm $::application::assistant::Priv(reqconfirm)
    set savedHooks [list $::action::ConfirmHook $::action::BulkHook]
    set ::application::assistant::Priv(confirm) ::scidb::test::actions::yes
    set ::application::assistant::Priv(reqconfirm) {}
    set ::action::ConfirmHook ::scidb::test::actions::yes
    set ::action::BulkHook ::scidb::test::actions::yes
    rename $command ${command}__reach_original
    interp alias {} $command {} ::scidb::test::actions_all::stubHandler $name
    set code [catch {
        set reply [::application::assistant::runTool $name $args]
        set debug [expr {[dict get [::action::get $name] ai] eq "debug"}]
        if {$debug} {
            if {![string match "error:*only available in debug mode*" $reply]
                || [llength $HandlerCalls]} { error "$name: $reply; calls=$HandlerCalls" }
        } elseif {$name eq "stop_engine"} {
            # Fresh process has no running engine. This is an asserted gate,
            # not a skip or an arbitrary error accepted as handler reachability.
            if {$reply ne "error: no engine is running" || [llength $HandlerCalls]} {
                error "$name: $reply; calls=$HandlerCalls"
            }
        } else {
            set checked [::application::assistant::CheckArgs $name $args]
            set expected [list $name [dict values $checked]]
            if {$HandlerCalls ne [list $expected] || ![string match "reached:$name*" $reply]} {
                error "$name: $reply; calls=$HandlerCalls; expected=$expected"
            }
            set registryReply [::action::run $name $args]
            if {$registryReply ne "reached:$name" || $HandlerCalls ne [list $expected $expected]} {
                error "$name registry: $registryReply; calls=$HandlerCalls"
            }
        }
        set result 1
    } result options]
    rename $command {}
    rename ${command}__reach_original $command
    set ::application::assistant::ErrorLogFile $savedLog
    set ::application::assistant::Priv(debug) $savedDebug
    set ::application::assistant::Priv(confirm) $savedConfirm
    set ::application::assistant::Priv(reqconfirm) $savedReqConfirm
    lassign $savedHooks ::action::ConfirmHook ::action::BulkHook
    return -options $options $result
}

# ----------------------------------------------------------------------
# Test: All 93 actions are registered and callable
# ----------------------------------------------------------------------
tcltest::test all-actions-count {exactly 93 assistant actions are registered} -body {
	set count [llength [dict keys $::application::assistant::Actions]]
	expr {$count == 93}
} -result 1

tcltest::test all-actions-have-handlers {every action has a handler defined} -body {
	set missing {}
	foreach id [dict keys $::application::assistant::Actions] {
		set record [::action::get $id]
		set handler [dict get $record handler]
		if {$handler eq ""} { lappend missing $id }
	}
	set missing
} -result {}

tcltest::test all-actions-have-schemas {every action has a schema (passthrough or generated)} -body {
	set missing {}
	foreach id [dict keys $::application::assistant::Actions] {
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
tcltest::test all-actions-runnable-through-assistant {every action reaches its handler or its explicit state/debug gate} -setup {
    ::scidb::test::actions::ready
    set savedEngines $::engine::Engines
    ::scidb::test::actions::stubEngine
} -body {
    set count 0
    foreach name [dict keys $::application::assistant::Actions] {
        incr count [::scidb::test::actions_all::reach $name]
    }
    set count
} -cleanup {
    set ::engine::Engines $savedEngines
    file delete -force $::scidb::test::actions::Dir
} -result 93

# Individually selectable legs for timeout 30 process isolation.
foreach name [dict keys $::application::assistant::Actions] {
    tcltest::test action-handler-$name {assistant and registry dispatch retain real gates} -setup {
        ::scidb::test::actions::ready
        set savedEngines $::engine::Engines
        ::scidb::test::actions::stubEngine
    } -body [list ::scidb::test::actions_all::reach $name] -cleanup {
        set ::engine::Engines $savedEngines
        file delete -force $::scidb::test::actions::Dir
    } -result 1
}

tcltest::test all-actions-confirm-without-pane {confirmation has a live parent before the assistant pane is built} -setup {
    ::scidb::test::actions::ready
    set savedWindow $::application::assistant::Priv(window)
    set ::application::assistant::Priv(window) {}
    rename ::dialog::question ::scidb::test::actions_all::originalQuestion
    proc ::dialog::question {args} {
        set ::scidb::test::actions_all::questionParent [dict get $args -parent]
        return yes
    }
} -body {
    list [::application::assistant::ConfirmDialog {generated test action}] \
        $::scidb::test::actions_all::questionParent
} -cleanup {
    rename ::dialog::question {}
    rename ::scidb::test::actions_all::originalQuestion ::dialog::question
    set ::application::assistant::Priv(window) $savedWindow
    unset -nocomplain ::scidb::test::actions_all::questionParent
} -result {1 .application}

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

		what {}
		object {}
		doc {}
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
	set allIds [dict keys $::application::assistant::Actions]
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
	foreach id [dict keys $::application::assistant::Actions] {
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
	foreach id [dict keys $::application::assistant::Actions] {
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

file delete -force $::scidb::test::actions::Dir
::tcltest::cleanupTests
