#include "node.h"
#include "gamesortinfo.h"
#ifdef CQL6_EMBEDDED // scidb: file lockdown during embedded searches
#include "scidb_lockdown.h"
#endif


GameSortInfo::GameSortInfo(string d, vector<SortValue> v,int gamen):
  data(d),
  gamenumber(gamen),
  values(v)
  {
  uassert(!data.empty()&&gamenumber>0,"bad gamesortinfo constructor arg");
}

void GameSortInfo::output(string outputfile, const vector<vector<GameSortInfo>> &results){
#ifdef CQL6_EMBEDDED // scidb: no file access during an embedded search
  scidb::file_guard("GameSortInfo::output", outputfile.c_str());
#endif
  uassert(outputfile.empty()==CqlPgnStdout,"GameSortInfo::output: outputfile/pgnstdout mismatch");
  vector<GameSortInfo>result;
  size_t sum=0;
  for (auto& r:results){
    sum+=r.size();
    result.insert(result.end(),r.begin(),r.end());
  }
  uassert(sum==result.size(),"cql_output size");
  sort(result);
  uassert(CqlPgnStdout||filename_is_pgn(outputfile),"output: output file is not a pgn file: ",outputfile);
  FILE* outputstream=NULL;
  if(CqlPgnStdout) outputstream=stdout;
  else outputstream=fopen(outputfile.c_str(),"w");
  uassert(outputstream,"CQL: could not open file for writing: ",outputfile);
  output(outputstream,result);
}

void GameSortInfo::output(FILE* os)const{
  fprintf(os,"%s\n\n",data.data());
}

void GameSortInfo::preamble(const vector<GameSortInfo>&v){
  uassert(CqlPgnStdout,"GameSortInfo preamble internal");
  size_t ngames=v.size();
  size_t totalbytes=0;
  for (const auto & gs : v)
    totalbytes=totalbytes+gs.data.size()+2; //the 2 for the "\n\n", see GameSortInfo::output(FILE*os)
  printf("\n<CqlGuiPgn numbergames=%zu numberbytes=%zu>\n",ngames,totalbytes);
}
	  

void GameSortInfo::output(FILE* os, const vector<GameSortInfo>& v){
  if(CqlPgnStdout) preamble(v);
  for (const auto &gs : v)
    gs.output(os);
  if(CqlPgnStdout)
    printf("</CqlGuiPgn>\n");
}

void GameSortInfo::sort(vector<GameSortInfo>& v){
  std::stable_sort(v.begin(), v.end());
}


bool operator<(const GameSortInfo& a, const GameSortInfo& b){
  uassert(!a.data.empty()&&!b.data.empty()&&a.values.size()==b.values.size(),"gamesortinfo < internal");
  int len=(int)(a.values.size());
  for (int i=0;i<len;i++)
    if(b.values[i]<a.values[i]) return true;
    else if (a.values[i]<b.values[i]) return false;
  if(a.gamenumber<b.gamenumber)return true;
  return false;
}

       
