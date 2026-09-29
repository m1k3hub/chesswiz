# ======================================================================
# AI: LLM tier routing (System One)
# ======================================================================
# Which model serves an assistant request: the local model or the cloud
# model? The obvious cases are decided by a deterministic rule -- a
# short request that only touches read-only tools is local; a request
# at or over the long-request bound, or one that asks for long-form
# prose (an article, a report, an essay), is cloud. The rest is asked
# of the bounded classifier (::ai::decide, type choice over the closed
# set {local cloud}); when the classifier does not settle the request
# either, the label is 'configured' -- today's behaviour: whatever
# provider the user configured serves the request, this module
# switches nothing by itself.
#
#   ::ai::tier::rule <request> ?<tools>?    -> local | cloud | ""
#   ::ai::tier::Question                    -> the classifier question
#   ::ai::tier::decide <request> <tools> <script>
#   ::ai::tier::describe <label>            -> a human phrase
#
# <tools> is a Tcl list of tool names as the assistant's Actions table
# names them (tcl/app-assistant.tcl); dict entries with a 'name' key
# are tolerated. A tool counts as read-only when its name is in the
# ReadOnly set below -- the queries over the board game, the active
# database, the engines and the session state; anything that writes,
# starts something or opens a dialog falls out by not being listed.
# The read-only rule answers only when tools were named at all: an
# unknown tool set withholds.
#
# Length bounds: a request of LongChars (2000) or more is already too
# big for the small local context window (cloud); a request over
# ShortChars (400) is neither obviously small nor obviously big, so
# the rule withholds. SCIDB_AI_TIER_LONG_CHARS and
# SCIDB_AI_TIER_SHORT_CHARS override the bounds for a session.
#
# <script> gets {ok 1 label L confidence C source S}:
#   L = local | cloud  (confidence 1.0, source rules) when the rule
#       settles the request -- the classifier is never asked;
#   L = local | cloud  (source classifier) when it answers;
#   L = configured when the rule abstained and the classifier did not
#       settle the request (confidence {}, source rules).
# Otherwise {ok 0}. Nothing blocks: the rules answer through after 0,
# the rest through the classifier's asynchronous callback.
#
# Firewall: this only labels a request with a tier; it never sends a
# request, never switches a provider and never reads the game beyond
# the caller's own state string. The answer is advice; routing the
# request is the caller's decision. The classifier's confidence
# threshold is the usual SCIDB_AI_TIER_MIN_CONFIDENCE (default 0.6,
# set by ::ai::decide).
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-tier
}

package require Tcl 8.5

namespace eval ::ai::tier {

	# the classifier's answer set (choice criteria name -> description)
	variable Criteria [dict create \
		"local" "the configured local model: a small, quick answer grounded in the session's own data" \
		"cloud" "the cloud model: long-form prose, or a request too big for the local window" \
		]

	# label -> English phrase ('' from the rule never reaches a caller)
	variable Names [dict create \
		local      "the local model" \
		cloud      "the cloud model" \
		configured "undecided: the configured provider serves the request, nothing is switched" \
		]

	# requests at or over this length are a cloud job (see header)
	variable LongChars 2000
	# requests at or under this length may be a local job (see header)
	variable ShortChars 400

	# the read-only tools of the assistant's Actions table
	# (tcl/app-assistant.tcl): queries over the board game, the active
	# database, the engines and the session state. Anything absent
	# writes, starts something, or opens a dialog a user must see.
	variable ReadOnly {app_state classifier_status clear_search current_game database_summary database_trend discover_databases engine_options list_engines list_issues list_open_databases player_stats position_moves prepare_against recent_errors repertoire_check search_games show_search tool_log}

	# words that ask for long-form prose: the request is short, the
	# answer is not
	variable Prose {\y(write\w*|draft\w*|compose\w*|article\w*|report\w*|essay\w*|letter\w*|guide\w*|tutorial\w*|biograph\w*|chapter\w*|stor\w*|review\w*|blog\w*|outline\w*|introduction\w*|comprehensive|detailed|in depth|step by step|long form)\y}
}

# The tools as plain lower-case names: a bare list of names, a single
# name, and dict entries with a 'name' key all read the same; junk
# that is not a list reads as no tools at all.
proc ::ai::tier::ToolList {tools} {
	set out {}
	if {[catch { llength $tools }]} { return $out }
	foreach tool $tools {
		if {[catch { llength $tool } n] == 0 && $n > 1
		 && [catch { dict get $tool name } name] == 0} {
			set tool $name
		}
		set tool [string tolower [string trim $tool]]
		if {$tool ne ""} { lappend out $tool }
	}
	return $out
}

# The long-request bound, from the environment when it says so.
proc ::ai::tier::LongLimit {} {
	variable LongChars
	if {[info exists ::env(SCIDB_AI_TIER_LONG_CHARS)]
	 && [string is integer -strict $::env(SCIDB_AI_TIER_LONG_CHARS)]} {
		return $::env(SCIDB_AI_TIER_LONG_CHARS)
	}
	return $LongChars
}

# The short-request bound, from the environment when it says so.
proc ::ai::tier::ShortLimit {} {
	variable ShortChars
	if {[info exists ::env(SCIDB_AI_TIER_SHORT_CHARS)]
	 && [string is integer -strict $::env(SCIDB_AI_TIER_SHORT_CHARS)]} {
		return $::env(SCIDB_AI_TIER_SHORT_CHARS)
	}
	return $ShortChars
}

# The deterministic tier, or "" when the request does not say: a
# request at or over the long bound says 'cloud'; a request that asks
# for long-form prose says 'cloud' whatever its length -- the answer,
# not the request, is what has to fit somewhere; a short request whose
# tools are all read-only says 'local'. Everything else withholds.
proc ::ai::tier::rule {request {tools ""}} {
	variable ReadOnly
	variable Prose

	set request [string trim $request]
	if {$request eq ""} { return "" }
	set chars [string length $request]

	if {$chars >= [LongLimit]} { return cloud }

	if {[regexp $Prose $request]} { return cloud }

	if {$chars > [ShortLimit]} { return "" }

	set names [ToolList $tools]
	if {[llength $names] == 0} { return "" }
	foreach name $names {
		if {[lsearch -exact $ReadOnly $name] < 0} { return "" }
	}
	return local
}

# The classifier question, in one place so calibration asks exactly
# what production asks.
proc ::ai::tier::Question {} {
	variable Criteria
	return [dict create type choice \
		instructions "Should this request be answered by the local model or by the cloud model?" \
		criteria $Criteria]
}

# The state string handed to the classifier: how long the request is
# and which tools it touches.
proc ::ai::tier::State {request tools} {
	set names [ToolList $tools]
	return "chars=[string length [string trim $request]] tools=[expr {[llength $names] ? [join $names { }] : "-"}]"
}

# The label when the rule abstained and the classifier did not settle
# the request either: the fallback of ::ai::decide (source rules) --
# today's behaviour, the configured provider.
proc ::ai::tier::Configured {} {
	return configured
}

proc ::ai::tier::describe {label} {
	variable Names
	return [expr {[dict exists $Names $label] ? [dict get $Names $label] : $label}]
}

# <script> gets {ok 1 label L confidence C source S}:
#   L = local | cloud   (confidence 1.0, source rules) when the rule
#       settles the request -- the classifier is never asked;
#   L = local | cloud   (source classifier) when it answers;
#   L = configured      (confidence {}, source rules) when the rule
#       abstained and the classifier did not settle the request.
# Otherwise {ok 0}.
proc ::ai::tier::decide {request tools script} {
	set rule [rule $request $tools]

	if {$rule ne ""} {
		after 0 [list {*}$script [list ok 1 label $rule confidence 1.0 source rules]]
		return
	}

	if {[llength [info commands ::ai::decide]] == 0} {
		after 0 [list {*}$script [list ok 1 label [Configured] confidence {} source rules]]
		return
	}

	::ai::decide tier [State $request $tools] [Question] $script \
		-fallback [namespace code Configured]
	return
}

# vi:set ts=3 sw=3:
