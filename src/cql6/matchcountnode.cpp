#include "node.h"

MatchCountNode::MatchCountNode(Range*r,bool s) : range{r},sort{s} {
  uassert(range,"mcnmcn range");
}

