#pragma once
#include <string>
using std::string;
/**All these signatures are used to avoid macros and to
   prevent the high cost of constructing or copying strings,
   since uassert is called in inner loops. Testing showed that argument
   conversion and copying was a timing bottleneck before the new signatures.
**/
//uassert section:

//one arguments
void uassert(bool, const char* s);
void uassert(bool, const string& s);
void uassert(void*,const char* s);
void uassert(void*,const string& s);

//two identical arguments
void uassert(void*,const string& s1, const string& s2);
void uassert(void*,const char* s1, const char* s2);
void uassert(bool b, const string& s1, const string& s2);
void uassert(bool b, const char* s1, const char* s2);

//two different arguments
void uassert(void*,const char* s1, const string& s2);
void uassert(bool b, const char* s1, const string& s2);
void uassert(void*,const string& s1, const char* s2);
void uassert(bool b, const string& s1, const char* s2);

//eassert section (same as uassert section)
//uassert section:

//one arguments
void eassert(bool, const char* s);
void eassert(bool, const string& s);
void eassert(void*,const char* s);
void eassert(void*,const string& s);

//two identical arguments
void eassert(void*,const string& s1, const string& s2);
void eassert(void*,const char* s1, const char* s2);
void eassert(bool b, const string& s1, const string& s2);
void eassert(bool b, const char* s1, const char* s2);

//two different arguments
void eassert(void*,const char* s1, const string& s2);
void eassert(bool b, const char* s1, const string& s2);
void eassert(void*,const string& s1, const char* s2);
void eassert(bool b, const string& s1, const char* s2);
