#include "uchar.h"
#include "cqlassert.h"
#include "util.h"
#include "lexer.h"
#include "uchar-strings.h"
#include <cctype> //needed for isgraph() per Microsoft
int left2bits(int by){
  return (by&0b11000000)>>6;
}
int left3bits(int by){
  return (by&0b11100000)>>5;
}
int left4bits(int by){
  return (by&0b11110000)>>4;
}
int left5bits(int by){
  return (by&0b11111000)>>3;
}
int right6bits(int by){
  return by&0b00111111;
}
int right5bits(int by){
  return by&0b00011111;
}
int right4bits(int by){
  return by&0b0001111;
}
int right3bits(int by){
  return by&0b00000111;
}

void UChar::printChar(char c){
  if(c=='\n')
    printf("\\n");
  else if(c==' ')
    printf("[ ]");
  else if (c=='\t')
    printf("\\t");
  else if (c=='\r')
    printf("\\r");
  else if (c==0)
    printf("\\0");
  else if (c=='\f')
    printf("\\f");
  else if (c=='\v')
    printf("\\v");
  else if (c=='\'')
    printf("\\'");
  else if (c=='\"')
    printf("\"");
  else if(std::isgraph(c))
    printf("'%c'",c);
  else
    printf("%2x ",UChar::char2int(c));
}
  

/*create a UChar from a string of bytes of the correct size.*/
/*use the diagram at https://en.wikipedia.org/wiki/UTF-8 
(which is why the first byte is byte1 and not byte0) */

UChar::UChar(string bytes){
  int len=(int)(bytes.size());
  uassert(len==1||
	  len==2||
	  len==3||
	  len==4,"UChar: invalid input in constructor from bytes");
  int byte1=char2int(bytes[0]);
  int byte2{0},byte3{0},byte4{0};
  if(byte1<=0x7F){
    theValue=(int)byte1;
    uassert(theValue>=0,"badv1");
    return;
  }
  if(len<=1){
    errorMessage="not enough characters: expected more than 1 character";
    return;
  }
  uassert(len>1,"internal error UChar len");
  byte2=char2int(bytes[1]);
  if(left2bits(byte2)!=0b10u){
    errorMessage="no '10' on byte2";
    return;
  }
  if(left3bits(byte1)==0b110){
    theValue=(right5bits(byte1)<<6)|right6bits(byte2);
    return;
  }
  if(len<3){
    errorMessage="expected at least 3 bytes";
    return;
  }
  byte3=char2int(bytes[2]);
  if(0){
    printf("UChar constructor got byte 3 of %#x and left 2 bits of: %#x\n",byte3,left2bits(byte3));
  }
  if(left2bits(byte3)!=0b10){
    errorMessage="expected 10 prefix in byte 3";
    return;
  }
  if(left4bits(byte1)==0b1110){
    theValue=
      (right4bits(byte1)<<12)
      | (right6bits(byte2) << 6)
      | right6bits(byte3);
    return;
  }
  if(len<4){
    errorMessage="expected at least 4 bytes";
    return;
  }
  if(left5bits(byte1)!=0b11110){
    errorMessage="expected 0b1110 prefix at first byte";
    return;
  }
  byte4=char2int(bytes[3]);
  if(left2bits(byte4)!=0b10){
    errorMessage="expected 0b10 prefix at fourth byte";
    return;
  }
  theValue=
    (right3bits(byte1)<<18)
    |(right6bits(byte2)<<12)
    |(right6bits(byte3)<<6)
    |right6bits(byte4);
}    

void UChar::convertEchoFile(string filename){
  cout<<"convertEchoFile: reading file: "<<filename<<endl;
  string contents=util::string_from_filename(filename);
  int filesize=(int)contents.size();
  if(filesize<=0){
    cout<<"cannot read empty or invalid file: "<<filename<<endl;
    cout<<"exiting with no change\n";
    cql_exit();
  }
    
  cout<<"echoFile: read "<<filesize<<" bytes from: "<<filename<<endl;

  string echo=Lexer::convertEchoString(contents);
  cout<<"echoFile: obtained "<<echo.size()<<" bytes from "<<filename<< ": "<<endl;
  cout<<echo;
}
  

void UChar::echoFile(string filename){
  cout<<"echoFile: reading file: "<<filename<<endl;
  string contents=util::string_from_filename(filename);
  int filesize=(int)(contents.size());
  cout<<"echoFile: read "<<filesize<<" bytes"<<endl;
  int offset=0;
  int lineno=1;
  int column=1;
  printf("line col offst codept 0xchars name\n");
  while(offset<filesize){
    if(contents[offset]=='\n'){
      lineno++;
      column=1;
    }
    UChar u=parse(contents,offset);
    if(!u.isValid())
      printf("Invalid unicode character. Error message is: %s\n",u.errorMessage.c_str());
    printf("%3d %2d %3d U+%-4x ",lineno, column,offset,u.getValue());
    if(!u.isValid()){
      printf("\n");
      cql_exit();
    }
    stringstream s; //the actual string, for testing
    for(int i=0;i<u.size();++i){
      char c= contents[offset++];
      s<<c;
      printChar(c);
    }
    string n=u.name();
    if(n.size())
      printf(" %s",n.c_str());
    string truestring=s.str();
    string teststring=u.toString();
    if(truestring!=teststring){
      cout<<"internal failure of toString test"
	  <<endl<<" got toString() string of: "
	  <<teststring
	  <<" which failed to match"<<endl;
	cql_exit();
    }
    printf("\n");
    column++;
  }
}

UChar UChar::parse(string buff, int offset){
  int sz=(int)(buff.size());
  uassert(offset<sz,"uchar bad offset");
  char c=buff[offset];
  if(0)printf("UChar::parse: called with string: %s and offset: %d to get char: %c\n",buff.c_str(),offset,c);
  int first=char2int(c);
  if(0)printf("UChar::parse: got first of: %d\n",first);
  int len=0;
  if(first<=0x007F) len=1;
  else if (left3bits(first)==0b110) len=2;
  else if (left4bits(first)==0b1110) len=3;
  else if (left5bits(first)==0b11110) len=4;
  else {
    printf("UChar::parse: error on hex first of: %x\n",first);
    printf("left3bits(first): %x\n",left3bits(first));
    printf("left4bits(first): %x\n",left4bits(first));
    printf("left5bits(first): %x\n",left5bits(first));
    printf("0b110 is: %x\n",0b110);
    uassert(false,"UChar: invalid first");
  }
  if(0)
    printf("UChar: for first of: %x got len of: %d\n",first,len);
  string arg=buff.substr(offset,len); //an error message will be returned if necessary but the constructor
  return UChar(arg);
}
	  
int UChar::char2int(char c){
  int ret= (int)(unsigned int)(unsigned char)c;
  uassert(ret>=0&&ret<=255,"char2int: bad char");
  if(0)printf("char2int: got char of: %c and returning int of: decimal %d and hex: %x\n",c,ret,ret);
  return ret;
}

int UChar::size()const{
  int v=theValue;
  uassert(v>=0,"invalid unicode character in size");
  uassert(v>0,"unexpected null value in size() of unicode character");
  if(v<=0x7F)return 1;
  if(v<=0x7FF)return 2;
  if(v<=0xFFFF)return 3;
  if(v<=0x10FFFF)return 4;
  uassert(false,"value to large in unicode character");
  return -1;
}
  
  
UChar::UChar(int v):theValue(v){
  if(theValue<=0||theValue>0x10FFFF){
    stringstream s;
    s<<"Attempt to create unicode character of invalid value: "<<theValue;
    uassert(false,s.str());
  }
}

string UChar::toString()const{
  uassert(isValid(),"UChar::toString: invalid unicode character");
  int v=theValue;
  uassert(v>=0,"UChar::toString: null or invalid unicode character");
  stringstream s;
  if(v<=0x007F){
    int byte1=v;
    s<<(char)byte1;
  }
  else if (v<=0x07FF){
    int high5bits=(v>>6)&0b11111;
    int low6bits=v&0b111111;
    int byte1=0b11000000|high5bits;
    int byte2=0b10000000|low6bits;
    s<<(char)byte1
     <<(char)byte2;
  }
  else if(v<=0xFFFF){
    int high4bits=(v>>12)&0b1111;
    int middle6bits=(v>>6)&0b111111;
    int low6bits=v&0b111111;
    int byte1=0b11100000|high4bits;
    int byte2=0b10000000|middle6bits;
    int byte3=0b10000000|low6bits;
    s<<(char)byte1
     <<(char)byte2
     <<(char)byte3;
  }
  else if(v<=0x10FFFF){
    if(0)
      printf("toString: Got v of: %x\n",v);
    int high3bits=(v>>18)&0b111;
    int third6bits=(v>>12)&0b111111;
    int second6bits=(v>>6)&0b111111;
    int low6bits=v&0b111111;
    int byte1=0b11110000|high3bits;
    int byte2=0b10000000|third6bits;
    int byte3=0b10000000|second6bits;
    int byte4=0b10000000|low6bits;
    s<<(char)byte1
     <<(char)byte2
     <<(char)byte3
     <<(char)byte4;
  }
  else{
    s<<"Cannot convert unicode character with apparent value of: "<<v
     <<" as the value is out of range";
    uassert(false,s.str());
  }
  return s.str();
}
  
      
  
void UChar::initialize(){
  stringstream s;
  test();
}
void UChar::test(){
  UChar uQ((int)UnicodePieces::Q);
  uassert(uQ.isValid(),"UChar: test: test failed on uQ construction");
  string uQstring=uQ.toString();
  uassert(uQ==UChar(uQstring),
	  "UChar::test failed on uQ test");
  stringstream s;
  for(int code:UnicodeDashCodes)
    s<<UChar(code);
  uassert(s.str()==UnicodeDashString,"test failed on Dash test for Unicode initialization check in UChar::test()");
}

string UChar::name()const{
  int v=getValue();
  auto&m=UnicodeNames;
  if(isInvalid())return "";
  if(m.find(v)==m.end())
    return "";
  return m.at(v);
}

string UChar::uname()const{
  uassert(isValid(),"unexpected invalid uchar at uname()");
  stringstream s;
  s<<"U+"<<std::uppercase<<std::hex<<getValue();
  return s.str();
}

std::ostream& operator<<(std::ostream&os,const UChar&u){
  uassert(u.isValid(),"cannot output invalid unicode character");
  return os<<u.toString();
}

bool UChar::isFigurine()const{
  return theValue>=(int)(UnicodePieces::Start)
    &&theValue<=(int)(UnicodePieces::Last);

}

vector<UChar>UChar::parseChars(const string& input){
  vector<UChar>ret;
  int len=(int)(input.size());
  int i=0;
  while(i<len){
    UChar uchar=parse(input,i);
    if(!uchar.isValid())
      uassert(false,"Invalid unicode character detected while parsing: "s+input);
    ret.push_back(uchar);
    i+=uchar.size();
  }
  if(i!=len)
    uassert(false,"length mismatch while parsing: "s+input);
  return ret;
}
    
    
