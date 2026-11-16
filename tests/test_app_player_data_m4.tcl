package require tcltest 2.5
namespace eval ::m4 {
 variable dir [file join $::env(HOME) m4-fixtures]
 file mkdir $dir
 proc write {name text} {
  variable dir
  set path [file join $dir $name]
  set f [open $path w]; fconfigure $f -encoding utf-8
  puts $f $text; close $f
  return $path
 }
 proc writeRaw {name text} {
  variable dir
  set path [file join $dir $name]
  set f [open $path wb]
  puts -nonewline $f [encoding convertto utf-8 $text]
  close $f
  return $path
 }
 proc convert {kind text} {
  variable dir
  set in [write input.csv $text]
  ::scidb::app::filterRatingList $kind $in $dir/output.txt 1800
  set f [open $dir/output.txt]; set result [read $f]; close $f
  return $result
 }
 proc checkReject {kind in out} {
  file delete -force $out $out.part
  set rc [catch {::scidb::app::filterRatingList $kind $in $out 1800}]
  list $rc [file exists $out] [file exists $out.part]
 }
}
tcltest::test VAL-PD4-007 {Revised standard takes priority independent of header order} -body {
 set result [::m4::convert ecf {ECF_code,full_name,original_standard,revised_standard
999001A,"Fixture, Alpha",1801,1902}]
 string match {*|1902|*} $result
} -result 1
tcltest::test VAL-PD4-008 {Rapid and online cannot replace standard} -body {
 set result [::m4::convert ecf {ECF_code,full_name,revised_rapid,original_standard_online,original_standard,revised_standard
999002B,"Fixture, Beta",2700,2800,1803,0}]
 expr {[string match {*|1803|*} $result] && ![string match {*|2700|*} $result]}
} -result 1
tcltest::test VAL-PD4-005 {Missing rating column fails} -body {
 catch {::m4::convert ecf {ECF_code,full_name
999003C,"Fixture, Gamma"}}
} -result 1
tcltest::test VAL-PD4-011 {Malformed suffix rejects a valid prefix} -body {
 catch {::m4::convert iccf "990001;ENG;IM;Fixture, Delta;20;2200;90;\n<html>blocked</html>"}
} -result 1
tcltest::test VAL-PD4-009 {ICCF RD does not become sex; titles use correspondence namespace} -body {
 set result [::m4::convert iccf {990002;ENG;LGM;Fixture, Epsilon;20;2200;90;}]
 expr {[string match {*|0|-|0|2200|ENG|CLGM|*} $result]}
} -result 1
tcltest::test VAL-PD4-011-quotes {Unterminated quoted CSV rejects valid prefix} -body {
 catch {::m4::convert ecf "ECF_code,full_name,revised_standard\n999004D,\"Fixture, Zeta\",1900\n999005E,\"unfinished"}
} -result 1

tcltest::test VAL-PD4-004 {Windows-1252 quoted comma names survive conversion} -body {
 set path $::m4::dir/cp1252.csv
 set f [open $path wb]
 puts -nonewline $f [encoding convertto cp1252 {ZPS,Mitgliedsnummer,"Name,Vorname",DWZ
99999,1,"Fïxture,Alpha",1900
}]
 close $f
 ::scidb::app::filterRatingList dwz $path $::m4::dir/out.txt
 set f [open $::m4::dir/out.txt]; fconfigure $f -encoding utf-8
 set out [read $f]; close $f
 string match {*Fïxture, Alpha*} $out
} -result 1
tcltest::test VAL-PD4-006 {Distinct club memberships remain distinct records} -body {
 set out [::m4::convert dwz {ID,ZPS,Mitgliedsnummer,"Name,Vorname",DWZ
SOURCE1,99999,1,"Fixture, Alpha",1900
SOURCE1,99998,2,"Fixture, Alpha",1900
SOURCE2,99999,3,"Fixture, Beta",1900}]
 expr {[string match {*99999-1|*} $out] && [string match {*99998-2|*} $out] && [string match {*99999-3|*} $out]}
} -result 1
tcltest::test VAL-PD4-015 {Boundary and FIDE/title retention exemptions} -body {
 set out [::m4::convert ecf {ECF_code,full_name,revised_standard,FIDE_no,title
999010A,"Fixture, Below",1799,0,
999011B,"Fixture, Boundary",1800,0,
999012C,"Fixture, Identity",1000,999800001,
999013D,"Fixture, Titled",1000,0,IM}]
 expr {![string match {*Fixture, Below*} $out] && [string match {*kept=3*} $out]}
} -result 1
tcltest::test VAL-PD4-003 {DWZ ZIP import selects spieler.csv irrespective of archive entry order} -body {
 set zpath $::m4::dir/reordered.zip
 exec python3 -c "import sys, zipfile\nwith zipfile.ZipFile(sys.argv\[1\], 'w', compression=zipfile.ZIP_DEFLATED) as z:\n    z.writestr('vereine.csv', 'ZPS,Verein\\n10614,Club\\n')\n    z.writestr('README.txt', 'Note\\n')\n    z.writestr('verbaende.csv', 'LV,Verband\\n0,DSB\\n')\n    z.writestr('spieler.csv', 'ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ\\n99999,1,\"Fixture, ZipOrder\",1950\\n'.encode('cp1252'))\n" $zpath
 set counts [::scidb::app::filterRatingList dwz $zpath $::m4::dir/zipout.txt 1800]
 set f [open $::m4::dir/zipout.txt]; fconfigure $f -encoding utf-8
 set out [read $f]; close $f
 list $counts [string match {*Fixture, ZipOrder*} $out] [string match {*Verein*} $out]
} -result {{1 1} 1 0}
tcltest::test VAL-PD4-011-corrupt-zip {Corrupt ZIP and HTML 403 bodies are rejected} -body {
 set badzip [::m4::write corrupt.zip "PK\x03\x04corrupt_not_a_valid_zip_archive"]
 set html403 [::m4::write 403.csv "<!DOCTYPE html><html><head><title>403 Forbidden</title></head><body>403</body></html>"]
 list [catch {::scidb::app::filterRatingList dwz $badzip $::m4::dir/bad1.txt}] \
      [catch {::scidb::app::filterRatingList ecf $html403 $::m4::dir/bad2.txt}] \
      [catch {::scidb::app::filterRatingList iccf $html403 $::m4::dir/bad3.txt}]
} -result {1 1 1}
tcltest::test VAL-PD4-011-required-fields {DWZ, ECF, and ICCF rows with empty, non-numeric, or overflowing numeric/grade fields reject whole import} -body {
 set ecfEmpty        [::m4::write ecf-empty.csv "ECF_code,full_name,revised_standard\n999001A,\"Fixture, Valid\",1900\n999002B,,1900\n"]
 set dwzEmpty        [::m4::write dwz-empty.csv "ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ\n99999,1,\"Fixture, Valid\",1900\n99999,2,,1900\n"]
 set dwzComma        [::m4::write dwz-comma.csv "ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ\n99999,1,\"Fixture, Valid\",1900\n99999,2,\",GivenOnly\",1900\n"]
 set dwzNoId         [::m4::write dwz-noid.csv "ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ\n99999,1,\"Fixture, Valid\",1900\n,2,\"Fixture, MissingZps\",1900\n"]
 set ecfNoId         [::m4::write ecf-noid.csv "ECF_code,full_name,revised_standard\n999001A,\"Fixture, Valid\",1900\n,\"Fixture, MissingCode\",1900\n"]
 set dwzBadMember    [::m4::write dwz-bad-member.csv "ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ\n99999,1,\"Fixture, Valid\",1900\n99999,abc,\"Fixture, BadMember\",1900\n"]
 set dwzZeroMember   [::m4::write dwz-zero-member.csv "ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ\n99999,1,\"Fixture, Valid\",1900\n99999,0,\"Fixture, ZeroMember\",1900\n"]
 set dwzBadRating    [::m4::write dwz-bad-rating.csv "ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ\n99999,1,\"Fixture, Valid\",1900\n99999,2,\"Fixture, BadRating\",abc\n"]
 set dwzHugeRating   [::m4::write dwz-huge-rating.csv "ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ\n99999,1,\"Fixture, Valid\",1900\n99999,2,\"Fixture, HugeRating\",99999\n"]
 set dwzBadFide      [::m4::write dwz-bad-fide.csv "ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ,FIDE-ID\n99999,1,\"Fixture, Valid\",1900,\n99999,2,\"Fixture, BadFide\",1500,xyz\n"]
 set dwzBadBirth     [::m4::write dwz-bad-birth.csv "ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ,Geburtsjahr\n99999,1,\"Fixture, Valid\",1900,\n99999,2,\"Fixture, BadBirth\",1900,19x5\n"]
 set dwzDupBad       [::m4::write dwz-dup-bad.csv "ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ\n99999,1,\"Fixture, Valid\",1900\n99999,1,\"Fixture, Valid\",abc\n"]
 set ecfBadRating    [::m4::write ecf-bad-rating.csv "ECF_code,full_name,revised_standard,FIDE_no\n999001A,\"Fixture, Valid\",1900,\n999002B,\"Fixture, BadRating\",abc,\n"]
 set ecfBadOrig      [::m4::write ecf-bad-orig.csv "ECF_code,full_name,revised_standard,original_standard\n999001A,\"Fixture, Valid\",1900,1850\n999002B,\"Fixture, BadOrig\",1900,abc\n"]
 set ecfBadGrade     [::m4::write ecf-bad-grade.csv "ECF_code,full_name,grade\n999001A,\"Fixture, Valid\",150\n999002B,\"Fixture, BadGrade\",abc\n"]
 set ecfBadFide      [::m4::write ecf-bad-fide.csv "ECF_code,full_name,revised_standard,FIDE_no\n999001A,\"Fixture, Valid\",1900,\n999002B,\"Fixture, BadFide\",1500,xyz\n"]
 set ecfGradeWrap    [::m4::write ecf-grade-wrap.csv "ECF_code,full_name,grade\n999001A,\"Fixture, Valid\",150\n999002B,\"Fixture, Overflow\",536871087\n"]
 set ecfGradeTooHigh [::m4::write ecf-grade-high.csv "ECF_code,full_name,grade\n999001A,\"Fixture, Valid\",150\n999002B,\"Fixture, GradeHigh\",426\n"]
 set iccfWrapRating  [::m4::write iccf-wrap-rating.csv "990001;ENG;IM;Fixture, ValidIccf;20;2200;90;\n990002;ENG;IM;Fixture, WrapIccf;20;4294969496;90;\n"]
 set gradeMaxOut     [::m4::convert ecf "ECF_code,full_name,grade\n999001A,\"Fixture, GradeMax\",425\n"]
 set cases [list \
  [list ecf $ecfEmpty        $::m4::dir/ecf-empty-out.txt] \
  [list dwz $dwzEmpty        $::m4::dir/dwz-empty-out.txt] \
  [list dwz $dwzComma        $::m4::dir/dwz-comma-out.txt] \
  [list dwz $dwzNoId         $::m4::dir/dwz-noid-out.txt] \
  [list ecf $ecfNoId         $::m4::dir/ecf-noid-out.txt] \
  [list dwz $dwzBadMember    $::m4::dir/dwz-bad-member-out.txt] \
  [list dwz $dwzZeroMember   $::m4::dir/dwz-zero-member-out.txt] \
  [list dwz $dwzBadRating    $::m4::dir/dwz-bad-rating-out.txt] \
  [list dwz $dwzHugeRating   $::m4::dir/dwz-huge-rating-out.txt] \
  [list dwz $dwzBadFide      $::m4::dir/dwz-bad-fide-out.txt] \
  [list dwz $dwzBadBirth     $::m4::dir/dwz-bad-birth-out.txt] \
  [list dwz $dwzDupBad       $::m4::dir/dwz-dup-bad-out.txt] \
  [list ecf $ecfBadRating    $::m4::dir/ecf-bad-rating-out.txt] \
  [list ecf $ecfBadOrig      $::m4::dir/ecf-bad-orig-out.txt] \
  [list ecf $ecfBadGrade     $::m4::dir/ecf-bad-grade-out.txt] \
  [list ecf $ecfBadFide      $::m4::dir/ecf-bad-fide-out.txt] \
  [list ecf $ecfGradeWrap    $::m4::dir/ecf-grade-wrap-out.txt] \
  [list ecf $ecfGradeTooHigh $::m4::dir/ecf-grade-high-out.txt] \
  [list iccf $iccfWrapRating $::m4::dir/iccf-wrap-rating-out.txt]]
 set results {}
 foreach c $cases {
  lassign $c kind in out
  lappend results [::m4::checkReject $kind $in $out]
 }
 lappend results [string match {*|4000|*} $gradeMaxOut]
 set results
} -result [list \
 {1 0 0} {1 0 0} {1 0 0} {1 0 0} {1 0 0} {1 0 0} {1 0 0} {1 0 0} \
 {1 0 0} {1 0 0} {1 0 0} {1 0 0} {1 0 0} {1 0 0} {1 0 0} {1 0 0} \
 {1 0 0} {1 0 0} {1 0 0} 1]
tcltest::test VAL-PD4-011-pipe-delimiters {Pipe and CR/LF separator injection in CSV and all raw installed-list fields are rejected while normal CRLF lines load} -body {
 set dwzPipeZps  [::m4::write dwz-pipe-zps.csv "ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ\n99999,1,\"Fixture, Valid\",1900\n\"99|999\",2,\"Fixture, PipeZps\",1900\n"]
 set dwzDashZps  [::m4::write dwz-dash-zps.csv "ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ\n99999,1,\"Fixture, Valid\",1900\n99-99,2,\"Fixture, DashZps\",1900\n"]
 set dwzAlphaZps [::m4::write dwz-alpha-zps.csv "ZPS,Mitgliedsnummer,\"Name,Vorname\",DWZ\nB000A,2,\"Fixture, AlphaZps\",1900\n"]
 set ecfPipeId   [::m4::write ecf-pipe-id.csv "ECF_code,full_name,revised_standard\n999001A,\"Fixture, Valid\",1900\n\"99|002B\",\"Fixture, PipeEcf\",1900\n"]
 set iccfPipeNm  [::m4::write iccf-pipe-name.csv "990098;ENG;IM;Fixture, ValidIccf;20;2200;90;\n990099;ENG;IM;Fixture, Pipe|Name;20;2200;90;\n"]
 set ecfCrCsvNm  [::m4::writeRaw ecf-cr-name.csv "ECF_code,full_name,revised_standard\n999001A,\"Fixture\r, CrCsvName\",1900\n"]
 set dwzPipeOut  $::m4::dir/dwz-pipe-out.txt
 set ecfPipeOut  $::m4::dir/ecf-pipe-out.txt
 set iccfPipeOut $::m4::dir/iccf-pipe-out.txt
 set ecfCrOut    $::m4::dir/ecf-cr-out.txt
 file delete -force $dwzPipeOut $ecfPipeOut $iccfPipeOut $ecfCrOut
 set extraPipeInstalled [::m4::write extra-pipe.txt "#chesswiz-rating-list v1 kind=dwz date=2026-01-01 read=1 kept=1\n#source synthetic\n10614-799|0|M|1990|2100|GER|-|Pipeinj, Trailing|EXTRA\n"]
 set crInstalled [::m4::writeRaw cr-fields.txt "#chesswiz-rating-list v1 kind=ecf date=2026-01-01 read=7 kept=7\n#source synthetic\n499001A|0|M\rX|0|2100|ENG|-|Fixture, Crsex\n499002B|0|M|0|2100|ENG\r|-|Fixture, Crfed\n499003C|0|M|0|2100|ENG|GM\rIM|Fixture, Crtitles\n499004D|0|M|0|2100\r|ENG|-|Fixture, Crrating\n499005E|0|M|0|2100|ENG|-|Fixture\r, Crname\n499006F|0|M|0|2100|ENG|-|Fixture, Crtrail\r\r\n499007G|0|M|0|2100|ENG|-|Fixture, CrlfValid\r\n"]
 ::scidb::app::load installed $extraPipeInstalled
 ::scidb::app::load installed $crInstalled
 ::scidb::app::load done
 set crlfRec [::scidb::player::lookup -name "Fixture, CrlfValid"]
 list \
  [catch {::scidb::app::filterRatingList dwz $dwzPipeZps $dwzPipeOut 1800}] [file exists $dwzPipeOut] \
  [catch {::scidb::app::filterRatingList dwz $dwzDashZps $::m4::dir/dwz-dash-out.txt 1800}] \
  [catch {::scidb::app::filterRatingList dwz $dwzAlphaZps $::m4::dir/dwz-alpha-out.txt 1800}] \
  [catch {::scidb::app::filterRatingList ecf $ecfPipeId $ecfPipeOut 1800}] [file exists $ecfPipeOut] \
  [catch {::scidb::app::filterRatingList iccf $iccfPipeNm $iccfPipeOut 1800}] [file exists $iccfPipeOut] \
  [::m4::checkReject ecf $ecfCrCsvNm $ecfCrOut] \
  [expr {[::scidb::player::lookup -name "Pipeinj, Trailing"] eq ""}] \
  [expr {[::scidb::player::lookup -name "Fixture, Crsex"] eq ""}] \
  [expr {[::scidb::player::lookup -name "Fixture, Crfed"] eq ""}] \
  [expr {[::scidb::player::lookup -name "Fixture, Crtitles"] eq ""}] \
  [expr {[::scidb::player::lookup -name "Fixture, Crrating"] eq ""}] \
  [expr {[::scidb::player::lookup -name "Fixture, Crname"] eq ""}] \
  [expr {[::scidb::player::lookup -name "Fixture, Crtrail"] eq ""}] \
  [expr {$crlfRec ne "" && [dict get $crlfRec ecf] eq "499007G"}]
} -result {1 0 1 0 1 0 1 0 {1 0 0} 1 1 1 1 1 1 1 1}
tcltest::test VAL-PD4-014 {Same FIDE identity joins without overwriting authoritative spelling; conflicting IDs remain distinct} -body {
 set fideHdr "ID Number      Name                                                         Fed Sex Tit  WTit OTit           FOA SRtng SGm SK RRtng RGm Rk BRtng BGm BK B-day Flag"
 set r1 [format "%-15s%-61s%-4s%-4s%-5s%-5s%-15s%-4s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s" 999700001 {Authoritative, One} GER M GM "" "" "" 2500 0 10 0 0 10 0 0 10 1985 ""]
 set r2 [format "%-15s%-61s%-4s%-4s%-5s%-5s%-15s%-4s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s%-3s%-6s%-4s" 999700002 {Distinct, Person} GER M "" "" "" "" 2200 0 10 0 0 10 0 0 10 1990 ""]
 set fideFile [::m4::write fide-auth.txt "$fideHdr\n$r1\n$r2"]
 ::scidb::app::load fide $fideFile
 set dwzInstalled [::m4::write dwz-join.txt "#chesswiz-rating-list v1 kind=dwz date=2026-01-01 read=2 kept=2\n#source synthetic\n10614-701|999700001|M|1985|2450|GER|GM|Authoritative, One-Variant\n10614-702|999700003|M|1992|2100|GER|-|Distinct, Person\n"]
 ::scidb::app::load installed $dwzInstalled
 ::scidb::app::load done
 set p1 [::scidb::player::lookup -fide 999700001]
 set p2 [::scidb::player::lookup -fide 999700002]
 set p3 [::scidb::player::lookup -fide 999700003]
 list [dict get $p1 name] [dict get $p1 dsb] [expr {[dict get $p2 fideID] != [dict get $p3 fideID]}] [dict get $p3 dsb]
} -result {{Authoritative, One} 10614-701 1 10614-702}
file delete -force $::m4::dir
tcltest::cleanupTests
