#include "lexer.h"
#include <stdio.h>
#include "cqlassert.h"
#include "cqlexit.h"
#include <ctype.h>
#include <sstream>
#include "util.h"
#include "uchar.h"

/*handle matching unicode pieces of which there are the following:
   Figurines, in enum class UnicodePieces (K,R,...p);
   UnicodeWhitePiece
   UnicodeBlackPiece
   UnicodePiece
   UnicodeEmptySquare

The UnicodeGrid for the dot equivalent is not considered an unicode piece or square specifier
for now.
These pieces differ from their ASCII equivalents in that
   - there is no ascii equivalent to UnicodePiece, and
   - multiple such need not be enclosed in []
*/

/*return single ascii char of a utf-8 figurine piece, a white piece, a
  black piece, or an empty square. Do not match (return 0) for the Unicode piece*/

char Lexer::charFromUnicodePieceSpecifier(UChar u){
  uassert(u.isValid(),"lexer bad uchar in cfups");
  int v=u.getValue();
  switch(v){
  case (int)UnicodePieces::K: return 'K';
  case (int)UnicodePieces::Q: return 'Q';
  case (int)UnicodePieces::R: return 'R';
  case (int)UnicodePieces::B: return 'B';
  case (int)UnicodePieces::N: return 'N';
  case (int)UnicodePieces::P: return 'P';
  case (int)UnicodePieces::k: return 'k';
  case (int)UnicodePieces::q: return 'q';
  case (int)UnicodePieces::r: return 'r';
  case (int)UnicodePieces::b: return 'b';
  case (int)UnicodePieces::n: return 'n';
  case (int)UnicodePieces::p: return 'p';
  case UnicodeWhitePiece: return 'A';
  case UnicodeBlackPiece: return 'a';
  case UnicodeEmptySquare: return '_';
  };
  return (char)0;
}

/*match a single unicode character representing a piece
specifier. This may be a figurine piece, a WhitePiece, a BlackPiece,
an empty square, or a UnicodePiece.  UnicodePiece corresponds to the
two tokens corresponding to 'a' and 'A'.  The others correspond to a
single ASCII character, RBNQKPrbnqkpAa_
*/


vector<PieceToken*>Lexer::match_singleunicodepiecespecifier(){
  int x=save();
  const vector<PieceToken*> retnull;
  UChar u = match_uchar();
  if(u.isInvalid())return retnull;
  char c = charFromUnicodePieceSpecifier(u);
  if(c!=0)
    return vector<PieceToken*>{new PieceToken(c)};
  if(u.getValue()==UnicodePiece)
    return vector<PieceToken*>{
      new PieceToken('A'),
	new PieceToken('a')};
  restore(x);
  return retnull;
}

vector<PieceToken*>Lexer::match_unicodepiecespecifier(){
  int x=save();
  bool seenbracket{false};
  if(match_char('['))
    seenbracket=true;
  vector<PieceToken*>ret;
  while(true){
    vector<PieceToken*>thispiece=match_singleunicodepiecespecifier();
    if(thispiece.size()==0)break;
    if(thispiece.size()==1)
      ret.push_back(thispiece.front());
    else if(thispiece.size()==2){
      ret.push_back(thispiece.front());
      ret.push_back(thispiece.back());
    }//thispiece.size()==2
    else
      show_error("unexpected apparent unicodepiece in lexer; internal error");
  }//while(true);
  if(seenbracket&&!match_char(']')){
    restore(x);
    return vector<PieceToken*>();
  }
  if(ret.empty()){
    restore(x);
    return ret;
  }
  for (size_t i =0;i<ret.size();++i)
    for(size_t j=i+1;j<ret.size();++j)
      if(ret[i]->value==ret[j]->value){
	stringstream s;
	s<<"Duplicate piece types in apparent piece designator: "<<ret[i]->value;
	show_error(s.str());
      }
  return ret;
}


