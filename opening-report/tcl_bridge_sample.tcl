#!/usr/bin/env tclsh
#
# tcl_bridge_sample.tcl — Sample Tcl bridge for the scidb-beta runtime adapter.
#
# Reads a JSON command on the command line (method, endpoint, optional JSON
# body) and prints a JSON response matching the adapter contract. Uses
# hardcoded sample data so tests run without a real scidb backend.
#
# Usage:
#   tclsh tcl_bridge_sample.tcl GET /api/databases
#   tclsh tcl_bridge_sample.tcl POST /api/searches '{"type":"advanced","query":{}}'
#

# ---------------------------------------------------------------------------
# Minimal JSON encoder (pure Tcl, no external packages)
# ---------------------------------------------------------------------------

proc json_encode {value} {
    set type [lindex $value 0]
    switch -- $type {
        str {
            set s [lindex $value 1]
            set s [string map {\\ \\\\ \" \\\" \n \\n \r \\r \t \\t} $s]
            return "\"$s\""
        }
        num {
            return [lindex $value 1]
        }
        bool {
            return [expr {[lindex $value 1] ? "true" : "false"}]
        }
        null {
            return "null"
        }
        list {
            set items [lindex $value 1]
            set parts {}
            foreach item $items {
                lappend parts [json_encode $item]
            }
            set joined [join $parts ","]
            return "\[${joined}\]"
        }
        obj {
            set items [lindex $value 1]
            set pairs {}
            foreach {k v} $items {
                lappend pairs "\"$k\":[json_encode $v]"
            }
            set joined [join $pairs ","]
            return "\{${joined}\}"
        }
    }
}

# ---------------------------------------------------------------------------
# Minimal JSON parser (pure Tcl)
# ---------------------------------------------------------------------------

proc json_parse {text} {
    set text [string trim $text]
    set result [json_parse_value $text 0]
    return [lindex $result 0]
}

proc _ws? {ch} {
    return [expr {$ch eq " " || $ch eq "\t" || $ch eq "\n" || $ch eq "\r"}]
}

proc json_parse_value {text pos} {
    while {$pos < [string length $text] && [_ws? [string index $text $pos]]} {
        incr pos
    }
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
# Convenience procs
# ---------------------------------------------------------------------------

proc jstr {s} { return [list str $s] }
proc jnum {n} { return [list num $n] }
proc jbool {b} { return [list bool $b] }
proc jobj {pairs} { return [list obj $pairs] }
proc jarr {items} { return [list list $items] }

proc json_response {value} {
    puts [json_encode $value]
    exit 0
}

proc error_response {code message} {
    puts "{\"error\": \"$message\", \"code\": $code}"
    exit 1
}

# Helper to extract a field value from a parsed JSON object
proc jget {parsed key} {
    set pairs [lindex $parsed 1]
    foreach {k v} $pairs {
        if {$k eq $key} { return $v }
    }
    return ""
}

# Helper to get the string value from a parsed JSON str
proc jval {parsed} {
    return [lindex $parsed 1]
}

# ---------------------------------------------------------------------------
# Sample data
# ---------------------------------------------------------------------------

set SAMPLE_DATABASES [jarr [list \
    [jobj [list \
        id [jstr "masters"] \
        name [jstr "Master Games"] \
        format [jstr "SCI"] \
        games [jnum 2400000] \
        readOnly [jbool 1] \
    ]] \
    [jobj [list \
        id [jstr "repertoire"] \
        name [jstr "My Repertoire"] \
        format [jstr "PGN"] \
        games [jnum 1842] \
        readOnly [jbool 0] \
    ]] \
]]

set SAMPLE_GAMES [jarr [list \
    [jobj [list \
        id [jstr "g-001"] \
        white [jstr "Carlsen, Magnus"] \
        whiteElo [jnum 2855] \
        black [jstr "Nepomniachtchi, Ian"] \
        blackElo [jnum 2782] \
        event [jstr "WCh 2021"] \
        site [jstr "Dubai UAE"] \
        date [jstr "2021.12.03"] \
        result [jstr "1/2-1/2"] \
        eco [jstr "A45"] \
    ]] \
    [jobj [list \
        id [jstr "g-002"] \
        white [jstr "Kasparov, Garry"] \
        whiteElo [jnum 2810] \
        black [jstr "Karpov, Anatoly"] \
        blackElo [jnum 2725] \
        event [jstr "Linares"] \
        site [jstr "Linares ESP"] \
        date [jstr "1993.03.02"] \
        result [jstr "1-0"] \
        eco [jstr "D37"] \
    ]] \
]]

set SAMPLE_TREE [jarr [list \
    [jobj [list \
        san [jstr "d4"] \
        uci [jstr "d2d4"] \
        games [jnum 126420] \
        score [jnum 52.8] \
        white [jnum 37] \
        draw [jnum 42] \
        black [jnum 21] \
        eco [jstr "A45"] \
    ]] \
    [jobj [list \
        san [jstr "Nf3"] \
        uci [jstr "g1f3"] \
        games [jnum 84210] \
        score [jnum 51.2] \
        white [jnum 35] \
        draw [jnum 44] \
        black [jnum 21] \
        eco [jstr "A06"] \
    ]] \
]]

# ---------------------------------------------------------------------------
# Endpoint handlers
# ---------------------------------------------------------------------------

proc handle_list_databases {} {
    global SAMPLE_DATABASES
    json_response $SAMPLE_DATABASES
}

proc handle_list_games {{database_id "masters"}} {
    global SAMPLE_GAMES
    json_response $SAMPLE_GAMES
}

proc handle_get_game {game_id} {
    global SAMPLE_GAMES
    set games_raw [lindex $SAMPLE_GAMES 1]
    foreach game $games_raw {
        if {[jval [jget $game id]] eq $game_id} {
            set headers [jobj [list \
                Event [jstr "WCh 2021"] \
                Site [jstr "Dubai UAE"] \
                Date [jstr "2021.12.03"] \
                White [jstr "Carlsen, Magnus"] \
                Black [jstr "Nepomniachtchi, Ian"] \
                WhiteElo [jstr "2855"] \
                BlackElo [jstr "2782"] \
                Result [jstr "1/2-1/2"] \
                ECO [jstr "A45"] \
            ]]
            set pgn [jstr {[Event "WCh 2021"]
[Site "Dubai UAE"]
[Date "2021.12.03"]
[White "Carlsen, Magnus"]
[Black "Nepomniachtchi, Ian"]
1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *
}]
            set moves {}
            foreach san {e4 e5 Nf3 Nc6 Bb5 a6} {
                set ply [expr {[llength $moves] + 1}]
                lappend moves [jobj [list \
                    id [jstr "m-$ply"] \
                    san [jstr $san] \
                    uci [jstr ""] \
                    fen [jstr ""] \
                    color [jstr [expr {$ply % 2 == 1 ? "w" : "b"}]] \
                    ply [jnum $ply] \
                    nags [jarr {}] \
                    annotations [jarr {}] \
                    variations [jarr {}] \
                ]]
            }
            json_response [jobj [list \
                id [jstr $game_id] \
                headers $headers \
                moves [jarr $moves] \
                pgn $pgn \
            ]]
        }
    }
    error_response 404 "Game not found"
}

proc handle_search {body} {
    global SAMPLE_GAMES
    set query_type [jval [jget $body type]]
    set query [jget $body query]
    set white_filter ""
    if {$query_type eq "advanced" && $query ne ""} {
        set white_filter [jval [jget $query white]]
    }
    set games_raw [lindex $SAMPLE_GAMES 1]
    set filtered {}
    foreach game $games_raw {
        set white_name [jval [jget $game white]]
        if {$white_filter eq "" || [string match -nocase "*$white_filter*" $white_name]} {
            lappend filtered $game
        }
    }
    set job_id "tcl-search-[clock clicks]"
    global _search_store
    set _search_store($job_id) [jobj [list \
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
    global _search_store
    if {[info exists _search_store($job_id)]} {
        json_response $_search_store($job_id)
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
    global SAMPLE_TREE
    json_response $SAMPLE_TREE
}

proc handle_analysis_start {body} {
    set fen [jval [jget $body fen]]
    set multi_pv [jval [jget $body multiPv]]
    if {$fen eq ""} { set fen "start" }
    if {$multi_pv eq ""} { set multi_pv 3 }
    set job_id "tcl-analysis-[clock clicks]"
    global _analysis_store
    set _analysis_store($job_id) [jobj [list \
        jobId [jstr $job_id] \
        status [jstr "running"] \
        fen [jstr $fen] \
        depth [jnum 0] \
        multiPv [jnum $multi_pv] \
        lines [jarr {}] \
        nodes [jnum 0] \
        nps [jnum 0] \
    ]]
    json_response [jobj [list \
        jobId [jstr $job_id] \
        status [jstr "running"] \
    ]]
}

proc handle_analysis_job {job_id} {
    global _analysis_store
    if {[info exists _analysis_store($job_id)]} {
        json_response $_analysis_store($job_id)
    } else {
        json_response [jobj [list \
            jobId [jstr $job_id] \
            status [jstr "unknown"] \
            fen [jstr ""] \
            depth [jnum 0] \
            multiPv [jnum 0] \
            lines [jarr {}] \
            nodes [jnum 0] \
            nps [jnum 0] \
        ]]
    }
}

proc handle_workspace {} {
    json_response [jobj [list \
        activeDatabaseId [jstr "masters"] \
        currentFen [jstr "start"] \
    ]]
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

if {$argc < 2} {
    error_response 400 "Usage: tcl_bridge_sample.tcl METHOD ENDPOINT \[JSON_BODY\]"
}

set method [lindex $argv 0]
set endpoint [lindex $argv 1]
set body {}
if {$argc >= 3} {
    set body_json [lindex $argv 2]
    set body [json_parse $body_json]
}

switch -glob -- "$method $endpoint" {
    "GET /api/databases"          { handle_list_databases }
    "GET /api/databases/*/games" { handle_list_games [lindex [split $endpoint /] 3] }
    "GET /api/games/*"           { handle_get_game [lindex [split $endpoint /] 3] }
    "POST /api/searches"        { handle_search $body }
    "GET /api/searches/*/results" { handle_search_results [lindex [split $endpoint /] 3] }
    "POST /api/tree/query"      { handle_tree_query $body }
    "POST /api/analysis/start"  { handle_analysis_start $body }
    "GET /api/analysis/*"        { handle_analysis_job [lindex [split $endpoint /] 3] }
    "GET /api/workspace"        { handle_workspace }
    default                       { error_response 404 "Unknown endpoint: $method $endpoint" }
}