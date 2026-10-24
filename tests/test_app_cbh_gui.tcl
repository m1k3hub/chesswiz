# ======================================================================
# Roadmap P10: write ChessBase .cbh from the GUI.
#
# The codec can already write (::scidb::db::copy into a new .cbh). These
# tests drive the *user-facing* paths with mocked dialogs: the New
# Database dialog, Database > Maintenance > Convert, and the Export
# dialog's ChessBase destination. They also check that an unsupported
# re-encode is reported instead of silently creating a broken file.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::cbhgui {

variable tmpRoot [file join $::scidb::test::app::testDir tmp-app cbh-gui]
variable nop {apply {args {return 0}}}

proc fixturePresent {} {
	return [file exists [file join $::scidb::test::app::testDir tmp-app cbh-p0 in "C45 Scotch Opening-168.cbh"]]
}

proc tempDir {name} {
	variable tmpRoot
	set dir [file join $tmpRoot $name]
	file delete -force $dir
	file mkdir $dir
	return $dir
}

# Copy the read-only CBH fixture (all companion files) into $dir/src.*.
proc copyFixture {dir} {
	set root [file join $::scidb::test::app::testDir tmp-app cbh-p0 in "C45 Scotch Opening-168"]
	foreach f [glob -nocomplain "${root}.*"] {
		file copy -force $f [file join $dir "src[file extension $f]"]
	}
	return [file normalize [file join $dir src.cbh]]
}

proc load {file} {
	::scidb::db::load $file $::scidb::test::cbhgui::nop {} -readonly 1
}

proc gameInfos {file} {
	set result {}
	set n [::scidb::db::count games $file Normal]
	for {set i 0} {$i < $n} {incr i} {
		lappend result [::scidb::db::get gameInfo $i -1 $file Normal]
	}
	return [list $n $result]
}

# Replace the dialogs the GUI paths use; unmockDialogs restores them.
proc mockDialogs {saveFileResult} {
	rename ::dialog::saveFile ::cbhgui::zs; proc ::dialog::saveFile args [list return $saveFileResult]
	rename ::dialog::question ::cbhgui::zq; proc ::dialog::question args { return no }
	rename ::dialog::info ::cbhgui::zi; proc ::dialog::info args { set ::cbhgui::zinfo $args; return {} }
	rename ::dialog::error ::cbhgui::ze; proc ::dialog::error args { set ::cbhgui::zerr $args; return 0 }
	unset -nocomplain ::cbhgui::zinfo ::cbhgui::zerr
}

proc unmockDialogs {} {
	catch { rename ::dialog::saveFile {}; rename ::cbhgui::zs ::dialog::saveFile }
	catch { rename ::dialog::question {}; rename ::cbhgui::zq ::dialog::question }
	catch { rename ::dialog::info {}; rename ::cbhgui::zi ::dialog::info }
	catch { rename ::dialog::error {}; rename ::cbhgui::ze ::dialog::error }
}

proc closeBase {file} {
	catch { $::application::database::Vars(switcher) remove $file }
	catch { ::scidb::db::close $file }
}

} ;# namespace cbhgui

tcltest::testConstraint cbhFixturePresent [::scidb::test::cbhgui::fixturePresent]

# ----------------------------------------------------------------------
# 1. New Database dialog: choose .cbh, get a ChessBase database.
# ----------------------------------------------------------------------
tcltest::test cbh-new-database {New Database dialog creates a .cbh database} -setup {
	set dir [::scidb::test::cbhgui::tempDir new]
	set dst [file normalize [file join $dir new.cbh]]
	::scidb::test::cbhgui::mockDialogs [list $dst utf-8]
} -body {
	set rc [catch { ::menu::dbNew .application Normal } err]
	set codec {}
	catch { set codec [::scidb::db::get codec $dst Normal] }
	list $rc [file exists $dst] $codec
} -cleanup {
	::scidb::test::cbhgui::closeBase $dst
	::scidb::test::cbhgui::unmockDialogs
	catch { file delete -force $dir }
} -result {0 1 cbh}

# ----------------------------------------------------------------------
# 2. Convert dialog: whole ChessBase database into a new .cbh.
# ----------------------------------------------------------------------
tcltest::test cbh-convert-roundtrip {Convert dialog raw-copies a CBH database into a new .cbh} \
-constraints cbhFixturePresent -setup {
	set dir [::scidb::test::cbhgui::tempDir convert]
	set src [::scidb::test::cbhgui::copyFixture $dir]
	set dst [file normalize [file join $dir out.cbh]]
	::scidb::test::cbhgui::load $src
	set srcData [::scidb::test::cbhgui::gameInfos $src]
	::scidb::test::cbhgui::mockDialogs [list $dst utf-8]
} -body {
	set rc [catch { ::application::database::ConvertDatabase .application $src Normal } err]
	::scidb::test::cbhgui::closeBase $src
	::scidb::test::cbhgui::load $dst
	set dstData [::scidb::test::cbhgui::gameInfos $dst]
	::scidb::test::cbhgui::closeBase $dst
	list $rc [file exists $dst] [info exists ::cbhgui::zinfo] [expr {$srcData eq $dstData}]
} -cleanup {
	::scidb::test::cbhgui::closeBase $src
	::scidb::test::cbhgui::closeBase $dst
	::scidb::test::cbhgui::unmockDialogs
	catch { file delete -force $dir }
} -result {0 1 1 1}

# ----------------------------------------------------------------------
# 3. Export dialog: filtered view into a new .cbh.
# ----------------------------------------------------------------------
tcltest::test cbh-export-view {Export dialog raw-copies a view into a new .cbh} \
-constraints cbhFixturePresent -setup {
	set dir [::scidb::test::cbhgui::tempDir export]
	set src [::scidb::test::cbhgui::copyFixture $dir]
	set dst [file normalize [file join $dir export.cbh]]
	::scidb::test::cbhgui::load $src
	set ::export::Info(base) $src
	set ::export::Info(variant) Normal
	unset -nocomplain ::export::Info(index)
	set ::export::Info(view) 0
	set ::export::Info(extension) cbh
	set ::export::Info(name) TestBase
	set ::export::Info(languages) {*}
	unset -nocomplain ::export::Info(fsbox)
	set ::export::Values(Type) cbh
	set ::export::Values(Types) {cbh}
} -body {
	set rc [catch {
		catch { destroy .exportDlg }
		toplevel .exportDlg
		::export::DoExport .application .exportDlg $dst
	} err]
	::scidb::test::cbhgui::load $dst
	set n [::scidb::db::count games $dst Normal]
	::scidb::test::cbhgui::closeBase $dst
	list $rc [file exists $dst] $n
} -cleanup {
	catch { destroy .exportDlg }
	::scidb::test::cbhgui::closeBase $src
	::scidb::test::cbhgui::closeBase $dst
	catch { file delete -force $dir }
} -result {0 1 10}

# ----------------------------------------------------------------------
# 4. Convert dialog refuses a non-ChessBase source, and shows the error.
# ----------------------------------------------------------------------
tcltest::test cbh-reencode-refused-gui {Convert dialog refuses a non-CBH source for a .cbh destination} \
-setup {
	set dir [::scidb::test::cbhgui::tempDir refuse]
	# Build a persistent .sci database (read-only when reopened, so the
	# unsaved? guard does not fire before the format check).
	set srcPgn [file join $dir src.pgn]
	set fh [open $srcPgn w]
	puts $fh "\[Event \"Refuse\"\]\n\[White \"W\"\]\n\[Black \"B\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 1-0\n"
	close $fh
	set nop $::scidb::test::cbhgui::nop
	::scidb::db::open $srcPgn $nop {} $nop {}
	set sci [file normalize [file join $dir src.sci]]
	::scidb::db::new $sci Normal [::application::database::lookupType Unspecific]
	::scidb::db::attach $sci $sci
	::scidb::db::copy $srcPgn $sci {} $nop {} $nop {}
	::scidb::db::save $sci $nop {}
	::scidb::db::close $sci
	::scidb::db::close $srcPgn
	::scidb::test::cbhgui::load $sci
	set dst [file normalize [file join $dir out.cbh]]
	::scidb::test::cbhgui::mockDialogs [list $dst utf-8]
} -body {
	set rc [catch { ::application::database::ConvertDatabase .application $sci Normal } err]
	list $rc [info exists ::cbhgui::zerr] [file exists $dst]
} -cleanup {
	::scidb::test::cbhgui::closeBase $sci
	::scidb::test::cbhgui::closeBase $dst
	::scidb::test::cbhgui::unmockDialogs
	catch { file delete -force $dir }
} -result {0 1 0}

tcltest::cleanupTests
