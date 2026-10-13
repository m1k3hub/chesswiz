// Differential startup-cache test against the shipped, compressed source data.
#include "db/db_player.h"
#include "db/db_site.h"
#include "db/db_startup_cache.h"
#include "util/u_zstream.h"
#include "sys/sys_utf8.h"
#include <cstring>
#include <tcl.h>
#include <iostream>
namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }
#include <stdexcept>
#include <string>
#include <chrono>
#include <algorithm>
#include <utility>

using db::cache::Writer;
void require(bool b, char const* msg) { if (!b) throw std::runtime_error(msg); }
int sign(int n) { return (n>0)-(n<0); }
void sameComparison(mstl::string const& a, mstl::string const& b) {
    require(sign(sys::utf8::compare(a,b))==sign(std::strcmp(a.c_str(),b.c_str())),"UTF-8 comparator changed sort order");
}
void compareNames() {
    unsigned n=db::Player::countPlayers();
    for (unsigned i=0;i<n;++i) {
        auto const& name=db::Player::getPlayer(i).name(); sameComparison(name,name);
        if (i) sameComparison(db::Player::getPlayer(i-1).name(),name);
        sameComparison(name,db::Player::getPlayer((uint64_t(i)*7919+17)%n).name());
    }
    char const* examples[]={"", "A", "a", "é", "ê", "Å", "Ж", "Я", "中国", "日本", "😀"};
    for (auto a : examples) for (auto b : examples) sameComparison(mstl::string(a),mstl::string(b));
}
void player(Writer& w, db::Player const& p) {
    w.string(p.name()); w.string(p.asciiName()); w.string(p.url());
    w.u32(p.sex()); w.u32(p.type()); w.string(p.dateOfBirth().asString());
    w.string(p.dateOfDeath().asString()); w.u32(p.birthYear()); w.u32(p.deathYear());
    w.u32(p.highestElo()); w.u32(p.latestElo()); w.u32(p.highestRating()); w.u32(p.latestRating());
    for (unsigned i=0;i<db::rating::Last;++i) {
        w.u32(p.highestRating(db::rating::Type(i))); w.u32(p.latestRating(db::rating::Type(i)));
    }
    w.u32(p.ratingType()); w.u32(p.title()); w.u32(p.titles());
    w.u32(p.federation()); w.u32(p.nativeCountry()); w.u32(p.fideID());
    for (unsigned i=db::organization::Fide;i<=db::organization::ICCF;++i) {
        w.u32(p.hasID(db::organization::ID(i))); w.string(p.organization(db::organization::ID(i)));
    }
    w.u32(p.dsbID()); w.u32(p.ecfID()); w.u32(p.iccfID()); w.u32(p.viafID());
    w.string(p.pndID()); w.string(p.chessgamesID()); w.u32(p.region()); w.u32(p.frequency());
    w.u32(p.isEngine()); w.u32(p.isUnique()); w.u32(p.isNotUnique());
    w.u32(p.supportsUciProtocol()); w.u32(p.supportsWinboardProtocol());
    w.u32(p.supportsChess960()); w.u32(p.supportsShuffleChess()); w.u32(p.supportsBughouseChess());
    w.u32(p.supportsCrazyhouseChess()); w.u32(p.supportsLosersChess());
    w.u32(p.supportsSuicideChess()); w.u32(p.supportsGiveawayChess()); w.u32(p.supportsThreeCheckChess());
    w.u32(p.aliases().size());
    for (unsigned i=0;i<p.aliases().size();++i) w.string(p.aliases()[i]);
    db::Player::AssocList links; w.u32(p.wikipediaLinks(links));
    for (auto i=links.begin();i!=links.end();++i) { w.string(i->first); w.string(i->second); }
}
void found(Writer& w, db::Player const* p) { w.u32(p!=0); if (p) player(w,*p); }
std::vector<std::pair<size_t,std::string>> records;
struct Snapshot : db::Player::PlayerCallback {
    Writer w;
    void entry(unsigned index, db::Player const& p) override {
        records.emplace_back(w.bytes.size(),p.name().c_str());
        w.u32(index); player(w,p);
        found(w,db::Player::findPlayer(p.name(),p.federation(),p.sex()));
        if (p.fideID()) found(w,db::Player::findFidePlayer(p.fideID()));
        if (p.iccfID()) found(w,db::Player::findIccfPlayer(p.iccfID()));
        if (p.dsbID()) found(w,db::Player::findDsbPlayer(p.dsbID()));
        if (p.ecfID()) found(w,db::Player::findEcfPlayer(p.ecfID()));
    }
};
void site(Writer& w, db::Site const& s) {
    w.string(s.name()); w.u32(s.countCountries());
    for (unsigned i=0;i<s.countCountries();++i) {
        auto c=s.country(i); w.u32(c); w.u32(s.containsCountry(c)); w.string(s.nonDiacriticName(c));
        auto const& aliases=s.aliases(c); w.u32(aliases.size());
        for (unsigned j=0;j<aliases.size();++j) w.string(aliases[j]);
    }
}
std::vector<std::pair<unsigned,std::string>> siteNames;
std::vector<std::pair<unsigned,std::string>> allSiteMatches() {
    std::vector<std::pair<unsigned,std::string>> result;
    for (unsigned c=1;c<256;++c) {
        char prefix[]={char(c),0}; db::Site::Matches sites; db::Site::findMatches(prefix,sites,1000000);
        for (unsigned i=0;i<sites.size();++i) result.emplace_back(sites[i].first,sites[i].second->name().c_str());
    }
    require(!result.empty(),"no site matches"); return result;
}
std::vector<unsigned char> snapshot() {
    records.clear();
    Snapshot s; s.w.u32(db::Player::countPlayers()); db::Player::enumerate(s);
    if (siteNames.empty()) siteNames=allSiteMatches();
    s.w.u32(siteNames.size());
    for (auto const& row : siteNames) {
        records.emplace_back(s.w.bytes.size(),"site "+row.second);
        s.w.u32(row.first); auto p=db::Site::findSite(mstl::string(row.second.c_str()));
        s.w.u32(p!=0); if (p) site(s.w,*p);
    }
    for (char const* prefix : {"Kas", "Carlsen", "Stock", "Tal"}) {
        db::Player::Matches matches; db::Player::findMatches(prefix,matches,100);
        s.w.u32(matches.size()); for (unsigned i=0;i<matches.size();++i) player(s.w,*matches[i]);
    }
    for (char const* prefix : {"London", "Berlin", "New", "San"}) {
        db::Site::Matches matches; db::Site::findMatches(prefix,matches,100);
        s.w.u32(matches.size()); for (unsigned i=0;i<matches.size();++i) { s.w.u32(matches[i].first); site(s.w,*matches[i].second); }
    }
    return s.w.bytes;
}
void compare(std::vector<unsigned char> const& expected, char const* message) {
    auto actual=snapshot();
    if (actual==expected) return;
    size_t i=0; while (i<actual.size() && i<expected.size() && actual[i]==expected[i]) ++i;
    auto record=std::upper_bound(records.begin(),records.end(),i,[](size_t offset, auto const& item) { return offset<item.first; });
    if (record!=records.begin()) { --record; std::cerr<<"First difference: "<<record->second<<", byte "<<(i-record->first)<<" of record (global "<<i<<")\n"; }
    throw std::runtime_error(message);
}
void parse(char const* root, char const* name, void (*fn)(mstl::istream&), char const* suffix="txt") {
    util::ZStream::setZipFileSuffixes(util::ZStream::Strings(1,suffix));
    mstl::string path((std::string(root)+"/"+name).c_str());
    util::ZStream stream(path,mstl::ios_base::in|mstl::ios_base::binary);
    require(stream.isOpen(),"source unavailable"); fn(stream);
}
void restore(std::vector<unsigned char> const& bytes) {
    db::cache::Reader r(bytes); auto p=db::Player::readCache(r); auto s=db::Site::readCache(r);
    r.finish(); p->commit(); s->commit();
}
int main(int argc,char** argv) {
    try {
        Tcl_FindExecutable(argv[0]); tcl::bits::interp=Tcl_CreateInterp();
        require(Tcl_Init(tcl::bits::interp)==TCL_OK,"Tcl initialization failed");
        char const* root=argc>1?argv[1]:"src/data";
        auto started=std::chrono::steady_clock::now();
        parse(root,"ratings_utf8.ssp.zip",db::Player::parseSpellcheckFile,"ssp");
        parse(root,"ratings-additional.ssp",db::Player::parseSpellcheckFile,"ssp");
        parse(root,"engines.txt",db::Player::parseComputerList);
        parse(root,"players_list.zip",db::Player::parseFideRating);
        parse(root,"ips-ratings.txt",db::Player::parseIpsRatingList);
        parse(root,"dwz-ratings.txt",db::Player::parseDwzRating);
        parse(root,"ecf-ratings.txt",db::Player::parseEcfRating);
        parse(root,"iccf-ratings.txt",db::Player::parseIccfRating);
        parse(root,"wikipedia-de.txt",db::Player::parseWikipediaLinks);
        parse(root,"wikipedia-en.txt",db::Player::parseWikipediaLinks);
        parse(root,"chessgames.com.zip",db::Player::parseChessgamesDotComLinks);
        parse(root,"cities.txt",db::Site::parseFile);
        auto parsed=std::chrono::steady_clock::now();
        db::Player::loadDone(); db::Site::loadDone();
        auto finalized=std::chrono::steady_clock::now();
        if (argc>2 && std::string(argv[2])=="--timing-only") {
            Writer w; auto writeStart=std::chrono::steady_clock::now();
            db::Player::writeCache(w); db::Site::writeCache(w);
            auto writeEnd=std::chrono::steady_clock::now(); restore(w.bytes);
            auto readEnd=std::chrono::steady_clock::now();
            auto seconds=[](auto a,auto b) { return std::chrono::duration<double>(b-a).count(); };
            std::cout<<"phase parse="<<seconds(started,parsed)<<" loadDone="<<seconds(parsed,finalized)
                     <<" cache-write="<<seconds(writeStart,writeEnd)<<" cache-read="<<seconds(writeEnd,readEnd)<<" seconds cache-bytes="<<w.bytes.size()<<"\n";
            return 0;
        }
        compareNames();
        auto expected=snapshot(); Writer w;
        auto writeStart=std::chrono::steady_clock::now();
        db::Player::writeCache(w); db::Site::writeCache(w);
        auto writeEnd=std::chrono::steady_clock::now();
        for (size_t n : {size_t(0),size_t(3),w.bytes.size()/2,w.bytes.size()-1}) {
            std::vector<unsigned char> bad(w.bytes.begin(),w.bytes.begin()+n); bool rejected=false;
            try { restore(bad); } catch (std::exception const&) { rejected=true; }
            require(rejected,"truncated cache accepted"); compare(expected,"failed read mutated live state");
        }
        auto bad=w.bytes; for (unsigned i=0;i<4;++i) bad[i]=255;
        bool rejected=false; try { restore(bad); } catch (std::exception const&) { rejected=true; }
        require(rejected,"invalid count accepted"); compare(expected,"corrupt read mutated live state");
        auto readStart=std::chrono::steady_clock::now(); restore(w.bytes);
        auto readEnd=std::chrono::steady_clock::now();
        require(allSiteMatches()==siteNames,"cache changed complete site matches");
        compare(expected,"cache changed player/site data or lookups");
        Writer again; db::Player::writeCache(again); db::Site::writeCache(again);
        restore(again.bytes); compare(expected,"second cache roundtrip changed data");
        auto seconds=[](auto a,auto b) { return std::chrono::duration<double>(b-a).count(); };
        std::cout<<"phase parse="<<seconds(started,parsed)<<" loadDone="<<seconds(parsed,finalized)
                 <<" cache-write="<<seconds(writeStart,writeEnd)<<" cache-read="<<seconds(readStart,readEnd)<<" seconds cache-bytes="<<w.bytes.size()<<"\n";
        std::cout<<"PASS: player/site cache parity, lookups, truncation and corruption ("<<db::Player::countPlayers()<<" players, "<<"all matching sites)\n";
        return 0;
    } catch (std::exception const& e) { std::cerr<<"FAIL: "<<e.what()<<'\n'; return 1; }
}
