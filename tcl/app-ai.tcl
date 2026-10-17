# ======================================================================
# ::application::ai -- AI position assessment wired into the report pane.
#
# Extras > "AI: Explain Position" runs grounded generation on the current
# board and renders the result (and any ungrounded claims) in the HTML report
# pane.  Generation is asynchronous so the interface never blocks.
#
#   ::application::ai::configure -provider ollama -model NAME
#   ::application::ai::analyze .application
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-ai
}

package require Tcl 8.5
package require Tk 8.5

namespace eval application {
namespace eval ai {

# The language model defaults to a strong cloud model, kimi-k3:cloud
# through Ollama; a model that runs on this machine, Claude, OpenAI and the
# other presets are a choice in AI: Choose Model (docs/ai/ASSISTANT_COVERAGE_MAP.md
# P6). An empty model means the provider's default (::ai::provider::model).
variable Config
array set Config {
	provider   ollama
	model      ""
	depth      12
	retries    1
	numPredict 400
}

# No model name is fixed here: the environment supplies the defaults
# (SCIDB_AI_PROVIDER / SCIDB_AI_MODEL), and the saved settings or the
# command line overwrite them in applySettings. A model is chosen in
# Extras > AI: Choose Model (or with SCIDB_AI_MODEL for a session).
if {[info exists ::env(SCIDB_AI_PROVIDER)] && $::env(SCIDB_AI_PROVIDER) ne ""} {
	set Config(provider) $::env(SCIDB_AI_PROVIDER)
}
if {[info exists ::env(SCIDB_AI_MODEL)] && $::env(SCIDB_AI_MODEL) ne ""} {
	set Config(model) $::env(SCIDB_AI_MODEL)
}

# The provider and model chosen in Extras > AI: Choose Model, saved in the
# options file. The System One classifier backend of the same dialog is saved
# here too (Settings(classifier)). Config holds the values in effect, which
# are overridden (for the session only) by, in this order:
#   --ai-model=NAME / --ai-provider=NAME / --ai-classifier=NAME   command line
#   SCIDB_AI_MODEL / SCIDB_AI_PROVIDER / SCIDB_AI_CLASSIFIER      environment
#
# chosen is 1 once the user picked a model in the dialog; until then the
# default above applies, also over a provider saved before it changed.
# cloudNotice is 1 once the first-use notice about the cloud was shown.
# me is the user's name as written in their games (the assistant's
# remember_me tool).
variable Settings
array set Settings [list provider $Config(provider) model $Config(model) classifier auto \
	chosen 0 cloudNotice 0 me ""]

# The backup models tried in turn when the chosen one is down (no reply,
# timeout, busy, server error): each "provider ?model?", "auto" for the
# first ready provider not already in use, or "" for none.
array set Settings {backup1 auto backup2 auto}

# The order "auto" picks backups in: a provider is ready when it needs no
# key (Ollama) or its key is there.
variable BackupOrder {ollama fireworks qwen anthropic gemini openai}

# API keys live in their own file (mode 0600), never in the options file.
variable Keys {}

namespace eval mc {
set CloudNotice		"Chesswiz's AI features use %s in the cloud."
set CloudNoticeDetail	"Your requests and the facts the AI reads (game headers, moves, statistics) are sent to %s. No database is uploaded, and voice stays on this machine. To keep everything on this machine, choose a local model in Extras > AI: Choose Model."
set NoKey				"The AI features need an API key for %s."
set NoKeyDetail		"Enter the key in Extras > AI: Choose Model, or choose a local model there. Open it now?"
}

} ;# namespace ai
} ;# namespace application


# Where the value of <key> (provider|model|classifier) in effect comes from,
# and it: {option|environment|settings value}.
proc ::application::ai::setting {key} {
	variable Settings

	set value [::process::optionValue ai-$key]
	if {[string length $value]} { return [list option $value] }
	set env SCIDB_AI_[string toupper $key]
	if {[info exists ::env($env)] && [string length $::env($env)]} {
		return [list environment $::env($env)]
	}
	return [list settings $Settings($key)]
}


proc ::application::ai::applySettings {} {
	variable Config
	variable Settings

	if {!$Settings(chosen)} {
		set Settings(provider) ollama
		set Settings(model) ""
	}
	# A locked or unavailable credential store must not stop startup.
	if {[catch loadKeys err]} { puts stderr "Chesswiz: AI keys not loaded: $err" }

	foreach key {provider model} {
		set Config($key) [lindex [setting $key] 1]
	}
	if {[llength [info commands ::ai::systemone::configure]]} {
		lassign [setting classifier] source backend
		if {[catch { ::ai::systemone::configure -backend $backend }]} {
			# A corrupt saved choice must not break startup: fall back to
			# the default backend and heal the setting, so the bad value
			# is not written back to the options file on exit.
			catch { ::ai::systemone::configure -backend kev }
			if {$source eq "settings"} { set Settings(classifier) kev }
		}
		# In auto mode this finds a local server; an explicit choice is a no-op.
		if {[llength [info commands ::ai::systemone::autostart]]} {
			::ai::systemone::autostart
		}
	}
}


# The backup models in effect, as a list of {provider model} (model "" is
# the provider's default), at most two, none the same as the chosen model.
proc ::application::ai::backups {} {
	variable Config
	variable Settings
	variable BackupOrder

	set used [list [list $Config(provider) [Model $Config(provider) $Config(model)]]]
	set result {}
	foreach key {backup1 backup2} {
		set value [string trim $Settings($key)]
		if {$value eq ""} { continue }
		if {$value eq "auto"} {
			foreach provider $BackupOrder {
				set pick [list $provider [Model $provider ""]]
				if {$pick ni $used && [Ready $provider]} { break }
				set pick {}
			}
		} else {
			set provider [lindex $value 0]
			set pick [list $provider [Model $provider [lindex $value 1]]]
			if {![info exists ::ai::provider::Label($provider)] || $pick in $used} { set pick {} }
		}
		if {[llength $pick]} {
			lappend used $pick
			lappend result $pick
		}
	}
	return $result
}


proc ::application::ai::Model {provider model} {
	if {$model ne ""} { return $model }
	if {[info exists ::ai::provider::DefaultModel($provider)]} {
		return $::ai::provider::DefaultModel($provider)
	}
	return ""
}


proc ::application::ai::Ready {provider} {
	if {$provider eq "ollama"} { return 1 }
	if {[Model $provider ""] eq ""} { return 0 }
	return [expr {[::ai::provider::apiKey $provider] ne ""}]
}


# Save a new choice; it takes effect unless overridden.
proc ::application::ai::choose {provider model} {
	variable Settings

	set Settings(provider) $provider
	set Settings(model) $model
	set Settings(chosen) 1
	applySettings
}


proc ::application::ai::KeyFile {} {
	if {![info exists ::scidb::dir::user]} { return "" }
	return [file join $::scidb::dir::user config ai-keys]
}


# Linux retains the private file. Supported platforms must use the OS store.
proc ::application::ai::CredentialStore {} {
	return [expr {$::tcl_platform(platform) eq "windows" || $::tcl_platform(os) eq "Darwin"}]
}

proc ::application::ai::ReadKeyFile {} {
	set file [KeyFile]
	if {$file eq "" || ![file readable $file]} { return {} }
	set chan [open $file r]
	try { set data [read $chan] } finally { close $chan }
	if {[catch {dict size $data}]} { error "invalid AI key file" }
	return $data
}

proc ::application::ai::WriteKeyFile {keys} {
	set file [KeyFile]
	if {$file eq ""} { return }
	file mkdir [file dirname $file]
	set chan [open $file w 0600]
	try { puts $chan $keys } finally { close $chan }
	catch {file attributes $file -permissions 0600}
}

proc ::application::ai::loadKeys {} {
	variable Keys
	set loaded {}
	if {[CredentialStore]} {
		set loaded [ReadKeyFile]
		set accounts [lsort -unique [concat [::ai::provider::credentialAccounts] [dict keys $loaded]]]
		set stored {}
		foreach provider $accounts {
			set key [::scidb::sys::credential get Chesswiz $provider]
			if {$key eq "" && [dict exists $loaded $provider]} {
				set key [dict get $loaded $provider]
				if {$key ne ""} { ::scidb::sys::credential set Chesswiz $provider $key }
			}
			if {$key ne ""} { dict set stored $provider $key }
		}
		# Only remove plaintext after every migration operation succeeded.
		set file [KeyFile]
		if {$file ne "" && [file exists $file]} { file delete $file }
		set loaded $stored
	} else {
		# Retain the Linux behavior for missing or malformed legacy files.
		set loaded $Keys
		set file [KeyFile]
		if {$file ne "" && [file readable $file]} { catch {set loaded [ReadKeyFile]} }
	}
	set Keys $loaded
	if {[llength [info commands ::ai::provider::configure]]} {
		::ai::provider::configure -keys $Keys
	}
}


# The saved key of <provider> ("" when none).
proc ::application::ai::key {provider} {
	variable Keys
	return [expr {[dict exists $Keys $provider] ? [dict get $Keys $provider] : ""}]
}


# Save (or with "" remove) the key of <provider> through the platform store.
proc ::application::ai::setKey {provider key} {
	variable Keys

	set key [string trim $key]
	set updated $Keys
	if {$key eq ""} { dict unset updated $provider } else { dict set updated $provider $key }
	if {[CredentialStore]} {
		if {$key eq ""} {
			::scidb::sys::credential delete Chesswiz $provider
		} else {
			::scidb::sys::credential set Chesswiz $provider $key
		}
	} else { WriteKeyFile $updated }
	set Keys $updated
	::ai::provider::configure -keys $Keys
}


# Before a user-started AI request: with a cloud provider, make sure there
# is a key (else offer the model dialog) and say once what is sent. Returns
# 1 when the request may go ahead.
proc ::application::ai::cloudReady {parent} {
	variable Config
	variable Settings
	variable mc

	# the provider's own state decides (Ollama: a cloud model or not)
	::ai::provider::configure -name $Config(provider) -model $Config(model)
	if {![::ai::provider::cloudProvider]} { return 1 }
	set name [::ai::provider::label $Config(provider)]

	if {$Config(provider) ne "ollama" && [::ai::provider::apiKey $Config(provider)] eq ""} {
		set reply [::dialog::question -parent $parent -default yes \
			-message [format $mc::NoKey $name] -detail $mc::NoKeyDetail]
		if {$reply eq "yes"} { ::application::ai::models::show $parent }
		return 0
	}
	if {!$Settings(cloudNotice)} {
		set Settings(cloudNotice) 1
		::dialog::info -parent $parent -message [format $mc::CloudNotice $name] \
			-detail [format $mc::CloudNoticeDetail $name]
	}
	return 1
}


# Save a new classifier backend; it takes effect unless overridden.
proc ::application::ai::chooseClassifier {backend} {
	variable Settings

	set Settings(classifier) [expr {$backend eq "off" ? "" : $backend}]
	applySettings
}


proc ::application::ai::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Settings
}
if {[llength [info commands ::options::hookWriter]]} {
	::options::hookWriter ::application::ai::WriteOptions
}

if {[llength [info commands ::process::optionValue]]} {
	::application::ai::applySettings
}


proc ::application::ai::configure {args} {
	variable Config

	foreach {key value} $args {
		switch -- $key {
			-provider { set Config(provider) $value }
			-model    { set Config(model) $value }
			-depth    { set Config(depth) $value }
			-retries  { set Config(retries) $value }
			default   { error "unknown option $key" }
		}
	}
	return
}


proc ::application::ai::escape {s} {
	return [string map {& &amp; < &lt; > &gt;} $s]
}


# The report pane is fed a sanitized-document dict (keys html/media/anchors/
# unresolved), not a raw string -- `Load` does `dict get $data html`. Build one
# from generated markup so the pane renders it instead of failing.
proc ::application::ai::htmlData {html} {
	if {[catch {::scidb::html::sanitize $html ""} data]} {
		set data [dict create html $html title "AI assessment" media {} \
			anchors {} warnings {} unresolved 0 converted 0]
	}
	return $data
}


# <html> is a page (HTML text) or an already sanitized data dict as htmlData
# returns it: most callers pass the latter, and sanitizing a dict as if it
# were HTML rendered its Tcl text ("html {...} title {} media {} ...") in the
# Report pane.
proc ::application::ai::showReport {parent title html} {
	if {![IsHtmlData $html]} { set html [htmlData $html] }
	return [::application::report::showHtmlData $parent $title $html]
}


proc ::application::ai::IsHtmlData {value} {
	if {[catch {
		expr {[llength $value] % 2 == 0
			&& [dict exists $value html] && [dict exists $value title]
			&& [dict exists $value media] && [dict exists $value anchors]}
	} yes]} { return 0 }
	return $yes
}


# <verdict> is shown only for a finished generation; status and error
# messages have no claims to vouch for. <notices> are advisory second-opinion
# labels from the System One classifier (rhetoric / coverage): they never
# affect `grounded` or the claim-check verdict, only add a fixed caution.
proc ::application::ai::toHtml {text claims {evidence {}} {verdict 1} {notices {}} {facts ""}} {
	set html ""

	if {[llength $evidence]} {
		append html "<p><b>Evidence</b></p><ul>"
		foreach line $evidence {
			append html "<li>[escape $line]</li>"
		}
		append html "</ul>"
	}

	set body [escape $text]
	set body [string map {\n <br>} $body]
	append html "<p><b>Assessment</b></p><p>$body</p>"

	if {[llength $claims]} {
		append html "<p><b>Ungrounded claims</b> (contradicted by the facts):</p><ul>"
		foreach claim $claims {
			append html "<li>[escape $claim]</li>"
		}
		append html "</ul>"
	} elseif {$verdict} {
		append html "<p><i>All claims verified against the facts.</i></p>"
	}

	if {[llength $notices]} {
		append html "<p><b>Advisory</b></p><ul>"
		foreach notice $notices {
			append html "<li><i>[escape $notice]</i></li>"
		}
		append html "</ul>"
	}

	# B9: show the work -- the deterministic facts the model was given.
	if {$facts ne ""} {
		append html "<p><b>Grounding facts</b></p><pre>[escape $facts]</pre>"
	}

	return $html
}


# One generation at a time: the prompt build runs a nested engine search, and
# a second request would re-enter it.  Every entry point (analyze, explain
# selection, ...) shares this gate and the placeholder/result rendering, so
# they all route through the same fact-pack -> prompt -> claim-check -> retry
# pipeline (the plan's "one grounding path").
proc ::application::ai::busy? {} {
	variable Busy
	return [expr {[info exists Busy] && $Busy}]
}


proc ::application::ai::begin {parent title placeholder} {
	variable Busy

	if {[busy?]} { return 0 }
	if {![cloudReady $parent]} { return 0 }
	set Busy 1
	::application::ai::showReport $parent $title [toHtml $placeholder {} {} 0]
	return 1
}


# Run the grounded generation for <fen> and render the result in the report
# pane.  <title> names the report; <placeholder> is shown immediately so the
# pane never blocks (latency honesty).
# <args> may carry -observer <cmd>: after the report is rendered the command
# is called with the result dict, so a caller can also use the text (C1 fills
# the comment editor from it).
proc ::application::ai::generate {parent title placeholder fen args} {
	variable Config

	array set opts [list -observer {}]
	array set opts $args
	set forward {}
	foreach {key value} [array get opts] { if {$key ne "-observer"} { lappend forward $key $value } }

	if {![begin $parent $title $placeholder]} { return }

	if {[catch {
		::ai::provider::configure -name $Config(provider) -model $Config(model) \
			-timeout 300000 -options [list num_predict $Config(numPredict)]
		::ai::generate::positionToolsAsync $fen \
			[namespace code [list ::application::ai::onResult $parent $title $opts(-observer)]] \
			-depth $Config(depth) -retries $Config(retries) {*}$forward
	} err]} {
		# prompt construction is synchronous (facts, engine); report its
		# failure in the pane rather than leaving the placeholder up
		onResult $parent $title $opts(-observer) [dict create ok 0 error $err]
	}
	return
}


proc ::application::ai::analyze {parent} {
	if {[catch {::scidb::pos::fen} fen]} {
		::dialog::info -parent $parent -message "No position available: $fen"
		return
	}
	generate $parent "AI assessment" "Analyzing the current position..." $fen
	return
}


proc ::application::ai::onResult {parent title observer result} {
	variable Busy
	set Busy 0

	if {![dict get $result ok]} {
		::application::ai::showReport $parent "$title (error)" \
			[toHtml "Generation failed: [dict get $result error]" {} {} 0]
		if {[llength $observer]} { uplevel #0 [list {*}$observer $result] }
		return
	}

	set state [expr {[dict get $result grounded] ? "grounded" : "unverified"}]
	set evidence [expr {[dict exists $result evidence] ? [dict get $result evidence] : {}}]
	set notices [expr {[dict exists $result notices] ? [dict get $result notices] : {}}]
	set facts [expr {[dict exists $result facts] ? [dict get $result facts] : ""}]
	::application::ai::showReport $parent "$title ($state)" \
		[toHtml [dict get $result text] [dict get $result claims] $evidence 1 $notices $facts]
	if {[llength $observer]} { uplevel #0 [list {*}$observer $result] }
	return
}


# ----------------------------------------------------------------------
# C1 -- selection -> explanation.
#
# A right-click "Explain" on a move, a game row or a comment produces a
# grounded explanation of *that thing* in the report pane, using the
# selection as context.  The move case reuses the engine classifier and the
# move facts; the game case reuses the current game's PGN; the comment case
# explains the stored text.  All three render through toHtml/showReport.
# ----------------------------------------------------------------------

# The facts for a single move, as a compact block for the prompt.  Returns
# the empty string when the move cannot be resolved.
proc ::application::ai::moveFacts {san fen} {
	if {[catch {::scidb::ai::moveFacts $san $fen} facts]} { return "" }
	return $facts
}


# A one-line classification of <san> in <fen>, or "" when no engine is
# available (the explanation then falls back to the move facts alone).
proc ::application::ai::moveClass {san fen} {
	if {[llength [info commands ::ai::engine::classify]] == 0} { return "" }
	if {[catch {::ai::engine::classify $fen $san} c]} { return "" }
	return "classification=[dict get $c classification] cpLoss=[dict get $c cpLoss] best=[dict get $c bestMove]"
}


# Explain the move <san> played in <fen>.  The prompt carries the move facts
# and, when an engine is available, the classification; the claim checker
# then verifies the narration against the same position.
proc ::application::ai::explainMove {parent san fen} {
	set facts [moveFacts $san $fen]
	if {$facts eq ""} {
		::dialog::info -parent $parent -message "Cannot explain '$san': not a legal move in this position."
		return
	}
	set class [moveClass $san $fen]
	set context "Explain the move $san in this position.\nMOVE FACTS (JSON):\n$facts\n"
	if {$class ne ""} { append context "MOVE CLASSIFICATION: $class\n" }
	generate $parent "Explain $san" "Explaining $san..." $fen -context $context
	return
}


# Explain the game currently on the board (its header, moves and comments).
proc ::application::ai::explainGame {parent} {
	set source [expr {[::scidb::game::query modified?] ? "modified" : "original"}]
	set pgn [string trim [::scidb::game::toPGN $source]]
	if {$pgn eq ""} {
		::dialog::info -parent $parent -message "No game to explain."
		return
	}
	set fen [::scidb::pos::fen]
	set context "Explain this game to a club player: its opening, the character of the play and the result.\nGAME (PGN):\n$pgn\n"
	generate $parent "Explain game" "Explaining the game..." $fen -context $context
	return
}


# Explain the comment stored at <pos> of the current game.
proc ::application::ai::explainComment {parent pos} {
	if {[catch {::scidb::game::query comment $pos} comment]} {
		::dialog::info -parent $parent -message "No comment at this position."
		return
	}
	set comment [string trim [::scidb::misc::xml toText $comment]]
	if {$comment eq ""} {
		::dialog::info -parent $parent -message "No comment at this position."
		return
	}
	set fen [::scidb::pos::fen]
	set context "Expand this annotation into a fuller explanation for a club player. Do not invent moves or evaluations.\nCOMMENT:\n$comment\n"
	generate $parent "Explain comment" "Explaining the comment..." $fen -context $context
	return
}


# C3: explain the engine's principal variation.  The line is the context and
# is also handed to the claim checker, so a move the model names from the line
# is grounded even when it is not legal in the current position.
proc ::application::ai::explainLine {parent pv fen} {
	set pv [string trim $pv]
	if {$pv eq ""} { return }
	if {$fen eq ""} { set fen [::scidb::pos::fen] }
	set context "Explain the engine's principal variation from this position to a club player.\nENGINE LINE: $pv\nDescribe what the first move achieves and how the idea unfolds. Every move you name must come from this line; do not invent moves or evaluations."
	generate $parent "Explain the engine's line" "Explaining the engine's line..." $fen \
		-context $context -line [split $pv]
	return
}


# Dispatch on the selection kind: {move san fen} | {game} | {comment pos}.
proc ::application::ai::explainSelection {parent kind payload} {
	switch -- $kind {
		move {
			lassign $payload san fen
			if {$fen eq ""} { set fen [::scidb::pos::fen] }
			explainMove $parent $san $fen
		}
		game {
			explainGame $parent
		}
		comment {
			lassign $payload pos
			explainComment $parent $pos
		}
		default {
			error "unknown selection kind '$kind'"
		}
	}
	return
}
