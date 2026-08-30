#ifndef _tcl_media_resolve_included
#define _tcl_media_resolve_included

#include "sys_file.h"

#include <dirent.h>
#include <sys/stat.h>

#include "m_string.h"
#include "m_vector.h"

namespace tcl_media {

/// True when `path` names an existing, readable file.
inline bool
mediaFileExists(mstl::string const& path)
{
	struct stat st;
	return ::stat(sys::file::internalName(path), &st) == 0
		&& S_ISREG(st.st_mode);
}


/// Append every "X.html" folder under `dir` (direct children only) to
/// `out`. Non-recursive.
inline void
collectHtmlFolders(mstl::string const& dir, mstl::vector<mstl::string>& out)
{
	DIR* d = ::opendir(sys::file::internalName(dir));
	if (!d)
		return;

	struct dirent* e;

	while ((e = ::readdir(d)))
	{
		mstl::string name(e->d_name);

		if (name.empty() || name == "." || name == "..")
			continue;

		mstl::string::size_type len = name.size();

		if (len < 5 || name[len - 5] != '.' || name[len - 4] != 'h'
			|| name[len - 3] != 't' || name[len - 2] != 'm' || name[len - 1] != 'l')
			continue;

		mstl::string sub(dir + "/" + name);
		struct stat st;

		if (::stat(sys::file::internalName(sub), &st) == 0 && S_ISDIR(st.st_mode))
			out.push_back(sub);
	}

	::closedir(d);
}


/// The media folders of the ChessBase release that contains `database`:
/// the database's own "<DB>.html" folder first, then every "X.html"
/// folder found in its directory, then the ones from up to two parent
/// directories — a CBM release keeps the .cbh databases under a
/// subfolder (e.g. "Data Collect/") while the media folders sit at the
/// release root. Priority order = out order.
inline void
collectMediaFolders(mstl::string const& database, mstl::vector<mstl::string>& out)
{
	mstl::string base(database);
	mstl::string::size_type dot = base.rfind('.');

	if (dot != mstl::string::npos)
		base.resize(dot);

	// 1) the database's own media folder
	out.push_back(base + ".html");

	mstl::string dir = base;

	for (int level = 0; level < 3; ++level)
	{
		mstl::string::size_type slash = dir.rfind('/');
		if (slash == mstl::string::npos)
			break;
		dir.resize(slash == 0 ? 1 : slash);
		collectHtmlFolders(dir, out);
	}
}


/// Resolve a media reference (`filename` from a .cbm/.cms manifest) to an
/// existing file: the database's own "<DB>.html" folder wins; the other
/// media folders of the ChessBase release are then tried in order. When
/// the file exists nowhere the primary candidate is returned unchanged,
/// preserving the previous "absent media" reporting behaviour.
inline mstl::string
resolveMediaFilename(mstl::string const& database, mstl::string const& filename)
{
	mstl::vector<mstl::string> folders;
	collectMediaFolders(database, folders);

	if (folders.empty())
	{
		mstl::string base(database);
		mstl::string::size_type dot = base.rfind('.');
		if (dot != mstl::string::npos)
			base.resize(dot);
		return base + ".html/" + filename;
	}

	mstl::string primary = folders[0] + "/" + filename;

	if (mediaFileExists(primary))
		return primary;

	for (unsigned i = 1; i < folders.size(); ++i)
	{
		mstl::string candidate = folders[i] + "/" + filename;

		if (mediaFileExists(candidate))
			return candidate;
	}

	return primary;
}

} // namespace tcl_media

#endif // _tcl_media_resolve_included

// vi:set ts=3 sw=3: