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
	variable DebugGate {}
	# Compatibility state for plan observers; never grants dispatch approval.
	variable PlanGate 0

	namespace export register run list get labels invoke
}

namespace eval ::action::resolver {}

proc ::action::_dg {d key def} {
	if {[dict exists $d $key]} { return [dict get $d $key] }
	return $def
}

# Tri-state required option: 1 = explicitly required, 0 = explicitly
# optional, -1 = not specified (required only when there is no default).
proc ::action::_requiredState {opts} {
	if {[dict exists $opts required]} {
		set val [dict get $opts required]
		if {$val in {1 true yes}} { return 1 }
		if {$val in {0 false no}} { return 0 }
		return 1
	}
	if {[lsearch -exact $opts required] >= 0} { return 1 }
	return -1
}

# ----------------------------------------------------------------------
# register: store an action record after validation.
# Record fields (all optional except label):
#   label      mc variable name (required)
#   object     app|board|game|move|db|player|engine-line|media|pane|...
#   args       Tcl-native args spec -> JSON schema generated
#   schema     pre-built JSON schema string (passthrough, no generation)
#   validate   cross-arg validation hook (command prefix, receives validated dict)
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
	# Every record must declare these fields explicitly. Empty values are
	# allowed for what/object/doc ("none"), but the key must be present so a
	# forgotten field is a registration error, not a runtime surprise.
	foreach requiredField {handler what object doc} {
		if {![dict exists $record $requiredField]} {
			return -code error "error: action '$id' missing required field '$requiredField'"
		}
	}
	if {[dict get $record handler] eq ""} {
		return -code error "error: action '$id' missing required field 'handler'"
	}

	if {[dict exists $record ai]} {
		set aiVal [dict get $record ai]
		if {$aiVal ni {0 1 debug}} {
			return -code error "error: action '$id' field 'ai' must be 0, 1, or debug"
		}
	}

	foreach boolField {confirm bulk async ends-in-dialog} {
		if {[dict exists $record $boolField]} {
			set bval [dict get $record $boolField]
			if {$bval ni {0 1 true false yes no}} {
				return -code error "error: action '$id' field '$boolField' must be boolean"
			}
		}
	}

	if {[dict exists $record maxreply]} {
		set mrval [dict get $record maxreply]
		if {![string is integer -strict $mrval]} {
			return -code error "error: action '$id' field 'maxreply' must be an integer"
		}
	}

	set normalized [dict create \
		label    [dict get $record label] \
		object   [_dg $record object {}] \
		args     [_dg $record args {}] \
		schema   [_dg $record schema {}] \
		validate [_dg $record validate {}] \
		handler  [_dg $record handler {}] \
		enabled  [_dg $record enabled {}] \
		visible  [_dg $record visible {}] \
		keys     [_dg $record keys {}] \
		confirm  [expr {[_dg $record confirm 0] ? 1 : 0}] \
		bulk     [expr {[_dg $record bulk 0] ? 1 : 0}] \
		what     [_dg $record what {}] \
		ai       [_dg $record ai 0] \
		menu     [_dg $record menu {}] \
		dropdown [_dg $record dropdown {}] \
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
# Spec format: {name {type <type> ?default <val>? ?enum <list>?
#                     ?range {min max}? ?description <text>?
#                     ?items <type>? ?item-enum <list>? ?required <bool>?}}
# Types: string, integer, number, boolean, enum, array
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
		set description [_dg $opts description {}]

		if {[llength $enumVals]} {
			set type enum
		}

		set reqState [_requiredState $opts]

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
		} elseif {$type eq "array"} {
			dict set prop type array
			set items [dict create type [_dg $opts items string]]
			set itemEnum [_dg $opts item-enum {}]
			if {[llength $itemEnum]} {
				dict set items enum $itemEnum
			}
			dict set prop items $items
		} else {
			dict set prop type string
		}

		if {$hasDefault} {
			dict set prop default $defaultVal
		}
		if {$description ne ""} {
			dict set prop description $description
		}

		dict set properties $name $prop

		if {($reqState == 1 || ($reqState < 0 && !$hasDefault)) && [lsearch -exact $required $name] < 0} {
			lappend required $name
		}
	}

	set schema [dict create type object properties $properties]
	if {[llength $required]} {
		dict set schema required $required
	}
	return $schema
}

proc ::action::_jsonString {s} {
	set s [string map [::list "\\" "\\\\" "\"" "\\\"" "\n" "\\n" "\r" "\\r" "\t" "\\t"] $s]
	return "\"$s\""
}

proc ::action::_jsonScalar {v} {
	if {[string is integer -strict $v] || [string is double -strict $v]} { return $v }
	if {$v in {true false}} { return $v }
	return [_jsonString $v]
}

# ----------------------------------------------------------------------
# Compact JSON schema generated from a Tcl args spec. Property order and
# key order follow the spec so the output matches the documented tool
# schema byte for byte (the assistant baseline in tests/fixtures).
# ----------------------------------------------------------------------
proc ::action::schemaJson {spec} {
	set props {}
	set required {}
	foreach param $spec {
		set name [lindex $param 0]
		set opts [lindex $param 1]
		set type [_dg $opts type string]
		set enumVals [_dg $opts enum {}]
		set rangeVals [_dg $opts range {}]
		set description [_dg $opts description {}]

		if {[llength $enumVals]} { set type enum }

		set reqState [_requiredState $opts]
		set hasDefault [dict exists $opts default]
		if {($reqState == 1 || ($reqState < 0 && !$hasDefault)) && [lsearch -exact $required $name] < 0} {
			lappend required $name
		}

		set p "\{\"type\":"
		if {$type eq "enum" && [llength $enumVals]} {
			set vals {}
			foreach v $enumVals { lappend vals [_jsonScalar $v] }
			append p "\"string\",\"enum\":\[[join $vals ,]\]"
		} elseif {$type eq "integer" || $type eq "number"} {
			append p [_jsonString $type]
			if {[llength $rangeVals] == 2} {
				append p ",\"minimum\":[lindex $rangeVals 0],\"maximum\":[lindex $rangeVals 1]"
			}
		} elseif {$type eq "boolean"} {
			append p "\"boolean\""
		} elseif {$type eq "array"} {
			set items [_dg $opts items string]
			set itemEnum [_dg $opts item-enum {}]
			append p "\"array\",\"items\":\{\"type\":[_jsonString $items]"
			if {[llength $itemEnum]} {
				set vals {}
				foreach v $itemEnum { lappend vals [_jsonScalar $v] }
				append p ",\"enum\":\[[join $vals ,]\]"
			}
			append p "\}"
		} else {
			append p "\"string\""
		}
		if {[dict exists $opts default]} {
			append p ",\"default\":[_jsonScalar [dict get $opts default]]"
		}
		if {$description ne ""} {
			append p ",\"description\":[_jsonString $description]"
		}
		append p "\}"
		lappend props "[_jsonString $name]:$p"
	}

	set reqJson {}
	foreach v $required { lappend reqJson [_jsonString $v] }
	set out "\{\"type\":\"object\",\"properties\":\{[join $props ,]\}"
	if {[llength $required]} {
		append out ",\"required\":\[[join $reqJson ,]\]"
	}
	append out "\}"
	return $out
}

# ----------------------------------------------------------------------
# Enum error text. The default is the validator's own wording; generated
# assistant tools carry a style so their messages stay identical to the
# texts the assistant has always returned ("quoted", "bare" or "oneof").
# ----------------------------------------------------------------------
proc ::action::_enumText {name vals style} {
	set n [llength $vals]
	switch -- $style {
		oneof {
			return "$name must be one of: [join $vals {, }]"
		}
		bare {
			if {$n <= 1} { return "$name must be [join $vals {, }]" }
			return "$name must be [join [lrange $vals 0 end-1] {, }] or [lindex $vals end]"
		}
		quoted {
			set quoted {}
			foreach v $vals { lappend quoted "'$v'" }
			if {$n <= 1} { return "$name must be [join $quoted {, }]" }
			return "$name must be [join [lrange $quoted 0 end-1] {, }] or [lindex $quoted end]"
		}
	}
	return "argument '$name' must be one of: [join $vals {, }]"
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
		set reqState [_requiredState $opts]
		set isRequired [expr {$reqState == 1 || ($reqState < 0 && !$hasDefault)}]
		set enumVals [_dg $opts enum {}]
		set enumStyle [_dg $opts enum-style {}]
		set rangeVals [_dg $opts range {}]
		set hasLegacyDefault [dict exists $opts legacy-default]

		if {[llength $enumVals]} {
			set type enum
		}

		if {[dict exists $argsDict $name]} {
			set value [dict get $argsDict $name]
		} elseif {$isRequired} {
			return [::list error "missing argument '$name'"]
		} elseif {$hasLegacyDefault} {
			set value [dict get $opts legacy-default]
		} elseif {$hasDefault} {
			set value $defaultVal
		} else {
			continue
		}

		if {$type eq "enum" && [llength $enumVals]} {
			if {[lsearch -exact $enumVals $value] < 0} {
				return [::list error [_enumText $name $enumVals $enumStyle]]
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
		} elseif {$type eq "array"} {
			set items [_dg $opts items string]
			set itemEnum [_dg $opts item-enum {}]
			if {[catch { llength $value }]} {
				return [::list error "argument '$name' must be an array"]
			}
			foreach item $value {
				if {[llength $itemEnum] && [lsearch -exact $itemEnum $item] < 0} {
					return [::list error "argument '$name' items must be one of: [join $itemEnum {, }]"]
				}
				if {$items eq "integer" && ![string is integer -strict $item]} {
					return [::list error "argument '$name' items must be integers"]
				}
			}
		}

		dict set validated $name $value
	}

	set validateHook [dict get $record validate]
	if {$validateHook ne ""} {
		if {[catch {uplevel #0 [::list $validateHook $validated]} hookResult]} {
			return [::list error "cross-argument validation failed: $hookResult"]
		}
		if {$hookResult eq "error" || ([llength $hookResult] >= 2 && [lindex $hookResult 0] eq "error")} {
			if {[llength $hookResult] >= 2} {
				return [::list error [lindex $hookResult 1]]
			}
			return [::list error "cross-argument validation failed"]
		}
	}

	return [::list ok $validated]
}

# ----------------------------------------------------------------------
# Object resolvers for context actions.
# Register resolvers per object type; they return a typed reference
# without depending on widget paths.
# ----------------------------------------------------------------------
proc ::action::resolver::register {objectType command} {
	namespace upvar ::action ObjectResolvers resolvers
	dict set resolvers $objectType $command
	return
}

proc ::action::resolver::resolve {objectType} {
	namespace upvar ::action ObjectResolvers resolvers
	if {![dict exists $resolvers $objectType]} {
		return -code error "no resolver for object type '$objectType'"
	}
	return [uplevel #0 [dict get $resolvers $objectType]]
}

# ----------------------------------------------------------------------
# run: validate args and call the handler.
# Returns the handler result or an error: text (never raises).
# Enforces confirm and bulk gates when hooks are configured.
# ----------------------------------------------------------------------
proc ::action::run {id args} {
	return [Dispatch $id $args {}]
}

# Approval is supplied only for the concrete call displayed in a plan.
# Ordinary run calls always enter Dispatch without approval.
proc ::action::RunApproved {id cargs} {
	return [Dispatch $id [::list $cargs] [::list $id $cargs]]
}

proc ::action::Dispatch {id args approval} {
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

	set aiFlag [dict get $record ai]
	if {$aiFlag eq "debug"} {
		variable DebugGate
		if {$DebugGate ne ""} {
			if {[catch {uplevel #0 $DebugGate} debugEnabled]} {
				set debugEnabled 0
			}
		} else {
			set debugEnabled 0
		}
		if {!$debugEnabled} {
			return "error: '$id' is only available in debug mode (--ai-debug or SCIDB_AI_DEBUG=1)"
		}
	}

	set argsDict {}
	if {[llength $args] == 1 && [string match "{*}" [lindex $args 0]]} {
		set argsDict [lindex $args 0]
	} elseif {[llength $args] > 0} {
		set argsDict [lindex $args 0]
	}

	set argsSpec [dict get $record args]
	set passthrough [dict get $record schema]
	if {$passthrough ne "" && $argsSpec eq ""} {
		set validatedArgs $argsDict
	} else {
		set validation [::action::validateArgs $id $argsDict]
		set status [lindex $validation 0]
		if {$status eq "error"} {
			return "error: [lindex $validation 1]"
		}
		set validatedArgs [lindex $validation 1]
	}

	if {$approval ne "" && $approval ne [::list $id $validatedArgs]} {
		return "error: approved action arguments changed"
	}

	set enabledPred [dict get $record enabled]
	if {$enabledPred ne ""} {
		set isEnabled [catch {uplevel #0 $enabledPred} result]
		if {$isEnabled || !$result} {
			return "error: action '$id' is not enabled"
		}
	}

	# Context-only actions act on the object they are listed for. With no
	# object (or an object whose R10 rule hides the row) they must not run.
	if {[llength [dict get $record context]] && [dict get $record dropdown] eq "" \
	 && [llength [info commands ::menu::state]]} {
		# A caller that supplies the object (a context menu, the assistant) is
		# judged by that object's rule; only a bare call uses the current one.
		set object [lindex $args 0]
		if {[llength $args] && ![catch { dict size $object } n] && $n > 0 \
		 && [llength [info commands ::context::ObjectRule]]} {
			set rule [::context::ObjectRule $id $object]
			if {[llength $rule] && (![lindex $rule 0] || ![lindex $rule 1])} {
				return "error: action '$id' is not available here"
			}
		} else {
			set state [::menu::state $id]
			if {![dict get $state visible] || ![dict get $state enabled]} {
				return "error: action '$id' is not available here"
			}
		}
	}

	set isConfirm [dict get $record confirm]
	set isBulk [dict get $record bulk]
	set what [dict get $record what]

	if {($isConfirm || $isBulk) && $approval ne [::list $id $validatedArgs]} {
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
		if {[catch {::action::resolver::resolve $objectType} resolvedObj]} {
			return "error: cannot resolve object '$objectType': [string trim $resolvedObj]"
		}
		set validatedArgs [dict set validatedArgs _object $resolvedObj]
	}

	set code [catch {uplevel #0 [::list {*}$handler $validatedArgs]} result options]
	if {$code != 0} {
		return "error: [string trim $result]"
	}
	return $result
}

# ----------------------------------------------------------------------
# fuzzyScore: rank <query> against <text>.
#
# Returns -1 when the query is not a subsequence of the text; otherwise a
# score (bigger is better). Substring and word-boundary matches beat a
# subsequence spread over the text. Kept allocation-light: the Ask field
# calls it for every registry row on every keystroke.
# ----------------------------------------------------------------------
proc ::action::fuzzyScore {query text} {
	if {$query eq ""} { return 0 }
	set q [string tolower $query]
	set t [string tolower $text]
	set pos [string first $q $t]
	if {$pos >= 0} {
		set score [expr {1000 - [string length $t] - $pos}]
		if {$pos == 0} {
			incr score 400
		} elseif {[regexp {(^|[ _./-])} [string index $t [expr {$pos - 1}]]]} {
			incr score 200
		}
		return $score
	}
	set i 0
	set first -1
	set last -1
	set gaps 0
	foreach ch [split $q ""] {
		set j [string first $ch $t $i]
		if {$j < 0} { return -1 }
		if {$first < 0} { set first $j }
		if {$last >= 0} { incr gaps [expr {$j - $last - 1}] }
		set last $j
		set i [expr {$j + 1}]
	}
	return [expr {500 - $gaps - ($last - $first + 1) - [string length $t]}]
}

# The registry stores human labels for menu actions but bare tool ids
# (open_game) for assistant tools. Show the latter as words.
proc ::action::displayLabel {label} {
	if {[regexp {^[a-z0-9_]+$} $label] && [string match "*_*" $label]} {
		return [join [split $label _] " "]
	}
	return $label
}

# The text a query is matched against: label, doc and accelerator.
proc ::action::searchText {id} {
	variable Registry
	set record [dict get $Registry $id]
	set text "[displayLabel [dict get $record label]] [dict get $record doc]"
	set ks [dict get $record keys]
	if {[llength $ks] >= 2 && [lindex $ks 1] ne ""} { append text " " [lindex $ks 1] }
	return $text
}

# The display accelerator of an action, honouring a key-editor override.
proc ::action::labelAccel {id} {
	if {[llength [info commands ::menu::Accel]]} {
		if {![catch { set a [::menu::Accel $id] }]} { return $a }
	}
	set ks [dict get [get $id] keys]
	if {[llength $ks] >= 2} { return [lindex $ks 1] }
	return ""
}

# ----------------------------------------------------------------------
# labels: return {id label accelerator enabled visible} rows for a surface.
# Surface: bar, context:<id>, palette, asklist ?query?
#
# asklist is the Ask field's result list: only runnable rows (enabled AND
# visible, the same predicates as the drop-down), filtered and ranked by
# the fuzzy match over label, doc and accelerator. With no query every
# runnable row is returned. The caller adds the trailing assistant row.
# Debug actions are excluded from all surfaces.
# ----------------------------------------------------------------------
proc ::action::labels {surface args} {
	variable Registry

	set query ""
	if {$surface eq "asklist" && [llength $args]} { set query [lindex $args 0] }

	set output {}
	set keyed {}
	set c9Ids {}
	if {$surface eq "asklist"} {
		# C9 rows belong to the pane the user is in: list only the rows
		# that pane's own header menu would post (VAL-RULE-006).
		if {[llength [info commands ::context::MenuIds]] \
		 && [llength [info commands ::context::CurrentObject]]} {
			if {![catch { set c9Object [::context::CurrentObject C9] }] \
			 && [dict size $c9Object]} {
				catch { set c9Ids [::context::MenuIds C9 $c9Object] }
			}
		}
	}
	foreach id [dict keys $Registry] {
		set record [dict get $Registry $id]

		if {[dict get $record ai] eq "debug"} { continue }

		set include 0
		set order ""

		if {$surface eq "dropdown"} {
			set order [dict get $record dropdown]
			if {$order ne ""} { set include 1 }
		} elseif {$surface eq "bar"} {
			if {[dict get $record menu] ne ""} { set include 1 }
		} elseif {[string match "context:*" $surface]} {
			set ctxId [string range $surface 8 end]
			if {$ctxId in [dict get $record context]} { set include 1 }
		} elseif {$surface eq "palette" || $surface eq "asklist"} {
			set vp [dict get $record visible]
			if {$vp eq ""} {
				set include 1
			} elseif {[catch { uplevel #0 $vp } shown]} {
				set include 1
			} elseif {$shown} {
				set include 1
			}
		} else {
			set include 1
		}

		if {!$include} continue

		if {$surface eq "asklist"} {
			# The context menus' assistant row is not a runnable action.
			if {$id eq "context.ask"} continue
			set ctx [dict get $record context]
			if {"C9" in $ctx && [lsearch -exact $c9Ids $id] < 0} { continue }
		}

		set ep [dict get $record enabled]
		set en 1
		if {$ep ne ""} {
			if {[catch { uplevel #0 $ep } state]} { set en 0 } else { set en [expr {$state ? 1 : 0}] }
		}

		set vp [dict get $record visible]
		set vis 1
		if {$vp ne ""} {
			if {[catch { uplevel #0 $vp } state]} { set vis 0 } else { set vis [expr {$state ? 1 : 0}] }
		}

		set label [displayLabel [dict get $record label]]
		set ac [labelAccel $id]

		if {$surface eq "asklist"} {
			# The list shows only actions the user can run now. Ask the same
			# state function the drop-down and context menus use, so R1-R16,
			# absent optional modules and context predicates agree exactly
			# (VAL-RULE-004).
			if {[llength [info commands ::menu::state]]} {
				if {![catch {::menu::state $id} state]} {
					set en [dict get $state enabled]
					set vis [dict get $state visible]
				}
			}
			if {!$en || !$vis} { continue }
			if {$query ne ""} {
				set score [fuzzyScore $query [searchText $id]]
				if {$score < 0} { continue }
			} else {
				set score 0
			}
			set row [::list $id $label $ac $en $vis]
			lappend output [::list $score $label $row]
			continue
		}

		set row [::list $id $label $ac $en $vis]
		lappend output $row
		if {$surface eq "dropdown"} { lappend keyed [::list $order $row] }
	}

	if {$surface eq "dropdown"} {
		set sorted [lsort -index 0 $keyed]
		set output {}
		foreach pair $sorted { lappend output [lindex $pair 1] }
	} elseif {$surface eq "asklist"} {
		set sorted [lsort -integer -decreasing -index 0 $output]
		set output {}
		foreach entry $sorted { lappend output [lindex $entry 2] }
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
	
	set aiFlag [dict get $record ai]
	if {$aiFlag eq "debug"} {
		variable DebugGate
		if {$DebugGate ne ""} {
			if {[catch {uplevel #0 $DebugGate} debugEnabled]} {
				set debugEnabled 0
			}
		} else {
			set debugEnabled 0
		}
		if {!$debugEnabled} {
			return "error: '$id' is only available in debug mode (--ai-debug or SCIDB_AI_DEBUG=1)"
		}
	}
	
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
