# ======================================================================
# Scidb App Test - Ask Field help page opens in help dialog
# ======================================================================

package require tcltest 2.5

set repoRoot [file dirname [file dirname [file normalize [info script]]]]
set ::scidb::dir::help [file join $repoRoot tcl help]

tcltest::test app-ask-help-opens {::help::open .application Ask-Field opens the help dialog showing Ask-Field.html} -body {
    set ::askHelpErr {}
    proc ::bgerror {msg} { set ::askHelpErr $msg }
    set dlg [::help::open .application Ask-Field]
    update
    after 500 {set ::askHelpWait 1}; vwait ::askHelpWait
    set pageLoaded [expr {[info exists ::help::Priv(current:file)] ? [file tail $::help::Priv(current:file)] : ""}]
    set exists [winfo exists .help]
    if {[winfo exists .help]} {
        catch { destroy .help }
    }
    list $exists $::askHelpErr $pageLoaded
} -result {1 {} Ask-Field.html}

tcltest::test app-ask-f1-binding {F1 in the Ask field entry opens Ask-Field.html} -body {
    set ::askHelpErr {}
    proc ::bgerror {msg} { set ::askHelpErr $msg }
    set entry [::application::ask::Entry]
    if {![winfo exists $entry]} {
        return "entry not found"
    }
    focus -force $entry
    update
    event generate $entry <KeyPress-F1> -keysym F1
    update
    after 500 {set ::askHelpWait 1}; vwait ::askHelpWait
    set pageLoaded [expr {[info exists ::help::Priv(current:file)] ? [file tail $::help::Priv(current:file)] : ""}]
    set exists [winfo exists .help]
    if {[winfo exists .help]} {
        catch { destroy .help }
    }
    list $exists $::askHelpErr $pageLoaded
} -result {1 {} Ask-Field.html}

tcltest::test app-ask-prefs-f1-binding {F1 in Assistant Preferences opens Ask-Field.html} -body {
    set ::askHelpErr {}
    proc ::bgerror {msg} { set ::askHelpErr $msg }
    ::application::ask::Preferences
    set dlg .application.assistantPreferences
    if {![winfo exists $dlg]} {
        return "preferences dialog not found"
    }
    focus -force $dlg
    update
    event generate $dlg <KeyPress-F1> -keysym F1
    update
    after 500 {set ::askHelpWait 1}; vwait ::askHelpWait
    set pageLoaded [expr {[info exists ::help::Priv(current:file)] ? [file tail $::help::Priv(current:file)] : ""}]
    set exists [winfo exists .help]
    if {[winfo exists .help]} {
        catch { destroy .help }
    }
    if {[winfo exists $dlg]} {
        catch { destroy $dlg }
    }
    list $exists $::askHelpErr $pageLoaded
} -result {1 {} Ask-Field.html}

tcltest::test app-ask-help-opens-de {::help::open in German opens the German help page} -body {
    set ::askHelpErr {}
    proc ::bgerror {msg} { set ::askHelpErr $msg }
    set origLang $::mc::langID
    ::mc::setLang de
    after 100 {
        if {[winfo exists .application.lang]} {
            set ::help::Options(lang) ""
        }
    }
    set dlg [::help::open .application Ask-Field]
    update
    after 500 {set ::askHelpWait 1}; vwait ::askHelpWait
    set pageLoaded [expr {[info exists ::help::Priv(current:file)] ? [file tail $::help::Priv(current:file)] : ""}]
    set pageLang [expr {[info exists ::help::Priv(current:lang)] ? $::help::Priv(current:lang) : ""}]
    set exists [winfo exists .help]
    if {[winfo exists .help]} {
        catch { destroy .help }
    }
    ::mc::setLang $origLang
    list $exists $::askHelpErr $pageLoaded $pageLang
} -result {1 {} Ask-Field.html de}

tcltest::test app-ask-f1-binding-de {F1 in the Ask field entry in German opens German Ask-Field.html} -body {
    set ::askHelpErr {}
    proc ::bgerror {msg} { set ::askHelpErr $msg }
    set origLang $::mc::langID
    ::mc::setLang de
    set entry [::application::ask::Entry]
    if {![winfo exists $entry]} {
        ::mc::setLang $origLang
        return "entry not found"
    }
    focus -force $entry
    update
    event generate $entry <KeyPress-F1> -keysym F1
    update
    after 500 {set ::askHelpWait 1}; vwait ::askHelpWait
    set pageLoaded [expr {[info exists ::help::Priv(current:file)] ? [file tail $::help::Priv(current:file)] : ""}]
    set pageLang [expr {[info exists ::help::Priv(current:lang)] ? $::help::Priv(current:lang) : ""}]
    set exists [winfo exists .help]
    if {[winfo exists .help]} {
        catch { destroy .help }
    }
    ::mc::setLang $origLang
    list $exists $::askHelpErr $pageLoaded $pageLang
} -result {1 {} Ask-Field.html de}

tcltest::cleanupTests
