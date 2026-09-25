# ======================================================================
# ::application::ai::models -- choose the model of the AI features.
#
# Extras > "AI: Choose Model" lists the models of the local Ollama server
# (/api/tags), marks cloud models and those that support tool calling
# (which the assistant needs), and saves the choice in the options file
# (::application::ai::Settings). A command-line flag or environment
# variable still overrides the saved choice for its session; the dialog
# says so.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-ai-models
}

package require Tcl 8.5
package require Tk 8.5

namespace eval application {
namespace eval ai {
namespace eval models {
namespace eval mc {

set Title			"AI Model"
set Model			"Model"
set Where			"Runs"
set Tools			"Tools"
set Local			"locally"
set Cloud			"in the cloud"
set Yes				"yes"
set No				"no"
set Name				"Model name:"
set Fetching		"Asking Ollama for its models..."
set Found			"%d models; the assistant needs one with tool support."
set Unreachable	"Ollama is not reachable (%s). You can still enter a model name."
set NoTools			"This model does not support tool calling: the assistant will not work with it."
set Overridden		"The %s given by %s (%s) is used this session; the choice here is saved for later sessions."
set Option			"the command line"
set Environment	"the environment"

} ;# namespace mc

array set Priv {
	dialog	{}
	models	{}
	name		{}
}

} ;# namespace models
} ;# namespace ai
} ;# namespace application


proc ::application::ai::models::show {{parent .application}} {
	variable Priv
	variable mc

	set dlg $parent.__aimodels__
	if {[winfo exists $dlg]} {
		raise $dlg
		return $dlg
	}
	set Priv(dialog) $dlg
	# the saved choice (an override is shown separately)
	set Priv(name) $::application::ai::Settings(model)

	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm protocol $dlg WM_DELETE_WINDOW [namespace code Close]
	bind $dlg <Escape> [namespace code Close]

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	set list [ttk::frame $top.list]
	set tree [ttk::treeview $list.tree -columns {where tools} -height 10 -selectmode browse]
	$tree heading #0 -text $mc::Model -anchor w
	$tree heading where -text $mc::Where -anchor w
	$tree heading tools -text $mc::Tools -anchor w
	$tree column #0 -width 280
	$tree column where -width 110 -stretch no
	$tree column tools -width 60 -stretch no
	$tree tag configure notools -foreground #808080
	ttk::scrollbar $list.vs -orient vertical -command [list $tree yview]
	$tree configure -yscrollcommand [list $list.vs set]
	pack $list.vs -side right -fill y
	pack $tree -side left -fill both -expand yes
	pack $list -fill both -expand yes

	set entry [ttk::frame $top.entry]
	ttk::label $entry.label -text $mc::Name
	ttk::entry $entry.name -textvariable [namespace current]::Priv(name)
	pack $entry.label -side left
	pack $entry.name -side left -fill x -expand yes -padx [list $::theme::padx 0]
	pack $entry -fill x -pady [list $::theme::pady 0]

	ttk::label $top.status -wraplength 460 -justify left
	ttk::label $top.override -wraplength 460 -justify left -foreground darkred
	pack $top.status -fill x -pady [list $::theme::pady 0]
	pack $top.override -fill x

	::widget::dialogButtons $dlg {ok cancel}
	$dlg.ok configure -command [namespace code Apply]
	$dlg.cancel configure -command [namespace code Close]

	bind $tree <<TreeviewSelect>> [namespace code Selected]
	bind $tree <Double-Button-1> [namespace code Apply]
	bind $entry.name <Return> [namespace code Apply]

	set Priv(tree) $tree
	set Priv(status) $top.status
	set Priv(override) $top.override
	ShowOverride

	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	$Priv(status) configure -text $mc::Fetching
	update idletasks
	Fill
	focus $entry.name
	return $dlg
}


proc ::application::ai::models::Fill {} {
	variable Priv
	variable mc

	set tree $Priv(tree)
	$tree delete [$tree children {}]

	if {[catch { ::ai::provider::ollamaModels } models]} {
		set Priv(models) {}
		$Priv(status) configure -text [format $mc::Unreachable $models]
		return
	}
	set Priv(models) $models

	foreach m $models {
		set name [dict get $m name]
		set tools [dict get $m tools]
		$tree insert {} end -id $name -text $name \
			-values [list \
				[expr {[dict get $m remote] ? $mc::Cloud : $mc::Local}] \
				[expr {$tools ? $mc::Yes : $mc::No}]] \
			-tags [expr {$tools ? "" : "notools"}]
	}
	if {[$tree exists $Priv(name)]} {
		$tree selection set [list $Priv(name)]
		$tree see $Priv(name)
	}
	$Priv(status) configure -text [format $mc::Found [llength $models]]
}


proc ::application::ai::models::Selected {} {
	variable Priv
	variable mc

	set sel [$Priv(tree) selection]
	if {![llength $sel]} { return }
	set Priv(name) [lindex $sel 0]

	set m [lsearch -inline -index 1 $Priv(models) $Priv(name)]
	if {[llength $m] && ![dict get $m tools]} {
		$Priv(status) configure -text $mc::NoTools
	} else {
		$Priv(status) configure -text [format $mc::Found [llength $Priv(models)]]
	}
}


proc ::application::ai::models::ShowOverride {} {
	variable Priv
	variable mc

	set text ""
	foreach key {model provider} {
		lassign [::application::ai::setting $key] source value
		if {$source ne "settings"} {
			set by [expr {$source eq "option" ? $mc::Option : $mc::Environment}]
			set text [format $mc::Overridden $key $by $value]
			break
		}
	}
	$Priv(override) configure -text $text
}


proc ::application::ai::models::Apply {} {
	variable Priv

	set name [string trim $Priv(name)]
	if {![string length $name]} { return }
	# the assistant's tool loop only speaks the Ollama chat API
	::application::ai::choose ollama $name
	Close
}


proc ::application::ai::models::Close {} {
	variable Priv

	if {[winfo exists $Priv(dialog)]} { destroy $Priv(dialog) }
	set Priv(dialog) {}
}

# vi:set ts=3 sw=3:
