#pragma once
#include<string>
using std::string;
class GameSortInfo{
 public:
  string data;
  int gamenumber{-1};
  vector<SortValue> values;
  string thisclass()const{return "GameSortInfo";}
  GameSortInfo(string d, vector<SortValue> values,int gamen);
  void print();
  static void sort(vector<GameSortInfo>&);
  void output(FILE* ostream) const;
  static void output(FILE* ostream,const vector<GameSortInfo>&);
  static void preamble(const vector<GameSortInfo>&);
  static void output(string outputfile, const vector<vector<GameSortInfo>>& results);
};
bool operator< (const GameSortInfo& a, const GameSortInfo& b);

