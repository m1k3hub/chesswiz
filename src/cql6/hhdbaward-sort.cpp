#include "node.h"
#include "tokens.h"
#include "hhdbawardnode.h"
#include "hhdbkeyword.h"

Node* Tokens::hhdbaward_sort(string typekey, bool hasspecial){
  uassert(HhdbKeyword::isAwardTypeKey(typekey),"hhdbaward_sort arg");
  if (hasspecial)
    return node_from_string (string() + "hhdb special and hhdb sort "+typekey);
  uassert (!hasspecial, "hhdbaward_sort special");
  if (typekey=="award")
    return node_from_string
      ("hhdb sort prize or \
        hhdb sort hm or \
        hhdb sort commendation");
  uassert (typekey!="award","hhdbaward_sort typekey award");
  int category =0;
  if (typekey=="prize") category=1;
  else if (typekey=="hm") category = 3;
  else if (typekey=="commendation") category=5;
  else uassert(false,"hhdbaward_sort switch");
  uassert(category>0&&category%2==1, "hhdbaward_sort category");

  const string fullcql_base =
    R"END(
       {
       hhdb AwardType
       if (hhdb special) then {
           cql_category= Category + 1
           cql_truerank= hhdb special AwardType
           cql_maxrank= hhdb special AwardType max}
       else { //not special
            cql_category= Category
            cql_truerank=hhdb AwardType
            cql_maxrank= hhdb AwardType max}
      sort quiet min "cql_category" cql_category
      sort quiet min "cql_truerank" cql_truerank
      sort quiet min "cql_maxrank" cql_maxrank
      true
      })END";

  const string categorystring = std::to_string(category);
  string tmpstr = util::replaceAll (fullcql_base, "Category", categorystring);
  string finalstr=util::replaceAll(tmpstr, "AwardType",typekey);
  if (0) printf("in hhdbaward-sort the finalstr is: \n%s\n",finalstr.c_str());
  return node_from_string(finalstr);
}


  
  
      
			    
  
