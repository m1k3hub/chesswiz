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
 proc convert {kind text} {
  variable dir
  set in [write input.csv $text]
  ::scidb::app::filterRatingList $kind $in $dir/output.txt 1800
  set f [open $dir/output.txt]; set result [read $f]; close $f
  return $result
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
