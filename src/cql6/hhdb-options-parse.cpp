#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "node.h"
#include "hhdbkeyword.h"
#ifndef CQL6_EMBEDDED // scidb: only reachable from parseargs()/main(), not from cql6_search;
                     // excludes its exit(0) from the embedded library
void hhdb_option_error(vector<string>args, string string1, string string2);

/*nextarg is the index of the current read args which should be "-hhdb"
  after running it should be set to the index of the last successfully read option
*/

void hhdb_parse_option(int&nextarg, int argc, char* argv[]){
  uassert(nextarg>= 0 && nextarg<argc, "hhdb_parse_option: bad nextarg");
  string current = argv[nextarg];
  uassert (current=="-hhdb"||current=="--hhdb", "hhdb_parse_option: expecting '-hhdb' here");
  vector<string> args;
  while(true){
    ++nextarg;
    if (nextarg>= argc) break;
    current=argv[nextarg];
    if(current=="info"||current=="help"){
      stringstream s;
      s<<"-hhdb introduces options passed to the hhdb filter for use with the Endgame Study Database HHdb VI\n"
       <<"For example 'cql -hhdb composer Kasparyian'\n"
       <<"See the CQL documentation for full documentation.\n"
       <<"Valid hhdb keywords are: \n"<<HhdbKeyword::showKeys()<<endl;
      printf("%s",s.str().c_str());
      exit(0);
    }
    if (!HhdbKeyword::isKey(current)) {
      --nextarg;
      break;
    }
    if (HhdbKeyword::isQuotedKey(current))
      args.push_back(string("") + "\""+current+"\"");
    else
      args.push_back(current);
    if (HhdbKeyword::takesParameterKey(current)){
      nextarg++;
      if (nextarg>=argc)
	hhdb_option_error(args, "Expecting parameter following hhdb parameter: ", args.back());
      current=argv[nextarg];
      if (current.empty())
	hhdb_option_error(args, "Empty parameter following hhdb parameter: ", args.back());
      args.push_back(string()+"\""+current+"\"");
      break;
    }
  }//while(true)
  if (args.empty()){
    stringstream s;
    s<<"No valid hhdb keywords were found following the '-hhdb' option\n"
     <<"Use 'cql -hhdb help' for more information on '-hhdb' option\n";
    eassert(false,s.str());
  }

  //Now all the hhdb arguments are in args, handle them.
    stringstream s;
    s<<"hhdb";
    for (string param : args)
      s<<" "<<param;
    if(0) printf("hhdb command line: got: %s\n", s.str().c_str());
    CqlPreambleStrings->push_back(s.str());
}


void hhdb_option_error(vector<string>args, string string1, string string2){
  stringstream s;
  s<<"Unable to parse 'hhdb' parameters at command line. After: reading 'hhdb";
  for (string arg:args)
    s<<' '<<arg;
  s<<"'";
  s<<" failed: "<<string1<<' '<<string2;
  eassert(false, s.str());
}
#endif // CQL6_EMBEDDED
