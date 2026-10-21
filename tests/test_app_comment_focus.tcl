# A native activation may queue focus work for the currently grabbed dialog.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
tcltest::testConstraint aqua [expr {[tk windowingsystem] eq "aqua"}]

tcltest::test comment-close-pending-native-focus {release the grab and drain native idle work before destroying its target} -constraints aqua -setup {
    set savedLanguages $::comment::Vars(langSet)
    toplevel .commentFocusProbe
    entry .commentFocusProbe.text
    pack .commentFocusProbe.text
    update
    ttk::grabWindow .commentFocusProbe
    set observed {}
} -body {
    # Model the native idle callback's target lifetime using the real Tk
    # window and grab. The crashing C callback cannot safely report failure.
    after idle {set observed [list [winfo exists .commentFocusProbe] [grab current]]}
    ::comment::Close .commentFocusProbe
    update idletasks
    list $observed [winfo exists .commentFocusProbe]
} -cleanup {
    catch {destroy .commentFocusProbe}
    ttk::releaseGrab .commentFocusProbe
    set ::comment::Vars(langSet) $savedLanguages
} -result {{1 {}} 0}

tcltest::test comment-close-releases-dialog {the production close callback destroys its window and clears language state} -setup {
    set savedLanguages $::comment::Vars(langSet)
    toplevel .commentFocusProbe
    update
    ttk::grabWindow .commentFocusProbe
    set ::comment::Vars(langSet) {en de}
} -body {
    ::comment::Close .commentFocusProbe
    update idletasks
    list [winfo exists .commentFocusProbe] [grab current] $::comment::Vars(langSet)
} -cleanup {
    catch {destroy .commentFocusProbe}
    ttk::releaseGrab .commentFocusProbe
    set ::comment::Vars(langSet) $savedLanguages
} -result {0 {} {}}

tcltest::cleanupTests
