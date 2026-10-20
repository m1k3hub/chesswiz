# ======================================================================
# Tests for Gap G17: PGN export UTF-8 default & migration
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::export_utf8 {

variable tmpDir
if {![info exists tmpDir]} {
	set tmpDir [file normalize [file join [file dirname [info script]] tmp-app utf8-[pid]]]
}
file mkdir $tmpDir

proc tempPath {stem ext} {
	variable tmpDir
	return [file join $tmpDir "${stem}_[pid]_[clock microseconds].${ext}"]
}

proc log {args} {}
proc progress {args} {}

proc makeSamplePgn {white black} {
	set path [tempPath sample pgn]
	set fh [open $path w]
	fconfigure $fh -encoding utf-8
	puts $fh {[Event "World Championship Match"]}
	puts $fh {[Site "Astana"]}
	puts $fh {[Date "2023.04.15"]}
	puts $fh {[Round "4"]}
	puts $fh "\[White \"$white\"\]"
	puts $fh "\[Black \"$black\"\]"
	puts $fh {[Result "1-0"]}
	puts $fh ""
	puts $fh {1. c4 Nf6 2. Nc3 e6 3. e4 d5 4. e5 d4 5. exf6 dxc3 6. bxc3 Qxf6 1-0}
	close $fh
	return $path
}

proc readRawBytes {path} {
	set fh [open $path r]
	fconfigure $fh -translation binary
	set data [read $fh]
	close $fh
	return $data
}

proc readUtf8Text {path} {
	set fh [open $path r]
	fconfigure $fh -encoding utf-8
	set text [read $fh]
	close $fh
	return $text
}

# ------------------------------------------------------------------------------
# Test 1: Export a game with non-ASCII player names ("Réti, Richard" and
# "Непомнящий, Ян" in Cyrillic) from fresh defaults via the export API
# (DoExport) and verify the output file decodes as UTF-8 and contains the names.
# ------------------------------------------------------------------------------
tcltest::test export-utf8-fresh-single-game {export game with non-ASCII players via export API decodes as UTF-8} -setup {
	set white "Réti, Richard"
	set black "Непомнящий, Ян"
	set srcPgn [makeSamplePgn $white $black]
	::scidb::db::open $srcPgn ::scidb::test::export_utf8::log log ::scidb::test::export_utf8::progress progress
	set pos [::scidb::game::current]
	::scidb::game::load $pos $srcPgn Normal 0
	set outPath [tempPath single-export pgn]
	catch {destroy .exportDlg}
	toplevel .exportDlg
} -body {
	set ::export::Info(base) $srcPgn
	set ::export::Info(variant) Normal
	set ::export::Info(index) 0
	set ::export::Info(view) 0
	set ::export::Info(extension) pgn
	set ::export::Info(languages) {*}
	set ::export::Values(Type) pgn

	::export::DoExport .application .exportDlg $outPath

	if {![file exists $outPath]} {
		return "MISSING_OUTPUT_FILE"
	}

	set raw [readRawBytes $outPath]
	set isUtf8Bom [expr {[string range $raw 0 2] eq "\xef\xbb\xbf"}]

	set decoded [readUtf8Text $outPath]
	set hasReti [string match "*$white*" $decoded]
	set hasNepo [string match "*$black*" $decoded]

	list [file exists $outPath] $isUtf8Bom $hasReti $hasNepo
} -cleanup {
	catch {destroy .exportDlg}
	catch {file delete -force $srcPgn $outPath}
} -result {1 1 1 1}

# ------------------------------------------------------------------------------
# Test 2: Database / view export of the same game via DoExport preserves UTF-8.
# ------------------------------------------------------------------------------
tcltest::test export-utf8-fresh-database-view {multi-game export via export API decodes as UTF-8} -setup {
	set white "Réti, Richard"
	set black "Непомнящий, Ян"
	set srcPgn [makeSamplePgn $white $black]
	::scidb::db::open $srcPgn ::scidb::test::export_utf8::log log ::scidb::test::export_utf8::progress progress
	set outPath [tempPath multi-export pgn]
	catch {destroy .exportDlg}
	toplevel .exportDlg
} -body {
	set ::export::Info(base) $srcPgn
	set ::export::Info(variant) Normal
	unset -nocomplain ::export::Info(index)
	set ::export::Info(view) 0
	set ::export::Info(extension) pgn
	set ::export::Info(languages) {*}
	set ::export::Values(Type) pgn

	::export::DoExport .application .exportDlg $outPath

	if {![file exists $outPath]} {
		return "MISSING_OUTPUT_FILE"
	}

	set raw [readRawBytes $outPath]
	set isUtf8Bom [expr {[string range $raw 0 2] eq "\xef\xbb\xbf"}]

	set decoded [readUtf8Text $outPath]
	set hasReti [string match "*$white*" $decoded]
	set hasNepo [string match "*$black*" $decoded]

	list [file exists $outPath] $isUtf8Bom $hasReti $hasNepo
} -cleanup {
	catch {destroy .exportDlg}
	catch {file delete -force $srcPgn $outPath}
} -result {1 1 1 1}

# ------------------------------------------------------------------------------
# Test 3: Migration of old default profile (pgn,encoding iso8859-1, use_utf8 0).
# Unmigrated profile must be updated to use_utf8=1 and marked migrated.
# ------------------------------------------------------------------------------
tcltest::test export-utf8-migration-old-default {migrate unmigrated profile with old default encoding to UTF-8} -setup {
	unset -nocomplain ::export::Values(pgn,encoding:migrated)
	set ::export::Values(pgn,encoding) iso8859-1
	set ::export::Values(pgn,flag,use_utf8_encoding) 0
	set ::export::Values(pgn,flag,use_strict_pgn_standard) 0
} -body {
	::export::migrateOptions
	list $::export::Values(pgn,flag,use_utf8_encoding) \
	     $::export::Values(pgn,encoding:migrated)
} -result {1 1}

# ------------------------------------------------------------------------------
# Test 4: Migration must NOT override a user who explicitly chose another encoding.
# ------------------------------------------------------------------------------
tcltest::test export-utf8-migration-preserves-custom-encoding {migration preserves explicitly chosen encoding} -setup {
	unset -nocomplain ::export::Values(pgn,encoding:migrated)
	set ::export::Values(pgn,encoding) cp1251
	set ::export::Values(pgn,flag,use_utf8_encoding) 0
	set ::export::Values(pgn,flag,use_strict_pgn_standard) 0
} -body {
	::export::migrateOptions
	list $::export::Values(pgn,encoding) \
	     $::export::Values(pgn,flag,use_utf8_encoding) \
	     $::export::Values(pgn,encoding:migrated)
} -result {cp1251 0 1}

# ------------------------------------------------------------------------------
# Test 5: Migration must NOT override strict PGN standard.
# ------------------------------------------------------------------------------
tcltest::test export-utf8-migration-preserves-strict-standard {migration preserves strict PGN standard} -setup {
	unset -nocomplain ::export::Values(pgn,encoding:migrated)
	set ::export::Values(pgn,encoding) iso8859-1
	set ::export::Values(pgn,flag,use_utf8_encoding) 0
	set ::export::Values(pgn,flag,use_strict_pgn_standard) 1
} -body {
	::export::migrateOptions
	list $::export::Values(pgn,flag,use_utf8_encoding) \
	     $::export::Values(pgn,encoding:migrated)
} -result {0 1}

# ------------------------------------------------------------------------------
# Test 6: A profile that has already been migrated retains user's explicit disable.
# ------------------------------------------------------------------------------
tcltest::test export-utf8-migration-respects-explicit-disable {already-migrated profile keeps user disable} -setup {
	set ::export::Values(pgn,encoding:migrated) 1
	set ::export::Values(pgn,encoding) iso8859-1
	set ::export::Values(pgn,flag,use_utf8_encoding) 0
	set ::export::Values(pgn,flag,use_strict_pgn_standard) 0
} -body {
	::export::migrateOptions
	list $::export::Values(pgn,flag,use_utf8_encoding) \
	     $::export::Values(pgn,encoding:migrated)
} -result {0 1}

# ------------------------------------------------------------------------------
# Test 7: Export dialog options defaults & bit 28 flag.
# ------------------------------------------------------------------------------
tcltest::test export-utf8-defaults-and-flags {dialog options default to UTF-8 and getPgnFlags sets bit 28} -setup {
	unset -nocomplain ::export::Values(pgn,encoding:migrated)
	array set ::export::Values [array get ::export::Defaults]
	::export::migrateOptions
} -body {
	set defaultFlag $::export::Defaults(pgn,flag,use_utf8_encoding)
	set testFlag [::export::testUTF8Flag]
	set pgnFlags [::export::getPgnFlags]
	set hasBit28 [expr {($pgnFlags & (1 << 28)) != 0}]
	list $defaultFlag $testFlag $hasBit28
} -result {1 1 1}

# Cleanup
file delete -force $tmpDir
tcltest::cleanupTests

} ;# namespace ::scidb::test::export_utf8
