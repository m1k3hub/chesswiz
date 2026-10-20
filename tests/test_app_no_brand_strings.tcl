# ======================================================================
# Scidb App Test — brand and competitor names (ChessBase, Fritz, etc.)
# and the name "CQL" must never appear in user-facing or assistant model-
# facing strings (Rule from AGENTS.md).
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::nobrands {
	variable BannedPattern {(?i)chessbase|fritz|\mcql\M}

	proc checkText {source id field text} {
		variable BannedPattern
		if {[regexp $BannedPattern $text match]} {
			return [list $source $id $field $match $text]
		}
		return {}
	}

	proc checkJsonProperties {source id jsonStr} {
		set hits {}
		if {[catch { package require json }]} { return $hits }
		if {[catch { ::json::json2dict $jsonStr } schema]} { return $hits }
		if {[dict exists $schema properties]} {
			set props [dict get $schema properties]
			dict for {pName pDef} $props {
				if {[dict exists $pDef description]} {
					set hit [checkText $source $id "property:$pName:description" [dict get $pDef description]]
					if {[llength $hit]} { lappend hits $hit }
				}
			}
		}
		return $hits
	}
}

tcltest::test no-brands-in-action-list {registered actions contain no competitor product names or CQL in user/model facing text} -body {
	set violations {}
	foreach id [::action::list] {
		set rec [::action::get $id]
		foreach field {label what doc toolmenu dropdown menu} {
			if {[dict exists $rec $field]} {
				set val [dict get $rec $field]
				# Check the direct value
				set hit [::scidb::test::nobrands::checkText "action" $id $field $val]
				if {[llength $hit]} { lappend violations $hit }

				# If it's a resolved mc variable
				if {$field in {label what} && [string match "::*" $val]} {
					catch {
						set resolved [set $val]
						set hit [::scidb::test::nobrands::checkText "action-resolved" $id "$field($val)" $resolved]
						if {[llength $hit]} { lappend violations $hit }
					}
				}
				# If it's a label, also check displayLabel
				if {$field eq "label"} {
					set disp [::action::displayLabel $val]
					if {$disp ne $val} {
						set hit [::scidb::test::nobrands::checkText "action-displayLabel" $id $field $disp]
						if {[llength $hit]} { lappend violations $hit }
					}
				}
			}
		}
		if {[dict exists $rec args]} {
			set spec [dict get $rec args]
			foreach param $spec {
				set pName [lindex $param 0]
				set pOpts [lindex $param 1]
				if {[dict exists $pOpts description]} {
					set pDesc [dict get $pOpts description]
					set hit [::scidb::test::nobrands::checkText "action-args" $id "param:$pName:description" $pDesc]
					if {[llength $hit]} { lappend violations $hit }
				}
			}
		}
		if {[dict exists $rec schema] && [dict get $rec schema] ne ""} {
			set hits [::scidb::test::nobrands::checkJsonProperties "action-schema" $id [dict get $rec schema]]
			foreach h $hits { lappend violations $h }
		}
	}
	set violations
} -result {}

tcltest::test no-brands-in-assistant-tools {assistant tool table contains no competitor names or CQL} -body {
	set violations {}
	if {[info exists ::application::assistant::Actions]} {
		dict for {name entry} $::application::assistant::Actions {
			lassign $entry confirm debug what description parameters handler
			set hit [::scidb::test::nobrands::checkText "assistant-action" $name "what" $what]
			if {[llength $hit]} { lappend violations $hit }

			set hit [::scidb::test::nobrands::checkText "assistant-action" $name "description" $description]
			if {[llength $hit]} { lappend violations $hit }

			set hits [::scidb::test::nobrands::checkJsonProperties "assistant-action" $name $parameters]
			foreach h $hits { lappend violations $h }
		}
	}
	set violations
} -result {}

tcltest::test no-brands-in-assistant-prompts {assistant system prompts and menu hints contain no competitor names or CQL} -body {
	set violations {}
	foreach var {
		::application::assistant::System
		::application::assistant::DebugSystem
		::application::assistant::ResultProseInstructions
	} {
		if {[info exists $var]} {
			set hit [::scidb::test::nobrands::checkText "assistant-prompt" $var "content" [set $var]]
			if {[llength $hit]} { lappend violations $hit }
		}
	}
	if {[info exists ::application::assistant::ToolMenu]} {
		dict for {tool path} $::application::assistant::ToolMenu {
			set hit [::scidb::test::nobrands::checkText "assistant-toolmenu" $tool "path" $path]
			if {[llength $hit]} { lappend violations $hit }
		}
	}
	set violations
} -result {}

tcltest::cleanupTests
