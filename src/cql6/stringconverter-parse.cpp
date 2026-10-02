#include "node.h"
#include "tokens.h"
#include "stringconverter.h"
#include "commentnode.h"

Node* Tokens::match_stringconverter(){
  bool ismessage=false;
  bool iscomment=false;
  bool isstring=false;
  bool isquiet=false;
  bool islinecomment=false;
  if(match_keywords("message", "quiet")){
    ismessage=true;
    isquiet=true;}
  else if(match_keyword("comment"))
    iscomment=true;
  else if (match_keyword("message"))
    ismessage=true;
  else if (match_keyword("str"))
    isstring=true;
  else if (match_linecomment())
    islinecomment=true;
  else return NULL;
  uassert (ismessage+iscomment+isstring+islinecomment==1,"msc internal");
  uassert(!(isquiet && !ismessage),"msc quiet internal");
  vector<Node*>nodes;
  if (!islinecomment&&!match_lparen()){
    Node*node=match_strconstituent();
    if(!node)
      show_error ("cannot parse 'comment/message/string' filter: expected a filter or parenthesized list of filters following 'comment', 'message', or 'str'");
    nodes.push_back(node);
  }
  else{ // matched the lparen or a linecomment
    while (true){
      Node*node=match_strconstituent();
      if (!node)break;
      nodes.push_back(node);
    }
    if(nodes.empty())
      show_error("empty list of items followed 'comment', 'message', '///' or 'str' ");
    if (!islinecomment&&!match_rparen())
      show_error("Could not parse 'comment', 'message', or 'str': could not find terminating ')' of list of arguments");
    if(islinecomment && !match_endlinecomment())
      show_error("could not detect end of apparent '///' comment. This is likely due to an invalid filter after the '///'. Use '///' as follows, e.g:  /// \"arg1\" x arg2...");
  }//if (!match_lparen...else )
  uassert(nodes.size()>0,"Parse of comment/message/to_string: internal parse error A39");
  StringConverter* converter=new StringConverter(nodes);
  if (ismessage||iscomment||islinecomment)
    return new CommentNode(converter,ismessage,isquiet);
  else return converter;
}

/*Handle argument to str specially in two cases:
  1. fen. Always parse as CurrentFen(). Ignore any trailing quoted string.
  2. A StringInNode with isImplicit set. This corresponds to an implicit search parameter, like
  player white "Gady"
  event "foo"
  hhdb composer "Reti"
  This is parsed as the target of the InNode (since 9.361). However, the token stream
  is restored to the value of InNode::implicitParameterIndex. Effectively,
  the implicit parameter is unread from the token stream.
  This fixes anomalies where say
  str("Event is: " event " and site: " site)
  or
  str (fen \n)
  Now these two cases should work as expected.
*/
Node*Tokens::match_strconstituent(){
  /* handle fen. 
     If we see a fen of the form
     fen  "..."
     then parse the fen as (fen) and move on.
     If we see anything else after the fen, then parse the
     whole fen normally as a node. 
     
     The purpose of this rigmarole is to handle these correctly:
     str(fen " is good")
     str (fen + Something()==x)
     str (fen "xxx" + y())
  */
  int x=save(); 
  if (match_keyword("fen") &&
      dynamic_cast<QuotedStringToken*>(current())!=NULL)
    return new CurrentFen();
  else restore(x);
  /* done the special case fen handling*/
  Node*node=match_node();
  if(node==NULL)return NULL;
  if(node->removedParens)return node;
  StringInNode* innode=dynamic_cast<StringInNode*>(node);
  if (!innode || !innode->isImplicit)
    return node;

  /*now we have an implicit search parameter encoded in innode.
    Handle this by rewinding to unread the literal parameter*/
  
  int paramStart=innode->implicitParameterIndex; //location of start of implicit parameter
  uassert(paramStart>x,"implicit parameter location error in str parse"); // should be after target node was read
  uassert(paramStart<save(),"implicit parameter location error: lost location"); //current position should be after paramStart, since paramStart should have been read already
  Node*target=innode->theRight->clone(); //make a new target node to return
  uassert(target->isString(),"match_strconstituent: innode right not a string");
  Node*pattern=innode->theLeft;//the implicit search parameter as a node
  /* reread the pattern to make sure we are in sync here*/
  StringLiteralNode*patternliteral=dynamic_cast<StringLiteralNode*>(pattern);
  uassert(patternliteral, "match_strconstituent: expected a stringliteral node in the pattern for implicit search here");
  string patternstring=patternliteral->theName; //the actual implicit parameter as a string
  restore(paramStart);
  string teststring; //the quoted string in the input, we hope - to be reread
  uassert(match_quotedstringvalue(&teststring),"implicit parameter parse string mismatch"); //reread quoted string
  uassert(teststring==patternstring,"implicit parameter string mismatch"); //should be same as patternstring
  restore(paramStart); //and restore paramStart once again
  return target; //now return the target. The implicit parameter is unread 
}
 
