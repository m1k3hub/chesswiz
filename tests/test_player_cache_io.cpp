// Exercise the exact production Tcl filesystem/envelope adapter without Tk.
#include <tcl.h>
namespace tcl { namespace bits { Tcl_Interp* interp = nullptr; } }
#include "tcl/tcl_player_cache.h"
#include "util/u_zstream.h"
#include <iostream>
#include <string>
#include <chrono>
using namespace tcl::startup_cache;
void require(bool ok, char const* why) { if (!ok) throw std::runtime_error(why); }
void eval(Tcl_Interp* ti, char const* script) { require(Tcl_Eval(ti,script)==TCL_OK, "Tcl evaluation failed"); }
std::vector<unsigned char> readFile(std::string const& path) {
    CacheObject object(path.c_str()); CacheChannel file(tcl::bits::interp,object.obj,"rb");
    std::vector<unsigned char> bytes; unsigned char block[65536];
    for (;;) {
        int n=Tcl_Read(file.channel,reinterpret_cast<char*>(block),sizeof(block));
        require(n>=0,"fixture read failed"); if (!n) break;
        bytes.insert(bytes.end(),block,block+n);
    }
    file.close(); return bytes;
}
void writeFile(std::string const& path,std::vector<unsigned char> const& bytes) {
    CacheObject object(path.c_str()); CacheChannel file(tcl::bits::interp,object.obj,"wb");
    size_t pos=0;
    while (pos<bytes.size()) {
        int n=Tcl_Write(file.channel,reinterpret_cast<char const*>(bytes.data()+pos),
                        int(std::min<size_t>(65536,bytes.size()-pos)));
        require(n>0,"fixture write failed"); pos+=n;
    }
    file.close();
}
void noTemps(Tcl_Interp* ti) {
    eval(ti,"llength [glob -nocomplain -directory $cacheDir *.tmp]");
    require(std::string(Tcl_GetStringResult(ti))=="0","temporary file leaked");
}
std::vector<unsigned char> state() {
    db::cache::Writer w; db::Player::writeCache(w); db::Site::writeCache(w); return w.bytes;
}
void miss(Tcl_Interp* ti,Tcl_Obj* path,Tcl_Obj* sources) {
    auto before=state(); bool hit=false;
    try { hit=readPlayerCache(ti,path,sources); } catch (std::exception const&) {}
    require(!hit,"invalid cache accepted"); require(before==state(),"failed read mutated live databases");
    Tcl_ResetResult(ti);
}
void parse(std::string const& root,char const* file,void (*fn)(mstl::istream&),char const* suffix) {
    util::ZStream::setZipFileSuffixes(util::ZStream::Strings(1,suffix));
    mstl::string path((root+"/"+file).c_str());
    util::ZStream in(path,mstl::ios_base::in|mstl::ios_base::binary);
    require(in.isOpen(),"shipped fixture unavailable"); fn(in);
}
int benchmark(Tcl_Interp* ti,std::string const& root,char const* cachePath) {
    struct Source { char const* name; void (*fn)(mstl::istream&); char const* suffix; };
    Source files[]={
        {"ratings_utf8.ssp.zip",db::Player::parseSpellcheckFile,"ssp"},
        {"ratings-additional.ssp",db::Player::parseSpellcheckFile,"ssp"},
        {"engines.txt",db::Player::parseComputerList,"txt"},
        {"players_list.zip",db::Player::parseFideRating,"txt"},
        {"ips-ratings.txt",db::Player::parseIpsRatingList,"txt"},
        {"dwz-ratings.txt",db::Player::parseDwzRating,"txt"},
        {"ecf-ratings.txt",db::Player::parseEcfRating,"txt"},
        {"iccf-ratings.txt",db::Player::parseIccfRating,"txt"},
        {"wikipedia-de.txt",db::Player::parseWikipediaLinks,"txt"},
        {"wikipedia-en.txt",db::Player::parseWikipediaLinks,"txt"},
        {"chessgames.com.zip",db::Player::parseChessgamesDotComLinks,"txt"},
        {"cities.txt",db::Site::parseFile,"txt"}
    };
    CacheObject path(cachePath),sources("");
    for (auto const& f : files) {
        CacheObject source((root+"/"+f.name).c_str());
        Tcl_ListObjAppendElement(ti,sources.obj,source.obj);
    }
    Tcl_SetVar(ti,"benchmarkCache",cachePath,TCL_GLOBAL_ONLY);
    eval(ti,"set benchmarkUser [file join [file dirname $benchmarkCache] fide-players.txt]; set benchmarkUser");
    CacheObject user(Tcl_GetStringResult(ti)); Tcl_ListObjAppendElement(ti,sources.obj,user.obj);
    auto start=std::chrono::steady_clock::now(); bool hit=false;
    try { hit=readPlayerCache(ti,path.obj,sources.obj); } catch (std::exception const&) { Tcl_ResetResult(ti); }
    auto readEnd=std::chrono::steady_clock::now(),parseEnd=readEnd,doneEnd=readEnd,writeEnd=readEnd;
    if (!hit) {
        for (auto const& f : files) parse(root,f.name,f.fn,f.suffix);
        eval(ti,"file exists $benchmarkUser");
        if (std::string(Tcl_GetStringResult(ti))=="1") {
            util::ZStream in(mstl::string(Tcl_GetString(user.obj)),mstl::ios_base::in|mstl::ios_base::binary);
            require(in.isOpen(),"user FIDE source unavailable"); db::Player::parseFideRating(in);
        }
        parseEnd=std::chrono::steady_clock::now();
        db::Player::loadDone(); db::Site::loadDone(); playerCacheFinalized=true;
        doneEnd=std::chrono::steady_clock::now();
        require(writePlayerCache(ti,path.obj,sources.obj),"benchmark cache write failed");
        writeEnd=std::chrono::steady_clock::now();
    }
    auto seconds=[](auto a,auto b) { return std::chrono::duration<double>(b-a).count(); };
    std::cout<<"HEADLESS production-adapter benchmark cache="<<(hit?"hit":"miss")
             <<" read="<<seconds(start,readEnd)<<" parse="<<seconds(readEnd,parseEnd)
             <<" loadDone="<<seconds(parseEnd,doneEnd)<<" write="<<seconds(doneEnd,writeEnd)
             <<" total="<<seconds(start,writeEnd)<<" seconds players="<<db::Player::countPlayers()<<'\n';
    return 0;
}
int main(int argc,char** argv) {
    std::string dir;
    try {
        Tcl_FindExecutable(argv[0]); auto ti=Tcl_CreateInterp(); tcl::bits::interp=ti;
        require(Tcl_Init(ti)==TCL_OK,"Tcl initialization failed");
        eval(ti,"namespace eval ::scidb::misc {}; set cacheVersion test; set cacheRevision test; set cacheSha test; proc ::scidb::misc::buildInfo {} {list version $::cacheVersion revision $::cacheRevision gitSha $::cacheSha}");
        if (argc==4 && std::string(argv[2])=="--benchmark") return benchmark(ti,argv[1],argv[3]);
        eval(ti,"set channel [file tempfile cacheDir]; close $channel; file delete $cacheDir; file mkdir $cacheDir; set cacheDir");
        dir=Tcl_GetStringResult(ti);
        CacheObject path((dir+"/players.bin").c_str()),source((dir+"/source.txt").c_str()),user((dir+"/fide-players.txt").c_str());
        Tcl_SetVar(ti,"cacheSource",Tcl_GetString(source.obj),TCL_GLOBAL_ONLY);
        CacheObject sources(""); Tcl_ListObjAppendElement(ti,sources.obj,source.obj); Tcl_ListObjAppendElement(ti,sources.obj,user.obj);
        writeFile(dir+"/source.txt",{'a','b','c'});
        miss(ti,path.obj,sources.obj); // Missing cache still binds the pre-parse manifest.
        std::string root=argc>1?argv[1]:"src/data";
        parse(root,"ratings-additional.ssp",db::Player::parseSpellcheckFile,"ssp");
        parse(root,"engines.txt",db::Player::parseComputerList,"txt");
        parse(root,"cities.txt",db::Site::parseFile,"txt");
        db::Player::loadDone(); db::Site::loadDone();
        require(!writePlayerCache(ti,path.obj,sources.obj),"write accepted before startup finalized");
        playerCacheFinalized=true;
        auto start=std::chrono::steady_clock::now();
        require(writePlayerCache(ti,path.obj,sources.obj),"initial write failed");
        auto saved=readFile(dir+"/players.bin"); require(saved.size()>100,"empty cache");
        require(writePlayerCache(ti,path.obj,sources.obj),"atomic replacement failed");
        noTemps(ti);
        for (size_t n : {size_t(0),size_t(3),saved.size()/2,saved.size()-1}) {
            writeFile(dir+"/players.bin",{saved.begin(),saved.begin()+n}); miss(ti,path.obj,sources.obj);
        }
        for (size_t offset : {size_t(0),size_t(4),saved.size()/2,saved.size()-1}) {
            auto bad=saved; bad[offset]^=0x80; writeFile(dir+"/players.bin",bad); miss(ti,path.obj,sources.obj);
        }
        // Even a checksum-correct invalid payload must be staged and rejected.
        auto bad=saved; auto header=cacheHeader(ti,sources.obj);
        for (unsigned i=0;i<4;++i) bad[header.bytes.size()+i]=255;
        uint64_t sum=db::cache::checksum(bad,bad.size()-8);
        for (unsigned i=0;i<8;++i) bad[bad.size()-8+i]=(sum>>(8*i))&255;
        writeFile(dir+"/players.bin",bad); miss(ti,path.obj,sources.obj);
        // Fail only after the complete player staging state has been constructed.
        db::cache::Writer playerPayload; db::Player::writeCache(playerPayload);
        bad=saved;
        for (unsigned i=0;i<4;++i) bad[header.bytes.size()+playerPayload.bytes.size()+i]=255;
        sum=db::cache::checksum(bad,bad.size()-8);
        for (unsigned i=0;i<8;++i) bad[bad.size()-8+i]=(sum>>(8*i))&255;
        writeFile(dir+"/players.bin",bad); miss(ti,path.obj,sources.obj);
        writeFile(dir+"/players.bin",saved);
        for (char const* change : {"set cacheVersion changed", "set cacheRevision changed", "set cacheSha changed"}) {
            eval(ti,change); miss(ti,path.obj,sources.obj);
            eval(ti,"set cacheVersion test; set cacheRevision test; set cacheSha test");
        }
        CacheObject reverse(""); Tcl_ListObjAppendElement(ti,reverse.obj,user.obj); Tcl_ListObjAppendElement(ti,reverse.obj,source.obj);
        miss(ti,path.obj,reverse.obj);
        CacheObject shortened(""); Tcl_ListObjAppendElement(ti,shortened.obj,source.obj); miss(ti,path.obj,shortened.obj);
        eval(ti,"set originalMtime [file mtime $cacheSource]");
        writeFile(dir+"/source.txt",{'a','b','c','d'}); miss(ti,path.obj,sources.obj);
        playerCacheSources=header.bytes; // The one pre-parse read is the production binding.
        require(!writePlayerCache(ti,path.obj,sources.obj),"changed-during-parse source accepted for write");
        writeFile(dir+"/source.txt",{'a','b','c'});
        eval(ti,"file mtime $cacheSource [expr {$originalMtime+5}]");
        miss(ti,path.obj,sources.obj);
        eval(ti,"file mtime $cacheSource $originalMtime");
        writeFile(dir+"/fide-players.txt",{'f'}); miss(ti,path.obj,sources.obj);
        require(Tcl_FSDeleteFile(user.obj)==0,"user source removal failed");
        auto count=db::Player::countPlayers();
        require(readPlayerCache(ti,path.obj,sources.obj),"valid cache rejected after optional source removed");
        require(db::Player::countPlayers()==count,"successful restore changed player count");
        require(playerCacheRestored && playerCacheFinalized,"successful read did not set startup flags");
        require(writePlayerCache(ti,path.obj,sources.obj),"write after restore failed");
        writeFile(dir+"/fide-players.txt",{'f'}); miss(ti,path.obj,sources.obj);
        miss(ti,path.obj,sources.obj); require(writePlayerCache(ti,path.obj,sources.obj),"present user source write failed");
        require(Tcl_FSDeleteFile(user.obj)==0,"user source removal failed"); miss(ti,path.obj,sources.obj);
        CacheObject directory(dir.c_str()); miss(ti,directory.obj,sources.obj);
        CacheObject missingParent((dir+"/missing/players.bin").c_str());
        miss(ti,path.obj,sources.obj);
        require(!writePlayerCache(ti,missingParent.obj,sources.obj),"write to missing parent accepted");
        noTemps(ti);
        require(!writePlayerCache(ti,directory.obj,sources.obj),"rename over directory accepted");
        noTemps(ti);
        CacheObject invalidSources("{");
        miss(ti,path.obj,invalidSources.obj);
        require(playerCacheSources.empty(),"failed header retained an earlier source manifest");
        require(!writePlayerCache(ti,path.obj,sources.obj),"write accepted after preparse header failure");
        CacheObject tooManySources("");
        for (unsigned i=0;i<129;++i) Tcl_ListObjAppendElement(ti,tooManySources.obj,source.obj);
        miss(ti,path.obj,tooManySources.obj);
        require(playerCacheSources.empty(),"oversized manifest retained a source binding");
        // Sparse file verifies the stat size cap before any database allocation.
        Tcl_SetVar(ti,"cacheOversized",(dir+"/oversized.bin").c_str(),TCL_GLOBAL_ONLY);
        eval(ti,"set sparse [open $cacheOversized wb]; fconfigure $sparse -translation binary; seek $sparse 536870912; puts -nonewline $sparse x; close $sparse");
        CacheObject oversized((dir+"/oversized.bin").c_str());
        miss(ti,oversized.obj,sources.obj);
        require(Tcl_FSDeleteFile(oversized.obj)==0,"oversized fixture removal failed");
        eval(ti,"file delete -force $cacheDir");
        std::cout<<"PASS: production cache envelope, manifest invalidation, atomic replacement, corruption, read/write errors and failed-read state isolation ("<<saved.size()<<" bytes; "<<std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count()<<" s)\n";
        return 0;
    } catch (std::exception const& e) { std::cerr<<"FAIL: "<<e.what()<<" (fixtures "<<dir<<")\n"; return 1; }
}
