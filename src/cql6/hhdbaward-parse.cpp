#include "node.h"
#include "tokens.h"
#include "hhdbawardnode.h"
#include "hhdbkeyword.h"

Node* Tokens::match_hhdb_award(){
  int x=save();
  if (!match_keyword("hhdb")) return NULL;
  vector<string>keys;
  while (true){
    int y=save();
    string key=match_hhdb_keyword();
    if (!HhdbKeyword::isAwardKey(key)){
      restore(y);
      break;
    }
    keys.push_back(key);
  }

  if (keys.empty()){ //this not an hhdb award type
    restore(x);
    return NULL;
  }

  bool seenmax=false;
  string typekey="";
  bool seenspecial=false;
  bool seensort=false;
  for (const string& key : keys){
    if (key=="max"){
      if (seenmax) show_error ("multiple max keywords following hhdb");
      seenmax=true;}
    else if (HhdbKeyword::isAwardTypeKey(key)){
      if (typekey.size()) show_error ("multiple type (hm, prize, commendation or award) specifications following 'hhdb'");
      typekey=key;
    }
    else if (key=="special"){
      if (seenspecial) show_error("multiple 'special' keywords following hhdb");
      seenspecial=true;
    }
    else if (key=="sort"){
      if (seensort) show_error ("multiple 'sort' keywords apparently following 'hhdb'");
      seensort=true;
    }
    else uassert(false,"match_hhdb_award internal parse");
  } // for const key:keys
  if (seensort&&keys.back()=="sort")
    show_error("'sort' apparently appears as the last parameter to 'hhdb'. This could lead to confusion if a 'sort' filter immediately followed the 'hhdb' filter. If 'hhdb sort' was intended, move the 'sort' to immediately follow the 'hhdb' keyword");
  if (seensort&&typekey.empty()&&!seenspecial){
    show_error("'hhdb sort' requires either 'special', 'award', 'prize', 'hm', or 'commendation' parameters as well");
  }
  
  if (typekey=="") typekey="award";
  if (seensort && seenmax)
    show_error("'hhdb' cannot be followed by both the 'sort' and the 'max' keywords");
  uassert (HhdbKeyword::isAwardTypeKey(typekey),"hhdbaward-parse award type");
  if (seensort)
    return hhdbaward_sort(typekey,seenspecial);
  HhdbAwardNode*node=new HhdbAwardNode(typekey,seenspecial,seenmax);
  return node;
}
