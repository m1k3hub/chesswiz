/* file to be included in pathnode.h
   this contains the configuration parameters for the path
*/

vector<PathCon*> theCons;
vector<PathCon*>& getCons(){return theCons;}

  
int ncons()const;
bool valid_con (int offset)const;
PathCon* getCon (int offset)const;
bool firstMatch{false};
bool isPrimary{false};
bool isSecondary{false};
bool returnFinish{false};
bool isQuiet{false};
Focus*theFocus{NULL};
Node*theMax{NULL};
PiecePathNode*piecePathNode{NULL};
Node*getMax()const{return theMax;}
bool hasMax()const{return theMax!=NULL;}
Focus*getFocus()const{return theFocus;}
bool hasFocus()const{return theFocus!=NULL;}
Range*theRange{NULL};
Range*getRange()const{return theRange;}
bool theNestBan{false};
QPos* theStartQPos{NULL};
QPos* getStartQPos()const {return theStartQPos;}
bool isPosition()const override{return returnFinish;}
bool isNumeric()const override{return !returnFinish;}
string theTitle;
string getTitle()const{return theTitle;}
bool hasTitle()const{return theTitle.size()>0;}
bool isVerbose{false};
bool keepAllBest{false};

