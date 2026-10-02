#include<fstream>
#ifdef CQL6_EMBEDDED // scidb: file lockdown during embedded searches
#include "scidb_lockdown.h"
#endif

#include<iostream>
#include "readfilenode.h"
ReadFileNode::ReadFileNode(Node* fn):fileNameNode(fn){
  uassert(fn&&fn->isString(),"rfn arg");
}

bool ReadFileNode::match_position(QPos*qpos){
  eassert(false, "readfile was evaluated only for whether it matched. The contents of the read file were ignored");
  return false;
}

bool ReadFileNode::match_stringvalue(QPos*qpos,string*stringp){
#ifdef CQL6_EMBEDDED // scidb: defense in depth; readfile is already rejected at parse time
  scidb::file_guard("readfile", NULL);
#endif
  string filename;
  if (!fileNameNode->match_stringvalue(qpos,&filename))
    eassert(false,"readfile: Could not open file: cannot get filename");
  if(!(filename_is_cql(filename)||
       filename_is_cqo(filename)||
       filename_is_pgn(filename)))
    eassert(false,"Invalid filename for 'readfile'. Filename must have extension '.cqo', '.pgn', or '.cql' but got filename: ",filename);
  if(stringp) {
    cout<<"\nReading file: "<<filename<<endl;
    *stringp= util::string_from_filename(filename);
    cout<<"Read file: "<<filename<<" got "<< stringp->size()<<" bytes\n";
  }
  return true;
}

void ReadFileNode::deepify(){
  fileNameNode=fileNameNode->clone();
}
vnode ReadFileNode::children()const{
  return vnode{fileNameNode};
}

    
  
