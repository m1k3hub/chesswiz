// A batch must equal independent searches while reading/preparing each game once.
#include "feed_common.h"

struct Match { int game, ply; std::string pgn; };
static int search(const std::vector<const char*>& scripts, const Dataset& data,
                  int threads, int pgn, int limit, cql6_result& result, FeedContext& feed) {
    feed=FeedContext{}; feed.dataset=&data;
    cql6_options options{};
    options.threads=threads; options.want_pgn=pgn; options.max_matches=limit;
    options.lazy_features=1;
    options.additional_script_count=int(scripts.size())-1;
    options.additional_scripts=scripts.size()>1 ? scripts.data()+1 : nullptr;
    char error[2048];
    int rc=cql6_search(scripts[0],&options,fc_feedNextGame,&feed,&result,error,sizeof(error));
    if (rc) fprintf(stderr,"search failed: %s\n",error);
    return rc;
}

int main(int argc, char** argv) {
    Dataset data;
    if (!fc_loadDataset(argc>1 ? argv[1] : "/tmp/cql_test/mega_3000.pgn",data)) return 2;
    const std::vector<const char*> scripts{
        "cql() check", "cql(variations) check", "cql() sort \"material\" ([a]<=6)",
        "cql() check and comment \"batch-first\"",
        "cql() check and settag(\"BatchTag\" \"changed\")", "cql() removecomment",
        "cql() tag \"BatchTag\" == \"changed\"", "cql(silent) check", "cql(quiet) check",
        "cql() function f(){check} f()", "cql() line --> check --> check",
        "cql() if initial persistent Counter += 1 Counter>=2",
        "cql() if initial persistent Counter += 1 Counter>=3"};
    for (int thread_count : {1,8}) for (int pgn : {0,1}) for (int limit : {0,3}) {
        std::vector<std::vector<Match>> reference(scripts.size());
        for (size_t s=0;s<scripts.size();++s) {
            cql6_result result{}; FeedContext feed{};
            if (search({scripts[s]},data,thread_count,pgn,limit,result,feed)) return 3;
            for (int i=0;i<result.nmatches;++i) {
                auto& m=result.matches[i];
                reference[s].push_back({m.game_number,m.first_ply,m.pgn ? m.pgn : ""});
            }
            cql6_free_result(&result);
        }
        cql6_result result{}; FeedContext feed{};
        if (search(scripts,data,thread_count,pgn,limit,result,feed)) return 4;
        if (feed.next_idx!=data.games.size() || result.ngames+result.nskipped!=long(data.games.size()) || result.threads_used!=1) {
            fprintf(stderr,"batch reread/skipped games or failed to honor persistent single-thread constraint\n");return 5;
        }
        std::vector<size_t> next(scripts.size(),0);
        int previous_script=-1;
        for (int i=0;i<result.nmatches;++i) {
            auto& m=result.matches[i];
            int s=m.script_index;
            if (s<previous_script || s<0 || s>=int(scripts.size()) || next[s]>=reference[s].size()) return 6;
            previous_script=s;
            const auto& expected=reference[s][next[s]++];
            if (m.game_number!=expected.game || m.first_ply!=expected.ply ||
                (m.pgn ? m.pgn : "")!=expected.pgn) {
                fprintf(stderr,"batch mismatch script=%d match=%zu pgn=%d threads=%d limit=%d\n",s,next[s]-1,pgn,thread_count,limit);
                std::ofstream("/tmp/cql6-multi-expected.pgn") << expected.pgn;
                std::ofstream("/tmp/cql6-multi-actual.pgn") << (m.pgn ? m.pgn : "");return 7;
            }
        }
        for (size_t s=0;s<scripts.size();++s) if (next[s]!=reference[s].size()) return 8;
        std::string messages=result.messages ? result.messages : "";
        std::string value=std::to_string(result.ngames);
        if (messages.find("script 11 Counter: "+value)==std::string::npos ||
            messages.find("script 12 Counter: "+value)==std::string::npos) return 9;
        printf("batch parity threads=%d pgn=%d max=%d scripts=%zu games=%ld matches=%d\n",
               thread_count,pgn,limit,scripts.size(),result.ngames,result.nmatches);fflush(stdout);
        cql6_free_result(&result);
    }
    // Without persistent variables the batch must actually exercise eight workers.
    cql6_result result{}; FeedContext feed{};
    if (search({scripts[0],scripts[1],scripts[2]},data,8,0,0,result,feed) || result.threads_used!=8) return 10;
    int cursor=0;
    for (int s=0;s<3;++s) {
        cql6_result single{}; FeedContext single_feed{};
        if (search({scripts[s]},data,8,0,0,single,single_feed)) return 11;
        for (int i=0;i<single.nmatches;++i) {
            if (cursor>=result.nmatches) return 12;
            auto& batch=result.matches[cursor++]; auto& one=single.matches[i];
            if (batch.script_index!=s || batch.game_number!=one.game_number || batch.first_ply!=one.first_ply) return 13;
        }
        cql6_free_result(&single);
    }
    if (cursor!=result.nmatches) return 14;
    cql6_free_result(&result);
    if (!search({scripts[0],"cql() this_is_invalid"},data,8,0,0,result,feed) || feed.next_idx!=0) return 15;
    cql6_free_result(&result);
    // Parser failure must not poison the following batch.
    if (search({scripts[0],scripts[1]},data,8,0,0,result,feed)) return 16;
    cql6_free_result(&result);
    puts("PASS: multi-script feed-once, independent views/annotations/sort/limits/persistents");
}
