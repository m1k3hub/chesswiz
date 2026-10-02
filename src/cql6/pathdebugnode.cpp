#include "pathdebugnode.h"
PathDebugNode::PathDebugNode():PathReferenceNode(){}

bool PathDebugNode::match_position(QPos*qpos){
  PathNode*path=getPath();
  vector<PathCon*> stack=path->conStack;
  cout
    <<endl
    <<"PathDebug: debugging path at "
    <<path
    <<" constack of size:  "<<stack.size()<<endl;
  if(0)for(int i=0;i<(int)(stack.size());++i){
    cout<<" stack constituent "<<i<<": ";
    stack.at(i)->print();
    cout<<endl;
  }
  cout<<" bestSoFar: "<<path->bestSoFar;
  if (path->bestSoFar) cout<< ":"<< path->bestSoFar->idString();
  cout<<endl;
  cout<<" bestLength: "<<path->bestLength;
  cout<<" bestCount: "<<path->bestCount;
  if (path->bestMaxValid) cout<<" bestMax: "<<path->bestMax;
  cout<<" path currentPosition: "<<path->currentPosition->idString()<<endl;
  cout<<" actual currpos: "<<qpos->idString()<<endl;
  return true;
}


