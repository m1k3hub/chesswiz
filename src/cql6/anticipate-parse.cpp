#include "token.h"
#include "node.h"
#include "tokens.h"
#include "anticipatenode.h"
#include "nodeheaders.h"

Node*Tokens::match_anticipatenode(){
  if(!match_keyword("similarposition"))
    return NULL;
  bool isnosort{false};
  bool isnotransform{false};
  while(true)
    if (match_keyword("nosort"))
      isnosort=true;
    else if (match_keyword("notransform"))
      isnotransform=true;
    else break;

  string filename=match_nonemptyquotedstring();
  if(filename.empty())
    show_error("'similarposition' must be followed by a quoted string, the name of a pgnfile");
  if(!filename_is_pgn(filename))
    show_error("quoted string following 'similarposition' must be the filename of a .pgn file. Instead, got: "s+filename);
  string minqgamename=get_unique_name("cql_anticipate_minqgame");
  //  nmatchesname=get_unique_name("cql_anticipate_nmatches");
  uassert(!environment->find(minqgamename),"man minqg");
  //  uassert(!environment->find(nmatchesname),"man nmatches");
  NumericVariable*minqgamevar=environment->createNumericVariable(minqgamename);
  //  NumericVariable*nmatchesvar=environment->createNumericVariable(nmatchesname);
  Node*an= new AnticipateNode(filename,minqgamevar,isnotransform);
  if(isnosort) return an;
  Node*minqsortnode=new SortNode(environment,"submission game", SortDirection::Up,false,minqgamevar);
  return new CompoundNode(vector<Node*>{an,minqsortnode});
}

string Tokens::get_unique_name(const string&n){
  for(int i=0;i<1000;++i){
    stringstream s;
    s<<n<<i;
    string ret=s.str();
    if(!environment->find(ret))
      return ret;
  }
  uassert(false,"get_unique_name: unable to find unique name suffix for stem: "s+n);
  return "";
}
