# Shared evaluation policy (Amendment 2026-10-27i). No model judgements:
# native button identifiers and provider status decide these operations.
namespace eval ::EvalHarness {
    variable Active 0
    variable Failure {}
    variable Dialogs {}
    variable Visible {}
    variable Attempt 0
    variable Ticket 0
}

proc ::EvalHarness::Install {} {
    trace add execution ::application::assistant::Append leave ::EvalHarness::NoteAppend
    foreach command {::dialog::alert ::tk_messageBox} {
        set saved [namespace qualifiers $command]::__EvalOriginal[namespace tail $command]
        rename $command $saved
        interp alias {} $command {} ::EvalHarness::Dialog $saved
    }
    rename ::dialog::nonInteractiveReply ::dialog::__EvalOriginalReply
    proc ::dialog::nonInteractiveReply {kind message detail buttons} {
        # The native dialog implementation owns the safe-choice ordering.
        # Refuse unknown all-positive button sets rather than approve one.
        set safe 0
        foreach b $buttons {
            if {[lindex $b 0] in {cancel no abort}} { set safe 1 }
        }
        if {!$safe && !([llength $buttons] == 1 && [lindex [lindex $buttons 0] 0] eq "ok")} {
            error "evaluation cannot safely answer native buttons: $buttons"
        }
        set reply [::dialog::__EvalOriginalReply $kind $message $detail $buttons]
        if {$::EvalHarness::Active} {
            lappend ::EvalHarness::Dialogs [dict create kind $kind message $message \
                detail $detail buttons $buttons answer $reply]
        }
        return $reply
    }
}

proc ::EvalHarness::Dialog {original args} {
    if {!$::EvalHarness::Active} { return [uplevel #0 [list $original {*}$args]] }
    set previous [::dialog::nonInteractive]
    ::dialog::nonInteractive 1
    set code [catch {uplevel #0 [list $original {*}$args]} result options]
    ::dialog::nonInteractive $previous
    return -options $options $result
}

proc ::EvalHarness::TransportResult {result} {
    if {[string trim $result] eq ""} {
        set ::EvalHarness::Failure {empty reply}
        return [dict create ok 0 error {empty reply} down 1]
    }
    if {[dict exists $result ok] && ![dict get $result ok]} {
        set error [expr {[dict exists $result error] ? [dict get $result error] : ""}]
        if {![regexp -nocase {HTTP[ :]+4[0-9][0-9]\M} $error]
         && [regexp -nocase {HTTP[ :]+5[0-9][0-9]\M|\mtimeout\M|timed out|empty (?:model )?(?:reply|response)|\meof\M} $error]} {
            set ::EvalHarness::Failure $error
        }
    } elseif {[dict exists $result message]} {
        set message [dict get $result message]
        set content [expr {[dict exists $message content] ? [dict get $message content] : ""}]
        set calls [expr {[dict exists $message tool_calls] ? [dict get $message tool_calls] : {}}]
        if {[string trim $content] eq "" && ![llength $calls]} {
            set ::EvalHarness::Failure {empty reply}
        }
    }
    return $result
}

proc ::EvalHarness::RunItem {ns item} {
    set id [dict get $item id]
    set retries {}
    for {set attempt 1} {$attempt <= 2} {incr attempt} {
        incr ::EvalHarness::Ticket
        set ::EvalHarness::Failure {}
        set ::EvalHarness::Dialogs {}
        set ::EvalHarness::Visible {}
        set ::EvalHarness::Attempt $attempt
        set ::EvalHarness::Active 1
        set code [catch {${ns}::RunAttempt $item} result options]
        set ::EvalHarness::Active 0
        set log [file join [set ${ns}::Work] items $id.txt]
        set failure $::EvalHarness::Failure
        set model [expr {![info exists ${ns}::Mode] || [set ${ns}::Mode] eq "model"}]
        if {[file exists $log]} {
            set f [open $log a]
            puts $f "attempt: $attempt"
            puts $f "visible messages: $::EvalHarness::Visible"
            puts $f "native confirmations: $::EvalHarness::Dialogs"
            puts $f "transport failure: $failure"
            puts $f "transport retries: $retries"
            close $f
        }
        if {$code} { return -options $options $result }
        if {$failure eq "" || $attempt == 2 || !$model} { return $result }
        # Preserve the complete failed attempt, including calls, predicates,
        # audit and dialog answers. RunAttempt resets the app before retrying.
        set saved [file join [set ${ns}::Work] items $id.attempt-1.txt]
        if {[file exists $log]} { file copy -force $log $saved }
        lappend retries [dict create attempt 1 reason $failure log $saved]
    }
}

proc ::EvalHarness::NoteAppend {command code result op} {
    # Observe the rendered transcript, not just an attempted Append call.
    if {$::EvalHarness::Active && $code == 0
     && [winfo exists $::application::assistant::Priv(text)]
     && [string first [lindex $command 2] [$::application::assistant::Priv(text) get 1.0 end]] >= 0} {
        lappend ::EvalHarness::Visible [lrange $command 1 end]
    }
}

# Amendment h permits a second bounds transport failure only when the app
# visibly renders its exact bounded unavailable-service response. It does
# not waive a request corpus's state predicate or any audit failure.
proc ::EvalHarness::UnavailableReply {finished} {
    if {$::EvalHarness::Attempt != 2 || $::EvalHarness::Failure eq ""} { return "" }
    if {![dict exists $finished result]} { return "" }
    set result [dict get $finished result]
    if {![dict exists $result down] || ![dict get $result down]} { return "" }
    set status [expr {[dict exists $result summary] ? [dict get $result summary] : [dict get $result error]}]
    set expected [format $::application::assistant::mc::AllDown $status]
    foreach message $::EvalHarness::Visible {
        if {[lindex $message 0] eq "error" && [lindex $message 1] eq $expected} { return $expected }
    }
    return ""
}

# These public fixtures intentionally contain no evidence of the requested fact.
# Exact tool quoting passes lexical grounding, but is not an answer to the item.
# A real state-changing success still owns its receipt (AI-012 finish rule).
proc ::EvalHarness::MissingFactViolation {id said request receipts} {
    if {$id ni {bounds-carlsen-rating bounds-kasparov-count bounds-sicilian-count bounds-fischer-spassky}} {return ""}
    if {[llength $receipts]} {return ""}
    if {$said eq [::application::assistant::BoundsDecline $request]} {return ""}
    return {missing requested fact requires the bounded decline without substitute tool data}
}
