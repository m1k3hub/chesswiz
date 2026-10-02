#include <stdio.h>
#include "cqlassert.h"
#include "cqlexit.h"
#include <ctype.h>
#include <sstream>
#include "util.h"
#include "cqlglobals.h"
#include "pgnsource.h"
#ifdef CQL6_EMBEDDED // scidb: file lockdown during embedded searches
#include "scidb_lockdown.h"
#endif

#include <cstring>
#include <mutex>

std::mutex pgnSourceMutex;

PgnSource::PgnSource(string name):fileName(name){
#ifdef CQL6_EMBEDDED // scidb: no file access during an embedded search
  scidb::file_guard("PgnSource", name.c_str());
#endif
  eassert(CqlPgnStdin||fileName.size(),"pgnsource:emptyfilename");
  uassert(CqlPgnStdin==fileName.empty(),"pgnsource: internal: empty filename/PGNstdin mismatch");
  if(CqlPgnStdin)
    theFile=stdin;
  else
    theFile=fopen(fileName.c_str(),"rb");
  eassert(theFile!=NULL,"PgnSource: could not open file: ",fileName);
}

/*The absurd code below is a hack on a hack on a hack. 
  Some pgn files (e.g. from chessbase) including heijden.pgn
  include non-ASCII Unicode characters at the start of a file.
  The SCID parser gives erroneous first-game comments when this
  happens. See also skipNonAscii in the file origChanges.cpp
  This function changes these starting nonAscii characters to \n
  We do not use ' ' because they come before a tag line. It would
  make most sense to convert all nonAscii characters to '?' or something
*/

void PgnSource::skipNonAsciiBuffer(){
  int i=0;
  while(true){
    int origc=theBuffer[i];
    if (origc>127 || origc<=0) theBuffer[i]='\n';
    else break; //added 1/30/2019
    ++i;
  }
}

bool PgnSource::nextGame(char*buffer,
			 int capacity,
			 int*gamenumberp,
			 int*charsreadp,
			 int*linestartp){


  /*the following line determines if we are exiting and if so exits. 
added in 9.324 to prevent a bad error message when the first exiting thread
destroys the pgnSourceMutex. The remains a race condition but all that
will happen is a bad error message, and it is unlikely to occur.
Considered pausing but that has implementation issues
*/
  
  if (CqlIsExiting)
    cql_exit(1);
  
  std::lock_guard<std::mutex> guard(pgnSourceMutex); // http://en.cppreference.com/w/cpp/thread/mutex
  ++nRequests;
  uassert(!isReading,"nextGame: isReading is true unexpectedly"); //mutex check
  isReading=true; 
  theBuffer=buffer;
  bufferCapacity=capacity;
  pgnAssert(theBuffer!=0
	    &&bufferCapacity>0
	    &&bufferCapacity<10000000
	    &&gamenumberp!=0
	    &&charsreadp!=0
	    &&linestartp!=0,
	    "nextGame: bad args");
  if (Eof) {isReading=false;return false;}
  if(!CqlPgnStdin)pgnAssert(filePosition==ftell(theFile),"nextGame filePosition mismatch");
  bufferPosition=0;
  theBuffer[0]=0; //invariant: first unwritten char must be 0
  gameNumber++;
  *linestartp=lineNumber;
  bool ret=mainLoop();
  if(!ret) {isReading=false;return false;}
  if(gameNumber==1)
    skipNonAsciiBuffer();
  *gamenumberp=gameNumber;
  *charsreadp=bufferPosition;
  isReading=false;
  return true;
}    

string PgnSource::toString(){
  stringstream s;
  s<<"Pgn file information: "
   <<"filename: " <<fileName
   <<" filePosition: "<<filePosition
   <<" lineNumber: "<<lineNumber
   <<" charInLine: "<<charInLine
   <<" gamenumber: "<< gameNumber
   <<" nrequests: "<<nRequests
   <<" bufferPosition: "<<bufferPosition
   <<" buffer:"<<endl
   <<theBuffer
   <<endl
   <<">";
  return s.str();
}

enum class ParserState{
  seekingTag,
  readingTags,
  readingGame};
  
bool PgnSource::mainLoop(){
    size_t lastTagSeenLine=0;
    bool seen_non_whitespace=false;
  while(true){ //we are not in a comment or Eof here
    pgnAssert(!Eof,"mainLoop PgnSource internal");
    int c=getChar();
    if(Eof)break;
    pgnAssert(c>0&&c<256,"PgnSource::mainLoop: null or illegal file character");
    if(c>127)continue;
    if(c==' '||c=='\t'||c=='\r'||c=='\v'||c=='f') continue;
    else if(c=='\n')continue;
    else if(c==';') {skipLine();continue;}
    else if(c=='{') {skipComment(CqlFixNestedComments);continue;}
    seen_non_whitespace=true;
    if(c=='[') {
      //      printf("mainloop: seen '[': %s\n",toString().c_str());
      pgnAssert(lastTagSeenLine==0
		||lastTagSeenLine>=lineNumber-1,
		"'[' seen in unexpected location: previous tag seen was not previous line");
      lastTagSeenLine=lineNumber;
      skipTagLine();
    }
    else if(seen_result()){
      pgnAssert(lastTagSeenLine>0,"Missing tag section (missing line starting with '['");
      return true;
    }
  }
  pgnAssert(!seen_non_whitespace,"PgnSource::mainLoop: missing end of game");
  return false;
}

int PgnSource::getChar(){
  if(Eof)
    pgnAssert(false,"PgnSource: attempt to read past Eof");
  int c=fgetc(theFile);
  if(c<0) {Eof=true;return -1;}
  if(c==0)pgnAssert(false,"PgnSource::getChar(): null character in file");
  ++filePosition;
  ++charInLine;
  if (c=='\n') {
    ++lineNumber;
    charInLine=0;
  }
  writeBuffer(c);
  return c;
}

void PgnSource::writeBuffer(int c){
  pgnAssert(c>0,"PgnSource::writeBuffer: internal");
  pgnAssert(bufferPosition<bufferCapacity-10,
	    "CQL internal buffer capacity exceeded while reading PGN file. \nThis might be due to an unmatched '{' in the PGN file, or some other issue with the PGN file\n");
  //I'm not 100% sure that conversion from int to char will work right
  //here. Probably the buffer should be unsigned char, but that poses
  //a problem
  //We can't use unsigned char here because pgnparse.h in SCID uses char
  char castedchar=(char)(unsigned char)(unsigned int)c;
  if((int)(unsigned int)(unsigned char)castedchar!=c){
    printf("Error in writeBuffer: The actual character to be written was %d\n",c);
    printf("The casted char int value is: %d\n",castedchar);
    pgnAssert(false,"writeBuffer::internal, cast from int to char failed");
  }
  theBuffer[bufferPosition++]=castedchar;
  theBuffer[bufferPosition]=0;
}

void PgnSource::skipLine(){
  pgnAssert(!Eof,"skipLine unexpected Eof at start: ");
  while(true){
    int c=getChar();
    if(Eof||c=='\n')return;
  }
  pgnAssert(false,"skipLine internal");
}

void PgnSource::skipTagLine(){
  bool seenrightbracket{false};
  int prev=getPreviousCharacter();
  pgnAssert(prev=='[',"SkipTagLine internal missing '['");
  while(true){
    int c=getChar();
    if(Eof||c=='\n'){
      pgnAssert(seenrightbracket,"missing right bracket in tagline");
      return;
    }
    if(c==']')seenrightbracket=true;
  }
  pgnAssert(false,"skipTagLine internal");
}

int PgnSource::getPreviousCharacter(){
  pgnAssert(bufferPosition>0,"getPreviousCharacter bad call");
  unsigned char c=theBuffer[bufferPosition-1];
  int ret=(int)c;
  pgnAssert(ret>0&&ret<256,"getPreviousCharacter: bad character");
  return ret;
}

void PgnSource::skipComment(bool fixnests){
  size_t startline=lineNumber;
  int startchar=charInLine;
  size_t startpos=filePosition;
  pgnAssert(getPreviousCharacter()=='{',"skipComment internal");
  int nestlevel=0;
  //  bool seennest=false; deleted by stiller 9/15/2022 as purpose unknown
  while(!Eof){
    int c=getChar();
    if(c=='{' && fixnests){
      uassert (bufferPosition>0&&theBuffer[bufferPosition-1]=='{',"PgnSource:skipComment: internal");
      theBuffer[bufferPosition-1]='_';
      ++nestlevel;
      //      seennest=true; deleted by stiller 9/15/2022 as purpose unknown
    }
    if(c=='}' && fixnests){
      if (nestlevel==0) return;
      uassert(nestlevel>0,"pgns sc i3");
      uassert (bufferPosition>0&&theBuffer[bufferPosition-1]=='}',"PgnSource:skipComment: internal2");
      theBuffer[bufferPosition-1]='_';
      --nestlevel;
    }
    else if (c=='}'&&!fixnests)
      return;
  }
  stringstream s;
  s<<"skipComment: unterminated comment '{' at file position: "
   <<startpos
   <<" Line number: "<<startline
   <<" charInLine: "<<startchar;
  pgnAssert(false,s.str().c_str());
}

bool PgnSource::seen_result(){
  const char* possibleresults[4]{"*","1-0","0-1","1/2-1/2"};
  if(bufferPosition==0)return false;
  int curr=theBuffer[bufferPosition-1];
  if(curr!='*'&&curr!='0'&&curr!='1'&&curr!='2')return false;
  for(const char* result : possibleresults)
    if (seen_result_string(result))return true;
  return false;
}

int PgnSource::peek(){
  if (Eof) return -1;
  int c = fgetc(theFile);
  if(c<0) {Eof=true;return -1;}
  pgnAssert(c>0,"In peek got a null character in file");
  int ret=ungetc(c,theFile);
  pgnAssert(ret>0,"ungetc failure");
  return c;
}
  

bool PgnSource::seen_result_string(const char*  result){
  int len=(int)(strlen(result));
  if(len>bufferPosition-2)return false;
  const char* buffstarttest=theBuffer+bufferPosition-len;
  char prev=*(buffstarttest-1);
  if(isalnum(prev)||prev=='-')return false;
  
  pgnAssert(buffstarttest>=theBuffer,"seen_result_string internal");
  if (std::strcmp(result,buffstarttest)!=0)return false;
  //skip whitespace to eol
  int nextch=peek();
  if(Eof) return true;
  pgnAssert(nextch>0,"bad peek value in seen_result_string");
  if(nextch<128&&!(isspace(nextch)))return false;
  while(true){
    int c=peek();
    if(Eof)return true;
    if(c>127)return true;
    pgnAssert(c>0,"seen_result_string: bad peek");
    if(isspace(c)){
      int newc=getChar();
      pgnAssert(c==newc,"internal in seen_result_string: peek mismatch");
      continue;}
    return true;
  }
  pgnAssert(false, "seen_result_string: internal loop");
}

void PgnSource::pgnAssert(bool b, const char* charmessage){
  if(b)return;
  stringstream s;
  s<<"PgnSource: pgnAssert fails: " <<charmessage<<toString()<<endl;
  string errmessage=s.str();
  if(errmessage.size()>1200){
    errmessage=errmessage.substr(0,1200);
    errmessage+= "...";}
  uassert(false,errmessage);
}

