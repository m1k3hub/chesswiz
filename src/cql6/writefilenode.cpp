#include "writefilenode.h"
#ifdef CQL6_EMBEDDED // scidb: file lockdown during embedded searches
#include "scidb_lockdown.h"
#endif

using std::map;
using std::ofstream;

map<string,ofstream*> WriteFileNode::fileMap;
WriteFileNode::WriteFileNode(Node*filenamenode,Node*contentnode):
  fileNameNode(filenamenode),
  contentNode(contentnode){
  uassert (fileNameNode&&contentNode&&
	   fileNameNode->isString()&&
	   contentNode->isString(), "wfn: args");
}
bool WriteFileNode::match_position(QPos*qpos){
#ifdef CQL6_EMBEDDED // scidb: defense in depth; writefile is already rejected at parse time
  scidb::file_guard("writefile", NULL);
#endif
  string filename;
  string contents;
  if (!fileNameNode->match_stringvalue(qpos,&filename))
    eassert(false,"filename does not match position in writefile");
  if (!contentNode->match_stringvalue(qpos,&contents))
    return false;
  if (!(filename_is_cqo(filename)||filename_is_cql(filename)))
    eassert(false,"writefile: filename must have extension '.cqo' or '.cql' but got filename: ", filename);
  if (fileMap.count(filename)==0){
    cout<<"writefile: opening file: "<<filename<<endl;
    ofstream*streamp=new ofstream(filename);
    if (!streamp->good())
      eassert(false,"writefile: unable to open file: ",filename);
    fileMap[filename]=streamp;
  }
  uassert(fileMap.count(filename)==1, "writefile: map error 1: ",filename );
  ofstream*streamp=fileMap[filename];
  uassert(streamp->good()&&streamp->is_open(), "writefile: map error 2: ", filename);
  *streamp<<contents;
  eassert(streamp->good(), "writefile: write failed to: ",filename);
  streamp->flush();
  eassert(streamp->good(),"writefile: flush failed to: ",filename);
  return true;
}

vnode WriteFileNode::children()const{
  vnode ret{fileNameNode};
  if(contentNode!=fileNameNode)
    ret.push_back(contentNode);
  return ret;
}

void WriteFileNode::deepify(){
  fileNameNode=fileNameNode->clone();
  contentNode=contentNode->clone();
}

  
