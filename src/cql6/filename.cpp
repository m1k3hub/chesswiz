#include <stdio.h>
#include "cqlassert.h"
#include "cqlexit.h"
#include <ctype.h>
#include <sstream>
#include "util.h"

bool filename_is_pgn(string filename){
  string ext=filename_extension(filename);
  if(ext.empty())return false;
  return ext==".pgn"||ext==".PGN";
}
bool filename_is_cql(string filename){
  if(filename.empty())return false;
  string ext=filename_extension(filename);
  if(ext.empty())return false;
  return ext==".cql"||ext==".CQL";
}

bool filename_is_cqo(string filename){
  string ext=filename_extension(filename);
  if(ext.empty())return false;
  return ext==".cqo"||ext==".CQO";
}
  
string filename_extension(string filename){
  uassert(!filename.empty(),"empty filename to filename_extension");
  auto dotpos=filename.rfind('.');
  auto slashpos=filename.find_last_of("/\\");
  if (dotpos==string::npos) return "";
  if (slashpos!=string::npos && slashpos>dotpos)return "";
  return filename.substr(dotpos);
}

string filename_stem(string name){
  string noprefix=filename_trim_path_prefix(name);
  string noext=filename_trim_extension(noprefix);
  return noext;
}

string filename_trim_path_prefix(string name){
  uassert(name.length(),"filename_trim_path_prefix no name");
  auto pos=name.find_last_of(":/\\");
  if (pos==string::npos)return name;
  uassert(pos<name.length()-1,"Cannot find filename from string: ",name);
  return name.substr(pos+1);
}

string filename_trim_extension(string name){
  uassert(name.length(),"bad arg to trim_ext");
  string  ext=filename_extension(name);
  if(ext.empty())return name;
  uassert (ext.length()<name.length(),"Cannot trim extension in filename ", name);
  return name.substr(0,name.length()-ext.length());
}

  
