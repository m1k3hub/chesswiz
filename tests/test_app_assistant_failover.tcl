# Failover is exact transport policy: no model or network needed.
package require tcltest 2.5

tcltest::test assistant-failover-503-timeout {both configured backups are tried in order and shown in the transcript} -setup {
	set savedConfig [array get ::ai::provider::Config]
	set savedSettings [array get ::application::ai::Settings]
	set savedAI [array get ::application::ai::Config]
	rename ::application::assistant::Step ::application::assistant::realFailoverStep
	set ::attempts {}
	proc ::application::assistant::Step {round} {
		lappend ::attempts [list $::ai::provider::Config(name) $::ai::provider::Config(model) $round]
	}
} -body {
	::application::assistant::show
	::application::assistant::clear
	set ::application::ai::Config(provider) gemini
	set ::application::ai::Config(model) gemini-primary
	set ::application::ai::Settings(backup1) {fireworks backup-one}
	set ::application::ai::Settings(backup2) {qwen backup-two}
	::application::assistant::ConfigureProvider
	set a [::application::assistant::TryBackup 2 {ok 0 down 1 error {Gemini: HTTP 503: busy}}]
	set b [::application::assistant::TryBackup 2 {ok 0 down 1 error {Fireworks: timeout}}]
	set c [::application::assistant::TryBackup 2 {ok 0 down 1 error {Qwen: timeout}}]
	set d [::application::assistant::TryBackup 2 {ok 0 down 0 error {HTTP 400}}]
	set text [$::application::assistant::Priv(text) get 1.0 end]
	list $a $b $c $d $::attempts \
		[string match {*asking Fireworks (backup-one) instead*} $text] \
		[string match {*asking Qwen token plan (backup-two) instead*} $text]
} -cleanup {
	rename ::application::assistant::Step {}
	rename ::application::assistant::realFailoverStep ::application::assistant::Step
	array set ::ai::provider::Config $savedConfig
	array set ::application::ai::Settings $savedSettings
	array set ::application::ai::Config $savedAI
} -result {1 1 0 0 {{fireworks backup-one 2} {qwen backup-two 2}} 1 1}

tcltest::test assistant-attempt-deadline {each attempt is bounded, shorter deadlines survive, and Finish restores the timeout} -setup {
	set savedConfig [array get ::ai::provider::Config]
	rename ::ai::provider::chatAsync ::ai::provider::realDeadlineChat
	proc ::ai::provider::chatAsync {args} {set ::deadline $::ai::provider::Config(timeoutMs)}
} -body {
	::application::assistant::clear
	::ai::provider::configure -timeout 120000
	::application::assistant::Step 0
	set a $::deadline
	::application::assistant::Finish {ok 0 down 1 error timeout} 0
	set b $::ai::provider::Config(timeoutMs)
	::ai::provider::configure -timeout 75
	::application::assistant::Step 0
	set c $::deadline
	::application::assistant::Finish {ok 0 down 1 error timeout} 0
	list $a $b $c $::application::assistant::Priv(busy)
} -cleanup {
	rename ::ai::provider::chatAsync {}
	rename ::ai::provider::realDeadlineChat ::ai::provider::chatAsync
	array set ::ai::provider::Config $savedConfig
} -result {30000 120000 75 0}

tcltest::test assistant-unavailable-status {provider details stay out of the short unavailable status} -setup {
 set savedPriv [array get ::application::assistant::Priv]
 array set ::application::assistant::Priv {observer {} turnResults {} internalReplies {} resultFacts {} lastFacts {} turnRefusal {} prohibitedAnalysis 0}
} -body {
	::application::assistant::clear
	::application::assistant::Finish {ok 0 down 1 summary {Gemini: HTTP 503} error {very long service diagnostics}} 0
	set text [$::application::assistant::Priv(text) get 1.0 end]
	list [string match {*Gemini: HTTP 503*} $text] [string match {*very long service diagnostics*} $text]
} -cleanup {
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $savedPriv
} -result {1 0}

tcltest::cleanupTests
