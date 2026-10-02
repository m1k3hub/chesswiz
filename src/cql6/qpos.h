#pragma once
#include "abbreviations.h"
#include "util.h"
#include "qmove.h"
#include <array>
class QPos {
 public:
  //CONSTRUCTORS (see private: section)
  static QPos* createRoot(QGame* qgame,bool searchvariations);
  static QPos* createFromParent(QPos*parent, int childindex, bool variations);
  static QPos* createQPos(QGame* qgame);
  QPos();
  //DATA MEMBERS
  markT squares_to_marks[64];
  squareT marks_to_squares[markTMax];
  pieceT board[64];
  int index{-1};
  int lastDescendantIndex{-1};
  
  colorT toMove{NOCOLOR};
  moveT* id{NULL};
  string originalComment;
  vector<int>nags;
  vector<string> addedComments;
  string identificationComment;
  vector<QPos*>children;
  vector<QMove*>moves;
  QMove previousMove;
  bool theIsCheck{false};
  bool theIsStalemate{false};
  bool theIsMate{false};
  QPos*parent{NULL};
  std::array<SquareMask,MAX_PIECE_TYPES>thePieceMasks;
  std::array<SquareMask,2>theColorMasks;
  int thePly{-1};
  QGame*qgame{NULL};
  //PUBLIC METHODS
  void print()const;
  vector<QMove*>*getMoves(){return &moves;}
  const vector<QMove*>*getMoves()const{return &moves;}
  colorT getToMove()const{return toMove;}
  QGame*getQGame()const{return qgame;}
  bool hasNag(int nag);
  std::array<SquareMask,MAX_PIECE_TYPES>*getPieceMasks(){return &thePieceMasks;}
  SquareMask getColorMask(colorT color){return theColorMasks.at(color);}
  int nChildren()const{return (int)(children.size());}
  vector<QPos*>descendants();
  static void visitRoot(QPos*root,bool variations,vector<QPos*>& all);
  static QPos* lca(QPos*left, QPos*right);
  static int distance(QPos*left, QPos*right);
  QPos*getChild(int childi){return children[childi];}
  bool mate()const{return theIsMate;}
  bool stalemate()const{return theIsStalemate;}
  void appendComment(const string &addition);
  void appendCommentLocally(const string &addition);
  string getOriginalComment(){return originalComment;}
  void mergeComments();
  void mergeCommentsCurrent();
  string commentAddition() const; // shared emission payload, including original size limits
  bool matchCommentVisible(const string& label) const;
  bool check()const{return theIsCheck;}
  bool initial()const{return parent==NULL;}
  bool terminal()const{return children.empty();}
  QMove* getPreviousMove(){return &previousMove;}
  const QMove* getPreviousMove()const{return &previousMove;}
  QPos*getParent()const{return parent;}
  Game*getGame();
  const pieceT*getBoard()const{return board;}
  pieceT getPiece(squareT sq)const;
  void clear();
  int getDepth();//This is the variation depth not the ply level!
  int getPly(){return thePly;}
  int getMoveNumber()const;
  void print();
  vector<QPos*>getDescendants();
  void verifyDescendants();
  void verify();
  markT getMark(squareT square){return squares_to_marks[square];}
  squareT getSquare(markT mark){return marks_to_squares[mark.getValue()];}
  int getGameNumber()const;
  int getSiblingIndex()const;
  bool virtualmainline()const;
  string idString();
  int markComments();
  void restoreComments(int);
  void deleteComments(int start, int stop);
  bool deleteOriginalComment{false};

  static bool isProperAncestor(const QPos* a, const QPos* d);//a is a proper ancestor of d
  static bool isImproperAncestor(const QPos* a, const QPos* d); //a is an improper ancestor of d
  static vector<QMove*>pathBetween(QPos*start, QPos*stop);
 private:
  static void marks_make_move(markT* squares_to_marks,
			      squareT* marks_to_squares,
			      squareT fromsquare,
			      squareT tosquare,
			      const pieceT* board,
			      colorT color
			      );
  void setMarks();
  void initializeMarks();
  void initialize(QGame*);
  static bool slowDescendant(QPos*ancestor, QPos*descendant);
};
