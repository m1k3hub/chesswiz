#include "cql6_api.h"
#include <cstdio>
#include <cstring>
#include <initializer_list>
struct Feed { bool sent=false; };
static int next(void* context,int,cql6_game* game) {
    auto& feed=*static_cast<Feed*>(context);if(feed.sent)return 0;feed.sent=true;
    // f1 is still occupied: castling after 1.e4 e5 2.Nf3 Nc6 is illegal.
    static const cql6_move moves[]={{0,12,28,0,nullptr},{0,52,36,0,nullptr},
        {0,6,21,0,nullptr},{0,57,42,0,nullptr},{0,4,6,0,nullptr}};
    *game={7,nullptr,0,nullptr,5,moves};return 1;
}
int main() {
    for(int compatibility : {0,1}) {
        Feed feed{};cql6_options options{};options.threads=1;options.want_pgn=1;
        options.truncate_illegal_moves=compatibility;
        cql6_result result{};char error[1024];
        int rc=cql6_search("cql() terminal",&options,next,&feed,&result,error,sizeof(error));
        if (!compatibility) {
            if (!rc || !strstr(error,"rejected")) return 2;
        } else {
            if(rc || result.ngames!=1 || result.ntruncated!=1 || result.nskipped || result.nmatches!=1 ||
               result.matches[0].first_ply!=4 || strstr(result.matches[0].pgn,"O-O")) {
                fprintf(stderr,"prefix mismatch: %s\n",error);return 3;
            }
        }
        cql6_free_result(&result);
    }
    puts("PASS: default rejects illegal moves; explicit PGN mode retains/reports legal prefix");
}
