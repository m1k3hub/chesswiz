# ======================================================================
# ::application::ai -- AI position assessment wired into the report pane.
#
# Extras > "AI: Explain Position" runs grounded generation on the current
# board and renders the result (and any ungrounded claims) in the HTML report
# pane.  Generation is asynchronous so the interface never blocks.
#
#   ::application::ai::configure -provider ollama -model granite4.2:3b
#   ::application::ai::analyze .application
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-ai
}

package require Tcl 8.5
package require Tk 8.5

namespace eval application {
namespace eval ai {

variable Config
array set Config {
	provider   ollama
	model      "deepseek-v4.1-flash:cloud"
	depth      12
	retries    1
	numPredict 400
}

# Swap provider/model without editing code:
#   SCIDB_AI_MODEL=glm-5.3:cloud pi
# or at runtime: ::application::ai::configure -model glm-5.3:cloud
if {[info exists ::env(SCIDB_AI_PROVIDER)]} { set Config(provider) $::env(SCIDB_AI_PROVIDER) }
if {[info exists ::env(SCIDB_AI_MODEL)]}    { set Config(model) $::env(SCIDB_AI_MODEL) }

} ;# namespace ai
} ;# namespace application


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


proc ::application::ai::showReport {parent title html} {
	return [::application::report::showHtmlData $parent $title [htmlData $html]]
}


# <verdict> is shown only for a finished generation; status and error
# messages have no claims to vouch for.
proc ::application::ai::toHtml {text claims {evidence {}} {verdict 1}} {
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
	return $html
}


proc ::application::ai::analyze {parent} {
	variable Config

	if {[catch {::scidb::pos::fen} fen]} {
		::dialog::info -parent $parent -message "No position available: $fen"
		return
	}

	# one generation at a time: the prompt build runs a nested engine search,
	# and a second request would re-enter it
	variable Busy
	if {[info exists Busy] && $Busy} { return }

	::application::ai::showReport $parent "AI assessment" \
		[toHtml "Analyzing the current position..." {} {} 0]

	set Busy 1
	if {[catch {
		::ai::provider::configure -name $Config(provider) -model $Config(model) \
			-timeout 300000 -options [list num_predict $Config(numPredict)]
		::ai::generate::positionToolsAsync $fen \
			[namespace code [list ::application::ai::onResult $parent]] \
			-depth $Config(depth) -retries $Config(retries)
	} err]} {
		# prompt construction is synchronous (facts, engine); report its
		# failure in the pane rather than leaving the placeholder up
		onResult $parent [dict create ok 0 error $err]
	}
	return
}


proc ::application::ai::onResult {parent result} {
	variable Busy
	set Busy 0

	if {![dict get $result ok]} {
		::application::ai::showReport $parent "AI assessment (error)" \
			[toHtml "Generation failed: [dict get $result error]" {} {} 0]
		return
	}

	set state [expr {[dict get $result grounded] ? "grounded" : "unverified"}]
	set evidence [expr {[dict exists $result evidence] ? [dict get $result evidence] : {}}]
	::application::ai::showReport $parent "AI assessment ($state)" \
		[toHtml [dict get $result text] [dict get $result claims] $evidence]
	return
}
