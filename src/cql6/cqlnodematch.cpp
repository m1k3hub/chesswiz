#include "node.h"
#include "numericvariable.h"
#include "environment.h"
/*This file has to with matching games and positions from the CQL node*/

void CqlNode::do_match(Node*p,QPos*qpos){
  int x=qpos->markComments();
  NumericVariable*mc=environment->matchCountVariable();
  uassert(mc&&qpos,"do_match no mc");
  if(p->match_position(qpos)){
    mc->increment();
    if(p->annotateFlag&&CqlCommentLevel>=CommentLevel::Normal)
      if(CqlMatchString)
	qpos->appendComment(CqlMatchString);
  }
  else //not matched
    qpos->restoreComments(x);
}

bool CqlNode::match_game(QGame*qgame){
  char buffer[64];
  QPos*root=qgame->root;
  //  MarkBoard::cleanFirstComment(game);
  //These should actually only be output when there is a match. Performance waste otherwise
  sprintf(buffer,"Game number %u",qgame->getGameNumber());
  if(CqlCommentLevel>CommentLevel::Silent&&CqlCommentHeader)root->appendComment(buffer); //Isn't this in setfirst comment??
  nestsClear();
  sortNodesClear();
  consecutiveMovesNodesClear();
  environment->reset();
  NumericVariable*mc=environment->matchCountVariable();
  uassert(mc,"match_game no matchcountvar");
  mc->bindNumeric(0);
  for(GameFilter* gf : gamefilters)
    if(!gf->match_game(qgame))
      /* the change below was made for 9.280 per discussions with Gady. See notes */
      {if (matchCountRange && matchCountRange->valid(0))
	return true;
      else
	return false;}
  for(QPos*current:qgame->allQPos)
    do_match(filter,current);
  int nmatches=(int)(mc->getValue());
  uassert(nmatches==(int)(mc->getValue()),"CqlNode::match_game: nmatches/extremalvalue mismatch");
  bool matched=false;
  if(matchCountRange)
    matched=matchCountRange->valid(nmatches);
  else matched=(nmatches>0);
  if(matched){
    annotateConsecutiveMovesNodes();
    annotateSortNodes();
  }
  return matched;
}
      
