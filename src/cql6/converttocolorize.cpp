#include "converttocolorize.h"
#include "lexer.h"
#include "cqlassert.h"
#include "util.h"
#include <fstream>
string readstdin();
using std::ofstream;
string ConvertToColorize::convert(){
  string s=readstdin();
  return convert(s);
}

string ConvertToColorize::convert(const string&cqlstring){
  Lexer lexer(cqlstring,true);
  vector<Token*>tokens;
  while(Token*token=lexer.nextToken())
    tokens.push_back(token);
  stringstream ret;
  for(Token*token:tokens)
    ret<<convert(token);
  return ret.str();
}

string ConvertToColorize::convert(const Token*token){
  const string style=token->colorizerClass();
  const string original=token->getTrueString();
  return span(style,escape(original));
}

string ConvertToColorize::escapeAscii(const string&str){
  uassert(str.size()==1,"eA bad arg");
  char c=str.at(0);
  switch(c){
      case '<': return "&lt;";
      case '>': return "&gt;";
      case '&': return "&amp;";
      default:  return str;
  }
}
    
string ConvertToColorize::escape(const string& str){
  stringstream s;
  s<<std::uppercase<<std::hex;
  vector<UChar>uchars=UChar::parseChars(str);
  for(UChar uchar:uchars){
    if(uchar.getValue()<=127){
      s<<escapeAscii(uchar.toString());
      continue;
    }
    string currentclass=escapeClass(uchar);
    string currenttitle=escapeTitle(uchar);
    string titlestring="";
    string classstring="";
    if(currenttitle.size())titlestring=" title="s+util::quotestring(currenttitle);
    if(currentclass.size())classstring=" class="s+util::quotestring(currentclass);
    uassert(titlestring.size()+classstring.size()>0,"missing title or class or character in colorize");
    s<< "<span"
     <<titlestring
     <<classstring
     <<'>'
     <<"&#x"<<uchar.getValue()<<';'
     <<"</span>";
  }
  return s.str();
}
	
string readstdin(){
  char c;
  string ret;
  while (std::cin.get(c))
    ret+=c;
  return ret;
}

string ConvertToColorize::span(const string&style, const string& value){
  if(style.empty())return value;
  stringstream s;
  s<<"<span class="
   <<'"'
   <<style
   <<'"'
   <<">"
   <<value
   <<"</span>";
  return s.str();
};

/*these should be in sync witt the switch statement in escapeClass()*/
  
  
string ConvertToColorize::escapeTitle(UChar uchar){
  uassert(uchar.isValid(),"ctcec valid");
  int v=uchar.getValue();
  if(v<128)return "";
  if(v>=(int)UnicodePieces::Start&&v<=(int)UnicodePieces::Last)
    return "";
  switch(v){
  case UnicodeTimes: return "[x]";
  case UnicodeWhitePiece: return "A";
  case UnicodeBlackPiece: return "a";
  case UnicodePiece: return "Aa";
  case UnicodeEmptySquare: return "_";
  case UnicodeGrid: return ".";
  case UnicodeTurnstile: return "path";
  case UnicodeEightPointedStar: return "flip";
  case UnicodeHalfBlackSquare: return "flipcolor";
  case UnicodeHorizontalBar: return "--";
  case UnicodeLE: return "&lt;=";
  case UnicodeGE: return "&gt;=";
  case UnicodeNE: return "!=";
  case UnicodeConcentricCircles: return "focus";
  case UnicodeBullet: return "currentposition";
  case UnicodeRightArrow: return "-&gt;";
  case UnicodeLeftArrow: return "&lt;-";
  case UnicodeUnion: return "|";
  case UnicodeIntersection: return "&amp;";
  case UnicodeForAll: return "[forall]";
  case UnicodeElement: return "[element]";
  case UnicodePrecedes: return "[&lt;]";
  case UnicodeSucceeds: return "[&gt;]";
  case UnicodePrecedesOrEqualTo: return "[&lt;=]";
  case UnicodeSucceedsOrEqualTo: return "[&gt;=]";
  }
  stringstream s;
  s<<"Could not escape title of unknown unicode character with code: "<<v;
  uassert(false,s.str());
  return "";
}

  /* These must all be in perfect sync with the end of basereplacements.map*/
  /* each case should also be in escapeTitle and handle consistently */
  /* these should all be handled in fonts.css */
string ConvertToColorize::escapeClass(UChar uchar){
  uassert(uchar.isValid(),"ctcec valid");
  int v=uchar.getValue();
  if(v<128)return "";
  if(v>=(int)UnicodePieces::Start&&v<=(int)UnicodePieces::Last)
    return "figurine";
  switch(v){
  case UnicodeTimes: return "timesu";
  case UnicodeWhitePiece: return "triangleu";
  case UnicodeBlackPiece: return "triangleu";
  case UnicodePiece: return "triangleu";
  case UnicodeEmptySquare: return "whitesquareu";
  case UnicodeGrid: return "allu";
  case UnicodeTurnstile: return "pathu";
  case UnicodeEightPointedStar: return "flipu";
  case UnicodeHalfBlackSquare: return "flipcoloru";
  case UnicodeHorizontalBar: return "dashu";
  case UnicodeApproximatelyEqual: return "mathu";
  case UnicodeLE: case UnicodeGE: case UnicodeNE: return "mathu";
  case UnicodeConcentricCircles: return "focusu";
  case UnicodeBullet: return "mathu";
  case UnicodeRightArrow:case UnicodeLeftArrow: return "mathu";
  case UnicodeUnion:
  case UnicodeIntersection:
  case UnicodeForAll:
  case UnicodeElement:
  case UnicodePrecedes:
  case UnicodePrecedesOrEqualTo:
  case UnicodeSucceeds:
  case UnicodeSucceedsOrEqualTo:
    return "mathu";
  }
  stringstream s;
  s<<"Could not escape unknown unicode character with code: "
   <<uchar.uname();
  uassert(false,s.str());
  return "";
}
  
    
      
