# ======================================================================
# ::application::ai::models -- choose the models of the AI features.
#
# Extras > "AI: Choose Model" has two sections. The first lists the models
# of the local Ollama server (/api/tags), marks cloud models and those that
# support tool calling (which the assistant needs). The second picks the
# System One classifier backend (::ai::systemone): kev, simple-jev and plumb
# serve the /v1/systemone contract on this machine, jev (TypeSafe's Jev)
# runs in the cloud through Vercel's AI Gateway, and "off" leaves everything
# to the language model.
#
# Both choices are saved in the options file (::application::ai::Settings,
# keys model and classifier). A command-line flag or environment variable
# still overrides the saved choice for its session; the dialog says so.
#
# The model list also shows what the machine can run (blank when the rules
# module tcl/ai-modelfit.tcl is not loaded): for every local model with a
# known size the "Fit" column names the largest quant that fits and where
# it goes (gpu or cpu; "none" for a model that fits nowhere), computed once
# from the machine's RAM and VRAM. This is advice only -- it never changes
# the choice.
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

set Title			"AI Models"
set LanguageModel	"Language model (Ollama)"
set Classifier		"System One classifier"
set Model			"Model"
set Where			"Runs"
set Tools			"Tools"
set Fit				"Fit"
set Local			"locally"
set Cloud			"in the cloud"
set Yes				"yes"
set No				"no"
set NoSize			"no size"
set Memory			"Machine: %d MB RAM, %d MB VRAM"
set Name				"Model name:"
set Fetching		"Asking Ollama for its models..."
set Found			"%d models; the assistant needs one with tool support."
set Unreachable	"Ollama is not reachable (%s). You can still enter a model name."
set NoTools			"This model does not support tool calling: the assistant will not work with it."
set Overridden		"The %s given by %s (%s) is used this session; the choice here is saved for later sessions."
set Option			"the command line"
set Environment	"the environment"

set Off				"off"
set OffNote			"No classifier: the language model classifies everything."
set Auto			"auto (local)"
set AutoNote		"Automatic: use the first local server that answers (kev, then simple-jev, then plumb). Off if none is running."
set ClassifierNote	"kev, simple-jev and plumb run on this machine; jev is TypeSafe's Jev in the cloud (Vercel AI Gateway)."
set Recommended	"recommended on this machine (best on the calibration battery)"
set PlumbNote		"Plumb-4B: scripts/serve-plumb-classifier.sh downloads it from Hugging Face and serves it on port 8090."
set KeyNote			"needs %s in the environment"

} ;# namespace mc

array set Priv {
	generation 0
	probe {}
	dialog	{}
	models	{}
	name		{}
	fit		{}
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
	incr Priv(generation)
	set Priv(dialog) $dlg
	# the saved choices (an override is shown separately)
	set Priv(name) $::application::ai::Settings(model)
	set Priv(classifier) [lindex [::application::ai::setting classifier] 1]
	# the vercel preset is the same server as jev; the dialog has one row

	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm protocol $dlg WM_DELETE_WINDOW [namespace code Close]
	bind $dlg <Escape> [namespace code Close]

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	### language model (Ollama) ############################################
	ttk::label $top.language -text $mc::LanguageModel
	pack $top.language -anchor w

	set list [ttk::frame $top.list]
	# the fit advice needs the rules module (tcl/ai-modelfit.tcl); without
	# it the list is exactly the model/where/tools list it always was
	set haveFit [expr {[llength [info commands ::ai::modelfit::memory]]
		&& [llength [info commands ::ai::modelfit::recommend]]}]
	set columns {where tools}
	if {$haveFit} { lappend columns fit }
	set tree [ttk::treeview $list.tree -columns $columns -height 8 -selectmode browse]
	$tree heading #0 -text $mc::Model -anchor w
	$tree heading where -text $mc::Where -anchor w
	$tree heading tools -text $mc::Tools -anchor w
	$tree column #0 -width 280
	$tree column where -width 110 -stretch no
	$tree column tools -width 60 -stretch no
	if {$haveFit} {
		$tree heading fit -text $mc::Fit -anchor w
		$tree column fit -width 140 -stretch no
	}
	$tree tag configure notools -foreground #808080
	ttk::scrollbar $list.vs -orient vertical -command [list $tree yview]
	$tree configure -yscrollcommand [list $list.vs set]
	pack $list.vs -side right -fill y
	pack $tree -side left -fill both -expand yes
	pack $list -fill both -expand yes

	if {$haveFit} {
		set Priv(fit) {}
		ttk::label $top.memory -text "" -justify left
		pack $top.memory -anchor w -pady [list $::theme::pady 0]
		set Priv(memory) $top.memory
	}

	set entry [ttk::frame $top.entry]
	ttk::label $entry.label -text $mc::Name
	ttk::entry $entry.name -textvariable [namespace current]::Priv(name)
	pack $entry.label -side left
	pack $entry.name -side left -fill x -expand yes -padx [list $::theme::padx 0]
	pack $entry -fill x -pady [list $::theme::pady 0]

	ttk::label $top.status -wraplength 460 -justify left
	pack $top.status -fill x -pady [list $::theme::pady 0]

	### system one classifier ###############################################
	set haveClassifier [llength [info commands ::ai::systemone::backends]]
	if {$haveClassifier} {
		ttk::separator $top.sep
		pack $top.sep -fill x -pady $::theme::pady
		ttk::label $top.classifierHead -text $mc::Classifier
		pack $top.classifierHead -anchor w

		set clist [ttk::frame $top.clist]
		set ctree [ttk::treeview $clist.tree -columns {where model} -height 6 -selectmode browse]
		$ctree heading #0 -text $mc::Classifier -anchor w
		$ctree heading where -text $mc::Where -anchor w
		$ctree heading model -text $mc::Model -anchor w
		$ctree column #0 -width 120 -stretch no
		$ctree column where -width 110 -stretch no
		$ctree column model -width 260
		$ctree column #0 -minwidth 120
		ttk::scrollbar $clist.vs -orient vertical -command [list $ctree yview]
		$ctree configure -yscrollcommand [list $clist.vs set]
		pack $clist.vs -side right -fill y
		pack $ctree -side left -fill both -expand yes
		pack $clist -fill both -expand yes

		ttk::label $top.cstatus -wraplength 460 -justify left
		pack $top.cstatus -fill x -pady [list $::theme::pady 0]

		bind $ctree <<TreeviewSelect>> [namespace code SelectedClassifier]
		bind $ctree <Double-Button-1> [namespace code DeferredApply]
		set Priv(ctree) $ctree
		set Priv(cstatus) $top.cstatus
	}

	ttk::label $top.override -wraplength 460 -justify left -foreground darkred
	pack $top.override -fill x

	::widget::dialogButtons $dlg {ok cancel}
	$dlg.ok configure -command [namespace code Apply]
	$dlg.cancel configure -command [namespace code Close]

	bind $tree <<TreeviewSelect>> [namespace code Selected]
	bind $tree <Double-Button-1> [namespace code DeferredApply]
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
	if {$haveClassifier} { FillClassifiers }
	focus $entry.name
	return $dlg
}


proc ::application::ai::models::Fill {} {
	variable Priv
	::ai::provider::ollamaModelsAsync [namespace code [list OnModels $Priv(generation)]]
}


proc ::application::ai::models::Current {generation} {
	variable Priv
	return [expr {$generation == $Priv(generation) && $Priv(dialog) ne {} && [winfo exists $Priv(dialog)]}]
}


proc ::application::ai::models::OnModels {generation result} {
	variable Priv
	variable mc
	if {![Current $generation]} { return }
	if {![dict get $result ok]} {
		set Priv(models) {}
		set Priv(fit) {}
		$Priv(status) configure -text [format $mc::Unreachable [dict get $result error]]
		return
	}
	set Priv(models) [dict get $result models]
	# RAM-only advice is cheap and useful while the GPU query is pending.
	set memory {ram_mb 0 vram_mb 0}
	if {[llength [info commands ::ai::modelfit::memory]]} {
		set memory [::ai::modelfit::memory -gpu {}]
	}
	RenderModels $memory
	if {[llength [info commands ::ai::modelfit::memoryAsync]]} {
		set Priv(probe) [::ai::modelfit::memoryAsync [namespace code [list OnMemory $generation]]]
	}
}


proc ::application::ai::models::OnMemory {generation memory} {
	variable Priv
	if {![Current $generation]} { return }
	set Priv(probe) {}
	RenderModels $memory
}


proc ::application::ai::models::RenderModels {memory} {
	variable Priv
	variable mc
	set tree $Priv(tree)
	$tree delete [$tree children {}]
	set models $Priv(models)
	set Priv(fit) [FitAdvice $models $memory]
	foreach m $models {
		set name [dict get $m name]
		set tools [dict get $m tools]
		set values [list \
			[expr {[dict get $m remote] ? $mc::Cloud : $mc::Local}] \
			[expr {$tools ? $mc::Yes : $mc::No}]]
		if {[dict exists $Priv(fit) $name]} {
			lappend values [dict get $Priv(fit) $name]
		} elseif {[llength [info commands ::ai::modelfit::recommend]]} {
			lappend values $mc::NoSize
		}
		$tree insert {} end -id $name -text $name -values $values \
			-tags [expr {$tools ? "" : "notools"}]
	}
	if {[$tree exists $Priv(name)]} {
		$tree selection set [list $Priv(name)]
		$tree see $Priv(name)
	}
	$Priv(status) configure -text [format $mc::Found [llength $models]]
}


# ----------------------------------------------------------------------
# The fit advice for the listed models (audit E2): a dict name -> "quant
# (placement)" for every local model whose size is known, plus the machine
# line (RAM/VRAM in MiB). Empty when tcl/ai-modelfit.tcl is not loaded, so
# the caller degrades to the list it always showed. Read-only: the choice
# the user makes is untouched.
# ----------------------------------------------------------------------

proc ::application::ai::models::FitAdvice {models {memory {}}} {
	variable mc
	variable Priv

	if {[llength [info commands ::ai::modelfit::memory]] == 0
	 || [llength [info commands ::ai::modelfit::recommend]] == 0} {
		return {}
	}

	# the candidates carry {name params_b}; a cloud model and one without
	# a readable parameter size are not candidates and keep the "no size"
	# note in the Fit column
	set candidates {}
	foreach m $models {
		if {[dict get $m remote]} { continue }
		set params [ParamsB $m]
		if {$params <= 0.0} { continue }
		lappend candidates [dict create name [dict get $m name] params_b $params]
	}

	if {[info exists Priv(memory)] && [winfo exists $Priv(memory)]} {
		$Priv(memory) configure -text ""
	}

	if {![llength $memory] && [catch { ::ai::modelfit::memory } memory]} { set memory {} }
	if {[llength $memory]
	 && [info exists Priv(memory)] && [winfo exists $Priv(memory)]} {
		$Priv(memory) configure -text [format $mc::Memory \
			[dict get $memory ram_mb] [dict get $memory vram_mb]]
	}

	if {![llength $candidates]} { return {} }
	if {[catch { ::ai::modelfit::recommend $memory $candidates } rows]} {
		return {}
	}
	set advice {}
	foreach row $rows {
		dict set advice [dict get $row name] [format "%s (%s)" \
			[dict get $row quant] [dict get $row placement]]
	}
	return $advice
}


# The parameter count in billions of a model from /api/tags: the named
# details.parameter_size ("8.0B") when the server sends one, else the size
# tag of the name ("qwen3:8b" -> 8). 0 when there is nothing to read (a
# cloud model, a name without a size tag) -- no candidate, not an error.
proc ::application::ai::models::ParamsB {m} {
	set text ""
	foreach key {parameter_size parameterSize} {
		if {[dict exists $m details $key]} { set text [dict get $m details $key]; break }
	}
	if {![string length $text]} {
		set name [dict get $m name]
		foreach token [split $name ":-"] {
			if {[regexp {^([0-9]+(?:\.[0-9]+)?)([bBmM])$} $token -> value unit]} {
				set text $value
				if {[string toupper $unit] eq "M"} { set text [expr {$value / 1000.0}] }
				break
			}
		}
	}
	if {![string length $text]} { return 0.0 }
	# "8.0B" -> 8.0, "7B" -> 7.0; a bare number is taken as billions
	if {[scan $text "%f" value] != 1 || $value <= 0.0} { return 0.0 }
	if {[regexp -nocase {m$} [string trim $text]]} { set value [expr {$value / 1000.0}] }
	return $value
}


# The classifier rows: "off" plus one row per backend. The "vercel" preset
# is the same server as "jev" and stays selectable only through the
# environment, not through a second row.
proc ::application::ai::models::FillClassifiers {} {
	variable Priv
	variable mc

	set tree $Priv(ctree)
	$tree delete [$tree children {}]
	$tree insert {} end -id auto -text $mc::Auto -values [list $mc::Local ""]
	$tree insert {} end -id off -text $mc::Off -values [list "" ""]

	foreach b [::ai::systemone::backends] {
		set name [dict get $b name]
		if {$name eq "vercel"} { continue }
		set where [expr {[dict get $b local] ? $mc::Local : $mc::Cloud}]
		set model [dict get $b model]
		if {$name eq "typesafe" && [info exists ::env(TYPESAFE_API_KEY)]
		 && [string length $::env(TYPESAFE_API_KEY)]} {
			append model "  ($mc::Recommended)"
		}
		$tree insert {} end -id $name -text $name \
			-values [list $where $model] \
			-tags [expr {[dict get $b local] ? "" : "cloud"}]
	}

	if {$Priv(classifier) eq "vercel"} { set Priv(classifier) jev }
	if {[string length $Priv(classifier)] && [$tree exists $Priv(classifier)]} {
		$tree selection set [list $Priv(classifier)]
		$tree see $Priv(classifier)
	} else {
		$tree selection set [list off]
	}
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


proc ::application::ai::models::SelectedClassifier {} {
	variable Priv
	variable mc

	set sel [$Priv(ctree) selection]
	if {![llength $sel]} { return }
	set Priv(classifier) [lindex $sel 0]

	set text ""
	if {$Priv(classifier) eq "off"} {
		set text $mc::OffNote
	} elseif {$Priv(classifier) eq "auto"} {
		set text $mc::AutoNote
	} elseif {$Priv(classifier) eq "plumb"} {
		set text $mc::PlumbNote
	}
	# Read the row from the backend table. Configuring the backend and
	# restoring it through applySettings would run the auto-discovery,
	# whose blocking connects and probe requests freeze the GUI.
	foreach b [::ai::systemone::backends] {
		if {[dict get $b name] ne $Priv(classifier)} { continue }
		if {$text eq ""} {
			set text [format "%s (%s at %s)" $Priv(classifier) \
				[dict get $b model] [dict get $b endpoint]]
		}
		set key [dict get $b key]
		if {![info exists ::env($key)] || ![string length $::env($key)]} {
			append text [expr {[string length $text] ? " " : ""}] [format $mc::KeyNote $key]
		}
		break
	}
	$Priv(cstatus) configure -text $text
}


proc ::application::ai::models::ShowOverride {} {
	variable Priv
	variable mc

	set text ""
	foreach key {model provider classifier} {
		lassign [::application::ai::setting $key] source value
		if {$source ne "settings"} {
			set by [expr {$source eq "option" ? $mc::Option : $mc::Environment}]
			set text [format $mc::Overridden $key $by $value]
			break
		}
	}
	$Priv(override) configure -text $text
}


# A double-click closes the dialog; Tk's own treeview DoubleClick class
# binding still runs after the widget binding, so applying immediately
# destroys the widget underneath it ("invalid command name ...tree").
# Defer past the click.
proc ::application::ai::models::DeferredApply {} {
	variable Priv

	if {![winfo exists $Priv(dialog)]} { return }
	after idle [namespace code Apply]
	return
}


proc ::application::ai::models::Apply {} {
	variable Priv

	set name [string trim $Priv(name)]
	if {![string length $name]} { return }
	# the assistant's tool loop only speaks the Ollama chat API
	::application::ai::choose ollama $name
	if {[info exists Priv(ctree)] && [string length $Priv(classifier)]} {
		::application::ai::chooseClassifier $Priv(classifier)
	}
	Close
}


proc ::application::ai::models::Close {} {
	variable Priv
	incr Priv(generation)
	if {$Priv(probe) ne {}} {
		::ai::modelfit::cancelMemory $Priv(probe)
		set Priv(probe) {}
	}

	if {[winfo exists $Priv(dialog)]} { destroy $Priv(dialog) }
	set Priv(dialog) {}
	set Priv(fit) {}
	if {[info exists Priv(ctree)]} { unset Priv(ctree) }
	if {[info exists Priv(memory)]} { unset Priv(memory) }
}

# vi:set ts=3 sw=3:
