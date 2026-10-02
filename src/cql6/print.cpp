#include "node.h"
#include "util.h"
#include "nodeheaders.h"

void Node::print(){
  printf("<%s>",thisclass().c_str());
}
void square_print(squareT square){
  uassert(square_valid(square),"square_print: bad square");
  int f=square_file(square);
  int r=square_rank(square);
  char fc=file_to_char(f);
  char rc=rank_to_char(r);
  printf("%c%c",fc,rc);
}

void AttackNode::print(){
  printf("<%s ",thisclass().c_str());
  if(returnAttacked)printf(" returnAttacked ");
  if (returnAttacking)printf(" returnAttacking ");
  attacking->print();
  printf(" ");
  attacked->print();
  printf("> ");
}

void BetweenNode::print(){
  printf("<%s ",thisclass().c_str());
  printf("\n");indent();tab();
  printf("source: ");
  source->print();
  unindent();
  printf("\n");indent();tab();
  printf("target: ");
  target->print();
  printf("> ");
  unindent();
}

void ComposeTransform::print()const {
  printf("<%s ",thisclass().c_str());
  for(auto t:transforms) t->print();
  printf(">");
}
void CountSquaresNode::print(){
  printf("<%s ",thisclass().c_str());
  set->print();
  printf(">");
}

void CqlNode::print(){
  printf("<%s  inputfile: %s outputfile: %s searchVariations: %d",thisclass().c_str(),inputfile.c_str(),outputfile.c_str(),searchVariations);
  
  if(gamenumberrange){
    printf(" gamenumberrange: ");
    gamenumberrange->print();
  }
  if(matchCountRange){
    printf("matchCountRange: ");
    matchCountRange->print();
  }
  indent();
  for(int i=0;i<gamefilters.size();++i){
    printf("\n");
    tab();
    printf("GameFilter %d of %zu: ",i,gamefilters.size());
    gamefilters[i]->print();
  }
    
  printf("\n");tab();
  printf("CqlNode body: \n");
  tab();
  filter->print();
  printf(" %s>",thisclass().c_str());
}
void DihedralTransform::print()const{
  printf("<%s %d %d %d>",thisclass().c_str(),reflectx,reflecty,swap);
}
void Direction::print()const{
  printf("<%d,%d>",xoffset,yoffset);
}
void DirectionParameter::print(){
  printf("<%s",thisclass().c_str());
  for(Direction d : directions){
    printf(" ");
    d.print();
  }
  range->print();
  printf(">");
}

void EloNode::print(){
  printf("<%s %s",thisclass().c_str(),color_string(color).c_str());
  range->print();
  printf(">");
}
void SquareLoopNode::print(){
  printf("<%s : variable: %s ",thisclass().c_str(),variable->name.c_str());
  if(isAll)printf(" all ");
  if(target){
    printf("\n");indent();tab();
    printf("target: ");
    target->print();
    unindent();
  }
  printf("\n");
  indent();
  tab();
  printf("body: ");
  theBody->print();
  unindent();
  printf(" %s> ",thisclass().c_str());
}
void PieceLoopNode::print(){
  printf("<%s : variable: %s ",thisclass().c_str(),variable->name.c_str());
  if(isAll)printf(" all ");
  if(target){
    printf("\n");indent();tab();
    printf("target: ");
    target->print();
    unindent();
  }
  printf("\n");
  indent();
  tab();
  printf("body: ");
  theBody->print();
  unindent();
  printf(" %s> ",thisclass().c_str());
}

void ExtensionNode::print(){
  printf("<%s>",thisclass().c_str());
}

void FindNode::print(){
  printf("<%s ",thisclass().c_str());
  if(range) range->print();
  if(isQuiet) printf(" quiet ");
  printf("\n");indent();tab();
  printf("FindNode body: ");
  printf("\n");tab();
  filter->print();
  unindent();
  printf("FindNode>");
}

void LoopNode::print(){
  printf("<%s ",thisclass().c_str());
  printf("\n");indent();tab();
  printf("LoopNode node: ");
  node->print();
  unindent();
  printf(">");
}

void WhileNode::print(){
  printf("<%s ",thisclass().c_str());
  printf("\n");indent();tab();
  printf("test: ");
  printf("\n");
  theTest->print();
  printf("\n");
  tab();
  printf("Body: ");
  theBody->print();
  unindent();
  printf(" WhileNode>");
}

void GameSortInfo::print(){
  output(stdout);
}
void HolderConstituent::print(){
  printf("<%s ",thisclass().c_str());
  filter->print();
  printf(">");
}
void HasCommentNode::print(){
  printf("<%s>",thisclass().c_str());
  if (nagValid)
    printf(" NAG: %d>",nag);
  else printf(">");
}
void MatchCountNode::print(){
  printf("<%s ",thisclass().c_str());
  if(sort) printf("sort ");
  range->print();
  printf(">");
}
void MoveBase::print(){
  printf("<%s",thisclass().c_str());
  if(from) {
    printf(" from ");
    from->print();}
  if (to){
    printf(" to ");
    to->print();
  }
  if (promote){
    printf(" promote ");
    promote->print();
  }
  if(enpassantsquare){
    printf(" enpassant ");
    enpassantsquare->print();
  }
  if(nullMove){
    printf(" nullMove ");
  }
  if (primaryMove)
    printf(" primaryMove ");
  if (secondaryMove)
    printf(" secondaryMove ");
  if (returnFrom) printf (" from ");
  if (returnTo) printf (" to ");
  if(returnCapture)printf(" capture ");
  printf("%s>",thisclass().c_str());
}
void MoveNumberNode::print(){
  printf("<%s>",thisclass().c_str());
}
void ToMoveNode::print(){
  if(color==WHITE)
    printf(" :wtm");
  else if (color==BLACK)
    printf(" :btm");
  else
    uassert(false,"internal color");
}
void KeywordNode::print(){
  printf("%s: %s>",thisclass().c_str(),value.c_str());
}

void PgnNode::print(){
  printf("<%s: %s>",thisclass().c_str(),value.c_str());
}

void OutputNode::print(){
  printf("<%s: %s>",thisclass().c_str(),value.c_str());
}
void Range::print(){
  printf("<%s ",thisclass().c_str());
  if(theMinv) printf("%s ",theMinv->name.c_str());
  else printf("%d ",theMin);
  if(theMaxv) printf("%s ",theMaxv->name.c_str());
  else printf("%d ",theMax);
  printf(">");
}

void ResultNode::print(){
  printf("<%s %s>",thisclass().c_str(),result_to_string(result).c_str());
}

void GameNumberNode::print(){
  uassert(range,"GNN int");
  printf("<%s: ",thisclass().c_str());
  range->print();
  printf(">");
}

void CurrentFen::print(){
  cout<< "<CurrentFen>";
}

void CommentNode::print(){
  printf("\n");
  tab();
  printf("<CommentNode ");
  if (theIsMessage) printf ("message ");
  indent();
  theConverter->print();
  printf(">");
  unindent();
}

void IsBoundNode::print(){
  printf("<isbound >");
  if(theVariable)
    printf(" variable: %s>",theVariable->name.c_str());
  else
    printf(" name: %s>",theName.c_str());
}

void UnbindNode::print(){
  printf("<unbind %s>",theVariable->name.c_str());
}

void NotNode::print(){
  printf("\n");
  tab();
  printf("<not ");
  indent();
  filter->print();
  printf(" not>");
  unindent();
}

void StringAsciiNode::print(){
  printf("\n");
  tab();
  printf("<StringAsciiNode ");
  if (isString()) printf (" fromAscii ");
  else if (isNumeric()) printf(" toAscii ");
  else printf (" noDirection ");
  printf("\n");
  indent();
  theNode->print();
  printf(" /StringAsciiNode>");
  unindent();
}

void NoTransformNode::print(){
  printf("\n");
  tab();
  printf("<notransform ");
  indent();
  theFilter->print();
  printf(" /notransform>");
  unindent();
}

void StringToIntNode::print(){
  printf("\n");
  tab();
  printf("<%s ",thisclass().c_str());
  indent();
  theNode->print();
  printf(" />");
  unindent();
}

void StringLengthNode::print(){
  printf("\n");
  tab();
  printf("<%s ",thisclass().c_str());
  indent();
  theNode->print();
  printf(" />");
  unindent();
}

void GameFilterWrapper::print(){
  printf("\n");
  tab();
  printf("<gamefilterwrapper ");
  indent();
  theNode->print();
  printf(" >");
  unindent();
}

void SquareParityNode::print(){
  printf("\n");
  tab();
  if (isLight())printf("<light ");
  else if (isDark())printf("<dark ");
  else printf("<SPN ERROR");
  indent();
  theSet->print();
  printf(">\n");
  unindent();
}

void OnNode::print(){
  printf("<%s",thisclass().c_str());
  printf("\n");indent();tab();
  printf("left &: ");
  clause1->print();
  printf("\n");tab();
  printf("right &: ");
  clause2->print();
  printf(" %s>",thisclass().c_str());
  unindent();
}
void OptionalConstituent::print(){
  printf("<%s ",thisclass().c_str());
  constituent->print();
  printf(">");
}

void OrNode::print(){
  printf("<%s",thisclass().c_str());
  printf("\n");indent();tab();
  printf("or left arg: ");
  clause1->print();
  printf("\n");tab();  
  printf("or right arg: ");
  clause2->print();
  printf(" %s>",thisclass().c_str());
  unindent();
}
void AndNode::print(){
  printf("<%s",thisclass().c_str());
  printf("\n");indent();tab();
  printf("and left arg: ");
  clause1->print();
  printf("\n");tab();
  printf("and right arg: ");
  clause2->print();
  printf(" %s>",thisclass().c_str());
  unindent();
}

void StringMatchNode::print(){
  printf("<%s",thisclass().c_str());
  printf("\n");indent();tab();
  printf("and left arg: ");
  targetNode->print();
  printf("\n");tab();
  printf("and right arg: %s",thePattern.c_str());
  unindent();
}

void PieceLoc::print(){
  if(thePieces.size()>1)
    printf("[");
  for(auto p : thePieces)
    printf("%c", piece_to_char((pieceT)p));
  if(thePieces.size()>1)
    printf("]");
  if(colorFlags[WHITE])printf("{A}");
  if(colorFlags[BLACK])printf("{a}");
  squaremask.print();
}
void PiOver4Transform::print()const{
  printf("<%s times: %d>",thisclass().c_str(),times);
}
void PlusConstituent::print(){
  printf("<%s ",thisclass().c_str());
  getConstituent()->print();
  printf(">");
}
void PlyNode::print(){
  printf("<PlyNode>");
}

void DepthNode::print(){
  printf("<DepthNode>");
}

void CompoundNode::print(){
  printf("<%s at %p: %zu specs:",thisclass().c_str(),this,specs.size());
  for(int i=0;i<specs.size();++i){
    printf("\n");
    indent();
    tab();
    printf("<%d of %zu: ",i,specs.size());
    specs[i]->print();
    unindent();
  }
  printf(" %s> ",thisclass().c_str());
}
void PowerNode::print(){
  printf("<%s Set: ",thisclass().c_str());
  set->print();
  printf(" >");
}
void RayNode::print(){
  printf("\n");tab();
  printf("<%s ",thisclass().c_str());
  if(isAttack) printf(" isAttack ");
  if(theReturnFirst)printf(" returnFirst");
  if(theRange) {
    printf(" Range: ");
    theRange->print();
  }
  for(auto d:directions){
    printf(" ");
    d.print();
  }
  printf("\n");
  indent();
  int nds=(int)(designators.size());
  for(int i=0;i<nds;++i){
    tab();
    printf("Ray designator %d of %d: ",i,nds);
    designators[i]->print();
    printf("\n");
  }
  tab();
  printf(" %s>",thisclass().c_str());
  unindent();
}
void RepeatInProcessConstituent::print(){
  printf("<%s ",thisclass().c_str());
  theRepeatConstituent->print();
  printf(">");
}

void RepeatConstituent::print(){
  printf("<%s ",thisclass().c_str());
  constituent->print();
  printf("{%d %d}",min,max);
  printf(">");
}

void GotoNode::print(){
  printf("<GotoNode: ");
  target->print();
  printf(">");
}

void PathReferenceNode::print(){
  printf("<%s ",thisclass().c_str());
  cout<<"thePath: "<<thePath;
  cout<<">";
}

void SequenceBase::print(){
  printf("<%s at %p: %d constituents: ",thisclass().c_str(),this,nconstituents());
  if(nestBan)printf("nestban ");
  if(firstMatch)printf("firstMatch ");
  if(isPrimary) printf("primary ");
  if (isSecondary) printf("secondary ");
  if(returnFinish) printf("returnfinish ");
  if(isQuiet) printf("quiet ");
  if(isPast())printf("past ");
  if(range) range->print();
  for(int i=0;i<nconstituents();++i){
    printf("\n");
    indent();
    tab();
    printf("<%d of %d: ",i,nconstituents());
    getConstituent(i)->print();
    unindent();
  }
  printf(" %s> ",thisclass().c_str());
}

void ShiftTransform::print()const{
  printf("<%s %d %d>",thisclass().c_str(),xoffset,yoffset);
}
void SortValue::print(){
  cout<<'<'<<thisclass()
      <<" value: ";
  if(isUnbound())
    cout<<"none ";
  else if (isString())
    cout<<getStringValue();
  else if (isNumeric())
    cout<<getNumericValue();
  else
    uassert(false,"SortValue::print bad type");
  if (isMin())
    cout<<' '<<"min";
  cout<<'>';
}

void SquareMask::print()const{
  if(full())
    printf("<all>");
  else if(empty())
    printf("<none>");
  else{
    printf("[");
    for(squareT s : getSquares())
      square_print(s);
    printf("]");
  }
}

void SquareMask::boardprint()const{
  squareT s;
  for (int rank=7; rank>=0; rank--) {
    printf("%c: ",rank_to_char(rank));
    for (int file=0; file<=7; file++) {
      s = square_make(file,rank);
      char c=member(s)?'1': rank%2==file%2 ? '+' : '-';
      printf("%c",c);
    }
    printf ("\n");
  }
  printf("   abcdefgh\n");
}

void SquareMask::boardprint(Mask m){
  SquareMask(m).boardprint();
}

void SquareMask::printnl(){
  print();
  printf("\n");
}

void mask_print(Mask m){
  SquareMask(m).printnl();
}
void StarConstituent::print(){
  printf("<%s ",thisclass().c_str());
  constituent->print();
  printf(">");
}

void Transform::print()const{
  printf("<%s>",thisclass().c_str());
}

void OrbitNode::print(){
  int orbitlen=orbitLength();
  printf("<%s orbitlen: %d",thisclass().c_str(),orbitlen);
  if(range) {
    printf(" range: ");
    range->print();
  }
  for(int i=0;i<orbitlen;++i){
    printf("\n");indent();tab();
    printf("Orbit element %d of %d: ",i,orbitlen);
    theOrbit.at(i).print();
    unindent();
  }
  printf(" %s>",thisclass().c_str());
}

void OrbitElement::print(){
  tab();
  printf("<OrbitElement Transform: %s\n",transform->toString().c_str());
  tab();
  printf(" Filter: ");
  node->print();
  printf("/OrbitElement>");
}
  
void VectorConstituent::print(){
  printf("\n");tab();
  printf("<%s %zu constituents: ",thisclass().c_str(),constituents.size());
  indent();
  for(int i=0;i<constituents.size();++i){
    printf("\n");
    tab();
    printf("%s %d of %zu: ",thisclass().c_str(),i,constituents.size());
    constituents[i]->print();
  }
  unindent();
  printf(">");
}
void VectorNode::print(){
  printf("<%s Parameter: ",thisclass().c_str());
  parameter.print();
  indent();
  printf("\n");tab();
  printf("source: ");
  source->print();
  printf("\n");tab();
  printf(" %s>",thisclass().c_str());
  unindent();
}
void YearNode::print(){
  printf("<%s ",thisclass().c_str());
  range->print();
  printf(">");
}

void TagNode::print(){
  printf("<%s %s>",thisclass().c_str(),theName.c_str());
}

void TagSetNode::print(){
  printf("<%s %s",thisclass().c_str(),theName.c_str());
  theNode->print();
  printf(" TagSetNode>");
}

void AssertNode::print(){
  printf("<%s %s",thisclass().c_str(),theName.c_str());
  theNode->print();
  printf(" AssertNode>");
}

string TransformVariable::toString(){
  stringstream s;
  s<<'<'<<thisclass()<<' '<<name<<'>';
  return s.str();
}

string PieceIdVariable::toString(){
  stringstream s;
  s<<"<"<<thisclass()<<' '<< name<<' ';
  if(bound)
    s<<"pieceid: "<<pieceid;
  s<<'>';
  return s.str();
}

string SquareVariable::toString(){
  stringstream s;
  s<<"<"<<thisclass()<<' ';
  if (isPersistent())
    s<<"persistent ";
  s << name<<' ';
  if(bound)
    s<<"squares: "<<mask.listString();
  s<<'>';
  return s.str();
}

string NumericVariable::toString(){
  stringstream s;
  s<<'<'
   <<thisclass()<<": "<<name;
  if(isPersistent())
    s<<" isPersistent";
  if (isUnbound()) s<< " unbound";
  else
    s<<" value: " << getValue();
  s<<">";
  return s.str();
}
string StringVariable::toString(){
  stringstream s;
  s<<'<'
   <<thisclass()<<": "<<name;
  if (isPersistent())
    s<<" persistent";
  if (isUnbound()) s<< " unbound";
  else
    s<<" value: " << getValue();
  s<<">";
  return s.str();
}


string SquareMask::listString()const{
  stringstream s;
  bool onecount= (count()==1);
  if(!onecount)
    s<<'[';
  bool seen=false;
  for(int sq=0;sq<64;++sq)
    if(this->member(sq)){
      if(seen)
	s<<',';
      int file=square_file(sq);
      int rank=square_rank(sq);
      s<<file_to_char(file)<<rank_to_char(rank);
      seen=true;
    }
  if(!onecount)
    s<<']';
  return s.str();
}

void Variable::print(){
  printf("%s",toString().c_str());
}
void AssignNumericNode::print(){
  printf("<%s variable: ",thisclass().c_str());
  variable->print();
  printf("\n");
  indent();tab();
  printf("Node: ");
  dynamic_cast<Node*>(node)->print();
  unindent();
  printf(" %s>",thisclass().c_str());
}

void AssignStringNode::print(){
  printf("<%s variable: ",thisclass().c_str());
  variable->print();
  printf("\n");
  indent();tab();
  printf("Node: ");
  dynamic_cast<Node*>(node)->print();
  unindent();
  printf(" %s>",thisclass().c_str());
}

void AssignSquareNode::print(){
  printf("<%s variable: ",thisclass().c_str());
  variable->print();
  if(isConditional) printf(" conditional");
  printf("\n");
  indent();tab();
  printf("Node: ");
  node->print();
  unindent();
  printf(" %s>",thisclass().c_str());
}

void CurrentNode::print(){
  printf("<CurrentNode>");
}
void AssignPositionNode::print(){
  printf("<%s variable: ",thisclass().c_str());
  variable->print();
  printf("\n");
  indent();tab();
  printf("Node: ");
  node->print();
  unindent();
  printf(" %s>",thisclass().c_str());
}

void RelationalNode::print(){
  printf("<%s %s\n",thisclass().c_str(),name.c_str());
  indent();tab();
  printf("Left: ");
  dynamic_cast<Node*>(left)->print();
  printf("\n");
  tab();
  printf("Right: ");
  dynamic_cast<Node*>(right)->print();
  printf("\n");
  unindent();
}

void ArithmeticNode::print(){
  printf("<%s %c\n",thisclass().c_str(),namec);
  indent();tab();
  printf("Left: ");
  dynamic_cast<Node*>(left)->print();
  printf("\n");
  tab();
  printf("Right: ");
  dynamic_cast<Node*>(right)->print();
  printf("\n");
  unindent();
}

void NumberNode::print(){
  cout<<"<"<<thisclass()<<": "<<value<<">";
}

void RangeNode::print(){
  printf("<%s numeric: ",thisclass().c_str());
  numeric->print();
  printf(">");
}

void NumericVariable::print(){
  cout<<toString();
}
void StringVariable::print(){
  cout<<toString();
}


void StringConverter::print(){
  int len=(int)(theNodes.size());
  printf("<%s Nconverters: %d\n",thisclass().c_str(),len);
  indent();
  for (int i=0;i<len;++i){
    tab();
    printf("converter %d of %d: ",i,len);
    theNodes[i]->print();
    printf("\n");
  }
  unindent();
  tab();
  printf(">");
}

void CurrentTransformNode::print(){
  printf(" currenttransform ");
}


void IfNode::print(){
  printf("<%s\n",thisclass().c_str());
  indent();tab();
  printf("Predicate: ");
  predicateFilter->print();
  printf("\n");
  tab();
  printf("Then: ");
  thenFilter->print();
  if (elseFilter){
    printf("\n");
    tab();
    printf("Else: ");
    elseFilter->print();
  }
  printf("if/>");
  unindent();
}

void SubstringNode::print(){
  printf("<%s\n",thisclass().c_str());
  indent();tab();
  printf("Target: ");
  theTarget->print();
  printf("\n");
  tab();
  printf("bracket: ");
  theBracket->print();
  printf(" substring/>");
  unindent();
}

void SubstringAssignmentNode::print(){
  printf("<%s\n",thisclass().c_str());
  indent();tab();
  printf("Target: %s \n",theTarget->name.c_str());
  tab();
  printf("bracket: ");
  theBracket->print();
  printf("\n");
  tab();
  printf("rhs/substring assignment: ");
  theRight->print();
  printf(" substring/>\n");
  unindent();
}

string LambdaValue::toString(){
  stringstream s;
  s<<"<"<<thisclass()<< " Parameters:[";
  for (auto n: parameters)
    {s<<' '<<n;}
  int ntokens = (int) body.size();
  s<<"] Body: Ntokens: "<<ntokens<<'\n';
  for (int i=0;i<ntokens;++i){
    s<<"     Token "<<i<<" of "<<ntokens<<": ";
    s<<body[i]->toString()<<'\n';
  }
  s<<thisclass()<<">";
  return s.str();
}

string LambdaVariable::toString(){
  stringstream s;
  s<<"<"<<thisclass()<<" name: "<<name<<" ";
  if (bound)
    s<<value.toString();
  s<<" "<<thisclass()<<">";
  return s.str();
}

string PositionVariable::toString(){
  stringstream s;
  s<<"<"<<thisclass()<<" name: "<<name<<" ";
  if (bound)
    s<<"[index: "<<value->index<<"]";
  s<<" "<<thisclass()<<">";
  return s.str();
}

void LambdaCallNode::print(){
  printf("<%s name: %s \n",thisclass().c_str(),name.c_str());
  indent();tab();
  int nassignments=(int)(assignments.size());
  for (int i=0;i<nassignments;++i){
    printf("Assignment %d of %d: ",i,nassignments);
    if(assignments[i])
      assignments[i]->print();
    else printf("<null assignment>");
    printf("\n");indent();tab();
  }
  printf("Body node (for call to %s)\n: ",name.c_str());
  indent();tab();
  bodynode->print();
  printf(" %s>",thisclass().c_str());
  unindent();
}

  
  
void MoveLegalNode::print(){
  printf("<%s",thisclass().c_str());
  if(enpassantSquare){
    printf(" enpassant ");
    enpassantSquare->print();
  }
  if(range){
    printf(" range: ");
    range->print();}
  if(fromNode) {
    printf("\n");
    indent();tab();
    printf("fromNode for MoveLegalNode:\n");
    tab();
    fromNode->print();
    unindent();
  }
  if(toNode) {
    printf("\n");
    indent();tab();
    printf("toNode for MoveLegalNode:\n");
    tab();
    toNode->print();
    unindent();
  }
  printf("%s>",thisclass().c_str());
}

void SquareCoordinateNode::print(){
  printf("<%s ",thisclass().c_str());
  if(isRank)printf("rank ");
  else printf("file ");
  printf("square: ");
  theSquare->print();
  printf(">");
}

void PieceIdNode::print(){
  printf("<%s\n",thisclass().c_str());
  indent();tab();
  if(theSet){printf("set ");
    theSet->print();}
  if(pieceidVariable){printf("tag ");
    printf("%s",pieceidVariable->name.c_str());}
  printf(">");
  unindent();
}

void MakeSquareNode::print(){
  printf("<%s ",thisclass().c_str());
  printf("\n");indent();tab();
  if (theFile&&theRank){
    printf("file: ");
    theFile->print();
    unindent();
    printf("\n");indent();tab();
    printf("Rank: ");
    theRank->print();
    unindent();
    printf(">");
  }
  else if (theName){
    printf("name: ");
    theName->print();
    unindent();
    printf("> ");
  }
  else
    uassert(false, "print: malformed MakeSquareNode");
}


void QPos::print(){
  printf("<QPos: %p tomove: %s board: \n",this,color_string(toMove).c_str());
  util::my_dump_board(board);
  if(parent){
    printf("parent: %p prior move: ",parent);
    previousMove.print();
  }
  printf("  check: %d mate: %d stalemate: %d nchildren: %d marked squares: \n",
	 theIsCheck,
	 theIsMate,
	 theIsStalemate,
	 (int)children.size());
	
  printf(" QPos>\n");
}

void QMove::print()const{
  printf("<QMove: %s-%s index: %d",
	 square_to_string(from).c_str(),
	 square_to_string(to).c_str(),
	 index);
  if(square_valid(enpassant))
    printf(" e.p. %s",square_to_string(enpassant).c_str());
  if(promote!=EMPTY)
    printf("(%c)",piece_to_char(promote));
  printf(">");
}

void QGame::print(){
  printf("<QGame variations: %d pgnUseSource: %d descendants are: \n", searchVariations,pgnUseSource);
  vector<QPos*>ds=root->getDescendants();
  int ndescendants=(int)(ds.size());
  for(int di=0;di<ndescendants;++di){
    QPos* curr=ds[di];
    printf("\n Descendant %d of %d at: %p: \n",
	   di,
	   ndescendants,
	   curr);
    curr->print();
  }
  printf("QGame>");
}      
  
void Environment::print(){
  printf("<Environment at %p nvariables: %zu nsortvariables: %zu\n",this,theVariables.size(),theSortVariables.size());
  printf(" theVariables: \n");
  for (auto v : theVariables)
    if(v==NULL)printf("    NULL\n");
    else printf("    v->toString()\n");
  printf(" theSortVariables: \n");
  for (auto v : theSortVariables)
    if(v==NULL)printf("    NULL\n");
    else printf("    v->toString()\n");
  printf("Environment>\n");
}

void PinNode::print(){
  printf("<%s","PinNode");
  if(returnFrom) printf(" from");
  if(returnThrough) printf(" through");
  if(returnTo) printf(" to");
  printf("\n");
  if(fromFilter){
    indent();tab();
    printf("From: ");
    fromFilter->print();
    unindent();
    printf("\n");
  }
  if(throughFilter){
    indent();tab();
    printf("Through: ");
    throughFilter->print();
    unindent();
    printf("\n");
  }
  if(toFilter){
    indent();tab();
    printf("To: ");
    toFilter->print();
    unindent();
    printf("\n");
  }
  indent();tab();
  printf(" %s>","PinNode");
  unindent();
}
  

void SubsetNode::print(){
  printf("<%s ",thisclass().c_str());
  printf("\n");indent();tab();
  printf("left: ");
  theLeft->print();
  unindent();
  printf("\n");indent();tab();
  printf("right: ");
  theRight->print();
  printf("> ");
  unindent();
}

void StringInNode::print(){
  printf("<%s ",thisclass().c_str());
  if (computeIndex) printf(" computeindex");
  if(isImplicit)printf(" isImplicit");
  printf("\n");indent();tab();
  printf("left: ");
  theLeft->print();
  unindent();
  printf("\n");indent();tab();
  printf("right: ");
  theRight->print();
  printf("> ");
  unindent();
}

void ConcatenationNode::print(){
  printf("<%s ",thisclass().c_str());
  if (isDestructive) printf("destructive ");
  printf("\n");indent();tab();
  printf("left: ");
  theLeft->print();
  unindent();
  printf("\n");indent();tab();
  printf("right: ");
  theRight->print();
  printf("> ");
  unindent();
}

void VirtualMainlineNode::print(){
  printf("<%s>",thisclass().c_str());
}

void WithPositionNode::print(){
  printf("<%s ",thisclass().c_str());
  printf("\n");indent();tab();
  printf("target: ");
  theTarget->print();
  unindent();
  printf("\n");indent();tab();
  printf("filter: ");
  theFilter->print();
  printf("> ");
  unindent();
}

void EchoNode::print(){
  printf("<%s: %s %s  ",thisclass().c_str(),sourcevar->name.c_str(),targetvar->name.c_str());
  if(isSort) printf("isSort ");
  if(searchAll) printf("all");
  if(isQuiet)printf(" quiet ");
  printf("\n");indent();tab();
  printf("filter: ");
  theFilter->print();
  unindent();
  printf(" %s> ",thisclass().c_str());
}

void MatchNode::print(){
  printf("<%s ",thisclass().c_str());
  printf("left: ");
  left->print();
  printf("right: ");
  right->print();
  printf(">");
}

void LcaNode::print(){
  printf("<%s ",thisclass().c_str());
  printf("left: ");
  left->print();
  printf("right: ");
  right->print();
  printf(">");
}

void DistanceNode::print(){
  printf("<%s ",thisclass().c_str());
  printf("left: ");
  left->print();
  printf("right: ");
  right->print();
  printf(">");
}

void DescendantNode::print(){
  printf("<%s ",thisclass().c_str());
  printf("left: ");
  left->print();
  printf("right: ");
  right->print();
  printf(">");
}

void ExtremalNode::print(){
  printf("<%s ",thisclass().c_str());
  if(theIsMax)printf("min");
  else printf("max");
  int nnodes=(int)(theNodes.size());
  for (int i=0;i<nnodes;++i){
    printf("\n");
    indent();
    tab();
    theNodes[i]->print();
    unindent();
  }
  printf(">");
}

void BracketRange::print(){
  printf("<%s ",thisclass().c_str());
  if (singleIndex) printf("singleindex ");
  printf("\n");
  indent();
  tab();
  printf("theLeft: ");
  theLeft->print();
  if (!singleIndex){
    printf("\n");
    tab();
    printf("theRight: ");
    if (theRight==NULL)
      printf("NULL");
    else theRight->print();
  }
  unindent();
  printf("/BracketRange>");
}

void ToMoveValueNode::print(){
  printf("<%s>",thisclass().c_str());
}

void ColorValueNode::print(){
  printf("<%s %s>",thisclass().c_str(),
	 name().c_str());
}

void ConsecutiveMovesNode::print(){
  printf("<%s ",thisclass().c_str());
  if(quiet) printf("quiet ");
  printf("left: ");
  left->print();
  printf("right: ");
  right->print();
  printf(">");
}

void UnionNode::print(){
  printf("<%s",thisclass().c_str());
  printf("\n");indent();tab();
  printf("left |: ");
  clause1->print();
  printf("\n");
  tab();printf("right |: ");
  clause2->print();
  printf(" %s>",thisclass().c_str());
  unindent();
}
void ComplementNode::print(){
  printf("\n");
  tab();
  printf("<~ ");
  indent();
  theSet->print();
  printf(" ~>");
  unindent();
}

void EqualityNode::print(){
  printf("<%s\n",thisclass().c_str());
  indent();tab();
  printf("Left: ");
  dynamic_cast<Node*>(left)->print();
  printf("\n");
  tab();
  printf("Right: ");
  dynamic_cast<Node*>(right)->print();
  printf("\n");
  unindent();
}

void PositionIndexNode::print(){
  printf("<PositionIndexNode>");
}

void ColorTypeNode::print(){
  printf("<%s ",thisclass().c_str());
  theSet->print();
  printf(">");
}

void SortNode::print(){
  printf("<%s %s isMax: %d\n",thisclass().c_str(),theVariable->name.c_str(),isMax());
  indent();tab();
  printf("sort filter: ");
  theFilter->print();
  printf(">");
  unindent();
}


void AbsNode::print(){
  printf("<%s ",thisclass().c_str());
  node->print();
  printf(">");
}
void SqrtNode::print(){
  printf("<%s ",thisclass().c_str());
  node->print();
  printf(">");
}

void NonemptyNode::print(){
  printf("<%s ",thisclass().c_str());
  set->print();
  printf(">");
}

void ChildNode::print(){
  printf("<%s Index: ",thisclass().c_str());
  indexNode->print();
  printf(">");
}

void ParentNode::print(){
  printf("<ParentNode>");
}

void PieceAssignNode::print(){
  printf("<%s %s\n",thisclass().c_str(),var->name.c_str());
  indent();tab();
  printf("pieceassign right: ");
  set->print();
  printf("\n");
  unindent();
  tab();printf("%s>",thisclass().c_str());
  unindent();
}
    
void CommentEntry::print(){
  printf("<CommentEntry: %s>",toString().c_str());
}

void CommentStack::print(){
  printf("%s",toString().c_str());
}

void HhdbAwardNode::print(){
  printf("<HhdbAwardNode:");
  if (restrictPrize) printf(" prize ");
  if (restrictHm) printf(" hm");
  if (restrictCommendation) printf(" c");
  if (useMax) printf (" max");
  if (restrictSpecial) printf(" sp");
  printf(">");
}

void HhdbHasCookNode::print(){
  printf("<HhdbHasCookNode>");
  return;
}

void AssertVariationsNode::print(){
  printf("<AssertVariationsNode: %s>",theMessage.c_str());
}

void AbortNode::print(){
  printf("<%s: %s>",thisclass().c_str(),theMessage.c_str());
}

void StringLiteralNode::print(){
  printf("<StringLiteralNode \"%s\">", theName.c_str());
}

void GroupNumberNode::print(){
  printf(" \\%d ",theGroup);
}

void TagBuiltInNode::print(){
  printf("<%s %s>",thisclass().c_str(),theName.c_str());
}

void StringIteratorNode::print(){
  printf("<%s ", thisclass().c_str());
  printf("\n");
  indent();tab();
  printf("theTarget: ");
  theTarget->print();
  unindent();

  printf("\n");
  indent();tab();
  printf("thePattern: %s",thePattern.c_str());

  printf("\n");
  indent();
  tab();
  printf("theBody: ");
  theBody->print();
  unindent();
  printf(" %s> ",thisclass().c_str());
}

void Dictionary::print(){
  printf("<%s name: %s count: %d isPersistent: %d>", thisclass().c_str(),name.c_str(),count(),isPersistent());
}

void CaseConvertNode::print(){
  printf("<%s: ",thisclass().c_str());
  if (theDirection==CaseConvertDirection::ToLower)
    printf("lowercase ");
  else if (theDirection==CaseConvertDirection::ToUpper)
    printf("uppercase ");
  else printf(" unknown direction");
  printf("\n");
  indent();tab();
  printf("Node: ");
  theNode->print();
  unindent();
  printf(" %s>",thisclass().c_str());
}


void ReadFileNode::print(){
  printf("\n");
  tab();
  printf("<ReadFileNode ");
  fileNameNode->print();
  printf(">");
}

void WriteFileNode::print(){
  printf("\n");
  tab();
  printf("<ReadFileNode\n");
  indent();tab();
  printf("fileName: ");
  fileNameNode->print();
  printf("\n");
  tab();
  printf("Contents: ");
  contentNode->print();
  printf(" /ReadFileNode>\n");
  unindent();
}

void NumericIteratorNode::print(){
  printf("<%s : variable: %s ",thisclass().c_str(),theVariable->name.c_str());
  printf("\n");
  indent();tab();
  printf("lowerBound: ");
  lowerBound->print();
  unindent();

  printf("\n");
  indent();tab();
  printf("upperBound: ");
  upperBound->print();
  unindent();

  printf("\n");
  indent();
  tab();
  printf("theBody: ");
  theBody->print();
  unindent();
  printf(" %s> ",thisclass().c_str());
}

void RemoveCommentNode::print(){
  printf("<RemoveCommentNode>");
}


void PreviousDashNode::print(){
  printf("<%s\n",thisclass().c_str());
  indent();tab();
  if(theDash==NULL)printf("NULL theDash");
  else theDash->print();
  printf(" PreviousDashNode>");
  unindent();
}

void DashNode::print(){
  printf("<%s",thisclass().c_str());
  printf(" %s",captureTypeToString(theCaptureType).c_str());
  if(isCount) printf(" isCount");
  printf("\n");indent();tab();
  if(left){
    printf("dash left: ");
    left->print();
    printf("\n");tab();
  }
  if(right){
    printf("dash right: ");
    right->print();
    printf("\n");tab();
  }
  if(target){
    printf("dash target: ");
    target->print();
    printf("\n");tab();
  }
  for(int i=0;i<(int)(fromToNodeOwned.size());++i){
    printf("owned: %d : ",i);
    fromToNodeOwned.at(i)->print();
  }
  unindent();
}

void PastMoveNode::print(){
  cout<<"<PastMoveNode "
      <<typetostring();
  if(promotePieceLoc){
    cout<< "promotePieceLoc: ";
    promotePieceLoc->print();
  }
  if(promoteStringFilter){
    cout<< "promoteStringFilter: ";
    promoteStringFilter->print();
  }

  if(theCapture){
    cout<< "capture: ";
    theCapture->print();
  }
  cout   <<">";
}


void ChainCon::print(){
  printf("\n");tab();
  printf("<%s ",thisclass().c_str());
  if(isInitial()) printf("initial ");
  printf("%zu constituents: ",theCons.size());
  indent();
  for(int i=0;i<theCons.size();++i){
    printf("\n");
    tab();
    printf("%s %d of %zu: ",thisclass().c_str(),i,theCons.size());
    theCons[i]->print();
  }
  unindent();
  printf(">");
}

void StarCon::print(){
  printf("<%s ",thisclass().c_str());
  theCon->print();
  printf(">");
}
void OptionalCon::print(){
  printf("<%s ",thisclass().c_str());
  theCon->print();
  printf(">");
}
void PlusCon::print(){
  printf("<%s ",thisclass().c_str());
  getCon()->print();
  printf(">");
}

void DashCon::print(){
  printf("<%s",thisclass().c_str());
  if (isInitial()) printf(" initial");
  printf(" %s",captureTypeToString(theCaptureType).c_str());
  printf("\n");indent();tab();
  if(theLeft){
    printf("dashcon left: ");
    theLeft->print();
    printf("\n");tab();
  }
  if(theRight){
    printf("dashcon right: ");
    theRight->print();
    printf("\n");tab();
  }
  if(theTarget){
    printf("dashcon target: ");
    theTarget->print();
    printf("\n");tab();
  }
  printf("%s>",thisclass().c_str());
  unindent();
}

 
void HolderCon::print(){
  printf("<%s ",thisclass().c_str());
  //  if (theSkip) printf(" skip");
  if(isInitial()) printf(" initial");
  theFilter->print();
  printf(">");
}
 
void PathNode::print(){
  printf("<%s at %p: %d constituents: ",thisclass().c_str(),this,ncons());
  if(nestBan)printf("nestban ");
  if(firstMatch)printf("firstMatch ");
  if(isPrimary) printf("primary ");
  if(isSecondary) printf("secondary ");
  if(returnFinish) printf("returnfinish ");
  if(isQuiet) printf("quiet ");
  if(piecePathNode) printf ("piecepath ");
  if(isVerbose) printf("verbose ");
  if(hasTitle())printf("title: %s ",theTitle.c_str());
  if(keepAllBest)printf("keepallbest ");
  if(theRange) theRange->print();
  if(hasMax()){
    printf("\n");
    indent();
    tab();
    printf("path max: ");
    theMax->print();
    unindent();
  }
      
  if (theFocus) {
    printf("\n");
    indent();
    tab();
    printf("path focus: ");
    theFocus->print();
    unindent();
  }
  for(auto v:atomicVariables)
    printf(" [atomic %s]",v->name.c_str());
  for(int i=0;i<ncons();++i){
    printf("\n");
    indent();
    tab();
    printf("<pathnode constituent %d of %d: ",i,ncons());
    getCon(i)->print();
    unindent();
  }
  printf(" %s> ",thisclass().c_str());
}

void FocusCaptureNode::print(){
  printf("<%s",thisclass().c_str());
  printf(" theSet: ");
  theSet->print();
  printf(">\n");
}

void Focus::print(){
    printf("<%s",thisclass().c_str());
    if (isCapture()) printf(" isCapture");
  printf("\n");indent();tab();
  printf("Focus theSet: ");
  theSetBase->print();
  printf("\n");tab();
  printf(" %s>",thisclass().c_str());
  unindent();
}

void GenericEqualNode::print(){
  printf("<%s",thisclass().c_str());
  printf("\n");indent();tab();
  printf("genericequal left: ");
  theLeft->print();
  printf("\n");tab();
  printf("genericequal right: ");
  theRight->print();
  printf(" %s>",thisclass().c_str());
  unindent();
}


void RepeatInProcessCon::print(){
  printf("<%s ",thisclass().c_str());
  repeatCon->print();
  printf(">");
}

void RepeatCon::print(){
  printf("<%s ",thisclass().c_str());
  theCon->print();
  printf("{%d %d}",theMin,theMax);
  printf(">");
}

void PiecePathNode::print(){
  printf("<%s",thisclass().c_str());
  if(isVerbose)printf(" verbose");
  printf("\n");indent();tab();
  printf("from: ");
  theFrom->print();
  printf("\n");tab();
  printf("to: ");
  theTo->print();
  printf(" %s>",thisclass().c_str());
  unindent();
}

void FromToNode::print(){
  printf("<%s this: @%p owner: @%p>",thisclass().c_str(),this,theOwner);
}

void PieceNameNode::print(){
  printf("<%s ",thisclass().c_str());
  theSet->print();
  printf(">");
}

void TrueNode::print(){
  printf("<%s>",thisclass().c_str());
}

void TypeNameNode::print(){
  printf("<%s ",thisclass().c_str());
  theSet->print();
  printf(">");
}

void DictionaryAccessNode::print(){
  printf("<%s Dictionary: %s",thisclass().c_str(),theDictionary->name.c_str());
  if(theKey){
    indent();tab();
    printf("theKey: ");
    theKey->print();
    unindent();
  }
  if (theValue){
    indent();tab();
    printf("\n");
    printf("theValue: ");
    theValue->print();
    unindent();
  }

  if (theBody){
    indent();tab();
    printf("\n");
    printf("theBody: ");
    theValue->print();
    unindent();
  }

  if (theVariable){
    indent();tab();
    printf("\n");
    printf("theVariable: ");
    theValue->print();
    unindent();
  }

printf(" %s>\n",thisclass().c_str());
  unindent();
}

void LastGameNumberNode::print(){
  printf("<%s>",thisclass().c_str());
}

void AnticipateNode::print(){
  printf("<%s %s",thisclass().c_str(),patternFile.c_str());
  if(isNoTransform) printf(" notransform");
}
