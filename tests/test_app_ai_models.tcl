# ======================================================================
# Scidb App Test — AI model choice (tcl/app-ai.tcl, tcl/app-ai-models.tcl)
# ======================================================================
# Precedence: --ai-model/--ai-provider > SCIDB_AI_* > saved setting.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::aimodels {}

# Run <body> with the AI settings, env and command-line options restored.
proc ::scidb::test::aimodels::isolated {body} {
	# Existing fixture bodies supply a synchronous model list. Deliver it
	# through the chooser's asynchronous provider seam, without real HTTP.
	rename ::ai::provider::ollamaModelsAsync ::scidb::test::aimodels::realAsyncModels
	proc ::ai::provider::ollamaModelsAsync {script args} {
		if {[catch {::ai::provider::ollamaModels {*}$args} models]} {
			set result [dict create ok 0 error $models]
		} else {
			set result [dict create ok 1 models $models]
		}
		after 0 [list {*}$script $result]
	}
	set settings [array get ::application::ai::Settings]
	set config [array get ::application::ai::Config]
	set options [array get ::process::Options ai-*]
	set valued [array get ::process::Valued ai-*]
	set env {}
	foreach v {SCIDB_AI_MODEL SCIDB_AI_PROVIDER SCIDB_AI_CLASSIFIER} {
		if {[info exists ::env($v)]} { lappend env $v $::env($v); unset ::env($v) }
	}
	set systemone {}
	set discovery {}
	if {[llength [info commands ::ai::systemone::configure]]} {
		set systemone [array get ::ai::systemone::Config]
		set discovery [list $::ai::systemone::Auto $::ai::systemone::Resolved]
	}
	set rc [catch { uplevel 1 $body } result]
	rename ::ai::provider::ollamaModelsAsync {}
	rename ::scidb::test::aimodels::realAsyncModels ::ai::provider::ollamaModelsAsync
	array set ::application::ai::Settings $settings
	array set ::application::ai::Config $config
	array unset ::process::Options ai-*
	array unset ::process::Valued ai-*
	array set ::process::Options $options
	array set ::process::Valued $valued
	foreach v {SCIDB_AI_MODEL SCIDB_AI_PROVIDER SCIDB_AI_CLASSIFIER} { unset -nocomplain ::env($v) }
	array set ::env $env
	if {[llength $systemone]} { array set ::ai::systemone::Config $systemone }
	if {[llength $discovery]} { lassign $discovery ::ai::systemone::Auto ::ai::systemone::Resolved }
	if {$rc} { return -code error $result }
	return $result
}

tcltest::test aimodels-saved-setting {the saved choice is in effect without overrides} -body {
	::scidb::test::aimodels::isolated {
		::application::ai::choose ollama saved-model:1b
		list [::application::ai::setting model] $::application::ai::Config(model)
	}
} -result {{settings saved-model:1b} saved-model:1b}

tcltest::test aimodels-env-overrides {SCIDB_AI_MODEL overrides the saved choice} -body {
	::scidb::test::aimodels::isolated {
		::application::ai::choose ollama saved-model:1b
		set ::env(SCIDB_AI_MODEL) env-model:2b
		::application::ai::applySettings
		list [::application::ai::setting model] $::application::ai::Config(model) \
			$::application::ai::Settings(model)
	}
} -result {{environment env-model:2b} env-model:2b saved-model:1b}

tcltest::test aimodels-option-overrides {--ai-model overrides the environment and the saved choice} -body {
	::scidb::test::aimodels::isolated {
		::application::ai::choose ollama saved-model:1b
		set ::env(SCIDB_AI_MODEL) env-model:2b
		::process::setOption ai-model flag-model:3b
		set ::process::Valued(ai-model) 1
		::application::ai::applySettings
		list [::application::ai::setting model] $::application::ai::Config(model)
	}
} -result {{option flag-model:3b} flag-model:3b}

tcltest::test aimodels-saved-in-options {the choice is written to the options file} -body {
	::scidb::test::aimodels::isolated {
		::application::ai::choose ollama saved-model:1b
		set chan [file tempfile path]
		::application::ai::WriteOptions $chan
		close $chan
		set chan [::open $path]
		set text [read $chan]
		close $chan
		file delete $path
		# sourcing it restores the setting
		array set ::application::ai::Settings {model other}
		eval $text
		list [string match "array set ::application::ai::Settings*" $text] \
			$::application::ai::Settings(model) \
			[expr {"::application::ai::WriteOptions" in $::options::WriteCallbacks(options)}]
	}
} -result {1 saved-model:1b 1}

tcltest::test aimodels-parse-tags {Ollama's model list is parsed with cloud and tool flags} -body {
	set data {{"models":[
		{"name":"qwen3:8b","size":5200000000,"capabilities":["completion","tools"]},
		{"name":"glm-5.3:cloud","remote_host":"https://ollama.com","size":326,"capabilities":["completion","tools"]},
		{"name":"gemma3:4b","size":3300000000,"capabilities":["completion","vision"]}]}}
	lmap m [::ai::provider::parseModels $data] {
		list [dict get $m name] [dict get $m remote] [dict get $m tools]
	}
} -result {{gemma3:4b 0 0} {glm-5.3:cloud 1 1} {qwen3:8b 0 1}}

tcltest::test aimodels-dialog-saves-choice {picking a model in the dialog saves it} -body {
	::scidb::test::aimodels::isolated {
		# the local section is shown for a saved local choice
		::application::ai::choose ollama earlier:1b
		rename ::ai::provider::ollamaModels ::scidb::test::aimodels::realModels
		proc ::ai::provider::ollamaModels {args} {
			return [list \
				[dict create name local-a:1b remote 0 tools 1 size 1] \
				[dict create name notools:1b remote 0 tools 0 size 1]]
		}
		set dlg [::application::ai::models::show .application]
		update
		set rows [$::application::ai::models::Priv(tree) children {}]
		$::application::ai::models::Priv(tree) selection set notools:1b
		update
		set warning [$::application::ai::models::Priv(status) cget -text]
		$::application::ai::models::Priv(tree) selection set local-a:1b
		update
		::application::ai::models::Apply
		rename ::ai::provider::ollamaModels {}
		rename ::scidb::test::aimodels::realModels ::ai::provider::ollamaModels
		list $rows [string match "*does not support tool calling*" $warning] \
			[winfo exists $dlg] $::application::ai::Settings(model) $::application::ai::Config(model)
	}
} -result {{local-a:1b notools:1b} 1 0 local-a:1b local-a:1b}

tcltest::test aimodels-dialog-sees-saved-model {the saved model's row is selected when the dialog opens} -body {
	::scidb::test::aimodels::isolated {
		::application::ai::choose ollama saved-model:1b
		rename ::ai::provider::ollamaModels ::scidb::test::aimodels::realModels
		proc ::ai::provider::ollamaModels {args} {
			return [list \
				[dict create name other:2b remote 0 tools 1 size 1] \
				[dict create name saved-model:1b remote 0 tools 1 size 1]]
		}
		# Fill selects and `see`s the saved model's row; a malformed item
		# name there raises ("Item ... not found")
		set dlg [::application::ai::models::show .application]
		update
		set sel [$::application::ai::models::Priv(tree) selection]
		::application::ai::models::Close
		rename ::ai::provider::ollamaModels {}
		rename ::scidb::test::aimodels::realModels ::ai::provider::ollamaModels
		set sel
	}
} -result {saved-model:1b}

tcltest::test aimodels-dialog-shows-override {the dialog says when a flag overrides the choice} -body {
	::scidb::test::aimodels::isolated {
		::application::ai::choose ollama earlier:1b
		::process::setOption ai-model flag-model:3b
		set ::process::Valued(ai-model) 1
		rename ::ai::provider::ollamaModels ::scidb::test::aimodels::realModels
		proc ::ai::provider::ollamaModels {args} { error "connection refused" }
		::application::ai::models::show .application
		update
		set override [$::application::ai::models::Priv(override) cget -text]
		set status [$::application::ai::models::Priv(status) cget -text]
		::application::ai::models::Close
		rename ::ai::provider::ollamaModels {}
		rename ::scidb::test::aimodels::realModels ::ai::provider::ollamaModels
		list [string match "*the command line (flag-model:3b)*" $override] \
			[string match "*not reachable*" $status]
	}
} -result {1 1}

tcltest::test aimodels-default-cloud {without a choice the default is Claude, whatever an old setting says} -body {
	::scidb::test::aimodels::isolated {
		array set ::application::ai::Settings {provider ollama model old:1b chosen 0}
		::application::ai::applySettings
		list $::application::ai::Config(provider) $::application::ai::Config(model)
	}
} -result {anthropic {}}

tcltest::test aimodels-dialog-cloud-default {the dialog opens on Claude with its default model, Ollama not asked} -body {
	::scidb::test::aimodels::isolated {
		set ::application::ai::Settings(chosen) 0
		rename ::ai::provider::ollamaModels ::scidb::test::aimodels::realModels
		proc ::ai::provider::ollamaModels {args} { error "must not be asked" }
		::application::ai::models::show .application
		update
		set out [list $::application::ai::models::Priv(provider) $::application::ai::models::Priv(cloudModel) \
			[winfo ismapped $::application::ai::models::Priv(cloud)] [winfo ismapped $::application::ai::models::Priv(local)] \
			$::application::ai::models::Priv(filled)]
		::application::ai::models::Close
		rename ::ai::provider::ollamaModels {}
		rename ::scidb::test::aimodels::realModels ::ai::provider::ollamaModels
		set out
	}
} -result {anthropic claude-opus-5-5 1 0 0}

tcltest::test aimodels-dialog-cloud-apply {a cloud choice saves the model and the key, the key file is private} -body {
	::scidb::test::aimodels::isolated {
		set keys $::application::ai::Keys
		::application::ai::models::show .application
		update
		set ::application::ai::models::Priv(provider) anthropic
		::application::ai::models::ProviderChanged
		set ::application::ai::models::Priv(cloudModel) claude-sonnet-5-5
		set ::application::ai::models::Priv(key) test-key-123
		::application::ai::models::Apply
		set file [::application::ai::KeyFile]
		set out [list $::application::ai::Settings(provider) $::application::ai::Settings(model) \
			$::application::ai::Settings(chosen) [::application::ai::key anthropic] \
			[::ai::provider::apiKey anthropic] [file attributes $file -permissions]]
		::application::ai::setKey anthropic [expr {[dict exists $keys anthropic] ? [dict get $keys anthropic] : ""}]
		set out
	}
} -result {anthropic claude-sonnet-5-5 1 test-key-123 test-key-123 00600}

tcltest::test aimodels-dialog-cloud-default-saved-empty {choosing the default model saves "" so a newer default applies later} -body {
	::scidb::test::aimodels::isolated {
		::application::ai::models::show .application
		update
		set ::application::ai::models::Priv(provider) anthropic
		::application::ai::models::ProviderChanged
		set ::application::ai::models::Priv(cloudModel) claude-opus-5-5
		::application::ai::models::Apply
		list $::application::ai::Settings(provider) $::application::ai::Settings(model)
	}
} -result {anthropic {}}

tcltest::test aimodels-dialog-switch-local {switching to the local model shows the Ollama list} -body {
	::scidb::test::aimodels::isolated {
		set ::application::ai::Settings(chosen) 0
		rename ::ai::provider::ollamaModels ::scidb::test::aimodels::realModels
		proc ::ai::provider::ollamaModels {args} {
			return [list [dict create name local-a:1b remote 0 tools 1 size 1]]
		}
		::application::ai::models::show .application
		update
		set ::application::ai::models::Priv(provider) ollama
		::application::ai::models::ProviderChanged
		update
		set out [list [winfo ismapped $::application::ai::models::Priv(local)] \
			[winfo ismapped $::application::ai::models::Priv(cloud)] \
			[$::application::ai::models::Priv(tree) children {}]]
		::application::ai::models::Close
		rename ::ai::provider::ollamaModels {}
		rename ::scidb::test::aimodels::realModels ::ai::provider::ollamaModels
		set out
	}
} -result {1 0 local-a:1b}

tcltest::test aimodels-classifier-saved-setting {the saved classifier backend is in effect} -body {
	::scidb::test::aimodels::isolated {
		::application::ai::chooseClassifier plumb
		list [::application::ai::setting classifier] [::ai::systemone::describe]
	}
} -result {{settings plumb} {plumb (plumb-4b-v5 at http://127.0.0.1:8090/v1/systemone)}}

tcltest::test aimodels-classifier-env-overrides {SCIDB_AI_CLASSIFIER overrides the saved choice} -body {
	::scidb::test::aimodels::isolated {
		::application::ai::chooseClassifier plumb
		set ::env(SCIDB_AI_CLASSIFIER) simple-jev
		::application::ai::applySettings
		list [::application::ai::setting classifier] [::ai::systemone::describe] 			$::application::ai::Settings(classifier)
	}
} -result {{environment simple-jev} {simple-jev (Qwen/Qwen3.5-0.8B at http://127.0.0.1:8000/v1/systemone)} plumb}

tcltest::test aimodels-classifier-option-overrides {--ai-classifier overrides the environment and the saved choice} -body {
	::scidb::test::aimodels::isolated {
		::application::ai::chooseClassifier plumb
		set ::env(SCIDB_AI_CLASSIFIER) simple-jev
		::process::setOption ai-classifier off
		set ::process::Valued(ai-classifier) 1
		::application::ai::applySettings
		list [::application::ai::setting classifier] [::ai::systemone::enabled]
	}
} -result {{option off} 0}

tcltest::test aimodels-classifier-off {choosing off disables the classifier} -body {
	::scidb::test::aimodels::isolated {
		::application::ai::chooseClassifier off
		list [::ai::systemone::enabled] $::application::ai::Settings(classifier)
	}
} -result {0 {}}

tcltest::test aimodels-classifier-saved-in-options {the classifier choice is written to the options file} -body {
	::scidb::test::aimodels::isolated {
		::application::ai::chooseClassifier jev
		set chan [file tempfile path]
		::application::ai::WriteOptions $chan
		close $chan
		set chan [::open $path]
		set text [read $chan]
		close $chan
		file delete $path
		array set ::application::ai::Settings {classifier other}
		array unset ::application::ai::Settings model
		eval $text
		list $::application::ai::Settings(classifier) [info exists ::application::ai::Settings(model)]
	}
} -result {jev 1}

tcltest::test aimodels-corrupt-saved-classifier {a corrupt saved classifier heals instead of breaking startup} -body {
	::scidb::test::aimodels::isolated {
		set ::application::ai::Settings(classifier) settings
		if {[catch { ::application::ai::applySettings } err]} { return "threw: $err" }
		list $::application::ai::Settings(classifier) [::ai::systemone::describe]
	}
} -result {kev {kev (kev-latest at http://127.0.0.1:8009/v1/systemone)}}

tcltest::test aimodels-dialog-classifier-value {the dialog starts from the backend VALUE, not the setting source} -body {
	::scidb::test::aimodels::isolated {
		::application::ai::chooseClassifier plumb
		rename ::ai::provider::ollamaModels ::scidb::test::aimodels::realModels
		proc ::ai::provider::ollamaModels {args} {
			return [list [dict create name local-a:1b remote 0 tools 1 size 1]]
		}
		::application::ai::models::show .application
		update
		set initial $::application::ai::models::Priv(classifier)
		set selected [$::application::ai::models::Priv(ctree) selection]
		::application::ai::models::Close
		rename ::ai::provider::ollamaModels {}
		rename ::scidb::test::aimodels::realModels ::ai::provider::ollamaModels
		list $initial $selected
	}
} -result {plumb plumb}

tcltest::test aimodels-dialog-saves-classifier {picking a classifier in the dialog saves it} -body {
	::scidb::test::aimodels::isolated {
		rename ::ai::provider::ollamaModels ::scidb::test::aimodels::realModels
		proc ::ai::provider::ollamaModels {args} {
			return [list [dict create name local-a:1b remote 0 tools 1 size 1]]
		}
		set dlg [::application::ai::models::show .application]
		update
		set rows [$::application::ai::models::Priv(ctree) children {}]
		$::application::ai::models::Priv(ctree) selection set plumb
		update
		::application::ai::models::Apply
		rename ::ai::provider::ollamaModels {}
		rename ::scidb::test::aimodels::realModels ::ai::provider::ollamaModels
		list $rows [winfo exists $dlg] 			$::application::ai::Settings(classifier) [::ai::systemone::describe]
	}
} -result {{auto off kev simple-jev plumb jev typesafe} 0 plumb {plumb (plumb-4b-v5 at http://127.0.0.1:8090/v1/systemone)}}

tcltest::test aimodels-help-lists-flags {--help documents the AI flags} -body {
	set exe [file join [file dirname [info nameofexecutable]] tkscidb-beta]
	if {![file executable $exe]} { set exe [info nameofexecutable] }
	set script [file join $::scidb::test::app::testDir .. tcl scidb-beta]
	set out [exec $exe $script --help 2>@1]
	list [string match "*--ai-model=MODEL*" $out] [string match "*--ai-provider=NAME*" $out] \
		[string match "*--ai-classifier=NAME*" $out] [string match "*--ai-debug*" $out]
} -result {1 1 1 1}

# ----------------------------------------------------------------------

::tcltest::cleanupTests
return
