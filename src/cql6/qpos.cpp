#include "qpos.h"
#include <cctype>
#include "markboard.h"
#include "cqlglobals.h"
#include "qgame.h"
//return a new QPos including the descendants (static)
void QPos::clear(){
  for (auto&mask:thePieceMasks)mask.clear();
  for(auto&cmask:theColorMasks)cmask.clear();
  for(auto&p:board) p=EMPTY;
  index= -1;
  lastDescendantIndex= -1;
  toMove=NOCOLOR;
  id=NULL;
  originalComment.clear();
  nags.clear();
  addedComments.clear();
  identificationComment.clear();
  deleteOriginalComment=false;
  children.clear();
  new(&previousMove)QMove();
  moves.clear();
  theIsCheck=false;
  theIsStalemate=false;
  theIsMate=false;
  parent=NULL;
  thePly= -1;
  qgame=NULL;
}
  
QPos* QPos::createRoot(QGame*qgame,bool variations){
  uassert(qgame,"createRoot args");
  QPos*root=createQPos(qgame);
  root->thePly=0;
  root->initializeMarks();
  return root;
}

QPos* QPos::createFromParent(QPos*parent, int childindex, bool variations){
  uassert(parent&&childindex>=0&&childindex==parent->nChildren(),"qpos cfp args");
  QGame*qgame=parent->qgame; // but points to the child game position
  QPos*child=createQPos(qgame);
  child->parent=parent;
  child->previousMove=QMove(qgame->game,parent->board);
  child->previousMove.head=parent;
  child->previousMove.tail=child;
  uassert(child->thePly<0&&parent->thePly>=0,"createFromParent: plies");
  child->thePly=parent->thePly+1;
  child->previousMove.index=childindex;
  parent->children.push_back(child);
  parent->moves.push_back(&child->previousMove);
  uassert(parent->children.size()-1==(size_t)childindex &&
	  parent->moves.size()-1==(size_t)childindex,"qpos cfp sizes");
  child->setMarks();
  return child;
}

//setMarks is called after all other fields of a child of parent QPos have been set.
//It uses the parent and the previousMove to set the marks
void QPos::setMarks(){
  uassert(parent,"setMarks arg");
  for(int i=0;i<64;++i)squares_to_marks[i]=parent->squares_to_marks[i];
  for(int i=0;i<32;++i)marks_to_squares[i]=parent->marks_to_squares[i];
  marks_make_move(squares_to_marks,
		  marks_to_squares,
		  previousMove.from,
		  previousMove.to,
		  parent->board,
		  parent->toMove
		  );
}

//this sets the board, pieceMasks, tomove, originalcomment, nags, id field, states (mate, stalemate, check)
//but not the parent, previousmove, or children


void QPos::initializeMarks(){
  markT nextmark{0};
  for(markT& m : squares_to_marks) m.makeInvalid();
  for(squareT& s : marks_to_squares) s=65;
  for (int sq=0;sq<64;++sq)
    if (board[sq]!=EMPTY){
      uassert(nextmark.isValid(),"qpos setasroot nmarks");
      squares_to_marks[sq]=nextmark;
      marks_to_squares[nextmark.getValue()]=sq;
      nextmark.inc();
    }
    else // square is empty
      squares_to_marks[sq].makeInvalid();
}


//static method copied from MarkBoardMap::make_move();
void QPos::marks_make_move(markT* squares_to_marks,
		       squareT* marks_to_squares,
		       squareT fromsquare,
		       squareT tosquare,
		       const pieceT* board,
		       colorT color
		       ){
  uassert(square_valid(fromsquare)&&square_valid(tosquare)&&color_valid(color),"updatemarks args");
  pieceT ptype=piece_Type(board[fromsquare]);
  if(fromsquare==tosquare){
    uassert(ptype==KING,"expecting a king on the null move from square updatemarks");
    return;
  }

  markT frommark=squares_to_marks[fromsquare];
  uassert(frommark.isValid(),"bad from mark");

  bool ep=(ptype==PAWN)&&board[tosquare]==EMPTY&&(square_Fyle(fromsquare)!=square_Fyle(tosquare));
  if (ep){
    int capturedsquare=(color==WHITE) ? (tosquare-8) : (tosquare+8);
    uassert(square_valid(capturedsquare),"map mark pawn bad");
    uassert(piece_Type(board[capturedsquare])==PAWN,"MB make move not a pawn");
    markT capturedpawn=squares_to_marks[capturedsquare];
    uassert(capturedpawn.isValid(),"MB make move invalid captured pawn");
    marks_to_squares[capturedpawn.getValue()]=65;
    squares_to_marks[capturedsquare].makeInvalid();
  }
  else if (ptype==KING && square_Fyle(fromsquare)==E_FYLE&&
	   (square_Fyle(tosquare)==C_FYLE||square_Fyle(tosquare)==G_FYLE)){
    int rookfromsquare,rooktosquare;

    if(square_Fyle(tosquare)==C_FYLE){
      rookfromsquare=tosquare-2;
      rooktosquare=tosquare+1;
    }
    else{
      rookfromsquare=tosquare+1;
      rooktosquare=tosquare-1;
    }
    uassert(rookfromsquare!=rooktosquare&&
	    square_valid(rookfromsquare)&&
	    square_valid(rooktosquare),
	    "mark makemove bad rook");
    markT rookfrommark=squares_to_marks[rookfromsquare];
    uassert(rookfrommark.isValid(),"mvrfrommark internal");
    squares_to_marks[rooktosquare]=rookfrommark;
    squares_to_marks[rookfromsquare].makeInvalid();
    marks_to_squares[rookfrommark.getValue()]=rooktosquare;
  }
	  //handle the general case
  markT capturedmark=squares_to_marks[tosquare];
  if(capturedmark.isValid()){
    uassert(board[tosquare]!=EMPTY,"capturedmark empty");
    marks_to_squares[capturedmark.getValue()]=-1;
    };
  markT movingmark=squares_to_marks[fromsquare];
  uassert(movingmark.isValid(),"movingmark nonempty");
  squares_to_marks[tosquare]=movingmark;
  squares_to_marks[fromsquare].makeInvalid();
  marks_to_squares[movingmark.getValue()]=tosquare;
}    // updateMarks

vector<QPos*>QPos::getDescendants(){
  vector<QPos*>ret;
  ret.push_back(this);
  for(QPos*child:children){
    vector<QPos*>childret=child->getDescendants();
    for(auto cr:childret)ret.push_back(cr);
  }
  return ret;
}

void QPos::verifyDescendants(){
  Game*game=getGame();
  verify();
  for(int childi=0;childi<nChildren();++childi){
    QPos*child=children[childi];
    MarkBoard::move_to_child(game,childi);
    child->verifyDescendants();
    MarkBoard::gameBackup(game);
  }
}

void QPos::verify(){
  uassert(qgame&&qgame->game,"verify no game");
  Game*game=qgame->game;
  uassert(id==MarkBoard::identity(game),"verify id");
  pieceT*gboard=MarkBoard::getBoard(game);
  colorT gcolor=MarkBoard::getToMove(game);
  uassert(toMove==gcolor,"qpos verify color");
  for(int i=0;i<64;++i)
    uassert(board[i]==gboard[i],"qpos verify boardcheck");
  uassert(nChildren()==MarkBoard::number_children(game,CqlSearchVariations),"qpos verify children");
  uassert(initial()==MarkBoard::isInitial(game),"verify initial");
  if(parent){
    uassert(previousMove.valid,"verify valid previousmove");
    auto gameprevious=MarkBoard::getPreviousMove(game);
    uassert(previousMove.from==gameprevious->from&&
	    previousMove.to==gameprevious->to,"verify previous");
    auto parentchildren=parent->children;
    uassert(myindex(parentchildren,this)==previousMove.index,"verify parent/child");
  }
  for(auto child:children)uassert(child,"verify null child");
  uassert(check()==MarkBoard::check(game)&&
	  mate()==MarkBoard::mate(game)&&
	  stalemate()==MarkBoard::stalemate(game),"verify check/mate/stalemate");
  //verifying the markboard, copied from markboardmap
    int marksseen=0;
  for (int square=0;square<64;++square){
    markT mark=squares_to_marks[square];
    pieceT piece=board[square];
    if(mark.isInvalid()) {
      uassert(piece==EMPTY,"verify no mark on nonempty");
      continue;}
    uassert(piece!=EMPTY,"verify mark on empty");
    uassert(mark.isValid(),"verify bad mark");
    uassert(marks_to_squares[mark.getValue()]==square,"verify mark not on square");
    marksseen++;
  }
  int marksinlist=0;
  for (int sq:marks_to_squares)
    if(square_valid(sq))++marksinlist;
  uassert(marksseen==marksinlist,"MBM verify mark seen in list");
}

int QPos::getDepth(){
  if(!parent)return 0;
  int index=myindex(parent->children,this);
  uassert(index>=0,"qpos getdepth");
  int parentdepth=parent->getDepth();
  return parentdepth + (index>0);
}
    
  
Game*QPos::getGame(){
  uassert(qgame&&qgame->game,"qpos getgame");
  return qgame->game;
}

vector<QPos*>QPos::descendants(){ //this can be done with an iterator
  vector<QPos*>ret;
  for(int i=index;i<=lastDescendantIndex;++i)
    ret.push_back(qgame->getQPos(i));
  uassert(ret.size()&&ret[0]==this,"qpos desc");
  return ret;
}

QPos::QPos(){
  clear();
}

QPos* QPos::createQPos(QGame*qgame){
  uassert(qgame,"createQPos args");
  QPos*ret=qgame->getNewQPos();
  ret->clear();
  ret->initialize(qgame);
  return ret;
}

void QPos::initialize(QGame*qg){
   clear();
   qgame=qg;
   uassert(qgame,"QPos bad arg");
   Game*game=qgame->game;
   uassert(game,"qpos no game");
   const pieceT* oldboard=MarkBoard::getBoard(game);
   toMove=MarkBoard::getToMove(game);
   id=MarkBoard::identity(game);
   originalComment=MarkBoard::getComment(game);
   nags=MarkBoard::getNags(game);
   for(int sq=0;sq<64;++sq){
     pieceT ptype=oldboard[sq];
     board[sq]=ptype;
    thePieceMasks.at(ptype).insert(sq);
    if(piece_Color(ptype)==WHITE)
      theColorMasks[WHITE].insert(sq);
    else if (piece_Color(ptype)==BLACK)
      theColorMasks[BLACK].insert(sq);
  }
   for(int i=0;i<64;++i)squares_to_marks[i]=markT(); //for debugging
   for(int i=0;i<markTMax;++i)marks_to_squares[i]=0; // for debugging
#ifdef CQL6_EMBEDDED // scidb: only the script's demanded position-state features
  if (qgame->stateFeatures & 1) theIsCheck=MarkBoard::check(game);
  if (qgame->stateFeatures & 2) theIsMate=MarkBoard::mate(game);
  if (qgame->stateFeatures & 4) theIsStalemate=MarkBoard::stalemate(game);
#else
  theIsCheck=MarkBoard::check(game);
  theIsMate=MarkBoard::mate(game);
  theIsStalemate=MarkBoard::stalemate(game);
#endif
}

int QPos::getGameNumber()const{return qgame->getGameNumber();}

bool QPos::virtualmainline() const{
  if(initial())return true;
  uassert(parent&&previousMove.valid&&previousMove.index>=0,"virtualmainline previousmove");
  if (previousMove.isNull())return false;
  if (previousMove.index>0&&parent->getToMove()==WHITE) return false;
  return parent->virtualmainline();
}

int QPos::getSiblingIndex()const{
  if (!parent)return 0;
  const QMove*prevmove=&previousMove;
  uassert(prevmove&&prevmove->valid,"qpos sibling index qmove");
  int ret=prevmove->index;
  uassert(ret>=0,"qpos siblingindex index");
  return ret;
}
  
QPos* QPos::lca(QPos*left, QPos*right){
  uassert(left&&right,"lca args");
   while(left!=right){
    uassert(left&&right,"lcanode internal null");
    int lply=left->getPly();
    int rply=right->getPly();
    uassert(lply>=0||rply>=0,"lcanode bad ply");
    if(lply>=rply)
      left=left->getParent();
    else if (rply>lply)
      right=right->getParent();
   }
   uassert(left!=NULL&&left==right,"lca terminal");
   return left;
}

void QPos::deleteComments(int start, int stop){
  return qgame->deleteComments(start,stop);
}

int QPos::distance(QPos*left,QPos*right){
  uassert(left&&right,"qpos distance arg");
  QPos*L=lca(left,right);
  int lply=left->getPly();
  int rply=right->getPly();
  int lcaply=L->getPly();
  uassert(lcaply<=lply&&lcaply<=rply,"distance plies");
  return (lply-lcaply)+(rply-lcaply);
}

//Assumes start move is move number 1
int QPos::getMoveNumber()const{
  int ply=thePly;
  bool wtm=getToMove()==WHITE;
  bool btm=!wtm;
  bool firstmovewhite=true;
  if(wtm&& (ply%2==1)||
     btm&&(ply%2==0)) firstmovewhite=false;
  if (!firstmovewhite &&
      wtm) ply+=1;
  return ply/2 + 1;
}

string QPos::idString(){
  stringstream s;
  s<<"move ";
  s<<getMoveNumber();
  if (getToMove()==BLACK)
    s<<"(btm)";
  else
    s<<"(wtm)";
  if(getDepth()>0){
    s<<'['<<index<<']';
    stringstream ss;
    ss<<"id:"<<index;
    appendComment(ss.str());
  }
  return s.str();
}

////////////////Comment methods here//////////////////
void QPos::appendComment(const string &addition){
  if(CqlCommentLevel==CommentLevel::Silent) return;
  if (addition.empty())return; //added 9.325 to prevent exra space at first comment issu
  if (!CqlSmartComments)
    appendCommentLocally(addition);
  else
    qgame->pushComment(this,addition);
}

void QPos::appendCommentLocally(const string &addition){
  if(addition.empty())return;
  if(CqlUniqueComments)
    for (string&previouscomment:addedComments)
      if (previouscomment==addition)return;
  addedComments.push_back(addition);
}

void QPos::mergeCommentsCurrent(){
  Game*game=qgame->game;
  uassert(game&&qgame,"mergecomments game");
  uassert(id==MarkBoard::identity(game),"mergeComments bad id");
  if (deleteOriginalComment)
    MarkBoard::gameDeleteComment(game);
  MarkBoard::gameAppendComment(game,commentAddition());
}

string QPos::commentAddition() const {
  stringstream s;
  int totalsize=(int)(originalComment.size());
  for(const string& c : addedComments){
    if(c.empty())continue;
    int csize=(int)(c.size());
    int newsize=csize+totalsize;
    if(newsize>4800) break;
    else if(newsize>4500){
      s<<"[cql truncate]...";
      break;
    }//if csize...>4500
    else{
      if(totalsize>0) s<<' ';
      totalsize+=csize;
      s<<c;
    }//else if csize > ...
  }//for string c
  return s.str();
}

bool QPos::matchCommentVisible(const string& label) const {
  if (label.empty()) return false;
  string addition=commentAddition();
  if ((deleteOriginalComment ? 0 : originalComment.size())+addition.size()>4500) return false;
  size_t offset=0;
  while ((offset=addition.find(label,offset))!=string::npos) {
    size_t end=offset+label.size();
    bool left=offset==0 || !(isalnum((unsigned char)addition[offset-1]) || addition[offset-1]=='_');
    bool right=end==addition.size() || !(isalnum((unsigned char)addition[end]) || addition[end]=='_');
    if (left && right) return true;
    offset=end;
  }
  return false;
}

void QPos::mergeComments(){
  Game*game=qgame->game;
  uassert(game&&qgame,"mergecomments game");
  uassert(id==MarkBoard::identity(game),"mergeComments bad id");
  mergeCommentsCurrent();
  for(int childi=0;childi<nChildren();++childi){
    MarkBoard::move_to_child(game,childi);
    QPos*child=children[childi];
    child->mergeComments();
    MarkBoard::gameBackup(game);
  }
  uassert(id==MarkBoard::identity(game),"mergeComments bad id2");
}

int QPos::markComments(){
  return qgame->markComments();
}
void QPos::restoreComments(int x){
  qgame->restoreComments(x);
}

bool QPos::hasNag(int nag){
  uassert(nag>0&&nag<=255,"hasNag: invalid nag parameter");
  for(int n:nags) if (nag==n) return true;
  return false;
}

//a is a proper ancestor of d
bool QPos::isProperAncestor(const QPos* a, const QPos* d){
  uassert(a&&d, "bad args to qpos ipa");
  int aindex=a->index;
  int dindex=d->index;
  return dindex>aindex
    && dindex<=a->lastDescendantIndex;
}

//a is a proper ancestor of d or else a==d
bool QPos::isImproperAncestor(const QPos*a, const QPos* d){
  return a==d || isProperAncestor(a,d);
}

pieceT QPos::getPiece(squareT sq)const{
  uassert(square_valid(sq),"qpos getpiece args");
  return board[sq];
}

/*return a vector consisting of the nodes on the path between start and stop.
  start is NOT included in the path but stop IS included in the path.
  if start==stop then the empty path is returned. start must be an improper
  ancestor of stop
*/

vector<QMove*>QPos::pathBetween(QPos*start, QPos*stop){
  uassert(start&&stop&&isImproperAncestor(start,stop),"path: invalid args");
  QPos*qpos{stop};
  vector<QMove*>path;
  if (start==stop)return path;
  for(qpos=stop;qpos!=start;qpos=qpos->getParent()){
    uassert(qpos,"path: invalid path somehow");
    QMove*qmove=qpos->getPreviousMove();
    uassert(qmove,"pathbetweenqmove");
    path.push_back(qmove);
  }
  std::reverse(path.begin(),path.end());
  uassert(path.size()&&path.front()->head==start,"pathbetween: path check");
  uassert(path.back()->tail->getPly()
	  -path.front()->head->getPly()
	  ==
	  (int)(path.size()),
	  "path bad size check");
  return path;
}
