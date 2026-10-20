# ======================================================================
# Brand and Version 1.0 Release Tests (G32)
#
# Verifies:
# - Version 1.0 in Makefile.version, tcl/exec.tcl, src/tcl/tcl_misc.cpp,
#   scripts/chesswiz.iss, macOS packaging scripts, freedesktop desktop file,
#   debian packaging metadata.
# - No "BETA" or "beta" in generated version strings or installer/package specs.
# - Executable --version output reports "Chesswiz version 1.0" without beta.
# - README has no sourceforge links, no "Wanted: testers", no competitor names,
#   no CQL, covers key features (databases, engines, analysis, 3D board, media,
#   assistant that runs the app for you), covers install on Linux/Windows/macOS,
#   build from source, licence, and keeps the upstream credits section.
# - Man page sources have no sourceforge links or beta wording, and the
#   legacy scidb-beta manpage is replaced with chesswiz.1.gz.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::brand {

variable repoRoot [file dirname [file dirname [file normalize [info script]]]]

proc slurp {path} {
    set fd [open $path r]
    fconfigure $fd -encoding utf-8
    set data [read $fd]
    close $fd
    return $data
}

# 1. Makefile.version
tcltest::test version-makefile-01 {Makefile.version defines version 1.0 without beta} -body {
    variable repoRoot
    set content [slurp [file join $repoRoot Makefile.version]]
    set hasVersion [regexp {SCIDB_VERSION\s*=\s*-DSCIDB_VERSION="\\"1\.0\\""} $content]
    set hasBeta [regexp -nocase {beta} $content]
    list $hasVersion $hasBeta
} -result {1 0}

# 2. tcl/exec.tcl
tcltest::test version-tcl-exec-02 {tcl/exec.tcl defines version 1.0 without beta} -body {
    variable repoRoot
    set content [slurp [file join $repoRoot tcl exec.tcl]]
    set match [regexp {set\s+version\s+"([^"]+)"} $content -> ver]
    set is10 [expr {$match && $ver eq "1.0"}]
    set hasBeta [regexp -nocase {beta} $ver]
    list $is10 $hasBeta
} -result {1 0}

# 3. src/tcl/tcl_misc.cpp
tcltest::test version-tcl-misc-03 {src/tcl/tcl_misc.cpp defines SCIDB_VERSION 1.0 without beta} -body {
    variable repoRoot
    set content [slurp [file join $repoRoot src tcl tcl_misc.cpp]]
    set match [regexp {#\s*define\s+SCIDB_VERSION\s+"([^"]+)"} $content -> ver]
    set is10 [expr {$match && $ver eq "1.0"}]
    set hasBeta [regexp -nocase {beta} $ver]
    list $is10 $hasBeta
} -result {1 0}

# 4. scripts/chesswiz.iss
tcltest::test version-inno-iss-04 {scripts/chesswiz.iss sets AppVersion 1.0 without beta} -body {
    variable repoRoot
    set content [slurp [file join $repoRoot scripts chesswiz.iss]]
    set match [regexp {#define\s+AppVersion\s+"([^"]+)"} $content -> ver]
    set is10 [expr {$match && $ver eq "1.0"}]
    set hasBeta [regexp -nocase {beta} $ver]
    list $is10 $hasBeta
} -result {1 0}

# 5. scripts/make-macos-run.sh
tcltest::test version-macos-run-05 {scripts/make-macos-run.sh plist defines version 1.0 without beta} -body {
    variable repoRoot
    set content [slurp [file join $repoRoot scripts make-macos-run.sh]]
    set hasVersion10 [regexp {<key>CFBundleVersion</key><string>1\.0</string>} $content]
    set hasShortVersion10 [regexp {<key>CFBundleShortVersionString</key><string>1\.0</string>} $content]
    set hasBeta [regexp -nocase {beta} $content]
    list [expr {$hasVersion10 && $hasShortVersion10}] $hasBeta
} -result {1 0}

# 6. scripts/make-macos-app.sh
tcltest::test version-macos-app-06 {scripts/make-macos-app.sh defaults CHESSWIZ_VERSION to 1.0 without beta} -body {
    variable repoRoot
    set content [slurp [file join $repoRoot scripts make-macos-app.sh]]
    set match [regexp {CHESSWIZ_VERSION:-([^"\}]+)} $content -> ver]
    set is10 [expr {$match && $ver eq "1.0"}]
    set hasBeta [regexp -nocase {beta} $ver]
    list $is10 $hasBeta
} -result {1 0}

# 7. freedesktop.org/chesswiz.desktop
tcltest::test version-desktop-file-07 {chesswiz.desktop defines Version 1.0 without beta} -body {
    variable repoRoot
    set content [slurp [file join $repoRoot freedesktop.org chesswiz.desktop]]
    set hasVer [regexp {Version=1\.0} $content]
    set hasBeta [regexp -nocase {beta} $content]
    set deOk [regexp {GenericName\[de\]=Schachdatenbank} $content]
    set enOk [regexp {GenericName\[en\]=Chess Database} $content]
    list $hasVer $hasBeta $deOk $enOk
} -result {1 0 1 1}

# 8. debian/control & description-pak
tcltest::test version-debian-meta-08 {debian/control and description-pak have no beta in description} -body {
    variable repoRoot
    set control [slurp [file join $repoRoot debian control]]
    set pak [slurp [file join $repoRoot description-pak]]
    set cBeta [regexp -line -nocase {^Description:.*beta} $control]
    set pBeta [regexp -nocase {beta} $pak]
    list $cBeta $pBeta
} -result {0 0}

# 9. Executable runtime --version
tcltest::test version-runtime-cli-09 {runtime --version reports 1.0 without beta} -body {
    variable repoRoot
    set exeCandidates [list \
        [file join $repoRoot src tkchesswiz] \
        "/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/src/tkchesswiz" \
    ]
    set exe ""
    foreach cand $exeCandidates {
        if {[file executable $cand]} {
            set exe $cand
            break
        }
    }
    if {$exe eq ""} {
        return "no-executable"
    }
    set bundle [file join $repoRoot tcl chesswiz]
    set out [exec $exe -encoding utf-8 $bundle --version]
    set is10 [regexp {Chesswiz version 1\.0} $out]
    set hasBeta [regexp -nocase {beta} $out]
    list $is10 $hasBeta
} -result {1 0}

# 10. README sourceforge check
tcltest::test readme-no-sourceforge-10 {README has no sourceforge links} -body {
    variable repoRoot
    set content [slurp [file join $repoRoot README]]
    regexp -nocase {sourceforge} $content
} -result 0

# 11. README competitor names and CQL check
tcltest::test readme-no-competitor-cql-11 {README does not name competitors or CQL in body} -body {
    variable repoRoot
    set content [slurp [file join $repoRoot README]]
    # Split body before Credits
    set parts [split $content "\n"]
    set bodyLines {}
    foreach line $parts {
        if {[string match "*Credits*" $line]} {
            break
        }
        lappend bodyLines $line
    }
    set body [join $bodyLines "\n"]
    set bad {}
    if {[regexp -nocase {\m(scid|chessbase|fritz|arena)\M} $body m]} {
        lappend bad "competitor:$m"
    }
    if {[regexp -nocase {\mcql\M} $content m]} {
        lappend bad "cql:$m"
    }
    if {[regexp -nocase {wanted:\s*testers} $content]} {
        lappend bad "wanted-testers"
    }
    join $bad ","
} -result ""

# 12. README key features and install instructions
tcltest::test readme-required-sections-12 {README contains key features and platform install instructions} -body {
    variable repoRoot
    set content [slurp [file join $repoRoot README]]
    set checks {
        "databases"    {databases}
        "engines"      {engines}
        "analysis"     {analysis}
        "3d_board"     {3D board}
        "media"        {media}
        "assistant"    {assistant}
        "linux"        {Linux}
        "windows"      {Windows}
        "macos"        {macOS}
        "licence"      {Licen[sc]e}
        "credits"      {Credits}
    }
    set missing {}
    foreach {name pat} $checks {
        if {![regexp -nocase $pat $content]} {
            lappend missing $name
        }
    }
    join $missing ","
} -result ""

# 13. Man page source check
tcltest::test man-no-sourceforge-or-beta-13 {man page sources have no sourceforge links or beta binary} -body {
    variable repoRoot
    set bad {}
    foreach mf [glob -nocomplain -directory [file join $repoRoot man] *.n] {
        set c [slurp $mf]
        if {[regexp -nocase {sourceforge} $c]} {
            lappend bad "[file tail $mf]:sourceforge"
        }
        if {[regexp -nocase {beta} $c]} {
            lappend bad "[file tail $mf]:beta"
        }
    }
    if {[file exists [file join $repoRoot man scidb-beta.1.gz]]} {
        lappend bad "man/scidb-beta.1.gz:exists"
    }
    if {![file exists [file join $repoRoot man chesswiz.1.gz]]} {
        lappend bad "man/chesswiz.1.gz:missing"
    }
    join $bad ","
} -result ""

tcltest::cleanupTests

} ;# namespace ::scidb::test::brand
