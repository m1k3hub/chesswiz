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
tcltest::test dictation-win-click {mic focuses input before requesting Win+H with SendInput} -setup {
    ::scidb::test::dictation::Install windows
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
    ::scidb::test::dictation::Restore
} -result {1 {powershell -NoProfile -NonInteractive -WindowStyle Hidden -Command} 1 1 {}}
tcltest::cleanupTests
