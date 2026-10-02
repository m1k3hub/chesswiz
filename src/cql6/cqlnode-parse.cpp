#include "node.h"
#include "tokens.h"
#include "environment.h"
/* This file would normally be in nodematch.cpp but is moved here as it so long*/

CqlNode* Tokens::match_cqlnode(){
  vector<Node*> features;
#ifdef CQL6_EMBEDDED // scidb: header is optional in embedded mode
  if (match_keyword("cql")) {
    if(!match_lparen())
      show_error("Expected left paren following the 'cql' keyword");
    features=match_some_cqlfeatures();
    if(!match_rparen())
      show_error("Syntax error while parsing the CQL specification. Expected right paren (this probably indicates an illegal CQL feature)");
  }
#else
  if(!match_keyword("cql")) 
    show_error("Expected 'cql' word to start :cql specification but got: ");
  if(!match_lparen())
    show_error("Expected left paren following the 'cql' keyword");
  features=match_some_cqlfeatures();
  if(!match_rparen())
    show_error("Syntax error while parsing the CQL specification. Expected right paren (this probably indicates an illegal CQL feature)");
  if(features.empty()){
    if (!CqlPgnFilename && !CqlPgnStdin)
      show_error("Empty CQL specification and no pgn input file. To specify a pgn input file, either (a) include 'cql (input foo.pgn)' in the CQL file, or (b) invoke cql via 'cql -i foo.pgn' from the command line");
  }
#endif
  Node* preamblenode = match_preamble(*CqlPreambleStrings);
  vector<Node*> filenodes=match_some_basicnodes();
  if(preamblenode)
    filenodes.insert(filenodes.begin(), preamblenode);
  if(filenodes.empty())
    show_error("Expected one or more filters following CQL specification, got none");
  if(!eof())
    show_error("Extra text following the filters after the CQL specification, or unspecified syntax error");
  Node*untransformedfilenode=NULL;
  if(filenodes.size()>1)
    untransformedfilenode=new CompoundNode(filenodes);
  else if (filenodes.size()==1)
    untransformedfilenode=filenodes.at(0);
  Node* finalnode=apply_preamble_transforms(*CqlPreambleTransforms,untransformedfilenode);
  if(!finalnode)
    show_error("could not apply preamble: possible invalid filters or options on command line");
  if(CqlCommentLevel==CommentLevel::Unspecified)
    CqlCommentLevel=CommentLevel::Normal;
  CqlNode*n=new CqlNode(features,finalnode,environment);
  return n;
}

Node*Tokens::apply_preamble_transforms(const vector<string>& transformnames,Node* node){
  uassert(node,"apt internal");
  if (transformnames.size()==0)return node;
  int len=(int)(transformnames.size());
  Node*currentnode=node;
  for(int i=len-1;i>=0;--i){
    string currentstring=transformnames.at(i);
    uassert(currentstring.size(),"apply_preamble_transforms: null string");
    currentnode=orbitnode_from_keyword(currentstring,currentnode);
    uassert(currentnode,"Unknown or unexpected transform name in preamble: ",currentstring);
  }
  return currentnode;
}
    
Node*Tokens::match_preamble(const vector<string>&preamble){
  if (preamble.empty()) return NULL;
  vector<Node*>nodes;
  for (const string& entry:preamble){
    Node*node=node_from_string(entry);
    if(!node)
      show_error(string("Unable to parse command line filter: ")+entry);
    nodes.push_back(node);
  }
  uassert(nodes.size()>0,"match_preamble: bad size");
  if (nodes.size()==1)return nodes.at(0);
  return new CompoundNode(nodes);
}

    

vector<Transform*> Tokens::transforms_from_keyword(const string& name){
  vector<Transform*>ret;
  //reversecolor is handled specially because it does not include the identity
  if(name=="reversecolor"){
    ret.push_back(ColorTransform::flipColorTransform());
    return ret;
  }
  //Now for the transforms that include the identity:
  if(name=="shift")
    ret=ShiftTransform::allShift();
  else if (name=="shifthorizontal")
    ret=ShiftTransform::shiftHorizontal();
  else if (name=="shiftvertical")
    ret=ShiftTransform::shiftVertical();
  else if (name=="flip")
    ret=DihedralTransform::allDihedral();
  else if (name=="rotate90")
    ret=DihedralTransform::rotations();
  else if (name=="rotate45")
    ret=PiOver4Transform::rotations();
  else if (name=="flipvertical")
    ret.push_back(DihedralTransform::flipVertical());
  else if (name=="fliphorizontal")
    ret.push_back(DihedralTransform::flipHorizontal());
  else if (name=="flipcolor")
    ret.push_back(ColorTransform::flipColorTransform());
  else
    return ret;
  uassert(ret.size(),"transforms_from_keywords internal");
  ret.insert(ret.begin(),new IdentityTransform());
  return ret;
}

vector<Node*> Tokens::match_some_cqlfeatures(){
  vector<Node*>v;
  while(true){
    Node*n{NULL};
    if(!match_cqlfeature(&n)) break;
    if(n) v.push_back(n);
  }
  return v;
}

bool Tokens::match_cqlfeature(Node**nodep){
  uassert(nodep,"m_cf args");
  *nodep=NULL;
  if(match_matchstringfeature()||match_commentlevelfeature())
    return true;
  Node*n=NULL;
  if(!n)n=match_pgnnode();
  if(!n)n=match_resultnode();
  if(!n)n=match_gamenumberrange();
  if(!n) n=match_outputnode();
  if(!n) n=match_variationsnode();
  if(!n) n=match_matchcountnode();
  *nodep=n;
  return n!=NULL;
}

PgnNode* Tokens::match_pgnnode(){
  InputFileToken* token=dynamic_cast<InputFileToken*>(current());
  if(!token)return NULL;
  forward();
  string filename = token->value;
  string globalpgn=getCqlGlobal(CqlPgnFilename);
  if(globalpgn.size()){
    filename=globalpgn;
  }
  if(!filename_is_pgn(filename))
#ifndef CQL6_EMBEDDED // scidb: the input clause is ignored in embedded mode; accept any name
    show_error(string("bad pgn filename: ")+filename);
#else
    { /* scidb: input filename ignored when embedded */ }
#endif
  return new PgnNode(filename);
}

OutputNode* Tokens::match_outputnode(){
  OutputFileToken* token=dynamic_cast<OutputFileToken*>(current());
  if(!token)return NULL;
  forward();
  string filename=token->value;
  string globaloutput=getCqlGlobal(CqlOutputFilename);
  if(globaloutput.size()){
    cout<<"Using command line argument for filename: "<<CqlOutputFilename<<endl;
    filename=globaloutput;
  }
  if(!filename_is_pgn(filename))
#ifndef CQL6_EMBEDDED // scidb: the output clause is ignored in embedded mode; accept any name
    show_error(filename+": invalid pgn file (must end in .pgn or .PGN)");
#else
    { /* scidb: output filename ignored when embedded */ }
#endif
  return new OutputNode(filename);
}

//  This feature for now simply returns NULL always, but sets
// the global variable CqlMatchString if it finds the feature
// and if CqlMatchStringSet is false. This is a dangerous way to
// handle this as it is not consistent with how other features
// are handled.

bool Tokens::match_matchstringfeature(){
  if(!match_keyword("matchstring"))
    return false;
  string name;
  if (!match_quotedstringvalue(&name))
    show_error("expected quoted string following 'matchstring'");
  if(CqlMatchStringSet)return true;
  setCqlGlobal(CqlMatchString,name);
  return true;
}

/* match_commentlevelfeature uses a similar hack as match_matchstringfeature()
   to always return NULL and just use the side effects. See the comments to that function.
*/
bool Tokens::match_commentlevelfeature(){
  if(match_keyword("silent")){
    if(CqlCommentLevel==CommentLevel::Unspecified)
      CqlCommentLevel=CommentLevel::Silent;
    return true;
  }
  else if(match_keyword("quiet")){
    if(CqlCommentLevel==CommentLevel::Unspecified)
      CqlCommentLevel=CommentLevel::Quiet;
    return true;
  }
  return false;
}

