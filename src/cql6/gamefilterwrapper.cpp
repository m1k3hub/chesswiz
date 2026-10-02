#include "gamefilterwrapper.h"
GameFilterWrapper::GameFilterWrapper(Node*n):theNode(n){
  uassert(theNode,"gfw arg");
}

void GameFilterWrapper::deepify(){
  theNode=theNode->clone();
}
vnode GameFilterWrapper::children()const{
  return vnode{theNode};
}

bool GameFilterWrapper::match_game(QGame*qgame){
  QPos*root=qgame->getRoot();
  uassert(root,"gfw null root");
  return theNode->match_position(root);
}

bool GameFilterWrapper::match_position(QPos*qpos){
  return theNode->match_position(qpos);
}

