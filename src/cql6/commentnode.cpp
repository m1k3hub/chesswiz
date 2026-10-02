#include "commentnode.h"
/* this handles CQL-generated comments and messages. The second
   constructor arg is true if it is a message. match_position() just
   invokes the convert(QPos*) method of the StringConverter argument
*/

CommentNode::CommentNode(StringConverter* c, bool ismessage, bool isquiet):
  theConverter(c),
  theIsMessage(ismessage),
  theIsQuiet(isquiet)
{
  uassert(theConverter,"cnn arg");
  uassert(!(isquiet && !ismessage),"commentnode quiet");
}

vnode CommentNode::children()const{
  return vnode{(Node*)theConverter};
}

void CommentNode::deepify(){
  theConverter=theConverter->clone();
}

bool CommentNode::match_position(QPos*qpos){
  string result=theConverter->convert(qpos);
  if(theIsMessage){
    int gamenumber=qpos->qgame->getGameNumber();
    if (!theIsQuiet)
      printf("Game: %d %s: %s\n",
	     gamenumber,
	     qpos->idString().c_str(),
	     result.c_str());
    else // theIsQuiet
      printf("%s\n",result.c_str());

    /*new test for CqlGui that respects isQuiet, from a patch by
      by Lionel, 9/24/2023 */
    if(CqlGui&&!theIsQuiet)
      printf("%s Game: %d %s: %s %s\n",
	            CqlGuiMessageStart,
	            gamenumber,
	            qpos->idString().c_str(),
	            result.c_str(),
	            CqlGuiMessageStop);
    else if(CqlGui&&theIsQuiet)
      printf("%s %s %s\n",
	     CqlGuiMessageStart,
	     result.c_str(),
	     CqlGuiMessageStop);
    /* end of CqlGui isQuiet test */
    uassert(theIsMessage,"internal message gui brace");
  } //if (theIsMessage)
  else
    qpos->appendComment(result);
  return true;
}
  
    
