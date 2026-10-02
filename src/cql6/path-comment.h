/*values and methods relating to keeping track of comments in the path*/
  ///commentStack
 private: 
    CommentStack commentStack; // entries from the main stack effectiveBottom to effectiveTop and then the reversed entries here are the best stack
  CommentStack*mainStack{NULL}; // the main stack
  int effectiveBottom{-1}; // the top of the main stack when the seqret was initialized. The main stack should never go below this value
  int effectiveTop{-1}; //Entries in the main stack from effectiveBottom exclusive to effectiveTop exclusive are stored in the main stack but actually
                        //belong to this seqret. Whenever they are popped, they should be transferred to the local commentStack.
  int trueSize{-1};
 public:
  void initializeComments(QPos*);
  void swapComments(QPos*,bool clearoldcomments);
  void commentStacksValid();
  int markComments(); //we actually don't need this here, but since we have restoreComments we use it
  void restoreComments(int);
  void pushComments(); //push all comments out to the main stack, deleting everything else on stack since effectiveBottom
  void popComment();
