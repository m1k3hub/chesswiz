// ======================================================================
// Shared database maintenance helpers.
// ======================================================================

#ifndef _db_maintenance_included
#define _db_maintenance_included

#include "db_common.h"

#include "m_string.h"
#include "m_vector.h"

namespace db {

class Database;

namespace maintenance {

struct EcoStats
{
	EcoStats();

	mstl::string eco;
	unsigned total;
	unsigned white;
	unsigned draws;
	unsigned black;
};

typedef mstl::vector<unsigned> DuplicateGroup;
typedef mstl::vector<DuplicateGroup> DuplicateGroups;
typedef mstl::vector<EcoStats> EcoStatsList;

enum DuplicateMode { Exact, Normalized };

DuplicateGroups findDuplicates(Database& db, DuplicateMode mode = Exact);
EcoStatsList computeEcoStats(Database const& db, variant::Type variant);

} // namespace maintenance
} // namespace db

#endif // _db_maintenance_included
