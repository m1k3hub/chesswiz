# Headless Windows distribution regression: real startup and catalogs, fake Tk.
package require tcltest 2.5
set root [file normalize [file join [file dirname [info script]] ..]]
set fixture [file join $root tests tmp-app win-i18n fixture-[pid]]
set dist [file join $fixture {Chesswiz Ü [dist]}]
file mkdir $dist
# This worktree has no generated ../Makefile.in. Exercise the unchanged
# install target in isolation, without requiring a configured native build.
set f [open [file join $root tcl Makefile] r]
set makefile [read $f]
close $f
regexp {(?s)(install-localizations:.*?)(?:\n\nuninstall-localizations:)} $makefile -> target
set installMakefile [file join $fixture install.mk]
set f [open $installMakefile w]
puts $f $target
close $f
# Make's install recipes require a space-free staging path.
set staged [file join $fixture staged]
exec make -s -C [file join $root tcl] -f $installMakefile install-localizations SHAREDIR=$staged
file copy [file join $staged lang] $dist
file copy [file join $root tcl start.tcl] [file join $dist chesswiz.tcl]
namespace eval scidb::db {proc get args {return scratch}}
namespace eval debuglog {proc init {} {error STOP_AFTER_DIRECTORIES}}
namespace eval util {proc source args {}}
namespace eval options {proc hookWriter args {}}
namespace eval font {proc useLanguage args {}}
namespace eval annotation::mc {}
namespace eval application::keyEditor {proc RegisterActions {} {}}
proc tk args {return win32}
proc bind {w ev args} {
    if {[llength $args]} {set ::bindings($w,$ev) [lindex $args 0]}
}
proc event {op args} {
    if {$op ne {generate}} {return}
    lassign $args w ev
    if {[info exists ::bindings($w,$ev)]} {uplevel #0 $::bindings($w,$ev)}
}
proc winfo {op w} {
    if {$op eq {exists}} {return [expr {$w in {. .entries}}]}
    if {$op eq {children}} {return [expr {$w eq {.} ? [list .entries] : {}}]}
}
set ::env(SCIDB_USERDIR) [file join $fixture user]
file mkdir $::env(SCIDB_USERDIR)
unset -nocomplain ::env(SCIDB_SHAREDIR)
set ::nameofexecutable [file join $fixture wrong tkchesswiz.exe]
set platform $::tcl_platform(platform)
set ::tcl_platform(platform) windows
catch {source [file join $dist chesswiz.tcl]} startupError
set ::tcl_platform(platform) $platform

tcltest::test win-share-bundle {bundle catalogs survive an inaccurate executable probe} -body {
    list $startupError [expr {$::scidb::dir::share eq $dist}]
} -result {STOP_AFTER_DIRECTORIES 1}

tcltest::test win-share-override {explicit share directory still takes precedence} -body {
    set ::env(SCIDB_SHAREDIR) $staged
    set ::tcl_platform(platform) windows
    catch {source [file join $dist chesswiz.tcl]} err
    set ::tcl_platform(platform) $platform
    list $err [expr {$::scidb::dir::share eq $staged}]
} -result {STOP_AFTER_DIRECTORIES 1}

# Continue through the real catalog loader even when the startup test fails.
set ::scidb::dir::share $dist
source [file join $root tcl i18n.tcl]
source -encoding utf-8 [file join $dist lang localization.tcl]
source [file join $root tcl dropdown.tcl]
::mc::setup

# Keep the actual menu builder; replace only action registration and Tk widgets.
rename ::menu::RegisterTree ::menu::RealRegisterTree
proc ::menu::RegisterTree {} {}
rename ::menu::RegisterExtras ::menu::RealRegisterExtras
proc ::menu::RegisterExtras {} {}
proc ::menu::CascadeAccel args {return {}}
namespace eval tk {
    proc UnderlineAmpersand {s} {return [list [string map {& {}} $s] -1]}
}
proc menu {w args} {interp alias {} $w {} fakeMenu $w}
proc destroy {w} {rename $w {}}
proc fakeMenu {w op args} {
    if {$op eq {delete}} {set ::labels($w) {}}
    if {$op eq {add}} {lappend ::labels($w) [dict get [lrange $args 1 end] -label]}
}
menu .entries
set ::menu::DropdownTree {{cascade Tools {} {}}}

tcltest::test win-language-relabels {direct setLang updates an already built menu} -body {
    ::mc::setLang en
    ::menu::BuildDropdown .entries
    set before $::labels(.entries)
    ::mc::setLang de
    list $before $::labels(.entries) $::mc::langID
} -result {{{ Tools}} {{ Werkzeuge}} de}

tcltest::test win-catalog-encodings {installed Latin-1 and UTF-8 catalogs ignore system code page} -body {
    set saved [encoding system]
    # On Unix the system encoding also controls filesystem names. Use the
    # ASCII staging directory here; the Unicode layout is tested above.
    set ::scidb::dir::share $staged
    encoding system cp1252
    set out {}
    foreach id {de es it hu sv en} {
        ::mc::setLang $id
        lappend out $::mc::langID $::menu::mc::View
    }
    encoding system $saved
    set ::scidb::dir::share $dist
    set out
} -result {de Ansicht es Ver it Mostra hu Nézet sv Visa en View}

file delete -force $fixture
set failed $::tcltest::numTests(Failed)
::tcltest::cleanupTests
exit [expr {$failed > 0}]
