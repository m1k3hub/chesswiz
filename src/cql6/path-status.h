/* status variables for PathNode. Keeping track of where we are and the
   best yet. To be included in pathnode.h.
Not to be confused with the similarly named pathstatus.h, which deals with the PathStatus class.
*/
int theCount{-1}; //number of in-focus positions so far
int getCount()const;
QPos* currentPosition{NULL}; // position being analyzed
vector<PathCon*>conStack; /*stack of PathCon waiting to be parsed*/
 public:
QPos*bestSoFar{NULL}; //best position so far
int bestLength{0}; // for focus.
int bestCount{-1}; // the best count so far
vector<QPos*>otherBestPositions;
NumValue bestMax{-100000000};
bool bestMaxValid{false};
bool isTrue();
bool isFalse();
bool isSuccess()const;

