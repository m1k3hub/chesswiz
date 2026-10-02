#include "util.h"
#include "cqlglobals.h"
#ifdef CQL6_EMBEDDED // scidb: file lockdown during embedded searches
#include "scidb_lockdown.h"
#endif

#include <string.h>
#include <ctype.h>

static int indentlevel;

void indent(){++indentlevel;};
void tab(){
  for(int i=0;i<indentlevel;++i) printf(" ");
}

void unindent(){
  indentlevel--;
  if(!indentlevel)indentlevel=0;
}
  
string util::num_to_string(long long v){
  stringstream s;
  s<<v;
  return s.str();
}

string util::num_to_string(size_t v){
  stringstream s;
  s<<v;
  return s.str();
}


//not robust against large or small inputs sadly

bool util::intValue(const string &s, int*val){
  if (s.empty()) return false;
  if (s[0]=='-'){
    string suffix=s.substr(1);
    int nonnegativevalue=-1;
    if(!nonnegativeIntValue(suffix,&nonnegativevalue))
      return false;
    *val= -nonnegativevalue;
    return true;
  }
  return nonnegativeIntValue(s,val);
}
    
bool util::nonnegativeIntValue(string s, int*val){
  if(s.empty()) return false;
  int sum=0;
  for (char c:s){
    if (c>='0'&&c<='9'){
      sum*=10;
      sum+= c - '0';
    }
    else return false;
  }
  *val=sum;
  return true;
}

bool util::positiveIntValue(string s,int*val){
  int tmpval = 0;
  if (nonnegativeIntValue(s,&tmpval)){
    if (tmpval==0) return false;
    uassert(tmpval>0, "util::piv internal");
    *val=tmpval;
    return true;}
  return false;
}

string util::game_to_string(Game*game){
  TextBuffer* tbuffer=new TextBuffer;
  const int buffersize=CqlPgnOutputBufferSize;
  eassert(buffersize>=100000 && buffersize <= 100000000, "game_to_string buffersize internal error out of range");
  tbuffer->SetBufferSize(buffersize);
  game->WriteToPGN_changed(tbuffer);
  char * buf=tbuffer->GetBuffer();
  buf[buffersize-1]=0;
  string ret(buf);
  if(ret.size()>buffersize-5)
    ret+= string(" game truncated by CQL } * \n\n");
  tbuffer->Free();
  delete tbuffer; // scidb: Task 3 §B — the TextBuffer object itself was leaked (~2 KB each)
  return ret;
}

void util::printgame(FILE* stream,Game* game){
  TextBuffer * tbuffer=new TextBuffer;
  tbuffer->SetBufferSize(100000);
  game->WriteToPGN_changed(tbuffer);
  tbuffer->DumpToFile(stream);
  tbuffer->Free();
}


//The routine below only works with QPos boards; it does not print the color_square of Position boards
//because boards in QPos and most of CQL ignore the 65th square of a pieceT* board.
void util::my_dump_board(boardT board){
  FILE * fp=stdout;
  squareT s;
  //  printf("Side To move is: %c\n",board[COLOR_SQUARE]);
  for (int i=7; i>=0; i--) {
    fputs ("   ", fp);
    for (int j=0; j<8; j++) {
      s = (i*8) + j;
      char c=PIECE_CHAR[board[s]];
      if (c=='.'){
	if (i%2==j%2)
	  putc('+',fp);
	else
	  putc('-',fp);
      }
      else 
	putc (c, fp);
      putc (' ', fp);
    }
    putc ('\n', fp);
  }
}

int util::squareShiftDirection(int sq, directionT direction){
  uassert(sq>=0&&sq<64&&direction<=DOWN_RIGHT,"squareshiftdirection down");
  int s=square_Move(sq,direction);
  if (s>=64) s=-1;
  return s;
}

bool util::directionCompatible(pieceT piece, directionT direction){
  pieceT newp=piece_Type(piece);
  if (newp==ROOK||newp==QUEEN) return directionOrthogonal(direction);
  else if (newp==BISHOP||newp==QUEEN) return directionDiagonal(direction);
  else return false;
}
bool util::directionOrthogonal(directionT direction){
  return direction==UP||direction==DOWN||direction==LEFT||direction==RIGHT;
}

bool util::directionDiagonal(directionT direction){
  return direction==UP_LEFT||direction==DOWN_LEFT||direction==UP_RIGHT||direction==DOWN_RIGHT;
}

void util::printgame(Game*g){
  if(!g){printf("NULL GAME\n");}
  my_dump_board(g->GetCurrentPos()->GetBoard());
}
    
string util::squarestring(int file, int rank){
  uassert(file>=0&&rank>=0&&file<=7&&rank<=7,"squarestring: invalid square");
  stringstream s;
  s<< (char)('a'+file)<<(char)('1'+rank);
  return s.str();
}
    
string util::downcase(const string & a){
  stringstream s;
  for (auto c : a)
    if (isupper(c))
      s<<(char)(tolower(c));
    else
      s<<(char)c;
  return s.str();
}
      
  
//read a positive integer from source and replace source by the unread characters
//return true if read succeeds. Allow starting 0s for now. Max of 100000000.

bool util::readPositiveInt(string * sourcep, int * valp){
  int ret=0;
  int i=0;
  for(i=0;i<sourcep->size();++i){
    char c=sourcep->at(i);
    if (c>='0'&&c<='9')
      ret=10*ret+(int)(c-'0');
    else break;
  }
  if (ret<=0||ret>100000000) return false;
  uassert(i>0&&i<=sourcep->size(),"readPositiveInt internal");
  *sourcep = sourcep->substr(i);
  *valp=ret;
  return true;
}

/* replace *sourcep with its suffix after pattern if it starts with pattern,
   otherwise false and no change*/

bool util::readString(string*sourcep, const string pattern){
  uassert(pattern.size()>0, "readString empty pattern");
  int i=0;
  for (i=0;i<pattern.size();++i)
    if (i>=sourcep->size() ||
	sourcep->at(i)!=pattern.at(i)) return false;
  uassert(i==pattern.size(),"readString pattern");
  *sourcep=sourcep->substr(pattern.size());
  return true;
}
  
  
string util::replaceAll(string content, const string& from, const string& to){
  while (content.find(from)!=string::npos)
    content.replace(content.find(from),from.size(), to);
  return content;
}

string util::quotestring(const string& str){
  stringstream s;
  s<<"\""<<str<<"\"";
  return s.str();
}

string util::string_from_filename(string filename){
#ifdef CQL6_EMBEDDED // scidb: no file access during an embedded search
  scidb::file_guard("util::string_from_filename", filename.c_str());
#endif
  eassert(!filename.empty(),"Unable to open empty filename");
  eassert(filename.size()<1000,"filename too long");
  FILE*file=fopen(filename.c_str(),"r");
  eassert(file!=NULL,"Unable to open file: ",filename);
  string ret;
  int c=0;
  while ((c=fgetc(file))>=0)
    ret.push_back(c);
  int closeret=fclose(file);
  eassert(!closeret,"File close failed on file: ",filename);
  return ret;
}

