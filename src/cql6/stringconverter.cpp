#include "stringconverter.h"
StringConverter::StringConverter(Node*node){
  uassert(node,"scnode arg");
  theNodes.push_back(node);
}

StringConverter::StringConverter(vector<Node*>nodes):theNodes(nodes){
  uassert(theNodes.size()>0,"scthenodes: len arg");
  for(Node*node:theNodes)
    uassert(node,"sc null node arg");
}
  
bool StringConverter::match_position(QPos*qpos){
  eassert(false,"attempt to use 'str ...' but the string value it returns is ignored. The 'str' filter is always true however");
  return false;
}

string StringConverter::convert(QPos*qpos){
  string ret;
  if(!match_stringvalue(qpos,&ret))
    uassert(false,"unexpected fail of stringvalue in StringConverter");
  return ret;
}

bool StringConverter::match_stringvalue(QPos*qpos,string*stringp){
  stringstream s;
  for (Node*node:theNodes)
    convertnode(node,qpos,s);
  if(stringp)*stringp=s.str();
  return true;
}

void StringConverter::deepify(){
  for(int i=0;i<(int)(theNodes.size());++i)
    theNodes[i]=theNodes[i]->clone();
}

vnode StringConverter::children()const{
  vnode ret;
  for(Node*node:theNodes)
    myinsert(ret,node);
  return ret;
}
/********converters*********/

void StringConverter::convertnode(Node*node,QPos*qpos,stringstream &s){
  uassert(node,"scconvert arg");
  if(
     false
     || convertUnboundVariable(node,qpos,s) //must start with this!
     || convertString(node,qpos,s)
     || convertNumeric(node,qpos,s)
     || convertPieceIdVariable(node,qpos,s) //must precede convertset
     || convertSet(node,qpos,s)
     || convertPosition(node,qpos,s)
     || convertDictionary(node,qpos,s)
     || convertLogical(node,qpos,s)
     )
    return;
  uassert(false,"stringconverter: could not convert node");
}

bool StringConverter::convertUnboundVariable(Node*node,QPos*qpos, stringstream&s){
  Variable*v=node->asVariable();
  if(v&&v->isUnbound()){
    s<<"<unbound: "
     <<v->name
     <<'>';
    return true;
  }
  return false;
}

bool StringConverter::convertString(Node*node,QPos*qpos,stringstream&s){
  if(!node->isString())return false;
  string stringval;
  if (node->match_stringvalue(qpos,&stringval)){
    s<<stringval;
    return true;
  }
  s<<"<false>";
  return true;
}

    
bool StringConverter::convertSet(Node*node,QPos*qpos, stringstream & s){
  if (node->isSet()){
    SetBase*setbase=node->asSet();
    uassert(setbase,"StringConverter: no such set");
    SquareMask mask=setbase->getSquares(qpos);
    s<<mask.listString();
    return true;
  }
  return false;
}
bool StringConverter::convertNumeric(Node*node,QPos*qpos,stringstream& s){
  if (!node->isNumeric())return false;
  NumValue value{-1000};
  bool matched=node->match_count(qpos,&value);
  if(matched)
    s<<value;
  else
    s<<"<false>"; //change for better result after regression
  return true;
}

bool StringConverter::convertPieceIdVariable(Node*node,QPos*qpos,stringstream& s){
  PieceIdVariable*v=node->asPieceIdVariable();
  if (!v) return false;
  eassert(v->isBound(),"StringConverter: expected a bound variable here");
  squareT sq{65};
  if(!v->getSquare(qpos,&sq))
    return "[absent]";
  uassert (square_valid(sq),"StringConverter: bad square");
  pieceT piece=qpos->getBoard()[sq];
  uassert(piece!=EMPTY,"StringConverter: Unexpected empty square");
  s<<piece_to_char(piece)<<square_to_string(sq);
  return true;
}

bool StringConverter::convertPosition(Node*node,QPos*qpos,stringstream&s){
  if (!node->isPosition())return false;
  QPos*position{NULL};
  if(node->match_positionvalue(qpos,&position)){
    s<<position->idString();
    return true;
  }
  s<<"<false>";
  return true;
}

bool StringConverter::convertDictionary(Node*node,QPos*qpos,stringstream&s){
  if(!node->isDictionary())return false;
  Dictionary* dictionary=node->asDictionary();
  s<<dictionary->toString();
  return true;
}

bool StringConverter::convertLogical(Node*node,QPos*qpos,stringstream&s){
  if (node->match_position(qpos))
    s<<"<true>";
  else
    s<<"<false>";
  return true;
}
  
