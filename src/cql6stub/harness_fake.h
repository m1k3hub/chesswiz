// Standalone test boundary: no Scidb codecs or Tk; all scheduling is real glue/Tcl.
#pragma once
#include <tcl.h>
#include <memory>
#include <map>
#include <string>
#include <stdexcept>
#include <thread>
#include <cassert>
namespace mstl { struct exception : std::runtime_error { using std::runtime_error::runtime_error; }; }
namespace db {
namespace variant { enum Type { Normal }; }
struct Database {
 unsigned count;
 std::thread::id owner = std::this_thread::get_id();
 unsigned countGames() const { assert(owner == std::this_thread::get_id()); return count; }
 template<class S> bool snapshot(unsigned n, S& s) const {
  assert(owner == std::this_thread::get_id());
  s.strings.emplace_back("White", "White " + std::to_string(n));
  s.strings.emplace_back("Black", "Black " + std::to_string(n));
  s.strings.emplace_back("Date", "2024.03.07");
  s.moves.push_back({0,12,28,0,nullptr}); s.comments.emplace_back("fixture");
  return true;
 }
};
}
namespace app {
struct Cursor { db::Database db; db::Database const& database() const { return db; } };
struct Application {
 std::map<std::string, std::unique_ptr<Cursor>> bases;
 bool contains(char const* b, db::variant::Type) const { return bases.count(b); }
 Cursor& cursor(char const* b, db::variant::Type) { return *bases.at(b); }
};
}
namespace tcl {
extern thread_local Tcl_Interp* testInterp;
inline void setResult(Tcl_Obj* o) { Tcl_SetObjResult(testInterp, o); }
inline void setResult(char const* s) { setResult(Tcl_NewStringObj(s,-1)); }
inline void setResult(int n) { setResult(Tcl_NewIntObj(n)); }
inline void createCommand(Tcl_Interp* t, char const* n, Tcl_ObjCmdProc* p) { Tcl_CreateObjCommand(t,n,p,nullptr,nullptr); }
namespace game { inline db::variant::Type variantFromObj(int, Tcl_Obj* const*, int) { return db::variant::Normal; } }
namespace app { extern ::app::Application* scidb; }
namespace cql6 { void init(Tcl_Interp*); }
}
