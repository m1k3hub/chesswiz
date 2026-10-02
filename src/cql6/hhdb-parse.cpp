#include "node.h"
#include "tokens.h"
#include "hhdbkeyword.h"
#include "hhdbawardnode.h"

Node*Tokens::match_hhdb(){
  Node*node=NULL;
  //handle hhdb_award separately
  node=match_hhdb_award();
  if(node)return node; 
  if (!match_keyword("hhdb"))return NULL;
  string key=match_hhdb_keyword();
  if (key.empty())
    show_error("Expecting a valid hhdb keyword following 'hhdb'. Use 'cql -hhdb info' to see all the valid keywords");
  string cql=HhdbKeyword::cql_from_key(key);
  if(0) cout<<"\nmatch_hhdb: got cql from key: "<<key<< " of:\n"<<cql<<endl;
  if (cql.empty())
    show_error("Internal: no cql mapping for key: ", key);
  Node*basenode=node_from_string(cql);
  basenode=match_trailing_quoted_string(basenode);
  return basenode;
}

bool Tokens::match_hhdb_keyword(string key){
  uassert(key.size(),"mhk key size");
  int x=save();
  string currkey=match_hhdb_keyword();
  if (currkey!=key){
    restore(x);
    return false;
  }
  return true;
}

/*return the next hhdb keyword. If the next hhdb keyword is "gbr"
  and if the following hhdb keyword key2 is an isGbrKey(), then
  return "gbr"+key2 [this should all be done in the lexer probably].
*/

string Tokens::match_hhdb_keyword(){
  StringToken*token=dynamic_cast<StringToken*>(current());
  if(!token) return "";
  string key=token->value;
  uassert(key.size(),"match_hhdb_keyword internal");
  if (!HhdbKeyword::isKey(key)) return "";
  QuotedStringToken*qtoken=dynamic_cast<QuotedStringToken*>(token);
  bool isquotedkey=(qtoken!=NULL);
  bool keymustbequoted=HhdbKeyword::isQuotedKey(key);
  if (isquotedkey != keymustbequoted) return "";
  forward();
  string abbrev=HhdbKeyword::matchAbbreviation(key);
  if(abbrev.size()) return abbrev;
  if (key=="gbr"){
    int x=save();
    string key2=match_hhdb_keyword();
    if (HhdbKeyword::isGbrKey(key2))
      return key+key2;
    else restore(x);
  }
  return key;
}


  

