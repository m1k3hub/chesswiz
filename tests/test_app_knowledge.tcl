# ======================================================================
# Knowledge for every action, the generated pack, and capability lookup
# (VAL-KNOW-001, VAL-KNOW-002, VAL-KNOW-003).
#
# Run alone through run_app_tests.tcl under Xvfb:
#   HOME=$PWD/tests/tmp-app/know-home xvfb-run -a \
#       src/tkchesswiz tests/run_app_tests.tcl -file test_app_knowledge.tcl
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5
package require json

namespace eval ::scidb::test::knowledge {
    variable root [file dirname [file dirname [file normalize [info script]]]]
    variable pack [file join [file dirname [file normalize [info script]]] tmp-app knowledge-pack]
    variable Banned {chessbase fritz {mega database} {chess assistant} cql {chess query language}}

    proc ready {} {
        set deadline [expr {[clock milliseconds] + 20000}]
        while {![info exists ::application::Vars(ready)] || !$::application::Vars(ready)} {
            update
            if {[clock milliseconds] > $deadline} { error {startup timed out} }
            after 10
        }
        update
        catch { destroy .tipoftheday }
        update
        ::knowledge::Ensure
    }

    proc knowledgeText {id} {
        set k [::knowledge::For $id en]
        set rec [::action::get $id]
        return [join [list [dict get $k title] [dict get $k purpose] [dict get $k when] \
            {*}[dict get $k examples] {*}[dict get $k related] [dict get $rec keywords]] "\n"]
    }

    proc readCorpus {} {
        variable root
        set f [open [file join $root tests fixtures know-eval-dev.jsonl] r]
        set data [read $f]
        close $f
        set rows {}
        foreach line [split $data \n] {
            if {[string trim $line] eq ""} { continue }
            lappend rows [::json::json2dict $line]
        }
        return $rows
    }

    proc readAliases {} {
        variable root
        set map [dict create]
        set f [open [file join $root tests fixtures know-id-aliases.txt] r]
        foreach line [split [read $f] \n] {
            set line [string trim $line]
            if {$line eq "" || [string match #* $line]} { continue }
            lassign $line from to
            dict set map $from $to
        }
        close $f
        return $map
    }

    proc sameFiles {a b} {
        foreach name {actions.json topics.json registry.sha256 README.txt} {
            set fa [open [file join $a $name] r]
            fconfigure $fa -translation binary
            set da [read $fa]
            close $fa
            set fb [open [file join $b $name] r]
            fconfigure $fb -translation binary
            set db [read $fb]
            close $fb
            if {$da ne $db} { return 0 }
        }
        return 1
    }
}

# ----------------------------------------------------------------------
# VAL-KNOW-001
# ----------------------------------------------------------------------
tcltest::test knowledge-fields {every exposed action has purpose, when, 2 examples and existing related ids} -body {
    ::scidb::test::knowledge::ready
    # Census the registry surfaces independently of PackIds so exclusions
    # cannot hide an action with missing fields.
    set ids {}
    foreach id [::action::list] {
        set rec [::action::get $id]
        if {[dict get $rec operator] || [dict get $rec ai] in {1 debug} || [dict get $rec dropdown] ne "" ||
            [llength [dict get $rec context]] || [string match toolbar.* $id] ||
            [string length [join [dict get $rec keys] ""]]} { lappend ids $id }
    }
    set bad {}
    foreach id $ids {
        if {$id ni [::knowledge::PackIds]} { lappend bad [list $id {missing from pack}] }
    }
    foreach id $ids {
        set rec [::action::get $id]
        set k [::knowledge::For $id en]
        foreach field {purpose when} {
            if {[string trim [dict get $k $field]] eq ""} { lappend bad [list $id $field empty] }
        }
        if {[llength [dict get $k examples]] < 2} { lappend bad [list $id examples [llength [dict get $k examples]]] }
        foreach rel [dict get $k related] {
            if {$rel eq $id || ![dict exists $::action::Registry $rel]} {
                lappend bad [list $id related $rel]
            }
        }
        foreach field {purpose when} {
            if {[string first "." [string trim [dict get $k $field]]] < 0
                && [string first "!" [string trim [dict get $k $field]]] < 0} {
                lappend bad [list $id $field {not a sentence}]
            }
        }
    }
    puts "KNOW-001 fields: [llength $ids] exposed actions, [llength $bad] bad"
    foreach field {purpose when examples related} {
        set covered 0
        foreach id $ids {
            set value [dict get [::knowledge::For $id en] $field]
            if {$field eq "related" || [string trim $value] ne ""} { incr covered }
        }
        puts [format "KNOW-001 coverage %s: %d/%d (%.1f%%)" $field $covered [llength $ids] [expr {100.0*$covered/[llength $ids]}]]
    }
    foreach b [lrange $bad 0 10] { puts "  bad: $b" }
    set bad
} -result {}

tcltest::test knowledge-examples-unique {no example repeats across actions} -body {
    ::scidb::test::knowledge::ready
    set seen [dict create]
    set dup {}
    foreach id [::knowledge::PackIds] {
        foreach ex [dict get [::knowledge::For $id en] examples] {
            set key [string tolower [string trim $ex]]
            if {[dict exists $seen $key]} {
                lappend dup [list $seen $key $id $ex]
            } else {
                dict set seen $key $id
            }
        }
    }
    puts "KNOW-001 examples: [dict size $seen] unique, [llength $dup] duplicates"
    foreach d [lrange $dup 0 10] { puts "  duplicate: $d" }
    set dup
} -result {}

tcltest::test knowledge-banned-names {no banned product name appears in a knowledge field} -body {
    ::scidb::test::knowledge::ready
    variable ::scidb::test::knowledge::Banned
    set bad {}
    foreach id [::knowledge::PackIds] {
        set text [string tolower [::scidb::test::knowledge::knowledgeText $id]]
        foreach word $::scidb::test::knowledge::Banned {
            if {[string first [string tolower $word] $text] >= 0} {
                lappend bad [list $id $word]
                break
            }
        }
    }
    puts "KNOW-001 banned: [llength $bad] hits"
    foreach b [lrange $bad 0 10] { puts "  banned: $b" }
    set bad
} -result {}

tcltest::test knowledge-german-fallback {German text where present, English otherwise, never empty} -body {
    ::scidb::test::knowledge::ready
    set de [::knowledge::For open_database de]
    set en [::knowledge::For open_database en]
    set plainDe [::knowledge::For nav-back de]
    set plainEn [::knowledge::For nav-back en]
    puts "KNOW-001 de: [dict get $de purpose]"
    puts "KNOW-001 fallback: [dict get $plainDe purpose]"
    list \
        [expr {[dict get $de purpose] ne [dict get $en purpose]}] \
        [expr {[string first "Datenbank" [dict get $de purpose]] >= 0}] \
        [expr {[string trim [dict get $plainDe purpose]] ne ""}] \
        [expr {[dict get $plainDe purpose] eq [dict get $plainEn purpose]}] \
        [llength [dict get $de examples]]
} -result {1 1 1 1 2}

tcltest::test knowledge-debug-is-in-scope {debug actions carry knowledge too} -body {
    ::scidb::test::knowledge::ready
    set bad {}
    dict for {id rec} $::action::Registry {
        if {[dict get $rec ai] ne "debug"} { continue }
        set k [::knowledge::For $id en]
        foreach field {purpose when} {
            if {[string trim [dict get $k $field]] eq ""} { lappend bad [list $id $field] }
        }
        if {[llength [dict get $k examples]] < 2} { lappend bad [list $id examples] }
    }
    puts "KNOW-001 debug fields: [llength $bad] bad"
    set bad
} -result {}

# ----------------------------------------------------------------------
# VAL-KNOW-002
# ----------------------------------------------------------------------
tcltest::test knowledge-pack-deterministic {generate twice, byte-identical} -body {
    ::scidb::test::knowledge::ready
    set a "$::scidb::test::knowledge::pack-a"
    set b "$::scidb::test::knowledge::pack-b"
    file delete -force $a $b
    ::knowledge::Generate $a
    ::knowledge::Generate $b
    set same [::scidb::test::knowledge::sameFiles $a $b]
    set f [open [file join $a registry.sha256] r]
    set hash [string trim [read $f]]
    close $f
    puts "KNOW-002 pack: actions=[file size [file join $a actions.json]] bytes, hash=$hash, identical=$same"
    list $same [expr {$hash ne ""}]
} -result {1 1}

tcltest::test knowledge-pack-topics {the six multi-step topics name existing action ids} -body {
    ::scidb::test::knowledge::ready
    set required {
        topic:prepare-against-opponent topic:build-repertoire topic:review-my-games
        topic:follow-live-broadcast topic:find-positions topic:train-endgames
    }
    set have {}
    set bad {}
    foreach topic [::knowledge::PackTopicList] {
        lappend have [dict get $topic id]
        set steps [dict get $topic steps]
        if {[llength $steps] < 2} { lappend bad [list [dict get $topic id] {fewer than 2 steps}] }
        foreach step $steps {
            set id [dict get $step action]
            if {[string match topic:* $id]} {
                lappend bad [list $topic $id {topic inside a chain}]
            } elseif {![dict exists $::action::Registry $id]} {
                lappend bad [list [dict get $topic id] $id missing]
            }
        }
    }
    foreach id $required {
        if {$id ni $have} { lappend bad [list $id {topic missing}] }
    }
    puts "KNOW-002 topics: [llength $have] generated, [llength $bad] bad"
    foreach b $bad { puts "  bad: $b" }
    set bad
} -result {}

tcltest::test knowledge-drift {a changed purpose makes the pack stale until regenerated} -body {
    ::scidb::test::knowledge::ready
    set dir "$::scidb::test::knowledge::pack-drift"
    file delete -force $dir
    ::knowledge::Generate $dir
    set current [::knowledge::Drift $dir]
    set saved [::action::get open_database]
    set changed [dict create {*}$saved]
    dict set changed purpose "A deliberately different purpose for the drift test."
    dict set ::action::Registry open_database $changed
    set stale [::knowledge::Drift $dir]
    ::knowledge::Generate $dir
    set again [::knowledge::Drift $dir]
    puts "KNOW-002 drift: current={$current} stale={$stale} regenerated={$again}"
    set f [open [file join $dir actions.json]]
    set content [read $f];close $f
    set propagated [expr {[string first [dict get $changed purpose] $content] >= 0 && [dict get [::action::get open_database] purpose] eq [dict get $changed purpose]}]
    dict set ::action::Registry open_database $saved
    list [expr {$current eq ""}] [expr {[string match {*stale*} $stale]}] [expr {$again eq ""}] $propagated
} -result {1 1 1 1}

tcltest::test knowledge-cli-status {real CLI rejects a stale pack and accepts a current pack} -body {
    set dir "$::scidb::test::knowledge::pack-cli"
    ::knowledge::Generate $dir
    set command [list [info nameofexecutable] [file join $::scidb::test::knowledge::root scripts build-knowledge.tcl] --check --out $dir]
    set good [catch {exec {*}$command 2>@1} output]
    set f [open [file join $dir registry.sha256] w]
    puts $f stale
    close $f
    set bad [catch {exec {*}$command 2>@1} output options]
    set status [dict get $options -errorcode]
    list $good $bad [lindex $status 0] [lindex $status 2] [string match {*stale*} $output]
} -result {0 1 CHILDSTATUS 1 1}

tcltest::test knowledge-installed-lookup {the app finds a pack under its share directory} -body {
    ::scidb::test::knowledge::ready
    set dir "$::scidb::test::knowledge::pack-install"
    file delete -force $dir
    ::knowledge::Generate [file join $dir knowledge]
    set savedShare ""
    if {[info exists ::scidb::dir::share]} { set savedShare $::scidb::dir::share }
    set envSaved ""
    if {[info exists ::env(CHESSWIZ_KNOWLEDGE_DIR)]} { set envSaved $::env(CHESSWIZ_KNOWLEDGE_DIR); unset ::env(CHESSWIZ_KNOWLEDGE_DIR) }
    set ::scidb::dir::share $dir
    set ::knowledge::PackDir ""
    set found [::knowledge::Dir]
    puts "KNOW-002 installed: found={$found} expected=[file normalize [file join $dir knowledge]]"
    set ok [expr {$found eq [file normalize [file join $dir knowledge]]}]
    set ::knowledge::PackDir ""
    if {$savedShare ne ""} { set ::scidb::dir::share $savedShare }
    if {$envSaved ne ""} { set ::env(CHESSWIZ_KNOWLEDGE_DIR) $envSaved }
    set ok
} -result 1

tcltest::test knowledge-pack-loads {the generated pack feeds the lookup with the same ids} -body {
    ::scidb::test::knowledge::ready
    set expected [llength [::knowledge::PackIds]]
    set expectedTopics [llength $::knowledge::Topics]
    set dir "$::scidb::test::knowledge::pack-load"
    file delete -force $dir
    ::knowledge::Generate $dir
    set saved [array get ::knowledge::PackActions]
    set savedTopics [set ::knowledge::PackTopics]
    set savedIndex [set ::knowledge::Index]
    set savedLoaded $::knowledge::PackLoaded
    set savedDir $::knowledge::PackDir
    set savedEnv ""
    if {[info exists ::env(CHESSWIZ_KNOWLEDGE_DIR)]} { set savedEnv $::env(CHESSWIZ_KNOWLEDGE_DIR) }
    set ::env(CHESSWIZ_KNOWLEDGE_DIR) $dir
    set ::knowledge::PackDir ""
    set ::knowledge::PackLoaded 0
    set ::knowledge::PackActions {}
    ::knowledge::Load
    set loaded [llength $::knowledge::PackActions]
    set tops [llength $::knowledge::PackTopics]
    puts "KNOW-002 load: $loaded actions, $tops topics from $dir"
    # restore the live index
    set ::knowledge::PackActions $saved
    set ::knowledge::PackTopics $savedTopics
    set ::knowledge::Index $savedIndex
    set ::knowledge::PackLoaded 1
    set ::knowledge::PackDir $savedDir
    if {$savedEnv ne ""} { set ::env(CHESSWIZ_KNOWLEDGE_DIR) $savedEnv } else { unset -nocomplain ::env(CHESSWIZ_KNOWLEDGE_DIR) }
    list [expr {$loaded == $expected}] [expr {$tops == $expectedTopics}]
} -result {1 1}

# ----------------------------------------------------------------------
# VAL-KNOW-003
# ----------------------------------------------------------------------
tcltest::test knowledge-query-punctuation {sentence punctuation does not change word matching; chess symbols remain searchable} -body {
    set equal {}
    foreach text {{open a downloaded database} {export games to PGN} {show a player card} {find opening games}} {
        lappend equal [expr {[::knowledge::Tokenize $text] eq [::knowledge::Tokenize "$text?"]}]
    }
    set marked [::knowledge::Tokenize {good move! bad move??}]
    list $equal [expr {"!" in $marked}] [expr {"??" in $marked}]
} -result {{1 1 1 1} 1 1}

tcltest::test knowledge-format-is-not-import {a portable game format does not imply importing rather than exporting} -body {
    set format [::knowledge::Tokenize PGN]
    set import [::knowledge::Tokenize import]
    list [expr {"imports" in $format}] [expr {"pgns" in $import}] [expr {"pgns" in $format}]
} -result {0 0 1}

tcltest::test knowledge-dev-corpus {an acceptable id in the top 3 for >= 90% of 40 questions} -body {
    ::scidb::test::knowledge::ready
    set aliases [::scidb::test::knowledge::readAliases]
    set total 0
    set hit 0
    set misses {}
    foreach row [::scidb::test::knowledge::readCorpus] {
        incr total
        if {[dict get $row absent]} { continue }
        set want {}
        foreach id [dict get $row acceptable] {
            if {[dict exists $aliases $id]} { set id [dict get $aliases $id] }
            lappend want $id
        }
        set top {}
        foreach cap [::knowledge::Search [dict get $row q] 3] { lappend top [dict get $cap id] }
        set ok 0
        foreach t $top { if {$t in $want} { set ok 1; break } }
        if {$ok} { incr hit } else { lappend misses [list [dict get $row id] $top $want] }
    }
    set rate [expr {double($hit) / $total}]
    puts "KNOW-003 dev: $hit/$total = [format %.3f $rate]"
    foreach m $misses { puts "  miss: $m" }
    expr {$rate >= 0.90}
} -result 1

tcltest::test knowledge-latency {p95 under 50 ms over 200 queries on the generated pack} -body {
    ::scidb::test::knowledge::ready
    set dir "$::scidb::test::knowledge::pack-lat"
    file delete -force $dir
    ::knowledge::Generate $dir
    set savedLoaded $::knowledge::PackLoaded
    set savedDir $::knowledge::PackDir
    set savedActions $::knowledge::PackActions
    set savedTopics $::knowledge::PackTopics
    set savedIndex $::knowledge::Index
    set envSaved ""
    if {[info exists ::env(CHESSWIZ_KNOWLEDGE_DIR)]} { set envSaved $::env(CHESSWIZ_KNOWLEDGE_DIR) }
    set ::env(CHESSWIZ_KNOWLEDGE_DIR) $dir
    set ::knowledge::PackDir ""
    set ::knowledge::PackLoaded 0
    ::knowledge::Load
    set queries {}
    foreach row [::scidb::test::knowledge::readCorpus] { lappend queries [dict get $row q] }
    set times {}
    for {set i 0} {$i < 200} {incr i} {
        set q [lindex $queries [expr {$i % [llength $queries]}]]
        set t0 [clock microseconds]
        ::knowledge::FindCapability $q 4
        lappend times [expr {[clock microseconds] - $t0}]
    }
    set times [lsort -integer $times]
    set p95 [lindex $times [expr {int(0.95 * [llength $times]) - 1}]]
    set median [lindex $times [expr {[llength $times] / 2}]]
    puts "KNOW-003 latency: median=${median}us p95=${p95}us max=[lindex $times end]us pack=[file size [file join $dir actions.json]] bytes"
    set ::knowledge::PackActions $savedActions
    set ::knowledge::PackTopics $savedTopics
    set ::knowledge::Index $savedIndex
    set ::knowledge::PackLoaded $savedLoaded
    set ::knowledge::PackDir $savedDir
    if {$envSaved ne ""} { set ::env(CHESSWIZ_KNOWLEDGE_DIR) $envSaved } else { unset -nocomplain ::env(CHESSWIZ_KNOWLEDGE_DIR) }
    expr {$p95 < 50000}
} -result 1

tcltest::test knowledge-unavailable {an action that cannot run now is reported with a reason} -body {
    ::scidb::test::knowledge::ready
    set id menu.view.panes.players
    lassign [::knowledge::Runnable $id] ok why
    set text [::knowledge::FindCapability "show the players pane" 5]
    set offered 0
    foreach line [split $text \n] {
        if {[string match "*$id*runnable*" $line] && ![string match "*unavailable*" $line]} { set offered 1 }
    }
    puts "KNOW-003 unavailable: $id ok=$ok why={$why} offered-as-runnable=$offered"
    list $ok [expr {$ok == 0 && $why ne "" && !$offered}]
} -result {0 1}

tcltest::test knowledge-tools-json {every provider is offered find_capability and run_action} -body {
    ::scidb::test::knowledge::ready
    set names {}
    foreach tool [::json::json2dict [::application::assistant::toolsJson]] {
        lappend names [dict get [dict get $tool function] name]
    }
    set missing {}
    foreach provider {ollama anthropic openai fireworks qwen gemini stub} {
        set saved $::ai::provider::Config(name)
        ::ai::provider::configure -name $provider
        set providerNames {}
        foreach tool [::json::json2dict [::application::assistant::toolsJson]] {
            lappend providerNames [dict get [dict get $tool function] name]
        }
        foreach required {find_capability run_action} {
            if {$required ni $providerNames} { lappend missing [list $provider $required] }
        }
        ::ai::provider::configure -name $saved
    }
    puts "KNOW-003 tools: [llength $names] tools, missing for a provider: [llength $missing]"
    set missing
} -result {}

tcltest::test knowledge-open-stream {the stream dialog operation is one assistant action with an argument} -body {
    ::scidb::test::knowledge::ready
    set rec [::action::get open_stream]
    set args {}
    foreach param [dict get $rec args] { lappend args [lindex $param 0] }
    puts "KNOW-003 open_stream: ai=[dict get $rec ai] args=$args"
    list [dict get $rec ai] $args
} -result {1 url}

tcltest::test knowledge-key-editor-exposed {keyboard-only actions are assistant actions} -body {
    ::scidb::test::knowledge::ready
    set missing {}
    foreach entry $::application::keyEditor::Actions {
        set id [lindex $entry 0]
        if {![dict exists $::action::Registry $id]} {
            lappend missing [list $id {no registry record}]
            continue
        }
        set rec [::action::get $id]
        set ai [dict get $rec ai]
        if {$ai ne "1" && $ai ne "debug"} { lappend missing [list $id "ai=$ai"] }
    }
    puts "KNOW-003 key editor: [llength $::application::keyEditor::Actions] actions, [llength $missing] not exposed"
    set missing
} -result {}

tcltest::test knowledge-closed-loop {find_capability names an id that run_action can run} -body {
    ::scidb::test::knowledge::ready
    set text [::knowledge::FindCapability "what is open right now" 4]
    set id ""
    foreach line [split $text \n] {
        if {[string match "CAPABILITY app_state*" $line]} { set id app_state }
    }
    set result [::knowledge::RunAction $id {}]
    puts "KNOW-003 closed loop: id={$id} result={$result}"
    expr {$id ne "" && ![string match error:* $result]}
} -result 1

tcltest::cleanupTests
