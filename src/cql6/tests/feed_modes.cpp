// Compare optimized native-feed preparation with the validating reference path.
#include "feed_common.h"
int main(int argc, char** argv) {
    Dataset data;
    if (!fc_loadDataset(argc > 1 ? argv[1] : "/tmp/cql_test/mega_3000.pgn", data)) return 2;
    const char* scripts[] = {"check", "mate", "stalemate", "[a]<=6", "pin", "xray (R k)",
        "shift (Kg1 and Pf2 and Pg2 and Ph2)", "function f(){check} f()", "sort \"material\" ([a]<=6)"};
    for (const char* body : scripts) {
        std::string script = std::string("cql() ") + body;
        for (int variations : {0,1}) for (int pgn : {0,1}) {
            std::vector<cql6_match> reference;
            std::vector<std::string> texts;
            long referenceGames=0, referenceSkipped=0;
            std::string referenceMessages;
            for (int mode=0; mode<4; ++mode) {
                FeedContext feed{}; feed.dataset=&data;
                cql6_options opt{}; opt.threads=4; opt.variations=variations; opt.want_pgn=pgn;
                opt.trusted_moves=mode & 1; opt.lazy_features=(mode >> 1) & 1;
                cql6_result result{}; char error[2048];
                auto start=std::chrono::steady_clock::now();
                int rc=cql6_search(script.c_str(),&opt,fc_feedNextGame,&feed,&result,error,sizeof(error));
                if (rc) {fprintf(stderr,"%s: %s\n",body,error);return 3;}
                if (!mode) {
                    referenceGames=result.ngames; referenceSkipped=result.nskipped;
                    referenceMessages=result.messages ? result.messages : "";
                    for (int i=0;i<result.nmatches;++i) {reference.push_back(result.matches[i]);texts.emplace_back(result.matches[i].pgn ? result.matches[i].pgn : "");}
                } else {
                    if (result.ngames!=referenceGames || result.nskipped!=referenceSkipped ||
                        referenceMessages!=(result.messages ? result.messages : "")) {
                        fprintf(stderr,"result metadata mismatch: %s mode=%d vars=%d pgn=%d\n",body,mode,variations,pgn);return 6;
                    }
                    if (result.nmatches != int(reference.size())) return 4;
                    for(int i=0;i<result.nmatches;++i)
                        if(result.matches[i].game_number!=reference[i].game_number || result.matches[i].first_ply!=reference[i].first_ply ||
                           texts[i]!=(result.matches[i].pgn ? result.matches[i].pgn : "")) {
                            fprintf(stderr,"mismatch: %s mode=%d vars=%d pgn=%d match=%d\n",body,mode,variations,pgn,i);return 5;
                        }
                }
                double seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
                printf("%s mode=%d variations=%d pgn=%d matches=%d seconds=%.3f\n",body,mode,variations,pgn,result.nmatches,seconds);fflush(stdout);
                cql6_free_result(&result);
            }
        }
    }
    puts("PASS: trusted/lazy feed modes preserve matches, order, first_ply and PGN");
}
