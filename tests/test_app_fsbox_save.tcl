# Saving in the file box checks only the file name, with its extension once:
# a typed folder or drive is not a forbidden character, and "x.pgn" does not
# become "x.pgn.pgn" (F-24 on Windows).
package require tcltest 2.5

namespace eval ::fsbox::.fsboxSaveTest { variable Vars }
set ::fsbox::.fsboxSaveTest::Vars(widget:main) .
set ::fsbox::.fsboxSaveTest::Vars(defaultextension) .pgn

proc ::scidb::test::fsboxSaveChecked {file} {
	rename ::fsbox::checkPath ::fsbox::checkPath_orig
	proc ::fsbox::checkPath {parent path} { set ::scidb::test::fsboxSaveName $path; return 1 }
	try {
		::fsbox::CheckSaveName .fsboxSaveTest $file
	} finally {
		rename ::fsbox::checkPath {}
		rename ::fsbox::checkPath_orig ::fsbox::checkPath
	}
	return $::scidb::test::fsboxSaveName
}

tcltest::test fsbox-save-name {the checked name is the tail, extension added once} -body {
	lmap f {retest retest.pgn retest.PGN C:/cwexplore/export/retest.pgn /home/u/games.pgn} {
		::scidb::test::fsboxSaveChecked $f
	}
} -result {retest.pgn retest.pgn retest.PGN retest.pgn games.pgn}

tcltest::test fsbox-save-backslash {a Windows path with backslashes} -constraints win -body {
	::scidb::test::fsboxSaveChecked {C:\cwexplore\export\retest}
} -result retest.pgn

tcltest::test fsbox-save-drive-allowed {a full Windows path passes the real check} -body {
	::fsbox::checkPath . [file tail {C:/cwexplore/export/retest.pgn}]
} -result 1

namespace delete ::fsbox::.fsboxSaveTest
::tcltest::cleanupTests
