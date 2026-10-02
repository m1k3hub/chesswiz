#include "chesstypes.h"
string direction_to_string(directionT d){
  switch(d){
  case UP: return "U";
  case DOWN: return "D";
  case LEFT: return "L";
  case RIGHT: return "R";
  case UP_LEFT: return "UL";
  case DOWN_LEFT: return "DL";
  case UP_RIGHT: return "UR";
  case DOWN_RIGHT: return "DR";
      };
  uassert(false, "unknown direction");
  return "";
}

string color_string(colorT c){
  if(c==WHITE)return "White";
  if(c==BLACK)return "Black";
  if(c==NOCOLOR)return " ";
  uassert(false,"bad color color_string");
  return "illegal";
}

bool file_valid(int f){
  return f>=0&&f<8;
}

bool rank_valid(int r){
  return file_valid(r);
}

char file_to_char(int f){
  uassert(file_valid(f),"file_to_char: bad file");
  return (char)(f+'a');
}


char rank_to_char(int r){
  uassert(rank_valid(r),"rank_to_char: bad rank");
  return (char)(r+'1');
}

bool piece_valid(pieceT p){
  static vector<pieceT>valid{
      WK,WQ,WR,WB,WN,WP,
      BK,BQ,BR,BB,BN,BP,
      EMPTY
      };
  for(pieceT x : valid) if(x==p)return true;
  return false;
}


char piece_to_char(pieceT p){
  switch(p){
  case BR: return 'r';
  case BN: return 'n';
  case BB: return 'b';
  case BQ: return 'q';
  case BK: return 'k';
  case BP: return 'p';

  case WR: return 'R';
  case WN: return 'N';
  case WB: return 'B';
  case WQ: return 'Q';
  case WK: return 'K';
  case WP: return 'P';

  case EMPTY: return '_';
  }
  uassert(false,"bad piece");
  return 0;
}

///square related functions

string square_to_string(squareT square){
  uassert(square_valid(square),"square_to_string: bad square");
  int f=square_file(square);
  int r=square_rank(square);
  char fc=file_to_char(f);
  char rc=rank_to_char(r);
  string ret{fc,rc};
  return ret;
}
  

string result_to_string(resultT rc){
  switch(rc){
  case RESULT_White: return "1-0";
  case RESULT_Black: return "0-1";
  case RESULT_Draw: return "1/2-1/2";
  case RESULT_None: return "No_Result";
  }
  uassert(false,"bad result");
  return "ILLEGAL";
}

bool direction_valid(directionT d){
  static vector<directionT> allds{
      UP, DOWN, LEFT, RIGHT,
	UP_LEFT, UP_RIGHT, DOWN_LEFT, DOWN_RIGHT};
  for(auto dir:allds) if(dir==d)return true;
  return false;
}
      
colorT color_other(colorT c){
  switch(c){
  case WHITE: return BLACK;
  case BLACK: return WHITE;
  }
  uassert(false,"color_other: bad color");
  return NOCOLOR;
}

