// Test-only engine. No Tcl, database, or application dependencies.
#include "../cql6/cql6_api.h"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <memory>
#include <sstream>
#include <thread>
#include <vector>

extern "C" const char* cql6_version() { return "cql6 stub 6.2"; }

extern "C" void cql6_free_result(cql6_result* r)
{
	for (int i = 0; i < r->nmatches; ++i) std::free(r->matches[i].pgn);
	std::free(r->matches);
	std::free(r->messages);
	*r = {};
}

static std::string oneLine(char const* text)
{
	std::string out;
	for (; *text; ++text)
	{
		if (*text == '\n') out += "\\n";
		else if (*text == '\r') out += "\\r";
		else if (*text == '\\') out += "\\\\";
		else out += *text;
	}
	return out;
}

static std::string dump(cql6_game const& g)
{
	std::ostringstream s;
	s << "number=" << g.number << " fen=" << oneLine(g.fen ? g.fen : "-")
	  << " ntags=" << g.ntags << " tags=";
	for (int i = 0; i < g.ntags; ++i)
	{
		if (i) s << ',';
		s << oneLine(g.tags[i].name) << ':' << oneLine(g.tags[i].value);
	}
	s << " moves=";
	for (int i = 0; i < g.nmoves; ++i)
	{
		if (i) s << ',';
		cql6_move const& m = g.moves[i];
		if (m.kind == 1) s << '(';
		else if (m.kind == 2) s << ')';
		else
		{
			s << m.from << '-' << m.to;
			if (m.promo) s << char(m.promo);
		}
		if (m.comment) s << '{' << oneLine(m.comment) << '}';
	}
	return s.str();
}

extern "C" int cql6_search(const char* script, const cql6_options* opt,
	cql6_next_fn next, void* ctx, cql6_result* out, char* err, size_t errlen)
{
	*out = {};
	if (errlen) err[0] = 0;
	if (!std::strcmp(script, "ERROR"))
	{
		std::snprintf(err, errlen, "stub error");
		return 1;
	}
	int threads = opt->threads ? opt->threads : 4;
	if (threads < 1 || threads > 256 || opt->max_matches < 0)
	{
		std::snprintf(err, errlen, "invalid stub options");
		return 1;
	}
	// All state is per invocation; the host enforces the one-search rule.
	if (opt->prepare_feed) opt->prepare_feed(ctx,opt->variations);
	std::mutex feed, results;
	std::vector<cql6_match> matches;
	long games = 0;
	int reserved = 0;
	bool eof = false;
	char failure[256] = {};
	std::vector<std::thread> workers;
	try
	{
		for (int t = 0; t < threads; ++t) workers.emplace_back([&, t] {
			try
			{
			for (;;)
			{
				cql6_game g = {};
				bool hit;
				{
					std::lock_guard<std::mutex> lock(feed);
					if (eof || (opt->max_matches && reserved >= opt->max_matches)) break;
					if (!next(ctx, t, &g)) { eof = true; break; }
					++games;
					hit = !std::strcmp(script, "MATCH_ALL") || !std::strcmp(script, "DUMP")
						|| !std::strcmp(script, "SLOW")
						|| (!std::strcmp(script, "MATCH_EVEN") && g.number % 2 == 0);
					if (hit) ++reserved;
				}
				if (opt->test_hook) opt->test_hook(g.number, t);
				if (!std::strcmp(script, "SLOW"))
					std::this_thread::sleep_for(std::chrono::milliseconds(5));
				if (hit)
				{
					std::unique_ptr<char, decltype(&std::free)> pgn(nullptr, std::free);
					if (opt->want_pgn)
					{
						std::string text = !std::strcmp(script, "DUMP") ? dump(g) : "stub match";
						pgn.reset(::strdup(text.c_str()));
						if (!pgn) throw std::bad_alloc();
					}
					std::lock_guard<std::mutex> lock(results);
					matches.push_back({g.number, !std::strcmp(script, "MATCH_EVEN") ? g.number % 7 : 0, pgn.get()});
					pgn.release();
				}
			}
			}
			catch (std::exception const& e)
			{
				std::lock_guard<std::mutex> lock(feed);
				eof = true;
				std::snprintf(failure, sizeof(failure), "%s", e.what());
			}
			catch (...)
			{
				std::lock_guard<std::mutex> lock(feed);
				eof = true;
				std::snprintf(failure, sizeof(failure), "stub callback exception");
			}
		});
	}
	catch (std::exception const& e)
	{
		{ std::lock_guard<std::mutex> lock(feed); eof = true; }
		for (auto& w : workers) w.join();
		for (auto& m : matches) std::free(m.pgn);
		std::snprintf(err, errlen, "%s", e.what());
		return 1;
	}
	for (auto& w : workers) w.join();
	if (failure[0])
	{
		for (auto& m : matches) std::free(m.pgn);
		std::snprintf(err, errlen, "%s", failure);
		return 1;
	}
	std::sort(matches.begin(), matches.end(), [](cql6_match const& a, cql6_match const& b) {
		return a.game_number < b.game_number;
	});
	out->nmatches = int(matches.size());
	out->matches = static_cast<cql6_match*>(std::calloc(matches.size(), sizeof(cql6_match)));
	if (!matches.empty() && !out->matches)
	{
		for (auto& m : matches) std::free(m.pgn);
		*out = {};
		std::snprintf(err, errlen, "out of memory");
		return 1;
	}
	std::copy(matches.begin(), matches.end(), out->matches);
	out->ngames = games;
	out->threads_used = threads;
	return 0;
}

// vi:set ts=3 sw=3:
