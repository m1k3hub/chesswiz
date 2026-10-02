#include "lexer.h"
#include <stdio.h>
#include "cqlassert.h"
#include "cqlexit.h"
#include <cctype>
#include <sstream>
#include "util.h"

/* the main lexer loop */
Token* Lexer::nextToken(){
  int startposition=currentCharacter;
  Token* token=NULL;
  auto line=getCurrentLine();
  auto column=getCurrentColumn();
  if(!token) token=match_piecedeclarationtoken(); //must precede match_piecedesignator
  if(!token) token=match_linecommenttoken();
  if(!token) token=match_whitespacetoken();
  if (!token) token=match_result_string();
  if (!token) token=match_int();
  if(!token) token=match_bracereptoken();
  if(!token) token=match_castle();
  if(!token) token=match_special_unicode();
  if(!token) token=match_special_string(); //before groupnumber, before match_special
  if (!token) token=match_groupnumber(); //must be BEFORE match_special
  if (!token) token=match_piecedesignator(); //moved before match_special not sure if ok for 9.301
  if (!token) token=match_dashtoken(); //must follow match_special
  if (!token) token=match_special();
  if (!token) token=match_predefined();
  if (!token) token=match_filenametoken();
  if (!token) token=match_keyword();
  if (!token) token=match_quotedstringtoken();
  if (!token) token=match_id();
  if (!token&&!eof()){
    stringstream s;
    UChar uchar=match_uchar();
    uassert(uchar.isValid(),"bad unicode character in lexing");
    s<<"Invalid character: "<<uchar.uname();
    show_error(s.str());
  }
    
  if(token) {
    token->setStart(line,column);
    if(startposition>=currentCharacter)
      show_error("Lexer: got unknown 0-length token");
    token->setTrueStartStop(startposition,currentCharacter,theBuffer);
  }
  return token;
}


//The sync variable is true if Token::CurrentLineNumber and Token::CurrentColumnNumber are updated
Lexer::Lexer(const string &input,bool sync): theBuffer(input),syncThis(sync){
  bomTrim(theBuffer);
  eassert(!theBuffer.empty(),"Lexer: empty input stream");
  eassert(theBuffer.size()<10000000,"Lexer:input too long");
  int linenumber=1,column=1; //before reading the next character
  for (char c:theBuffer){
    if(c=='\n'){++linenumber;column=1;}
    else ++column;
    lineNumbers.push_back(linenumber);
    columnNumbers.push_back(column);
  }
  uassert(lineNumbers.size()==theBuffer.size() && columnNumbers.size()==theBuffer.size(),"Lexer size");
  if(syncThis)syncLocation();
}

  
void Lexer::syncLocation(){
  if(syncThis)
    Token::syncLocation(getCurrentLine(),
			getCurrentColumn());
}

int Lexer::getCurrentLine(){
  int i=currentCharacter-1;
  if (i<0)i=0;
  uassert(i<lineNumbers.size(),"gcl internal");
  return lineNumbers.at(i);
}

int Lexer::getCurrentColumn(){
  int i=currentCharacter-1;
  if (i<0)i=0;
  uassert(i<columnNumbers.size(),"gcl internal");
  return columnNumbers.at(i);
}

  




vector<Token*> Lexer::lexString(string contents){
  eassert(!contents.empty(),"Attempt to lex an empty file");
  Lexer lexer(contents,true);
  return lexer.lex();
}

//Same as lexString except this does NOT updated CurrentLine and CurrentChar
vector<Token*> Lexer::lexStringNested(string contents){
  eassert(!contents.empty(),"Attempt to lex an empty file");
  Lexer lexer(contents,false);
  return lexer.lex();
}
  
vector<Token*> Lexer::lexFile(string filename){
  string filecontents;
  if(filename=="cqldefault.cql")
    filecontents="cql().";
  else
    filecontents=util::string_from_filename(filename);
  return lexString(filecontents);
}
 
vector<Token*>Lexer::lex(){
  vector<Token*>ret;
  while(true){
    Token* token=nextToken();
    if(token) 
      ret.push_back(token);
    else break;
  }
  eassert(!ret.empty(),"Lexer failed: no tokens found");
  uassert(eof(),"unexpected lexer failure");
  vector<Token*>trimmedwhite=fixWhiteSpace(ret);
  return fixPath(trimmedwhite); //handle blank lines, wildcards
}


Token*Lexer::match_castle(){
  int x=save();
  char c=0;
  if(!match_char('o')) goto fail;
  if (!match_char('-')) goto fail;
  if (!match_char('o')) goto fail;
  c=peek();
  if (word_start(c)) goto fail;
  if(c!='-') return new KeywordToken("o-o");
  if (!match_char('-'))
    eassert(false,"lexer match_castle error");
  if (!match_char('o'))goto fail;
  c=peek();
  if(word_start(c))goto fail;
  return new KeywordToken("o-o-o");
 fail:restore(x);
  return NULL;
}

Token* Lexer::match_filenametoken(){
  int x=save();
  string w=next_word();
  bool isinput=false;
  bool isoutput=false;
  if(w=="input") isinput=true;
  else if(w=="output") isoutput=true;
  if (isinput || isoutput){
    match_whitespacetoken();
    string file=next_filename();
    if (!file.empty()&&isinput)
      return new InputFileToken(file);
    else if (!file.empty()&&isoutput)
      return new OutputFileToken(file);
  }
  restore(x);
  return NULL;
}

StringToken* Lexer::match_result_string(){
  int x=save();
  string name;
  while(true){
    char c=peek();
    if(word_constituent(c)||
       c=='/'||
       c=='-')
      {name+=c;
	forward();}
    else break;
  }
  if (name=="1-0"||
      name=="0-1"||
      name=="1/2-1/2")
    return new StringToken(name);
  restore(x);
  return NULL;
}

/*next_filename() returns either an empty string or a non-filename as an empty string.
  it DOES modify the stack so check this*/

string Lexer::next_filename(){
  string ret;
  QuotedStringToken*quoted=match_quotedstringtoken();
  if(quoted) return quoted->value;
  while(true){
    char c = peek();
    if (c==0 || c=='(' || c==')' || c=='<' || c=='>' || isspace(c) || c=='"')
      return ret;
    forward();
    ret+=c;
  }
  uassert(false,"next_filename");
  return ret;
}

string Lexer::next_word(){
  string name;
  char first=peek();
  if(!word_start(first))
    return name;
  forward();
  name+=first;
  while(true){
    char c=peek();
    if (!word_constituent(c))
      break;
    name+=c;
    forward();
  }
  return name;
}
  
Token* Lexer::match_id(){
  int x=save();
  string name=next_word();
  if (!name.empty() && !isReserved(name))
    return new IdToken(name);
  restore(x);
  return NULL;
}

Token* Lexer::match_keyword(){
  int x=save();
  string name=next_word();
  if (!name.empty() && isReserved(name))
    return new KeywordToken(name);
  restore(x);
  return NULL;
}
bool Lexer::isReserved(string s){
  return KeywordToken::isReserved(s);
}

bool Lexer::word_start(char c){
  return
    c>='a'&&c<='z' ||
    c>='A'&&c<='Z' ||
    c=='$' ||
    c=='_'
    ;
}

bool Lexer::word_constituent(char c){
  return word_start(c) ||
    c>='0'&&c<='9';
}
    
    
char Lexer::forward(){
  uassert(!eof(),"forward at eof");
  char c=peek();
  uassert(c,"forward null");
  ++currentCharacter;
  syncLocation();
  return c;
}

char Lexer::peek(){
  uassert(currentCharacter<=length(),"peek");
  if (currentCharacter>=length()) return (char)0;
  return theBuffer.at(currentCharacter);
}

int Lexer::save(){
  return currentCharacter;
}

void Lexer::restore(int x){
  uassert(x>=0&&x<=currentCharacter,"restore fail");
  currentCharacter=x;
  syncLocation();
}

Token* Lexer::match_special_unicode(){
  if(match_string(UnicodeUnionString+"="))
    return new SpecialToken("|=");
  else if (match_string(UnicodeIntersectionString+"="))
    return new SpecialToken("&=");
  else if (match_uvalue(UnicodeLE))
    return new SpecialToken("<=");
  else if (match_uvalue(UnicodeGE))
    return new SpecialToken(">=");
  else if (match_uvalue(UnicodeNE))
    return new SpecialToken("!=");
  else if (match_uvalue(UnicodeTurnstile))
    return new KeywordToken("path");
  else if (match_uvalue(UnicodeForAll))
    return new SpecialToken("[forall]");
  else if (match_uvalue(UnicodeElement))
    return new SpecialToken("[element]");
  else if (match_uvalue(UnicodeLeftArrow))
    return new SpecialToken("<-");
  else if (match_uvalue(UnicodeRightArrow))
    return new SpecialToken("->");
  else if (match_uvalue(UnicodeConcentricCircles))
    return new KeywordToken("focus");
  else if (match_uvalue(UnicodeBullet))
    return new KeywordToken("currentposition");
  else if (match_uvalue(UnicodeEightPointedStar))
    return new KeywordToken("flip");
  else if (match_uvalue(UnicodeHalfBlackSquare))
    return new KeywordToken("flipcolor");
  else if (match_uvalue(UnicodeGrid))
    return new SpecialToken(".");
  else if (match_uvalue(UnicodeUnion))
    return new SpecialToken("|");
  else if (match_uvalue(UnicodeIntersection))
    return new SpecialToken("&");
  else if (match_uvalue(UnicodePrecedes))
    return new SpecialToken("[<]");
  else if (match_uvalue(UnicodeSucceeds))
    return new SpecialToken("[>]");
  else if (match_uvalue(UnicodePrecedesOrEqualTo))
    return new SpecialToken("[<=]");
  else if (match_uvalue(UnicodeSucceedsOrEqualTo))
    return new SpecialToken("[>=]");
  else return NULL;
}
  
Token* Lexer::match_special(){
  const vector<string>specials{
			       "[element]","[forall]",
			       "-->","<--",
			       "{*}", "{+}",
			       "->", "<-",
			       "~~",
			       "<=",">=","==","!=","+=", "-=", "*=","/=", "%=","|=","&=",
			       "[<]","[<=]","[>]","[>=]",
			       "=?", "[]",
			       "+","-","*","/","=",">","<",
			       ".","(",")","{","}","|","?",":",
			       "#","~","&","%","\\",
			       ",","[","]"
  };
  for (auto name:specials)
    if(match_string(name))
      return new SpecialToken(name);
  return NULL;
}

bool Lexer::match_char(char c){
  uassert(c!=0,"match_char");
  if (c==peek()){
    forward();
    return true;
  }
  return false;
}

bool Lexer::match_string(string v){
  uassert(!v.empty(),"lex match_string");
  int x=save();
  for (char c:v)
    if (!match_char(c))
      {restore(x);
	return false;}
  return true;
}

QuotedStringToken* Lexer::match_quotedstringtoken(){
  if(!match_char('"'))return NULL;
  string val;
  while(true){
    if (eof())show_error("missing end of quoted string");
    char c=forward();
    if (c=='\n')
      show_error("quoted string spans end of line marker");
    if (c=='"') 
      return new QuotedStringToken(val);
    else val.push_back(c);
  }
  uassert(false,"match_quotedstring: internal");
  return NULL;
}

Token* Lexer::match_int(){ 
  int sum=0;
  int x=save();
  string word=next_digits();
  bool valid=util::nonnegativeIntValue(word,&sum);
  if(!valid){
    restore(x);
    return NULL;}
  return new IntToken(sum);
}

string Lexer::next_digits(){
  string ret;
  while(char c=peek())
    if (c>='0'&&c<='9'){
      ret+=c;
      forward();
    }
    else return ret;
  return ret;
}

bool Lexer::word_boundary(char c){
  return !word_constituent(c);
}


LineCommentToken* Lexer::match_linecommenttoken(){
  if(!peekslashslashslash())return NULL;
  bool x=match_string("///");
  uassert(x,"expected a match here match_linecommenttoken");
  return new LineCommentToken();
}

bool Lexer::peekslashslashslash(){
  int x=save();
  bool ret=false;
  if(!match_string("////")&&
     match_string("///"))
    ret=true;
  restore(x);
  return ret;
}
WhiteSpaceToken* Lexer::match_whitespacetoken(){
  bool foundblankline{false};
  int oldcurrent=currentCharacter;
  bool insideblankline=false;
  bool hasnewline{false};
  while(true){
    if(eof())break;
    char c=peek();
    if(c=='\n')hasnewline=true;
    if(peekslashslashslash()) break;
    if (c==';'
	|| match_string("////")
	|| !match_string("///")&&
	match_string("//"))
      {
	insideblankline=false;
	while(!eof()&& forward()!='\n');
	insideblankline=true;
      }
    else if (c=='\n'){
      if (insideblankline) foundblankline=true;
      else insideblankline=true;
      forward();
    }
    else if (isspace(c))
      forward();
    else if (match_string("/*")){
      read_to_starslash();
      insideblankline=false;
    }
    else break;
  }
  uassert(currentCharacter>=oldcurrent,"lexer whitespace current");
  if(currentCharacter>oldcurrent)
    return new WhiteSpaceToken(foundblankline,hasnewline);
  else return NULL;
}      

void Lexer::read_to_starslash(){
  while(!eof()){
    if (match_string("*/")) return;
    else forward();
  }
  eassert(false,"unterminated '/*'");
}

void Lexer::show_error(string s){
  cql_exit(string("Lexer error at ")
	   + locationString() + " "+s);
}

string Lexer::locationString(){
  std::stringstream stream;
  stream<<"Line: "<<
    getCurrentLine()<<
    " Column: "<<
    getCurrentColumn();
  return stream.str();
}

bool Lexer::match_files(int*min, int*max){
  if(match_filerange(min,max))
    return true;
  if(match_file(min)){
    *max=*min;
    return true;
  }
  return false;
}

bool Lexer::match_filerange(int*min,int*max){
  int x=save();
  int lmin=-1,lmax=-1;
  if(!match_file(&lmin))goto fail;
  if(!match_char('-')) goto fail;
  if(!match_file(&lmax))goto fail;
  *min=lmin;
  *max=lmax;
  if(lmin>lmax)show_error("bad file range");
  return true;
 fail:
  restore(x);
  return false;
}
bool Lexer::match_file(int* result){
  char f=peek();
  if(f>='a'&&f<='h'){
    forward();
    *result=f-'a';
    return true;
  }
  return false;
}

bool Lexer::match_ranks(int*min, int*max){
  if(match_rankrange(min,max))
    return true;
  if(match_rank(min)){
    *max=*min;
    return true;
  }
  return false;
}

bool Lexer::match_rankrange(int*min,int*max){
  int x=save();
  int lmin=-1,lmax=-1;
  if(!match_rank(&lmin))goto fail;
  if(!match_char('-')) goto fail;
  if(!match_rank(&lmax))goto fail;
  *min=lmin;
  *max=lmax;
  if(lmin>lmax)show_error("bad rank range");
  return true;
 fail:
  restore(x);
  return false;
}
bool Lexer::match_rank(int* result){
  char f=peek();
  if(f>='1'&&f<='8'){
    forward();
    *result=f-'1';
    return true;
  }
  return false;
}

Token* Lexer::match_predefined(){
  return NULL;
}

Token* Lexer::match_groupnumber(){
  if (!match_char('\\'))return NULL;
  bool seenhyphen=match_char('-');
  string word=next_digits();
  int len=(int)(word.size());
  if (len==0)
    show_error ("illegal backslash character (expecting 1 or 2 digits following, got none");
  if (len>2)
    show_error (string() + "at most two digits can follow a backslash character. Got digits: "+word);
  int val=0;
  val=word[0]- ('0');
  if (len==2)
    val= 10*val + word[1] - '0';
  if (seenhyphen)
    return new GroupIndexToken(val);
  else
    return new GroupNumberToken(val);
}

QuotedStringToken* Lexer::match_special_string(){
  int x=save();
  if (!match_char('\\')) return NULL;
  if (match_char('"'))
    return new QuotedStringToken("\"");
  else if (match_char('\\'))
    return new QuotedStringToken("\\");
  string name=next_word();
  if (name=="n")
    return new QuotedStringToken("\n");
  else if (name=="r")
    return new QuotedStringToken("\r");
  else if (name=="t")
    return new QuotedStringToken("\t");
  restore(x);
  return NULL;
}
		      
/* This must not be called if CurrentCharacter=0 and --> begins the lex. Otherwise it will be confused*/
DashToken* Lexer::match_dashtoken(){
  int start=save();
  if(match_string("-->")){
    restore(start);
    return NULL;
  }
  CaptureType captype{CaptureType::None};
  if(match_string(CaptureAscii))
    captype=CaptureType::Capture;
  else if(match_uvalue(UnicodeTimes)){
    captype=CaptureType::Capture;
  }
  else if (match_string(DashAscii))
    captype=CaptureType::NonCapture;
  else if (match_string(UnicodeDashString))
    captype=CaptureType::NonCapture;
  else{
    restore(start);
    return NULL;
  }
  return new DashToken(captype);
}



BraceRepToken*Lexer::match_bracereptoken(){
  int x=save();
  if(peek()!='{') return NULL;
  forward();
  bool seencomma{false};
  int firstnumber{-1};
  int secondnumber{-1};
  string firstword;
  string secondword;
  constexpr int maxreps=100000; // max allowed reps;
  if(peek()=='}') goto fail;
  firstword=next_digits();
  if(peek()==','){
    forward();
    seencomma=true;
  }
  if(seencomma)
    secondword=next_digits();
  if(peek()!='}'){
    goto fail;
  }
  else forward();
  if (firstword.size()){
    bool valid=util::nonnegativeIntValue(firstword,&firstnumber);
    if(!valid) goto fail;
  }
  if (secondword.size()){
    bool valid=util::nonnegativeIntValue(secondword,&secondnumber);
    if(!valid)goto fail;
  }
  if(firstword.size())uassert(firstnumber>=0,"bad firstnum in lexer in brace");
  if(secondword.size())uassert(secondnumber>=0,"bad secondnum in lexer in brace");
  if (!firstword.size()&&!secondword.size()&&seencomma)
    show_error("apparent empty brace repetition '{,}' which is illegal. Use '*'");
  if(firstnumber<0) firstnumber=0;
  if(secondnumber<0){
    uassert(firstnumber>=0,"lexer: bracerep: internal");
    if (seencomma) secondnumber=maxreps;
    else secondnumber=firstnumber;
  }
  if (firstnumber>secondnumber)
    show_error("in apparent '{n,m}' range indication, m is < n");
  if(firstnumber>maxreps||secondnumber>maxreps)
    show_error("too many repetitions in apparent brace repetition {n} or {n,m}");
  return new BraceRepToken(firstnumber,secondnumber);
 fail:
  restore(x);
  return NULL;
}
  
/* if the next character is a non-ASCII Unicode character of value between
   v1 and v2 inclusive, 
   return true and skip its constituent characters. Otherwise, no change*/

UChar Lexer::match_uchar(){
  if(eof())return UChar{};
  int v= UChar::char2int(peek());
  if(v<128)return UChar{};
  UChar u=UChar::parse(theBuffer,currentCharacter);
  if(u.isInvalid()){
    stringstream s;
    s<<"Unable to read apparent UTF-8 character. The first read character was had decimal value of: "
     <<v;
    show_error(s.str());
  }
  for(int i=0;i<u.size();++i)
    forward();
  return u;
}

bool Lexer::match_uvalue(int v){
  int x=save();
  UChar u = match_uchar();
  if(u.isValid() && u.getValue()==v)
    return true;
  restore(x);
  return false;
}


/* If the lexer matches a description of a Unicode string,
   currently just [x], then return that string. Otherwise return ""
*/
string Lexer::match_entity_string(){
  const string captureentity="[x]" ; // do this more systematically later
  if(match_string(captureentity))
    return captureentity;
  return "";
}
  
/*trim any leading byte order markers from the beginning of the string.
  we trim multiple BOMs because in emacs it is very hard just to insert a single
  BOM, muliple ones are inserted by default.
  This also outputs a message to discourage people from using BOMs at all.
*/
void Lexer::bomTrim(string&str){
  while(str.size()>=3&&
	str[0]==UnicodeBOMString[0]&&
	str[1]==UnicodeBOMString[1]&&
	str[2]==UnicodeBOMString[2]){
    cout<<"Lexer: ignoring prefixed byte-order marker\n";
    str=str.substr(3);
  }
}
 
PieceDeclarationToken* Lexer::match_piecedeclarationtoken(){
  int x=save();
  if(!(match_string("[Aa]")
       ||match_uvalue(UnicodePiece)))
    {restore(x); return NULL;}
  int y=save();
  if(!match_squarespecifier().empty()){
    restore(x); return NULL;}
  if(match_id()!=NULL){
    restore(y);
    return new PieceDeclarationToken();
  }
  restore(x);
  return NULL;
}
