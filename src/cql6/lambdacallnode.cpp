#include "lambdacallnode.h"
#include "tokens.h"
#include "variable.h"
#include "lambdavariable.h"
#include "environment.h"

bool LambdaCallNode::isSet()const{
  return bodynode->isSet();
}

bool LambdaCallNode::isNumeric()const{
  return bodynode->isNumeric();
}

bool LambdaCallNode::isString()const{
  return bodynode->isString();
}

bool LambdaCallNode::isPosition()const{
  return bodynode->isPosition();
}

SquareMask LambdaCallNode::getSquares(QPos*qpos){
  SquareMask ret;
  uassert(isSet(),"LambdaCallNode: Unexpectedly getting squares from a non-set ", name);
  for (AssignNode*assignment : assignments){
    if (assignment && !assignment->match_position(qpos))
      return ret;
  }
  SetBase* set=dynamic_cast<SetBase*>(bodynode);
  uassert(set,"LCN getsquares set",name);
  ret= set->getSquares(qpos);
  return ret;
}

bool LambdaCallNode::match_count(QPos*qpos,NumValue*v){
  uassert(isNumeric(),"LambdaCallNode: Unexpectedly getting squares from a non-set ", name);
  for (AssignNode*assignment : assignments){
    if (assignment && !assignment->match_position(qpos))
      return false;
  }
  uassert(bodynode->isNumeric(),"LCN numeric",name);
  return bodynode->match_count(qpos,v);
}

bool LambdaCallNode::match_positionvalue(QPos*qpos,QPos**v){
  uassert(isPosition(),"LambdaCallNode: Unexpectedly getting position value of non-position ", name);
  for (AssignNode*assignment : assignments){
    if (assignment && !assignment->match_position(qpos))
      return false;
  }
  uassert(bodynode->isPosition(),"LCN positionv",name);
  return bodynode->match_positionvalue(qpos,v);
}

bool LambdaCallNode::match_stringvalue(QPos*qpos,string*v){
  uassert(isString(),"LambdaCallNode: Unexpectedly getting string value of non-string ", name);
  for (AssignNode*assignment : assignments){
    if (assignment && !assignment->match_position(qpos))
      return false;
  }
  uassert(bodynode->isString(),"LCN stringv",name);
  return bodynode->match_stringvalue(qpos,v);
}

  
bool LambdaCallNode::match_position(QPos*qpos){
  for (AssignNode*assignment : assignments){
    if (assignment && !assignment->match_position(qpos))
      return false;
  }
  uassert(bodynode,"lcnmp int");
  return bodynode->match_position(qpos);
}

LambdaCallNode::LambdaCallNode(string n,
			       Environment*e,
			       vector<Node*>args,
			       LambdaValue l):name(n),environment(e),lambda(l){
  uassert(name.size()&&environment,"lcn lcn parameter");
  vector<Token*>body=lambda.body;

  /*the following hack removes the containing braces from a body of the form
  { n }
where n is an integer literal following Gamble email 5/2/2021 for 9.355 because
{n} is not a legal node*/
      
  if (body.size()==3){
    SpecialToken*ltoken=dynamic_cast<SpecialToken*>(body[0]);
    IntToken*btoken=dynamic_cast<IntToken*>(body[1]);
    SpecialToken*rtoken=dynamic_cast<SpecialToken*>(body[2]);
    if (ltoken&&btoken&&rtoken&&ltoken->eq("{")&&rtoken->eq("}"))
      body=vector<Token*>{btoken};
  }

  vector<string>newparameternames;
  int nparameters=(int)(args.size());
  uassert(nparameters==lambda.numberParameters(),"lcn paramcount");
  for (int i=0;i<lambda.numberParameters();++i){
    string oldparameter=lambda.parameters.at(i);
    Node* arg=args.at(i);
    uassert(arg,"null arg lcn");
    //A pieceide variable is now passed by reference although this can have surprising results
    // if user changes current position in the function body
    Variable*var=dynamic_cast<Variable*>(arg);
    string newparameter;
    if (!var){ //argument is a not variable
      stringstream s;
      s<<"CQL-"<<Tokens::nextid();
      s<<"-"<<oldparameter;
      newparameter=s.str();
      uassert(!environment->find(newparameter) && myindex(newparameternames,newparameter)<0,"lcn internal new name");
    } // the argument is not a variable
    else newparameter=var->name;
    uassert(newparameter.size()," lcn newparam");
    newparameternames.push_back(newparameter);
    body=replacebody(body,newparameter,oldparameter);
    string errormessage;
    AssignNode* assignment=NULL;
    if(!var) {assignment = AssignNode::create(newparameter,environment,arg,false,errormessage);
      uassert(assignment,errormessage);
    }
    assignments.push_back(assignment);
  }
  uassert((int)(assignments.size())==nparameters,"lcn bad assignment");
  Tokens temptokens(body,environment);
  bodynode=temptokens.match_node();
  uassert(bodynode,"LambdaCallNode constructor: could not create body from passed tokens for name: ",name);
  uassert(bodynode,"LambdaCallNode constructor: could not create a filter from the body of the function: ", name);
  uassert (temptokens.eof(),"LambdaCallNode constructor: did not parse all of passed tokens for name: ",name);
}

vnode LambdaCallNode::children()const{
  vnode ret;
  ret.push_back(bodynode);
  for (auto assn : assignments)
    if (assn) ret.push_back(assn);
  return ret;
}

void LambdaCallNode::deepify(){
  for (int i=0;i<(int)(assignments.size());++i)
    if(assignments[i]) assignments[i]=assignments[i]->clone();
  bodynode=bodynode->clone();
}


vector<Token*> LambdaCallNode::replacebody(vector<Token*> tokens, string newname, string oldname){
  vector<Token*>ret;
  ret=tokens;
  uassert(newname.size()&&oldname.size(),"lcn replacebody args");
  //  uassert(newname != oldname, "lcn names the same");
  Token* newtoken=new IdToken(newname);
  for (auto& token : ret){
    IdToken* idtoken=dynamic_cast<IdToken*>(token);
    if (!idtoken)continue;
    string testname=idtoken->value;
    uassert(testname.size(),"lcnrb testname");
    //    uassert(testname!=newname,"LambdaCallNode::replacebody: the new parameter name was found in the token list: ",newname);
    if (testname==oldname)
      token=newtoken;
  }
  return ret;
}

  
