#include "util.h"
#include "cql.h"
#include "markboard.h"
#include "cqlglobals.h"
#include <map>

int  MarkBoard::number_children(Game*game, bool searchvariations){
  int nseen=0;
  bool currentatend=game->AtVarEnd();
  if (!currentatend)++nseen;
  if(searchvariations){
    int numvars=game->GetNumVariations();
    // This code assumes that a variation will never be at its own varend.
    nseen+=numvars;
  }
  return nseen;
}

pieceT MarkBoard::piece_at_square(squareT square, Game*game){
  uassert(square_valid(square), "internal piece_at_square");
  pieceT p= game->GetCurrentPos()->GetBoard()[square];
  uassert(piece_valid(p),"pieceatsquare pv");
  return p;
}
    
moveT* MarkBoard::identity(Game*game){
  return game->CurrentMove;
}

simpleMoveT* MarkBoard::getCurrentMove(Game*game){
  uassert(!atVarEnd(game),
	  "Attempt to get a move where there are none to be had"
	  );
  simpleMoveT* s=game->GetCurrentMove();
  uassert(s,"expecting non-null move");
  return s;
}



void MarkBoard::move_to_child(Game*game, int child){
  bool hasmainline= !atVarEnd(game);
  if(hasmainline&& child==0){
    gameForward(game);
    return;
  }
  int variationnumber=child;
  if(hasmainline) variationnumber--;
  uassert(variationnumber>=0 && variationnumber<game->GetNumVariations(),"varnumgnv");
  MoveIntoVariation(game,variationnumber);
  gameForward(game);
}


bool MarkBoard::inMainline(Game*game){
  return game->GetVarLevel()==0;
}

bool MarkBoard::inVariation(Game*game){
  return game->GetVarLevel()>0;
}

bool MarkBoard::atVarEnd(Game*game){
  return game->AtVarEnd();
}

bool MarkBoard::atVarStart(Game*game){
  return game->AtVarStart();
}

int MarkBoard::getCurrentPly(Game*game){
  return (int)(game->GetCurrentPly());
}

bool MarkBoard::isInitial(Game*game){
  return getCurrentPly(game)==0;
}

bool MarkBoard::isTerminal(Game*game){
  return atVarEnd(game);
}

void MarkBoard::MoveIntoVariation(Game*game, int i){
  if(game->MoveIntoVariation(i))
    uassert(false,"Move Into Variation error");
}

void MarkBoard::gameForward(Game*g){
  bool r=g->MoveForward(); //technically this is an errorT but it is typedefed as unsigned short and 0 is ok
  if(r){                   //error
    stringstream s; //this message added for 6.1 at build 9.244 per Gamble and Yves. CQL
                    //could give hard to track down errors on files with empty variations or
                    //illegal moves simulating these (Z0 for Yves case 12/26/2020 by Stiller
    s<<"Possible invalid pgn file detected (gameforward fail error 1) at game number: "
     <<g->GetNumber()
     <<"\n(You might find this message easier to read if you run CQL with the -s option for single-threaded)"
     <<"\nPlease contact authors if PGN file was generated from a major program or seems to be a widespread database or if file seems fine to you"
     <<endl;
    uassert(false,s.str());
  }
}

void MarkBoard::gameBackup(Game*g){
  g->MoveBackup();
  if(atVarStart(g)&&inVariation(g))
    g->MoveExitVariation();
  uassert(inMainline(g) || !atVarStart(g),"gameBackup internal");
}

void MarkBoard::gameMoveToPly(Game*g, int ply){ //ply must be 0
  uassert(ply==0,"movetoplay 0");
  g->MoveToPly(0);
}
    
  
void MarkBoard::make_move(simpleMoveT*move,Game*game){
  if(move==game->GetCurrentMove())
    {gameForward(game);return;}
  for(int varnumber=0;varnumber<game->GetNumVariations();++varnumber){
    MoveIntoVariation(game,varnumber);
    if(move==game->GetCurrentMove()){
      gameForward(game);
      return;
    }
    else
      game->MoveExitVariation();
  }
  uassert(false,"move not found in make_move");
}


void MarkBoard::gameToIdentity(moveT* myid, Game*game,bool variations){
  gameMoveToPly(game,0);
  if(gameSeekIdDescendants(myid,game,variations))
    return;
  else uassert(false,"id not found gametoid",myid->san);
}

void MarkBoard::gameToChild(moveT*childid,Game*game, bool variations){
  int nchildren=MarkBoard::number_children(game,variations);
  uassert(nchildren,"No children in gameToChild");
  for (int child=0;child<nchildren;++child){
    move_to_child(game,child);
    if (identity(game)==childid) return;
    else gameBackup(game);
  }
  uassert(false,"gametochild: id not found");
}

bool MarkBoard::gameSeekIdDescendants(moveT*myid, Game*game, bool vars){
  if(identity(game)==myid) return true;
  int nchildren=MarkBoard::number_children(game, vars);
  for(int child=0;child<nchildren;++child){
    move_to_child(game,child);
    if(gameSeekIdDescendants(myid,game,vars)) return true;
    else MarkBoard::gameBackup(game);
  }
  return false;
}
  
void MarkBoard::gameDeleteComment(Game*game){
  if (game->GetMoveComment())
    game->SetMoveComment(NULL);
}

void MarkBoard::gameAppendComment(Game*game, string commentstring){
  if(commentstring.empty())return;
  char buffer[5000];
  char*current=buffer;
  current[0]=0;
  const char*oldcomment=game->GetMoveComment();
  int oldcommentsize=0;
  if(oldcomment)
    oldcommentsize=strlen(oldcomment);
  if(oldcommentsize+commentstring.size()>4500){
    printf("\nIgnoring long comment in game: %d\n",game->GetNumber());
      return;
  }
  if(oldcommentsize)
    current+=sprintf(current,"%s",oldcomment);
  uassert(*current==0,"gAC current null");
  sprintf(current,"%s",commentstring.c_str());
  cleanCommentBuffer(buffer);
  game->SetMoveComment(buffer);
}

void MarkBoard::cleanCommentBuffer(char* buffer){
  unsigned char* current=(unsigned char*)buffer;
  while(true){
    unsigned char c=*current;
    if (c==0)return;
    else if (c=='{'||c=='}')
      *current='_';
    else if (c>=127)
      *current='?';
    ++current;
  }
}
    
	
      
vector<simpleMoveT*> MarkBoard::getMoves(Game*game,bool searchvars){
  vector<simpleMoveT*> moves;
  if(!atVarEnd(game))
    moves.push_back(getCurrentMove(game));
  if(!searchvars) return moves;
  for(int varnum=0;varnum<game->GetNumVariations();++varnum){
    MoveIntoVariation(game,varnum);
    uassert(!atVarEnd(game),"get_moves end of var in var");
    moves.push_back(getCurrentMove(game));
    uassert(!game->MoveExitVariation(),"getMoves exitvar");
  }
  int nm=(int)(moves.size());
  for(int i=0;i<nm;++i)
    for(int j=i+1;j<nm;++j)
      uassert(moves[i]!=moves[j],"get_moves internal");
  return moves;
}
  
vector<simpleMoveT*> MarkBoard::getLegalMoves(Game*game){
  uassert(false,"getLegalMoves is not implemented");
  static int gamenumber=0; //ignore non-reentrancy as not called
  static std::map<moveT*,vector<simpleMoveT*>> legalmap; //ignore non-reentrancy as not called
  if(game->GetNumber()!=gamenumber){
    gamenumber=game->GetNumber();
    legalmap.clear();
  }
  moveT* me=identity(game);
  if(legalmap.find(me)==legalmap.end()){
    Position*position=game->GetCurrentPos();
    position->GenerateMoves();
    MoveList* movelist=position->GetLegalMoves();
    uassert(movelist,"getLegalMoves");
    vector<simpleMoveT*> movevec;
    for(unsigned int i=0;i<movelist->Size();++i)
      movevec.push_back(movelist->Get(i));
    legalmap[me]=movevec;
  }
  uassert(legalmap.find(me)!=legalmap.end(),"genmoves unknonwn");
  return legalmap[me];
}
  
string MarkBoard::getEvent(Game*game){
  uassert(game,"event internal");
  char* event=game->GetEventStr();
  if (event)
    return string(event);
  return "";
}

string MarkBoard::getSite(Game*game){
  uassert(game,"getSite internal");
  char* site=game->GetSiteStr();
  if (site)
    return string(site);
  return "";
}

vector<int>MarkBoard::getNags(Game*game){
  vector<int>ret;
  uassert(game,"mbnag internal");
  if (isInitial(game))return ret;
  byte* nags=game->GetNags();
  if(nags==NULL)return ret;
  int num=0;
  for(byte* pnag=nags;*pnag;++pnag){
    ret.push_back(*pnag);
    ++num; // should be less than MAX_NAGS, which is 8 currently in orig/game.h
    uassert(num<=8,"Too many NAGs in game");
    uassert(ret.back()>0,"Unexpected negative NAG value");
  }
  return ret;
}

string MarkBoard::getComment(Game*game){
  uassert(game,"mbgc internal");
  string ret;
  char* comment=game->GetMoveComment();
  if(comment) ret=comment;
  return ret;
}

string MarkBoard::getPlayer(Game*game,colorT color){
  uassert(game,"gpg njll");
  char*name=NULL;
  if(color==WHITE)
    name=game->GetWhiteStr();
  else if (color==BLACK)
    name=game->GetBlackStr();
  else uassert(false,"getPlayer: illegal color");
  if (!name)return "";
  return name;
}

bool MarkBoard::check(Game*game){
  Position*pos=game->GetCurrentPos();
  return pos->myIsKingInCheck();
}
bool MarkBoard::mate(Game*game){
  Position*pos=game->GetCurrentPos();
  return pos->myIsKingInMate();
}
bool MarkBoard::stalemate(Game*game){
  Position*pos=game->GetCurrentPos();
  return pos->myIsKingInStalemate();
}

simpleMoveT* MarkBoard::getPreviousMove(Game*game){
  uassert(!isInitial(game),"markboard previousMove at initial");
  moveT*prev=game->CurrentMove->prev;
  uassert(prev&&prev->marker!=START_MARKER,"previousMove start");
  return &(prev->moveData);
}

pieceT* MarkBoard::getBoard(Game*game){
  uassert(game,"mgb intenral");
  pieceT* ret= game->GetCurrentPos()->GetBoard();
  uassert(ret,"mgb ret");
  return ret;
}

colorT MarkBoard::getToMove(Game*game){
  uassert(game,"mbgtm arg");
  colorT ret=game->GetCurrentPos()->GetToMove();
  uassert(ret==WHITE||ret==BLACK,"mbgtm ret");
  return ret;
}

int MarkBoard::getNumber(Game*game){
  return game->GetNumber();
}

string MarkBoard::getECO(Game*game){
  const int buffsize=50;
  char buffer[buffsize]; // too big really
  for (int i=0;i<buffsize;++i)
    buffer[i]=0;
  eco_ToString(game->GetEco(), buffer);
  uassert(buffer[buffsize-1]==0,"getECO bad buffer 1");
  string ret{buffer};
  return ret;
}

/* keep in sync with getEventDate()!*/
string MarkBoard::getDate(Game*game){
  const int buffsize=13;
  char buffer[buffsize]; //too big really
  for (int i=0;i<buffsize;++i)
    buffer[i]=0;
  date_DecodeToString(game->GetDate(),buffer);
  uassert(buffer[buffsize-1]==0,"MarkBoard::getDate::bad buffer!");
  string ret{buffer};
  uassert(ret.size()==10, "MarkBoard::getDate: bad date"); //yyyy.mm.dd
  return ret;
}

/*  keep in sync with getDate() ! */
string MarkBoard::getEventDate(Game*game){
  const int buffsize=13;
  char buffer[buffsize]; //too big really
  for (int i=0;i<buffsize;++i)
    buffer[i]=0;
  date_DecodeToString(game->GetEventDate(),buffer);
  uassert(buffer[buffsize-1]==0,"MarkBoard::getEventDate::bad buffer!");
  string ret{buffer};
  uassert(ret.size()==10, "MarkBoard::getEventDate: bad event date"); //yyyy.mm.dd
  return ret;
}

int MarkBoard::getYear(Game*game){
  return (int)(date_GetYear(game->GetDate()));
}

int MarkBoard::getElo(Game*game, colorT color){
   if(color==WHITE)return game->GetWhiteElo();
  else if (color==BLACK)return game->GetBlackElo();
  uassert(false,"getelo bad color");
  return 0;
}

resultT MarkBoard::getResult(Game*game){
  return game->GetResult();
}

string MarkBoard::getStartFen(Game*game){
  if (!game->HasNonStandardStart())
    return "";
  char fenstr[256]; // following orig/game.cpp line 2287
  game->GetStartPos()->PrintFEN(fenstr,FEN_ALL_FIELDS);
  return string(fenstr);
}

void MarkBoard::setNonstandardTag(Game*game, const string&name, const string& value){
  game->AddPgnTag(name.c_str(),value.c_str());
}
