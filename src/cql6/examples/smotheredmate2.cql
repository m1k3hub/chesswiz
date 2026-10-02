/*black is in smothered mate,
  sorted by ascending year, before 1900
  outputs the specific blockers*/
  
cql(input hhdbvi.pgn)
btm mate
not ♚→□△
/// "Smothered mate. Blockers at: " ▲ attackedby ♚
sort min "Year" year < 1900

