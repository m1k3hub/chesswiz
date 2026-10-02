#include "cqlthread.h"
#include "lexer.h"
#include "cqlexit.h"
#include "tokens.h"
#include "environment.h"
#include "numericvariable.h"
#include "uchar.h"
#include <thread>
#include <chrono>
using std::thread;
void cql_execute(string cqlfilename,int nthreads){
  auto timeStart=std::chrono::high_resolution_clock::now();
  if(nthreads==0)nthreads=1;
  uassert(nthreads>0,"cql_execute bad nthread");
  bool forcesinglethread=false;
  vector<CqlNode*>cqlnodes=generateCqlNodes(cqlfilename, nthreads,&forcesinglethread);
  if(forcesinglethread){
    uassert(cqlnodes.size()==1,"cql_execute: persistent: threads: internal");
    nthreads=1;
  }
  for(int i=0;i<nthreads;++i)
    for(int j=0;j<nthreads;++j)if(i!=j){
	auto cqli=cqlnodes[i];
	auto cqlj=cqlnodes[j];
	uassert(cqli!=cqlj,"ceij");
	vnode di=cqli->descendants();
	vnode dj=cqlj->descendants();
	uassert(di.size()==dj.size(),"ceij2");
	/*The next two lines are deleted as they have quadratic complexity
	  for(auto iel:di)for(auto jel: dj) uassert(iel!=jel,"ceij3");
	  for(auto iel:di)
	  uassert(myindex(dj,iel)<0,"ceij4");
	*/
      }
      
  cqlcheckvalid(cqlnodes);
  string outputfile=cqlnodes[0]->outputfile;
  string inputfile=cqlnodes[0]->inputfile;
  auto searchvariations=CqlSearchVariations;
  for(auto&cn : cqlnodes)
    uassert(cn->outputfile==outputfile&&
	    cn->inputfile==inputfile,"cql_execute output/input cqlnode");
  vector<QGame*>qgames;
  PgnSource* pgnsource{NULL};
  bool multithreaded= (nthreads>1);
  bool use0pgnsource=(multithreaded || CqlUsePgnSourceAlways);
  if(multithreaded||use0pgnsource)
    pgnsource=new PgnSource(inputfile);
  for(int threadindex=0;threadindex<nthreads;++threadindex){
    QGame*qgame=NULL;
    if(use0pgnsource)
      qgame=new QGame(pgnsource,searchvariations);
    else
      uassert(false,"cqlthread: unexpected pgnsource is false");
    uassert(qgame,"cqlthread cannot make qgame");
    qgames.push_back(qgame);
  }
  uassert(qgames.size()==cqlnodes.size(),"cqlthread fatal2");
  uassert(!outputfile.empty()||CqlPgnStdout,"cql_execute: missing output file");

  //  vector<vector<int>>biggames(nthreads);
  vector<vector<GameSortInfo>>results(nthreads);
  uassert((int)(results.size())==nthreads,"cql_execute internal result");
  vector<std::thread*>threads;
  threads.push_back(NULL);
  std::vector<size_t>ngames_array;
  for(int i=0;i<nthreads;++i)ngames_array.push_back(0);
  for(auto&g:ngames_array)g=0;
  if(nthreads>1) {
    uassert(!CqlRunningThreads,"CRT in cqlthread");
    CqlRunningThreads=true;}
  for (int threadindex=1;threadindex<nthreads;++threadindex){
    threads.push_back(new std::thread(thread_exec,
				      cqlnodes[threadindex],
				      qgames[threadindex],
				      threadindex,
				      nthreads,
				      &ngames_array.at(threadindex),
				      &results[threadindex]));
  }
  uassert((int)(threads.size())==nthreads,"cql_execute threadssize");
  thread_exec(cqlnodes.front(),qgames.front(),0,nthreads,&ngames_array[0],&results[0]);
  for(int threadindex=1;threadindex<nthreads;++threadindex){
    threads[threadindex]->join();
  }
  if(nthreads>1){
    uassert(CqlRunningThreads,"CRT2 in cqlthread");
    CqlRunningThreads=false;
  }
  
  size_t ngames=0;
  for(auto g:ngames_array)ngames+=g;
  size_t nmatches=0;
  for(auto &v:results)nmatches+=v.size();
  GameSortInfo::output(outputfile,results);
  auto timeStop = std::chrono::high_resolution_clock::now();
  auto duration=timeStop-timeStart;
  long msecs= std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
  double secs= msecs/1000.0;
  string threadstring ="threads";
  if(nthreads==1) threadstring="thread";
  printf("\n%zu matches of %zu games in %.3g seconds using %d %s to %s\n",
	 nmatches,
	 ngames,
	 secs,
	 nthreads,
	 threadstring.c_str(),
	 outputfile.c_str());
  if(CqlGui){
    printf("\n%s numbermatches %zu\n",CqlGuiVariable,nmatches);
    printf("%s numbergamesexamined %zu\n",CqlGuiVariable,ngames);
    printf("%s seconds %.3g\n",CqlGuiVariable,secs);
    printf("%s numberthreads %d\n",CqlGuiVariable,nthreads);
    printf("%s outputfile %s\n",CqlGuiVariable,outputfile.c_str());
  }
  vector<Variable*> persistents=cqlnodes.front()->getPersistentVariables();
  for(auto v:persistents)
    if (!cqlnodes.front()->isQuietPersistentVariable(v))
      {
	printf("%s: %s\n",v->name.c_str(),v->persistentValueAsString().c_str());
	if(CqlGui)
	  printf("\n%s%s: %s%s\n",CqlGuiMessageStart,v->name.c_str(),v->persistentValueAsString().c_str(),CqlGuiMessageStop);
      }
}


vector<CqlNode*> generateCqlNodes(string filename, int nthreads, bool *forcesinglethreadp){
  *forcesinglethreadp=false;
  uassert(nthreads>0,"generateCqlNodes args");
  if(CqlEcho){
    UChar::echoFile(filename);
    cql_exit();
  }
  if(CqlDebug)cout<<"Parser: lexing file: "<<filename<<endl;
  vector<Token*> tokenvector= Lexer::lexFile(filename);
  if(CqlShowLex)
    printf("genCqlNodes::Got return of ntokens: %zu\n",tokenvector.size());
  vector<Tokens*> alltokens;
  for(int threadindex=0;threadindex<nthreads;++threadindex){
    alltokens.push_back(new Tokens(tokenvector,NULL));
    if(threadindex==0){
      if(CqlShowLex){
	cout<<"Printing the token stream for file: "<<filename<<endl;
	cout<<alltokens[0]->toString();
      }
      if (CqlLexOnly) cql_exit(); //Note - might want to ignore this if INTEGRATED
    }
  }
  uassert(alltokens.size()==(size_t)nthreads,"thread alltoknthread");
  vector<CqlNode*>ret;
  for(int threadindex=0;threadindex<nthreads;++threadindex){
    Tokens*tokensp=alltokens[threadindex];
    uassert(tokensp,"tokensp error");
    //modify Variables class here, or use passed environment
    CqlNode* cqlnode=CqlNode::create(*tokensp);
    if(CqlShowParse&&threadindex==0){
      cqlnode->print();
      printf("\n");
    }
    if(CqlParseOnly)
      cql_exit();
    eassert(cqlnode,"Unable to parse file: %s",filename);
    ret.push_back(cqlnode);
    if(cqlnode->isSingleThread()){
      string message="CQL: running single-threaded because 'persistent', 'writefile', 'readfile' or 'dictionary' detected";
      printf("%s\n",message.c_str());
      if(CqlGui)
	printf("%s%s%s\n",CqlGuiMessageStart,message.c_str(),CqlGuiMessageStop);
      *forcesinglethreadp=true;
    }//if(forceSingleThread());
    if (*forcesinglethreadp) break; //stop looping over threads if persistent/writefile
  }//for int threadindex
  if(*forcesinglethreadp)
    uassert((int)(ret.size())==1,"internal ret nthreads");
  else
    uassert((int)(ret.size())==nthreads,"internal ret nthreads");
  return ret;
}

#ifdef CQL6_EMBEDDED // scidb: parse directly from string
vector<CqlNode*> generateCqlNodesFromString(const string& script_text, int nthreads, bool *forcesinglethreadp){
  *forcesinglethreadp=false;
  uassert(nthreads>0,"generateCqlNodesFromString args");
  vector<Token*> tokenvector = Lexer::lexString(script_text);
  vector<Tokens*> alltokens;
  for(int threadindex=0;threadindex<nthreads;++threadindex){
    alltokens.push_back(new Tokens(tokenvector,NULL));
  }
  uassert(alltokens.size()==(size_t)nthreads,"thread alltoknthread");
  vector<CqlNode*>ret;
  try {
    for(int threadindex=0;threadindex<nthreads;++threadindex){
      Tokens*tokensp=alltokens[threadindex];
      uassert(tokensp,"tokensp error");
      CqlNode* cqlnode=CqlNode::create(*tokensp);
      eassert(cqlnode,"Unable to parse script text");
      ret.push_back(cqlnode);
      if(cqlnode->isSingleThread()){
        *forcesinglethreadp=true;
      }
      if (*forcesinglethreadp) break;
    }
  } catch(...) {
    // scidb: Task 3 §B — release the parser wrappers on a syntax error too.
    // (The CqlNode/environment they produced stays reachable from the caller's
    // registry; Tokens itself is not referenced by the tree.)
    for(Tokens*t:alltokens) delete t;
    throw;
  }
  // scidb: Task 3 §B — Tokens is only a parse cursor; the tree does not reference
  // it after CqlNode::create. Deleting it frees the vector<Token*> and the wrapper.
  for(Tokens*t:alltokens) delete t;
  if(*forcesinglethreadp)
    uassert((int)(ret.size())==1,"internal ret nthreads");
  else
    uassert((int)(ret.size())==nthreads,"internal ret nthreads");
  return ret;
}
#endif

void thread_exec(CqlNode* cqlnode,
		 QGame*qgame,
		 int threadindex,
		 int nthreads,
		 size_t*ngamesp,
		 vector<GameSortInfo>*resultp){
  
  uassert(cqlnode&&threadindex>=0
	  && threadindex<nthreads
	  &&resultp
	  && resultp->empty()
	  && qgame,
	  "thread_exec bad args");
  //this part is mainly taken from the old CqlNode::match() in cqlnodematch.cpp
  int gameNumber=qgame->getGameNumber();
  Range*gamenumberrange=cqlnode->gamenumberrange;
  uassert(gameNumber==0,"thread_exec");
  while(qgame->parseNextGame()){
    *ngamesp+=1;
    gameNumber=qgame->getGameNumber();
    if(gamenumberrange){
      if(gameNumber>gamenumberrange->getMax())
	break;
      if(gameNumber<gamenumberrange->getMin())
	continue;
    }
    bool matched=cqlnode->match_game(qgame);
#ifdef CQL6_EMBEDDED // scidb: test hook for T5 assert recovery
    if (CqlTestAssertHook) CqlTestAssertHook(gameNumber, threadindex);
#endif
    cql_output_status(gameNumber,threadindex,matched);
    if (true)
      qgame->verifyRoot();
    if(matched) {
      cqlnode->setFirstComment(qgame);
      qgame->mergeComments();
      resultp->push_back(cqlnode->makeInfo(qgame));
    } // if (matched)
  } // while next game
}//exec

void cql_output_status(int gamenumber, int threadindex, bool matched){
  if (gamenumber==0)return;
  bool showthread=CqlShowThread;
  if (!CqlShowOutput||CqlLineIncrementOutput<=0)return;
  int lineinc=CqlLineIncrementOutput;
  int dotinc=std::max(lineinc/10,1);
  if((gamenumber)%lineinc==0&&gamenumber>=lineinc){
    if (showthread)
      printf("{%d:%d}\n",threadindex,gamenumber);
    else
      printf("[%d]\n",gamenumber);
  }
  else if ((gamenumber)%dotinc==0){
    if(showthread)
      printf("[%d.]",threadindex);
    else printf(".");
  }
  if(CqlGui && (gamenumber%dotinc==0))
    printf("\n%s currentgamenumber %d\n",CqlGuiVariable,gamenumber);
  if(matched&&CqlShowMatches){
    if(showthread)
      printf("+<%d:%d>",threadindex,gamenumber);
    else
      printf("<%d>",gamenumber);
  }
}

void cqlcheckvalid(vector<CqlNode*>&roots){
  CqlNode*source=roots.at(0);
  for (int i=1;i<(int)(roots.size());++i){
    CqlNode*target=roots.at(i);
    uassert(source&&target&&source!=target&&source->environment!=target->environment,"ccv e1");
    auto senv=source->environment;
    auto tenv=target->environment;
    uassert(source&&target,"ccv e2");
    auto ssortvars=senv->getSortVariables();
    auto tsortvars=tenv->getSortVariables();
    uassert(ssortvars&&tsortvars&&ssortvars->size()==tsortvars->size(),"ccv e3");
    for(auto v : *ssortvars)
      for (auto w : *tsortvars)
	uassert(v!=w,"ccv e4");
  }
}

int cql_compute_number_threads(){
  int hc = std::thread::hardware_concurrency();
  if (hc<=1) return 1;
  return hc-1;
}

/*pause the current thread for the given number of seconds. This will I hope remove
  most race conditions when one thread calls exit(1)
  For code this copies, see: https://en.cppreference.com/w/cpp/thread/sleep_for
*/

  
