#include "hhdbkeyword.h"
/* this file lists all the hhdb keywords (or keys) as well as their classifications*/
/* an hhdb filter is of the form
   hhdb key+
  where key is an hhdb keyword

  A key must be quoted in the CQL if and only if it has special characters
  ([^a-zA-Z0-9_]),thus
  hhdb MC
   but
  hhdb "(c)"
*/

/*playerBlackKeys is a list of keys which are just search the Black tag for 
  their value. If key is in this list, then
      hhdb key
  is identical to 
     "key" in tag "Black"
*/

const vector<string> HhdbKeyword::playerBlackKeys=
    {
     "(c)",
     "(m)",
     "(s)",
     "(v)",
     "AN",
     "CR",
     "MC",
     "PH",
     "TE",
     "TT",
     "TW",
     "U1",
     "U2",
     "U3",
     "U4",
     "U5"
};

/*otherKeys are keys not in playerBlackKeys*/
const vector<string>HhdbKeyword::otherKeys=
  {
   "<cook>",
   "<eg>",
   "<main>",
   "<minor_dual>",
   "<or>",
   "composer",
   "cooked",
   "diagram",
   "dual",
   "egdiagram",
   "firstcomment",
   "gbr",
   "mainline",
   "search",
   "sound",
   "source",
   "stipulation",
   "unsound",
   "variation"
};

/* This list keys that are just longhand values for other keys. 
   It only applies to keys in playerBlackKeys. For example, "hhdb colors_reversed" 
    is another way of saying "hhdb CR" or ' "CR" in player black
*/
const vector<pair<string,string>> HhdbKeyword::abbreviationMap=
    {
     {"anticipation","AN"},
     {"colors_reversed","CR"},
     {"corrected_solution","(s)"},
     {"correction","(c)"},
     {"dual_after_move_1","U2"},
     {"dual_at_move_1","U1"},
     {"modification","(m)"},
     {"posthumous","PH"},
     {"theme_tournament","TT"},
     {"theme_tourney","TT"},
     {"theoretical_ending","TE"},
     {"too_many_composers", "MC"},
     {"twin","TW"},
     {"unreachable","U5"},
     {"version","(v)"},
     {"white_fails", "U3"},
     {"white_wins_in_draw","U4"}
    };

/*award keys are keywords specifically used  in hhdb award, hhdb special, hhdb prize, hhdb hm, 
  hhdb commendation*/

const vector<string>HhdbKeyword::awardKeys
{ "award",
    "commendation",
    "hm",
    "max",
    "prize",
    "sort",
    "special"
    };

/* awardTypeKeys specify the type of an award, one of the four listed.
   Here, "award" subsumes the other three*/

const vector<string>HhdbKeyword::awardTypeKeys
{
  "award",
    "commendation",
    "hm",
    "prize"
    };

/* gbr keys are keywords that can follow "hhdb gbr", e.g.
     hhdb gbr material
*/
const vector<string>HhdbKeyword::gbrKeys
{
  "kings",
    "material",
    "pawns",
    "pieces"
};

/*takesParameterKeys are used for keywords which CAN be followed
  by a single quoted parameter. It is equivalent to 
     hhdb key
  being of type string, in which case the following quoted parameter 
  if present is an implicit search parameter.
  This does not correctly handle gbr keys.
  This is used entirely for command-line parsing.
  This might be renamed to isString key to clarify its function
*/

const vector<string>HhdbKeyword::takesParameterKeys
{
    "composer",
    "firstcomment",
    "gbr",
    "search",
    "source",
    "stipulation"
      };
    

