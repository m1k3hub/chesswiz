# Native dictation hands input to the Ask entry and never submits it.
# OS activation is the only stub; focus, button, tooltip and status are real Tk.
package require tcltest 2.5
namespace eval ::scidb::test::dictation {}
proc ::scidb::test::dictation::Install {mode} {
    rename ::application::speech::detect ::scidb::test::dictation::Detect
    proc ::application::speech::detect {} [list return [dict create mode $mode available 1 cli {} model {} recorder {}]]
    proc ::application::speech::exec {args} {
        set ::scidb::test::dictation::activation $args
        return {}
    }
    set ::scidb::test::dictation::activation {}
    rename ::application::assistant::ask ::scidb::test::dictation::Ask
    proc ::application::assistant::ask {args} { error {Dictation submitted a request} }
    set ::application::speech::Priv(state) idle
    ::application::ask::SyncMic
    [::application::ask::Entry] delete 0 end
    focus -force .application
    update
}
proc ::scidb::test::dictation::Restore {} {
    rename ::application::speech::detect {}
    rename ::scidb::test::dictation::Detect ::application::speech::detect
    rename ::application::speech::exec {}
    rename ::application::assistant::ask {}
    rename ::scidb::test::dictation::Ask ::application::assistant::ask
    ::application::speech::Cancel
    catch {destroy .application.nb.dictationHint}
    ::application::ask::SyncMic
}
tcltest::test dictation-mac-click {mic focuses input and displays the system shortcut} -setup {
    ::scidb::test::dictation::Install mac
} -body {
    [::application::ask::Mic] invoke
    update
    set entry [::application::ask::Entry]
    $entry insert 0 "R\u00e9ti opening"
    list [expr {[focus] eq $entry}] [$entry get] \
        [expr {[::tooltip::tooltip [::application::ask::Mic]] eq "::application::ask::Priv(micHint)"}] \
        [string match {*dictation key*Fn Fn*} $::application::ask::Priv(micHint)] \
        [winfo ismapped .application.nb.dictationHint] \
        [expr {[::application::speech::LastHint] eq $::application::speech::mc::InstallMac}] \
        $::scidb::test::dictation::activation
} -cleanup {
    ::scidb::test::dictation::Restore
} -result {1 {Réti opening} 1 1 1 1 {}}
proc ::scidb::test::dictation::StubHelper {} {
    proc ::application::speech::open {args} {
        set ::scidb::test::dictation::activation [string range [lindex $args 0] 1 end]
        error {no powershell in tests}
    }
}
proc ::scidb::test::dictation::StubNative {} {
    # The native Win32 EDIT is the only stub; it records calls and exposes its text.
    namespace eval ::chesswiz::win {}
    set ::scidb::test::dictation::native {}
    set ::scidb::test::dictation::active 0
    proc ::chesswiz::win::dictateEdit {sub args} {
        lappend ::scidb::test::dictation::native [list $sub {*}$args]
        switch -- $sub {
            begin  { set ::scidb::test::dictation::active 1; set ::scidb::test::dictation::text [lindex $args 1] }
            active { return $::scidb::test::dictation::active }
            settext { set ::scidb::test::dictation::text [lindex $args 0] }
            get    { return $::scidb::test::dictation::text }
            commit - cancel {
                set ::scidb::test::dictation::active 0
                set text [expr {$sub eq "commit" ? $::scidb::test::dictation::text : {}}]
                after idle [list ::application::speech::DictateFinish $sub $text]
            }
        }
        return
    }
}
proc ::scidb::test::dictation::RestoreNative {} {
    catch { rename ::chesswiz::win::dictateEdit {} }
    catch { rename ::application::speech::open {} }
}
tcltest::test dictation-win-click {without the native field the mic requests Win+H with SendInput} -setup {
    ::scidb::test::dictation::Install windows
    ::scidb::test::dictation::StubHelper
} -body {
    [::application::ask::Mic] invoke
    set invocation $::scidb::test::dictation::activation
    set script [lindex $invocation end]
    list [expr {[focus] eq [::application::ask::Entry]}] \
        [lrange $invocation 0 5] \
        [string match {*SendInput(4,*} $script] \
        [expr {[string first keybd_event $script] < 0}] \
        [[::application::ask::Entry] get]
} -cleanup {
    ::scidb::test::dictation::RestoreNative
    ::scidb::test::dictation::Restore
} -result {1 {powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command} 1 1 {}}
tcltest::test dictation-win-edit-commit {the native field is seeded from the entry and commits Unicode without sending} -setup {
    ::scidb::test::dictation::Install windows
    ::scidb::test::dictation::StubHelper
    ::scidb::test::dictation::StubNative
} -body {
    set entry [::application::ask::Entry]
    $entry insert 0 "Play the "
    $entry icursor 4
    [::application::ask::Mic] invoke
    set begin [lindex $::scidb::test::dictation::native 1]
    ::chesswiz::win::dictateEdit settext "Play the Réti opening"
    ::chesswiz::win::dictateEdit commit
    update
    list [lrange $begin 0 3] [lindex $begin end] \
        [expr {[string length [lindex $begin 4]] > 0}] [string is integer -strict [lindex $begin 5]] \
        $::scidb::test::dictation::activation \
        [$entry get] [encoding convertto utf-8 [$entry get]] [$entry index insert] \
        [expr {[focus] eq $entry}] [::chesswiz::win::dictateEdit active]
} -cleanup {
    ::scidb::test::dictation::RestoreNative
    ::scidb::test::dictation::Restore
} -result [list {begin .application.nb.ask.entry {Play the } 4} ::application::speech::DictateFinish 1 1 {} \
    "Play the Réti opening" "Play the R\xc3\xa9ti opening" 21 1 0]
tcltest::test dictation-win-edit-cancel {Esc in the native field keeps the original entry text} -setup {
    ::scidb::test::dictation::Install windows
    ::scidb::test::dictation::StubNative
} -body {
    set entry [::application::ask::Entry]
    $entry insert 0 "Réti"
    [::application::ask::Mic] invoke
    ::chesswiz::win::dictateEdit settext "something else"
    ::chesswiz::win::dictateEdit cancel
    update
    list [$entry get] [expr {[focus] eq $entry}] [::chesswiz::win::dictateEdit active]
} -cleanup {
    ::scidb::test::dictation::RestoreNative
    ::scidb::test::dictation::Restore
} -result [list "Réti" 1 0]
tcltest::test dictation-win-edit-busy {a second click while dictating does not start another field} -setup {
    ::scidb::test::dictation::Install windows
    ::scidb::test::dictation::StubNative
} -body {
    [::application::ask::Mic] invoke
    [::application::ask::Mic] invoke
    set begins [llength [lsearch -all -index 0 $::scidb::test::dictation::native begin]]
    ::application::speech::Cancel
    update
    list $begins [::chesswiz::win::dictateEdit active]
} -cleanup {
    ::scidb::test::dictation::RestoreNative
    ::scidb::test::dictation::Restore
} -result {1 0}
tcltest::cleanupTests
