# ======================================================================
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
#
# Import a master-games PGN into the bundled sample .sci database
# share/sample/Sample games.sci.  Run by scripts/build-sample-db.sh with
# the program shell (no GUI is created):
#
#   xvfb-run -a src/tkchesswiz -encoding utf-8 \
#       scripts/import-sample-db.tcl <source-pgn> <destination.sci> \
#       <eco.bin-path> [type-name]
#
# <source-pgn>          TWIC master games, already filtered.
# <destination.sci>     the sample database to create (must not exist).
# <eco.bin-path>        SHAREDIR/data/eco.bin ("" to skip the ECO load).
# <type-name>           internal database type (default GMGames).
#
# The import is the same chain Maintenance > Convert uses: open the PGN,
# create a fresh .sci, copy every game, save.  Progress and log callbacks
# are stubs, so this runs headless (see tests/test_app_convert.tcl).
# ======================================================================

package require tkscidb

if {[llength $argv] < 3 || [llength $argv] > 4} {
	puts stderr "usage: import-sample-db.tcl <source-pgn> <destination.sci> <eco.bin-path> \[type-name\]"
	exit 1
}

lassign $argv srcPath dstPath ecoPath
set typeName [expr {[llength $argv] > 3 ? [lindex $argv 3] : "GMGames"}]

set srcPath [file normalize $srcPath]
set dstPath [file normalize $dstPath]

foreach {path what} [list $srcPath source.pgn $ecoPath eco.bin] {
	if {[llength $path] && ![file readable $path]} {
		puts stderr "import-sample-db.tcl: cannot read the $what '$path'"
		exit 1
	}
}

foreach ext {.sci .scg .scn} {
	set part "[file rootname $dstPath]$ext"
	if {[file exists $part]} {
		puts stderr "import-sample-db.tcl: destination already exists: '$part'"
		exit 1
	}
}
unset part

# progress and log callbacks: stubs, no UI, no log file
proc ::ImportStub {args} { return 0 }

if {[llength $ecoPath]} {
	if {[catch { ::scidb::app::load eco $ecoPath } err]} {
		puts stderr "import-sample-db.tcl: cannot load ECO file: $err"
		exit 1
	}
}

# the type index is the position in the .sci type list (internal names)
set typeIndex [lsearch -exact [::scidb::db::get types sci] $typeName]
if {$typeIndex < 0} {
	puts stderr "import-sample-db.tcl: unknown database type '$typeName'"
	exit 1
}

if {[catch {
	::scidb::db::open $srcPath ::ImportStub {} ::ImportStub {}
	::scidb::db::new $dstPath Normal $typeIndex
	::scidb::db::attach $dstPath $dstPath
	# copy returns {count illegal-rejected ?accepted? ?rejected? ?source-encoding?}
	set res [::scidb::db::copy $srcPath $dstPath {} ::ImportStub {} ::ImportStub {}]
	set count [lindex $res 0]
	::scidb::db::save $dstPath ::ImportStub {}
} err]} {
	puts stderr "import-sample-db.tcl: import failed: $err"
	catch { ::scidb::db::close $dstPath }
	catch { ::scidb::db::close $srcPath }
	exit 1
}

::scidb::db::close $dstPath
::scidb::db::close $srcPath

# verify: reopen and count
::scidb::db::load $dstPath ::ImportStub {}
set verified [::scidb::db::count games $dstPath Normal]
::scidb::db::close $dstPath

if {$verified != $count} {
	puts stderr "import-sample-db.tcl: verification failed: copied $count, reopened $verified"
	exit 1
}

puts "import-sample-db.tcl: $verified games -> [file tail $dstPath]"
exit 0

# vi:set ts=3 sw=3: