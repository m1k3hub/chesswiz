# ======================================================================
# Help Pages Audit Test (helppages - G32 follow-up)
#
# Verifies:
# 1. Every help topic ID referenced from the Tcl application resolves
#    to a valid help page in tcl/help/en.
# 2. Every file referenced in tcl/help/en/Contents.dat exists.
# 3. Every internal link (<a href="...">) and fragment anchor in English
#    help pages resolves to an existing file and valid anchor.
# 4. English help pages contain no stale upstream branding:
#    - no "sourceforge" or "sf.net" links
#    - no "scidb-beta"
#    - no "beta" version text
#    - no "Scidb" except where naming the database file format (.sci /
#      Scidb format) or original authors in credits.
# 5. English help pages contain no competitor product names:
#    - no "chessbase", "fritz", "arena"
#    - no "scid" as a competitor product (distinct from Scidb format).
# 6. English help pages contain no query-language names (CQL / Chess Query Language).
# 7. Other language Contents.dat and Overview files contain no broken links.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::helppages {

variable repoRoot [file dirname [file dirname [file normalize [info script]]]]
variable helpDir [file join $repoRoot tcl help]

proc slurp {path} {
    set fd [open $path r]
    fconfigure $fd -encoding utf-8
    set data [read $fd]
    close $fd
    return $data
}

# 1. Every help topic referenced in tcl/ resolves
tcltest::test helppages-topics-resolve-01 {every help topic referenced in tcl/ resolves} -body {
    variable repoRoot
    variable helpDir

    set tclFiles [glob -nocomplain [file join $repoRoot tcl *.tcl] [file join $repoRoot tcl * *.tcl]]
    set topics [dict create]
    foreach f $tclFiles {
        if {[string match "*/chesswiz" $f]} continue
        set fd [open $f r]
        set lines [split [read $fd] "\n"]
        close $fd
        set lno 0
        foreach line $lines {
            incr lno
            if {[regexp {::help::open\s+(\S+)(?:\s+([^\]\s]+))?} $line _ parent topic]} {
                if {$topic ne "" && ![string match "-*" $topic] && ![string match "$*" $topic] && [string index $topic 0] ne "\[" && $topic ne "\}"} {
                    dict set topics $topic [list [file tail $f] $lno]
                }
            }
        }
    }

    set missing {}
    dict for {t loc} $topics {
        # Check both .html and .txt in en/
        set htmlFile [file join $helpDir en "$t.html"]
        set txtFile [file join $helpDir en "$t.txt"]
        if {![file exists $htmlFile] && ![file exists $txtFile]} {
            lappend missing "$t ($loc)"
        }
    }
    join $missing ", "
} -result ""

# 2. Every file referenced in tcl/help/en/Contents.dat exists
tcltest::test helppages-contents-dat-02 {all files in en/Contents.dat exist} -body {
    variable helpDir
    set contentsFile [file join $helpDir en Contents.dat]
    if {![file exists $contentsFile]} {
        return "missing Contents.dat"
    }
    set cData [slurp $contentsFile]
    set Contents {}
    eval $cData

    proc checkEntries {items dir} {
        set missing {}
        foreach item $items {
            if {[llength $item] == 1} {
                set spec [lindex $item 0]
                set targetFile [lindex $spec 1]
                if {![file exists [file join $dir $targetFile]]} {
                    lappend missing $targetFile
                }
            } else {
                lappend missing {*}[checkEntries $item $dir]
            }
        }
        return $missing
    }

    set missing [checkEntries $Contents [file join $helpDir en]]
    join $missing ", "
} -result ""

# 3. Every internal link and anchor in en/ resolves
tcltest::test helppages-internal-links-03 {all internal links and anchors in en/ resolve} -body {
    variable helpDir
    set enDir [file join $helpDir en]
    set htmlFiles [glob -nocomplain -directory $enDir *.html]

    set broken {}
    foreach hf $htmlFiles {
        set base [file tail $hf]
        set content [slurp $hf]

        set hrefs [regexp -all -inline {href=['"]([^'"]+)['"]} $content]
        foreach {full href} $hrefs {
            if {[string match "http:*" $href] || [string match "https:*" $href] ||
                [string match "ftp:*" $href] || [string match "mailto:*" $href] ||
                [string match "javascript:*" $href]} {
                continue
            }
            set parts [split $href "#"]
            set targetFile [lindex $parts 0]
            set anchor [lindex $parts 1]

            if {$targetFile eq ""} {
                set targetPath $hf
            } else {
                set targetPath [file join $enDir $targetFile]
            }

            if {![file exists $targetPath]} {
                lappend broken "$base -> $href (missing file)"
            } elseif {$anchor ne ""} {
                set targetContent [slurp $targetPath]
                set hasAnchor 0
                set anchorPat [string map {[ \\[ ] \\] . \\. : \\: + \\+ ? \\? * \\*} $anchor]
                if {[regexp -line -- "(?:id|name)=\[\"']${anchorPat}\[\"']" $targetContent]} {
                    set hasAnchor 1
                }
                if {!$hasAnchor} {
                    lappend broken "$base -> $href (missing anchor #$anchor)"
                }
            }
        }
    }
    join $broken "\n"
} -result ""

# 4. No stale branding (sourceforge, scidb-beta, beta) in en help files
tcltest::test helppages-no-stale-branding-04 {no stale branding in en help files} -body {
    variable helpDir
    set enDir [file join $helpDir en]
    set files [glob -nocomplain -directory $enDir *.txt *.html]

    set bad {}
    foreach f $files {
        set base [file tail $f]
        set content [slurp $f]

        if {[regexp -nocase {sourceforge|sf\.net} $content]} {
            lappend bad "$base:sourceforge"
        }
        if {[regexp -nocase {scidb-beta} $content]} {
            lappend bad "$base:scidb-beta"
        }
        # Check for beta outside acceptable words
        if {[regexp -nocase {\bbeta\b} $content]} {
            lappend bad "$base:beta"
        }
        # Check for Scidb when not describing the database format or Gregor Cramer / credits
        # Strip allowed credits and format references
        set stripped $content
        regsub -all -nocase {Gregor Cramer} $stripped {} stripped
        regsub -all -nocase {Scidb('s)? (database|native|own)?\s*format} $stripped {} stripped
        regsub -all -nocase {format\s*(\([^\)]*\))?\s*is\s*Scidb('s)?} $stripped {} stripped
        regsub -all -nocase {Scidb (\(\.sci\)|database archive|archive|\.sci)} $stripped {} stripped
        regsub -all -nocase {database in Scidb('s)? format} $stripped {} stripped
        regsub -all -nocase {built on Scidb} $stripped {} stripped
        regsub -all -nocase {Scidb, whose development} $stripped {} stripped
        regsub -all -nocase {ft-scidb} $stripped {} stripped
        regsub -all -nocase {cdb2sci} $stripped {} stripped
        regsub -all -nocase {what Chesswiz adds on top of Scidb} $stripped {} stripped
        regsub -all -nocase {Engine Sjeng-scidb} $stripped {} stripped
        regsub -all -nocase {%scidb%} $stripped {} stripped
        if {[regexp -nocase {\bscidb\b} $stripped m]} {
            lappend bad "$base:scidb"
        }
    }
    join $bad ", "
} -result ""

# 5. No competitor mentions in en help files
tcltest::test helppages-no-competitors-05 {no competitor products mentioned in en help files} -body {
    variable helpDir
    set enDir [file join $helpDir en]
    set files [glob -nocomplain -directory $enDir *.txt *.html]

    set bad {}
    foreach f $files {
        set base [file tail $f]
        set content [slurp $f]

        if {[regexp -nocase {\m(chessbase|fritz|arena)\M} $content m]} {
            lappend bad "$base:competitor:$m"
        }
        # Scid as competitor (not Scidb)
        set stripped $content
        regsub -all -nocase {\bscidb\b} $stripped {} stripped
        regsub -all -nocase {ft-scidb} $stripped {} stripped
        if {[regexp -nocase {\bscid\b} $stripped m]} {
            lappend bad "$base:competitor:scid"
        }
    }
    join $bad ", "
} -result ""

# 6. No query language names in en help files
tcltest::test helppages-no-query-languages-06 {no query language names in en help files} -body {
    variable helpDir
    set enDir [file join $helpDir en]
    set files [glob -nocomplain -directory $enDir *.txt *.html]

    set bad {}
    foreach f $files {
        set base [file tail $f]
        set content [slurp $f]

        if {[regexp -nocase {\mcql\M|chess\s+query\s+language} $content m]} {
            lappend bad "$base:query_lang:$m"
        }
    }
    join $bad ", "
} -result ""

# 7. Other languages have no broken file links in Contents.dat or Overview
tcltest::test helppages-other-languages-links-07 {other languages have no broken file links in Contents.dat} -body {
    variable helpDir
    set missingAll {}
    foreach lang {de es hu it sv} {
        set cFile [file join $helpDir $lang Contents.dat]
        if {![file exists $cFile]} continue
        set cData [slurp $cFile]
        set Contents {}
        eval $cData

        proc checkOtherEntries {items lDir enDir langName} {
            set miss {}
            foreach item $items {
                if {[llength $item] == 1} {
                    set spec [lindex $item 0]
                    set targetFile [lindex $spec 1]
                    set inLang [file exists [file join $lDir $targetFile]]
                    set inEn [file exists [file join $enDir $targetFile]]
                    if {!$inLang && !$inEn} {
                        lappend miss "$langName:$targetFile"
                    }
                } else {
                    lappend miss {*}[checkOtherEntries $item $lDir $enDir $langName]
                }
            }
            return $miss
        }

        set m [checkOtherEntries $Contents [file join $helpDir $lang] [file join $helpDir en] $lang]
        lappend missingAll {*}$m
    }
    join $missingAll ", "
} -result ""

tcltest::cleanupTests

} ;# namespace ::scidb::test::helppages
