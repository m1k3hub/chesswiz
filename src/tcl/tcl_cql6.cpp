// CQL 6 host adapter. The engine and its callbacks never use Tcl objects.
#ifdef CQL6_STANDALONE
#include "../cql6stub/harness_fake.h"
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

#include <algorithm>
#include <condition_variable>
#include <chrono>
#include <deque>
#include <iterator>
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
	size_t bytes = 0;
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
			if (m.isNull()) record(3);
			else record(0, m.isCastling() ? m.castlingKingFrom() : m.from(),
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

// Queue bounds exclude the snapshots retained by active engine workers.
constexpr size_t PrefetchCapacity = 2048;
constexpr size_t PrefetchBytes = 16 * 1024 * 1024;
constexpr auto SliceTime = std::chrono::milliseconds(2);

struct Job
{
	int id = 0;
	Tcl_Interp* interp = nullptr; // used only on the owning Tcl thread
	Tcl_ThreadId owner;
	Tcl_Obj* command = nullptr; // main-thread reference, never read by workers
	std::string base, script;
	std::vector<std::string> additionalScripts;
	std::vector<const char*> scriptPointers;
	bool feedReady = false, feedVariations = false; // guarded by mutex until published
	variant::Type variant;
	unsigned count = 0, index = 0, skipped = 0;
	int sourceView = -1;
	std::vector<unsigned> candidateIndices;
	void const* identity = nullptr;
	cql6_options options = {};
	cql6_result result = {};
	std::mutex mutex;
	std::condition_variable changed;
	bool cancelled = false, closed = false, dead = false, done = false;
	bool async = false;
	bool compact = false; // -compact 1: matches as a flat {game first_ply ...} list ({game first_ply script ...} with -scripts)
	bool paged = false;   // -paged 1: matches stay here, read by ::scidb::cql6::matches
	// Timer fields are accessed only by the interpreter thread.
	Tcl_TimerToken timer = nullptr;
	std::shared_ptr<Job>* timerData = nullptr;
	long progress = 0;
	std::string error;
	std::deque<std::unique_ptr<Snapshot>> ready;
	size_t readyBytes = 0;
	bool eof = false, waitRoom = false;
	// Engine callbacks are serialized; each thread retains its last snapshot.
	std::vector<std::unique_ptr<Snapshot>> retained = std::vector<std::unique_ptr<Snapshot>>(256);
	std::deque<std::unique_ptr<Snapshot>> recycled;
	~Job() { cql6_free_result(&result); }
};

// The sole mutable global: the table also owns its mutex and id allocator.
struct JobTable
{
	std::mutex mutex;
	std::map<int, std::shared_ptr<Job>> jobs;
	std::map<int, std::shared_ptr<Job>> results; // paged results until released
	int next = 1;
	unsigned engines = 0;
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

// Database::exportGame mutates the shared codec, so ONLY the owning Tcl
// thread resolves the database and decodes snapshots. Workers touch owned
// C++ data only, retaining their last snapshot until their next callback.
// Close traces wake workers immediately; each slice also checks identity.
// A slice yields after 2ms (one indivisible decode can exceed that budget).
// Prefetch is bounded by both count and estimated owned allocation bytes.
// One oversized game is allowed in an otherwise empty queue to make progress;
// the count bound still holds. An indivisible decode also needs its own memory.
static size_t snapshotBytes(Snapshot const& s)
{
	size_t bytes = sizeof(s) + s.fen.capacity();
	bytes += s.strings.capacity() * sizeof(s.strings[0]);
	for (auto const& tag : s.strings) bytes += tag.first.capacity() + tag.second.capacity();
	bytes += s.comments.capacity() * sizeof(std::string);
	for (auto const& comment : s.comments) bytes += comment.capacity();
	return bytes + s.tags.capacity() * sizeof(cql6_tag) + s.moves.capacity() * sizeof(cql6_move);
}

static bool running(Job const& job)
{
	return !job.cancelled && !job.closed && !job.dead && !job.done && !job.eof;
}

static void requestGame(std::shared_ptr<Job> const& job)
{
	auto deadline = std::chrono::steady_clock::now() + SliceTime;
	size_t slots, bytes;
	std::deque<std::unique_ptr<Snapshot>> recycled;
	{
		std::lock_guard<std::mutex> lock(job->mutex);
		if (!running(*job) || !job->feedReady) return;
		slots = PrefetchCapacity - job->ready.size();
		bytes = job->readyBytes;
		recycled.swap(job->recycled);
	}
	if (!scidb->contains(job->base.c_str(), job->variant)
		|| &scidb->cursor(job->base.c_str(), job->variant).database() != job->identity)
	{
		std::lock_guard<std::mutex> lock(job->mutex);
		job->closed = true;
		job->ready.clear();
		job->readyBytes = 0;
		job->changed.notify_all();
		return;
	}
	// Publish a slice as a batch: no per-game mutex round trips or wakeups.
	// No Tcl evaluation occurs while decoding, so close/cancel cannot reenter.
	std::deque<std::unique_ptr<Snapshot>> batch;
	size_t addedBytes = 0;
	std::string error;
	bool waitRoom = false;
	while (batch.size() < slots && bytes + addedBytes < PrefetchBytes && job->index < job->count)
	{
		unsigned index = job->index++;
		if (job->sourceView >= 0) index = job->candidateIndices[index];
		std::unique_ptr<Snapshot> data;
		try
		{
			Database const& db = scidb->cursor(job->base.c_str(), job->variant).database();
			if (index < db.countGames())
			{
				if (recycled.empty()) data = std::make_unique<Snapshot>();
				else
				{
					data = std::move(recycled.front());
					recycled.pop_front();
					data->fen.clear(); data->strings.clear(); data->comments.clear();
					data->tags.clear(); data->moves.clear();
				}
				data->number = int(index);
#ifdef CQL6_STANDALONE
				bool exported = db.snapshot(index, *data);
#else
				Exporter consumer(*data, job->variant, job->feedVariations);
				bool exported = db.exportGame(index, consumer) == save::Ok;
#endif
				if (exported) { data->seal(); data->bytes = snapshotBytes(*data); }
				else data.reset();
			}
		}
		catch (mstl::exception const&) { data.reset(); }
		catch (std::exception const& e) { error = e.what(); break; }
		if (data)
		{
			if (bytes + addedBytes && data->bytes > PrefetchBytes - bytes - addedBytes)
			{
				// Retry this index when the queue drains; never drop or reorder it.
				--job->index;
				waitRoom = true;
				break;
			}
			addedBytes += data->bytes;
			batch.push_back(std::move(data));
		}
		else ++job->skipped;
		if (std::chrono::steady_clock::now() >= deadline) break;
	}
	std::lock_guard<std::mutex> lock(job->mutex);
	if (!error.empty()) { job->error = error; job->cancelled = true; }
	if (running(*job))
	{
		for (auto& data : batch) job->ready.push_back(std::move(data));
		job->readyBytes += addedBytes;
		job->waitRoom = waitRoom;
		if (job->index >= job->count) job->eof = true;
	}
	job->changed.notify_all();
}

static void stopTimer(Job& job)
{
	if (job.timer) Tcl_DeleteTimerHandler(job.timer);
	job.timer = nullptr;
	delete job.timerData;
	job.timerData = nullptr;
}

static void prefetchTimer(ClientData);
static void scheduleSlice(std::shared_ptr<Job> const& job)
{
	std::lock_guard<std::mutex> lock(job->mutex);
	if (!running(*job) || job->timer) return;
	// Above the low-water mark, poll gently. Below it, a zero-delay timer
	// gives already-due timers and GUI events a turn before the next slice.
	int delay = job->feedReady && !job->waitRoom && job->ready.size() < PrefetchCapacity / 2
		&& job->readyBytes < PrefetchBytes / 2 ? 0 : 1;
	job->timerData = new std::shared_ptr<Job>(job);
	job->timer = Tcl_CreateTimerHandler(delay, prefetchTimer, job->timerData);
}

static void prefetchTimer(ClientData data)
{
	auto ptr = static_cast<std::shared_ptr<Job>*>(data);
	auto job = *ptr;
	delete ptr;
	job->timer = nullptr;
	job->timerData = nullptr;
	bool fill;
	{
		std::lock_guard<std::mutex> lock(job->mutex);
		fill = running(*job) && (job->waitRoom ? job->ready.empty()
			: job->ready.size() < PrefetchCapacity / 2 && job->readyBytes < PrefetchBytes / 2);
	}
	if (fill) requestGame(job);
	scheduleSlice(job);
}

static int nextGame(void* ctx, int thread, cql6_game* g)
{
	// The cql6_search context owns the job until all callbacks have returned.
	auto job = static_cast<std::shared_ptr<Job>*>(ctx)->get();
	std::unique_lock<std::mutex> lock(job->mutex);
	job->changed.wait(lock, [&] {
		return !job->ready.empty() || job->eof || job->cancelled || job->closed || job->dead;
	});
	if (job->cancelled || job->closed || job->dead || job->ready.empty()) return 0;
	size_t oldBytes = job->readyBytes;
	auto data = std::move(job->ready.front());
	job->ready.pop_front();
	job->readyBytes -= data->bytes;
	if (size_t(thread) >= job->retained.size()) job->retained.resize(size_t(thread) + 1);
	if (job->retained[thread]) job->recycled.push_back(std::move(job->retained[thread]));
	data->fill(*g);
	job->retained[thread] = std::move(data);
	++job->progress;
	if (job->ready.size() == PrefetchCapacity / 2 - 1 || job->ready.empty()
		|| (oldBytes >= PrefetchBytes / 2 && job->readyBytes < PrefetchBytes / 2))
		job->changed.notify_all();
	return 1;
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
		job->ready.clear();
		job->readyBytes = 0;
		job->retained.clear();
		job->recycled.clear();
		job->changed.notify_all();
	}
	std::lock_guard<std::mutex> table(jobTable.mutex);
	--jobTable.engines;
}

static void prepareFeed(void* ctx, int variations)
{
	auto job = *static_cast<std::shared_ptr<Job>*>(ctx);
	std::lock_guard<std::mutex> lock(job->mutex);
	job->feedVariations = variations != 0;
	job->feedReady = true;
	job->changed.notify_all();
}

static void run(std::shared_ptr<Job> job)
{
	if (!job->async) { searchEngine(job); return; }
	// Only this coordinator uses Tcl thread event APIs; the engine and its
	// callbacks never call Tcl. Prefetch timers live on the owner thread.
	try
	{
		std::thread engine(searchEngine, job);
		engine.join();
	}
	catch (std::exception const& e)
	{
		{
			std::lock_guard<std::mutex> lock(job->mutex);
			job->error = e.what();
			job->done = true;
			job->changed.notify_all();
		}
		std::lock_guard<std::mutex> table(jobTable.mutex);
		--jobTable.engines;
	}
	queue(job, true);
}

static void put(Tcl_Interp* ti, Tcl_Obj* dict, char const* key, Tcl_Obj* value)
{
	Tcl_DictObjPut(ti, dict, Tcl_NewStringObj(key, -1), value);
}

static void retainResult(std::shared_ptr<Job> const& job)
{
	if (!job->paged || job->closed || !job->error.empty()) return;
	{
		// keep only the matches: the engine has finished with the snapshots
		std::lock_guard<std::mutex> lock(job->mutex);
		for (auto& snapshot : job->retained) snapshot.reset();
		job->ready.clear();
		job->recycled.clear();
		job->readyBytes = 0;
	}
	std::lock_guard<std::mutex> table(jobTable.mutex);
	jobTable.results[job->id] = job;
}

static Tcl_Obj* resultDict(Job const& job, bool async)
{
	Tcl_Interp* ti = job.interp;
	Tcl_Obj* dict = Tcl_NewDictObj();
	std::string error = job.closed ? "database closed" : job.error;
	if (async) put(ti, dict, "ok", Tcl_NewBooleanObj(error.empty()));
	if (!error.empty()) { put(ti, dict, "error", Tcl_NewStringObj(error.c_str(), -1)); return dict; }
	if (job.paged)
	{
		// Creating and later freeing a million Tcl objects stalls the GUI
		// either way: the caller pages through the retained array instead.
		put(ti, dict, "count", Tcl_NewIntObj(job.result.nmatches));
		put(ti, dict, "results", Tcl_NewIntObj(job.id));
	}
	else
	{
		// This runs on the main thread: a million matches must not cost a million
		// dictionaries plus fresh key strings, so build the list in one allocation.
		Tcl_Obj* matches;
		if (job.compact)
		{
			// with -scripts each match is a triple {game first_ply script}
			bool triples = !job.additionalScripts.empty();
			std::vector<Tcl_Obj*> items;
			items.reserve(std::size_t(job.result.nmatches) * (triples ? 3 : 2));
			for (int i = 0; i < job.result.nmatches; ++i)
			{
				items.push_back(Tcl_NewIntObj(job.result.matches[i].game_number));
				items.push_back(Tcl_NewIntObj(job.result.matches[i].first_ply));
				if (triples) items.push_back(Tcl_NewIntObj(job.result.matches[i].script_index));
			}
			matches = Tcl_NewListObj(int(items.size()), items.data());
		}
		else
		{
			Tcl_Obj* keys[4] = { Tcl_NewStringObj("game", -1), Tcl_NewStringObj("first_ply", -1),
				Tcl_NewStringObj("script", -1), Tcl_NewStringObj("pgn", -1) };
			for (Tcl_Obj* key : keys) Tcl_IncrRefCount(key);
			std::vector<Tcl_Obj*> items;
			items.reserve(job.result.nmatches);
			for (int i = 0; i < job.result.nmatches; ++i)
			{
				cql6_match const& m = job.result.matches[i];
				Tcl_Obj* match = Tcl_NewDictObj();
				Tcl_DictObjPut(ti, match, keys[0], Tcl_NewIntObj(m.game_number));
				Tcl_DictObjPut(ti, match, keys[1], Tcl_NewIntObj(m.first_ply));
				if (!job.additionalScripts.empty()) Tcl_DictObjPut(ti, match, keys[2], Tcl_NewIntObj(m.script_index));
				if (job.options.want_pgn) Tcl_DictObjPut(ti, match, keys[3], Tcl_NewStringObj(m.pgn ? m.pgn : "", -1));
				items.push_back(match);
			}
			matches = Tcl_NewListObj(int(items.size()), items.data());
			for (Tcl_Obj* key : keys) Tcl_DecrRefCount(key);
		}
		put(ti, dict, "matches", matches);
	}
	put(ti, dict, "games", Tcl_NewWideIntObj(job.result.ngames));
	put(ti, dict, "threads", Tcl_NewIntObj(job.result.threads_used));
	put(ti, dict, "truncated", Tcl_NewWideIntObj(job.result.ntruncated));
	put(ti, dict, "cancelled", Tcl_NewBooleanObj(job.cancelled));
	std::string messages = job.result.messages ? job.result.messages : "";
	if (job.result.ntruncated) {
		if (!messages.empty()) messages += '\n';
		messages += "illegal moves truncated to legal prefixes: " + std::to_string(job.result.ntruncated);
	}
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
	if (!e->completion) { requestGame(job); scheduleSlice(job); return 1; }
	stopTimer(*job);
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
		retainResult(job);
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
			job->ready.clear();
			job->recycled.clear();
			job->readyBytes = 0;
			job->changed.notify_all();
		}
		stopTimer(*job);
		if (job->command) Tcl_DecrRefCount(job->command);
		job->command = nullptr;
		i = jobTable.jobs.erase(i);
	}
	for (auto i = jobTable.results.begin(); i != jobTable.results.end(); )
		i = i->second->interp == ti ? jobTable.results.erase(i) : std::next(i);
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
			job->ready.clear();
			job->recycled.clear();
			job->readyBytes = 0;
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
		if (!job->done) { job->cancelled = true; job->ready.clear(); job->recycled.clear(); job->readyBytes = 0; job->changed.notify_all(); }
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

// ::scidb::cql6::matches <results> <first> <count>: flat {game first_ply ...}
static int cmdMatches(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 4) { Tcl_WrongNumArgs(ti, 1, objv, "<results> <first> <count>"); return TCL_ERROR; }
	int id, first, count;
	if (Tcl_GetIntFromObj(ti, objv[1], &id) != TCL_OK
		|| Tcl_GetIntFromObj(ti, objv[2], &first) != TCL_OK
		|| Tcl_GetIntFromObj(ti, objv[3], &count) != TCL_OK)
		return TCL_ERROR;
	std::shared_ptr<Job> job;
	{
		std::lock_guard<std::mutex> table(jobTable.mutex);
		auto i = jobTable.results.find(id);
		if (i != jobTable.results.end() && i->second->interp == ti) job = i->second;
	}
	if (!job) { setResult(Tcl_ObjPrintf("unknown CQL 6 results %d", id)); return TCL_ERROR; }
	int n = job->result.nmatches;
	first = std::max(0, std::min(first, n));
	int last = count < 0 ? first : int(std::min<long>(n, long(first) + count));
	std::vector<Tcl_Obj*> items;
	items.reserve(std::size_t(last - first) * 2);
	for (int i = first; i < last; ++i)
	{
		items.push_back(Tcl_NewIntObj(job->result.matches[i].game_number));
		items.push_back(Tcl_NewIntObj(job->result.matches[i].first_ply));
	}
	Tcl_SetObjResult(ti, Tcl_NewListObj(int(items.size()), items.data()));
	return TCL_OK;
}

// ::scidb::cql6::release <results>: 1 if the results were retained
static int cmdRelease(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc != 2) { Tcl_WrongNumArgs(ti, 1, objv, "<results>"); return TCL_ERROR; }
	int id;
	if (Tcl_GetIntFromObj(ti, objv[1], &id) != TCL_OK) return TCL_ERROR;
	std::shared_ptr<Job> job; // destroyed after the table lock is released
	{
		std::lock_guard<std::mutex> table(jobTable.mutex);
		auto i = jobTable.results.find(id);
		if (i != jobTable.results.end() && i->second->interp == ti) { job = i->second; jobTable.results.erase(i); }
	}
	Tcl_SetObjResult(ti, Tcl_NewBooleanObj(bool(job)));
	return TCL_OK;
}

static int cmdSearch(ClientData, Tcl_Interp* ti, int objc, Tcl_Obj* const objv[])
{
	if (objc < 4 || (objc - 4) % 2)
	{
		Tcl_WrongNumArgs(ti, 1, objv, "<database> <variant> <script> ?-scripts LIST? ?-threads N? ?-variations 0|1? ?-max N? ?-pgn 0|1? ?-compact 0|1? ?-paged 0|1? ?-command CMD?");
		return TCL_ERROR;
	}
	auto job = std::make_shared<Job>();
	job->interp = ti;
	job->owner = Tcl_GetCurrentThread();
	job->base = Tcl_GetString(objv[1]);
	job->variant = tcl::game::variantFromObj(objc, objv, 2);
	job->script = Tcl_GetString(objv[3]);
	// Native databases may contain imported illegal moves. Codec decoding alone
	// does not establish legality, so retain validation at this boundary.
	job->options.trusted_moves = 0;
	job->options.lazy_features = 1;
	job->options.truncate_illegal_moves = 1; // official PGN-reader semantics for imported native games
	job->options.prepare_feed = prepareFeed;
	Tcl_Obj* command = nullptr;
	for (int i = 4; i < objc; i += 2)
	{
		char const* key = Tcl_GetString(objv[i]);
		if (!std::strcmp(key, "-command")) { command = objv[i + 1]; continue; }
		if (!std::strcmp(key, "-scripts"))
		{
			int count; Tcl_Obj** scripts;
			if (Tcl_ListObjGetElements(ti, objv[i + 1], &count, &scripts) != TCL_OK) return TCL_ERROR;
			if (count > 1023) { setResult("CQL 6 accepts at most 1023 additional scripts"); return TCL_ERROR; }
			job->additionalScripts.clear();
			for (int s = 0; s < count; ++s) job->additionalScripts.emplace_back(Tcl_GetString(scripts[s]));
			continue;
		}
		int value;
		if (Tcl_GetIntFromObj(ti, objv[i + 1], &value) != TCL_OK) return TCL_ERROR;
		if (!std::strcmp(key, "-threads") && value >= 0 && value <= 256) job->options.threads = value;
		else if (!std::strcmp(key, "-max") && value >= 0) job->options.max_matches = value;
		else if (!std::strcmp(key, "-view") && value >= 0) job->sourceView = value;
		else if (!std::strcmp(key, "-variations") && (value == 0 || value == 1)) job->options.variations = value;
		else if (!std::strcmp(key, "-pgn") && (value == 0 || value == 1)) job->options.want_pgn = value;
		else if (!std::strcmp(key, "-compact") && (value == 0 || value == 1)) job->compact = value;
		else if (!std::strcmp(key, "-paged") && (value == 0 || value == 1)) job->paged = value;
		else { setResult(Tcl_ObjPrintf("invalid CQL 6 option %s or value", key)); return TCL_ERROR; }
	}
	for (auto const& script : job->additionalScripts) job->scriptPointers.push_back(script.c_str());
	job->options.additional_script_count = int(job->scriptPointers.size());
	job->options.additional_scripts = job->scriptPointers.data();
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
	if (job->sourceView >= 0)
	{
#ifdef CQL6_STANDALONE
		setResult("views are unavailable in the stub host"); return TCL_ERROR;
#else
		::app::Cursor& cursor = scidb->cursor(job->base.c_str(), job->variant);
		if (!cursor.isValidView(job->sourceView) || !cursor.isViewOpen(job->sourceView))
		{ setResult("invalid CQL 6 source view"); return TCL_ERROR; }
		if (!cursor.view(job->sourceView).isUsed(table::Games))
		{ setResult("CQL 6 source view does not contain games"); return TCL_ERROR; }
		Filter const& filter = cursor.view(job->sourceView).filter(table::Games);
		for (int index = filter.next(); index >= 0; index = filter.next(index))
			job->candidateIndices.push_back(unsigned(index));
		job->count = unsigned(job->candidateIndices.size());
#endif
	}
	{
		std::lock_guard<std::mutex> table(jobTable.mutex);
		// Reject a second search until completion has been delivered. This
		// also applies to synchronous searches and different interpreters.
		if (!jobTable.jobs.empty() || jobTable.engines) { setResult("CQL 6 engine busy"); return TCL_ERROR; }
		job->id = jobTable.next++;
		jobTable.jobs.emplace(job->id, job);
		++jobTable.engines;
	}
	if (command) { job->command = command; Tcl_IncrRefCount(command); }
	std::thread worker;
	try { worker = std::thread(run, job); }
	catch (std::exception const& e)
	{
		std::lock_guard<std::mutex> table(jobTable.mutex);
		jobTable.jobs.erase(job->id);
		--jobTable.engines;
		if (command) Tcl_DecrRefCount(command);
		setResult(e.what()); return TCL_ERROR;
	}
	if (job->async)
	{
		queue(job, false);
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
			job->changed.wait(lock, [&] { return job->done || (job->feedReady && !job->eof
				&& (job->waitRoom ? job->ready.empty() : job->ready.size() < PrefetchCapacity / 2
				&& job->readyBytes < PrefetchBytes / 2)); });
			if (!job->done) { lock.unlock(); requestGame(job); lock.lock(); }
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
	retainResult(job);
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
	createCommand(ti, "::scidb::cql6::matches", cmdMatches);
	createCommand(ti, "::scidb::cql6::release", cmdRelease);
	Tcl_CreateObjTrace(ti, 0, 0, closeTrace, nullptr, nullptr);
	Tcl_CallWhenDeleted(ti, deleteInterp, nullptr);
}

// vi:set ts=3 sw=3:
