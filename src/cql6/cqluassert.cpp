#include <string>
using std::string;
#include "cqlassert.h"
#include "cqlexit.h"

const string UassertPreamble="CQL internal error: ";
void uassert(void* v,const string& s){
  uassert(v!=NULL,s);
}

void uassert(void *v,const string& s, const string& s2){
  uassert(v!=NULL,s,s2);
}


void uassert(bool b,const string& s){
  if (!b)
    cql_exit(UassertPreamble+s);
}

/* modified for build 9.192 in order to correct numerous instances
   of error messages without a space between characters (multiple
   errors reported by Robert Gamble*/

void uassert(bool b,const string &s1, const string &s2){
  if(b) return;
  else if (s1.empty()) uassert(false, s2);
  else if (s2.empty()) uassert(false, s1);
  else if (s1.back()!= ' ')
    uassert(false, (s1+' ')+s2);
  else uassert(false,s1+s2);
}

void uassert(void* v,const char* s){
  uassert(v!=NULL,s);
}

void uassert(void *v,const char* s, const char* s2){
  uassert(v!=NULL,s,s2);
}


void uassert(bool b,const char* s){
  if (!b)
    cql_exit(UassertPreamble+s);
}

/*Modified for build 9.192 to handle intercalating spaces. See comments above*/
void uassert(bool b,const char *s1, const char *s2){
  if(b)return;
  uassert(false,string(s1),string(s2));
}

void uassert(bool b,const char*s1, const string& s2){
  if(!b) uassert(false,string(s1),s2);
}

void uassert(bool b,const string& s1, const char* s2){
  if(!b) uassert(false,s1,string(s2));
}

void uassert(void* v ,const char*s1, const string& s2){
  uassert(v!=NULL,s1,s2);
}

void uassert(void* v,const string& s1, const char* s2){
  uassert(v!=NULL,s1,s2);
}


