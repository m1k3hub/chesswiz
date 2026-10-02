#include "node.h"
#include "tokens.h"
#include "environment.h"
#include "nodeheaders.h"

Variable* Tokens::match_variable_use(){
  int x=save();
  string name=match_id();
  if(name.empty())return NULL;
  Variable*v =environment->find(name);
  if(!v){
    restore(x);
    return NULL;
  }
  return v;
}

  

PlyNode* Tokens::match_plynode(){
  if(!match_keyword("ply"))return NULL;
  return new PlyNode();
}

Node* Tokens::match_movenumbernode(){
  if(!match_keyword("movenumber")) return NULL;
  return new MoveNumberNode();
}

GameNumberNode* Tokens::match_gamenumbernode(){
  if(!match_keyword("gamenumber")) return NULL;
  Range * r=new Range(-1000,1000000000);
  return new GameNumberNode(r);
}

GameNumberNode* Tokens::match_gamenumberrange(){
  if(!match_keyword("gamenumber")) return NULL;
  Range* r=match_constant_range();
  if (!r)
    show_error("Expected range after 'gamenumber'");
  return new GameNumberNode(r);
}



Node* Tokens::match_compoundnode(){
  vector<Node*> nodes;
  int x=save();
  if (match_repeat_range()){
    restore(x);
    return NULL;
  }
  if(!match_lbrace()) return NULL;
  nodes=match_some_basicnodes();
  if(nodes.size()==0)
    show_error("syntax error following a '{' : expected a filter");
  bool rp=match_rbrace();
  if(!rp)
    show_error("Syntax error while trying to parse list of filters: could not parse filter inside '{...}'");
  if(nodes.size()==1 &&
     !nodes.front()->isSequence()&&
     !nodes.front()->isPathNode()&&
     !nodes.front()->isVariable()){ //allow f({v}) to inhibit pass-by-name in functions
    nodes.front()->removedParens=true;
    return nodes.front();} 
  return new CompoundNode(nodes);
}



NotNode* Tokens::match_notnode(){
  if(!match_keyword("not")) return NULL;
  Node*node=match_and_x();
  if(!node)
    show_error("could not get filter argument for 'not'");
  return new NotNode(node);
}


Node* Tokens::match_pinnode(){
  if(!match_keyword("pin"))return NULL;
  SetBase*from{NULL};
  SetBase*through{NULL};
  SetBase*to{NULL};
  bool returnfrom{false};
  bool returnto{false};
  bool returnthrough{false};
  int keywordindex{0};
  while(++keywordindex>0){
    if (match_keyword("from")){
      if(from)
	show_error("Multiple 'from' detected in 'pin'");
      from=match_setparameter();
      if(!from)
	show_error("Missing set filter following 'from' in 'pin'");
      if(keywordindex==1) returnfrom=true;
    }
    else if (match_keyword("through")){
      if(through)
	show_error("Multiple 'through' detected in 'pin'");
      through=match_setparameter();
      if(!through)
	show_error("Missing set filter following 'through' in 'pin'");
      if(keywordindex==1)returnthrough=true;
    }
    else if (match_keyword("to")){
      if(to)
	show_error("Multiple 'to' detected in 'pin'");
      to=match_setparameter();
      if(!to)
	show_error("Missing set filter following 'to' in 'pin'");
      if(keywordindex==1)returnto=true;
    }
    else break;
  }//while(true)
  if(returnfrom+returnthrough+returnto==0) returnthrough=true;
  uassert(returnfrom+returnthrough+returnto==1,"pinnode parse: internal");
  return new PinNode(from,through,to,returnfrom,returnthrough,returnto);
}

RayNode* Tokens::match_raynode(){
  bool xray=false;
  if(match_keyword("ray"))
    xray=false;
  else if (match_keyword("xray"))
    xray=true;
  else return NULL;
  bool isattack=false;
  vector<Direction> directions;
  if(!xray)directions=match_raydirections(&isattack);
  if(xray&&isattack)
    show_error("cannot specify 'xray attack'");
  if(xray)isattack=true;
  if (directions.empty())
    directions=Direction::allDirections();
  if(!match_lparen())
    show_error("Expecting '(' character after list of directions in the ray");
  vector<Node*>nodes=match_some_basicnodes();
  vector<SetBase*>constituents;
  for(auto node:nodes)
    constituents.push_back(dynamic_cast<SetBase*>(node));
  for(auto set:constituents)
    if(!set||!set->isSet())
      show_error("All parameters to ray must be sets");
  if(!match_rparen())
    show_error("Expected ')' character after arguments to ray");
  eassert(constituents.size()>1,"Must have at least two arguments to a ray");
  return new RayNode(directions,
		     constituents,
		     isattack,
		     NULL,
		     false); // the last false is whether to return first (true) or last value, added in 9.450
}

vector<Direction> Tokens::match_raydirections(bool*isattack){
  vector<Direction> directions;
  if (match_keyword("attack")||match_keyword("attacks")){
    directions=Direction::allDirections();
    *isattack=true;
    return directions;
  }
  *isattack=false;
  while(true){
    StringToken *token=dynamic_cast<StringToken*>(current());
    if(!token) break;
    vector<Direction> these=Direction::directionsFromString(token->value);
    if(these.empty()) break;
    forward();
    for(auto d:these){
      for(auto seen:directions)
	eassert(!d.eq(seen),"Duplicate directions in ray specification");
      directions.push_back(d);
    }
  }
  return directions;
}

      
vector<directionT>Tokens::directionsFromRayKeyword(KeywordToken *k){
  uassert(k,"T::dfr null k");
  if(k->eq("rayorthogonal"))
    return vector<directionT>{UP, DOWN, LEFT, RIGHT};
  else if (k->eq("raydiagonal"))
    return vector<directionT>{UP_LEFT, UP_RIGHT, DOWN_LEFT, DOWN_RIGHT};
  else if (k->eq("rayattack")||k->eq("ray"))
    return vector<directionT>{
      UP, DOWN, LEFT, RIGHT,
	UP_LEFT, UP_RIGHT, DOWN_LEFT, DOWN_RIGHT};
  uassert(false, "Unknown ray keyword: ", k->value);
  return vector<directionT>{};
}
    
Node* Tokens::match_simplenode(){
  if(match_keyword("check"))
    return new CheckNode();
  if(match_keyword("stalemate"))
    return new StalemateNode();
  if(match_keyword("mate"))
    return new MateNode();
  if(match_keyword("wtm"))
    return new ToMoveNode(WHITE);
  if(match_keyword("btm"))
    return new ToMoveNode(BLACK);
  if(match_keyword("initial"))
    return new InitialNode();
  if(match_keyword("variation"))
    return new InVariationNode();
  if(match_keyword("mainline"))
    return new InMainlineNode();
  if(match_keyword("terminal"))
    return new TerminalNode();
  return NULL;
}

VariationsNode* Tokens::match_variationsnode(){
  if(match_keyword("variations"))
    return new VariationsNode();
  return NULL;
}

KeywordToken*Tokens::match_raykeyword(){
  int x=save();
  char*keys[]={"ray","rayorthogonal","raydiagonal","rayattack"}; //leaving old style
  size_t nkeys = sizeof(keys)/sizeof(char*);
  KeywordToken *t=dynamic_cast<KeywordToken*>(current());
  forward();
  if(!t)return NULL;
  for(int i=0;i<nkeys;++i)
    if(t->eq(keys[i]))return t;
  restore(x);
  return NULL;
}


OrbitNode* Tokens::match_orbitnode(){
  OrbitNode*t=NULL;
  if(!t) t=match_fliptransform();
  if(!t) t=match_shifttransform();
  return t;
}

int Tokens::nextid(){
  return Tokens_nextid++;
}


  
MatchCountNode* Tokens::match_matchcountnode(){
  bool sort=false;
  if (match_keywords("sort","matchcount"))
    sort=true;
  else if(!match_keyword("matchcount"))
    return NULL;
  Range * range= match_constant_range();
  if(!range)
    show_error("missing constant range, eg. '1 20', following 'matchcount' keyword");
  return new MatchCountNode(range,sort);
}
  
/*match_stringtointnode() in theory parses correctly
  int "23" + "34" 
  and
  int "23" + 1
  but the complexity might be huge
*/

Node* Tokens::match_stringtointnode(){
  if(!match_keyword("int"))
    return NULL;
  Node*arg=match_string(); 
  if(!arg)
    show_error("expected a string filter following 'int'");
  uassert(arg->isString(),"mstin internal isString()");
  return new StringToIntNode(arg);
}

Node* Tokens::match_player(){
  int x=save();
  if (!match_keyword("player"))
    return NULL;
  if (match_keyword("black")||match_keyword("white")){
    restore(x);
    return NULL;
  }
  Node* players= node_from_string
    (R"END(notransform player white + "\n" + player black)END");
  return match_trailing_quoted_string(players);
}


Node* Tokens::match_tagbuiltinnode(){
  string target;
  if (match_keyword("site"))
    target="Site";
  else if (match_keywords("player","white"))
    target="White";
  else if (match_keywords("player","black"))
    target="Black";
  else if (match_keyword("event"))
    target="Event";
  else if (match_keyword("date"))
    target="Date";
  else if (match_keyword("eventdate"))
    target="EventDate";
  else if (match_keyword("eco"))
    target="ECO";
  else return NULL;
  Node*tagnode=new TagBuiltInNode(target);
  return match_trailing_quoted_string(tagnode);
}
  

EloNode* Tokens::match_elonode(){
  if(!match_keyword("elo"))
    return NULL;
  colorT color=match_color();
  Range* range=new Range(1,100000);
  return new EloNode(range,color);
}

YearNode* Tokens::match_yearnode(){
  if(!match_keyword("year"))
    return NULL;
  Range* range=new Range(1,10000);
  return new YearNode(range);
}

ResultNode* Tokens::match_resultnode(){
  if(!match_keyword("result"))
    return NULL;
  StringToken*token=match_stringtoken();
  if(!token) show_error("expecting 1-0 or 0-1 or 1/2-1/2 following result");
  string name=token->value;
  uassert(name.size(),"m_rn internal");
  if(name=="1-0" || name=="0-1" || name=="1/2-1/2")
    return new ResultNode(name);
  show_error("Expecting '1-0' or '0-1' or '1/2-1/2' following 'result' but got: ", name);
  return NULL;
}


StringToken*Tokens::match_stringtoken(){
  StringToken*n=dynamic_cast<StringToken*>(current());
  if(n)forward();
  return n;
}

vector<Node*> Tokens::match_some_basicnodes(){
  vector<Node*>v;
  while(true){
    Node* n=match_node();
    if(!n) break;
    v.push_back(n);
  }
  return v;
}


KeywordToken* Tokens::match_keyword(string v){
  KeywordToken* token=dynamic_cast<KeywordToken*>(current());
  if(token&&token->eq(v)){
    forward();
    return token;
  }
  return NULL;
}

bool Tokens::match_keywords(string v1, string v2){
  int x=save();
  if(match_keyword(v1)&&match_keyword(v2)) return true;
  restore(x);
  return false;
}


PieceLoc* Tokens::match_pieceloc(){
  PieceDesignatorToken* t =
    dynamic_cast<PDT*>(current());
  if(!t) return NULL;
  else
    forward();
  return new PieceLoc(t->pieces,
		      t->squares);
}

Node* Tokens::match_parens(){
  if(!match_lparen())return NULL;
  if(match_rparen())
    show_error("An empty parenthesized expression was unexpectedly seen");
  Node*node=match_node();
  if(!node)
    show_error("Cannot parse expression after '(', expected a filter");
  if(!match_rparen())
    show_error("A parenthesized expression must contain exactly one filter here. Expected a ')' following the first filter");
  if (node->isVariable()) //allow a variable to passed to a function by enclosing it in parens and inhibiting pass-by-name
    return new CompoundNode(vector<Node*>{node}); 
  node->removedParens=true; 
  return node;
}

NumberNode* Tokens::match_numbernode(){
  int val{1000};
  if(match_intvalue(&val))
    return new NumberNode(val);
  return NULL;
}




bool Tokens::match_intvalue(int*value){
  int x=save();
  bool negate=false;
  if(match_special("-"))negate=true;
  IntToken *ip=dynamic_cast<IntToken*>(current());
  if(!ip){
    restore(x);
    return false;
  }
  forward();
  int v=ip->value;
  uassert(v>=0,"match_intvalue: bad int token");
  if (negate) v= -v;
  *value=v;
  return true;
}

  
  
Node* Tokens::match_makesquare(){
  if(!match_keyword("makesquare"))return NULL;
  const string syntax=
    R"E(Use either
         makesquare (x y)
      where 'x' and 'y' are numeric indicators of the
      file and the rank of the square to be constructed, or
          makesquare z
      where 'z' is a string filter, like "e4", indicating the
      name of the square to be constructed)E";
  bool seenlparen=match_lparen();
  Node*firstarg=match_sortable();
  if(!firstarg)
    show_error("Invalid makesquare syntax: no valid argument\n"s + syntax);
  uassert(firstarg->isNumeric()||firstarg->isString(),"mms parse 1");
  if(firstarg->isString()){
    if(seenlparen&&!match_rparen())
      show_error("missing right paren after 'makesquare (string'. )\n"s + syntax);
    return new MakeSquareNode(firstarg);
  }
  uassert(firstarg->isNumeric(),"mms parse: unexpected type in first arg");
  if(!seenlparen)
    show_error("Invalid makesquare syntax: missing left paren with numeric argument.\n"s + syntax);
  Node*secondarg=match_numeric();
  if(!secondarg)
    show_error("could not parse second numeric argument to 'makesquare'.\n"s+syntax);
  if(!match_rparen())
    show_error("missing ')' following 'makesquare (numeric numeric'.\n"s+syntax);
  return new MakeSquareNode(firstarg,secondarg);
}

Node* Tokens::match_squarecoordinate(){
  bool isrank{false};
  if(match_keyword("rank"))
    isrank=true;
  else if (match_keyword("file"))
    isrank=false;
  else
    return NULL;
  SetBase*square=match_set();
  if(!square)
    show_error("rank/file must be followed by a set filter");
  return new SquareCoordinateNode(square,isrank);
}



/*modified for build 9.192 to put space between arguments for
  bug CQLI9.186-10 reported by Gamble*/
void Tokens::show_error(string m1, string m2){
  if (m1.empty()) show_error(m2);
  else if (m2.empty()) show_error(m1);
  else if(m1.back()==' ')
    show_error(m1+m2);
  else show_error((m1+' '),m2);
}

void Tokens::show_error(string message){
  stringstream s;
  s<<"\nCQL syntax error: "<<message;
  if(eof())
    s<<" (end of file) \n";
  else{
    s<<"\nUnable to parse the following token: ";
    s<<current()->toString();
    s<<'\n';
  }
  if(CqlGui&&!eof()){
    int linenumber=current()->lineNumber;
    int columnnumber=current()->columnNumber;
    cql_gui_exit(s.str(),linenumber,columnnumber);
  }
  cql_exit(s.str());
}

VectorNode* Tokens::match_vectornode(){
  DirectionParameter*p=match_directionparameter();
  if(!p)return NULL;
  SetBase*source=match_setparameter();
  if(!source)
    show_error("expecting a set specifier following the direction parameter");
  return new VectorNode(*p,source);
}

vector<Direction>Tokens::match_direction(){
  StringToken*token=dynamic_cast<StringToken*>(current());
  if(!token)return vector<Direction>{};
  string v=token->value;
  vector<Direction> directions=Direction::directionsFromString(v);
  if(directions.empty()){
    return directions;
  }
  forward();
  return directions;
}
  
DirectionParameter* Tokens::match_directionparameter(){
  vector<Direction> directions=match_direction();
  if(directions.empty())return NULL;
  Range *range=match_range();
  if (!range) range= new Range(1,7);
  DirectionParameter*p=new DirectionParameter(directions,range);
  return p;
}

FindNode* Tokens::match_findnode(){
  if(!match_keyword("find"))return NULL;
  bool isquiet{false};
  bool isfuture{true};
  bool isall{false};
  Range*range{NULL};
  while(true){
  if(match_keyword("quiet"))isquiet=true;
  else if(match_keyword("all"))isall=true;
  else if (match_leftarrow())isfuture=false;
  else if (!range&&((range=match_range())));
  else break;
  }
  if(isall&&range)
    show_error("find with both a range and 'all': use one or the other");
  if(isall)
    range=new Range(1,1000000);
  Node*node=match_node();
  if(!node)
    show_error("Expected a filter following 'find'");
  return new FindNode(node,range,isfuture,isquiet);
}


// handle the '#' character, for strings, dictionaries and sets
// the parsing of strings is probably incorrect or confusing:
// #"foo" + "bar" will be parsed as
// {#"foo"} + "bar" or error, perhaps. 
Node* Tokens::match_count_something(){
  if(!match_special("#")) return NULL;
  Dictionary*dictionary=match_dictionary();
  if (dictionary)
    return new DictionaryCountNode(dictionary);
  int x=save();
  Node*setnode=match_set();
  if(setnode) return new CountSquaresNode(setnode->asSet());
  restore(x);
  Node*stringnode=match_string();
  if(stringnode)
    return new StringLengthNode(stringnode);
  show_error("Expected either a string filter or a set filter following '#' but the filter parsed was of neither type");
  return NULL;
}
  

SetBase* Tokens::match_inexpr(){
  if(!match_keyword("in"))
    return NULL;
  SetBase*ret=match_set();
  if(!ret)
    show_error("Expecting a set expression following the 'in' keyword in 'square' expression");
  return ret;
}

BetweenNode* Tokens::match_betweennode(){
  if(!match_keyword("between"))
    return NULL;
  if(!match_lparen())
    show_error("arguments to 'between' should be enclosed in parens: missing '('");
  SetBase* source=match_set();
  if(!source)
    show_error("Expected a source set following 'between'");
  SetBase* target=match_set();
  if(!target)
    show_error("Expected a target set following 'between' and the source");
  if(!match_rparen())
    show_error("arguments to 'between' should be enclosed in parens: missing ')'");

  return new BetweenNode(source,target);
}

ExtensionNode* Tokens::match_extensionnode(){
  if(!match_keyword("extension"))
    return NULL;
  return new ExtensionNode();
}

AnyNode* Tokens::match_anynode(){
  if(match_keyword("any"))
    show_error("The 'any' keyword has been replaced by the '.' character since version 5.2. Use '_' instead of '.' to denote an empty square");
  if(match_special("."))
    return new AnyNode();
  return NULL;
}

Node* Tokens::match_powernode(){
  if(!match_keyword("power"))
    return NULL;
  SetBase*set=match_set();
  if(!set)
    show_error("Expected a set following 'power'");
  auto powernode=new PowerNode(set);
  return powernode;
}


Node* Tokens::match_squareloopnode(){
  bool isAll{false};
  if(!match_keyword("square")) return NULL;
  if (match_keyword("all"))
    isAll=true;
  SquareVariable*sv=match_squarevariable();
  if(!sv) show_error("Expecting a square variable in 'square' keyword specification");
  SetBase*target=match_inexpr();
  if(!target)
    show_error ("Missing 'in' following the variable name in 'square' expression");
  Node*body=match_node();
  if(!body) show_error("No filter following 'square .. in expr..'");
  return new SquareLoopNode(sv,target,body,isAll);
  
}

Node* Tokens::match_pieceloopnode(){
  bool isAll{false};
  if(!match_keyword("piece")) return NULL;
  if (match_keyword("all"))
    isAll=true;
  PieceIdVariable*tv=match_pieceidvariable();
  if(!tv) show_error("Expecting a piece variable in 'piece' keyword specification");
  SetBase*target=match_inexpr();
  if(!target)
    show_error ("Expected 'piece variable in setfilter filter' or 'piece variable = setfilter' but  neither 'in' nor '=' followed 'piece' ",tv->name); //modified 8/20/2019 per Costeff
  Node*body=match_node();
  if(!body)
    show_error("missing body in piece filter");
  return new PieceLoopNode(tv,target,body,isAll);
}

Node* Tokens::match_hascommentnode(){
  if(!match_keyword("hascomment")&&!match_keyword("originalcomment"))
    return NULL;
  int quotestart=save();
  string re;
  bool hasre=match_quotedstringvalue(&re);
  if (!hasre) return new HasCommentNode();
  if(re=="$0")
    show_error("'originalcomment' cannot search for apparent NAG of '$0'");
  int nag=HasCommentNode::nag_from_string(re);
  if(nag>255)
    show_error("'originalcomment' cannot search for apparent NAG greater than 255: ",re);
  if(nag>0)
    return new HasCommentNode(nag);
  restore(quotestart);
  return match_trailing_quoted_string
    (new HasCommentNode());
}

/*This matches a nonempty quoted string. If an empty quoted string
  is seen or if a non-quoted-string token is seen, then "" is returned
  and the stack unchanged
*/
string Tokens::match_nonemptyquotedstring(){
  QuotedStringToken*q=dynamic_cast<QuotedStringToken*>(current());
  if(!q) return "";
  if (q->value.empty()) return "";
  forward();
  eassert(q->value.size(),"Illegal empty quoted string");
  return q->value;
}

bool Tokens::match_quotedstringvalue(string *stringp){
  QuotedStringToken*q=dynamic_cast<QuotedStringToken*>(current());
  if(!q) return false;
  *stringp = q->value;
  forward();
  return true;
}

StringLiteralNode* Tokens::match_stringliteralnode(){
  string name;
  if (match_quotedstringvalue(&name))
    return new StringLiteralNode(name);
  return NULL;
}

colorT Tokens::match_color(){
  if (match_keyword("white"))return WHITE;
  if (match_keyword("black"))return BLACK;
  return NOCOLOR;
}


string Tokens::match_relationoperator(){
  int x=save();
  string name=match_special();
  if(name.empty())return "";
  auto names=RelationalNode::allNames();
  uassert(names,"mro int");
  if(myindex(*names,name)>=0)
    return name;
  restore(x);
  return "";
}
/* match the '+' character when not used as a regex operator.
 */   
string Tokens::match_plusoperator(){
  int x=save();
  if (match_wildcardcharacter().size()){
    restore(x);
    return "";
  }
  string name=match_special();
  if (name.empty())return "";
  if (name=="+") return name;
  restore(x);
  return "";
}

/*match '+' or '-' when not used as a regex operator*/
string Tokens::match_addoperator(){
  int x=save();
  if (match_wildcardcharacter().size()){
    restore(x);
    return "";
  }
  string name=match_special();
  if (name.empty())return "";
  if (name=="+" || name=="-") return name;
  restore(x);
  return "";
}

     
string Tokens::match_multoperator(){
  int x=save();
  if (match_wildcardcharacter().size()){
    restore(x);
    return "";
  }
  string name=match_special();
  if (name.empty())return "";
  if (name=="*" || name=="/" || name=="%") return name;
  restore(x);
  return "";
}
  
string Tokens::match_arithmeticoperator(){
  string addop=match_addoperator();
  if(addop.size())return addop;
  return match_multoperator();
}


string Tokens::match_special(){
  Token* token=current();
  auto special=dynamic_cast<SpecialToken*>(token);
  if (special){
    forward();
    return special->value;
  }
  return "";
}


bool Tokens::match_bar(){
  return match_special("|");
}

bool Tokens::match_tildetilde(){
  return match_special("~~");
}

bool Tokens::match_colon(){
  return match_special(":");
}

bool Tokens::match_ampersand(){
  if (match_keyword("on"))
    show_error("the 'on' keyword has been replaced by the & symbol in CQL version 6");
  return match_special("&");
}

bool Tokens::match_lparen(){
  return match_special("(");
}

bool Tokens::match_rparen(){
  return match_special(")");
}

bool Tokens::match_lbrace(){
  return match_special("{");
}

bool Tokens::match_rbrace(){
  return match_special("}");
}
bool Tokens::match_lbracket(){
  return match_special("[");
}

bool Tokens::match_equalsign(){
  return match_special("=");
}

bool Tokens::match_rbracket(){
  return match_special("]");
}

bool Tokens::match_comma(){
  return match_special(",");
}

bool Tokens::match_star(){
  return match_special("*");
}

bool Tokens::match_plus(){
  return match_special("+");
}

bool Tokens::match_colonequal(){
  return match_special(":=");
}

bool Tokens::match_special(string v){
  SpecialToken*token=dynamic_cast<SpecialToken*>(current());
  if (token&&token->eq(v)){
    forward();
    return true;}
  return false;
}
  
string Tokens::match_id(){
  auto idtoken=dynamic_cast<IdToken*>(current());
  if (!idtoken) return "";
  forward();
  string name=idtoken->value;
  uassert(name.size(),"match_id internal");
  return name;
}

Node* Tokens::make_relational_op_node(const string& op, Node* left, Node*right){
  uassert(left&&right&&myindex(*RelationalNode::allNames(),op)>=0,"make_relational_op: bad args");
  if(myindex(*RelationalNode::positionComparisonNames(),op)>=0&&
     (!left->isPosition()||
      !right->isPosition())){
    stringstream s;
    s<<"Tried to make a comparison of two filters using the operation: "
     <<op
     <<" which expects position filters on its left and right sides. Got "
     <<" non-position filter";
    show_error(s.str());
  }

  if (left->isSet()&&right->isSet()&&op=="==")
    return new EqualityNode(left,right);
  else if (left->isSet()&&right->isSet()&&op=="!=")
    return new NotNode(new EqualityNode(left,right));
  else if (left->isSet()&&right->isNumeric())
    return make_relational_op_node(op,new CountSquaresNode(left->asSet()),right);
  else if (left->isNumeric()&&right->isSet())
    return make_relational_op_node(op,left,new CountSquaresNode(right->asSet()));
  else if (left->isPosition()&&right->isPosition()){
    return new RelationalNode(op,left,right);
  }
  else if (!left->isNumeric()&&!left->isString())
    show_error("left side of relational operator must be numeric or string: ", op);
  else if (!right->isNumeric()&&!right->isString())
    show_error("right side of relational operator must be numeric or string: ", op);
  else if (left->isNumeric()!=right->isNumeric() ||
	   left->isString()!=right->isString())
    show_error ("left side and right sides of relational operator are not both numeric or both string or both position: ", op);
  else if (op=="!=")
    return new NotNode(make_relational_op_node("==", left, right));
  return new RelationalNode(op,left,right);
}



/*Warning: for complex old-style (using then) if filters, the matching here is
  exponential
  The if node parse is split into two parts per Gamble email 4/9/2021 for
  if(test) and test2 then body
  which is very tough to parse without backtracking
*/

Node* Tokens::match_ifnode(){
  if (!match_keyword("if"))
    return NULL;
  Node* predicate=match_node();
  if(!predicate)
    show_error("No legal test clause found after the keyword 'if'");
  match_keyword("then"); //optional then since 6.1
  Node*thenfilter=match_node();
  if(!thenfilter){ //see comments above
    show_error("missing consequent following 'if testfilter' or 'if testfilter then'");
    return NULL;
  }
  Node*elseFilter=NULL;
  if (match_keyword("else"))
    elseFilter=match_node();
  return new IfNode(predicate,thenfilter,elseFilter);
}

SetBase*Tokens::match_connectedpawns(){
  if(!match_keyword("connectedpawns"))
    return NULL;
  string description=
    "{P & horizontal 1"
    " vertical 0 7 P}"
    " |"
    "{p & horizontal 1"
    " vertical 0 7 p}" ;
  return new NoTransformNode(set_from_string(description));
}

SetBase*Tokens::match_isolatedpawns(){
  if(!match_keyword("isolatedpawns"))
    return NULL;
  string connecteddescription=
    "{P & horizontal 1"
    " vertical 0 7 P}"
    " |"
    "{p & horizontal 1"
    " vertical 0 7 p}" ;
  string isolateddescription=
    "[Pp] & ~{"
    + connecteddescription
    + "}";
  return new NoTransformNode(set_from_string(isolateddescription));
}

SetBase* Tokens::match_doubledpawns(){
  if(!match_keyword("doubledpawns"))
    return NULL;
  string description =
    "{P & vertical P}"
    "| {p & vertical p}";
  return new NoTransformNode(set_from_string(description));
}

SetBase* Tokens::match_passedpawns(){
  if(!match_keyword("passedpawns"))
    return NULL;
  string description =
    "{P & {~down horizontal 0 1 p}}"
    " | "
    "{p & {~up horizontal 0 1 P}}";
  return new NoTransformNode(set_from_string(description));
}

Node* Tokens::match_fen(){
  if(!match_keyword("fen"))return NULL;
  string fen;
  if(!match_quotedstringvalue(&fen))
    return new CurrentFen();
  string message;
  Node * node=node_from_fen(fen,message);
  if(!node)
    show_error(message);
  return node;
}

VirtualMainlineNode* Tokens::match_virtualmainlinenode(){
  if(!match_keyword("virtualmainline")) return NULL;
  return new VirtualMainlineNode();
}

Node* Tokens::match_true(){
  if(!match_keyword("true"))return NULL;
  return new TrueNode();
}
Node* Tokens::match_false(){
  if(!match_keyword("false"))return NULL;
  return new NotNode(new TrueNode());
}
			    
CurrentNode* Tokens::match_currentnode(){
  if(!match_keyword("currentposition")&&!match_keyword("curpos"))return NULL;
  return new CurrentNode;
}

  
  
EchoNode*Tokens::match_echonode(){
  if(!match_keyword("echo"))return NULL;
  bool isquiet{false};
  if (match_keyword("quiet")) isquiet=true;
  if(!match_lparen())
    show_error("'echo' must be followed by '('");
  if(0)printf("match_echonode: matching sourcevar\n");
  PositionVariable*sourcevar=match_positionvariable();
  if(!sourcevar)
    show_error("missing position variable after 'echo ('");
  PositionVariable*targetvar=match_positionvariable();
  if(!targetvar)
    show_error("missing second position variable in echo");
  if(sourcevar==targetvar)
    show_error("source and target variables in 'echo' must be distinct");
  if(!match_rparen())
    show_error("missing right parenthesis after variables in 'echo(...'");
  bool searchall{false};
  if(match_keywords("in","all"))
    searchall=true;
  Node*filter=match_node();
  if(!filter)
    show_error("expected filter following 'echo(...)'");
  return new EchoNode(sourcevar,targetvar,filter,searchall,isquiet);
}



Node* Tokens::match_distancenode(){
  if(!match_keyword("distance"))
    return NULL;
  if(!match_lparen())
    show_error("distancenode: missing lparen following 'distance'");
  Node*left=match_node();
  if(!left)
    show_error("expected filter following 'distance ('");
  if(!left->isPosition())
    show_error("first argument to 'distance' not a position filter");
  Node*right=match_node();
  if(!right)
    show_error("expected filter following 'distance (filter'");
  if(!right->isPosition())
    show_error("second argument to 'distance' not a position filter");
  if(!match_rparen())
    show_error("missing right paren following two arguments to 'distance'");
  return new DistanceNode(left,right);
}

LcaNode* Tokens::match_lcanode(){
  if(!match_keyword("lca"))
    return NULL;
  if(!match_lparen())
    show_error("lcanode: missing lparen following 'lca'");
  Node*left=match_node();
  if(!left)
    show_error("expected filter following 'lca ('");
  if(!left->isPosition())
    show_error("first argument to 'lca' not a position filter");
  Node*right=match_node();
  if(!right)
    show_error("expected filter following 'lca (filter'");
  if(!right->isPosition())
    show_error("second argument to 'lca' not a position filter");
  if(!match_rparen())
    show_error("missing right paren following two arguments to 'lca'");
  return new LcaNode(left,right);
}

  
ExtremalNode*Tokens::match_extremalnode(){
  bool ismax=false;
  bool ismin=false;
  if(match_keyword("max"))
    ismax=true;
  else if (match_keyword("min"))ismin=true;
  else return NULL;
  uassert(ismax||ismin,"m_em: internal");
  string name;
  if(ismax) name="max";
  else name="min";
  if(!match_lparen())
    show_error("expected left parentheses following function: ",name);
  vector<Node*>args;
  while(true){
    if(match_rparen())break;
    Node*arg=match_sortable();
    if(!arg)
      show_error("Expected a list of numeric or string filters in parentheses following: ",name);
    args.push_back(arg);
    if ((arg->isString())!=(args[0]->isString()) ||
	(arg->isNumeric())!=(args[0]->isNumeric()))
      show_error("The arguments to 'max' or 'min' must either all be numeric or all be string");
  }
  if(args.size()<2)
    show_error("Expected at least two arguments to: ",name);
    
  return new ExtremalNode(args,ismax);
}

NoTransformNode* Tokens::match_notransformnode(){
  if(!match_keyword("notransform"))return NULL;
  Node*node=match_node();
  if(!node)
    show_error("Expecting a filter following 'notransform'");
  return new NoTransformNode(node);
}

ToMoveValueNode* Tokens::match_tomovevaluenode(){
  if(!match_keyword("sidetomove"))return NULL;
  return new ToMoveValueNode();
}

ColorValueNode* Tokens::match_colorvaluenode(){
  bool iswhite{false};
  bool isblack{false};
  if(match_keyword("white"))
    iswhite=true;
  else if (match_keyword("black"))
    isblack=true;
  else
    return NULL;
  uassert(iswhite+isblack==1,"m_cvn internal");
  colorT color{NOCOLOR};
  if(iswhite) color=WHITE;
  else color=BLACK;
  return new ColorValueNode(color);
}
  
Node* Tokens::match_consecutivemovesnode(){
  if (!match_keyword("consecutivemoves"))
    return NULL;
  Range*range{NULL};
  bool quiet{false};
  if(match_keyword("quiet")) quiet=true;
  range=match_range();
  if(match_keyword("quiet")) quiet=true;
  if(!range)
    range=new Range(1,100000);
  if(!match_lparen())
    show_error("consecutivemovesnode: missing lparen following 'consecutivemoves'");
  PositionVariable*left=match_positionvariable();
  if(!left)
    show_error("expected positoinvariable following 'consecutivemoves ('");
  PositionVariable*right=match_positionvariable();
  if(!right)
    show_error("expected positionvariable following 'consecutivemoves (filter'");
  if(!match_rparen())
    show_error("missing right paren following two arguments to 'consecutivemoves'");
  return new ConsecutiveMovesNode(left,right,range,quiet);
}

Range* Tokens::match_range(){
  if(match_keyword("count"))
    return new Range(-100000,100000);
  int valmin{-1000};
  int valmax{-1000};
  NumericVariable* varmin{NULL};
  NumericVariable* varmax{NULL};
  bool ret1=match_rangeconstituent(&valmin,&varmin);
  if(!ret1) return NULL;
  bool ret2=match_rangeconstituent(&valmax,&varmax);
  if(!ret2){
    valmax=valmin;
    varmax=varmin;}
  return new Range(valmin,valmax,varmin,varmax);
}

/*Look for either an integer or an existing numeric variable that
 * is NOT followed by an arithmetic operator or relational operator.
 * If so, set the appropriate pointer and return true
 */
bool Tokens::match_rangeconstituent(int* valp, NumericVariable**varp){
  int x=save();
  uassert(valp&&varp,"miornv internal");
  *varp=NULL;
  int intvalue{0}; //local copy of next int value
  NumericVariable*varvalue{NULL}; //local copy of next numeric variable
  bool matchedint{false}; //seen int?
  bool matchedvar{false}; // seen variable?

  if(match_intvalue(&intvalue))
    matchedint=true;
  else {
    varvalue=match_existingnumericvariable();
    if(!varvalue)return false;
    matchedvar=true;}
  //Now we have the appropriate variables in intvalue or varvalue
  //but we check the number is not part of a larger expression
  //we do it this way to avoid reparsing the whole expression
  uassert(matchedint+matchedvar==1,"mrc internal");
  int y=save(); //where we start looking at the next token to see if its an operator
  if(match_lparen()||match_lbrace()||match_rightarrow()||match_leftarrow()||
     match_rparen()||match_rbrace())
    restore(y);
  else if (match_special().size()){
    restore(x); //failure, so go back to the beginning
    return false;}
  restore(y); // Now push back the token we just possibly successfully read
  if(matchedint)
    *valp=intvalue;
  else if(matchedvar){
    uassert(varvalue,"range parse internal nv");
    *varp=varvalue;
  }
  return true;
}

Range* Tokens::match_constant_range(){
  int x=save();
  Range*range=match_range();
  if(!range)return NULL;
  if(range->isConstant())
    return range;
  restore(x);
  return NULL;
}


PositionIndexNode* Tokens::match_positionindexnode(){
  if(!match_keyword("positionid"))return NULL;
  return new PositionIndexNode();
}

Node* Tokens::match_type(){
  if(!match_keyword("type"))return NULL;
  SetBase*set=match_set();
  if(!set)
    show_error("expected set following 'type'");
  return new AbsNode(new ColorTypeNode (set));
}

TypeNameNode* Tokens::match_typenamenode(){
  if(!match_keyword("typename"))return NULL;
  SetBase*set=match_set();
  if(!set)
    show_error("expected set filter following 'typename', which should name a square");
  return new TypeNameNode(set);
}

PieceNameNode* Tokens::match_piecenamenode(){
  if(!match_keyword("piecename"))return NULL;
  SetBase*set=match_set();
  if(!set)
    show_error("expected set filter following 'typename', which should name a square");
  return new PieceNameNode(set);
}


AbsNode* Tokens::match_absnode(){
  if(!match_keyword("abs"))return NULL;
  Node*node=match_numeric();
  if(!node)
    show_error("expected a numeric filter following 'abs'");
  return new AbsNode(node);
}

ColorTypeNode* Tokens::match_colortypenode(){
  if(!match_keyword("colortype")) return NULL;
  SetBase*set=match_set();
  if(!set)
    show_error("Expected a set filter following 'colortype'");
  return new ColorTypeNode(set);
}

SetBase* Tokens::match_colorsquare(){
  bool islight{false};
  bool isdark{false};
  if (match_keyword("light"))
    islight=true;
  else if (match_keyword("dark"))
    isdark=true;
  else if (match_keyword("lightsquares"))
    show_error("'lightsquares' has been replaced by 'light .' in CQL 6. 'light set' is the light squares in set");
  else if (match_keyword("darksquares"))
    show_error("'darksquares' has been replaced by 'dark .' in CQL 6. 'dark set' is the dark squares in set");
  else return NULL;
  uassert(islight+isdark==1,"mcs internal");
  SetBase*set=match_setparameter();
  if(!set)
    show_error("expected a set filter following 'light' or 'dark'");
  return new SquareParityNode(set,islight);
}
    
SetBase* Tokens::set_from_string(const string &description){
  Node*node=node_from_string(description);
  uassert(node,"set_from_string: bad node");
  uassert(node->isSet(),"set_from_string: return node is not a set");
  return node->asSet();
}

//match_unaryminus should follow match_numbernode in matchcomplexnode.cpp
Node* Tokens::match_unaryminus(){
  if(!match_special("-"))
    return NULL;
  Node* node=match_substring_x(); //modified in 9.301 from match_attack_x
  if(!node || !node->isNumeric())
    show_error("No numeric filter following '-' symbol");
  Node*minus1=new NumberNode(-1);
  return make_op_node('*',minus1,node);
}

bool Tokens::match_leftarrow(){
  return match_special("<--");
}

bool Tokens::match_rightarrow(){
  return match_special("-->");
}

/* return the token of a dash if it exists.*/

DashToken* Tokens::getDash(){
  DashToken* dash= dynamic_cast<DashToken*>(current());
  if (dash==NULL) return dash;
  forward();
  return dash;
}
  

ChildNode*Tokens::match_childnode(){
  if(!match_keyword("child"))
    return NULL;
  Node* indexnode{NULL};
  if (match_lparen()){
    indexnode=match_numeric();
    if(indexnode==NULL)
      show_error("Expected a numeric filter following 'child ('");
    if(!match_rparen())
      show_error("expected a ')' following 'child(filter'");
  }
  if(!indexnode)
    indexnode=new NumberNode(0);
  return new ChildNode(indexnode);
}

ParentNode*Tokens::match_parentnode(){
  if(!match_keyword("parent"))
    return NULL;
  return new ParentNode();
}

PieceAssignNode* Tokens::match_pieceassignnode(){
  int x=save();
  if(!(match_keyword("piece")||
       match_symbolicpiecedeclaration()))
    return NULL;
  if(match_keyword("all")){
    restore(x);
    return NULL;
  }
  PieceIdVariable*tv=match_pieceidvariable();
  if (!tv)
    {restore(x);return NULL;}
  if (!match_special("=")){
    restore(x);
    return NULL;
  }
  SetBase*set=match_set();
  if(!set){
    stringstream s;
    s<<"Missing set filter following 'piece "<<tv->name<<"='";
    show_error(s.str());
  }
  return new PieceAssignNode(tv,set);
}

LoopNode* Tokens::match_loopnode(){
  if(!match_keyword("loop"))
    return NULL;
  Node* node=match_node();
  if(!node)
    show_error("Missing filter following 'loop'");
  return new LoopNode(node);
}


PieceIdNode* Tokens::match_pieceidnode(){
  if(!match_keyword("pieceid"))
    return NULL;
  SetBase*set=match_set();
  if(!set)
    show_error("expected a set filter or piece variable following 'pieceid'");
  return new PieceIdNode(set);
}

DescendantNode* Tokens::match_descendantnode(){
  bool isancestor{false};
  bool isdescendant{false};
  if (match_keyword("descendant"))
    isdescendant=true;
  else if (match_keyword("ancestor"))
    isancestor=true;
  else return NULL;
  uassert(isancestor+isdescendant==1,"mdn args");
  if(!match_lparen())
    show_error("descendantnode: missing lparen following 'descendant/ancestor'");
  Node*left=match_node();
  if(!left)
    show_error("expected filter following 'descendant/ancestor ('");
  if(!left->isPosition())
    show_error("first argument to 'descendant/ancestor' not a position filter");
  Node*right=match_node();
  if(!right)
    show_error("expected filter following 'descendant/ancestor (filter'");
  if(!right->isPosition())
    show_error("second argument to 'descendant/ancestor' not a position filter");
  if(!match_rparen())
    show_error("missing right paren following two arguments to 'descendant/ancestor'");
  
  if (isdescendant)
    return new DescendantNode(left,right);
  return new DescendantNode(right,left);
}  

SqrtNode* Tokens::match_sqrtnode(){
  if(!match_keyword("sqrt"))
    return NULL;
  Node* node=match_numeric();
  if(!node)
    show_error("Missing numeric filter after 'sqrt'");
  return new SqrtNode(node);
}
  
DepthNode*Tokens::match_depthnode(){
  if(match_keyword("depth"))
    return new DepthNode();
  return NULL;
}

GotoNode*Tokens::match_gotonode(){
  if (match_keyword("initialposition"))
    return new GotoNode(new NumberNode(0));
  if(!match_keyword("position"))
    return NULL;
  Node*node=match_numeric();
  if(!node)
    show_error ("'position' requires a numeric filter following it");
  return new GotoNode(node);
}

Node* Tokens::match_error(){
  if(match_rightarrow() || match_leftarrow())
    show_error
      ("Unexpected <-- or --> seen. Perhaps there is more than one filter between the separating <-- or --> of the 'line' filter.\n If so, try enclosing each constituent of the line filter in braces, or contact support for assistance.");
  return NULL;
}

  
Node* Tokens::match_assertvariationsnode(){
  if (!match_keyword("cql_assertvariations"))
    return NULL;
  string message=match_nonemptyquotedstring();
  if (message.empty())
    show_error("cql_assertvariations must be followed by nonempty quoted string");
  return new AssertVariationsNode(message);
}

Node*Tokens::match_tagnode(){
  if (!match_keyword("tag"))
    return NULL;
  string name=match_nonemptyquotedstring();
  string message;
  if (!TagNode::isQueryable(name,&message))
    show_error(message);
  return TagNode::create(name);
}

Node*Tokens::match_tagsetnode(){
  if(!match_keyword("settag"))
    return NULL;
  if (!match_lparen())
    show_error("'settag' should be followed by '(' which is missing here (and then the two arguments)");
  string name=match_nonemptyquotedstring();
  if(name.empty())
    show_error("'settag' must be followed by a left paren and nonempty quoted string: the first argument to settag should be a quoted string");
  string message;
  if (!TagSetNode::isSettable(name,&message))
    show_error(message);
  Node*node=match_node();
  if (!node)
    show_error("'settag' must be followed by a left paren, a nonempty quoted string and then a filter. The filter is missing here");
  if (!match_rparen())
    show_error("'settag' must be followed by a quoted string and a string filter enclosed in parentheses. The closing ')' is missing");
  if (node->isString())
    return new TagSetNode(name,node);
  //  else if (node->isSet() || node->isNumeric())
  //    return new TagSetNode(name,new StringConverter(node));
  else
    show_error("Expected a string filter following 'settag(\"xx\" '; could not parse second argument to settag");
  return NULL;
}

/* the stringindex filter is handled as:
   stringindex := 'indexof' (substring string)
*/
Node* Tokens::match_stringindex(){ //actually indexof
  if (!match_keyword("indexof"))
    return NULL;
  if(!match_lparen())
    show_error("expecting '(' following 'indexof'");
  Node*left=match_string();
  if(!left)
    show_error("could not get first argument to 'indexof', which must be a string");
  Node*right=match_string();
  if(!right)
    show_error("could not get second argument to 'indexof', which must be a string");
  if(!match_rparen())
    show_error("expected 'indexof (pattern string)' but missing right paren");
  return new StringInNode(left,right,true);
}
    
  
Node * Tokens::match_groupindexnode(){
  int group=0;
  string location;
  if(!match_groupindextoken(&group,&location))return NULL;
  uassert(group>=0,"Invalid negative group as group index");
  return new GroupNumberNode(group,location,true);
}

Node * Tokens::match_groupnumbernode(){
  int group=0;
  string location;
  if (!match_groupnumbertoken(&group,&location)) return NULL;
  if (group<0)
    show_error("The group number must be nonegative in expression '\\[0-9]'");
  if (group>99)
    show_error("The group number must be <100 in expression '\\[1-9]'");
  return new GroupNumberNode(group,location,false);
}

bool Tokens::match_groupnumbertoken(int *valp, string*locationp){
  GroupNumberToken*token=dynamic_cast<GroupNumberToken*>(current());
  if(!token)return false;
  forward();
  if(valp) *valp=token->value;
  if(locationp)*locationp=token->locationString();
  return true;
}

bool Tokens::match_groupindextoken(int *valp,string*locationp){
  GroupIndexToken*token=dynamic_cast<GroupIndexToken*>(current());
  if(!token)return false;
  forward();
  if(valp) *valp=token->value;
  if(locationp)*locationp=token->locationString();
  return true;
}

Node* Tokens::match_keyword_optional_regex(string keyword, const string&prefix){
  if(!match_keyword(keyword))
    return NULL;
  string re;
  bool hasre=match_quotedstringvalue(&re);
  stringstream s;
  s<<prefix;
  if (hasre)
    s<< " ~~ " << re;
  return node_from_string(s.str());
}

Node* Tokens::match_trailing_quoted_string(Node*node){
  if(!node->isString())return node;
  int x=save(); // start of the nonempty quoted string
  string parameter=match_nonemptyquotedstring();
  if (parameter.empty())return node;
  auto lbracket=parameter.find("[");
  if (lbracket!=string::npos&&
      parameter.find("]",lbracket)!=string::npos ||
      parameter.find_first_of("*+?",1)!=string::npos)
    {
      string messagetemplate =
	R"END(
Warning: Use of the search pattern
        ",parameter"
in a context in which this pattern is interpreted literally but might
have been intended to be a regular expression. Because this pattern
contains special characters, CQL believes the pattern might have been
intended as a regular expression. If the pattern was intended as a
regular expression, prefix it with ~~. For example (if searching
within 'event'):
    event ~~ ",parameter"
If you in fact intended to use the pattern literally, make the pattern
the left side of an 'in' filter, for example,
     ",parameter" in event)
For more information , see documentation on "implicit search".)END";
      show_error(util::replaceAll(messagetemplate,",parameter",parameter));
    }
  StringInNode *innode= new StringInNode(new StringLiteralNode(parameter),node);
  innode->isImplicit=true;
  innode->implicitParameterIndex=x;
  return innode;
}
  
    
Node* Tokens::match_assertnode(){
  Token*token=current();
  if (!match_keyword("assert"))
    return NULL;
  Node*node=match_node();
  if(!node)
    show_error("expected a filter following 'assert'");
  return new AssertNode(node,token->locationString());
}

AbortNode* Tokens::match_abortnode(){
  Token*token=current();
  if (!match_keyword("cql_abort"))
    return NULL;
  return new AbortNode(token->locationString());
}

Node*Tokens::match_isboundnode(){
  bool isbound{false};
  if (match_keyword("isbound"))
    isbound=true;
  else if (match_keyword("isunbound"))
    isbound=false;
  else return NULL;
  string name=match_nonemptyquotedstring();
  if (name.empty())
    name=match_id();
  if (name.empty())
    show_error("'isbound' and 'isunbound' must be followed by a quoted string or a variable name");
  Node*boundnode=new IsBoundNode(name);
  return isbound ? boundnode : new NotNode(boundnode);
}
    
  

  
StringAsciiNode* Tokens::match_stringasciinode(){
  if(!match_keyword("ascii"))
    return NULL;
  Node*node=match_sortable(); //string or numeric;
  if (!node)
    show_error ("expected a string filter or numeric filter following 'ascii'");
  if (node->isString())
    return new StringAsciiNode(node,AsciiDirection::ToAscii);
  else if (node->isNumeric())
    return new StringAsciiNode(node,AsciiDirection::FromAscii);
  uassert(false,"unexpected type of node following 'ascii'");
  return NULL;
}



BracketRange*Tokens::match_bracketrange(){
  if (!match_lbracket())
    return NULL;
  Node*left{NULL};
  Node*right{NULL};
  bool seencolon{false};
  if (match_colon()){
    left=new NumberNode(0);
    seencolon=true;
  }
  else
    left=match_numeric();
  if(!left)
    show_error ("expected numeric filter or ':' after '['");
  if (match_rbracket())
    return new BracketRange(left,right,!seencolon);
  if (!seencolon && !match_colon())
    show_error("expected ':' after '[numeric '");
  seencolon=true;
  //Now we match the right  hand side.
  if (match_rbracket())
    return new BracketRange(left,right,false);
  right=match_numeric();
  if (!right)
    show_error("expected numeric filter after '[numeric : '");
  if (!match_rbracket())
    show_error("missing ']' following '[numeric : numeric'");
  return new BracketRange(left,right,false);
}
	
ReadFileNode* Tokens::match_readfilenode(){
  if(!match_keyword("readfile"))
    return NULL;
#ifdef CQL6_EMBEDDED // scidb: file access is disabled in embedded mode; fail at PARSE time
  show_error("`readfile` is not available when CQL runs inside Scidb");
#endif
  Node*node=match_string();
  if(!node)
    show_error("expected a string filter following 'readfile'");
  return new ReadFileNode(node);
}

WriteFileNode* Tokens::match_writefilenode(){
  if(!match_keyword("writefile"))
    return NULL;
#ifdef CQL6_EMBEDDED // scidb: file access is disabled in embedded mode; fail at PARSE time
  show_error("`writefile` is not available when CQL runs inside Scidb");
#endif
  if(!match_lparen())
    show_error("expected '(' following 'writefile'");
  Node*filename=match_string();
  if (!filename)
    show_error("expected string filter, the filename, following 'writefile('");
  Node*content=match_string();
  if(!content)
    show_error("expected string filter, the content, following 'writefile(filename'");
  if(!match_rparen())
    show_error("malformed 'writefile': expected two parenthesized string arguments, got extra arguments");
  return new WriteFileNode(filename,content);
}

HhdbHasCookNode* Tokens::match_hhdbhascooknode(){
  if(match_keyword("cql_hhdbhascook"))
    return new HhdbHasCookNode();
  return NULL;
}

  
Node* Tokens::match_removecommentnode(){
  if(!match_keyword("removecomment"))
    return NULL;
  return new RemoveCommentNode();
}

CurrentTransformNode*Tokens::match_currenttransformnode(){
  if(!match_keyword("currenttransform"))
    return NULL;
  return new CurrentTransformNode();
}

Node*Tokens::match_whilenode(){
  if (!match_keyword("while"))
    return NULL;
  if (!match_lparen())
    show_error("expected '(' following 'while'");
  Node*test=match_node();
  if(!test)show_error("could not match test filter after 'while ('");
  if (!match_rparen())
    show_error("Missing ')' following 'while(...' expression ");
  Node*body=match_node();
  if(!body)
    show_error("Could not parse the body filter after 'while (...)'");
  StringMatchNode*tildetest=dynamic_cast<StringMatchNode*>(test);
  if(tildetest&&!tildetest->removedParens){
    Node*target=tildetest->targetNode;
    string pattern=tildetest->thePattern;
    uassert(target,"expected valid target:match_whileregex internal");
    return new StringIteratorNode(target,pattern,body);
  }
  else
    return new WhileNode(test,body);
}

Node* Tokens::match_emptyset(){
  if(match_special("[]"))
    return node_from_string("~.");
  else return NULL;
}

/*this will fail silently if the variable is a dictionary*/
Node* Tokens::match_unbind(){
  if (!match_keyword("unbind"))
    return NULL;
  Variable*v=match_variable_use();
  if (!v)
    show_error("following 'unbind' expected the name of existing variable");
  uassert(v,"expected a variable here in tmu");
  uassert(!v->isDictionary(),"unexpected parse issue in match_unbind: did not expect dictionary here");
  return new UnbindNode(v);
}
  
CaseConvertNode*Tokens::match_caseconvertnode(){
  CaseConvertDirection d=CaseConvertDirection::None;
  if(match_keyword("uppercase"))
    d=CaseConvertDirection::ToUpper;
  else if (match_keyword("lowercase"))
    d=CaseConvertDirection::ToLower;
  else return NULL;
  Node*node=match_string_simple();
  if (!node)
    show_error("expected a string filter following 'uppercase' or 'lowercase'");
  return new CaseConvertNode(node,d);
}

PathStartNode*Tokens::match_pathstartnode(){
  if(match_keyword("pathstart"))
    return new PathStartNode();
  return NULL;
}

PathDebugNode*Tokens::match_pathdebugnode(){
  if(match_keyword("pathdebug"))
    return new PathDebugNode();
  return NULL;
}

PathCountNode*Tokens::match_pathcountnode(){
  if(match_keyword("pathcount"))
    return new PathCountNode();
  return NULL;
}

PathLastPositionNode*Tokens::match_pathlastpositionnode(){
  if(match_keyword("pathlastposition"))
    return new PathLastPositionNode();
  return NULL;
}

Node*Tokens::match_pathcountunfocused(){
  if(match_keyword("pathcountunfocused"))
    return node_from_string("ply-pathstart:ply-pathcount");
  return NULL;
}


GenericEqualNode* Tokens::match_genericequalnode(){
  if(!match_keyword("equal"))
    return NULL;
  if(!match_lparen())
    show_error("expected '(' following 'equal'");
  Node*left=match_node();
  if(!left)
    show_error("expected filter following 'equal('");
  Node*right=match_node();
  if(!right)
    show_error("expected filter following 'equal(left')");
  if(!match_rparen())
    show_error("missing ')' following 'equal(left right'");
  return new GenericEqualNode(left,right);
}

    
PiecePathNode* Tokens::match_piecepathnode(){
  if (match_keyword("piecepath"))
    show_error("The 'piecepath' filter has been removed. You can use 'piecepath' as a parameter to 'path' however");
  return NULL;
}

/*keep in sync with match_tonode()*/
FromNode* Tokens::match_fromnode(){
  if(!match_keyword("from"))
    return NULL;
  return new FromNode();
}

/*keep in sync with match_fromnode()*/
ToNode* Tokens::match_tonode(){
  if(!match_keyword("to"))
    return NULL;
  return new ToNode();
}

PreviousDashNode* Tokens::match_previousdashnode(){
  if(!match_keyword("currentmove")&&!match_keyword("previous"))
    return NULL;
  Node*node=match_mulop_x();
  if(!node)
    show_error("expected --  filter following 'currentmove'. No filter found.");
  DashNode* dash=dynamic_cast<DashNode*>(node);
  if(!dash){
    cout<<"invalid node type following 'currentmove'. Expected -- but got:\n";
    node->print();
    show_error("expected -- node following 'currentmove', like 'currentmove a4--a1'");
  }
  return new PreviousDashNode(dash);
}

Node* Tokens::match_countmoves(){
  if(!match_keyword("countmoves"))
    return NULL;
  Node*node=match_mulop_x();
  if(!node)
    show_error("expected -- or legal filter following 'countmoves'. No filter found.");
  MoveLegalNode* legal=dynamic_cast<MoveLegalNode*>(node);
  DashNode* dash=dynamic_cast<DashNode*>(node);
  if(!legal&&!dash){
    cout<<"invalid node:\n";
    node->print();
    show_error("expected a -- filter or a legal -- filter following 'countmoves' but got the above printed node");
  }
  uassert(!(legal&&dash),"in match_countmoves, internal");
  if(legal){
    if(legal->range)
      show_error("unexpected range field set in MoveLegalNode, which might indicate a double countmoves application");
    legal->range=new Range(0,10000);
    return legal;
  }
  if(dash){
    if(dash->isCount)
      show_error("unexpected dash count already set after 'countmoves'. Might indicate a double countmoves issue");
    dash->isCount=true;
    return dash;
  }
  uassert(false,"internal in countmoves");
  return NULL;
}
    
  
    
  
bool Tokens::match_linecomment(){
  if (dynamic_cast<LineCommentToken*>(current()) != NULL){
    forward();
    return true;
  }
  return false;
}

bool Tokens::match_endlinecomment(){
  if (dynamic_cast<EndLineCommentToken*>(current()) != NULL){
    forward();
    return true;
  }
  return false;
}
  
Node* Tokens::match_try(){
  static const string trystring=
    R"U(
     notransform 1== find <-- quiet all {btm secondary}
     )U";
  if(!match_keyword("try"))
    return NULL;
  return node_from_string(trystring);
}

bool Tokens::match_attackarrow(AttackArrowDirection dir){
  if(dir==AttackArrowDirection::Left)
    return match_special("<-");
  if(dir==AttackArrowDirection::Right)
    return match_special("->");
  uassert(false,"maa bad dir");
  return false;
}

AttackArrowDirection Tokens::match_attackarrow(){
  if(match_special("->"))
     return AttackArrowDirection::Right;
  if(match_special("<-"))
    return AttackArrowDirection::Left;
  return AttackArrowDirection::None;
}
     
bool Tokens::match_Aa(){
  PieceDesignatorToken*t=dynamic_cast<PDT*>(current());
  if(!t)return false;
  if(t->isAa()){
    forward();
    return true;
  }
  return false;
}

bool Tokens::match_element(){
  return match_special("[element]");
}

bool Tokens::match_forall(){
  return match_special("[forall]");
}

LastGameNumberNode* Tokens::match_lastgamenumbernode(){
  if(!match_keyword("lastgamenumber"))
    return NULL;
  return new LastGameNumberNode();
}

