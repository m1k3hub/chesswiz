#include "node.h"
#include "pgnparse.h"
#include "tokens.h"
#include "numericvariable.h"
#include "environment.h"
#include "assertvariationsnode.h"
#include "lastgamenumbernode.h"

CqlNode::CqlNode(vector<Node*> features,Node*node,Environment*e):
  filter(node), environment(e){
  uassert(filter&&environment,"CqlNode: null parameter");
  filter->annotateFlag=true;

  for(auto feature : features){
    VariationsNode*variationsnode=dynamic_cast<VariationsNode*>(feature);
    if(variationsnode){
      if(!CqlSearchVariationsCommandLineSet)
	CqlSearchVariations=true;
      continue;
    }
  
    PgnNode *pgnnode=dynamic_cast<PgnNode*>(feature);
    if(pgnnode){
      if(CqlPgnStdin) continue;
      eassert(inputfile.empty(),"multiple pgn designators");
      inputfile=pgnnode->value;
      eassert(!inputfile.empty(),"CqlNode: missing input file");
      continue;
    }

    OutputNode* outputnode=dynamic_cast<OutputNode*>(feature);
    if(outputnode){
      if(CqlPgnStdout) continue;
      eassert(outputfile.empty(),"Multiple outputfiles");
      outputfile=outputnode->value;
      eassert(!outputfile.empty(),"CqlNode: missing output file");
      continue;
    }

    MatchCountNode* matchcountnode=dynamic_cast<MatchCountNode*>(feature);
    if(matchcountnode){ //eliminated test for !CqlMatchCountRange for 9.228 per Gamble email 5/19/2020
      eassert(!matchCountRange,"unexpected two matchcount ranges");
      matchCountRange=matchcountnode->range;
      /* This code must be in sync with the sortnode code */
      if(matchcountnode->sort){
	Variable*v=environment->find("matchcount");
	auto nv=dynamic_cast<NumericVariable*>(v);
	if(v)uassert(nv,"matchcount of nonnumeric type: internal");
	if (!nv)
	  nv=environment->createNumericVariable("matchcount");
	uassert(nv,"matchcount creation failed");
	environment->registerSortVariable(nv,SortDirection::Down);
      }
      continue;
    }
    
    GameNumberNode* gamenumbernode=dynamic_cast<GameNumberNode*>(feature);
    if(gamenumbernode){
      uassert(!gamenumberrange,"unexpected two gamenumberranges");
      gamenumberrange=gamenumbernode->range;
      uassert(gamenumberrange,"expected non-null game number range");
      continue;
    }
    
    GameFilter* gamefilter=dynamic_cast<GameFilter*>(feature);
    if(gamefilter){
      gamefilters.push_back(gamefilter);
      continue;
    }
    uassert(false,"cql unknown feature: ",feature->thisclass());
  }
#ifndef CQL6_EMBEDDED // scidb: in embedded mode, input and output files are ignored
  /*Handle the input file*/
  
  if(inputfile.empty()&&CqlPgnFilename&&!CqlPgnStdin)
    inputfile=CqlPgnFilename;
  eassert(inputfile.size()||CqlPgnStdin,
	  "Missing pgn input file: no pgn input file was specified either (a) via 'pgn filname.pgn' in cql file, or (b) via '--input filename.pgn' as a command line argument to 'cql'");
  uassert(inputfile.empty()==CqlPgnStdin,
	  "Internal: nonempty input filename but CqlPgnStdin specified or neither");

  /*Handle the output file*/
  if(outputfile.empty()&&CqlOutputFilename&&!CqlPgnStdout)
    outputfile=CqlOutputFilename;
  if(outputfile.size())
    eassert(filename_is_pgn(outputfile),"Expected pgn extension in output file: ",outputfile);
  if(outputfile.empty()&&CqlFilename&&!CqlPgnStdout)
    outputfile=outputFileFromCqlFile(CqlFilename);
  if(outputfile.size())
    eassert(filename_is_pgn(outputfile),"Expected pgn extension in output file: ",outputfile);
  uassert(outputfile.size()||CqlPgnStdout,"internal: expected output file in cql creation");
  uassert(outputfile.size()&&!CqlPgnStdout
	  ||outputfile.empty()&&CqlPgnStdout,"internal: output file is specified and CqlPgnStdout or neither");
  /*End handle output file*/
#endif
  
  if(CqlGameNumberRange)
    gamenumberrange=CqlGameNumberRange;
  if(CqlPlayer){
    GameFilter*p=Node::createVirtualPlayerNode(CqlPlayer);
    gamefilters.push_back(p);
  }
  if(CqlYearRange){
    YearNode*y=new YearNode(CqlYearRange);
    gamefilters.push_back(y);
  }
  if(CqlMatchCountRange){ //modified for 9.228 to allow the command-line specified matchcount range to override the internally specified one
    matchCountRange=CqlMatchCountRange;
  }
}


string CqlNode::outputFileFromCqlFile(string cqlname){
  uassert(filename_is_cql(cqlname),"outputFileFromCqlFile: not a CQL file");
  string stem=filename_stem(cqlname);
  uassert(!stem.empty(),"bad stem from: ",cqlname);
  return stem+"-out.pgn";
}
  


vnode CqlNode::children()const{
  vnode ret;
  ret.push_back(filter);
  ret.insert(ret.end(),gamefilters.begin(),gamefilters.end());
  return ret;
};

/*after a game is matched, set the header information in the first comment, namely the
  values of all the sortedVariables (whose name encodes the documentation string),
  like "NPieces: 18 NsquaresAttacked: 0"*/
void CqlNode::setFirstComment(QGame*qgame){
  if (CqlCommentLevel==CommentLevel::Silent)return;
  QPos*root=qgame->root;
  stringstream s;
  for(SortVariable* var:*environment->getSortVariables())
    if (!environment->isQuietSortVariable(var)){
      SortDirection dir=environment->getSortDirection(var);
      SortValueType valtype=var->getSortValueType();
      SortValue sortval(valtype,dir);
      var->assignSortValue(&sortval);
      string nameused=SortNode::convertName(var->name);
      string valuestring=sortval.toString();
      s<<' '<<nameused<<": "<<valuestring;
    }
  root->appendComment(s.str());
}

vector<Variable*> CqlNode::getPersistentVariables()const{
  uassert(environment,"cqlnode gpv");
  return environment->getPersistentVariables();
}

bool CqlNode::isQuietPersistentVariable(Variable*v)const{
  uassert(environment,"cqlnode gpv");
  return environment->isQuietPersistentVariable(v);
}

GameSortInfo CqlNode::makeInfo(QGame*qgame){
  vector<SortValue> values;
  for(SortVariable* var : *environment->getSortVariables()){
    SortDirection dir=environment->getSortDirection(var);
    SortValueType vartype=var->getSortValueType();
    SortValue sortvalue(vartype,dir);
    var->assignSortValue(&sortvalue);
    values.push_back(sortvalue);
  }
  string out=util::game_to_string(qgame->game);
  int gamenumber=qgame->getGameNumber();
  return GameSortInfo(out,values,gamenumber);
}

void CqlNode::computeAllSequences(){
  uassert(allSequences.empty(),"createAllSeq");
  for(auto node:descendants()){
    uassert(node,"cqlnode createallsequences");
    SequenceBase*seq=dynamic_cast<SequenceBase*>(node);
    if(seq)allSequences.insert(seq);
  }
}
void CqlNode::computeAllPaths(){
  uassert(allPaths.empty(),"createAllPaths");
  for(auto node:descendants()){
    uassert(node,"cqlnode createallpaths");
    PathNode*path=dynamic_cast<PathNode*>(node);
    if(path)allPaths.insert(path);
  }
}


bool CqlNode::hasLastGameNumber(){
  for(auto node:descendants())
    if(dynamic_cast<LastGameNumberNode*>(node)!=NULL)
      return true;
  return false;
}

bool CqlNode::isSingleThread(){
  for (auto node:descendants()){
    if (dynamic_cast<WriteFileNode*>(node)!=NULL
	|| dynamic_cast<ReadFileNode*>(node)!=NULL)
      return true;
    if(node->isVariable() &&
       node->asVariable()->isPersistent())
      return true;
  }
  return false;
}

void CqlNode::computeAllSortNodes(){
  uassert(allSortNodes.empty(),"computeAllSortNodes");
  for(auto node:descendants()){
    uassert(node,"cqlnode: computeallsortnodes");
    SortNode*sortnode=dynamic_cast<SortNode*>(node);
    if(sortnode)allSortNodes.insert(sortnode);
  }
}

void CqlNode::computeAllConsecutiveMovesNodes(){
  uassert(allConsecutiveMovesNodes.empty(),"createAllConsecutimveMoveNodes");;
  for(auto node:descendants()){
    uassert(node,"cqlnode computeallconsecutivemoves");
    ConsecutiveMovesNode*consecutivemovesnode=dynamic_cast<ConsecutiveMovesNode*>(node);
    if(consecutivemovesnode)allConsecutiveMovesNodes.insert(consecutivemovesnode);
  }
}
  

void CqlNode::consecutiveMovesNodesClear(){
  for (ConsecutiveMovesNode* cmn : allConsecutiveMovesNodes){
    uassert(cmn,"cmnc clear err");
    cmn->clear();
  }
}

void CqlNode::sortNodesClear(){
  for (SortNode* sortnode : allSortNodes){
    uassert(sortnode,"sortnode clear err");
    sortnode->clear();
  }
}

void CqlNode::annotateSortNodes(){
  for(SortNode*sortnode:allSortNodes)
    sortnode->makeComments();
}

void CqlNode::annotateConsecutiveMovesNodes(){
  for(ConsecutiveMovesNode* cmn: allConsecutiveMovesNodes){
    uassert(cmn,"cmnc annotate err");
    cmn->annotate();
  }
}
void CqlNode::nestsClear(){
  for(SequenceBase* seq:allSequences){
    uassert(seq,"nestsclear cql");
    seq->nestClearPositions();
  }
  for(PathNode* path:allPaths){
    uassert(path,"nestsclear cql");
    path->nestClearPositions();
  }

}

CqlNode* CqlNode::create(Tokens& tokens){
  CqlNode* ret=tokens.match_cqlnode();
  if(!ret)return NULL;
  ret->computeOrbit();
  ret->computeAllSequences();
  ret->computeAllPaths(); // same as computeAllSequences but with paths
  ret->computeAllConsecutiveMovesNodes();
  ret->computeAllSortNodes();
  ret->checkAssertVariations();
  ret->completeIsBoundNodes();
  ret->completePathReferenceNodes();
  ret->completeDashOwners();
  if(ret->hasLastGameNumber())LastGameNumberNode::initialize(ret->inputfile,ret->gamenumberrange);
  CqlParseRoot=ret; //leaving this in for SCID but really ought to remove
  return ret;
}

CqlNode* CqlNode::clone(){
  uassert(false,"unexpected clone of CqlNode");
  return NULL;
}

/*for each IsBoundNode, set its theVariable member to the member corresponding
  to its name argument, if it exists*/

void CqlNode::completeIsBoundNodes(){
  for(auto node:descendants()){
    IsBoundNode*isboundnode=dynamic_cast<IsBoundNode*>(node);
    if(isboundnode&&!isboundnode->getVariable()){
      Variable*v=environment->find(isboundnode->getName());
      if(v) isboundnode->setVariable(v);
    }
  }
}
      
/*verify that no AssertVariationsNode if variations is not set. Should be called only on the root node*/
void CqlNode::checkAssertVariations(){
  if(CqlSearchVariations)return;
  for(auto node:descendants()){
    uassert(node,"cqlnode: assertvariations");
    AssertVariationsNode* assertvariationsnode=dynamic_cast<AssertVariationsNode*>(node);
    if (assertvariationsnode)
      eassert(false,assertvariationsnode->getMessage());
  }
}

/******** Fill in PathReferenceNodes ***************/

/* Make each node pathcount, pathstart, pathlastposition point to its containing path.*/

void CqlNode::completePathReferenceNodes(){
  for(auto node:descendants()){
    PathNode*pathnode=dynamic_cast<PathNode*>(node);
    if(pathnode)
      completePathReferenceNodesInPath(pathnode,pathnode);
  }
}

/* Make each descendant of node that is a pathreference node point to pathnode*/

void CqlNode::completePathReferenceNodesInPath(PathNode*pathnode,Node*node){
  PathReferenceNode* pathreference=dynamic_cast<PathReferenceNode*>(node);
  if (pathreference){
    uassert(!pathreference->getPath(),"clrnil seq internal");
    pathreference->setPath(pathnode);
  }
  for(auto child:node->children())
    if (!child->isPathNode()) //do not follow into another path filter. 
      completePathReferenceNodesInPath(pathnode,child);
}

/***************Fill in the FromNode with pointers to masks from their owning DashNode or DashCon*/
/*These make sure each FromNode and ToNode (that is, a FromToNode) point to their owners, if any (by setting
  the from and to masks, which are used for accurate castling from/to values).
  Such an owner owns a FromToNode if the owned is
  a descendant of the owner (i.e., a target)
  but is not a descendant of a WithPositionNode that is itself a descendant of
  the owner. The structure of these two methods is similar to the pathreference node handling.
*/

void CqlNode::completeDashOwners(){
  for(auto node:descendants()){
    DashNode*dashnode=dynamic_cast<DashNode*>(node);
    DashCon*dashcon=dynamic_cast<DashCon*>(node);
    if(dashnode&&dashnode->getTarget())
      completeDashOwnersFromNode(node,dashnode->getTarget());
    else if(dashcon)
      completeDashOwnersFromNode(node,dashcon->getTarget());
  }
}

/*given a DashOwner owner and a node ownedcandidate, set recursively all FromToNodes in current
   to point to owner, given that:
     - an ownedcandidate for which canModifyCurpos() is true, (e.g. sort, path, capture, withposition, dash) is skipped
       even if the ownedcadidate contains a to in it, if inside some dash arrow it will be hit by that arrow
     - Consider a dasher node D
       X--Y XX--YY

      Here, X and Y are not set to be owned by D, but XX and YY are set to be owned by D.
*/

void CqlNode::completeDashOwnersFromNode(Node*owner, Node*ownedcandidate){
  uassert(owner&&owner->isFromToOwner(),"cqlnode cdofn owner");
  if(!ownedcandidate)return;
  if(ownedcandidate->canModifyCurpos())return;
  FromToNode* owned=dynamic_cast<FromToNode*>(ownedcandidate);
  if(owned){
    owned->setOwner(owner);
    return;
  }
  for(Node*child:ownedcandidate->children())
    completeDashOwnersFromNode(owner,child);
}
  
