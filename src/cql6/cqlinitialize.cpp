#include "node.h"
#include "variable.h"
#include "attack.h"
#include "uchar.h"

void cql_initialize(){
  static bool first_call=true; //first time called
  uassert(!CqlRunningThreads,"cql_initialize: running threads");
  if(first_call){
    uassert(sizeof(Mask)==8,"Expecting sizeof of datatype 'Mask' to be 8");
#ifndef CQL6_EMBEDDED // scidb: no global side effects on the host's stdio
    setbuf(stdout,NULL);
#endif
    scid_Init(); // remove this at some future point.
    Attack::initialize();
  }
  cqlglobals_initialize();
  UChar::initialize();
  first_call=false;
}
