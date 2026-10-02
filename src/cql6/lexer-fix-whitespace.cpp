#include "lexer.h"
#include <stdio.h>
#include "cqlassert.h"
#include "cqlexit.h"
#include <cctype>
#include <sstream>
#include "util.h"

/* handle the whitespace as follows:
   - If the whitespace has a blank line, set the following token to followsBlankLine
   - Otherwise delete it.
The whitespace is handled specially for two reasons:
    (a) to facilitate conversion to and from ascii
    (b) to simplify the base lexing

Handle linecomments as follows:
  If a line comment is seen, set
     SeenLineComment to that token
  each time whitespace is seen, if it contains a blank line, emit EndLineComment and
  set seenlinecomment to null
*/

vector<Token*>Lexer::fixWhiteSpace(const vector<Token*>&tokens){
  vector<Token*>ret;
  int len=(int)(tokens.size());
  bool seenlinecomment{false};
  for(int i=0;i<len;++i){
    Token*token=tokens[i];
    uassert(token,"fws arg");
    LineCommentToken*linecommenttoken=dynamic_cast<LineCommentToken*>(token);
    if(linecommenttoken){
      if(seenlinecomment)
	show_error("multiple line comments on the same line");
      seenlinecomment=true;
      ret.push_back(token);
      continue;
    }
    DashToken*dashtoken=dynamic_cast<DashToken*>(token);
    if(dashtoken&&i>0)
      dashtoken->fixPrevious(tokens[i-1]);
    if(dashtoken&&i<len-1)
      dashtoken->fixNext(tokens[i+1]);
    SpecialToken* specialtoken=dynamic_cast<SpecialToken*>(token);
    if(specialtoken&&
       i>0&&
       tokens[i-1]->isWhiteSpaceToken())
      specialtoken->setFollowsWhitespace();
    WhiteSpaceToken*whitetoken=dynamic_cast<WhiteSpaceToken*>(token);
    if(!whitetoken){
      ret.push_back(token);
      continue;
    }
    if(seenlinecomment&&whitetoken->hasNewline()){
      ret.push_back(new EndLineCommentToken());
      seenlinecomment=false;
    }
    if(whitetoken->hasBlankLine()){
      EndPathToken* endpath=new EndPathToken(whitetoken->CurrentLineNumber,
					     whitetoken->CurrentColumnNumber);
      ret.push_back(endpath);
    }
  }//for i=0 to len
  if(seenlinecomment)
    ret.push_back(new EndLineCommentToken());
  return ret;
}
      
