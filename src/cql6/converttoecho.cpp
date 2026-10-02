#include "converttoecho.h"
#include "cqlassert.h"
#include "util.h"
#include "uchar.h"

void ConvertToEcho::fromCqlFile(string filename){
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
    UChar u=UChar::parse(contents,offset);
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
      UChar::printChar(c);
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
