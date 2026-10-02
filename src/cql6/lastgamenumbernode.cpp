#include "lastgamenumbernode.h"
#include "util.h"

bool LastGameNumberNode::match_position(QPos*qpos){
  eassert(false,"'lastgamenumber' invoked in a context where it is used for whether it matches, but this filter always matches. Do not ignore its numeric value");
  return false;
}

bool LastGameNumberNode::match_count(QPos*qpos,NumValue*valuep){
  uassert(qpos && valuep,"invalid LastGameNumberNode args");
  uassert(CqlLastGameNumber>0,"LGNN: bad lastgamenumber");
  *valuep=CqlLastGameNumber;
  return true;
}

void LastGameNumberNode::initialize(string filename,Range*range){
  if(CqlLastGameNumber>0)return;
  uassert(filename_is_pgn(filename),
	  "Invalid pgn filename in LastGameNumber::initialize: "s+filename);
  cout<<"lastgamenumber: reading file: "<<filename<<endl;
  string contents=util::string_from_filename(filename);
  cout<<"lastnumber: read "<<contents.size()<<" bytes. Counting games:...\n";
  int count=0;
  size_t pos=0;
  string pattern="[White ";
  while((pos=contents.find(pattern,pos))!=std::string::npos){
    ++count;
    pos+=pattern.length();
  }
  eassert(count!=0,"No valid games found by searching for the pattern '[White ' in the file: "s+filename);
  uassert(count>0,"Expected positive count of '[White ' in the file: "s+filename);
  CqlLastGameNumber=count;
  cout<<"Detected estimated "<<count<< " games in the file: "<<filename
      << " (Number may not be accurate)"<<endl;
  if(range)
    CqlLastGameNumber=std::min(count,range->getMax());
  else
    CqlLastGameNumber=count;
  uassert(CqlLastGameNumber>0,"non-positive lastgamenumber");
  if(count!=CqlLastGameNumber)
    cout<<"Due to CQL header gamenumber, using lastgamenumber value of: "<<CqlLastGameNumber<<endl;
}
    
    
