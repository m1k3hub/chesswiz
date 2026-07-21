#!/usr/bin/env tclsh
#
# tcl_bridge_real.tcl — Real scidb C++/Tcl backend bridge for runtime_adapter.py.
#
# This script is loaded by the compiled scidb interpreter (tkscidb-beta) and
# communicates with runtime_adapter.py over stdin/stdout as a persistent
# JSON-line REPL.
#
# Environment variables:
#   SCI_DATABASE        Path to a PGN/SI3/SI4/SCI database to open at startup.
#                       The file extension determines the command used:
#                       .pgn/.gz/.zip -> ::scidb::db::open
#                       .sci/.si3/.si4 -> ::scidb::db::load
#
# Usage (launched by runtime_adapter.py via tcl_bridge.py):
#   tkscidb-beta tcl_bridge_real.tcl
#
# Protocol:
#   1. On startup the bridge prints {"__scidb_ready": true} and flushes.
#   2. Each request is one JSON line: {"method": "GET", "endpoint": "/api/databases", "body": {}}
#   3. Each response is one JSON line. If the bridge wants the Python adapter
#      to fall back to mock data, it returns {"__scidb_fallback": true}.
#

# ---------------------------------------------------------------------------
# Minimal JSON encoder / decoder (pure Tcl, no external packages)
# ---------------------------------------------------------------------------

proc json_encode {value} {
    set type [lindex $value 0]
    switch -- $type {
        str {
            set s [lindex $value 1]
            set s [string map {\\ \\\" \" \\\" \n \\n \r \\r \t \\t} $s]
            return "\"$s\""
        }
        num { return [lindex $value 1] }
        bool { return [expr {[lindex $value 1] ? "true" : "false"}] }
        null { return "null" }
        list {
            set items [lindex $value 1]
            set parts {}
            foreach item $items { lappend parts [json_encode $item] }
            return "\[[join $parts ,]\]"
        }
        obj {
            set pairs [lindex $value 1]
            set parts {}
            foreach {k v} $pairs { lappend parts "\"$k\":[json_encode $v]" }
            return "\{[join $parts ,]\}"
        }
    }
}

proc json_parse {text} {
    set text [string trim $text]
    set result [json_parse_value $text 0]
    return [lindex $result 0]
}

proc _ws? {ch} {
    return [expr {$ch eq " " || $ch eq "\t" || $ch eq "\n" || $ch eq "\r"}]
}

proc json_parse_value {text pos} {
    while {$pos < [string length $text] && [_ws? [string index $text $pos]]} { incr pos }
    set ch [string index $text $pos]
    if {$ch eq "\{"} { return [json_parse_object $text $pos] }
    if {$ch eq "\["} { return [json_parse_array $text $pos] }
    if {$ch eq "\""} { return [json_parse_string $text $pos] }
    return [json_parse_literal $text $pos]
}

proc json_parse_object {text pos} {
    incr pos
    set result {}
    while {$pos < [string length $text]} {
        while {$pos < [string length $text] && [_ws? [string index $text $pos]]} { incr pos }
        set ch [string index $text $pos]
        if {$ch eq "\}"} { incr pos; return [list [list obj $result] $pos] }
        set key_result [json_parse_string $text $pos]
        set key [lindex [lindex $key_result 0] 1]
        set pos [lindex $key_result 1]
        while {$pos < [string length $text] && ([_ws? [string index $text $pos]] || [string index $text $pos] eq ":")} { incr pos }
        set val_result [json_parse_value $text $pos]
        set val [lindex $val_result 0]
        set pos [lindex $val_result 1]
        lappend result $key $val
        while {$pos < [string length $text] && ([_ws? [string index $text $pos]] || [string index $text $pos] eq ",")} { incr pos }
    }
    return [list [list obj $result] $pos]
}

proc json_parse_array {text pos} {
    incr pos
    set result {}
    while {$pos < [string length $text]} {
        while {$pos < [string length $text] && [_ws? [string index $text $pos]]} { incr pos }
        set ch [string index $text $pos]
        if {$ch eq "\]"} { incr pos; return [list [list list $result] $pos] }
        set val_result [json_parse_value $text $pos]
        set val [lindex $val_result 0]
        set pos [lindex $val_result 1]
        lappend result $val
        while {$pos < [string length $text] && ([_ws? [string index $text $pos]] || [string index $text $pos] eq ",")} { incr pos }
    }
    return [list [list list $result] $pos]
}

proc json_parse_string {text pos} {
    incr pos
    set result {}
    while {$pos < [string length $text]} {
        set ch [string index $text $pos]
        if {$ch eq "\""} { incr pos; return [list [list str $result] $pos] }
        if {$ch eq "\\"} {
            incr pos
            set next [string index $text $pos]
            switch -- $next {
                n { append result "\n" }
                r { append result "\r" }
                t { append result "\t" }
                "\"" { append result "\"" }
                "\\" { append result "\\" }
                "/" { append result "/" }
                default { append result $next }
            }
        } else {
            append result $ch
        }
        incr pos
    }
    return [list [list str $result] $pos]
}

proc json_parse_literal {text pos} {
    set start $pos
    while {$pos < [string length $text]} {
        set ch [string index $text $pos]
        if {$ch eq "," || $ch eq "\]" || $ch eq "\}" || $ch eq " " || $ch eq "\t" || $ch eq "\n" || $ch eq "\r"} { break }
        incr pos
    }
    set literal [string range $text $start [expr {$pos - 1}]]
    if {$literal eq "true"} { return [list [list bool 1] $pos] }
    if {$literal eq "false"} { return [list [list bool 0] $pos] }
    if {$literal eq "null"} { return [list [list null ""] $pos] }
    return [list [list num $literal] $pos]
}

# ---------------------------------------------------------------------------
# JSON convenience procs
# ---------------------------------------------------------------------------

proc jstr {s} { return [list str $s] }
proc jnum {n} { return [list num $n] }
proc jbool {b} { return [list bool $b] }
proc jnull {} { return [list null ""] }
proc jobj {pairs} { return [list obj $pairs] }
proc jarr {items} { return [list list $items] }

proc json_response {value} {
    puts [json_encode $value]
    flush stdout
}

proc fallback {} {
    json_response [jobj [list __scidb_fallback [jbool 1]]]
}

proc error_response {code message} {
    json_response [jobj [list error [jstr $message] code [jnum $code]]]
}

# Extract a value from a parsed JSON object (returns the tagged value)
proc jget {parsed key} {
    set pairs [lindex $parsed 1]
    foreach {k v} $pairs {
        if {$k eq $key} { return $v }
    }
    return ""
}

# Extract the raw value from a parsed JSON str/bool/num/null
proc jval {parsed} {
    return [lindex $parsed 1]
}

# ---------------------------------------------------------------------------
# Helpers for missing numeric values
# ---------------------------------------------------------------------------

proc maybe_num {value} {
    if {$value eq "" || $value eq "null" || $value eq "-"} { return [jnull] }
    if {[string is integer -strict $value]} { return [jnum $value] }
    if {[string is double -strict $value]} { return [jnum $value] }
    return [jnull]
}

proc maybe_str {value} {
    if {$value eq ""} { return [jstr "-"]} ;# return dash rather than empty for PGN display
    return [jstr $value]
}

# ---------------------------------------------------------------------------
# Backend database registry
# ---------------------------------------------------------------------------

proc nop args {}

array set _db_registry {}
array set _db_variant {}
array set _db_format {}
array set _db_readonly {}
array set _views {}
array set _search_results {}
set _active_database ""

proc registerDatabase {path {readOnly 1}} {
    global _db_registry _db_variant _db_format _db_readonly _active_database

    if {![file exists $path]} {
        error "database file not found: $path"
    }

    set ext [string tolower [file extension $path]]
    if {$ext in {.pgn .gz .zip}} {
        set fmt "PGN"
        ::scidb::db::open $path nop nop nop nop
    } elseif {$ext in {.sci .si3 .si4}} {
        set fmt [string toupper [string range $ext 1 end]]
        ::scidb::db::load $path nop {} -readonly $readOnly
    } else {
        error "unsupported database extension: $ext"
    }

    set id [file rootname [file tail $path]]
    set _db_registry($id) $path
    set _db_format($id) $fmt
    set _db_readonly($id) $readOnly
    set _active_database $id

    # Pick the first available variant; most databases are Normal.
    set variants [::scidb::db::get variants $path]
    if {[llength $variants] > 0} {
        set _db_variant($id) [lindex $variants 0]
    } else {
        set _db_variant($id) Normal
    }

    return $id
}

proc dbPath {database_id} {
    global _db_registry
    if {[info exists _db_registry($database_id)]} {
        return $_db_registry($database_id)
    }
    return ""
}

proc dbVariant {database_id} {
    global _db_variant
    if {[info exists _db_variant($database_id)]} {
        return $_db_variant($database_id)
    }
    return Normal
}

proc ensureView {database_id} {
    global _views _db_registry _db_variant
    set path [dbPath $database_id]
    if {$path eq ""} { error "unknown database: $database_id" }

    if {[info exists _views($database_id)]} {
        return $_views($database_id)
    }

    set variant [dbVariant $database_id]
    set view [::scidb::view::new $path master master master master master master]
    ::scidb::view::search $path $variant $view reset none
    set _views($database_id) $view
    return $view
}

proc loadEcoFile {} {
    # Allow explicit override.
    set explicit [lindex [array get ::env SCIDB_ECO_PATH] 1]
    if {$explicit ne "" && [file exists $explicit]} {
        catch { ::scidb::app::load eco $explicit }
        return
    }

    # Candidate paths, most specific first.
    set candidates {}

    # If SCIDB_SHAREDIR is set, data should be under it.
    set sharedir [lindex [array get ::env SCIDB_SHAREDIR] 1]
    if {$sharedir ne ""} {
        lappend candidates [file join $sharedir data eco.bin]
    }

    # Relative to the interpreter executable: <bin>/../share/scidb-beta/data/eco.bin
    set interp [info nameofexecutable]
    if {$interp ne ""} {
        lappend candidates [file join [file dirname $interp] .. share scidb-beta data eco.bin]
    }

    # Standard system installation path.
    lappend candidates /usr/local/share/scidb-beta/data/eco.bin
    lappend candidates /usr/share/scidb-beta/data/eco.bin

    # Development source tree layout: the interpreter may live in src/ and
    # eco.bin in src/data/.
    if {$interp ne ""} {
        lappend candidates [file join [file dirname $interp] data eco.bin]
    }

    foreach path $candidates {
        set path [file normalize $path]
        if {[file exists $path]} {
            if {[catch { ::scidb::app::load eco $path } err]} {
                puts stderr "tcl_bridge_real: failed to load ECO file $path: $err"
            } else {
                return
            }
        }
    }

    puts stderr "tcl_bridge_real: ECO file not found; opening tree will fall back to mock data for non-root positions"
}

# ---------------------------------------------------------------------------
# Startup: load ECO table and open the default database if provided
# ---------------------------------------------------------------------------

loadEcoFile

set env_db [lindex [array get ::env SCI_DATABASE] 1]
if {$env_db eq ""} {
    set env_db [lindex [array get ::env SCIDB_DATABASE] 1]
}
if {$env_db ne "" && [file exists $env_db]} {
    set rc [catch { registerDatabase $env_db 1 } startup_err]
    if {$rc != 0} {
        puts stderr "tcl_bridge_real: failed to open $env_db: $startup_err"
    }
}

# ---------------------------------------------------------------------------
# Game summary / detail builders
# ---------------------------------------------------------------------------

# attribute::game enum indices (as returned by ::scidb::db::get gameInfo)
set IDX_NUMBER 0
set IDX_WHITE_PLAYER 1
set IDX_WHITE_ELO 3
set IDX_BLACK_PLAYER 10
set IDX_BLACK_ELO 12
set IDX_EVENT 19
set IDX_SITE 24
set IDX_DATE 25
set IDX_RESULT 22
set IDX_ECO 32

proc buildGameSummary {database_id row} {
    set path [dbPath $database_id]
    set variant [dbVariant $database_id]
    set view [ensureView $database_id]

    set info [::scidb::db::get gameInfo $row $view $path $variant]

    set number [lindex $info $::IDX_NUMBER]
    set white [lindex $info $::IDX_WHITE_PLAYER]
    set whiteElo [lindex $info $::IDX_WHITE_ELO]
    set black [lindex $info $::IDX_BLACK_PLAYER]
    set blackElo [lindex $info $::IDX_BLACK_ELO]
    set event [lindex $info $::IDX_EVENT]
    set site [lindex $info $::IDX_SITE]
    set date [lindex $info $::IDX_DATE]
    set result [lindex $info $::IDX_RESULT]
    set eco [lindex $info $::IDX_ECO]

    return [jobj [list \
        id [jstr "g-[expr {$row + 1}]"] \
        number [maybe_num $number] \
        white [jstr $white] \
        whiteElo [maybe_num $whiteElo] \
        black [jstr $black] \
        blackElo [maybe_num $blackElo] \
        event [jstr $event] \
        site [jstr $site] \
        date [jstr $date] \
        result [jstr $result] \
        eco [jstr $eco] \
    ]]
}

proc parsePgnMoves {pgn_text} {
    set moves {}
    set lines [split $pgn_text "\n"]
    set movetext {}
    foreach line $lines {
        set trim [string trim $line]
        if {[string length $trim] == 0 || [string index $trim 0] eq "\["} { continue }
        append movetext " " $trim
    }
    set tokens [split [string trim $movetext] " "]
    set ply 0
    set result_tokens [list "1-0" "0-1" "1/2-1/2" "*" "1/2"]
    foreach tok $tokens {
        set tok [string trim $tok]
        if {$tok eq ""} { continue }
        if {$tok in $result_tokens} { continue }
        # strip leading move numbers like "1.", "12.", "12..." and any trailing dots
        set tok [regsub {^\d+\.\.?\s*} $tok {}]
        set tok [regsub {^\d+\.\s*} $tok {}]
        if {$tok eq ""} { continue }
        incr ply
        lappend moves [jobj [list \
            id [jstr "m-$ply"] \
            san [jstr $tok] \
            uci [jstr ""] \
            fen [jstr ""] \
            color [jstr [expr {$ply % 2 == 1 ? "w" : "b"}]] \
            ply [jnum $ply] \
            nags [jarr {}] \
            annotations [jarr {}] \
            variations [jarr {}] \
        ]]
    }
    return $moves
}

proc loadGamePgn {database_id row} {
    set path [dbPath $database_id]
    set variant [dbVariant $database_id]
    set view [ensureView $database_id]

    set gameIndex [::scidb::view::map game $path $variant $view $row]
    ::scidb::game::load 0 $path $variant $gameIndex
    return [::scidb::game::toPGN original -position 0]
}

proc buildGameDetail {database_id row} {
    set path [dbPath $database_id]
    set variant [dbVariant $database_id]
    set view [ensureView $database_id]

    set pgn [loadGamePgn $database_id $row]
    set info [::scidb::db::get gameInfo $row $view $path $variant]

    set headers [jobj [list \
        Event [jstr [lindex $info $::IDX_EVENT]] \
        Site [jstr [lindex $info $::IDX_SITE]] \
        Date [jstr [lindex $info $::IDX_DATE]] \
        White [jstr [lindex $info $::IDX_WHITE_PLAYER]] \
        Black [jstr [lindex $info $::IDX_BLACK_PLAYER]] \
        WhiteElo [jstr [lindex $info $::IDX_WHITE_ELO]] \
        BlackElo [jstr [lindex $info $::IDX_BLACK_ELO]] \
        Result [jstr [lindex $info $::IDX_RESULT]] \
        ECO [jstr [lindex $info $::IDX_ECO]] \
    ]]

    return [jobj [list \
        id [jstr "g-[expr {$row + 1}]"] \
        headers $headers \
        moves [jarr [parsePgnMoves $pgn]] \
        pgn [jstr $pgn] \
    ]]
}

# ---------------------------------------------------------------------------
# Search matching (implemented in Tcl against backend game info)
# ---------------------------------------------------------------------------

proc matchAdvanced {info raw_query} {
    array set q $raw_query
    set white [string tolower [lindex $info $::IDX_WHITE_PLAYER]]
    set black [string tolower [lindex $info $::IDX_BLACK_PLAYER]]
    set event [string tolower [lindex $info $::IDX_EVENT]]
    set site [string tolower [lindex $info $::IDX_SITE]]
    set date [lindex $info $::IDX_DATE]
    set eco [lindex $info $::IDX_ECO]
    set result [lindex $info $::IDX_RESULT]

    foreach key {white black event site ecoFrom ecoTo result yearFrom yearTo} {
        if {![info exists q($key)]} { set q($key) "" }
    }

    if {$q(white) ne "" && [string first [string tolower $q(white)] $white] == -1} { return 0 }
    if {$q(black) ne "" && [string first [string tolower $q(black)] $black] == -1} { return 0 }
    if {$q(event) ne "" && [string first [string tolower $q(event)] $event] == -1} { return 0 }
    if {$q(site) ne "" && [string first [string tolower $q(site)] $site] == -1} { return 0 }
    if {$q(ecoFrom) ne "" && $eco < $q(ecoFrom)} { return 0 }
    if {$q(ecoTo) ne "" && $eco > $q(ecoTo)} { return 0 }
    if {$q(result) ne "" && $q(result) ne "any" && $result ne $q(result)} { return 0 }
    if {$q(yearFrom) ne "" && [string length $date] >= 4 && [string range $date 0 3] < $q(yearFrom)} { return 0 }
    if {$q(yearTo) ne "" && [string length $date] >= 4 && [string range $date 0 3] > $q(yearTo)} { return 0 }
    return 1
}

proc matchRating {info raw_query} {
    array set q $raw_query
    foreach key {whiteEloMin whiteEloMax blackEloMin blackEloMax averageEloMin averageEloMax} {
        if {![info exists q($key)]} { set q($key) "" }
    }
    set whiteElo [lindex $info $::IDX_WHITE_ELO]
    set blackElo [lindex $info $::IDX_BLACK_ELO]
    if {$whiteElo eq "" || ![string is integer -strict $whiteElo]} { set whiteElo 0 }
    if {$blackElo eq "" || ![string is integer -strict $blackElo]} { set blackElo 0 }
    set avg [expr {($whiteElo + $blackElo) / 2}]

    if {$q(whiteEloMin) ne "" && $whiteElo < $q(whiteEloMin)} { return 0 }
    if {$q(whiteEloMax) ne "" && $whiteElo > $q(whiteEloMax)} { return 0 }
    if {$q(blackEloMin) ne "" && $blackElo < $q(blackEloMin)} { return 0 }
    if {$q(blackEloMax) ne "" && $blackElo > $q(blackEloMax)} { return 0 }
    if {$q(averageEloMin) ne "" && $avg < $q(averageEloMin)} { return 0 }
    if {$q(averageEloMax) ne "" && $avg > $q(averageEloMax)} { return 0 }
    return 1
}

proc matchCql {info raw_query} {
    array set q $raw_query
    set terms [string tolower $q(cql)]
    if {$terms eq ""} { return 1 }
    set haystack [string tolower "[lindex $info $::IDX_WHITE_PLAYER] [lindex $info $::IDX_BLACK_PLAYER] [lindex $info $::IDX_EVENT] [lindex $info $::IDX_SITE] [lindex $info $::IDX_ECO] [lindex $info $::IDX_RESULT]"]
    foreach term [split $terms " "] {
        if {[string first $term $haystack] == -1} { return 0 }
    }
    return 1
}

proc matchMaterial {info raw_query} {
    array set q $raw_query
    set material_str [lindex $info 34]
    array set counts [parseMaterialCounts $material_str]

    foreach key {whiteQ whiteR whiteB whiteN whiteP blackQ blackR blackB blackN blackP imbalance} {
        if {![info exists q($key)]} { set q($key) "" }
    }

    if {$q(whiteQ) ne "" && $counts(wq) != $q(whiteQ)} { return 0 }
    if {$q(whiteR) ne "" && $counts(wr) != $q(whiteR)} { return 0 }
    if {$q(whiteB) ne "" && $counts(wb) != $q(whiteB)} { return 0 }
    if {$q(whiteN) ne "" && $counts(wn) != $q(whiteN)} { return 0 }
    if {$q(whiteP) ne "" && $counts(wp) != $q(whiteP)} { return 0 }
    if {$q(blackQ) ne "" && $counts(bq) != $q(blackQ)} { return 0 }
    if {$q(blackR) ne "" && $counts(br) != $q(blackR)} { return 0 }
    if {$q(blackB) ne "" && $counts(bb) != $q(blackB)} { return 0 }
    if {$q(blackN) ne "" && $counts(bn) != $q(blackN)} { return 0 }
    if {$q(blackP) ne "" && $counts(bp) != $q(blackP)} { return 0 }
    if {$q(imbalance) ne ""} {
        set wv [expr {$counts(wq)*9 + $counts(wr)*5 + ($counts(wb)+$counts(wn))*3 + $counts(wp)}]
        set bv [expr {$counts(bq)*9 + $counts(br)*5 + ($counts(bb)+$counts(bn))*3 + $counts(bp)}]
        switch -- $q(imbalance) {
            up { if {$wv <= $bv} { return 0 } }
            down { if {$wv >= $bv} { return 0 } }
            equal { if {$wv != $bv} { return 0 } }
        }
    }
    return 1
}

# ---------------------------------------------------------------------------
# Endpoint handlers
# ---------------------------------------------------------------------------

proc handle_list_databases {} {
    global _db_registry _db_format _db_readonly _active_database
    set items {}
    foreach {id path} [array get _db_registry] {
        set variant [dbVariant $id]
        set count [::scidb::db::count games $path $variant]
        lappend items [jobj [list \
            id [jstr $id] \
            name [jstr [file tail $path]] \
            format [jstr $_db_format($id)] \
            games [jnum $count] \
            readOnly [jbool $_db_readonly($id)] \
        ]]
    }
    json_response [jarr $items]
}

proc handle_list_games {database_id} {
    global _db_registry
    if {![info exists _db_registry($database_id)]} { return [fallback] }

    set view [ensureView $database_id]
    set count [::scidb::view::count games [dbPath $database_id] [dbVariant $database_id] $view]
    set limit 100
    if {$count > $limit} { set count $limit }

    set items {}
    for {set row 0} {$row < $count} {incr row} {
        lappend items [buildGameSummary $database_id $row]
    }
    json_response [jarr $items]
}

proc handle_get_game {game_id} {
    global _db_registry _active_database
    set database_id $_active_database
    if {$database_id eq ""} { return [fallback] }

    if {![regexp {^g-(\d+)$} $game_id -> row]} {
        return [error_response 400 "invalid game id"]
    }
    set row [expr {$row - 1}]

    catch { set detail [buildGameDetail $database_id $row] } err
    if {[info exists detail]} {
        json_response $detail
    } else {
        error_response 404 $err
    }
}

proc handle_search {body} {
    global _db_registry _active_database _search_results

    set database_id $_active_database
    set query_obj [jget $body query]
    set query_pairs [lindex $query_obj 1]

    # Build a flat raw-query dict from the parsed JSON object.
    set raw_query {}
    array set q {}
    foreach {k v} $query_pairs {
        set val [jval $v]
        lappend raw_query $k $val
        set q($k) $val
    }

    set type [jval [jget $body type]]
    if {$type eq ""} { set type advanced }

    if {$database_id eq "" || ![info exists _db_registry($database_id)]} {
        return [fallback]
    }

    set view [ensureView $database_id]
    set path [dbPath $database_id]
    set variant [dbVariant $database_id]
    set total [::scidb::view::count games $path $variant $view]

    set matcher matchAdvanced
    switch -- $type {
        material { set matcher matchMaterial }
        rating { set matcher matchRating }
        cql { set matcher matchCql }
    }

    set filtered {}
    for {set row 0} {$row < $total} {incr row} {
        set info [::scidb::db::get gameInfo $row $view $path $variant]
        if {[$matcher $info $raw_query]} {
            lappend filtered [buildGameSummary $database_id $row]
        }
    }

    set job_id "scidb-search-[clock clicks]"
    set _search_results($job_id) [jobj [list \
        jobId [jstr $job_id] \
        status [jstr "complete"] \
        total [jnum [llength $filtered]] \
        games [jarr $filtered] \
    ]]

    json_response [jobj [list \
        jobId [jstr $job_id] \
        status [jstr "complete"] \
        total [jnum [llength $filtered]] \
    ]]
}

proc handle_search_results {job_id} {
    global _search_results
    if {[info exists _search_results($job_id)]} {
        json_response $_search_results($job_id)
    } else {
        json_response [jobj [list \
            jobId [jstr $job_id] \
            status [jstr "pending"] \
            total [jnum 0] \
            games [jarr {}] \
        ]]
    }
}

proc handle_tree_query {body} {
    global _active_database
    if {$_active_database eq ""} {
        fallback
        return
    }

    set movesTag [jget $body moves]
    set moves [lindex $movesTag 1]

    set path [dbPath $_active_database]
    set variant [dbVariant $_active_database]

    if {[catch { set view [ensureView $_active_database] }]} {
        fallback
        return
    }

    set count [::scidb::view::count games $path $variant $view]
    if {$count == 0} {
        json_response [jarr {}]
        return
    }

    # Slot 9 is reserved for tree queries so we don't clobber game slot 0.
    set treePos 9

    # Load the first game in the view, set up a minimal subscriber, and replay
    # the requested move list to reach the target position.  Using SAN from the
    # request avoids FEN-string mismatches (e.g. en-passant square formatting).
    if {[catch {
        set gameIndex [::scidb::view::map game $path $variant $view 0]
        ::scidb::game::load $treePos $path $variant $gameIndex
        ::scidb::game::subscribe board $treePos nop
        ::scidb::game::switch $treePos
        ::scidb::game::go s
        ::scidb::game::strip truncate

        foreach moveTag $moves {
            set san [jval [jget $moveTag san]]
            if {$san eq ""} { continue }
            ::scidb::game::move $san
            ::scidb::game::go e
        }
    } err]} {
        puts stderr "[tcl_bridge_real] failed to navigate to tree position: $err"
        fallback
        return
    }

    if {[catch {
        ::scidb::tree::set $path
        ::scidb::tree::switch 1
        ::scidb::tree::init nop 0
        ::scidb::tree::invalidate
        set ures [::scidb::tree::update Elo fast 0]
        if {!$ures} {
            # Without a full Tk event loop the worker thread usually finishes
            # synchronously, but give it a tiny grace period just in case.
            after 10
        }
        set finish [::scidb::tree::finish Elo fast 0 -sort 2]
        if {$finish eq "null" || $finish eq "empty"} {
            json_response [jarr {}]
            return
        }

        set rows [::scidb::tree::fetch]
        set out {}
        foreach row $rows {
            set move [lindex $row 0]
            if {$move eq ""} { continue }
            set eco [lindex $row 1]
            set freq [lindex $row 2]
            set score [lindex $row 3]
            set result [lindex $row 5]
            set white [lindex $result 0]
            set black [lindex $result 1]
            set draw [lindex $result 2]
            lappend out [jobj [list \
                san [jstr $move] \
                uci [jstr ""] \
                games [jnum $freq] \
                score [jnum [expr {$score / 10.0}]] \
                white [jnum $white] \
                draw [jnum $draw] \
                black [jnum $black] \
                eco [jstr $eco] \
            ]]
        }
        json_response [jarr $out]
    } err]} {
        puts stderr "[tcl_bridge_real] native tree query failed: $err"
        fallback
    }
}

proc handle_workspace {} {
    global _active_database
    set fen "start"
    if {$_active_database ne ""} {
        if {[catch { set isOpen [::scidb::game::query open? 0] }]} {
            set isOpen 0
        }
        if {$isOpen} {
            catch { set fen [::scidb::game::fen 0] }
        }
    }
    json_response [jobj [list \
        activeDatabaseId [jstr $_active_database] \
        currentFen [jstr $fen] \
    ]]
}

# ---------------------------------------------------------------------------
# Request dispatch
# ---------------------------------------------------------------------------

proc dispatch {method endpoint body} {
    if {$method eq "GET" && $endpoint eq "/api/databases"} {
        handle_list_databases
    } elseif {$method eq "GET" && [regexp {^/api/databases/([^/]+)/games$} $endpoint -> db_id]} {
        handle_list_games $db_id
    } elseif {$method eq "GET" && [regexp {^/api/games/([^/]+)$} $endpoint -> g_id]} {
        handle_get_game $g_id
    } elseif {$method eq "POST" && $endpoint eq "/api/searches"} {
        handle_search $body
    } elseif {$method eq "GET" && [regexp {^/api/searches/([^/]+)/results$} $endpoint -> job_id]} {
        handle_search_results $job_id
    } elseif {$method eq "POST" && $endpoint eq "/api/tree/query"} {
        handle_tree_query $body
    } elseif {$method eq "GET" && $endpoint eq "/api/workspace"} {
        handle_workspace
    } else {
        error_response 404 "unknown endpoint: $method $endpoint"
    }
}

proc handleRequest {line} {
    if {[catch { set req [json_parse $line] } err]} {
        error_response 400 "invalid JSON: $err"
        return
    }
    set method [jval [jget $req method]]
    set endpoint [jval [jget $req endpoint]]
    set body [jget $req body]
    if {$body eq ""} { set body [jobj {}] }

    if {[catch { dispatch $method $endpoint $body } err]} {
        puts stderr "[tcl_bridge_real] error dispatching $method $endpoint: $err"
        fallback
    }
}

# ---------------------------------------------------------------------------
# REPL loop
# ---------------------------------------------------------------------------

fconfigure stdin -buffering line -blocking 0
fconfigure stdout -buffering line

proc readLine {} {
    if {[gets stdin line] < 0} {
        if {[eof stdin]} { exit 0 }
        return
    }
    if {$line eq ""} { return }
    handleRequest $line
}

fileevent stdin readable readLine

# Handshake: tell the Python side we are ready.
json_response [jobj [list __scidb_ready [jbool 1]]]

# The Tk event loop will drive stdin reads. Return to let Tk_Main take over.
