# ======================================================================
# ::application::assistant -- closed-set tool-argument filling (System One)
# ======================================================================
# The language model emits a tool call's arguments as free JSON. For an
# argument whose values are a closed set (a JSON-schema `enum`), a bounded
# Choice question is more reliable than the model's emitted value: measured
# against granite4.2:3b/8b and deepseek-v4.1-flash (docs/TYPESAFE_COOKBOOK_REVIEW.md
# #4), every one of them made enum-argument errors (4-12%), including a
# systematic "opponent colour" inversion, while the classifier made 0/26 and
# its answer is always a value the schema allows.
#
# This module corrects the closed-set arguments of a tool call before it runs;
# anything the classifier does not confidently fill keeps the model's value,
# and a request it does not need (off, no server, no enum args) is untouched.
# It never invents a value: the options ARE the schema's enum members.
#
# Modes (SCIDB_AI_ARGS):
#   off      leave the model's arguments alone
#   shadow   compute the correction and log it; run the model's arguments
#            (default: active must beat the model on labelled requests first)
#   active   use the corrected arguments; a tool still runs through
#            runTool, so CheckArgs, the confirm gate and the tool log all run
#
# Environment: SCIDB_AI_ARGS, SCIDB_AI_ARGS_MIN_CONFIDENCE (0.7).
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-assistant-args
}

package require Tcl 8.5

namespace eval application {
namespace eval assistant {

variable ArgsMode shadow
variable ArgsThreshold 0.7

if {[info exists ::env(SCIDB_AI_ARGS)] && $::env(SCIDB_AI_ARGS) in {off shadow active}} {
	set ArgsMode $::env(SCIDB_AI_ARGS)
}
if {[info exists ::env(SCIDB_AI_ARGS_MIN_CONFIDENCE)]
 && [string is double -strict $::env(SCIDB_AI_ARGS_MIN_CONFIDENCE)]} {
	set ArgsThreshold $::env(SCIDB_AI_ARGS_MIN_CONFIDENCE)
}

} ;# namespace assistant
} ;# namespace application


# The closed-set arguments of a tool, from its JSON schema: arg -> enum values.
proc ::application::assistant::enumArgs {name} {
	variable Actions

	if {![dict exists $Actions $name]} { return {} }
	if {[catch { package require json }]} { return {} }

	lassign [dict get $Actions $name] _ _ _ _ parameters _
	if {[catch { set schema [::json::json2dict $parameters] }]} { return {} }
	set props [expr {[dict exists $schema properties] ? [dict get $schema properties] : {}}]
	set out {}
	dict for {arg def} $props {
		if {[dict exists $def enum]} { dict set out $arg [dict get $def enum] }
	}
	return $out
}


# The schema's own description of each argument: arg -> text. It says whose
# value is meant ("the colour the opponent will play"), which the argument
# name alone does not: without it the classifier answers the user's colour.
proc ::application::assistant::argDescriptions {name} {
	variable Actions

	if {![dict exists $Actions $name]} { return {} }
	if {[catch { package require json }]} { return {} }

	lassign [dict get $Actions $name] _ _ _ _ parameters _
	if {[catch { set schema [::json::json2dict $parameters] }]} { return {} }
	set props [expr {[dict exists $schema properties] ? [dict get $schema properties] : {}}]
	set out {}
	dict for {arg def} $props {
		if {[dict exists $def description]} { dict set out $arg [dict get $def description] }
	}
	return $out
}


# The current request: the last user message.
proc ::application::assistant::RequestText {} {
	variable Priv

	if {![info exists Priv(messages)] || ![llength $Priv(messages)]} { return "" }
	for {set i [expr {[llength $Priv(messages)] - 1}]} {$i >= 0} {incr i -1} {
		set msg [lindex $Priv(messages) $i]
		if {[dict exists $msg role] && [dict get $msg role] eq "user"} {
			return [dict get $msg content]
		}
	}
	return ""
}


proc ::application::assistant::LogArgsLine {line} {
	variable ErrorLogFile

	if {![info exists ErrorLogFile] || ![string length $ErrorLogFile]} { return }
	set dir [file dirname $ErrorLogFile]
	file mkdir $dir
	set file [file join $dir args-shadow.log]
	if {[file exists $file] && [file size $file] > 1048576} {
		catch { file delete -force $file.1 }
		catch { file rename $file $file.1 }
	}
	set chan [open $file a]
	fconfigure $chan -encoding utf-8
	puts $chan $line
	close $chan
	return
}


# Correct the closed-set arguments of one tool call from the request. Returns
# the corrected cargs; an argument the classifier does not fill, or does not
# offer, keeps the model's value.
proc ::application::assistant::correctArgs {name cargs} {
	variable ArgsMode
	variable ArgsThreshold

	if {$ArgsMode eq "off"} { return $cargs }
	if {[llength [info commands ::ai::systemone::chooseManySync]] == 0} { return $cargs }
	if {![::ai::systemone::enabled]} { return $cargs }

	set enums [enumArgs $name]
	if {![dict size $enums]} { return $cargs }
	set request [RequestText]
	if {$request eq ""} { return $cargs }

	set descriptions [argDescriptions $name]
	set questions {}
	dict for {arg values} $enums {
		set desc [expr {[dict exists $descriptions $arg] ? [dict get $descriptions $arg] : ""}]
		set criteria [dict create none "the request does not say"]
		if {$desc ne ""} {
			# the description is the question: "the colour the opponent will
			# play" is not read as the user's own colour
			set what "According to the request, what is $desc?"
			foreach value $values { dict set criteria $value "$desc is $value" }
		} else {
			set what "Which $arg does the request specify?"
			foreach value $values { dict set criteria $value "the request means $arg=$value" }
		}
		dict set questions $arg [dict create type choice \
			instructions "$what Answer none if it does not say." \
			criteria $criteria]
	}

	set picked [::ai::systemone::chooseManySync tool_args $request $questions \
		-threshold $ArgsThreshold]

	set out $cargs
	dict for {arg label} $picked {
		if {$label eq "none"} { continue }
		if {![dict exists $enums $arg] || $label ni [dict get $enums $arg]} { continue }
		set had [expr {[dict exists $cargs $arg] ? [dict get $cargs $arg] : ""}]
		if {$ArgsMode eq "shadow"} {
			LogArgsLine "$name.$arg model=$had classifier=$label"
			continue
		}
		dict set out $arg $label
	}
	return $out
}

# vi:set ts=3 sw=3:
