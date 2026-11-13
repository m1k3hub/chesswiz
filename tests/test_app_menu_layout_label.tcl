# A dialog label includes its ellipsis in its shared mc value. Both native
# layout menus and generated registry/Ask rows consume the complete label.
package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
set savedShare $::scidb::dir::share
set ::scidb::dir::share [file normalize [file join [file dirname [info script]] .. tcl]]
foreach language {en de es it hu sv} {
    tcltest::test layout-manager-label-$language {native and generated dialog labels keep one ellipsis} -body {
        ::menu::SwitchLanguage $language
        set label $::application::twm::mc::ManageLayouts
        set registry [dict get [::action::get menu.view.layout.manage] label]
        list [expr {$registry eq $label}] \
            [expr {[regexp {(…|\.\.\.)$} $label]}] \
            [expr {![regexp {(…|\.\.\.)(…|\.\.\.)$} $label]}] \
            [expr {$language eq "en" || $label ne "Manage Layouts…"}]
    } -result {1 1 1 1}
}
::menu::SwitchLanguage en
set ::scidb::dir::share $savedShare
::tcltest::cleanupTests
