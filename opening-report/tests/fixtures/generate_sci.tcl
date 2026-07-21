#!/usr/bin/env tclsh
# generate_sci.tcl — Import a PGN file into a native scidb (.sci) database.
#
# Usage:
#   xvfb-run -a /usr/local/bin/tkscidb-beta generate_sci.tcl <input.pgn> <output.sci>
#
# The script creates output.sci (plus .scg and .scn siblings), imports all games,
# and saves the database.  Xvfb is required because tkscidb-beta initialises Tk.

proc log_msg {msg} { puts "LOG: $msg" }

proc progress {args} {
    set sub [lindex $args 0]
    switch -- $sub {
        "interrupted?"  { return 0 }
        "interruptable?" { return 0 }
        "ticks"         { return 1000 }
        default         { return "" }
    }
}

if {$argc != 2} {
    puts stderr "Usage: $argv0 <input.pgn> <output.sci>"
    exit 1
}

set pgn  [lindex $argv 0]
set sci  [lindex $argv 1]

if {![file exists $pgn]} {
    puts stderr "PGN file not found: $pgn"
    exit 1
}

set root [file rootname $sci]
foreach ext {sci scg scn} {
    catch { file delete "${root}.${ext}" }
}
catch { file delete $sci }

puts "Creating SCI database: $sci"
if {[catch { ::scidb::db::new $sci Normal 0 } err]} {
    puts stderr "Failed to create database: $err"
    exit 1
}

puts "Attaching on-disk storage..."
if {[catch { ::scidb::db::attach $sci $sci } err]} {
    puts stderr "Failed to attach storage: $err"
    exit 1
}

puts "Importing games from $pgn..."
if {[catch { ::scidb::db::import $sci $pgn log_msg {} progress 0 -encoding utf-8 -illegal true } res]} {
    puts stderr "Import failed: $res"
    exit 1
}
puts "Import result: $res"

puts "Saving..."
if {[catch { ::scidb::db::save $sci progress 0 } err]} {
    puts stderr "Save failed: $err"
    exit 1
}
puts "Save result: $err"

puts "Done.  Generated files:"
foreach f [glob -nocomplain "${root}.*"] {
    puts "  $f"
}
exit 0
