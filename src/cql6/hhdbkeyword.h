#pragma once
#include <vector>
#include <string>
#include <map>
using std::string;
using std::vector;
using std::pair;
using std::map;
class HhdbKeyword{
public:
  static bool isKey(const string &);
  static bool isPlayerBlackKey(const string&); //search directly in playerblack
  static bool isAwardKey(const string&);
  static bool isOtherKey(const string&); //not award, not playerblack
  static string matchAbbreviation(const string &abbreviation);
  static bool isAbbreviation(const string &key);
  static bool isAwardTypeKey(const string&key);
  static bool takesParameterKey(const string&key);
  static bool isQuotedKey(const string&key);
  static string showKeys();
  static vector<string>allKeys();
  static string showStipulationParameters();
  static bool isStipulationParameter(const string& parameter);
  static bool isGbrKey(const string& parameter);
  static string cql_from_key(const string&key);

 private:
  static bool isIn(const vector<string>& keys, const string& val);
  static const vector<string>playerBlackKeys;
  static const vector<string>otherKeys; 
  static const vector<pair<string,string>> abbreviationMap;
  static const vector<string> awardKeys; //keys related to awards
  static const vector<string>awardTypeKeys; //prize, hm, commendation, award
  static const vector<string>takesParameterKeys; //keys that take 1 parameter following
  static const vector<string>stipulationParameters;//valid strings that can follow 'hhdb stipulation'
  static const vector<string>gbrKeys; //material, pawns, kings
  static const map<string,string>KeyToCql;
};
