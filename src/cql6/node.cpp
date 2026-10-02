#include "node.h"
#include "assignnode.h"
#include "variable.h"
#include "notnode.h"
#include "gamefilterwrapper.h"
#include "notransformnode.h"
#include "ornode.h"
#include "stringmatchnode.h"
#include "tagbuiltinnode.h"
#include "dictionary.h"

bool GameFilter::match_position(QPos*qpos){
  return match_game(qpos->qgame);
}

void Node::cloneverify(Node*s,Node*t){
  uassert(s,"cloneverify s");
  uassert(t,"cloneverify t");
  uassert(s->thisclass()==t->thisclass(),"cloneverify thisclass");
  auto vars=dynamic_cast<Variable*>(s);
  auto vart=dynamic_cast<Variable*>(t);
  uassert((vars==NULL)==(vart==NULL),"cloneverify null null test");
  if (!vars) return;
  vector<Node*>schildren=s->children();
  vector<Node*>tchildren=t->children();
  uassert(schildren.size()==tchildren.size(),"bad child count");
  for(int i=0;i<schildren.size();++i){
    Node*schild=schildren[i];
    Node*tchild=tchildren[i];
    uassert(schild&&tchild,"internal cloneverify");
    uassert(schild->thisclass()==tchild->thisclass(),"bad classes ==");
    if(schild==tchild){
      printf("Unexpected identical children after cloning. \n");
      printf("Source child: \n");
      schild->print();
      printf("\nTarget child: \n");
      tchild->print();
      printf("\n");
      uassert(false,"cloneverify child identical");
    }
    cloneverify(schild,tchild);
  }
}

	     
  
  

KeywordNode::KeywordNode(string v):value(v){
  uassert(KeywordToken::isReserved(v),"KeywordNode: internal: ",v);
}

bool KeywordNode::eq(string v){
  return value==v;
}



vnode Node::descendants(){
  vnode start{this};
  alldescendants(&start);
  return start;
}

void Node::alldescendants(vnode*v){
  vnode c=children();
  for(auto np : c)
    if(np){
      v->push_back(np);
      np->alldescendants(v);
    }
}
	

ResultNode::ResultNode(string v){
  if(v=="1-0")
    result=RESULT_White;
  else if(v=="0-1")
    result=RESULT_Black;
  else if(v=="1/2-1/2")
    result=RESULT_Draw;
  else
    uassert(false,"Invalid result string",v);
}


bool ResultNode::match_game(QGame*qgame){
  uassert(qgame,"RNmg game");
  if(result!=RESULT_None&&
     result!=QMarkBoard::getResult(qgame))
    return false;
  return true;
}

bool Node::match_count(QPos*qpos, NumValue*v){
  uassert(false,"Node::match_count(), internal, should not be invoked. Possible missing match_count in a subclass of Node");
  return false;
}

bool Node::match_positionvalue(QPos*qpos, QPos**v){
  uassert(false,"Node::match_positionvalue(), internal, should not be invoked. Possible missing match_positionvalue() in a subclass of Node");
  return false;
}

bool Node::match_stringvalue(QPos*qpos, string*stringp){
  uassert(false,"Node::match_stringvalue(), internal, should not be invoked. ");
  return false;
}

/* create an effective player node with no color, transform it correctly.
   a static method.
   used by cqlnode.cpp and also node-parse.cpp to create player nodes
*/
GameFilter* Node::createVirtualPlayerNode(string name){
  uassert(name.size()>0,"cvpn: empty player name in player node");
  return
    new GameFilterWrapper
    (new NoTransformNode
     (new OrNode
      (new StringMatchNode(new TagBuiltInNode("White"),name),
       new StringMatchNode(new TagBuiltInNode("Black"),name))));
}


ValueType Node::valuetype()const{
  if (isNumeric())return ValueType::Number;
  if (isSet())return ValueType::Set;
  if (isString())return ValueType::String;
  if (isPosition())return ValueType::Position;
  return ValueType::Logical;
}

bool Node::valuetypeIsAssignable(ValueType v){
  switch(v){
  case ValueType::Set:
  case ValueType::Number:
  case ValueType::Position:
  case ValueType::String:
    return true;
  default:
    return false;
  }
}

bool Node::valuetypeIsPersistent(ValueType v){
  switch(v){
  case ValueType::Set: case ValueType::Number: case ValueType::String:
    return true;
  default:
    return false;
  }
}
string Node::valuetypeToString(ValueType v){
  switch(v){
  case ValueType::None: return "None";
  case ValueType::Set: return "Set";
  case ValueType::Number: return "Number";
  case ValueType::String: return "String";
  case ValueType::Position: return "Position";
  case ValueType::Logical: return "Logical";
  default: uassert(false,"vts err v");
  }
  return "ERROR";
}
  
bool Node::match_game(QGame*qgame){
  uassert(qgame,"nmg arg");
  if (!isGameFilter()){
    printf("Illegal match_game() call. Node is: \n");
    print();
    uassert(false,"Attempt to call 'matchgame' on a non-game-filter");
  }
  return match_position(qgame->getRoot());
}

Dictionary* Node::asDictionary(){
  if (isDictionary()){
    Dictionary*d=dynamic_cast<Dictionary*>(this);
    uassert(d,"asdictionary");
    return d;}
  return NULL;
}

const Dictionary* Node::asDictionary()const{
  if(isDictionary()){
    auto d= dynamic_cast<const Dictionary*>(this);
    uassert(d,"asdictionary const");
    return d;}
  return NULL;
}



