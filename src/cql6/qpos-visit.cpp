#include "qpos.h"
#include "markboard.h"
#include "cqlglobals.h"

void QPos::visitRoot(QPos*root,bool variations,vector<QPos*>& all){
  uassert(all.empty(),"visitRoot: bad out arg");
  uassert(root->index<0,"visitRoot: topind");
  root->index=0;
  Game*game=root->getGame();
  uassert(MarkBoard::isInitial(game),"vGame not initial");
  uassert(MarkBoard::identity(game)==root->id,"vg bad g/roo");
  uassert(root->nChildren()==0,"childs bad root");
  vector<QPos*>stack;
  stack.reserve(150);
  stack.push_back(root);
  all.push_back(root);
  while(stack.size()) {
    QPos*top=stack.back();
    uassert(top->id==MarkBoard::identity(game),"visitGame idcheck");
    int nextchild=top->nChildren();
    int gamenchildren=MarkBoard::number_children(game,variations);
    uassert(nextchild>=0&&nextchild<=gamenchildren,"vgame nextchild");
    if(nextchild==gamenchildren){
      stack.pop_back();
      int toptopi=top->index;
      int lasttopi=(int)(all.size()-1);
      uassert(toptopi>=0&&toptopi<=lasttopi,"visitroot bad topi");
      top->lastDescendantIndex=lasttopi;
      if(MarkBoard::isInitial(game))
	uassert(stack.empty(),"vgame nonempty");
      else
	MarkBoard::gameBackup(game);
      continue;
    }
    MarkBoard::move_to_child(game,nextchild);
    QPos* child=createFromParent(top,nextchild,variations);
    child->index=(int)(all.size());
    stack.push_back(child);
    all.push_back(child);
  }
  uassert(MarkBoard::isInitial(game),"visit noninitial game");
  int n=(int)(all.size());
  // scidb: was a double loop issuing n*n uassert calls (n ~ 250 positions per game);
  // the checked condition only ever involves one index at a time, so one loop is
  // enough and costs O(n)
  for (int i=0;i<n;++i)
    uassert(all[i]->index==i,"visitroot ij");
}

bool QPos::slowDescendant(QPos*v, QPos*w){
  auto parent=w;
  while(parent)
    if (v==parent)return true;
    else parent=parent->parent;
  return false;
}

