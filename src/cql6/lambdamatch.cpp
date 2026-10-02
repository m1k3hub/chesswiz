#include "node.h"
#include "lambdavariable.h"
#include "tokens.h"
#include "lambdacallnode.h"
#include "environment.h"

Node* Tokens::match_lambda_definition(){
  if (!match_keyword("function"))return NULL;
  string name = match_id();
  if (name.empty())
    show_error("expecting the name of the function (an id) after 'function'");
  if (environment->find(name))
    show_error("Cannot reuse a variable which already exists for function definition: ", name);
  if(!match_lparen())
    show_error("missing '(' after function name");
  vector<string>parameters;
  while(true){
    if (match_rparen()) break;
    string param=match_id();
    if (param.empty())
      show_error("Could not parse parameter list: could not parse formal parameter in function named: ",name);
    if(myindex(parameters,param)>=0)
      show_error("duplicated parameter in formal parameter list");
    parameters.push_back(param);
  }
  if(0) printf("match_lambda_definition matching body for: %s\n",name.c_str());
  vector<Token*>body=match_lambda_body();
  if(0) printf("got body of length: %zu\n",body.size());
  if (body.empty())
    show_error("Could not parse body in function definition named: ",name);
  LambdaValue lambda(parameters,body);
  if(0)printf("got lambda of: %s\n",lambda.toString().c_str());
  LambdaVariable *var=environment->createLambdaVariable(name,lambda);
  uassert(var,"lambda define int");
  uassert(var->isBound(),"ld internal");
  return var;
}
  
vector<Token*> Tokens::match_lambda_body(){
  vector<Token*> tokens;
  int nbraces=0;
  int x=save();
  if (!match_lbrace())
    return tokens;
  restore(x);
  nbraces=0;
  while(true){
    if (eof())
      show_error("Missing '}' in function definition: unterminated list");
    Token*token=current();
    uassert(token,"mlb internal");
    if (match_special("{"))
      ++nbraces;
    else if (match_special("}"))
      --nbraces;
    else forward();
    tokens.push_back(token);
    uassert(nbraces>=0,"mlb nbraces");
    if (nbraces==0)break;
  } // while(true, the main loop)
  uassert(nbraces==0,"mlb final");
  return tokens;
}

LambdaCallNode* Tokens::match_lambda_use(){
  int x=save();
  Variable*v=match_variable_use();
  if(!v)return NULL;
  LambdaVariable*lv=v->asLambda();
  if(!lv){restore(x);return NULL;}
  string name=lv->name;
  LambdaValue lambda=lv->getValue();
  int expected=lambda.numberParameters();
  vector<Node*>actuals;
  if(!match_lparen())
    show_error("Use of function must be followed by left paren with list of actual parameters",name);
  while(true){
    if(match_rparen())break;
    Node*arg=match_node();
    if(!arg) show_error("Could not parse list of actual parameters in function use: ",name);
    actuals.push_back(arg);
  }
  if((int)(actuals.size())!=expected){
    stringstream s;
    s<<"Expecting: "<<expected<<" parameters but got: "<<actuals.size()<<" parameters in call of function: "<<name;
    show_error(s.str());
  }
  return new LambdaCallNode(name,environment,actuals,lambda);
}

