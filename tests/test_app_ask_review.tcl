# Regression coverage for the nine Ask/plan/speech review findings.
# Local executable fixtures and stubbed providers only; no network or microphone.
package require tcltest 2.5
source [file join [pwd] tests test_app_assistant_plan.tcl]

proc ::reviewLater {args} {
    set ::reviewToken [::application::assistant::Later]
    return $::reviewToken
}
proc ::reviewEffect {args} { lappend ::reviewEffects effect; return ok }
proc ::reviewNo {args} { incr ::reviewAsked; return 0 }
proc ::reviewWait {ms} { after $ms {set ::reviewWaitDone 1}; vwait ::reviewWaitDone }

tcltest::test review-async-error-and-global-gate {deferred failure stops the plan and ordinary actions still confirm} -body {
    ::scidb::test::plan::isolated {
        set ::reviewEffects {}; set ::reviewAsked 0
        ::scidb::test::plan::action test.plan.slow slow [dict create handler ::reviewLater]
        ::scidb::test::plan::action test.plan.next next [dict create handler ::reviewEffect confirm 1]
        ::scidb::test::plan::action test.plan.unrelated unrelated [dict create handler ::reviewEffect confirm 1]
        set savedHook $::action::ConfirmHook
        set ::action::ConfirmHook ::reviewNo
        set ::application::assistant::Priv(reqconfirm) ::scidb::test::plan::confirm
        set ::application::assistant::Priv(maxRounds) 0
        ::application::assistant::RunPlan 0 [::scidb::test::plan::calls {test.plan.slow test.plan.next}]
        set gate $::action::PlanGate
        set manual [::action::run test.plan.unrelated]
        ::application::assistant::Resolve $::reviewToken {error: deferred step failed}
        set ::action::ConfirmHook $savedHook
        list $gate $manual $::reviewAsked $::reviewEffects
    }
} -result {0 declined 1 {}}

tcltest::test review-speech-stale-callback {cancel and restart before old FinishStub fires} -body {
    set savedSettings [array get ::application::speech::Settings]
    ::application::speech::configure stub [list list old-transcript]
    ::application::ask::HideList
    set ::application::ask::Query {}
    ::application::speech::Start
    ::application::speech::StopRecording
    ::reviewWait 220
    ::application::speech::Cancel
    ::application::speech::configure stub [list list new-transcript]
    ::application::speech::Start
    ::application::speech::StopRecording
    ::reviewWait 150
    set result [list $::application::ask::Query $::application::speech::Priv(state)]
    ::reviewWait 300
    lappend result $::application::ask::Query $::application::speech::Priv(state)
    ::application::speech::Cancel
    array set ::application::speech::Settings $savedSettings
    ::application::ask::HideList
    set ::application::ask::Query {}
    set result
} -result {{} transcribing new-transcript idle}

tcltest::test review-poll-missing-output {missing output with a live child keeps polling} -body {
    rename ::application::speech::Alive? ::reviewRealAlive
    proc ::application::speech::Alive? {pids} {return 1}
    set ::application::speech::Priv(state) transcribing
    set ::application::speech::Priv(transcribeOut) {}
    set rc [catch {::application::speech::PollTranscribe} err]
    set polling [expr {[info exists ::application::speech::Priv(timers)] && [llength $::application::speech::Priv(timers)] > 0}]
    rename ::application::speech::Alive? {}
    rename ::reviewRealAlive ::application::speech::Alive?
    ::application::speech::Cancel
    list $rc [expr {$rc ? $err : {}}] $polling
} -result {0 {} 1}

tcltest::test review-plan-debug-script {plan approval discloses the full Tcl script} -body {
    ::scidb::test::plan::isolated {
        set ::reviewEvalDone 0
        set ::application::assistant::Priv(debug) 1
        set ::application::assistant::Priv(reqconfirm) ::scidb::test::plan::confirm
        set ::application::assistant::Priv(maxRounds) 0
        ::scidb::test::plan::action test.plan.next next {}
        set evalCall [dict create function [dict create name eval_tcl arguments [dict create script {set ::reviewEvalDone 1}]]]
        ::application::assistant::RunPlan 0 [list $evalCall [::scidb::test::plan::call test.plan.next]]
        list $::reviewEvalDone [llength $::scidb::test::plan::ConfirmAsked] \
            [string match {*set ::reviewEvalDone 1*} [lindex $::scidb::test::plan::ConfirmAsked 0]]
    }
} -result {1 1 1}

# Native Aqua speech bypasses the Linux Whisper/recorder CLI entirely.
tcltest::testConstraint whisperCLI [expr {[tk windowingsystem] ne "aqua" && $::tcl_platform(platform) ne "windows"}]
tcltest::test review-speech-path-spaces {speech executable paths containing spaces remain usable} -constraints whisperCLI -body {
    set dir [file join [pwd] tests tmp-app finish "speech path [pid]"]
    file mkdir $dir
    set exe [file join $dir review-whisper]
    set chan [open $exe w]; puts $chan {#!/bin/sh}; puts $chan {printf 'hello\n'}; close $chan
    file attributes $exe -permissions 0700
    set savedPath $::env(PATH)
    set savedSettings [array get ::application::speech::Settings]
    set ::env(PATH) "$dir:$savedPath"
    ::application::speech::configure stub {} whisperCli review-whisper whisperModel $exe recorder review-whisper
    set available [::application::speech::available]
    set recorder [lindex [::application::speech::RecorderArgv [::application::speech::detect] $exe] 0]
    set rc [catch {::application::speech::transcribeFile $exe} err]
    set wrapped [expr {[::application::speech::which review-whisper] ne $exe}]
    set direct [exec $exe]
    array set ::application::speech::Settings $savedSettings
    set ::env(PATH) $savedPath
    file delete -force $dir
    list $available $rc $wrapped $direct $err [expr {$recorder eq $exe}]
} -result {1 0 0 hello hello 1}

tcltest::test review-speech-symlink {preplanted transcript links cannot clobber another file} -body {
    set base [file join [pwd] tests tmp-app finish "symlink-probe-[pid]"]
    file mkdir [file join $base chesswiz-ask]
    set victim [file join $base victim.txt]
    set chan [open $victim w]; puts $chan original; close $chan
    set seconds [clock seconds]
    for {set i 0} {$i < 3} {incr i} {
        file link -symbolic [file join $base chesswiz-ask "ask-[pid]-[expr {$seconds+$i}]-transcript.txt"] $victim
    }
    set hadTmp [info exists ::env(TMPDIR)]
    if {$hadTmp} {set savedTmp $::env(TMPDIR)}
    set savedSettings [array get ::application::speech::Settings]
    set ::env(TMPDIR) $base
    ::application::speech::configure stub {} whisperCli /bin/echo whisperModel $victim recorder /bin/true
    set ::application::speech::Priv(state) transcribing
    ::application::speech::StartTranscribe $victim
    ::reviewWait 400
    set chan [open $victim r]; set data [read $chan]; close $chan
    ::application::speech::Cancel
    array set ::application::speech::Settings $savedSettings
    if {$hadTmp} {set ::env(TMPDIR) $savedTmp} else {unset ::env(TMPDIR)}
    file delete -force $base
    ::application::ask::HideList
    set ::application::ask::Query {}
    string trim $data
} -result original

tcltest::test review-empty-unknown-and-model-text {empty submission and unregistered Tcl-like id do not run code} -body {
    set ::application::ask::Query {}
    ::application::ask::HideList
    set empty [::application::ask::Choose]
    set ::reviewInjected 0
    set unknown [::application::assistant::runTool {set ::reviewInjected 1} {}]
    set unknownAction [::action::run {set ::reviewInjected 1}]
    list $empty $::reviewInjected [string match {error: unknown tool*} $unknown] \
        [string match {error: unknown action id*} $unknownAction]
} -result {break 0 1 1}

tcltest::test review-busy-submission {busy assistant preserves the editable request} -body {
    set busy $::application::assistant::Priv(busy)
    set ::application::assistant::Priv(busy) 1
    set messages $::application::assistant::Priv(messages)
    set ::application::ask::Query {new request while the previous request is working}
    ::application::ask::SendToAssistant
    set result [list $::application::ask::Query \
        [expr {$messages eq $::application::assistant::Priv(messages)}]]
    set ::application::assistant::Priv(busy) $busy
    ::reviewWait 20
    set result
} -result {{new request while the previous request is working} 1}

tcltest::test review-action-error {dispatch failures are shown and preserve input} -body {
    set ::reviewMessages {}
    rename ::ui::message ::reviewRealMessage
    proc ::ui::message {args} {lappend ::reviewMessages $args}
    ::scidb::test::plan::action test.review.error error [dict create handler {apply {{args} {error {offline or missing file}}}}]
    set ::application::ask::Priv(rows) [list [list test.review.error {Review Error} {} 1 1]]
    set ::application::ask::Priv(index) 0
    set ::application::ask::Query {Review Error}
    ::application::ask::Choose
    set result [list $::application::ask::Query [string match {*offline or missing file*} $::reviewMessages]]
    dict unset ::action::Registry test.review.error
    rename ::ui::message {}
    rename ::reviewRealMessage ::ui::message
    set result
} -result {{Review Error} 1}


tcltest::test review-async-declined {a deferred decline skips dependent calls and clears approval} -body {
    ::scidb::test::plan::isolated {
        set ::reviewEffects {}
        ::scidb::test::plan::action test.plan.slow slow [dict create handler ::reviewLater]
        ::scidb::test::plan::action test.plan.next next [dict create handler ::reviewEffect confirm 1]
        set ::application::assistant::Priv(reqconfirm) ::scidb::test::plan::confirm
        set ::application::assistant::Priv(maxRounds) 0
        ::application::assistant::RunPlan 0 [::scidb::test::plan::calls {test.plan.slow test.plan.next}]
        ::application::assistant::Resolve $::reviewToken declined
        list $::reviewEffects $::application::assistant::Priv(planConfirmed) \
            [string match {*plan stopped at an earlier step*} [lindex [::scidb::test::plan::toolReplies] end]]
    }
} -result {{} 0 1}

tcltest::test review-async-dialog {deferred success waits for its dialog before continuing} -body {
    ::scidb::test::plan::isolated {
        set ::reviewEffects {}
        ::scidb::test::plan::action test.plan.slow slow [dict create handler ::reviewLater ends-in-dialog 1]
        ::scidb::test::plan::action test.plan.next next [dict create handler ::reviewEffect]
        set ::application::assistant::Priv(maxRounds) 0
        ::application::assistant::RunPlan 0 [::scidb::test::plan::calls {test.plan.slow test.plan.next}]
        toplevel .reviewDialog
        after 150 {destroy .reviewDialog}
        set started [clock milliseconds]
        ::application::assistant::Resolve $::reviewToken ok
        list $::reviewEffects [expr {[clock milliseconds] - $started >= 100}]
    }
} -result {effect 1}

tcltest::test review-plan-concrete-args {confirmation shows the checked target and executes exactly that target} -setup {
    rename ::application::assistant::correctArgs ::reviewCorrectArgs
    proc ::application::assistant::correctArgs {name cargs} {
        if {$name eq "test.plan.target"} {
            incr ::reviewCorrections
            return [dict create target "checked target $::reviewCorrections"]
        }
        return $cargs
    }
} -body {
    ::scidb::test::plan::isolated {
        set ::reviewCorrections 0
        set ::reviewTarget {}
        ::scidb::test::plan::action test.plan.target target [dict create confirm 1 what {delete %s} \
            args {{target {type string required 1}}} \
            handler {apply {{argsDict} {set ::reviewTarget [dict get $argsDict target]; return ok}}}]
        ::scidb::test::plan::action test.plan.next next {}
        set ::application::assistant::Priv(reqconfirm) ::scidb::test::plan::confirm
        set ::application::assistant::Priv(maxRounds) 0
        set call [dict create function [dict create name test.plan.target arguments [dict create target raw]]]
        ::application::assistant::RunPlan 0 [list $call [::scidb::test::plan::call test.plan.next]]
        list $::reviewTarget $::reviewCorrections \
            [string match {*delete checked target 1*} [lindex $::scidb::test::plan::ConfirmAsked 0]] \
            [llength $::scidb::test::plan::ConfirmAsked]
    }
} -cleanup {
    rename ::application::assistant::correctArgs {}
    rename ::reviewCorrectArgs ::application::assistant::correctArgs
} -result {{checked target 1} 1 1 1}

tcltest::test review-plan-invalid-tail {all arguments are validated before confirmation or any effect} -body {
    ::scidb::test::plan::isolated {
        set ::reviewEffects {}
        ::scidb::test::plan::action test.plan.first first [dict create handler ::reviewEffect confirm 1]
        ::scidb::test::plan::action test.plan.required required [dict create args {{target {type string required 1}}}]
        set ::application::assistant::Priv(reqconfirm) ::scidb::test::plan::confirm
        ::application::assistant::RunPlan 0 [::scidb::test::plan::calls {test.plan.first test.plan.required}]
        list $::reviewEffects $::scidb::test::plan::ConfirmAsked
    }
} -result {{} {}}

tcltest::test review-poll-exited-missing-output {missing output from an exited child finishes cleanly} -body {
    set ::application::speech::Priv(state) transcribing
    set ::application::speech::Priv(transcribeOut) {}
    set ::application::speech::Priv(transcribePids) {}
    set rc [catch {::application::speech::PollTranscribe} err]
    list $rc $::application::speech::Priv(state)
} -result {0 idle}

tcltest::test review-speech-private-files {symlink and permissive directories are refused and files are private and exclusive} -setup {
    set testTargetDir [file join [pwd] tests tmp-app finish]
    set base [tcltest::makeDirectory [format "review-private-temp-%d" [pid]] $testTargetDir]
    set hadTmp [info exists ::env(TMPDIR)]
    if {$hadTmp} {set savedTmp $::env(TMPDIR)}
    set ::env(TMPDIR) $base
} -body {
    set dir [file join $base chesswiz-ask-[exec id -u]]
    set target [file join $base target]
    file mkdir $target
    file link -symbolic $dir $target
    set symlink [catch {::application::speech::TempDir}]
    file delete $dir
    file mkdir $dir
    file attributes $dir -permissions 0777
    set public [catch {::application::speech::TempDir}]
    file attributes $dir -permissions 0700
    set first [::application::speech::TempFile .wav]
    set chan [open $first w]; puts $chan preserved; close $chan
    set second [::application::speech::TempFile .wav]
    set chan [open $first r]; set content [string trim [read $chan]]; close $chan
    list $symlink $public [file owned $dir] \
        [expr {([file attributes $dir -permissions] & 0077) == 0}] \
        [expr {([file attributes $first -permissions] & 0077) == 0}] \
        [expr {$first ne $second}] $content
} -cleanup {
    ::application::speech::Cancel
    if {$hadTmp} {set ::env(TMPDIR) $savedTmp} else {unset ::env(TMPDIR)}
    tcltest::removeDirectory [format "review-private-temp-%d" [pid]] $testTargetDir
} -result {1 1 1 1 1 1 preserved}

tcltest::test review-speech-dequeued-callback {a callback already dequeued at cancel cannot touch a replacement session} -setup {
    set savedSettings [array get ::application::speech::Settings]
} -body {
    ::application::speech::configure stub [list list old]
    ::application::speech::Start
    ::application::speech::StopRecording
    set callbacks {}
    foreach timer [after info] {
        set script [lindex [after info $timer] 0]
        if {[string match {*StartTranscribe*} $script]} {lappend callbacks $script}
    }
    ::application::speech::Cancel
    ::application::speech::configure stub [list list new]
    ::application::speech::Start
    ::application::speech::StopRecording
    set files $::application::speech::Priv(tempFiles)
    foreach script $callbacks {uplevel #0 $script}
    set same [expr {$files eq $::application::speech::Priv(tempFiles)}]
    list [expr {[llength $callbacks] > 0}] $same $::application::speech::Priv(state)
} -cleanup {
    ::application::speech::Cancel
    array set ::application::speech::Settings $savedSettings
} -result {1 1 transcribing}

tcltest::test review-speech-owner-destroy {destroying the field cancels processes, files and timers} -setup {
    set savedSettings [array get ::application::speech::Settings]
    rename ::application::ask::Entry ::reviewEntry
    proc ::application::ask::Entry {} {return .reviewOwner}
    ttk::entry .reviewOwner
} -body {
    ::application::speech::configure stub [list list unused]
    ::application::speech::Start
    ::application::speech::StopRecording
    destroy .reviewOwner
    list $::application::speech::Priv(state) $::application::speech::Priv(tempFiles) \
        $::application::speech::Priv(timers)
} -cleanup {
    ::application::speech::Cancel
    rename ::application::ask::Entry {}
    rename ::reviewEntry ::application::ask::Entry
    array set ::application::speech::Settings $savedSettings
} -result {idle {} {}}

tcltest::test review-assistant-unavailable {unavailable or raising assistant preserves editable input and reports why} -setup {
    rename ::application::assistant::ask ::reviewAsk
    rename ::application::assistant::show ::reviewShow
    proc ::application::assistant::show {} {}
    rename ::ui::message ::reviewMessage
    set ::reviewMessages {}
    proc ::ui::message {args} {lappend ::reviewMessages $args}
} -body {
    set ::application::ask::Query {keep this request}
    ::application::ask::SendToAssistant
    set missing $::application::ask::Query
    proc ::application::assistant::ask {args} {error {service unavailable}}
    ::application::ask::SendToAssistant
    list $missing $::application::ask::Query [llength $::reviewMessages]
} -cleanup {
    catch {rename ::application::assistant::ask {}}
    rename ::reviewAsk ::application::assistant::ask
    rename ::application::assistant::show {}
    rename ::reviewShow ::application::assistant::show
    rename ::ui::message {}
    rename ::reviewMessage ::ui::message
    set ::application::ask::Query {}
} -result {{keep this request} {keep this request} 2}

tcltest::test review-action-statuses {validation and decline stay visible and direct actions remain available while busy} -setup {
    rename ::ui::message ::reviewMessage
    set ::reviewMessages {}
    proc ::ui::message {args} {lappend ::reviewMessages $args}
    set savedHook $::action::ConfirmHook
    set ::action::ConfirmHook ::reviewNo
    set savedBusy $::application::assistant::Priv(busy)
} -body {
    ::scidb::test::plan::isolated {
        set ::application::assistant::Priv(busy) 1
        set ::reviewEffects {}
        set ::reviewAsked 0
        ::scidb::test::plan::action test.plan.required required [dict create args {{target {type string required 1}}}]
        ::scidb::test::plan::action test.plan.decline decline [dict create confirm 1]
        ::scidb::test::plan::action test.plan.direct direct [dict create handler ::reviewEffect]
        set kept {}
        foreach id {test.plan.required test.plan.decline test.plan.direct} {
            set ::application::ask::Priv(rows) [list [list $id $id {} 1 1]]
            set ::application::ask::Priv(index) 0
            set ::application::ask::Query $id
            ::application::ask::Choose
            lappend kept $::application::ask::Query
        }
        list $kept $::reviewEffects $::reviewAsked [llength $::reviewMessages]
    }
} -cleanup {
    set ::application::assistant::Priv(busy) $savedBusy
    set ::action::ConfirmHook $savedHook
    rename ::ui::message {}
    rename ::reviewMessage ::ui::message
    ::application::ask::HideList
    set ::application::ask::Query {}
} -result {{test.plan.required test.plan.decline {}} effect 1 2}

tcltest::cleanupTests
