#include "anticipatenode.h"
AnticipateNode::AnticipateNode(string patternfile,NumericVariable*minremoteqgamevar,bool isnotransform):
  patternFile(patternfile),
  minRemoteQGameVar(minremoteqgamevar),
  isNoTransform(isnotransform)
{
  uassert(minRemoteQGameVar,"missing minRemoteQGameVar an");
  theDb=AnticipateDb::create(patternFile,isNoTransform);
}

bool AnticipateNode::match_position(QPos*qpos){
  if (!theDb->find(qpos)) return false;
  const vector<AnticipateEntry>& result=theDb->lookup(qpos);
  uassert(result.size()>0,"ANmp no result");
  stringstream s;
  for(const AnticipateEntry& ae:result){
    s<<"see "<<patternFile<< " game: "
     <<ae.gameNumber
     << " at move: "
     << ae.moveNumber;
    if(ae.sideToMove==WHITE)
      s<<" wtm ";
    else
      s<<" btm ";
    if(!ae.theTransform->isIdentity())
      s<<ae.theTransform->toString();
    updateMinRemoteQGame(ae.gameNumber);
    qpos->appendComment(s.str());
  }
  return true;
}

void AnticipateNode::updateMinRemoteQGame(int qgame){
  uassert(qgame>0,"an umrqg");
  if(minRemoteQGameVar->isUnbound())
    minRemoteQGameVar->bindNumeric(qgame);
  else
    minRemoteQGameVar->bindNumeric(std::min(qgame,
					    minRemoteQGameVar->getValue()));
}

  
void AnticipateNode::deepify(){
  eassert(false,"Attempt to apply a transform to anticipate node. This operation is not supported at this time");
};

    
