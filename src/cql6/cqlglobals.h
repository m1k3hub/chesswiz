#pragma once
/***** certain global variables to be reset.*////
/**the following are used to hold command line parameters. 
   These parameters override values specified in the cql file itself
   Most of these don't need to be global at all actually
*/
#include <set>
#include <string>
#include <vector>
#include "commentlevel.h"

class Range;
class Tokens;
class SequenceBase;
class CqlNode;

extern int  CqlPgnOutputBufferSize; //size for TextBuffer used in util::game_to_string() in util.cpp() per request Lionel 7/19/2020
#ifdef CQL6_EMBEDDED
extern thread_local CommentLevel CqlCommentLevel; // scidb: per-script worker setting
#else
extern CommentLevel CqlCommentLevel;
#endif
extern bool CqlDebug; // debugging, not used
extern bool CqlParseOnly; //show only the parse
extern bool CqlShowLex; // show the lex
extern bool CqlEcho; // output the Unicode input
extern bool CqlShowOutput; // show the status updates during match
extern bool CqlShowMatches; //whether to print the game numbers of matched games as they occur
extern int CqlLineIncrementOutput; // show status updates each time CqlLineIncrementOutput games, 0 if not used
extern bool CqlLexOnly; // show only the lex
extern bool CqlShowParse; // show the parse
extern bool CqlSearchVariations; // search the variations as well as the mainline
extern bool CqlSearchVariationsCommandLineSet; // true if CqlSearchVariations was set at the command line
extern const char* CqlFilename; // Where the .cql file is located
extern const char* CqlPgnFilename; //where the PGN file to be read is
extern const char* CqlOutputFilename; // where the PGN is output
extern Range* CqlGameNumberRange; //Use this gamenumberrange
extern Range* CqlMatchCountRange; //Use this matchcount
extern Range* CqlYearRange; // only search in these years
extern const char* CqlPlayer; //only look for this player
extern const char* CqlMatchString; //what to print when a match is found
extern bool CqlMatchStringSet;
extern bool  CqlCommentHeader; //whether to print header information
extern bool CqlDoNotLinearize; // whether to linearize move filters inside next filter
extern int CqlNumberThreads;
extern int CqlThreadPlyMax; //max number of ply to search for in a thread
extern bool CqlUsePgnSourceAlways;
extern bool CqlFixNestedComments;
extern bool CqlShowThread; //whether to print out thread information when showing the output
extern bool CqlNoRemoveComment;
extern bool CqlNoSetTag;
extern std::vector<std::string>* CqlPreambleStrings;
extern std::vector<std::string>* CqlPreambleTransforms;
extern bool CqlRunningThreads;
extern bool CqlUniqueComments;
extern bool CqlSmartComments;
extern bool CqlShowFromString;
extern bool CqlIsExiting;
#ifdef CQL6_EMBEDDED // scidb: test hook for T5 assert recovery
extern void (*CqlTestAssertHook)(int gameNumber, int threadIndex);
#endif
/* Caches: static variables in methods*/
extern  int MarkBoard_gameAppendComment_lastignored; //must be initialized to -1
extern int Tokens_nextid; // the next valid id to use if no name specified by numeric
/* Other global variables*/
extern CqlNode* CqlParseRoot; //The most recently read CQL parse tree;
extern bool CqlSortComments;
/* stdin/stdout issues */
extern bool CqlPgnStdin; // Use standard input for the pgn file
extern bool CqlPgnStdout; //Use standard output for the pgn file
/*GUI stuff*/
extern const char *CqlGuiMessageStart;
extern const char* CqlGuiMessageStop;
extern const char* CqlGuiVariable;
extern const char* CqlGuiErrorStart;
extern const char* CqlGuiErrorStop;
extern const char* CqlGuiNormalExit;
extern bool CqlGui;
extern int CqlLastGameNumber;
/* String accessors for configuration parameters so code doesn't have to deal with char */
/* SICD may still use char* however */
void setCqlGlobal(const char * & global, std::string name);
std::string getCqlGlobal(const char * & global);
