#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "node.h"
#include "cqlthread.h"
#include "uchar.h"
#include "converttoascii.h"
#include "converttounicode.h"
#include "converttoecho.h"
#include "converttocolorize.h"
#include "converttoexternal.h"
bool matchoption(const string&, const string&);
void printhelp();
#ifndef CQL6_EMBEDDED // scidb: do not compile main() in embedded library
int main(int argc, char*argv[]){
  cql_initialize();
  if (!(argc>1&&
	("-colorize"s==argv[1]||
	 "--colorize"s==argv[1])))
    printf("CQL version %s (build %s %s) (c) Gady Costeff and Lewis Stiller\n",
	   CqlVersion,
	   CqlBuild,
	   CqlOptimizeLevel);
    
  parseargs(argc,argv);
  uassert(CqlFilename,"Main: could not access the cql file, unexpected NULL");
  cql_execute(CqlFilename,CqlNumberThreads);
  if(CqlGui)printf("\n%s\n",CqlGuiNormalExit);
  return 0;
}
#endif

	      
	
#ifndef CQL6_EMBEDDED // scidb: command-line parsing (and its exit()/cql_exit() paths) is
                     // only reachable from main(), which is not compiled into the library
void parseargs(int argc, char*argv[]){
  //string arguments shadowing the global const char * arguments in cqlglobal
  string inputfile; // --input , 
  string outputfile; // --output
  string cqlfile; // the CQL file
  string player; // the global player
  string matchstring="CQL";
  CqlNumberThreads=cql_compute_number_threads();
  int nextarg=0;
  if(argc==1){
    printhelp();
    exit(0);
  }
  while (++nextarg<argc){
    if (argv[nextarg]==NULL) break;
    string current(argv[nextarg]);
    if(current.empty()) break;
    else if (matchoption(current,"d")||
	     matchoption(current,"debug"))
      CqlDebug=1;
    else if (matchoption(current,"parse")){
      CqlParseOnly=true;
      CqlShowParse=true;
      CqlShowLex=true;
      CqlDebug=true;
    }
    else if (matchoption(current,"version")||matchoption(current,"v"))
      cql_exit(0);
    else if (matchoption(current,"matchstring")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing matchstring argument");
      matchstring=argv[nextarg];
      CqlMatchStringSet=true;
    }
    else if (matchoption(current,"noheader") ||matchoption(current,"noheaders")){
      CqlCommentHeader=false;
    }
    else if (matchoption(current,"showfromstring"))
      CqlShowFromString=true;
    else if (matchoption(current,"alwayscomment"))
      CqlSmartComments=false;
    else if (matchoption(current,"similarposition")){
      bool isnotransform{false};
      bool isnosort{false};
      while(true){
	++nextarg;
	eassert(nextarg<argc&&argv[nextarg],"command line: missing argument after '-similarposition'. Expected a pgn file, e.g. \n     'cql -similarposition submissions.pgn -input hhdbvi.pgn'");
	string arg=argv[nextarg];
	if(arg=="nosort")
	  isnosort=true;
	else if(arg=="notransform")
	  isnotransform=true;
	else break;
      }
      eassert(nextarg<argc&&argv[nextarg],"command line: missing argument after '-similarposition'. Expected a pgn file, e.g. \n     'cql -similarposition submissions.pgn -input hhdbvi.pgn'");
      string aname=argv[nextarg];
      if(!filename_is_pgn(aname))
	eassert(false,"invalid command line argument after '-similarposition'. Expected a .pgn file, e.g. \n     'cql -similarposition submissions.pgn -input hhdbvi.pgn'");
      stringstream s;
      s<<"similarposition";
      if(isnosort) s<<" nosort";
      if(isnotransform) s<<" notransform";
      s<<" \""<<aname<<"\"";
      CqlPreambleStrings->push_back(s.str());
    }
    else if (matchoption(current,"assign")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"Cql command line: missing argument after '-assign'");
      string id=argv[nextarg];
      eassert(id.size(),"invalid zero id length following -assign");
      for (char c:id) if (!(
			    c>='a'&&c<='z'
			    ||c>='A'&&c<='Z'
			    ||c>='0'&&c<='9'
			    ||c=='_'
			    || c=='$'))
			eassert(false,"expected name of ID following '-assign' but got invalid id: ",id);
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"Cql command line: missing assignment value following '-assign '",id);
      string value=argv[nextarg];
      int numvalue=0;
      stringstream s;
      s<<id << '=';
      if (util::intValue(value,&numvalue))
	s<<numvalue;
      else (s<<'\"'<<value<<'\"');
      CqlPreambleStrings->push_back(s.str());
    }//matchoption(current,"assign");
    
    else if (matchoption(current,"showMatches")){
      CqlShowMatches=true;
      CqlShowOutput=true;
      if(CqlLineIncrementOutput==0)
	CqlLineIncrementOutput=10000;
    }
    else if (matchoption(current,"variations")||
	     matchoption(current,"variations")){
      CqlSearchVariationsCommandLineSet=true;
      CqlSearchVariations=true;
    }
    else if (matchoption(current,"hhdb")){
      hhdb_parse_option(nextarg, argc, argv);
    }
    else if (matchoption(current,"cql")){
      ++nextarg;
      eassert(nextarg<argc,"Missing filter following '--cql'");
      current=argv[nextarg];
      eassert(current.size(),"empty filter following '--cql'");
      /* delete the __ escaping per Gamble suggestion. See backup-9-239/cql.cpp for original*/
      stringstream filterstream;
      filterstream<<'{'<<current<<'\n'<<'}'; //the \n is added so that ' cql -cql "///foo" bar.cql ' works 
      CqlPreambleStrings->push_back(filterstream.str());
    }
    else if (matchoption(current,"flip"))
      CqlPreambleTransforms->push_back("flip");
    else if (matchoption(current,"flipcolor"))
      CqlPreambleTransforms->push_back("flipcolor");
    else if (matchoption(current,"flipvertical"))
      CqlPreambleTransforms->push_back("flipvertical");
    else if (matchoption(current,"fliphorizontal"))
      CqlPreambleTransforms->push_back("fliphorizontal");
    else if (matchoption(current,"shift"))
      CqlPreambleTransforms->push_back("shift");
    else if (matchoption(current,"shifthorizontal"))
      CqlPreambleTransforms->push_back("shifthorizontal");
    else if (matchoption(current,"shiftvertical"))
      CqlPreambleTransforms->push_back("shiftvertical");
    else if (matchoption(current,"rotate90"))
      CqlPreambleTransforms->push_back("rotate90");
    else if (matchoption(current,"rotate45"))
      CqlPreambleTransforms->push_back("rotate45");
    else if (matchoption(current,"reversecolor"))
      CqlPreambleTransforms->push_back("reversecolor");
    else if (matchoption(current,"mainline")){
      CqlSearchVariationsCommandLineSet=true;
      CqlSearchVariations=false;
    }
    else if (matchoption(current,"virtualmainline")){
      CqlPreambleStrings->push_back("virtualmainline");
      CqlSearchVariationsCommandLineSet=true;
      CqlSearchVariations=true;
    }
    else if (matchoption(current,"fen")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing fen string");
      current=argv[nextarg];
      eassert(current.size(),"empty fen argument in command line");
      eassert(current[0]!='"',"fen command line argument unexpectedly starts with a quotation mark");
      stringstream filterstream;
      filterstream<<"fen "<<'"'<<current<<'"';
      CqlPreambleStrings->push_back(filterstream.str());
    }
    else if (matchoption(current,"event")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing event string");
      current=argv[nextarg];
      eassert(current.size(),"empty event argument in command line");
      stringstream filterstream;
      filterstream<<"event "<<'"'<<current<<'"';
      CqlPreambleStrings->push_back(filterstream.str());
    }
    else if (matchoption(current,"site")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing site string");
      current=argv[nextarg];
      eassert(current.size(),"empty site argument in command line");
      stringstream filterstream;
      filterstream<<"site "<<'"'<<current<<'"';
      CqlPreambleStrings->push_back(filterstream.str());
    }
    else if (matchoption(current,"result")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing result string");
      current=argv[nextarg];
      eassert(current.size(),"empty result argument in command line");
      if (current!="1-0"&&current!="1/2-1/2"&&current!="0-1")
	eassert(false,"Invalid argument to '-result'. Must be '1-0' or '0-1' or '1/2-1/2'. Got: ",current);
      stringstream filterstream;
      filterstream<<"result "<<'"'<<current<<'"';
      CqlPreambleStrings->push_back(filterstream.str());
    }
    else if (matchoption(current,"white")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing WHITE field following -white");
      current=argv[nextarg];
      eassert(current.size(),"empty WHITE field argument in command line");
      stringstream filterstream;
      filterstream<<"player white ~~ "<<'"'<<current<<'"';
      CqlPreambleStrings->push_back(filterstream.str());
    }
    else if (matchoption(current,"black")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing BLACK field following -black");
      current=argv[nextarg];
      eassert(current.size(),"empty BLACK field argument in command line");
      stringstream filterstream;
      filterstream<<"player black ~~ "<<'"'<<current<<'"';
      CqlPreambleStrings->push_back(filterstream.str());
    }
    else if (matchoption(current,"wtm"))
      CqlPreambleStrings->push_back("wtm");
    else if (matchoption(current,"btm"))
      CqlPreambleStrings->push_back("btm");
    
    else if (matchoption(current,"showOutput")){
      CqlShowOutput=true;
      if(CqlLineIncrementOutput==0)
	CqlLineIncrementOutput=10000;
    }
    else if (matchoption(current,"showThread")){
      CqlShowThread=true;
      CqlShowOutput=true;
    }
    else if (matchoption(current,"lineIncrement")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing lineIncrement value");
      int inc=0;
      current=argv[nextarg];
      eassert(current.size(),"missing lineIncrement value");
      if(!util::positiveIntValue(current,&inc))
	eassert(false,"CQL command line: expected positive integer following --lineIncrement");
      uassert(inc>0,"CQL command line internal");
      CqlLineIncrementOutput=inc;
      CqlShowOutput=true;
    }
    else if (matchoption(current,"lex")){
      CqlLexOnly=true;
      CqlShowLex=true;
      CqlDebug=true;
    }
    else if (matchoption(current,"echo")){
      ++nextarg;
      eassert(nextarg==2,"command line arguments preceded --echo, which must be the first argument on the command line");
      eassert(nextarg<argc,"CQL command line: missing convert file argument");
      eassert(argv[nextarg],"bad input in convert file argument to command line");
      string convertfile=argv[nextarg];
      eassert(filename_is_cql(convertfile),
	      "filename argument to --echo did not have a '.cql' extension: ",
	      convertfile);
      ++nextarg;
      eassert(nextarg==argc,"extra arguments on command line following '--echo' ",convertfile);
      ConvertToEcho::fromCqlFile(convertfile);
      cql_exit();
    }
    else if (matchoption(current,"colorize")){
      ++nextarg;
      eassert(nextarg==argc,"-colorize must be the only option");
      cout<<ConvertToColorize::convert();
      exit(0);
    }
    else if (matchoption(current,"a")){
      ++nextarg;
      eassert(nextarg==2,"command line arguments preceded --a, which must be the first argument on the command line: 'cql --a filename.cql'");
      eassert(nextarg<argc,"CQL command line: missing name of file to convert from unicode following '--u' option");
      eassert(argv[nextarg],"bad input in convert to ascii file argument to command line");
      string convertfile=argv[nextarg];
      eassert(filename_is_cql(convertfile),
	      "filename after '--a ' is not a .cql file");
      ConvertToAscii::fromCqlFileToFile(convertfile,convertfile);
      cql_exit();
    }      
    else if (matchoption(current,"u")){
      ++nextarg;
      eassert(nextarg==2,"command line arguments preceded --u, which must be the first argument on the command line: 'cql --u filename.cql'");
      eassert(nextarg<argc,"CQL command line: missing name of file to convert to unicode following '--u' option");
      eassert(argv[nextarg],"bad input in convert file argument to command line");
      string convertfile=argv[nextarg];
      eassert(filename_is_cql(convertfile),
	      "filename after '--u ' is not a .cql file");
      ConvertToUnicode::fromCqlFileToFile(convertfile,convertfile);
      cql_exit();
    }      
    else if (matchoption(current,"html")){
      ++nextarg;
      eassert(nextarg==2,"command line arguments preceded --html, which must be the first argument on the command line: 'cql --html filename.cql'");
      eassert(nextarg<argc,"CQL command line: missing name of file to convert to unicode following '--html' option");
      eassert(argv[nextarg],"bad input in convert file argument to command line");
      string convertfile=argv[nextarg];
      eassert(filename_is_cql(convertfile),
	      "filename after '--u ' is not a .cql file");
      ConvertToExternal::exporthtml(convertfile);
      cql_exit();
    }      
    else if (matchoption(current,"utf8")){
      string converttofile="";
      string convertfromfile="";
      ++nextarg;
      eassert(nextarg==2,"command line arguments preceded --utf8, which must be the first argument on the command line");
      eassert(nextarg<argc,"CQL command line: missing convert file argument");
      eassert(argv[nextarg],"bad input in convert file argument to command line");
      convertfromfile=argv[nextarg];
      eassert(filename_is_cql(convertfromfile),
	      "filename argument to --utf8 did not have a '.cql' extension: ",
	      convertfromfile);
      ++nextarg;
      if(nextarg<argc){
	if("-o"s != argv[nextarg])
	  eassert("-o"s==argv[nextarg],"expected '-o' argument on command line following '-utf8 filename.cql'");
	++nextarg;
	eassert(nextarg<argc,"missing parameter following '-utf8 filename.cql -o' on command line");
	converttofile=argv[nextarg];
	eassert(filename_is_cql(converttofile),
		"output filename after '-utf8 filename.cql -o file' is not a .cql file");
	++nextarg;
      }
      eassert(nextarg==argc,"extra arguments on command line following '--utf8' ",convertfromfile);
      ConvertToUnicode::fromCqlFileToFile(convertfromfile,converttofile);
      cql_exit();
    }
    else if (matchoption(current,"nooutputstatus")){
      CqlShowOutput=false;
    }
    else if (matchoption(current,"i")||
	     matchoption(current,"input")){
      if(CqlPgnStdin)
	eassert(false,"-input specified with -guistdin");
      ++nextarg;
      eassert(nextarg<argc,"CQL command line: missing input file argument");
      eassert(argv[nextarg],"bad command line arg after input file");
      eassert(inputfile.empty(),"Multiple input files on command line");
      inputfile=argv[nextarg];
      eassert(filename_is_pgn(inputfile),"invalid pgn input filename from command line", inputfile);
    }
    else if (matchoption(current,"vi")){
      if (CqlPgnStdin)
	eassert(false, "-vi specified with -guistdin");
      eassert(inputfile.empty(),"The '-vi' command line option was specified but another -input option was already encountered");
      inputfile="hhdbvi.pgn";
    }
    else if (matchoption(current,"vii")){
      if (CqlPgnStdin)
	eassert(false, "-vii specified with -guistdin");
      eassert(inputfile.empty(),"The '-vii' command line option was specified but another -input option was already encountered");
      inputfile="hhdbvii.pgn";
    }
    else if (matchoption(current,"nolinearize"))
      CqlDoNotLinearize=true;
    else if (matchoption(current,"nosortcomments"))
      CqlSortComments=false;
    else if (matchoption(current,"uniquecomments"))
      CqlUniqueComments=true;
    else if (matchoption(current,"nouniquecomments"))
      CqlUniqueComments=false;
    else if (matchoption(current,"output")||
	     matchoption(current,"o")){
      if(CqlPgnStdout)
	eassert(false,"-output specified with -guistdout");
      ++nextarg;
      eassert(nextarg<argc,"CQL command line: missing output file argument");
      eassert(argv[nextarg],"bad input in outputfile");
      eassert(outputfile.empty(),"multiple output files on command line");
      outputfile=argv[nextarg];
      eassert(outputfile.size(),"missing output file");
      eassert(filename_is_pgn(outputfile),"bad output filename from command line", outputfile);
    }
    else if (matchoption(current,"player")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing player argument");
      eassert(player.empty()," already saw a player, cannot have two --player options: ", player);
      player=argv[nextarg];
      uassert(player.size(),"missing player");
    }
    else if (matchoption(current,"g")||
	     matchoption(current,"gamenumber")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing gamenumber");
      int gamestart=0;
      int gamestop=0;
      current=argv[nextarg];
      eassert(current.size(),"missing game number");
      if (!util::positiveIntValue(current,&gamestart))
	eassert(false,"expected positive integer following -g or --gamenumber");
      eassert(gamestart>0,"internal");
      if(nextarg+1<argc){
	eassert(argv[nextarg+1],"unknown after game number");
	current=argv[nextarg+1];
	if(util::positiveIntValue(current,&gamestop))
	  nextarg++;
      }
      if (gamestop==0) gamestop=gamestart;
      CqlGameNumberRange=new Range(gamestart,gamestop);
    }
    else if (matchoption(current,"matchcount")){
	++nextarg;
	eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing matchcount");
	int matchstart= -1;
	int matchstop= -1;
	current=argv[nextarg];
	eassert(current.size(),"missing matchcount range");
	if (!util::nonnegativeIntValue(current,&matchstart))
	  eassert(false,"expected  integer following --matchcount");
	eassert(matchstart>=0,"matchcount range must be positive");
	if(nextarg+1<argc){
	  eassert(argv[nextarg+1],"unknown or missing argument after matchcount range");
	  current=argv[nextarg+1];
	  if(util::nonnegativeIntValue(current,&matchstop)){
	    nextarg++;
	    eassert(matchstop>=0,"second argument to matchcount must be nonnegative");
	  }
	}
	if (matchstop<0) matchstop=matchstart;
	eassert(matchstart<=matchstop,"Invalid range to matchcount at command line");
	CqlMatchCountRange=new Range(matchstart,matchstop);
      }
    else if (matchoption(current,"outputbuffer")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing -outputbuffer size");
      int outputbuffersize=0;
      current=argv[nextarg];
      if(!util::positiveIntValue(current,&outputbuffersize))
	eassert(false,"expected positive integer following --outputbuffer");
      if (outputbuffersize<=100000 || outputbuffersize > 100000000)
	eassert(false, "outputbuffersize is out of range [100000 100000000]");
      CqlPgnOutputBufferSize = outputbuffersize;
    }
    else if (matchoption(current,"threads")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing threads count");
      int nthreads=0;
      current=argv[nextarg];
      if (!util::positiveIntValue(current,&nthreads))
	eassert(false,"expected positive integer following --threads");
      CqlNumberThreads=nthreads;
    }
    else if (matchoption(current,"gui")){
      CqlGui=true;
      printf("%s version %s\n",CqlGuiVariable,CqlVersion);
      printf("%s build %s\n",CqlGuiVariable,CqlBuild);
    }
    else if (matchoption (current,"guipgnstdin")){
      if(CqlPgnStdin || inputfile.size())
	eassert(false,"-guistdin specified but there is already a defined -guistdin or -input");
      CqlPgnStdin=true;
    }
    else if (matchoption (current,"guipgnstdout")){
      if(CqlPgnStdout || outputfile.size())
	eassert(false,"-guipgnstdout specified but there is already a defined -guipgnstdout or -output");
      CqlPgnStdout=true;
    }
    else if (matchoption(current,"noremovecomment"))
      CqlNoRemoveComment=true;
    else if (matchoption(current,"year")){
      ++nextarg;
      eassert(nextarg<argc&&argv[nextarg],"CQL command line: missing year");
      current=argv[nextarg];
      int yearstart=0;
      int yearstop=0;
      if (!util::positiveIntValue(current,&yearstart))
	eassert(false,"expected positive integer following --year");
      eassert(yearstart>0,"internal");
      if(nextarg+1<argc&&
	 argv[nextarg+1]){
	current=argv[nextarg+1];
	if(util::positiveIntValue(current,&yearstop))
	  nextarg++;
      }
      if (yearstop==0) yearstop=yearstart;
      CqlYearRange=new Range(yearstart,yearstop);
    }
    else if (matchoption(current,"silent")){
      eassert(CqlCommentLevel==CommentLevel::Unspecified,
	      "command line option '-silent' specified but comment level already specified");
      CqlCommentLevel=CommentLevel::Silent;
    }
    else if (matchoption(current,"quiet")){
      eassert(CqlCommentLevel==CommentLevel::Unspecified,
	      "command line option '-quiet' specified but comment level already specified");
      CqlCommentLevel=CommentLevel::Quiet;
    }
    else if (matchoption(current,"nosettag"))
      CqlNoSetTag=true;
    else if (matchoption(current,"h")||
	     matchoption(current,"help")){
      printhelp();
      exit(0);
    }
    else if (matchoption(current,"m") ||
	     matchoption(current,"multithreaded")){
      CqlNumberThreads=cql_compute_number_threads();
    }
    else if (matchoption(current,"s") ||
	     matchoption(current,"singlethreaded")){
      CqlNumberThreads=1;
    }
    else if (current.at(0)=='-'){
      fprintf(stderr, "CQL: invalid option: %s. Printing help: \n",current.c_str());
      printhelp();
      exit(1);
    }
    else{
      eassert(cqlfile.empty(),"cql command line: got two CQL filenames");
      cqlfile=current;
      if(filename_extension(cqlfile).empty())
	cqlfile += ".cql";
      eassert(filename_is_cql(cqlfile),
	      "CQL file must have extension .cql or .CQL, if it has an extension. Invalid CQL filename: ",current);
      eassert(nextarg==argc-1,"The CQL filename must be the last argument on the command line: ", current);
      break;
    }
  }//while(++nextarg<argc)
  if(cqlfile.empty()){
    eassert(CqlPgnStdin || inputfile.size(),"Missing CQL file on command line and no PGN input file either");
    cqlfile="cqldefault.cql";
  }
  setCqlGlobal(CqlFilename,cqlfile);
  setCqlGlobal(CqlPgnFilename,inputfile);
  setCqlGlobal(CqlPlayer,player);
  setCqlGlobal(CqlOutputFilename,outputfile);
  setCqlGlobal(CqlMatchString,matchstring);
}

bool matchoption(const string& arg, const string& option){
  int substart=0;
  if(arg.empty())return false;
  if(arg.size()==1)return false;
  if(arg.size()>=2 && arg[0]=='-'&&arg[1]=='-') substart+=2;
  else if(arg[0]=='-') substart++;
  else return false;
  uassert(substart==1||substart==2,"matchoption internal");
  string narg=arg.substr(substart);
  return util::downcase(narg)==util::downcase(option);
}



void printhelp(){
  printf("CQL usage: cql options filename\n");
  printf(" the 'filename' above should be a file with extension '.cql'. The allowed options are:\n");
  printf("-a x.cql: convert x.cql to ASCII\n");
  printf("-black playername: playername has Black\n");
  printf("-cql filter: only positions matching filter (or filters)\n");
  printf("-event eventname: event field in PGN has eventname as substring\n");
  printf("-fen fen_string: restrict to specified fen board\n");
  printf("-flip: flip following filters\n");
  printf("-flipcolor: flipcolor following filters\n");
  printf("-gamenumber number or -gamenumber number number to specify the range of games to search (-g abbreviates)\n");
  printf("-help: print this message\n");
  printf("-hhdb: arguments to 'hhdb' (Heijden database VI) follow. Use '-hhdb help' for help\n");
  printf("-html x.cql: create x-cql.html, an HTML file that renders x.cql\n");
  printf("-input inputfile.pgn: read games from inputfile.pgn\n");
  printf("-lineincrement value: print message after every value games parsed\n");
  printf("-mainline: search only in the mainline\n");
  printf("-matchstring 'comment': comment 'comment' when match occurs (default 'CQL')\n");
  printf("-noheader: do not comment game header information, like game number\n");
  printf("-noremovecomment: ignore removecomment filters\n");
  printf("-nosettag: do not modify tags\n");
  printf("-output outputfile.pgn: write output to outputfile.pgn\n");
  printf("-parse: parse only, do not run [not supported]\n");
  printf("-player playername: restrict output to given playername\n");
  printf("-quiet: only print explicit user comments\n");
  printf("-result resultstring: results must be of specified kind, either 1-0 or 0-1 or 1/2-1/2\n");
  printf("-reversecolor: reverse the colors\n");
  printf("-shift: shift following filters\n");
  printf("-similarposition submission.pgn: check each position in submission.pgn to see if it matches current position\n");
  printf("-singlethreaded or -s: run single-threaded\n");
  printf("-site locationname: site field in PGN has locationname as substring\n");
  printf("-showmatches: print the game number of each match as it occurs\n");
  printf("-silent: do not output new comments and do not modify tags\n");
  printf("-threads number: set the number of threads to number\n");
  printf("-u x.cql: convert x.cql from ASCII to Unicode");
  printf("-variations: search in both mainline and variations\n");
  printf("-version: print version information only\n");
  printf("-vi: set input file to hhdbvi.pgn\n");
  printf("-white playername: playername has White\n");
  printf("-year number or --year number number to restrict output to year in the given range\n");
}
#endif // CQL6_EMBEDDED
  
