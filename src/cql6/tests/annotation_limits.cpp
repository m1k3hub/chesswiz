#include "cql6_api.h"
#include <string>
#include <cstdio>

struct Feed { bool sent=false; cql6_move move{}; };
static int next(void* context, int, cql6_game* game) {
    auto& feed=*static_cast<Feed*>(context);
    if (feed.sent) return 0;
    feed.sent=true;
    *game={0,nullptr,0,nullptr,1,&feed.move};return 1;
}
int main() {
    for (int length : {0,4490,4496,4497,4500,4800,5000})
    for (int remove : {0,1}) for (int pgn : {0,1}) {
        std::string comment(length,'x');
        Feed feed{};feed.move={3,0,0,0,comment.c_str()};
        cql6_options options{};options.threads=1;options.want_pgn=pgn;
        std::string script=remove ? "cql() terminal and removecomment" : "cql() terminal";
        cql6_result result{};char error[1024];
        if (cql6_search(script.c_str(),&options,next,&feed,&result,error,sizeof(error))) {
            fprintf(stderr,"%s\n",error);return 2;
        }
        // Compare the reported ply with the emitted annotation, including the
        // boundary's separating space and the upstream truncation behavior.
        int expected=length<=4496 || (remove && length<=4497) ? 1 : -1;
        if (result.nmatches!=1 || result.matches[0].first_ply!=expected ||
            (pgn && ((std::string(result.matches[0].pgn).find("CQL")!=std::string::npos)!=(expected==1)))) {
            fprintf(stderr,"annotation mismatch len=%d remove=%d pgn=%d expected=%d got=%d\n",
                    length,remove,pgn,expected,result.nmatches ? result.matches[0].first_ply : -2);return 3;
        }
        cql6_free_result(&result);
    }
    puts("PASS: first_ply follows actual annotation emission across comment limits");
}
