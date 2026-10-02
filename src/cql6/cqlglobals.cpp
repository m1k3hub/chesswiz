#include "cqlglobals.h"
#include "abbreviations.h"
#include <map>
using std::set;

bool CqlDebug=false;
bool CqlParseOnly=false;
bool CqlShowParse=false;
bool CqlShowLex=false;
bool CqlEcho=false;
int CqlNumberThreads=0;
bool CqlLexOnly=false;
bool CqlCommentHeader=false;
const char* CqlMatchString=NULL;
bool CqlMatchStringSet=false;
int CqlLineIncrementOutput=0;
bool CqlRunningThreads=false;
bool CqlPgnStdin=false; 
bool CqlPgnStdout=false; 
bool CqlShowThread=false;
bool CqlShowMatches=false;
bool CqlSearchVariations=false;
bool CqlSortComments=true;
bool CqlSearchVariationsCommandLineSet=false;
bool CqlUniqueComments=true;
bool CqlIsExiting=false;
#ifdef CQL6_EMBEDDED
thread_local CommentLevel CqlCommentLevel=CommentLevel::Unspecified;
#else
CommentLevel CqlCommentLevel=CommentLevel::Unspecified;
#endif
bool CqlUsePgnSourceAlways=true; //modified 1/27/2019
bool CqlShowOutput=false; //modified by initialize
const char* CqlFilename=0;
const char* CqlPgnFilename=0;
const char* CqlOutputFilename=0;
Range* CqlGameNumberRange=0;
Range* CqlMatchCountRange=0;
Range* CqlYearRange=0;
int CqlThreadPlyMax=70; //max number of ply to search for in a thread
const char* CqlPlayer=0;
int MarkBoard_gameAppendComment_lastignored=-1; //must be initialized to -1
int Tokens_nextid=0; // the next valid id to use if no name specified by numeric
Tokens* CqlGlobalTokens=0; //the list of tokens that have been read
CqlNode* CqlParseRoot=0; //The most recently read CQL parse tree;
bool CqlDoNotLinearize=false;
bool CqlFixNestedComments=true; //only for parallel mode
bool CqlSmartComments=true;
std::vector<string>*CqlPreambleStrings=NULL;
std::vector<string>*CqlPreambleTransforms=NULL;
const char *CqlGuiMessageStart;
const char* CqlGuiMessageStop;
const char* CqlGuiVariable;
const char* CqlGuiErrorStart;
const char* CqlGuiErrorStop;
const char* CqlGuiNormalExit;
bool CqlGui;
int CqlPgnOutputBufferSize;
bool CqlShowFromString=false;
bool CqlNoRemoveComment=false;
bool CqlNoSetTag=false;
int CqlLastGameNumber=0;
#ifdef CQL6_EMBEDDED // scidb: test hook definition
void (*CqlTestAssertHook)(int gameNumber, int threadIndex) = nullptr;
#endif

void cqlglobals_initialize(){
  CqlGuiMessageStart="<CqlGuiMessage>";
  CqlGuiMessageStop="</CqlGuiMessage>";
  CqlGuiVariable="<CqlGuiVariable>";
  CqlGuiErrorStart="<CqlGuiError>";
  CqlGuiErrorStop="</CqlGuiError>";
  CqlGuiNormalExit="<CqlGuiNormalExit>";
  CqlGui=false;
  CqlDebug=false;
  CqlParseOnly=false;
  CqlLexOnly=false;
  CqlShowParse=false;
  CqlCommentLevel=CommentLevel::Unspecified;
  CqlShowLex=false;
  CqlSortComments=true;
  CqlShowOutput=true;
  CqlShowMatches=false;
  CqlSmartComments=true;
  CqlMatchString=NULL;
  CqlCommentHeader=true;
  CqlShowThread=false;
  CqlLineIncrementOutput=10000;
  CqlSearchVariations=false;
  CqlSearchVariationsCommandLineSet=false;
  CqlFilename=0;
  CqlUniqueComments=true;
  CqlPgnFilename=0;
  CqlOutputFilename=0;
  CqlGameNumberRange=0;
  CqlMatchCountRange=0;
  CqlYearRange=0;
  CqlNumberThreads=0;
  CqlPlayer=0;
  MarkBoard_gameAppendComment_lastignored=-1; //must be initialized to -1
  Tokens_nextid=0; // the next valid id to use if no name specified by numeric
  CqlParseRoot=0; //The most recently read CQL parse tree;
  CqlDoNotLinearize=false;
  if (!CqlPreambleStrings) // scidb: prevent leak on repeated calls
    CqlPreambleStrings=new std::vector<string>;
  else
    CqlPreambleStrings->clear();
  if (!CqlPreambleTransforms)
    CqlPreambleTransforms=new std::vector<string>;
  else
    CqlPreambleTransforms->clear();
  CqlShowFromString=false; //print arguments to Tokens::node_from_string() in tokens.cpp
  CqlPgnOutputBufferSize= 105000; //the default size for the TextBuffer used in util::game_to_string() in util.cpp per request Lionel
  CqlIsExiting=false;
#ifdef CQL6_EMBEDDED // scidb: reset hook
  CqlTestAssertHook = nullptr;
#endif
}

void setCqlGlobal(const char * & global, string name){
#ifdef CQL6_EMBEDDED // scidb: bounded storage instead of a leaked string per header
  static std::map<const char**, string> values;
  string& value = values[&global];
  value = name;
  global = value.empty() ? nullptr : value.c_str();
#else
  if(name.size())
    global=(new string(name))->c_str();
  else
    global=NULL;
#endif
}

string getCqlGlobal(const char * & global){
  if (global==NULL) return "";
  return string(global);
}


