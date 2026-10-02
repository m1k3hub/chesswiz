#include "anticipatedb.h"
vector<Transform*> AnticipateDb::pawnlessTransforms;
vector<Transform*>AnticipateDb::pawnTransforms;
vector<Transform*>AnticipateDb::idTransforms;
AnticipateDb* AnticipateDb::AnticipateDbP{NULL};
AnticipateDb*AnticipateDb::create(string patternfile,bool isnotransform){
  if(AnticipateDbP!=NULL){
    eassert(AnticipateDbP->theFilename==patternfile,
	    "attempt to use two different predecessor Dbs. This feature is not yet supported.");
    uassert(pawnlessTransforms.size()&&pawnTransforms.size(),"init anticipate transforms");
    eassert(isnotransform==AnticipateDbP->isNoTransform,"notransform specified differently for different invocations of similarposition");
    return AnticipateDbP;
  }
  initializeTransforms();
  AnticipateDbP=new AnticipateDb(patternfile,isnotransform);
  AnticipateDbP->initialize();
  return AnticipateDbP;
}

AnticipateDb::AnticipateDb(string patternfile,bool isnotransform){
  theFilename=patternfile;
  isNoTransform=isnotransform;
  uassert(filename_is_pgn(patternfile),"AnticipateDb: bad pattern filename");
  uassert(!AnticipateDbP,"unexpected AD constructor");
}

/*static*/
void AnticipateDb::initializeTransforms(){
  uassert (pawnlessTransforms.empty()&&
	   pawnTransforms.empty(),
	   "ADiniit initializetransforms");
  pawnlessTransforms=DihedralTransform::allDihedral();
  uassert(pawnlessTransforms.size()==8&&pawnlessTransforms[0]->isIdentity(),"bad dtall adit");
  Transform*fv=DihedralTransform::flipVertical();
  uassert(fv,"adit dt eh?");
  vector<Transform*>shifts=ShiftTransform::shiftHorizontal();
  uassert(shifts.size()==14,"adit bad shifts size");
  pawnTransforms.push_back(pawnlessTransforms[0]);
  for(Transform*t:shifts)pawnTransforms.push_back(t);
  pawnTransforms.push_back(fv);
  idTransforms.push_back(pawnlessTransforms.at(0));
  uassert(idTransforms.size()==1&&idTransforms[0]->isIdentity(),"adit id");
  for(Transform*t:shifts)pawnTransforms.push_back(new ComposeTransform(fv,t));
  uassert(pawnTransforms.size()==30,"bad shfvt in transforms init ad");
}

void AnticipateDb::initialize(){
  uassert (nGames==0,"AD bad game initial");
  uassert(pawnlessTransforms.size(),"adinit transforms not init");
  PgnSource*pgnsource= new PgnSource(theFilename);
  QGame*qgame=new QGame(pgnsource,false); //do not search variations for the time being
  while(qgame->parseNextGame()){
    //    cout<<"Inserting qgame: "<<qgame->getGameNumber()<<endl;
    insertQGame(qgame);
    nGames++;
    uassert(qgame->getGameNumber()==nGames,"AnticipateDb: bad qgame#");
  }
  cout<<"Db: read "<<nGames<< " games from submission file: "<<theFilename<<endl;
  eassert(nGames>0,"Db: unable to read any games from file: ", theFilename);
}

void AnticipateDb::insertQGame(const QGame*qgame){
  uassert(qgame,"AD iqg arg");
  for(const QPos* qpos:qgame->allQPos){
    insertQPos(qpos);
  }
}

void AnticipateDb::insertQPos(const QPos*qpos){
  vector<Transform*>*tp{NULL};
  if(isNoTransform)
    tp= &idTransforms;
  else if(isPawnless(qpos))
    tp= &pawnlessTransforms;
  else
    tp= &pawnTransforms;
  vector<AnticipateEntry>entries=AnticipateEntry::entriesFromQPos(qpos,*tp);
  for(auto& entry:entries)
    insertEntry(entry);
}

void AnticipateDb::insertEntry(const AnticipateEntry& entry){
  string key=entry.key;
  auto entriesp = theMap.find(key);
  if(entriesp==theMap.end()){
    theMap[key]=new vector<AnticipateEntry>{entry};
    return;
  }
vector<AnticipateEntry>&oldentries= *(entriesp->second);
  for(const AnticipateEntry& oldentry:oldentries)
    if (oldentry.gameNumber==entry.gameNumber&&
	oldentry.moveNumber==entry.moveNumber)
	return;
  oldentries.push_back(entry);
}
  
bool AnticipateDb::find(const QPos* qpos)const{
  return theMap.find(AnticipateEntry::computeKey(qpos))!=theMap.end();
}

const vector<AnticipateEntry>& AnticipateDb::lookup(const QPos*qpos)const{
  string key=AnticipateEntry::computeKey(qpos);
  auto PairP=theMap.find(key);
  uassert(PairP!=theMap.end(),"qpos unexpected not found ADl");
  return *(PairP->second);
}
  
/*static*/ 
bool AnticipateDb::isPawnless(const QPos*qpos){
  for(int sq=0;sq<64;++sq)
    if(qpos->board[sq]==WP||
       qpos->board[sq]==BP)return false;
  return true;
}
