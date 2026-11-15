# ======================================================================
# VAL-KNOW-008: the properties window must really show, and the opening
# preparation report must name itself so the request's state check sees it.
#
# Both failed the frozen request corpus: menu.db.properties left the
# window withdrawn (::util::place was given the switcher canvas as its
# parent), and open_view opening_report opened a window whose title did
# not read as opening preparation.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::know008 {
    variable savedTree ""
}

proc ::scidb::test::know008::propertiesDialog {} {
    set switcher $::application::database::Vars(switcher)
    set base [::menu::CurrentBase]
    set canv $switcher.content
    return $canv.prop_[regsub -all {[^[:alnum:]]} $base _]
}

proc ::scidb::test::know008::closeProperties {} {
    catch { destroy [propertiesDialog] }
    update
}

proc ::scidb::test::know008::useTreeBase {} {
    variable savedTree
    set savedTree [::scidb::tree::get]
    set base [::scidb::db::get name]
    if {$base ne ""} { catch { ::scidb::tree::set $base } }
    return $base
}

proc ::scidb::test::know008::restoreTree {} {
    variable savedTree
    catch { ::scidb::tree::set $savedTree }
}

tcltest::test know008-d2-props {menu.db.properties shows a mapped Properties window} -setup {
    ::scidb::test::know008::closeProperties
} -body {
    set dlg [::scidb::test::know008::propertiesDialog]
    set before [winfo exists $dlg]
    ::action::run menu.db.properties
    update
    set exists [winfo exists $dlg]
    list $before $exists \
        [expr {$exists && [winfo ismapped $dlg]}] \
        [expr {$exists ? [wm state $dlg] : {missing}}]
} -cleanup {
    ::scidb::test::know008::closeProperties
} -result {0 1 1 normal}

tcltest::test know008-t2-prep {open_view opening_report names an opening preparation report} -setup {
    ::scidb::test::know008::useTreeBase
    catch { destroy .openingReport }
    update
} -body {
    set reply [::application::assistant::runTool open_view {kind opening_report}]
    update
    set title [expr {[winfo exists .openingReport] ? [wm title .openingReport] : {}}]
    list [string match {error:*} $reply] \
        [expr {[regexp -nocase {eco|opening prep} .openingReport]
               || [regexp -nocase {eco|opening prep} $title]}] $title
} -cleanup {
    catch { destroy .openingReport }
    ::scidb::test::know008::restoreTree
} -match glob -result {0 1 {Opening Preparation Report}}

::tcltest::cleanupTests
return
