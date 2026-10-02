// Frozen prefetch-task baseline; test-only reference, never linked into Scidb.
// CQL 6 host adapter. The engine and its callbacks never use Tcl objects.
#ifdef CQL6_STANDALONE
#include "harness_fake.h"
#else
#include "tcl_cql6.h"
#include "tcl_application.h"
#include "tcl_base.h"
#include "tcl_game.h"
#include "app_application.h"
#include "app_cursor.h"
#include "db_consumer.h"
#include "db_database.h"
#include "db_tag_set.h"
#include "db_comment.h"
#include "db_move.h"
#include "m_exception.h"
#endif
#include "../cql6/cql6_api.h"

#include <condition_variable>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

using namespace db;
using namespace tcl;
using namespace tcl::app;

namespace {

struct Snapshot
{
	int number;
	std::string fen;
	std::vector<std::pair<std::string, std::string>> strings;
	std::vector<std::string> comments;
	std::vector<cql6_tag> tags;
	std::vector<cql6_move> moves;

	void seal()
	{
		for (auto const& s : strings) tags.push_back({s.first.c_str(), s.second.c_str()});
		for (size_t i = 0; i < moves.size(); ++i)
			moves[i].comment = comments[i].empty() ? nullptr : comments[i].c_str();
	}
	void fill(cql6_game& g) const
	{
		g = {number, fen.empty() ? nullptr : fen.c_str(), int(tags.size()), tags.data(),
			int(moves.size()), moves.data()};
	}
};

#ifndef CQL6_STANDALONE
struct Exporter : Consumer
{
	Snapshot& data;
	bool variations;
	std::string preceding;
	Exporter(Snapshot& s, variant::Type v, bool vars)
		:Consumer(format::Pgn, "utf-8", TagBits(), true), data(s), variations(vars)
	{
		setVariant(v);
	}
	format::Type format() const override { return format::Scidb; }
	void start() override {}
	void finish() override {}
	bool beginGame(TagSet const&) override { return true; }
	save::State endGame(TagSet const& tags) override
	{
		for (tag::ID id = tags.findFirst(); id < tag::ExtraTag; id = tags.findNext(id))
			data.strings.emplace_back(tag::toName(id).c_str(), tags.value(id).c_str());
		for (unsigned i = 0; i < tags.countExtra(); ++i)
			data.strings.emplace_back(tags.extra(i).name.c_str(), tags.extra(i).value.c_str());
		// The seven mandatory PGN tags exist even for an incomplete database record.
		char const* names[] = {"White", "Black", "Event", "Site", "Date", "Round", "Result"};
		for (auto name : names)
		{
			bool found = false;
			for (auto& s : data.strings) if (s.first == name)
			{
				found = true;
				if (s.second.empty()) s.second = !std::strcmp(name, "Date") ? "????.??.??" : "?";
			}
			if (!found) data.strings.emplace_back(name,
				!std::strcmp(name, "Date") ? "????.??.??" : !std::strcmp(name, "Result") ? "*" : "?");
		}
		return save::Ok;
	}
	void beginMoveSection() override
	{
		if (!startBoard().isStandardPosition(variant()))
			data.fen = startBoard().toFen(variant()).c_str();
	}
	void endMoveSection(result::ID) override {}
	void record(int kind, int from = 0, int to = 0, int promo = 0)
	{
		data.moves.push_back({kind, from, to, promo, nullptr});
		data.comments.emplace_back();
	}
	bool include() const { return variations || variationLevel() == 0; }
	std::string text(Comment const& c)
	{
		mstl::string value;
		c.flatten(value, encoding::Utf8, 0);
		return value.c_str();
	}
	void comment(Comment const& c)
	{
		if (!include() || c.isEmpty()) return;
		if (data.comments.empty()) { preceding = text(c); return; }
		std::string& dst = data.comments.back();
		if (!dst.empty()) dst += '\n';
		dst += text(c);
	}
	void sendPrecedingComment(Comment const& c, Annotation const&, MarkSet const&) override { comment(c); }
	void sendTrailingComment(Comment const& c, bool) override { comment(c); }
	void sendComment(Comment const& c) override { comment(c); }
	void sendMoveInfo(MoveInfoSet const&) override {}
	bool sendMove(Move const& m) override
	{
		if (include())
		{
			int promo = 0;
			if (m.isPromotion()) switch (m.promoted())
			{
				case piece::Queen: promo = 'Q'; break;
				case piece::Rook: promo = 'R'; break;
				case piece::Bishop: promo = 'B'; break;
				case piece::Knight: promo = 'N'; break;
				default: break;
			}
			record(0, m.isCastling() ? m.castlingKingFrom() : m.from(),
				m.isCastling() ? m.castlingKingTo() : m.to(), promo);
			if (!preceding.empty()) { data.comments.back().swap(preceding); preceding.clear(); }
		}
		return true;
	}
	bool sendMove(Move const& m, Annotation const&, MarkSet const&, Comment const& pre,
		Comment const& post) override
	{
		bool ok = sendMove(m);
		comment(pre);
		comment(post);
		return ok;
	}
	void beginVariation() override { if (variations) record(1); }
	void endVariation(bool) override { if (variations) record(2); }
};

#endif

struct Job
{
	int id = 0;
	Tcl_Interp* interp = nullptr; // used only on the owning Tcl thread
	Tcl_ThreadId owner;
	Tcl_Obj* command = nullptr; // main-thread reference, never read by workers
	std::string base, script;
	variant::Type variant;
	unsigned count = 0, index = 0, skipped = 0;
	void const* identity = nullptr;
	cql6_options options = {};
	cql6_result result = {};
	std::mutex mutex;
	std::condition_variable changed;
	bool cancelled = false, closed = false, dead = false, pending = false, done = false;
	bool async = false;
	unsigned long requestSerial = 0;
	long progress = 0;
	std::string error;
	std::shared_ptr<Snapshot> requested;
	// Engine callbacks are serialized; each thread retains its last snapshot.
	std::map<int, std::shared_ptr<Snapshot>> retained;
	~Job() { cql6_free_result(&result); }
};

// The sole mutable global: the table also owns its mutex and id allocator.
struct JobTable
{
	std::mutex mutex;
	std::map<int, std::shared_ptr<Job>> jobs;
	int next = 1;
} jobTable;

struct Event
{
	Tcl_Event header;
	std::shared_ptr<Job>* job;
	bool completion;
};

static int eventProc(Tcl_Event*, int);

static void queue(std::shared_ptr<Job> const& job, bool completion)
{
	// Serialize queueing with interpreter deletion. No event can be queued
	// after the deletion handler has removed this interpreter's events.
	std::lock_guard<std::mutex> table(jobTable.mutex);
	std::lock_guard<std::mutex> lock(job->mutex);
	if (job->dead) return;
	Event* e = reinterpret_cast<Event*>(Tcl_Alloc(sizeof(Event)));
	e->header.proc = eventProc;
	e->job = new std::shared_ptr<Job>(job);
	e->completion = completion;
	Tcl_ThreadQueueEvent(job->owner, &e->header, TCL_QUEUE_TAIL);
	Tcl_ThreadAlert(job->owner);
}

// Thread safety: Database::exportGame resets the cursor's shared codec.
// It is NOT safe to run that operation concurrently with GUI reads, writes,
// or close. Instead the worker callback requests one owned snapshot via a
// main-thread event and waits on its own condition variable. Only the Tcl
// thread resolves the cursor and exports a single game. There is no bulk
// preloading and no main-thread wait for a worker in async mode. A callback
// touches only C++ snapshots (no Tcl/Tk), retained per engine thread until
// its next call. Database reads/writes/close remain serialized by the GUI
// thread; no database pointer ever escapes to a worker. A close execution
// trace cancels before close, including close/reopen under the same name.
// Each event costs one game decode; pathological huge games or slow storage
// can still delay a GUI turn. The engine's computation never blocks it.
static void requestGame(std::shared_ptr<Job> const& job)
{
	std::lock_guard<std::mutex> lock(job->mutex);
	job->requested.reset();
	if (!job->cancelled && !job->dead && !job->closed && job->index < job->count)
	{
		if (!scidb->contains(job->base.c_str(), job->variant)
			|| &scidb->cursor(job->base.c_str(), job->variant).database() != job->identity)
		{
			job->closed = true;
		}
		else
		{
			unsigned index = job->index++;
			try
			{
				Database const& db = scidb->cursor(job->base.c_str(), job->variant).database();
				if (index < db.countGames())
				{
					auto data = std::make_shared<Snapshot>();
					data->number = int(index);
					#ifdef CQL6_STANDALONE
					bool exported = db.snapshot(index, *data);
#else
					Exporter consumer(*data, job->variant, job->options.variations);
					bool exported = db.exportGame(index, consumer) == save::Ok;
#endif
					if (exported)
					{
						data->seal();
						job->requested = data;
					}
					else ++job->skipped;
				}
				else ++job->skipped;
			}
			catch (mstl::exception const&) { ++job->skipped; }
			catch (std::exception const& e) { job->error = e.what(); job->cancelled = true; }
		}
	}
	job->pending = false;
	job->changed.notify_all();
}

static int nextGame(void* ctx, int thread, cql6_game* g)
{
	auto job = *static_cast<std::shared_ptr<Job>*>(ctx);
	for (;;)
	{
		{
			std::lock_guard<std::mutex> lock(job->mutex);
			if (job->cancelled || job->closed || job->dead || job->index >= job->count) return 0;
			job->pending = true;
			++job->requestSerial;
			job->changed.notify_all();
		}
		std::unique_lock<std::mutex> lock(job->mutex);
		job->changed.wait(lock, [&] { return !job->pending || job->cancelled || job->closed || job->dead; });
		if (job->cancelled || job->closed || job->dead) return 0;
		if (job->requested)
		{
			job->retained[thread] = job->requested;
			job->requested->fill(*g);
			++job->progress;
			return 1;
		}
	}
}

static void searchEngine(std::shared_ptr<Job> job)
{
	char error[4096] = {};
	std::string failure;
	try
	{
		if (cql6_search(job->script.c_str(), &job->options, nextGame, &job,
			&job->result, error, sizeof(error))) failure = error[0] ? error : "CQL 6 search failed";
	}
	catch (std::exception const& e) { failure = e.what(); }
	catch (...) { failure = "CQL 6 engine exception"; }
	{
		std::lock_guard<std::mutex> lock(job->mutex);
		if (!failure.empty()) job->error = failure;
		job->done = true;
		job->changed.notify_all();
	}
}

static void run(std::shared_ptr<Job> job)
{
	if (!job->async) { searchEngine(job); return; }
	// The coordinator, not the engine callback, uses Tcl's thread event
	// APIs. nextGame uses only C++ memory, locks, and a condition variable.
	std::thread engine;
	try
	{
		engine = std::thread(searchEngine, job);
		unsigned long dispatched = 0;
		{
			std::unique_lock<std::mutex> lock(job->mutex);
			while (!job->done)
			{
				job->changed.wait(lock, [&] {
					return job->done || (job->pending && job->requestSerial != dispatched);
				});
				if (job->done) break;
				dispatched = job->requestSerial;
				lock.unlock();
				queue(job, false);
				lock.lock();
			}
		}
	}
	catch (std::exception const& e)
	{
		std::lock_guard<std::mutex> lock(job->mutex);
		job->error = e.what();
		job->cancelled = true;
		job->changed.notify_all();
	}
	if (engine.joinable()) engine.join();
	{
		std::lock_guard<std::mutex> lock(job->mutex);
		job->done = true;
	}
	queue(job, true);
}

static void put(Tcl_Interp* ti, Tcl_Obj* dict, char const* key, Tcl_Obj* value)
{
	Tcl_DictObjPut(ti, dict, Tcl_NewStringObj(key, -1), value);
}

static Tcl_Obj* resultDict(Job const& job, bool async)
{
	Tcl_Interp* ti = job.interp;
	Tcl_Obj* dict = Tcl_NewDictObj();
	std::string error = job.closed ? "database closed" : job.error;
	if (async) put(ti, dict, "ok", Tcl_NewBooleanObj(error.empty()));
	if (!error.empty()) { put(ti, dict, "error", Tcl_NewStringObj(error.c_str(), -1)); return dict; }
	Tcl_Obj* matches = Tcl_NewListObj(0, nullptr);
	for (int i = 0; i < job.result.nmatches; ++i)
	{
		cql6_match const& m = job.result.matches[i];
		Tcl_Obj* match = Tcl_NewDictObj();
		put(ti, match, "game", Tcl_NewIntObj(m.game_number));
		put(ti, match, "first_ply", Tcl_NewIntObj(m.first_ply));
		if (job.options.want_pgn) put(ti, match, "pgn", Tcl_NewStringObj(m.pgn ? m.pgn : "", -1));
		Tcl_ListObjAppendElement(ti, matches, match);
	}
	put(ti, dict, "matches", matches);
	put(ti, dict, "games", Tcl_NewWideIntObj(job.result.ngames));
	put(ti, dict, "threads", Tcl_NewIntObj(job.result.threads_used));
	put(ti, dict, "cancelled", Tcl_NewBooleanObj(job.cancelled));
	std::string messages = job.result.messages ? job.result.messages : "";
	if (job.skipped)
	{
		if (!messages.empty()) messages += '\n';
		messages += "skipped undecodable games: " + std::to_string(job.skipped);
	}
	put(ti, dict, "messages", Tcl_NewStringObj(messages.c_str(), -1));
	return dict;
}

static int eventProc(Tcl_Event* event, int flags)
{
	if (!(flags & TCL_WINDOW_EVENTS)) return 0;
	Event* e = reinterpret_cast<Event*>(event);
	auto job = *e->job;
	delete e->job;
	if (!e->completion) { requestGame(job); return 1; }
	if (!job->dead && (!scidb->contains(job->base.c_str(), job->variant)
		|| &scidb->cursor(job->base.c_str(), job->variant).database() != job->identity))
		job->closed = true;
	{
		std::lock_guard<std::mutex> table(jobTable.mutex);
		jobTable.jobs.erase(job->id);
	}
	if (!job->dead)
	{
		Tcl_Preserve(job->interp);
		Tcl_Obj* cmd = Tcl_DuplicateObj(job->command);
		Tcl_IncrRefCount(cmd);
		Tcl_ListObjAppendElement(job->interp, cmd, resultDict(*job, true));
		// Save the interpreter result: an asynchronous callback must not
		// replace the result of a command whose event loop is being serviced.
		Tcl_InterpState state = Tcl_SaveInterpState(job->interp, TCL_OK);
		int rc = Tcl_EvalObjEx(job->interp, cmd, TCL_EVAL_GLOBAL);
		if (rc != TCL_OK) Tcl_BackgroundException(job->interp, rc);
		Tcl_RestoreInterpState(job->interp, state);
		Tcl_DecrRefCount(cmd);
		Tcl_DecrRefCount(job->command);
		job->command = nullptr;
		Tcl_Release(job->interp);
	}
	return 1;
}

static int deleteEvent(Tcl_Event* event, ClientData data)
{
	if (event->proc != eventProc) return 0;
	Event* e = reinterpret_cast<Event*>(event);
	if ((*e->job)->interp != data) return 0;
	delete e->job;
	return 1;
}

static void deleteInterp(ClientData, Tcl_Interp* ti)
{
	std::lock_guard<std::mutex> table(jobTable.mutex);
	for (auto i = jobTable.jobs.begin(); i != jobTable.jobs.end(); )
	{
		auto job = i->second;
		if (job->interp != ti) { ++i; continue; }
		{
			std::lock_guard<std::mutex> lock(job->mutex);
			job->dead = job->cancelled = true;
			job->changed.notify_all();
		}
		if (job->command) Tcl_DecrRefCount(job->command);
		job->command = nullptr;
		i = jobTable.jobs.erase(i);
	}
	Tcl_DeleteEvents(deleteEvent, ti);
}

static int closeTrace(ClientData, Tcl_Interp* ti, int, char const*, Tcl_Command command,
	int objc, Tcl_Obj* const objv[])
{
	if (objc != 2 || command != Tcl_FindCommand(ti, "::scidb::db::close", nullptr, TCL_GLOBAL_ONLY))
		return TCL_OK;
	char const* base = Tcl_GetString(objv[1]);
	std::lock_guard<std::mutex> table(jobTable.mutex);
	for (auto const& entry : jobTable.jobs)
	{
		auto job = entry.second;
		if (job->interp == ti && job->base == base)
		{
			std::lock_guard<std::mutex> lock(job->mutex);
			job->closed = true;
			job->changed.notify_all();
		}
	}
	return TCL_OK;
}

static int cmdVersion(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 1) { Tcl_WrongNumArgs(ti, 1, objv, ""); return TCL_ERROR; }
	setResult(cql6_version());
	return TCL_OK;
}

static int jobCommand(bool cancel, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2) { Tcl_WrongNumArgs(ti, 1, objv, "<job>"); return TCL_ERROR; }
	int id;
	if (Tcl_GetIntFromObj(ti, objv[1], &id) != TCL_OK) return TCL_ERROR;
	std::lock_guard<std::mutex> table(jobTable.mutex);
	auto i = jobTable.jobs.find(id);
	if (i == jobTable.jobs.end() || i->second->interp != ti)
	{
		setResult(cancel ? 0 : -1); return TCL_OK;
	}
	auto job = i->second;
	std::lock_guard<std::mutex> lock(job->mutex);
	if (cancel)
	{
		setResult(!job->done);
		if (!job->done) { job->cancelled = true; job->changed.notify_all(); }
	}
	else Tcl_SetObjResult(ti, Tcl_NewWideIntObj(job->done ? -1 : job->progress));
	return TCL_OK;
}

static int cmdProgress(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	return jobCommand(false, ti, objc, objv);
}

static int cmdCancel(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	return jobCommand(true, ti, objc, objv);
}

static int cmdSearch(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 4 || (objc - 4) % 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <script> ?-threads N? ?-variations 0|1? ?-max N? ?-pgn 0|1? ?-command CMD?");
		return TCL_ERROR;
	}
	auto job = std::make_shared<Job>();
	job->interp = ti;
	job->owner = Tcl_GetCurrentThread();
	job->base = Tcl_GetString(objv[1]);
	job->variant = tcl::game::variantFromObj(objc, objv, 2);
	job->script = Tcl_GetString(objv[3]);
	Tcl_Obj* command = nullptr;
	for (int i = 4; i < objc; i += 2)
	{
		char const* key = Tcl_GetString(objv[i]);
		if (!std::strcmp(key, "-command")) { command = objv[i + 1]; continue; }
		int value;
		if (Tcl_GetIntFromObj(ti, objv[i + 1], &value) != TCL_OK) return TCL_ERROR;
		if (!std::strcmp(key, "-threads") && value >= 0 && value <= 256) job->options.threads = value;
		else if (!std::strcmp(key, "-max") && value >= 0) job->options.max_matches = value;
		else if (!std::strcmp(key, "-variations") && (value == 0 || value == 1)) job->options.variations = value;
		else if (!std::strcmp(key, "-pgn") && (value == 0 || value == 1)) job->options.want_pgn = value;
		else { setResult(Tcl_ObjPrintf("invalid CQL 6 option %s or value", key)); return TCL_ERROR; }
	}
	if (command)
	{
		int length;
		if (Tcl_ListObjLength(ti, command, &length) != TCL_OK) return TCL_ERROR;
		if (!length) { setResult("CQL 6 callback must be a nonempty command prefix"); return TCL_ERROR; }
		job->async = true;
	}
	if (!scidb->contains(job->base.c_str(), job->variant))
	{
		setResult(Tcl_ObjPrintf("unknown database '%s'", job->base.c_str())); return TCL_ERROR;
	}
	Database const& db = scidb->cursor(job->base.c_str(), job->variant).database();
	job->identity = &db;
	job->count = db.countGames();
	{
		std::lock_guard<std::mutex> table(jobTable.mutex);
		// Reject a second search until completion has been delivered. This
		// also applies to synchronous searches and different interpreters.
		if (!jobTable.jobs.empty()) { setResult("CQL 6 engine busy"); return TCL_ERROR; }
		job->id = jobTable.next++;
		jobTable.jobs.emplace(job->id, job);
	}
	if (command) { job->command = command; Tcl_IncrRefCount(command); }
	std::thread worker;
	try { worker = std::thread(run, job); }
	catch (std::exception const& e)
	{
		std::lock_guard<std::mutex> table(jobTable.mutex);
		jobTable.jobs.erase(job->id);
		if (command) Tcl_DecrRefCount(command);
		setResult(e.what()); return TCL_ERROR;
	}
	if (job->async)
	{
		worker.detach();
		setResult(job->id);
		return TCL_OK;
	}
	// Synchronous form services only this job's snapshot requests, never
	// evaluates unrelated Tcl events and never calls Tcl from a worker.
	{
		std::unique_lock<std::mutex> lock(job->mutex);
		while (!job->done)
		{
			job->changed.wait(lock, [&] { return job->pending || job->done; });
			if (job->pending) { lock.unlock(); requestGame(job); lock.lock(); }
		}
	}
	worker.join();
	{
		std::lock_guard<std::mutex> table(jobTable.mutex);
		jobTable.jobs.erase(job->id);
	}
	if (job->closed || !job->error.empty())
	{
		setResult(job->closed ? "database closed" : job->error.c_str()); return TCL_ERROR;
	}
	setResult(resultDict(*job, false));
	return TCL_OK;
}

} // namespace

void tcl::cql6::init(Tcl_Interp* ti)
{
	createCommand(ti, "::scidb::cql6::version", cmdVersion);
	createCommand(ti, "::scidb::cql6::search", cmdSearch);
	createCommand(ti, "::scidb::cql6::progress", cmdProgress);
	createCommand(ti, "::scidb::cql6::cancel", cmdCancel);
	Tcl_CreateObjTrace(ti, 0, 0, closeTrace, nullptr, nullptr);
	Tcl_CallWhenDeleted(ti, deleteInterp, nullptr);
}

// vi:set ts=3 sw=3:
