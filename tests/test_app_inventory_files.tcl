package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::fileactions {
    proc call {id args} {
        set result [::knowledge::RunAction $id $args]
        if {[string match error:* $result]} {error $result}
        return $result
    }
    proc inspect {parent file} {
        set ch [open $file];set text [read $ch];close $ch
        set ch [open $file.inspected w];puts -nonewline $ch $text;close $ch
    }
    proc companions {source destination} {return [list $source $destination $source.meta $destination.meta]}
    proc used {path} {expr {[file tail $path] eq "protected.txt"}}
    proc yes {args} {return 1}
    proc no {args} {return 0}
}
tcltest::test inventory-file-mutations {real picker file operations accept names, preserve bytes and enforce confirmation} -setup {
    ::scidb::test::actions::ready
    set dir [file join $::env(HOME) fileops]
    file mkdir $dir
    set src [file join $dir source.txt]
    set f [open $src w];puts -nonewline $f Generated;close $f
    toplevel .fileactions
    ::fsbox::fsbox .fileactions.picker open -initialdir $dir -customcommand ::scidb::test::fileactions::inspect
    pack .fileactions.picker -fill both -expand 1
    update
    set windows [wm stackorder .]
    set originalHook $::action::ConfirmHook
} -body {
    set w .fileactions.picker
    set renamed [::scidb::test::fileactions::call files.mutate widget $w operation rename path $src name renamed.txt]
    set copied [::scidb::test::fileactions::call files.mutate widget $w operation duplicate path $renamed name copied.txt]
    set f [open $copied];set bytes [read $f];close $f
    set folder [::scidb::test::fileactions::call files.mutate widget $w operation mkdir name GeneratedFolder]
    set ::action::ConfirmHook ::scidb::test::fileactions::no
    set declined [::knowledge::RunAction files.delete [list widget $w path $copied]]
    set protected [file exists $copied]
    set ::action::ConfirmHook ::scidb::test::fileactions::yes
    ::scidb::test::fileactions::call files.delete widget $w path $copied
    ::scidb::test::fileactions::call files.delete widget $w path $folder
    ::scidb::test::fileactions::call files.picker widget $w operation custom path $renamed
    set f [open $renamed.inspected];set inspected [read $f];close $f
    list [file exists $src] [file exists $renamed] $bytes $protected \
        [file exists $copied] [file exists $folder] $inspected [expr {[wm stackorder .] eq $windows}] \
        [string match error:* [::knowledge::RunAction files.mutate [list widget $w operation mkdir name ../invalid]]] \
        [string match error:* [::knowledge::RunAction files.mutate [list widget $w operation rename path $renamed name renamed.txt]]]
} -cleanup {
    set ::action::ConfirmHook $originalHook
    destroy .fileactions
    file delete -force $dir
} -result {0 1 Generated 1 0 0 Generated 1 1 1}

tcltest::test inventory-file-errors {companion collision and files in use return errors without opening a dialog or partially copying} -setup {
    ::scidb::test::actions::ready
    set dir [file join $::env(HOME) fileerrors]
    file mkdir $dir
    foreach name {source.txt source.txt.meta target.txt.meta protected.txt} {
        set ch [open [file join $dir $name] w]; puts $ch Generated; close $ch
    }
    toplevel .fileerrors
    ::fsbox::fsbox .fileerrors.picker open -initialdir $dir -duplicatecommand ::scidb::test::fileactions::companions -isusedcommand ::scidb::test::fileactions::used
    pack .fileerrors.picker -fill both -expand 1
    update
    set windows [wm stackorder .]
} -body {
    set collision [::knowledge::RunAction files.mutate [list widget .fileerrors.picker operation duplicate path [file join $dir source.txt] name target.txt]]
    set used [::knowledge::RunAction files.mutate [list widget .fileerrors.picker operation rename path [file join $dir protected.txt] name new.txt]]
    set copied [::scidb::test::fileactions::call files.mutate widget .fileerrors.picker operation duplicate path [file join $dir protected.txt] name allowed-copy.txt]
    if {![file exists $copied]} {error "read-only duplication of a file in use was incorrectly blocked"}
    list [string match error:* $collision] [file exists [file join $dir target.txt]] \
        [string match {*source is currently in use*} $used] [file exists [file join $dir protected.txt]] \
        [expr {[wm stackorder .] eq $windows}]
} -cleanup {destroy .fileerrors; file delete -force $dir} -result {1 0 1 1 1}

tcltest::test inventory-file-copy-failure {native copy failure returns directly and removes the progress window} -setup {
    ::scidb::test::actions::ready
    set dir [file join $::env(HOME) filecopyfailure]
    file mkdir $dir
    set src [file join $dir source.txt]
    set ch [open $src w];puts $ch Generated;close $ch
    toplevel .filecopyfailure
    ::fsbox::fsbox .filecopyfailure.picker open -initialdir $dir
    pack .filecopyfailure.picker -fill both -expand 1
    update
    set windows [wm stackorder .]
    file attributes $dir -permissions 0500
} -body {
    set reply [::knowledge::RunAction files.mutate [list widget .filecopyfailure.picker operation duplicate path $src name target.txt]]
    list [string match error:* $reply] [file exists $src] [file exists [file join $dir target.txt]] [expr {[wm stackorder .] eq $windows}]
} -cleanup {
    file attributes $dir -permissions 0700
    destroy .filecopyfailure
    file delete -force $dir
} -result {1 1 0 1}

tcltest::cleanupTests
