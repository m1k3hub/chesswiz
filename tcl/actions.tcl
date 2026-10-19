# ======================================================================
# ::action -- unified action registry for menus, context menus, palettes
# and the AI assistant.
#
# Every user-facing operation is registered once with its metadata;
# menus, toolbars, the key editor, the palette and the assistant all
# read from this single source. The registry generates the JSON schema
# sent to the model from the Tcl args spec, runs one shared validator,
# and resolves context objects so handlers never depend on widget paths.
#
#   ::action::register <id> <record>
#   ::action::run <id> ?args?
#   ::action::list
#   ::action::get <id>
#   ::action::labels <surface>
#   ::action::invoke <id> ?args?
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source actions
}

package require Tcl 8.5

namespace eval ::action {
	variable Registry [dict create]
	variable ObjectResolvers [dict create]
	variable ConfirmHook {}
	variable BulkHook {}

	namespace export register run list get labels invoke
}

namespace eval ::action::resolver {}

proc ::action::_dg {d key def} {
	if {[dict exists $d $key]} { return [dict get $d $key] }
	return $def
}

# ----------------------------------------------------------------------
# register: store an action record after validation.
# Record fields (all optional except label):
#   label      mc variable name (required)
#   object     app|board|game|move|db|player|engine-line|media|pane|...
#   args       Tcl-native args spec -> JSON schema generated
#   schema     pre-built JSON schema string (passthrough, no generation)
#   handler    command prefix (validated args dict appended)
#   enabled    predicate command (returns 1/0)
#   visible    predicate command (returns 1/0)
#   keys       {chesswiz {} chessbase Control-n}
#   confirm    0|1
#   bulk       0|1
#   what       format string for confirmation prompt
#   ai         1|0|debug
#   menu       {Game 10}  (menu path hint)
#   context    {C12}      (context menu id)
#   toolmenu   "..."      (assistant reply menu hint)
#   doc        description text
#   async      0|1
#   maxreply   int
#   ends-in-dialog  0|1
# ----------------------------------------------------------------------
proc ::action::register {id record} {
	variable Registry

	if {$id eq ""} {
		return -code error "error: action id cannot be empty"
	}
	if {[dict exists $Registry $id]} {
		return -code error "error: duplicate action id '$id'"
	}
	if {![dict exists $record label]} {
		return -code error "error: action '$id' missing required field 'label'"
	}

	set normalized [dict create \
		label    [dict get $record label] \
		object   [_dg $record object {}] \
		args     [_dg $record args {}] \
		schema   [_dg $record schema {}] \
		handler  [_dg $record handler {}] \
		enabled  [_dg $record enabled {}] \
		visible  [_dg $record visible {}] \
		keys     [_dg $record keys {}] \
		confirm  [expr {[_dg $record confirm 0] ? 1 : 0}] \
		bulk     [expr {[_dg $record bulk 0] ? 1 : 0}] \
		what     [_dg $record what {}] \
		ai       [_dg $record ai 0] \
		menu     [_dg $record menu {}] \
		context  [_dg $record context {}] \
		toolmenu [_dg $record toolmenu {}] \
		doc      [_dg $record doc {}] \
		async    [expr {[_dg $record async 0] ? 1 : 0}] \
		maxreply [_dg $record maxreply 6000] \
		ends-in-dialog [expr {[_dg $record ends-in-dialog 0] ? 1 : 0}] \
	]

	dict set Registry $id $normalized
	return $id
}

# ----------------------------------------------------------------------
# get: retrieve a single action record.
# ----------------------------------------------------------------------
proc ::action::get {id} {
	variable Registry
	if {![dict exists $Registry $id]} {
		return -code error "error: unknown action id '$id'"
	}
	return [dict get $Registry $id]
}

# ----------------------------------------------------------------------
# list: return all registered action ids.
# ----------------------------------------------------------------------
proc ::action::list {} {
	variable Registry
	return [dict keys $Registry]
}

# ----------------------------------------------------------------------
# schemaOf: return the effective JSON schema for an action.
# Uses passthrough 'schema' field if present, else generates from 'args'.
# Returns a dict (not a string) for programmatic use.
# ----------------------------------------------------------------------
proc ::action::schemaOf {id} {
	variable Registry
	if {![dict exists $Registry $id]} {
		return -code error "error: unknown action id '$id'"
	}
	set record [dict get $Registry $id]
	set passthrough [dict get $record schema]
	if {$passthrough ne ""} {
		if {[catch { package require json }]} {
			return $passthrough
		}
		if {![catch { ::json::json2dict $passthrough } parsed]} {
			return $parsed
		}
		return $passthrough
	}
	set spec [dict get $record args]
	return [argsToSchema $spec]
}

# ----------------------------------------------------------------------
# Args spec -> JSON schema generator.
# Spec format: {name {type <type> ?default <val>? ?enum <list>? ?range {min max}?}}
# Types: string, integer, number, boolean, enum
# ----------------------------------------------------------------------
proc ::action::argsToSchema {spec} {
	if {$spec eq ""} {
		return [dict create type object properties [dict create]]
	}

	set properties [dict create]
	set required [::list]

	foreach param $spec {
		set name [lindex $param 0]
		set opts [lindex $param 1]

		set type [_dg $opts type string]
		set defaultVal [_dg $opts default {}]
		set hasDefault [dict exists $opts default]
		set enumVals [_dg $opts enum {}]
		set rangeVals [_dg $opts range {}]

		if {[llength $enumVals]} {
			set type enum
		}

		if {[dict exists $opts required]} {
			lappend required $name
		}

		set prop [dict create]
		if {$type eq "enum" && [llength $enumVals]} {
			dict set prop type string
			dict set prop enum $enumVals
		} elseif {$type eq "integer" || $type eq "number"} {
			dict set prop type $type
			if {[llength $rangeVals] == 2} {
				dict set prop minimum [lindex $rangeVals 0]
				dict set prop maximum [lindex $rangeVals 1]
			}
		} elseif {$type eq "boolean"} {
			dict set prop type boolean
		} else {
			dict set prop type string
		}

		if {$hasDefault} {
			dict set prop default $defaultVal
		}

		dict set properties $name $prop

		if {!$hasDefault && ![lsearch -exact $required $name]} {
			lappend required $name
		}
	}

	set schema [dict create type object properties $properties]
	if {[llength $required]} {
		dict set schema required $required
	}
	return $schema
}

# ----------------------------------------------------------------------
# Shared argument validator.
# Returns {ok validatedDict} or {error message}.
# Never raises; bad args return an error text to the assistant.
# ----------------------------------------------------------------------
proc ::action::validateArgs {id argsDict} {
	variable Registry

	if {![dict exists $Registry $id]} {
		return [::list error "unknown action id '$id'"]
	}

	set record [dict get $Registry $id]
	set spec [dict get $record args]

	if {$spec eq ""} {
		if {[dict size $argsDict] > 0} {
			return [::list error "action '$id' takes no arguments"]
		}
		return [::list ok [dict create]]
	}

	set validated [dict create]

	foreach param $spec {
		set name [lindex $param 0]
		set opts [lindex $param 1]

		set type [_dg $opts type string]
		set defaultVal [_dg $opts default {}]
		set hasDefault [dict exists $opts default]
		set isRequired [expr {!$hasDefault}]
		set enumVals [_dg $opts enum {}]
		set rangeVals [_dg $opts range {}]

		if {[llength $enumVals]} {
			set type enum
		}

		if {[dict exists $argsDict $name]} {
			set value [dict get $argsDict $name]
		} elseif {$hasDefault} {
			set value $defaultVal
		} elseif {$isRequired} {
			return [::list error "missing required argument '$name' for action '$id'"]
		} else {
			continue
		}

		if {$type eq "enum" && [llength $enumVals]} {
			if {[lsearch -exact $enumVals $value] < 0} {
				return [::list error "argument '$name' must be one of: [join $enumVals {, }]"]
			}
		} elseif {$type eq "integer"} {
			if {![string is integer -strict $value]} {
				return [::list error "argument '$name' must be an integer"]
			}
			if {[llength $rangeVals] == 2} {
				set min [lindex $rangeVals 0]
				set max [lindex $rangeVals 1]
				if {$value < $min || $value > $max} {
					return [::list error "argument '$name' must be between $min and $max"]
				}
			}
		} elseif {$type eq "number"} {
			if {![string is double -strict $value]} {
				return [::list error "argument '$name' must be a number"]
			}
			if {[llength $rangeVals] == 2} {
				set min [lindex $rangeVals 0]
				set max [lindex $rangeVals 1]
				if {$value < $min || $value > $max} {
					return [::list error "argument '$name' must be between $min and $max"]
				}
			}
		} elseif {$type eq "boolean"} {
			if {$value ni {0 1 true false yes no}} {
				return [::list error "argument '$name' must be a boolean"]
			}
			if {$value in {true yes 1}} {
				set value 1
			} else {
				set value 0
			}
		}

		dict set validated $name $value
	}

	return [::list ok $validated]
}

# ----------------------------------------------------------------------
# Object resolvers for context actions.
# Register resolvers per object type; they return a typed reference
# without depending on widget paths.
# ----------------------------------------------------------------------
proc ::action::resolver::register {objectType command} {
	variable ::action::ObjectResolvers
	dict set ::action::ObjectResolvers $objectType $command
	return
}

proc ::action::resolver::resolve {objectType} {
	variable ::action::ObjectResolvers
	if {![dict exists $::action::ObjectResolvers $objectType]} {
		return -code error "no resolver for object type '$objectType'"
	}
	return [uplevel #0 [dict get $::action::ObjectResolvers $objectType]]
}

# ----------------------------------------------------------------------
# run: validate args and call the handler.
# Returns the handler result or an error: text (never raises).
# Enforces confirm and bulk gates when hooks are configured.
# ----------------------------------------------------------------------
proc ::action::run {id args} {
	variable Registry
	variable ConfirmHook
	variable BulkHook

	if {![dict exists $Registry $id]} {
		return "error: unknown action id '$id'"
	}

	set record [dict get $Registry $id]
	set handler [dict get $record handler]

	if {$handler eq ""} {
		return "error: action '$id' has no handler"
	}

	set argsDict {}
	if {[llength $args] == 1 && [string match "{*}" [lindex $args 0]]} {
		set argsDict [lindex $args 0]
	} elseif {[llength $args] > 0} {
		set argsDict [lindex $args 0]
	}

	set passthrough [dict get $record schema]
	if {$passthrough ne ""} {
		set validatedArgs $argsDict
	} else {
		set validation [::action::validateArgs $id $argsDict]
		set status [lindex $validation 0]
		if {$status eq "error"} {
			return "error: [lindex $validation 1]"
		}
		set validatedArgs [lindex $validation 1]
	}

	set enabledPred [dict get $record enabled]
	if {$enabledPred ne ""} {
		set isEnabled [catch {uplevel #0 $enabledPred} result]
		if {$isEnabled || !$result} {
			return "error: action '$id' is not enabled"
		}
	}

	set isConfirm [dict get $record confirm]
	set isBulk [dict get $record bulk]
	set what [dict get $record what]

	if {$isConfirm || $isBulk} {
		if {$what eq ""} {
			set what "perform action '$id'"
		} else {
			if {[catch { set what [format $what {*}[dict values $validatedArgs]] }]} {
				set what "perform action '$id'"
			}
		}
		if {$isBulk && $BulkHook ne ""} {
			if {[catch { uplevel #0 [::list $BulkHook $what] } answer]} {
				set answer 0
			}
			if {!$answer} {
				return "declined"
			}
		} elseif {$isConfirm && $ConfirmHook ne ""} {
			if {[catch { uplevel #0 [::list $ConfirmHook $what] } answer]} {
				set answer 0
			}
			if {!$answer} {
				return "declined"
			}
		}
	}

	set objectType [dict get $record object]
	if {$objectType ne ""} {
		if {![catch {::action::resolver::resolve $objectType} resolvedObj]} {
			set validatedArgs [dict set validatedArgs _object $resolvedObj]
		}
	}

	set cmd [::list $handler $validatedArgs]

	set code [catch {uplevel #0 $cmd} result options]
	if {$code != 0} {
		return "error: [string trim $result]"
	}
	return $result
}

# ----------------------------------------------------------------------
# labels: return {id label accelerator enabled visible} rows for a surface.
# Surface: bar, context:<id>, palette
# Debug actions are excluded from all surfaces.
# ----------------------------------------------------------------------
proc ::action::labels {surface} {
	variable Registry

	set output {}
	foreach id [dict keys $Registry] {
		set record [dict get $Registry $id]
		
		if {[dict get $record ai] eq "debug"} { continue }
		
		set include 0

		if {$surface eq "bar"} {
			if {[dict get $record menu] ne ""} { set include 1 }
		} elseif {[string match "context:*" $surface]} {
			set ctxId [string range $surface 8 end]
			if {$ctxId in [dict get $record context]} { set include 1 }
		} elseif {$surface eq "palette"} {
			set vp [dict get $record visible]
			if {$vp eq "" || [uplevel #0 $vp]} { set include 1 }
		} else {
			set include 1
		}

		if {!$include} continue

		set ep [dict get $record enabled]
		set en 1
		if {$ep ne ""} { set en [uplevel #0 $ep] }

		set vp [dict get $record visible]
		set vis 1
		if {$vp ne ""} { set vis [uplevel #0 $vp] }

		set ks [dict get $record keys]
		set ac ""
		if {[llength $ks] >= 2} { set ac [lindex $ks 1] }

		lappend output [::list $id [dict get $record label] $ac $en $vis]
	}

	return $output
}

# ----------------------------------------------------------------------
# invoke: run an action as a user click would (with confirmation gate).
# ----------------------------------------------------------------------
proc ::action::invoke {id args} {
	variable Registry

	if {![dict exists $Registry $id]} {
		return "error: unknown action id '$id'"
	}

	set record [dict get $Registry $id]
	if {[dict get $record confirm]} {
		set what [dict get $record what]
		if {$what eq ""} {
			set what "perform action '$id'"
		}
		if {[llength [info commands ::dialog::question]]} {
			set answer [::dialog::question -message $what -default no]
			if {$answer ne "yes"} {
				return "declined"
			}
		}
	}

	return [::action::run $id {*}$args]
}
