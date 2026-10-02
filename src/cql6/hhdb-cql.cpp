#include "hhdbkeyword.h"
#include "abbreviations.h"

/*This file deals with predefined conversions of hhdb filters (except for hhdb award filters)
  to cql strings*/


/* return {str \i} ;  [odd formatting due to emacs indent bug]
   used by hhdbgbr keywords
*/

/* If MC is in player black, then read the start of the first comment until
   a period is seen to get the composers. Otherwise, read the player white field,
   deleting any trailing " NN". This is tested in the suite hhdb-full.cql near the end
*/
const string hhdbcomposer=
     R"E({if isunbound CQL_composer_string
             CQL_composer_string =
                if player black "MC" 
                   position 0: {originalcomment ~~ "^([^.]+)\." \1}
                else{
                   if player white[-3:]==" NN"
                      player white [:-3]
                   else player white
                  }
            CQL_composer_string}
             )E";

const string hhdbcook=
     R"E( originalcomment "<cook" or false)E";

const string hhdbcooked=
     "cql_hhdbhascook";

const string hhdbdiagram =
     R"E({event ~~ "#([^ ]+)" \1})E";

const string hhdbdual=
     R"E(player black ~~ "U[12]" or false)E";
const string hhdbeg=
     R"E( originalcomment "<eg>")E";

const string hhdbegdiagram=
     R"E(position 0 : 
        {originalcomment ~~ "EG#(\d+)" 
         int \1}
    )E";

const string hhdbfirstcomment=
     "position 0 : originalcomment";

const string hhdbgbr=
     R"E(
   player black ~~  "[+-=]\d{4}\.\d{2}[a-h][1-8][a-h][1-8]" 
//////////////////      0 1234  5 67  8=-4 9=-3 10=-2 11=-1
     )E";

const string hhdbgbrmaterial=
     hhdbgbr+"[1:-4]";
const string hhdbgbrpieces=
     hhdbgbr+"[1:5]";
const string hhdbgbrpawns=
     hhdbgbr+"[6:8]";
const string hhdbgbrkings=
     hhdbgbr+"[-4:]";

const string hhdbmain=
     R"E(
       cql_assertvariations 
          "'hhdb <main>' can only be used when 'variations' is set in the CQL header (or run with 'cql -variations')"
        and originalcomment "<main>")E";
const string hhdbmainline=
     R"E(
     cql_assertvariations
       "'hhdb mainline' can only be used when 'variations' is set in the CQL header (or run with 'cql -variations...')"
     and not find quiet <-- move previous secondary and not originalcomment "<main>"
     )E";
const string hhdbminor_dual=
     R"E(originalcomment "<minor_dual" or false)E";
const string hhdbor =
     R"E(
      cql_assertvariations 
        "'hhdb <or>' can only be used when 'variations' is set in the CQL header (or run with 'cql -variations...')"
       and originalcomment "<or>")E";

const string hhdbsearch=
     R"E(
          event 
          + \n  
          + tag "White" + \n
          + tag "Black"
          + if (position 0: originalcomment)
             \n + position 0:originalcomment 
            else ""
    )E";

//we DO allow some studies with a <cook> tag if "U[1-5]" is not listed in the header (there are three). 
//These also count as unsound studies. However, if there is a <cook> tag AND a "U" is listed, then the
//study IS counted as sound. 

const string hhdbsound=    
     R"E(
      not{ 
         hhdb cooked and player black ~~ "U[12]"
         or player black ~~ "U[345]"}
      )E";

const string hhdbunsound=
  R"E(hhdb cooked or player black ~~ "U[1-5]")E";
        
const string hhdbstipulation =
     R"E(
     {position 0:originalcomment ~~ "stipulation: ([^.]+)\."
      \1}
     )E";

const string hhdbvariation=
     R"E(
     cql_assertvariations 
        "'hhdb variation' can only be used when 'variations' is set in the CQL header (or run with 'cql -variations...')"
     and find quiet <-- move previous secondary and not originalcomment "<main>"
      )E";
const map<string,string> HhdbKeyword::KeyToCql=
  {
   {"<cook>",hhdbcook},
   {"<eg>",hhdbeg},
   {"<main>",hhdbmain},
   {"<minor_dual>",hhdbminor_dual},
   {"<or>",hhdbor},
   {"composer",hhdbcomposer},
   {"cooked",hhdbcooked},
   {"diagram",hhdbdiagram},
   {"dual",hhdbdual},
   {"egdiagram",hhdbegdiagram},
   {"firstcomment",hhdbfirstcomment},
   {"gbr",hhdbgbr},
   {"gbrkings",hhdbgbrkings},
   {"gbrmaterial",hhdbgbrmaterial},
   {"gbrpieces",hhdbgbrpieces},
   {"gbrpawns",hhdbgbrpawns},
   {"mainline",hhdbmainline},
   {"search",hhdbsearch},
   {"sound",hhdbsound},
   {"unsound",hhdbunsound},
   {"stipulation",hhdbstipulation},
   {"variation",hhdbvariation},
   {"zzz zzz","DUMMY"} //for formatting this map source
  };
   
string HhdbKeyword::cql_from_key(const string &key){
  if (HhdbKeyword::isPlayerBlackKey(key))
    return "notransform "s +
      '\"' + key + '\"'
      + " in player black ";      
  if (KeyToCql.count(key)>0)
    return "notransform "s + KeyToCql.at(key);
  return "";
}
