// Host-only adapter: pristine executable -> ordered game/first-ply TSV.
#include "feed_common.h"
int main(int argc, char** argv) {
    if (argc!=5) return 2;
    OracleResult result=fc_runOracle(argv[1],argv[2],argv[3],true,std::atoi(argv[4])!=0);
    if (result.exit_status!=0) {
        fprintf(stderr,"pristine oracle failed: %d\n%s",result.exit_status,result.stdoutText.c_str());return 3;
    }
    for (const auto& match : result.ordered) printf("%d\t%d\n",match.game_number,match.first_ply);
}
