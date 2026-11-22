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
	# Bare-call validity is a property of the args spec, not of live state.
	variable BareCache [dict create]
	# The Ask list reads every row on every keystroke. Its state-qualified
	# rows are cached until a state input changes. The stamp below reads the
	# same inputs menu::state does, so a menu build (a pure read) does not
	# have to invalidate the cache.
	variable AskCachedStamp ""
	variable AskCachedRows {}
	variable AskLiveScriptsKey ""
	variable AskLiveScripts {}
	variable AskMetaCache [dict create]
	# Availability each cached row had when it was captured, so a menu read
	# that observes a different availability can invalidate the snapshot.
	variable AskStateMap [dict create]
	variable AskBuilding 0
	variable RegistryVersion 0

	namespace export register run list get labels invoke
}

namespace eval ::action::resolver {}

proc ::action::_dg {d key def} {
	if {[dict exists $d $key]} { return [dict get $d $key] }
	return $def
}

# Exact effect metadata, independent of whether a model likes the result.
proc ::action::changesState {id arguments} {
	set rec [get $id]
	if {[_dg $rec effect change] eq "query"} {return 0}
	# Execution used schema defaults. Classifying only the supplied arguments
	# would incorrectly turn an omitted default status/list into a mutation.
	foreach param [dict get $rec args] {
		lassign $param name opts
		if {![dict exists $arguments $name] && [dict exists $opts default]} {
			dict set arguments $name [dict get $opts default]
		}
	}
	if {[dict exists $arguments operation] && [dict get $arguments operation] in {status list}} {return 0}
	set predicate [_dg $rec effect-command {}]
	if {$predicate ne ""} {
		if {[catch {uplevel #0 [::list {*}$predicate $arguments]} changes]} {return 0}
		return [expr {[string is boolean -strict $changes] && $changes}]
	}
	return 1
}

# Tri-state required option: 1 = required, 0 = optional, -1 = unspecified.
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
#   label      display text (required)
#   label-command optional native label resolver, evaluated at read time
#   object     app|board|game|move|db|player|engine-line|media|pane|...
#   args       Tcl-native args spec -> JSON schema generated
#   schema     pre-built JSON schema string (passthrough, no generation)
#   validate   cross-arg validation hook (command prefix, receives validated dict)
#   handler    command prefix (validated args dict appended)
#   enabled    predicate command (returns 1/0)
#   enabled-args  append validated arguments to enabled on dispatch (default 0)
#   visible    predicate command (returns 1/0)
#   visible-args  append validated arguments to visible on invoke (default 0)
#   keys       {chesswiz {} chessbase Control-n}
#   confirm    0|1
#   bulk       0|1
#   what       format string for confirmation prompt
#   ai         1|0|debug
#   menu       {Game 10}  (menu path hint)
#   context    {C12}      (context menu id)
#   toolmenu   "..."      (assistant reply menu hint)
#   doc        description text
#   effect     change|query (query results never stand in for a missing fact)
#   effect-command optional exact predicate for mixed getter/setter actions
#   async      0|1
#   maxreply   int
#   ends-in-dialog  0|1
#   purpose    one plain sentence: what the action does (VAL-KNOW-001)
#   when       one plain sentence: when a user wants it
#   examples   at least two plain-language requests
#   related    existing action ids a user may want next
#   video      optional how-to video key
#   keywords   lexical lookup terms (find_capability; never shown)
#   i18n       {lang {purpose ... when ... examples {...}}} translations
#   operator   1 = the assistant may run it through run_action (VAL-AI-009)
# ----------------------------------------------------------------------
proc ::action::register {id record} {
	variable Registry
	variable BareCache
	variable RegistryVersion

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

	foreach boolField {confirm bulk async ends-in-dialog enabled-args visible-args} {
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

	if {[_dg $record effect change] ni {change query}} {
		return -code error "error: action '$id' effect must be change or query"
	}
	set normalized [dict create \
		effect   [_dg $record effect change] \
		effect-command [_dg $record effect-command {}] \
		label    [dict get $record label] \
		label-command [_dg $record label-command {}] \
		object   [_dg $record object {}] \
		args     [_dg $record args {}] \
		schema   [_dg $record schema {}] \
		validate [_dg $record validate {}] \
		handler  [_dg $record handler {}] \
		enabled  [_dg $record enabled {}] \
		enabled-args [expr {[_dg $record enabled-args 0] ? 1 : 0}] \
		visible  [_dg $record visible {}] \
		visible-args [expr {[_dg $record visible-args 0] ? 1 : 0}] \
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
		purpose  [_dg $record purpose {}] \
		when     [_dg $record when {}] \
		examples [_dg $record examples {}] \
		related  [_dg $record related {}] \
		video    [_dg $record video {}] \
		keywords [_dg $record keywords {}] \
		i18n     [_dg $record i18n {}] \
		operator [expr {[_dg $record operator 0] ? 1 : 0}] \
	]

	dict set Registry $id $normalized
	dict unset BareCache $id
	if {[info exists AskMetaCache]} { dict unset AskMetaCache $id }
	incr RegistryVersion
	InvalidateAskRows
	return $id
}

# Dynamic popup operations exist only while their surface does. Removing one
# keeps the assistant's toolset equal to the approved set between dialogs.
proc ::action::Unregister {id} {
	variable Registry
	variable BareCache
	variable AskMetaCache
	variable RegistryVersion

	if {![dict exists $Registry $id]} { return 0 }
	dict unset Registry $id
	dict unset BareCache $id
	if {[info exists AskMetaCache]} { dict unset AskMetaCache $id }
	incr RegistryVersion
	InvalidateAskRows
	return 1
}

# A pane can be closed and reopened. Its native toolbar keeps the stable
# action id it was registered with, but the widget-bound command changes.
# Update that handler in place; the toolbar caller only asks when no live
# widget still owns the id (a second open instance gets its own id).
proc ::action::UpdateToolbarHandler {id handler} {
	variable Registry
	variable RegistryVersion

	if {![dict exists $Registry $id]} { return 0 }
	set record [dict get $Registry $id]
	if {[lindex [dict get $record handler] 0] ne "::toolbar::InvokeCommand"} { return 0 }
	dict set record handler $handler
	dict set Registry $id $record
	incr RegistryVersion
	InvalidateAskRows
	return 1
}

# Direct ::action::Registry mutations (context rows, named sorts, menu
# nodes) bypass register; they call this so the Ask snapshot sees them.
proc ::action::NoteRegistryChange {} {
	variable BareCache
	variable RegistryVersion
	set BareCache [dict create]
	incr RegistryVersion
	InvalidateAskRows
}

# ----------------------------------------------------------------------
# get: retrieve a single action record.
# ----------------------------------------------------------------------
proc ::action::get {id} {
	variable Registry
	if {![dict exists $Registry $id]} {
		return -code error "error: unknown action id '$id'"
	}
	# Native rows supply their label resolver to generated surfaces. Resolve
	# at read time, including derived mc text changed after a language switch.
	set command [_dg [dict get $Registry $id] label-command {}]
	if {$command ne ""} {
		dict set Registry $id label [uplevel #0 $command]
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
		} elseif {$type eq "object"} {
			dict set prop type object
			dict set prop additionalProperties 1
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
		} elseif {$type eq "object"} {
			append p "\"object\",\"additionalProperties\":true"
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

	if {[catch {dict size $argsDict}]} {
		return [::list error "arguments must be a dictionary"]
	}

	if {$spec eq ""} {
		if {[dict size $argsDict] > 0} {
			return [::list error "action '$id' takes no arguments"]
		}
		return [::list ok [dict create]]
	}

	# A model sometimes wraps flat arguments in an invented object
	# ("criteria": {...}); silently dropping those keys runs the action with
	# defaults. Name the key so the model loop can correct the call.
	set known [lmap param $spec { lindex $param 0 }]
	foreach key [dict keys $argsDict] {
		if {$key ni $known} {
			return [::list error "unknown argument '$key'"]
		}
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
			# A model (and a JSON null) commonly sends "" for an optional
			# value; that means "use the default". An explicit empty enum
			# member remains a value when the schema offers it.
			if {!$isRequired && $value eq "" && $type in {integer number boolean enum}
			 && ($type ne "enum" || "" ni $enumVals)} {
				if {$hasLegacyDefault} {
					set value [dict get $opts legacy-default]
				} elseif {$hasDefault} {
					set value $defaultVal
				} else {
					continue
				}
			}
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
		} elseif {$type eq "object"} {
			if {[catch { dict size $value }]} {
				return [::list error "argument '$name' must be an object"]
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
	# Menu rows pass {... defer idle} so the handler starts after native popup
	# tracking returns (Windows runs -command inside TrackPopupMenu); a handler
	# that opens a dialog or a nested event loop there hangs the menu.
	if {[llength $args] == 1 && ![catch { dict exists [lindex $args 0] defer } has] \
	 && $has && [dict get [lindex $args 0] defer] eq "idle"} {
		after idle [::list ::action::run $id [dict remove [lindex $args 0] defer]]
		return ""
	}
	if {[catch {Dispatch $id $args {}} result]} {return "error: $result"}
	return $result
}

# Approval is supplied only for the concrete call displayed in a plan.
# Ordinary run calls always enter Dispatch without approval.
proc ::action::RunApproved {id cargs} {
	if {[catch {Dispatch $id [::list $cargs] [::list $id $cargs]} result]} {return "error: $result"}
	return $result
}

proc ::action::Dispatch {id args approval {postedState 0}} {
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

	if {[catch {dict size $argsDict}]} {
		return "error: arguments must be a dictionary"
	}
	if {[llength [info commands ::capability::actionAvailable]] && ![::capability::actionAvailable $id $argsDict]} {
		return "error: action '$id' requires an unavailable module"
	}

	if {[llength [info commands ::context::NeedsObject]] && [::context::NeedsObject $record $argsDict]} {
		if {![dict exists $argsDict object]} {
			set selected [::context::CurrentObjectFor $id]
			if {[llength $selected]} { dict set argsDict object [lindex $selected 1] }
		}
		if {![dict exists $argsDict object] || [dict get $argsDict object] eq ""} {
			return "error: precondition: select an item before running $id"
		}
	}

	# A schema is a presentation format, not an exemption from the shared
	# args-spec validator. An empty spec still rejects every supplied key.
	set validation [::action::validateArgs $id $argsDict]
	if {[lindex $validation 0] eq "error"} {
		return "error: [lindex $validation 1]"
	}
	set validatedArgs [lindex $validation 1]

	if {$approval ne "" && $approval ne [::list $id $validatedArgs]} {
		return "error: approved action arguments changed"
	}

	set enabledPred [dict get $record enabled]
	if {$enabledPred ne ""} {
		# Argument-aware predicates use the exact validated object supplied
		# by the caller. Existing no-argument predicates keep their API.
		if {[dict get $record enabled-args]} {
			lappend enabledPred $validatedArgs
		}
		set isEnabled [catch {uplevel #0 $enabledPred} result]
		if {$isEnabled || !$result} {
			return "error: action '$id' is not enabled"
		}
	}

	# Every invocation follows the posted row's visibility and enabled state,
	# including dropdown tab restrictions (R16). Resolve context rules against
	# the validated explicit object, just as a native caller does.
	if {$postedState && [llength [info commands ::menu::state]]} {
		set object {}
		if {[dict exists $validatedArgs object]} {
			set object [dict get $validatedArgs object]
		} elseif {[llength [dict get $record context]]} {
			set object $validatedArgs
		}
		set state [::menu::state $id $object $validatedArgs]
		if {![dict get $state visible] || ![dict get $state enabled]} {
			return "error: action '$id' is not available here"
		}
	} elseif {[llength [dict get $record context]] && [dict get $record dropdown] eq "" \
	 && [llength [info commands ::menu::state]]} {
		# A caller that supplies the object (a context menu, the assistant) is
		# judged by that object's rule; only a bare call uses the current one.
		set object $validatedArgs
		if {[dict exists $object object]} { set object [dict get $object object] }
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
		if {[llength [info commands ::debuglog::log]]} {
			::debuglog::log action "$id: $result"
		}
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
	return [fuzzyScoreLower $q $t]
}

# fuzzyScore with both strings already lowercased. The Ask list keeps its
# row text lowercased and lowercases the query once, so typing does not
# re-case every registry row on every keystroke.
proc ::action::fuzzyScoreLower {q t} {
	if {$q eq ""} { return 0 }
	set pos [string first $q $t]
	if {$pos >= 0} {
		set score [expr {1000 - [string length $t] - $pos}]
		if {$pos == 0} {
			incr score 400
		} elseif {[string first [string index $t [expr {$pos - 1}]] " _./-"] >= 0} {
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

# The registry stores menu labels with Tk's "&" mnemonic markup and bare
# tool ids (open_game) for assistant tools. A surface that prints a label
# as text (Ask, knowledge, assistant, key editor, tooltips) must drop the
# mnemonic markers; "&&" is one literal ampersand.
proc ::action::plainText {text} {
	if {[llength [info commands ::tk::UnderlineAmpersand]]} {
		return [lindex [::tk::UnderlineAmpersand $text] 0]
	}
	# Tk-less test interpreters: one "&" marks the next character, "&&" is
	# a literal ampersand.
	set out ""
	set n [string length $text]
	for {set i 0} {$i < $n} {incr i} {
		if {[string index $text $i] ne "&"} {
			append out [string index $text $i]
			continue
		}
		if {$i + 1 < $n && [string index $text [expr {$i + 1}]] eq "&"} {
			append out "&"
			incr i
		}
	}
	return $out
}

# The label as a menu/Ask row stores it: bare tool ids become words, and
# any "&" mnemonic markup is kept for the consumer that owns the surface.
proc ::action::markupLabel {label} {
	if {[regexp {^[a-z0-9_]+$} $label] && [string match "*_*" $label]} {
		return [join [split $label _] " "]
	}
	return $label
}

proc ::action::displayLabel {label} {
	return [::action::plainText [::action::markupLabel $label]]
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

# The same two readings from a record the caller already resolved. The Ask
# field reads every registry row per keystroke, so it must not call get (and
# a label-command) again for the text and the accelerator.
proc ::action::searchTextRecord {record} {
	set markup [markupLabel [dict get $record label]]
	set text [plainText $markup]
	if {$markup ne $text} { append text " $markup" }
	append text " " [dict get $record doc]
	set ks [dict get $record keys]
	if {[llength $ks] >= 2 && [lindex $ks 1] ne ""} { append text " " [lindex $ks 1] }
	return $text
}

proc ::action::labelAccelRecord {id record} {
	if {[llength [info commands ::menu::Accel]]} {
		if {![catch { set a [::menu::Accel $id] }]} { return $a }
	}
	set ks [dict get $record keys]
	if {[llength $ks] >= 2} { return [lindex $ks 1] }
	return ""
}

# Drop the cached Ask rows. Called by every input the stamp cannot see
# cheaply (register, capability override, tab/language/key changes) and by
# any menu-state read outside an Ask rebuild.
proc ::action::InvalidateAskRows {} {
	variable AskCachedStamp
	variable AskCachedRows
	variable AskLiveScriptsKey
	variable AskLiveScripts
	variable AskMetaCache
	variable AskStateMap
	set listVisible 0
	if {[llength [info commands ::application::ask::ListVisible]]} {
		catch { set listVisible [::application::ask::ListVisible] }
	}
	if {!$listVisible \
	 && (![info exists AskCachedStamp] || $AskCachedStamp eq "") \
	 && (![info exists AskCachedRows] || [llength $AskCachedRows] == 0) \
	 && (![info exists AskLiveScriptsKey] || $AskLiveScriptsKey eq "") \
	 && (![info exists AskMetaCache] || [dict size $AskMetaCache] == 0) \
	 && (![info exists AskStateMap] || [dict size $AskStateMap] == 0)} {
		if {[llength [info commands ::context::InvalidateCascadeIdSet]]} {
			::context::InvalidateCascadeIdSet
		}
		return
	}
	set AskCachedStamp ""
	set AskCachedRows {}
	set AskLiveScriptsKey ""
	set AskLiveScripts {}
	set AskMetaCache [dict create]
	set AskStateMap [dict create]
	if {[llength [info commands ::context::InvalidateCascadeIdSet]]} {
		::context::InvalidateCascadeIdSet
	}
	if {[llength [info commands ::application::ask::InvalidateCache]]} {
		::application::ask::InvalidateCache
	}
	if {[llength [info commands ::application::ask::ScheduleRefresh]]} {
		::application::ask::ScheduleRefresh
	}
}

# A menu build (or any state read outside an Ask rebuild) sees live
# availability. If it disagrees with the snapshot we captured, some state
# input the stamp cannot read has changed; drop the snapshot rather than
# serve a stale row set.
proc ::action::_ObserveState {id visible enabled} {
	variable AskCachedStamp
	variable AskStateMap
	variable AskBuilding
	# Some embedders copy these procedure bodies into a fresh interpreter
	# without running this namespace's initializer. There an unset variable
	# means the same thing as a cold cache: no build in progress and no
	# snapshot to compare against.
	if {[info exists AskBuilding] && $AskBuilding} { return }
	if {![info exists AskCachedStamp] || $AskCachedStamp eq ""} { return }
	if {![info exists AskStateMap] || ![dict exists $AskStateMap $id]} { return }
	set now [expr {$visible && $enabled ? 1 : 0}]
	if {$now != [dict get $AskStateMap $id]} {
		set AskCachedStamp ""
		if {[llength [info commands ::application::ask::ScheduleRefresh]]} {
			::application::ask::ScheduleRefresh
		}
	}
}

proc ::action::_stampOf {cmd} {
	if {![llength [info commands $cmd]]} { return "M" }
	if {[catch {$cmd} value]} { return "E" }
	return $value
}

# Read predicate RESULTS, not a hand-maintained list of their variables.
# Predicates are arbitrary scripts: a new action must not need a matching
# cache invalidation hook. Deduplicate shared predicates across aliases.
proc ::action::AskLiveInputs {ctxObjects ctxMenus} {
	variable Registry
	variable RegistryVersion
	variable AskLiveScriptsKey
	variable AskLiveScripts

	if {![info exists RegistryVersion]} { set RegistryVersion 0 }
	if {![info exists AskLiveScriptsKey]} { set AskLiveScriptsKey "" }
	if {![info exists AskLiveScripts]} { set AskLiveScripts {} }
	set predVer [expr {[info exists ::context::PredicateVersion] ? $::context::PredicateVersion : 0}]
	set predSize [expr {[info exists ::context::Predicates] ? [dict size $::context::Predicates] : 0}]
	set menusVer [expr {[info exists ::context::MenusVersion] ? $::context::MenusVersion : 0}]
	set hasObjRule [llength [info commands ::context::ObjectRule]]
	set hasDirectObjRule [llength [info commands ::context::HasDirectObjectRule]]
	set scriptsKey [::list $RegistryVersion [dict size $Registry] $ctxObjects $ctxMenus $predVer $predSize $menusVer $hasObjRule $hasDirectObjRule]
	if {$scriptsKey ne $AskLiveScriptsKey} {
		set scripts [dict create]
		dict for {id rec} $Registry {
			if {[dict get $rec ai] eq "debug" || $id eq "context.ask"} { continue }
			set object {}
			set contexts [dict get $rec context]
			if {[llength $contexts] && [dict get $rec dropdown] eq ""} {
				set included 0
				foreach cid $contexts {
					if {[dict exists $ctxMenus $cid] && $id in [dict get $ctxMenus $cid]} {
						set included 1
					}
				}
				if {!$included} { continue }
				foreach cid $contexts {
					if {[dict exists $ctxObjects $cid]} {
						if {$cid eq "C5" && $id ni [dict get $ctxMenus $cid]} { continue }
						set object [dict get $ctxObjects $cid]
						break
					}
				}
			}
			foreach field {visible enabled} {
				set script [dict get $rec $field]
				if {$script eq ""} { continue }
				if {[dict get $rec $field-args] && $object ne {}} {
					lappend script [dict create object $object]
				}
				dict set scripts $script 1
			}
			if {[string match {c[0-9]*} $id] && $hasObjRule \
			 && (($hasDirectObjRule && [::context::HasDirectObjectRule $id]) \
			  || (!$hasDirectObjRule && (![llength [info commands ::context::HasObjectRule]] || [::context::HasObjectRule $id])))} {
				dict set scripts [::list ::context::ObjectRule $id $object] 1
			}
		}
		if {[info exists ::context::Predicates]} {
			dict for {id predicates} $::context::Predicates {
				if {[dict exists $Registry $id]} {
					set rec [dict get $Registry $id]
					set contexts [dict get $rec context]
					if {[llength $contexts] && [dict get $rec dropdown] eq ""} {
						set included 0
						foreach cid $contexts {
							if {[dict exists $ctxMenus $cid] && $id in [dict get $ctxMenus $cid]} {
								set included 1
								break
							}
						}
						if {!$included} { continue }
					}
				}
				dict for {field predicate} $predicates {
					if {$field in {visible enabled}} {
						dict set scripts [::list namespace eval ::context [::list expr $predicate]] 1
					}
				}
			}
		}
		set AskLiveScripts [dict keys $scripts]
		set AskLiveScriptsKey $scriptsKey
	}
	set values {}
	foreach script $AskLiveScripts {
		set code [catch {uplevel #0 $script} value]
		lappend values $script $code $value
	}
	# These are the complete inputs to actionAvailable's bare-call gate.
	# Only readiness booleans are retained; credentials never enter a stamp.
	if {[llength [info commands ::capability::present]]} {
		foreach name {Modules Overrides ActionModuleById ActionCommands ArgumentModules ArgumentCommands} {
			lappend values $name [set ::capability::$name]
		}
		foreach module [dict keys $::capability::Modules] {
			lappend values $module [::capability::present $module]
		}
		dict for {id command} $::capability::ActionCommands {
			lappend values $id [llength [info commands $command]]
		}
	}
	return $values
}

# A cheap reading of the state inputs that decide availability. The
# context objects and their posted rows are passed in because they change
# per position/selection. Anything else menu::state reads is named here, so
# a menu build (which reads the same state) does not need to invalidate.
proc ::action::AskStamp {ctxObjects ctxMenus} {
	variable Registry
	variable RegistryVersion

	set parts [::list [dict size $Registry] $RegistryVersion]
	if {[info exists ::mc::langID]} { lappend parts L $::mc::langID }
	foreach {key cmd} {
		tab ::application::activeTab
		game ::menu::GameLoaded
		trial ::menu::TrialMode
		engine ::menu::EngineRunning
		over ::menu::GameOver
		variant ::menu::NormalVariant
		boardsetup ::menu::BoardSetupOpen
		dbopen ::menu::DbOpen
		dbwritable ::menu::DbWritable
		sortable ::menu::Sortable
		boardonly ::menu::BoardOnlyLayout
		base ::menu::CurrentBase
		panetwm ::menu::PaneTWM
	} {
		lappend parts $key [_stampOf $cmd]
	}
	if {[info exists ::menu::SupportURL]} { lappend parts support $::menu::SupportURL }
	if {[llength [info commands ::game::clipboard::entries]]} {
		lappend parts clip [::game::clipboard::entries]
	}
	if {[llength [info commands ::scidb::db::get]]} {
		if {![catch {::scidb::db::get variant?} dbvariant]} {
			lappend parts dbvariant $dbvariant
		}
	}
	if {[llength [info commands ::gamebar::size]] \
	 && [info exists ::application::pgn::Vars(gamebar)] \
	 && [winfo exists $::application::pgn::Vars(gamebar)]} {
		lappend parts gb [::gamebar::size $::application::pgn::Vars(gamebar)]
	}
	if {[info exists ::context::PredicateVersion]} {
		lappend parts predver $::context::PredicateVersion
	}
	if {[info exists ::context::MenusVersion]} {
		lappend parts menusver $::context::MenusVersion
	}
	if {[dict exists $ctxObjects C9] && [llength [info commands ::menu::PaneFloating]]} {
		set c9obj [dict get $ctxObjects C9]
		set c9uid [expr {[dict exists $c9obj paneUid] ? [dict get $c9obj paneUid] : ""}]
		set c9twm [expr {[dict exists $c9obj twm] ? [dict get $c9obj twm] : ""}]
		lappend parts c9float [::menu::PaneFloating $c9uid $c9twm]
	}
	if {[llength [info commands ::menu::NoHtmlReport]]} {
		lappend parts nohtml [::menu::NoHtmlReport]
	}
	# Each online control row follows ::online::view::Available, i.e. the
	# presence and state of its widget, which no variable below covers.
	if {[llength [info commands ::online::view::Available]] \
	 && [llength [info commands ::online::view::Current]]} {
		set onlineCurrent ""
		catch {set onlineCurrent [::online::view::Current]}
		lappend parts online $onlineCurrent
		if {$onlineCurrent ne ""} {
			foreach key {resign draw takeback abort claim flip live
				     accept decline analyse close chat autoqueen} {
				if {[catch {::online::view::Available $key} avail]} { set avail E }
				lappend parts online:$key $avail
			}
		}
	}
	if {[info exists ::capability::Overrides]} { lappend parts cap $::capability::Overrides }
	if {[info exists ::application::keyEditor::Options]} {
		lappend parts keys [lsort [array get ::application::keyEditor::Options]]
	}
	if {[info exists ::application::ai::Config(provider)]} {
		lappend parts provider $::application::ai::Config(provider)
	}
	if {[info exists ::application::ai::Config(model)]} {
		lappend parts model $::application::ai::Config(model)
	}
	if {[info exists ::comment::Vars(langSet)]} { lappend parts clangs $::comment::Vars(langSet) }
	if {[info exists ::comment::Vars(lang)]} { lappend parts clang $::comment::Vars(lang) }
	lappend parts live [AskLiveInputs $ctxObjects $ctxMenus]
	lappend parts ctx $ctxObjects $ctxMenus
	return $parts
}

# A row may be offered in the Ask list only when its bare call validates.
# The answer depends on the registered args spec alone, so cache it per id;
# register drops the entry when the record changes.
proc ::action::_bareRunnable {id} {
	variable BareCache
	if {[dict exists $BareCache $id]} { return [dict get $BareCache $id] }
	set ok 0
	if {![catch { ::action::validateArgs $id {} } validation]} {
		set ok [expr {[lindex $validation 0] ne "error"}]
	}
	dict set BareCache $id $ok
	return $ok
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

	if {$surface eq "asklist"} { return [AskRows $query] }

	set output {}
	set keyed {}
	foreach id [dict keys $Registry] {
		set record [get $id]

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
		} elseif {$surface eq "palette"} {
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
		if {$surface eq "dropdown" && [llength [info commands ::menu::state]]} {
			set state [::menu::state $id]
			set en [dict get $state enabled]
			set vis [dict get $state visible]
		}

		set label [markupLabel [dict get $record label]]
		set ac [labelAccel $id]

		set row [::list $id $label $ac $en $vis]
		lappend output $row
		if {$surface eq "dropdown"} { lappend keyed [::list $order $row] }
	}

	if {$surface eq "dropdown"} {
		set sorted [lsort -index 0 $keyed]
		set output {}
		foreach pair $sorted { lappend output [lindex $pair 1] }
	}
	return $output
}

# ----------------------------------------------------------------------
# Ask list rows. Same predicates as the drop-down and context menus, but
# every input that does not depend on the row is read once and every row
# record is resolved once. The row set must stay identical to the general
# path; tests/test_app_ask_arguments.tcl compares it with an independent
# menu::state + validateArgs reference.
# ----------------------------------------------------------------------
proc ::action::AskRows {query} {
	variable AskCachedStamp
	variable AskCachedRows
	variable AskBuilding

	# A fresh interpreter may lack the namespace initializer (see
	# _ObserveState); treat that as a cold cache rather than an error.
	if {![info exists AskCachedStamp]} { set AskCachedStamp "" }
	if {![info exists AskCachedRows]} { set AskCachedRows {} }

	# Context resolution reads live menus; its own state reads are not an
	# external change and must not invalidate the snapshot we are building.
	set AskBuilding 1
	set rc [catch {
		# Context rows belong to their current object. Resolve each context's
		# object and declared row ids cheaply first; only call ::context::MenuIds
		# (which evaluates per-row visibility via ::menu::state) on a cache miss.
		set ctxObjects [dict create]
		set ctxDeclared [dict create]
		set hasDeclared [llength [info commands ::context::DeclaredIds]]
		set hasMenuIds [llength [info commands ::context::MenuIds]]
		if {$hasMenuIds && [llength [info commands ::context::CurrentObject]]} {
			foreach cid {C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12} {
				if {![catch {set object [::context::CurrentObject $cid]}] \
				 && [dict size $object] && [::context::HasObject $cid $object]} {
					dict set ctxObjects $cid $object
					if {$hasDeclared} {
						dict set ctxDeclared $cid [::context::DeclaredIds $cid $object]
					} else {
						dict set ctxDeclared $cid [::context::MenuIds $cid $object]
					}
				}
			}
		}

		set stamp [AskStamp $ctxObjects $ctxDeclared]
		if {$stamp ne $AskCachedStamp} {
			set ctxIds {}
			set ctxMenus [dict create]
			if {$hasDeclared} {
				dict for {cid object} $ctxObjects {
					set ids [::context::MenuIds $cid $object]
					lappend ctxIds {*}$ids
					dict set ctxMenus $cid $ids
				}
			} else {
				set ctxMenus $ctxDeclared
				dict for {cid ids} $ctxDeclared { lappend ctxIds {*}$ids }
			}
			set rows [_BuildAskRows $ctxObjects $ctxMenus $ctxIds]
			set AskCachedRows $rows
			# A lazy registration during the build would make this
			# snapshot mixed; leave the cache cold in that case.
			if {[AskStamp $ctxObjects $ctxDeclared] eq $stamp} {
				set AskCachedStamp $stamp
			} else {
				set AskCachedStamp ""
			}
		} else {
			set rows $AskCachedRows
			# Opt-in diagnostic for future changes to menu::state itself.
			if {[info exists ::action::AskCacheCheck] && $::action::AskCacheCheck} {
				set ctxIds {}
				set ctxMenus [dict create]
				dict for {cid object} $ctxObjects {
					set ids [::context::MenuIds $cid $object]
					lappend ctxIds {*}$ids
					dict set ctxMenus $cid $ids
				}
				if {[_BuildAskRows $ctxObjects $ctxMenus $ctxIds] ne $rows} {
					set AskCachedStamp ""
					error "Ask cache disagrees with live menu state"
				}
			}
		}
		set rows
	} result]
	set AskBuilding 0
	if {$rc} { return -code error $result }
	set rows $result

	# With no query every row scores 0 and the stable sort keeps registry
	# order, so skip building and sorting one key per row.
	if {$query eq ""} {
		set output {}
		foreach row $rows {
			lappend output [lindex $row 0]
		}
		return $output
	}
	set q [string tolower $query]
	set qchars [split $q ""]
	set qlen [llength $qchars]
	set q0 [lindex $qchars 0]
	set output {}
	foreach row $rows {
		lassign $row outRow text visible
		set pos [string first $q $text]
		if {$pos >= 0} {
			set score [expr {1000 - [string length $text] - $pos}]
			if {$pos == 0} {
				incr score 400
			} elseif {[string first [string index $text [expr {$pos - 1}]] " _./-"] >= 0} {
				incr score 200
			}
		} elseif {$qlen <= 1} {
			continue
		} else {
			set first [string first $q0 $text]
			if {$first < 0} { continue }
			set i [expr {$first + 1}]
			set last $first
			set gaps 0
			set matched 1
			for {set k 1} {$k < $qlen} {incr k} {
				set j [string first [lindex $qchars $k] $text $i]
				if {$j < 0} { set matched 0; break }
				incr gaps [expr {$j - $last - 1}]
				set last $j
				set i [expr {$j + 1}]
			}
			if {!$matched} { continue }
			set score [expr {500 - $gaps - ($last - $first + 1) - [string length $text]}]
		}
		if {$score < 0} { continue }
		# The indexed text also carries the stored "&" markup and the docs,
		# so a longer label that merely starts with the query could beat an
		# exact visible label ("Help…" vs "Help"). Prefer the exact label.
		if {$visible ne "" && $q eq $visible} { incr score 500 }
		lappend output [::list $score $outRow]
	}
	set sorted [lsort -integer -decreasing -index 0 $output]
	set result {}
	foreach entry $sorted { lappend result [lindex $entry 1] }
	return $result
}

# Rebuild the state-qualified rows. This is the only place the Ask path
# asks ::menu::state; the same predicates therefore decide the menus and
# the Ask list, but a state change costs one pass rather than every key.
proc ::action::_BuildAskRows {ctxObjects ctxMenus ctxIds} {
	variable Registry
	variable AskStateMap
	variable AskMetaCache
	if {![info exists AskMetaCache]} { set AskMetaCache [dict create] }

	set ctxSet [dict create]
	foreach id $ctxIds { dict set ctxSet $id 1 }

	set hasMenu [expr {[llength [info commands ::menu::state]] ? 1 : 0}]
	set gameLoaded 1
	set onDb 0
	set boardOnly 0
	if {$hasMenu} {
		if {[llength [info commands ::menu::GameLoaded]]} { set gameLoaded [::menu::GameLoaded] }
		if {[llength [info commands ::menu::OnDatabaseTab]]} { set onDb [::menu::OnDatabaseTab] }
		if {[llength [info commands ::menu::BoardOnlyLayout]]} { set boardOnly [::menu::BoardOnlyLayout] }
	}

	set rows {}
	set stateMap [dict create]
	foreach id [dict keys $Registry] {
		set record [get $id]

		if {[dict get $record ai] eq "debug"} { continue }
		# The context menus' assistant row is not a runnable action.
		if {$id eq "context.ask"} { continue }

		set ctx [dict get $record context]
		set object {}
		if {[llength $ctx] && [dict get $record dropdown] eq ""} {
			if {![dict exists $ctxSet $id]} { continue }
			foreach cid $ctx {
				if {[dict exists $ctxObjects $cid]} {
					if {$cid eq "C5" && $id ni [dict get $ctxMenus $cid]} { continue }
					set object [dict get $ctxObjects $cid]
					break
				}
			}
		}

		if {$hasMenu} {
			set top ""
			if {[llength [info commands ::menu::TopOfRecord]]} {
				set top [::menu::TopOfRecord $record]
			}
			set pre [dict create record $record objectResolved 1 \
				gameLoaded $gameLoaded onDb $onDb boardOnly $boardOnly top $top]
			set state [::menu::state $id $object {} 0 $pre]
			set available [expr {[dict get $state visible] && [dict get $state enabled] ? 1 : 0}]
			dict set stateMap $id $available
			if {!$available} { continue }
		} else {
			set en 1
			set ep [dict get $record enabled]
			if {$ep ne ""} {
				if {[catch { uplevel #0 $ep } state]} { set en 0 } else { set en [expr {$state ? 1 : 0}] }
			}
			set vis 1
			set vp [dict get $record visible]
			if {$vp ne ""} {
				if {[catch { uplevel #0 $vp } state]} { set vis 0 } else { set vis [expr {$state ? 1 : 0}] }
			}
			if {!$en || !$vis} { continue }
		}

		if {![_bareRunnable $id]} { continue }

		set rawLabel [dict get $record label]
		set doc [dict get $record doc]
		set ks [dict get $record keys]
		if {[dict exists $AskMetaCache $id]} {
			lassign [dict get $AskMetaCache $id] cRaw cDoc cKs label visible searchLower
			set hit [expr {$cRaw eq $rawLabel && $cDoc eq $doc && $cKs eq $ks}]
		} else {
			set hit 0
		}
		if {!$hit} {
			set label [markupLabel $rawLabel]
			set plain [plainText $label]
			set visible [string tolower $plain]
			set search $plain
			if {$label ne $plain} { append search " $label" }
			append search " " $doc
			if {[llength $ks] >= 2 && [lindex $ks 1] ne ""} { append search " " [lindex $ks 1] }
			set searchLower [string tolower $search]
			dict set AskMetaCache $id [::list $rawLabel $doc $ks $label $visible $searchLower]
		}
		set ac [labelAccelRecord $id $record]
		lappend rows [::list [::list $id $label $ac 1 1] $searchLower $visible]
	}
	set AskStateMap $stateMap
	return $rows
}

# ----------------------------------------------------------------------
# invoke: run an action as a user click would (with confirmation gate).
# ----------------------------------------------------------------------
proc ::action::invoke {id args} {
	# Preserve native popup deferral without dropping the posted-state gate.
	if {[llength $args] == 1 && ![catch {dict exists [lindex $args 0] defer} has] \
	 && $has && [dict get [lindex $args 0] defer] eq "idle"} {
		after idle [::list ::action::invoke $id [dict remove [lindex $args 0] defer]]
		return ""
	}
	# Dispatch owns validation and the single formatted confirmation gate.
	if {[catch {Dispatch $id $args {} 1} result]} {return "error: $result"}
	return $result
}

# Typed operations for native HTML and drawable popups. Arguments contain
# identities and values only; executable callbacks never cross the API.
namespace eval ::action::html {}
proc ::action::html::Developer {} {
    if {$::action::DebugGate eq ""} {return 0}
    if {[catch {uplevel #0 $::action::DebugGate} enabled]} {return 0}
    return [expr {!!$enabled}]
}
proc ::action::html::Command {surface operation target {value {}} {key {}}} {
    set operations [dict create playercard {web font_inc font_dec trace_html trace_log} \
        crosstable {font_inc font_dec font_family font_select update save previous next close trace_html trace_log narrate player switcher workset browser overview pgn merge} \
        help {font_inc font_dec font_family font_select expand collapse prev next back forward load align index close} \
        tips {font_inc font_dec} info {font_inc font_dec recent_remove} merge {font_inc font_dec notation} report {font_family font_select size} overview {rotate load reload prev next first last} move {choice promotion} tree {choice} online {promotion}]
    if {![dict exists $operations $surface] || $operation ni [dict get $operations $surface]} {
        error "unknown HTML popup operation"
    }
    set id html.$surface.$operation
    if {![dict exists $::action::Registry $id]} {
        set ai [expr {[string match trace_* $operation] ? "debug" : "0"}]
        ::action::register $id [dict create label "HTML $surface: $operation" \
            handler [list ::action::html::Invoke $surface $operation] what $operation object {} \
            enabled [list ::action::html::Enabled $surface $operation] enabled-args 1 \
            args {{target {type string required 1}} {value {type string default {}}} {key {type string default {}}}} \
            ai $ai doc "Apply $operation to an existing $surface window."]
    }
    return [list ::action::run $id [dict create target $target value $value key $key]]
}
# Navigation uses the same live button as the dialog, at construction and
# again at dispatch. A retained command cannot bypass a newly reached end.
proc ::action::html::Enabled {surface operation arguments} {
    set target [dict get $arguments target]
    set button {}
    switch -- $surface {
        crosstable {
            if {$operation in {previous next}} {set button $target.$operation}
        }
        overview {
            if {$operation in {prev first next last}} {
                set direction [expr {$operation in {prev first} ? "previous" : "next"}]
                if {![winfo exists $target]} {return 0}
                set button [winfo toplevel $target].$direction
            }
        }
        help {
            if {$operation in {prev next back forward}} {
                if {![info exists ::help::Priv(dlg)] || $target ne $::help::Priv(dlg)
                    || ![info exists ::help::Priv(button:$operation)]} {return 0}
                set button $::help::Priv(button:$operation)
            }
        }
    }
    if {$button eq {}} {return 1}
    return [expr {[winfo exists $button] && [$button cget -state] ne "disabled"}]
}
proc ::action::html::Invoke {surface operation arguments} {
    set target [dict get $arguments target]
    set value [dict get $arguments value]
    set key [dict get $arguments key]
    if {![winfo exists $target]} {error "HTML popup window has closed"}
    if {$surface eq "playercard"} {
        if {![info exists ::playercard::Vars($key:arguments)]
            || [lindex $::playercard::Vars($key:arguments) 0] ne $target} {error "player card has closed"}
    }
    switch -- $surface {
        crosstable {if {![info exists ::crosstable::${target}::Vars(html)]} {error "tournament table has closed"}}
        help {if {![info exists ::help::Priv(dlg)] || $target ne $::help::Priv(dlg)} {error "help window has closed"}}
        tips - info - report {
            switch -- $surface {
                tips {set name ::tips::Priv(html)}
                info {set name ::application::information::Priv(html)}
                report {set name ::application::report::Priv(html)}
            }
            if {![info exists $name] || ![winfo exists [set $name]]
                || $target ne [winfo toplevel [set $name]]} {error "$surface window has closed"}
        }
    }
    if {[string match font_* $operation]} {
        switch -- $surface {
            playercard {set apply [list ::playercard::ChangeFontSize $target $key]}
            crosstable {set apply [list ::crosstable::ChangeFontSize $target]}
            help {set apply [list $::help::Priv(html) fontsize]}
            tips {set apply ::tips::ChangeFontSize}
            info {set apply ::application::information::Update}
            merge {
                ::font::ChangeFontSize merge {} [expr {$operation eq "font_inc" ? 1 : -1}]
                return
            }
        }
        switch -- $operation {
            font_inc - font_dec {
                set context [expr {$surface eq "info" ? "info" : $surface}]
                set size [::font::html::fontSize $context]
                if {($operation eq "font_inc" && $size >= [::html::maxFontSize])
                    || ($operation eq "font_dec" && $size <= [::html::minFontSize])} {return}
                ::font::html::ChangeFontSize $context $apply [expr {$operation eq "font_inc" ? 1 : -1}]
            }
            font_family - font_select {
                if {$surface eq "help"} {set apply ::help::ApplyFont} elseif {$surface eq "report"} {set apply ::application::report::ApplyFont} else {set apply [list ::crosstable::ApplyFont $target]}
                if {$operation eq "font_family"} {
                    if {$value ni [::font::html::defaultFonts] && $value ne [::font::html::userTextFont $surface]} {error "unknown font family"}
                    ::font::html::SetFont $surface $apply $value
                } else {
                    if {$value ni {0 1}} {error "unknown font selection"}
                    ::font::html::SelectFont $surface $target $value $apply
                }
            }
        }
        return
    }
    switch -- $surface {
        playercard {
            switch -- $operation {
                web {
                    menu .htmlVerifyWeb -tearoff 0
                    try {
                        ::playercard::buildWebMenu $target .htmlVerifyWeb [::scidb::db::playerInfo {*}[lrange $::playercard::Vars($key:arguments) 3 4] {*}[lindex $::playercard::Vars($key:arguments) 6]]
                        if {![::context::WebMenuHasUrl .htmlVerifyWeb $value]} {error "player link is unavailable"}
                    } finally {destroy .htmlVerifyWeb}
                    ::web::open $target $value
                }
                trace_html - trace_log {::playercard::ToggleTrace [string range $operation 6 end] $key}
            }
        }
        online {
            if {$value ni {q r b n} || ![::online::view::exists $target] || ![winfo ismapped $target.promo]} {error "no pending online promotion"}
            set ::online::view::${target}::V(promo) $value
        }
        move {
            set board $::application::board::board
            set menu [expr {$operation eq "promotion" ? "$board.popup_promotion" : "$board.popup_confirm"}]
            if {$target ne $menu} {error "unknown pending move menu"}
            set found 0
            for {set i 0} {$i <= [$menu index end]} {incr i} {
                if {[$menu type $i] ne "command"} {continue}
                set command [$menu entrycget $i -command]
                if {[lindex $command 1] eq "html.move.$operation" && [dict get [lindex $command 2] value] eq $value} {set found 1;break}
            }
            if {!$found} {error "choice is not offered"}
            if {$operation eq "promotion"} {set ::move::_promoted $value} else {::move::SetAction $value}
        }
        tree {
            if {$value ni {replace variation mainline trial exchange append load}} {error "unknown tree choice"}
            lassign $key row move
            ::application::tree::DoAction $target $row $move $value
        }
        report {
            if {$value ni {8 9 10 11 12 13 14}} {error "unknown report size"}
            ::application::report::SetSize $value
        }
        overview {
            if {![info exists ::overview::${target}::Vars(flip)]} {error "overview has closed"}
            switch -- $operation {
                rotate {::overview::RotateBoard $target}
                load {::overview::LoadGame $target}
                reload {::overview::NextGame $target 0}
                prev - next - first - last {::overview::GotoGame($operation) $target}
            }
        }
        info {::application::information::RemoveRecentFile $value}
        merge {
            if {$value ni $::notation::moveStyles} {error "unknown notation"}
            set ::pgn::merge::Options(style:move) $value
            ::merge::Refresh
        }
        help {
            switch -- $operation {
                expand {::help::ExpandAllItems}
                collapse {::help::CollapseAllItems}
                prev {::help::GotoTopic -1}
                next {::help::GotoTopic +1}
                back {::help::history::back}
                forward {::help::history::forward}
                load {
                    if {$value ni $::help::Priv(recent)} {error "unknown recent topic"}
                    ::help::Load [::help::FullPath $value]
                }
                align {
                    if {$value ni {left justify}} {error "unknown alignment"}
                    set ::help::Options(textalign) $value
                    $::help::Priv(html) configure -textalign $value -showhyphens [expr {$value eq "justify"}]
                }
                index {::help::ToggleIndex}
                close {::help::Destroy}
            }
        }
        crosstable {
            switch -- $operation {
                update {::crosstable::UpdateContent $target}
                save {::crosstable::SaveAsHTML $target}
                previous - next - close { $target.$operation invoke }
                trace_html - trace_log {::crosstable::ToggleTrace $target [string range $operation 6 end]}
                narrate {::crosstable::NarrateEvent $target}
                player {::crosstable::ShowPlayerCard $target $value}
                switcher {::crosstable::OpenPlayerGamesInSwitcher $target $value}
                workset {::crosstable::SavePlayerGamesWorkingSet $target $value}
                browser - overview - pgn {::crosstable::Open $target $operation $value}
                merge {
                    upvar #0 ::crosstable::${target}::Vars vars
                    ::gamebar::mergeGame $target [list $vars(base) $vars(variant) $vars(viewId) $value]
                }
            }
        }
    }
}
