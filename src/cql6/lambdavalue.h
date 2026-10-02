#pragma once
#include "abbreviations.h"
#include "token.h"
class LambdaValue{
public:
  LambdaValue(vector<string>,vector<Token*>);
  vector<string> parameters;
  vector<Token*> body;
  int numberParameters(){return (int)(parameters.size());}
  string toString();
  string thisclass()const{return "LambdaValue";}
void print();
};

