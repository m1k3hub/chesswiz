#include "node.h"
#include "tokens.h"
#include "environment.h"
#include "nodeheaders.h"
#include "matefunction.h"

void Tokens::load_matefunction(){
  if (!environment->find("cql_PureMate")){
    if(0)cout<<"Loading mate functions\n";
    Node*matefunctionnode=node_from_string(MateFunctionString);
    uassert(matefunctionnode,"parse error load_matefunction");
  }
  uassert(environment->find("cql_PureMate"),"cql_PureMate not found after function load");
}

Node*Tokens::match_matefunction(){
  if (match_keyword("puremate")){
    load_matefunction();
    return node_from_string("notransform cql_TruePureMate()");
  }
  if(match_keyword("modelmate")){
    load_matefunction();
    return node_from_string("notransform cql_TrueModelMate()");
  }
  if(match_keyword("idealmate")){
    load_matefunction();
    return node_from_string("notransform cql_TrueIdealMate()");
  }
  if (match_keyword("purestalemate")){
    load_matefunction();
    return node_from_string("notransform cql_TruePureStalemate()");
  }
  if(match_keyword("modelstalemate")){
    load_matefunction();
    return node_from_string("notransform cql_TrueModelStalemate()");
  }
  if(match_keyword("idealstalemate")){
    load_matefunction();
    return node_from_string("notransform cql_TrueIdealStalemate()");
  }
  
  return NULL;
}
