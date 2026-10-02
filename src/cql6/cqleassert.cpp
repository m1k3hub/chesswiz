#include <string>
using std::string;
#include "cqlassert.h"
#include "cqlexit.h"

void eassert(void* v,const string& s){
  eassert(v!=NULL,s);
}

void eassert(void *v,const string& s, const string& s2){
  eassert(v!=NULL,s,s2);
}


void eassert(bool b,const string& s){
  if (!b)
    cql_exit(s);
}

/* modified for build 9.192 in order to correct numerous instances
   of error messages without a space between characters (multiple
   errors reported by Robert Gamble*/

void eassert(bool b,const string &s1, const string &s2){
  if(b) return;
  else if (s1.empty()) eassert(false, s2);
  else if (s2.empty()) eassert(false, s1);
  else if (s1.back()!= ' ')
    eassert(false, (s1+' ')+s2);
  else eassert(false,s1+s2);
}

void eassert(void* v,const char* s){
  eassert(v!=NULL,s);
}

void eassert(void *v,const char* s, const char* s2){
  eassert(v!=NULL,s,s2);
}


void eassert(bool b,const char* s){
  if (!b)
    cql_exit(s);
}

/*Modified for build 9.192 to handle intercalating spaces. See comments above*/
void eassert(bool b,const char *s1, const char *s2){
  if(b)return;
  eassert(false,string(s1),string(s2));
}

void eassert(bool b,const char*s1, const string& s2){
  if(!b) eassert(false,string(s1),s2);
}

void eassert(bool b,const string& s1, const char* s2){
  if(!b) eassert(false,s1,string(s2));
}

void eassert(void* v ,const char*s1, const string& s2){
  eassert(v!=NULL,s1,s2);
}

void eassert(void* v,const string& s1, const char* s2){
  eassert(v!=NULL,s1,s2);
}


