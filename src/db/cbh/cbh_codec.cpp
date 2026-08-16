// ======================================================================
// Author : $Author$
// Version: $Revision: 1383 $
// Date   : $Date: 2017-08-06 13:18:29 -0400 (Sun, 06 Aug 2017) $
// Url    : $URL$
// ======================================================================

// ======================================================================
//    _/|            __
//   // o\         /    )           ,        /    /
//   || ._)    ----\---------__----------__-/----/__-
//   //__\          \      /   '  /    /   /    /   )
//   )___(     _(____/____(___ __/____(___/____(___/_
// ======================================================================

// ======================================================================
// Copyright: (C) 2009-2017 Gregor Cramer
// ======================================================================

// ======================================================================
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
// ======================================================================

// ChessBase format description:
// http://talkchess.com/forum/viewtopic.php?t=29468&highlight=cbh
// http://talkchess.com/forum/viewtopic.php?topic_view=threads&p=287896&t=29468&sid=a535ba2e9a17395e2582bdddf57c2425

// Required files:	.cba .cbc .cbg .cbh .cbp .cbt
// Used files:			.cba .cbc .cbg .cbh .cbp .cbt .cbs .cbe .cbj .ini .html/*

#include "cbh_codec.h"
#include "cbh_consumer.h"
#include "cbh_decoder.h"
#include "cbh_game_decoder.h"

#include "db_reader.h"
#include "db_game_data.h"
#include "db_exception.h"

#include "u_progress.h"
#include "u_byte_stream.h"
#include "u_misc.h"

#include "sys_file.h"
#include "sys_utf8.h"
#include "sys_utf8_codec.h"
#include "sys_lock.h"

#include "m_limits.h"
#include "m_string.h"
#include "m_byte_order.h"
#include "m_vector.h"
#include "m_stdio.h"
#include "m_bitfield.h"

#include <string.h>
#include <ctype.h>
#include <stdlib.h>
#include <limits.h>

using namespace db;
using namespace db::cbh;
using namespace db::country;
using namespace db::type;
using namespace util;


enum { Deleted = -999 };


static db::tag::TagSet m_infoTags;

namespace {

uint32_t
findPlayerRecordIndex(Namebase const& base, NamebasePlayer const* player)
{
	if (player == 0)
		return 0;

	for (unsigned i = 0; i < base.size(); ++i)
	{
		if (base.playerAt(i) == player)
			return i;
	}

	return 0;
}


uint32_t
findEventRecordIndex(Namebase const& base, NamebaseEvent const* event)
{
	if (event == 0)
		return 0;

	for (unsigned i = 0; i < base.size(); ++i)
	{
		if (base.eventAt(i) == event)
			return i;
	}

	return 0;
}


uint32_t
findAnnotatorRecordIndex(Namebase const& base, NamebaseEntry const* annotator)
{
	if (annotator == 0)
		return 0;

	for (unsigned i = 0; i < base.size(); ++i)
	{
		if (base.entryAt(i) == annotator)
			return i;
	}

	return 0;
}

} // namespace

static country::Code NationMap[] =
{
	Unknown,										//   0
	Afghanistan,								//   1 AFG
	Albania,										//   2 ALB
	Algeria,										//   3 ALG
	Angola,										//   4 ANG
	Andorra,										//   5 AND
	Antigua,										//   6 ANT
	Argentina,									//   7 ARG
	Armenia,										//   8 ARM
	Australia,									//   9 AUS
	Austria,										//  10 AUT
	Azerbaijan,									//  11 AZE
	Bahamas,										//  12 BAH
	Bahrain,										//  13 BHN
	Bangladesh,									//  14 BAN
	Barbados,									//  15 BAR
	Belarus,										//  16 BLR
	Belgium,										//  17 BEL
	Belize,										//  18 BLZ
	Bermuda,										//  19 BER
	Bolivia,										//  20 BOL
	Bosnia_and_Herzegovina,					//  21 BIH
	Botswana,									//  22 BOT
	Brazil,										//  23 BRA
	British_Virgin_Islands,					//  24 IVB
	Brunei,										//  25 BRU
	Bulgaria,									//  26 BUL
	Burkina_Faso,								//  27 BUR
	Canada,										//  28 CAN
	Chile,										//  29 CHI
	China,										//  30 CHN
	Colombia,									//  31 COL
	Costa_Rica,									//  32 CRI
	Croatia,										//  33 CRO
	Cuba,											//  34 CUB
	Cyprus,										//  35 CYP
	Czech_Republic,							//  36 CZE
	Denmark,										//  37 DEN
	Djibouti,									//  38 DJI
	Dominican_Republic,						//  39 DOM
	Ecuador,										//  40 ECU
	Egypt,										//  41 EGY
	England,										//  42 ENG
	Spain,										//  43 ESP
	Estonia,										//  44 EST
	Ethiopia,									//  45 ETH
	Faroe_Islands,								//  46 FAI
	Fiji,											//  47 FIJ
	Finland,										//  48 FIN
	France,										//  49 FRA
	Macedonia,									//  50 FRM
	Gambia,										//  51 GAM
	Georgia,										//  52 GEO
	Germany,										//  53 GER
	Ghana,										//  54 GHA
	Greece,										//  55 GRE
	Guatemala,									//  56 GUA
	Guernsey,									//  57 GCI
	Guyana,										//  58 GUY
	Haiti,										//  59 HAI
	Honduras,									//  60 HON
	Hong_Kong,									//  61 HKG
	Hungary,										//  62 HUN
	Iceland,										//  63 ISL
	India,										//  64 IND
	Indonesia,									//  65 INA
	Iran,											//  66 IRI
	Iraq,											//  67 IRQ
	Israel,										//  68 ISR
	Ireland,										//  69 IRL
	Italy,										//  70 ITA
	Ivory_Coast,								//  71 IVO
	Jamaica,										//  72 JAM
	Japan,										//  73 JPN
	Jersey,										//  74 JCI
	Jordan,										//  75 JOR
	Kazakhstan,									//  76 KAZ
	Kenya,										//  77 KEN
	South_Korea,								//  78 KOR
	Kyrgyzstan,									//  79 KGZ
	Kuwait,										//  80 KUW
	Latvia,										//  81 LAT
	Lebanon,										//  82 LBN
	Libya,										//  83 LBY
	Liechtenstein,								//  84 LIE
	Lithuania,									//  85 LTU
	Luxembourg,									//  86 LUX
	Macao,										//  87 MAC
	Madagascar,									//  88 MAD
	Malaysia,									//  89 MAS
	Mali,											//  90 MLI
	Malta,										//  91 MLT
	Mauritania,									//  92 MAU
	Mauritius,									//  93 MRI
	Mexico,										//  94 MEX
	Moldova,										//  95 MDA
	Monaco,										//  96 MNC
	Mongolia,									//  97 MGL
	Morocco,										//  98 MAR
	Mozambique,									//  99 MOZ
	Myanmar,										// 100 MYA
	Namibia,										// 101 NAM
	Nepal,										// 102 NEP
	Netherlands,								// 103 NED
	Netherlands_Antilles,					// 104 AHO
	New_Zealand,								// 105 NZL
	Nicaragua,									// 106 NCA
	Nigeria,										// 107 NGR
	Norway,										// 108 NOR
	Pakistan,									// 109 PAK
	Palestine,									// 110 PLE
	Panama,										// 111 PAN
	Papua_New_Guinea,							// 112 PNG
	Paraguay,									// 113 PAR
	Peru,											// 114 PER
	Philippines,								// 115 PHI
	Poland,										// 116 POL
	Portugal,									// 117 POR
	Puerto_Rico,								// 118 PUR
	Qatar,										// 119 QAT
	Romania,										// 120 ROM
	Russia,										// 121 RUS
	El_Salvador,								// 122 ESA
	San_Marino,									// 123 SMR
	Scotland,									// 124 SCO
	Senegal,										// 125 SEN
	Seychelles,									// 126 SEY
	Singapore,									// 127 SIN
	Slovakia,									// 128 SVK
	Slovenia,									// 129 SLO
	South_Africa,								// 130 RSA
	Sri_Lanka,									// 131 SRI
	Sudan,										// 132 SUD
	Suriname,									// 133 SUR
	Sweden,										// 134 SWE
	Switzerland,								// 135 SUI
	Syria,										// 136 SYR
	Tajikistan,									// 137 TJK
	Tanzania,									// 138 TAN
	Thailand,									// 139 THA
	Trinidad_and_Tobago,						// 140 TRI
	Tunisia,										// 141 TUN
	Turkey,										// 142 TUR
	Turkmenistan,								// 143 TKM
	Uganda,										// 144 UGA
	Ukraine,										// 145 UKR
	United_Arab_Emirates,					// 146 UAE
	United_States_of_America,				// 147 USA
	Uruguay,										// 148 URU
	Soviet_Union,								// 149 URS
	Uzbekistan,									// 150 UZB
	Venezuela,									// 151 VEN
	Vietnam,										// 152 VIE
	US_Virgin_Islands,						// 153 ISV
	Wales,										// 154 WLS
	Yemen,										// 155 YEM
	Yugoslavia,									// 156 YUG
	Zambia,										// 157 ZAM
	Zimbabwe,									// 158 ZIM
	DR_Congo,									// 159 ZRE
	East_Germany,								// 160 DDR
	Czechoslovakia,							// 161 CSR
	Cameroon,									// 162 CAM
	Chad,											// 163 CHD
	Cape_Verde,									// 164 KAP
	Kiribati,									// 165 KBA
	Comoros,										// 166 COM
	Congo,										// 167 CON
	North_Korea,								// 168 NKO
	Laos,											// 169 LAO
	Lesotho,										// 170 LES
	Malawi,										// 171 MWI
	Maldives,									// 172 MDV
	Marshall_Islands,							// 173 MSH
	Oman,											// 174 OMN
	Nauru,										// 175 NAU
	Micronesia,									// 176 MIC
	Niger,										// 177 NIG
	Saudi_Arabia,								// 178 SAU
	Togo,											// 179 TOG
	Tonga,										// 180 TON
	Vanuatu,										// 181 VAN
	Vatican,										// 182 VAT
	Tuvalu,										// 183 TUV
	Swaziland,									// 184 SWA
	Sierra_Leone,								// 185 SIE
	Saint_Lucia,								// 186 SLU
	Papua_New_Guinea,							// 187 PAP
	Saint_Vincent_and_the_Grenadines,	// 188 SVI
	Samoa,										// 189 SAM
	Saint_Kitts_and_Nevis,					// 190 SKI
	Solomon_Islands,							// 191 SAL
	Germany,										// 192 GE2 German Empire
	Russia,										// 193 ZAR Russian Empire
	Rwanda,										// 194 RWA
	Liberia,										// 195 LBR
	American_Samoa,							// 196 NET
	Chinese_Taipei,							// 197 TWN
	Anguilla,									// 198 ASU
	Aruba,										// 199 AGG
	Benin,										// 200 BNN
	Bhutan,										// 201 BTN
	Burundi,										// 202 BRI
	Cambodia,									// 203 CMB
	Cayman_Islands,							// 204 CAY
	Central_African_Republic,				// 205 CAR
	Great_Britain,								// 206 CIB Channel Islands
	Christmas_Island,							// 207 CIA
	Cocos_Islands,								// 208 COA
	Cook_Islands,								// 209 CIN
	Equatorial_Guinea,						// 210 ELG
	Eritrea,										// 211 ERI
	Falkland_Islands,							// 212 FGB
	French_Guiana,								// 213 FRG
	French_Polynesia,							// 214 FRP
	Gabon,										// 215 GAB
	Gibraltar,									// 216 GGB
	Grenada,										// 217 GRA
	Greenland,									// 218 GRL
	Guadeloupe,									// 219 FGA
	Guam,											// 220 GMA
	Guinea,										// 221 GUI
	Guinea_Bissau,								// 222 GUB
	Isle_of_Man,								// 223 IOM
	Jan_Mayen_and_Svalbard,					// 224 JMY Jan Mayen
	Martinique,									// 225 MFR
	Mayotte,										// 226 MYF
	Montserrat,									// 227 MSG
	New_Caledonia,								// 228 NCF
	Niue,											// 229 NNN
	Norfolk_Island,							// 230 NNA
	Northern_Mariana_Islands,				// 231 NMI
	Timor_Leste,								// 232 OTM
	Palau,										// 233 PAL
	Pitcairn_Islands,							// 234 PIG
	Reunion,										// 235 RUF
	Sao_Tome_and_Principe,					// 236 SAO
	Somalia,										// 237 SOM
	Jan_Mayen_and_Svalbard,					// 238 SVN Svalbard
	Saint_Helena,								// 239 HGB
	Saint_Pierre_and_Miquelon,				// 240 PGB
	Tokelau,										// 241 TKI
	Turks_and_Caicos_Islands,				// 242 TCI
	Wallis_and_Futuna,						// 243 WFR
	Northern_Ireland,							// 244 NIR
	Aboard_Spacecraft,						// 245 ISS
	Great_Britain,								// 246 GBR
	Germany,										// 247 SAA Saarland
	Montenegro,									// 248 MNT
	Serbia,										// 249 SER
	Catalonia,									// 250 CAT
	Basque,										// 251 BAS
	Kosovo,										// 252 KOS
};


static type::ID const TypeMap[] =
{
	Unspecific,					// Unspecific
	Work,							// Work
	My_Games,					// My games
	Large_Database,			// Large database
	Informant,					// Informant
	Openings,					// Openings
	Unspecific,					// Magazine/Express
	Tournament,					// Classical Tournament
	Tournament,					// Recent Tournament
	Correspondence_Chess,	// Correspondence
	Tactics,						// Tactics
	Analysis,					// Analysis
	Training,					// Training
	Endgames,					// Endings
	Studies,						// Studies
	Blitz_Games,				// Blitz
	Computer_Chess,			// Computer chess
	Problems,					// Problems
	Patzer,						// Patzer
	Gambit,						// Gambit
	Correspondence_Chess,	// BdF
	Match,						// Match
	Player_Collection,		// Biography
	Unspecific,					// Multimedia
	Important,					// Important
	Unspecific,					// Text
	Internet_Chess,			// Internet
	Email_Chess,				// E-Mail
	Openings,					// Opening book
	Unspecific,					// Chess Media
	Unspecific,					// Reference
	Unspecific,					// Repertoire
	Unspecific,					// Update
	Unspecific,					// Strategy
	Unspecific,					// Playchess
	Unspecific,					// Tutorial
	Unspecific,					// Elite Chess
	Jewels,						// Brilliance
	PlayerCollectionFemale,	// Woman Chess
	Unspecific,					// Junior Chess
	Unspecific,					// Simultaneous
	Tournament,					// Team Tournaments
};


static void
convPlayerName(mstl::string& str)
{
	for (unsigned i = 0; i < str.size(); ++i)
	{
		switch (Byte(str[i]))
		{
			case 0xa2: str[i] = 'K'; break;
			case 0xa3: str[i] = 'Q'; break;
			case 0xa4: str[i] = 'N'; break;
			case 0xa5: str[i] = 'B'; break;
			case 0xa6: str[i] = 'R'; break;
			case 0xa7: str[i] = 'P'; break;
		}
	}
}


inline
static unsigned
convertEco(unsigned code)
{
	code = (code >> 7) & 0x1ff;

	// Sometimes the ECO code is invalid. Either this is
	// an CB error, or an unknown "feature".
	return code <= 500 ? code : 0;
}


inline
static void
setDate(Date& result, uint32_t value)
{
	result.setYMD((value >> 9) & 4095, (value >> 5) & 15, value & 31);
}


static void
replaceNewlines(mstl::string& s)
{
	char const*	p = s.begin();
	char const*	e = s.end();
	char*			q = s.data();

	for ( ; p < e; ++p, ++q)
	{
		if (p[0] != '\r')
			*q = *p;
		else if (p[1] == '\n')
			*q = *++p;
		else
			*q = '\n';
	}

	s.resize(q - s.begin());
}


static unsigned
strippedLen(char const* s)
{
	unsigned len = strlen(s);

	while (len > 0 && ::isspace(s[len - 1]))
		--len;

	return len;
}


Codec::Tournament::Tournament() :category(0) ,rounds(0) {}
Codec::Tournament::Tournament(Byte cat, Byte nrounds) :category(cat) ,rounds(nrounds) {}


struct Codec::Source : public NamebaseEntry
{
	Source(mstl::string const& name, Date const& sourceDate);
	Date date;
};


Codec::Source::Source(mstl::string const& name, Date const& sourceDate)
	:NamebaseEntry(name)
	,date(sourceDate)
{
}


unsigned Codec::maxGameRecordLength() const	{ return 0x2fffffff - 1; }
unsigned Codec::maxGameCount() const			{ return (1u << 31)/46u; }
unsigned Codec::maxGameLength() const			{ return (1 << 16) - 1; }
unsigned Codec::maxPlayerCount() const			{ return (1 << 24) - 1; }
unsigned Codec::maxEventCount() const			{ return (1 << 24) - 1; }
unsigned Codec::maxSiteCount() const			{ return (1 << 24) - 1; }
unsigned Codec::maxAnnotatorCount() const		{ return (1 << 24) - 1; }
unsigned Codec::minYear() const					{ return 0; }
unsigned Codec::maxYear() const					{ return mstl::min(Date::MaxYear, uint16_t(4094)); }
unsigned Codec::maxDescriptionLength() const	{ return mstl::numeric_limits<uint32_t>::max() - 1; }
mstl::string const& Codec::defaultEncoding() const { return sys::utf8::Codec::windows(); }


unsigned
Codec::gameFlags() const
{
	return	GameInfo::Flag_Best_Game
			 | GameInfo::Flag_Decided_Tournament
			 | GameInfo::Flag_Model_Game
			 | GameInfo::Flag_Novelty
			 | GameInfo::Flag_Pawn_Structure
			 | GameInfo::Flag_Strategy
			 | GameInfo::Flag_Tactics
			 | GameInfo::Flag_With_Attack
			 | GameInfo::Flag_Sacrifice
			 | GameInfo::Flag_Defense
			 | GameInfo::Flag_Material
			 | GameInfo::Flag_Piece_Play
			 | GameInfo::Flag_End_Game
			 | GameInfo::Flag_Blunder
			 | GameInfo::Flag_User;
}


Codec::Codec()
	:m_codec(0)
	,m_teamRecords(0)
	,m_teamRecordSize(0)
	,m_encoding(::sys::utf8::Codec::windows())
	,m_allocator(32768)
	,m_sourceBase(Namebase::Annotator)
	,m_illegalEvent(0)
	,m_illegalPlayer(0)
	,m_numGames(0)
	,m_highQuality(false)
	,m_isWritable(false)
	,m_nextGameOffset(0)
	,m_nextAnnotationOffset(0)
{
	if (::m_infoTags.none())
	{
		::m_infoTags.set(tag::Event);
		::m_infoTags.set(tag::Site);
		::m_infoTags.set(tag::Date);
		::m_infoTags.set(tag::Round);
		::m_infoTags.set(tag::White);
		::m_infoTags.set(tag::Black);
		::m_infoTags.set(tag::Result);
		::m_infoTags.set(tag::Annotator);
		::m_infoTags.set(tag::Eco);
		::m_infoTags.set(tag::WhiteElo);
		::m_infoTags.set(tag::BlackElo);
		::m_infoTags.set(tag::EventDate);
		::m_infoTags.set(tag::EventCountry);
		::m_infoTags.set(tag::EventType);
		::m_infoTags.set(tag::Mode);
		::m_infoTags.set(tag::TimeMode);
	}
}


Codec::~Codec() throw()
{
	delete m_codec;

	for (unsigned i = 0; i < m_teamBase.size(); ++i)
		delete m_teamBase[i];

	BaseMap::container_type const& sourceList = m_sourceMap2.container();

	for (unsigned i = 0; i < sourceList.size(); ++i)
		delete sourceList[i].second;
}


bool
Codec::isWritable() const
{
	return m_isWritable;
}


bool
Codec::encodingFailed() const
{
	M_ASSERT(m_codec);
	return m_codec->failed();
}


Codec::Format
Codec::format() const
{
	return format::ChessBase;
}


mstl::string const&
Codec::encoding() const
{
	M_ASSERT(m_codec);
	return m_codec->encoding();
}


mstl::string const&
Codec::extension() const
{
	static mstl::string const Suffix("cbh");
	return Suffix;
}


void
Codec::Report(char const* charset)
{
	if (::sys::utf8::Codec::latin1() == charset)
		m_encoding.assign(::sys::utf8::Codec::windows());
	else if (::sys::utf8::Codec::ascii() != charset)
		m_encoding.assign(charset);
}


void
Codec::setEncoding(mstl::string const& encoding)
{
	if (m_codec == 0)
		m_codec = new ::sys::utf8::Codec(encoding);
	else
		m_codec->reset(encoding);
}


void
Codec::reset()
{
	// no action
}


void
Codec::toUtf8(mstl::string& str)
{
	m_codec->toUtf8(str);

	if (!sys::utf8::validate(str))
		m_codec->forceValidUtf8(str);
}


tag::TagSet
Codec::tagFilter(Section, TagSet const&) const
{
	return m_infoTags;
}


void
Codec::mapPlayerName(mstl::string& str)
{
	if (str.empty())
	{
		str = '?';
	}
	else
	{
		mstl::vector<unsigned> indices;

		for (unsigned i = 0; i < str.size(); ++i)
		{
			switch (Byte(str[i]))
			{
				case 0xa2: str[i] = 'K'; indices.push_back(i); break;
				case 0xa3: str[i] = 'Q'; indices.push_back(i); break;
				case 0xa4: str[i] = 'N'; indices.push_back(i); break;
				case 0xa5: str[i] = 'B'; indices.push_back(i); break;
				case 0xa6: str[i] = 'R'; indices.push_back(i); break;
				case 0xa7: str[i] = 'P'; indices.push_back(i); break;
			}
		}

		toUtf8(str);

		mstl::string piece;
		unsigned k = 0;

		for (unsigned i = 0; i < indices.size(); ++i)
		{
			switch (str[indices[i] + k])
			{
				case 'K': piece = piece::utf8::asString(piece::King  ); break;
				case 'Q': piece = piece::utf8::asString(piece::Queen ); break;
				case 'R': piece = piece::utf8::asString(piece::Rook  ); break;
				case 'B': piece = piece::utf8::asString(piece::Bishop); break;
				case 'N': piece = piece::utf8::asString(piece::Knight); break;
				case 'P': piece = piece::utf8::asString(piece::Pawn  ); break;
			}

			str.replace(indices[i] + k, 1, piece);
			k += piece.size() - 1;
		}
	}
}


void
Codec::close()
{
	if (m_gameStream.is_open())
		m_gameStream.close();
	if (m_annotationStream.is_open())
		m_annotationStream.close();
	if (m_indexStream.is_open())
		m_indexStream.close();
	if (m_namebaseStream.is_open())
		m_namebaseStream.close();
	if (m_teamStream.is_open())
		m_teamStream.close();
}


void
Codec::doOpen(	mstl::string const& rootname,
					mstl::string const& originalSuffix,
					mstl::string const& encoding,
					util::Progress& progress)
{
	M_ASSERT(originalSuffix == "cbh");

	ProgressWatcher watcher(progress, 0);

	setEncoding(encoding);
	setVariant(variant::Normal);

	m_numGames = readHeader(rootname);

	mstl::string filename(rootname + ".cbg");
	checkPermissions(filename);
	openFile(m_gameStream, filename, Readonly);

	if (!m_codec->hasEncoding())
	{
		preloadPlayerData(rootname, progress);
		preloadAnnotatorData(rootname, progress);
		preloadTournamentData(rootname, progress);
		DataEnd();

		if (m_encoding == sys::utf8::Codec::automatic())
			m_encoding = sys::utf8::Codec::windows(); // cannot be Latin-1
		m_codec->reset(m_encoding);
		useEncoding(m_encoding);
	}

	progress.message("read-init");

	readIniData(rootname);
	readSourceData(rootname, progress);
	readPlayerData(rootname, progress);
	readAnnotatorData(rootname, progress);
	readTournamentData(rootname, progress);
	readTeamData(rootname, progress);
	readIndexData(rootname, progress);

	namebases().setReadonly();

	// delete unused annotators (because we are discarding guiding text)
	namebase(Namebase::Annotator).cleanup();

	// delete unused events (sometimes it contains unused entries)
	namebase(Namebase::Event).cleanup();

	namebases().setReadonly(false);
	namebases().setModified(false);
	namebases().update();
	namebases().setReadonly();

	filename.assign(rootname + ".cba");
	checkPermissions(filename);
	openFile(m_annotationStream, filename, Readonly);
}


void
Codec::readTournamentData(mstl::string const& rootname, util::Progress& progress)
{
	M_ASSERT(m_codec);

	static unsigned const RecordSize = 99;

	mstl::string	filename(rootname + ".cbt");
	mstl::string	name;
	mstl::string	city;
	mstl::fstream	strm;

	checkPermissions(filename);
	openFile(strm, filename, Readonly);
	name.assign(160, '\0');
	city.assign(160, '\0');

	uint32_t hdr[7];
	strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr));
	uint32_t nrecs = mstl::bo::swapLE(hdr[0]);
	strm.seekg((strm.size() % RecordSize) - sizeof(hdr), mstl::ios_base::cur);

	unsigned frequency	= progress.frequency(nrecs, 20000);
	unsigned reportAfter	= frequency;
	Namebase& eventBase	= namebase(Namebase::Event);
	Namebase& siteBase	= namebase(Namebase::Site);

	progress.start(nrecs);
	progress.message("read-tournament");
	eventBase.reserve(nrecs, (1 << 24) - 1);

	for (unsigned i = 0; i < nrecs; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		int32_t addr;
		strm.read(reinterpret_cast<char*>(&addr), 4);
		addr = mstl::bo::swapLE(addr);

		if (addr == ::Deleted)
		{
			strm.seekg(RecordSize - 4, mstl::ios_base::cur);
		}
		else
		{
			strm.seekg(5, mstl::ios_base::cur);
			strm.read(name.data(), 40);

			name.set_size(::strippedLen(name));
			mapPlayerName(name);
			toUtf8(name);

			strm.read(city.data(), 30);
			city.set_size(::strippedLen(city));
			toUtf8(city);

			if (city.empty())
				city = '?';

			unsigned char buf[6];
			strm.read(buf, 6);

			Date evDate;
			::setDate(evDate, ByteStream::uint24LE(buf));

			Byte eventType = buf[4];

			time::Mode	timeMode		= time::Unknown;
			event::Mode	eventMode	= event::Undetermined;

			switch ((eventType >> 5) & 3)
			{
				case 0: timeMode = time::Normal; break;
				case 1: timeMode = time::Blitz; break;
				case 2: timeMode = time::Rapid; break;

				case 4:
					timeMode = time::Corr;
//					eventMode = event::PaperMail;
					break;
			}

			Byte nationCode = strm.get();
			country::Code countryCode = country::Unknown;

			if (0 < nationCode && nationCode < U_NUMBER_OF(::NationMap))
			{
				countryCode = ::NationMap[nationCode];

				if (	countryCode == country::Jersey
					&& (	::strstr(city, "Guernsey") != 0
						|| ::strstr(city, "Dgernesy") != 0
						|| ::strstr(city, "Dgèrnésy") != 0
						|| ::strstr(city, "Peter Port") != 0))
				{
					countryCode = country::Guernsey;
				}
			}

			if (countryCode == country::Unknown)
				countryCode = Reader::extractCountryFromSite(city);

			Byte category = strm.get();
			strm.get();	// skip
			Byte rounds = strm.get();

			NamebaseSite* site = siteBase.insertSite(city, countryCode, nrecs);

			NamebaseEvent* event = eventBase.insertEvent(
												name,
												evDate.year(),
												evDate.month(),
												evDate.day(),
												event::Type(mstl::min(eventType & 15, 8)),
												timeMode,
												eventMode,
												nrecs,
												site);

			m_eventMap.container().push_back(BaseMap::value_type(i, event));

			m_tournamentMap.container().push_back(
				TournamentMap::value_type(event, Tournament(category, rounds)));

			strm.seekg(RecordSize - 89, mstl::ios_base::cur);
		}
	}

	siteBase.setNextId(nrecs);
	eventBase.setNextId(nrecs);
	strm.close();

	m_tournamentMap.qsort();
	m_eventMap.qsort();
}


void
Codec::readPlayerData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 67;

	mstl::fstream	strm;
	mstl::string	str;
	mstl::string	filename(rootname + ".cbp");
	Namebase&		base(namebase(Namebase::Player));

	checkPermissions(filename);
	openFile(strm, filename, Readonly);

	uint32_t hdr[7];
	strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr));
	strm.seekg((strm.size() % RecordSize) - sizeof(hdr), mstl::ios_base::cur);
	uint32_t nrecs	= mstl::bo::swapLE(hdr[0]);

	unsigned frequency	= progress.frequency(nrecs, 20000);
	unsigned reportAfter	= frequency;

	base.reserve(nrecs, (1 << 24) - 1);
	str.assign(202, '\0');
	progress.start(nrecs);
	progress.message("read-player");

	for (unsigned i = 0; i < nrecs; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		int32_t addr;
		strm.read(reinterpret_cast<char*>(&addr), 4);
		addr = mstl::bo::swapLE(addr);

		if (addr == ::Deleted)
		{
			strm.seekg(RecordSize - 4, mstl::ios_base::cur);
		}
		else
		{
			uint32_t fideID = 0;

			strm.seekg(5, mstl::ios_base::cur);
			strm.read(str.data(), 30);
			str.set_size(::strippedLen(str));

			char* p = str.data() + str.size();

			str.append(", ", 2);
			strm.read(p + 2, 20);
			str.set_size(::strippedLen(p + 2) + str.size());

			if (p + 2 == str.end())
				str.resize(str.size() - 2);

			mapPlayerName(str);

			if (m_highQuality)
			{
				if (Player const* player = Player::findPlayer(str))
				{
					fideID = player->fideID();

					if (::strchr(str, ',') == nullptr)
						str = player->name();
				}
			}

			m_playerMap.container().push_back(
				BaseMap::value_type(i, base.insertPlayer(str, fideID, nrecs)));
			strm.seekg(RecordSize - 59, mstl::ios_base::cur);
		}
	}

	strm.close();
	base.setNextId(nrecs);
	m_playerMap.qsort();
}


void
Codec::readAnnotatorData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 62;

	mstl::fstream	strm;
	mstl::string	str;
	mstl::string	filename(rootname + ".cbc");
	Namebase&		base(namebase(Namebase::Annotator));

	checkPermissions(filename);
	openFile(strm, filename, Readonly);

	uint32_t hdr[7];
	strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr));
	strm.seekg((strm.size()%RecordSize) - sizeof(hdr), mstl::ios_base::cur);
	uint32_t nrecs	= mstl::bo::swapLE(hdr[0]);

	unsigned frequency	= progress.frequency(nrecs, 20000);
	unsigned reportAfter	= frequency;

	base.reserve(nrecs, (1 << 24) - 1);
	str.assign(200, '\0');
	progress.start(nrecs);
	progress.message("read-annotator");

	for (unsigned i = 0; i < nrecs; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		int32_t addr;
		strm.read(reinterpret_cast<char*>(&addr), 4);
		addr = mstl::bo::swapLE(addr);

		if (addr == ::Deleted)
		{
			strm.seekg(RecordSize, mstl::ios_base::cur);
		}
		else
		{
			strm.seekg(5, mstl::ios_base::cur);
			strm.read(str.data(), 45);
			str.set_size(::strippedLen(str));

			if (!str.empty())
			{
				toUtf8(str);
				m_annotatorMap.container().push_back(BaseMap::value_type(i, base.insert(str, nrecs)));
			}

			strm.seekg(RecordSize - 54, mstl::ios_base::cur);
		}
	}

	strm.close();
	base.setNextId(nrecs);
	m_annotatorMap.qsort();
}


void
Codec::readSourceData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 68;

	mstl::string filename(rootname + ".cbs");

	if (!sys::file::access(filename, sys::file::Readable))
		return;

	mstl::fstream	strm;
	mstl::string	str;
	Date				sourceDate;

	openFile(strm, filename, Readonly);

	uint32_t hdr[7];
	strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr));
	strm.seekg((strm.size()%RecordSize) - sizeof(hdr), mstl::ios_base::cur);
	uint32_t nrecs	= mstl::bo::swapLE(hdr[0]);

	unsigned frequency	= progress.frequency(nrecs, 20000);
	unsigned reportAfter	= frequency;

	m_sourceBase.reserve(nrecs, (1 << 24) - 1);
	str.assign(200, '\0');
	progress.start(nrecs);
	progress.message("read-source");

	for (unsigned i = 0; i < nrecs; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		int32_t addr;
		strm.read(reinterpret_cast<char*>(&addr), 4);
		addr = mstl::bo::swapLE(addr);

		if (addr == ::Deleted)
		{
			strm.seekg(RecordSize - 4, mstl::ios_base::cur);
		}
		else
		{
			strm.seekg(5, mstl::ios_base::cur);
			strm.read(str.data(), 25);
			str.set_size(::strippedLen(str));

			strm.seekg(20, mstl::ios_base::cur);

			unsigned char buf[3];
			strm.read(buf, 3);

			if (!str.empty())
			{
				toUtf8(str);
				::setDate(sourceDate, ByteStream::uint24LE(buf));
				m_sourceMap2.container().push_back(BaseMap::value_type(i, new Source(str, sourceDate)));
			}

			strm.seekg(4, mstl::ios_base::cur); // skip date and version

			if (strm.get() == 1)
				m_highQuality = true;

			strm.seekg(RecordSize - 62, mstl::ios_base::cur);
		}
	}

	strm.close();
	m_sourceMap2.qsort();
}


void
Codec::readTeamData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 72;

	mstl::string filename(rootname + ".cbe");
	if (!sys::file::access(filename, sys::file::Readable))
		return;

	mstl::string filenameJ(rootname + ".cbj");
	if (!sys::file::access(filenameJ, sys::file::Readable))
		return;
	openFile(m_teamStream, filenameJ, Readonly);

	{
		char hdr[12];

		if (!m_teamStream.read(reinterpret_cast<Byte*>(hdr), sizeof(hdr)))
			IO_RAISE(Index, Read_Error, "unexpected end of file");

		m_teamRecordSize = hdr[4];
		m_teamRecords = mstl::bo::swapLE(*(reinterpret_cast<uint32_t*>(hdr + 8)));

		unsigned expectedSize = m_teamRecords*m_teamRecordSize;
		expectedSize += m_teamStream.size()%m_teamRecordSize;

		if (expectedSize != m_teamStream.size())
		{
			fprintf(
				stderr,
				"File \"%s\" has %u records, but %u records are expected (record size is %u)\n",
				filenameJ.c_str(),
				unsigned(m_teamStream.size()/m_teamRecordSize),
				m_teamRecords,
				m_teamRecordSize);

			m_teamStream.close();
			m_teamRecords = 0;
			return;
		}

		if (m_teamRecords != m_numGames)
		{
			fprintf(
				stderr,
				"File \"%s\" has %u records, but index has %u records (%d missing)\n",
				filenameJ.c_str(),
				m_teamRecords,
				m_numGames,
				int(m_numGames - m_teamRecords));
		}
	}

	mstl::fstream	strm;
	mstl::string	str;
	Date				sourceDate;

	openFile(strm, filename, Readonly);

	uint32_t hdr[7];
	strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr));
	strm.seekg((strm.size()%RecordSize) - sizeof(hdr), mstl::ios_base::cur);
	uint32_t nrecs	= mstl::bo::swapLE(hdr[0]);

	unsigned frequency	= progress.frequency(nrecs, 20000);
	unsigned reportAfter	= frequency;

	m_teamBase.reserve(nrecs);
	str.assign(250, '\0');
	progress.start(nrecs);
	progress.message("read-team");

	for (unsigned i = 0; i < nrecs; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		int32_t addr;
		strm.read(reinterpret_cast<char*>(&addr), 4);
		addr = mstl::bo::swapLE(addr);

		if (addr == ::Deleted)
		{
			strm.seekg(RecordSize - 4, mstl::ios_base::cur);
			m_teamBase.push_back(0);
		}
		else
		{
			Team* team = new Team;
			m_teamBase.push_back(team);

			strm.seekg(5, mstl::ios_base::cur);
			strm.read(str.data(), 45);
			str.set_size(::strippedLen(str));
			toUtf8(str);

			unsigned char buf[10];
			strm.read(buf, 10);
			ByteStream bstrm(buf, sizeof(buf));

			unsigned number	= bstrm.uint32LE();
			unsigned year2		= bstrm.get();
			unsigned year  	= bstrm.uint16LE();

			if (number)
			{
				str.append(' ');

				if (str.appendRomanNumber(number) == 0)
					str.format("%u", number);
			}

			if (year && !str.empty())
			{
				if (year2)
					str.format(" %u/%02u", year, (year + 1)%100);
				else
					str.format(" %u", year);
			}

			bstrm.skip(2);
			Byte nation = bstrm.get();

			if (0 < nation && nation < U_NUMBER_OF(::NationMap))
				team->nation = ::NationMap[nation];
			else
				team->nation = country::Unknown;

			char* p = m_sourceBase.alloc(str.size() + 1);
			::memcpy(p, str, str.size());
			p[str.size()] = '\0';
			team->title.hook(p, str.size());

			// next 4 bytes: number of games with this team?
			// next 4 bytes: first game id with this team?

			strm.seekg(RecordSize - 54 - sizeof(buf), mstl::ios_base::cur);
		}
	}

	strm.close();
}


void
Codec::reloadDescription(mstl::string const& rootname)
{
	readIniData(rootname);
}


void
Codec::reloadNamebases(	mstl::string const& rootname,
								mstl::string const& originalSuffix,
								Progress& progress)
{
	M_ASSERT(originalSuffix == "cbh");

	ProgressWatcher watcher(progress, 0);

	namebases().setReadonly(false);

	reloadPlayerData(rootname, progress);
	reloadAnnotatorData(rootname, progress);
	reloadTournamentData(rootname, progress);
	reloadTeamData(rootname, progress);
	reloadSourceData(rootname, progress);

	namebases().setReadonly(true);
}


void
Codec::preloadTournamentData(mstl::string const& rootname, util::Progress& progress)
{
	M_ASSERT(m_codec);

	static unsigned const RecordSize = 99;

	mstl::string	filename(rootname + ".cbt");
	mstl::string	name;
	mstl::string	city;
	mstl::fstream	strm;

	checkPermissions(filename);
	openFile(strm, filename, Readonly);
	name.assign(160, '\0');
	city.assign(160, '\0');

	uint32_t hdr[7];
	strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr));
	uint32_t nrecs = mstl::bo::swapLE(hdr[0]);
	strm.seekg((strm.size() % RecordSize) - sizeof(hdr), mstl::ios_base::cur);

	unsigned frequency	= progress.frequency(nrecs, 20000);
	unsigned reportAfter	= frequency;

	progress.start(nrecs);
	progress.message("preload-tournament");

	for (unsigned i = 0; i < nrecs; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		int32_t addr;
		strm.read(reinterpret_cast<char*>(&addr), 4);
		addr = mstl::bo::swapLE(addr);

		if (addr == ::Deleted)
		{
			strm.seekg(RecordSize - 4, mstl::ios_base::cur);
		}
		else
		{
			strm.seekg(5, mstl::ios_base::cur);
			strm.read(name.data(), 40);
			::convPlayerName(name);
			if (size_t n = ::strlen(name)) HandleData(name, n);

			strm.read(city.data(), 30);
			if (size_t n = ::strlen(city)) HandleData(city, n);

			strm.seekg(RecordSize - 79, mstl::ios_base::cur);
		}
	}

	strm.close();
}


void
Codec::preloadPlayerData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 67;

	mstl::string	name;
	mstl::fstream	strm;
	mstl::string	filename(rootname + ".cbp");

	checkPermissions(filename);
	openFile(strm, filename, Readonly);

	uint32_t hdr[7];
	strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr));
	strm.seekg((strm.size() % RecordSize) - sizeof(hdr), mstl::ios_base::cur);
	uint32_t nrecs	= mstl::bo::swapLE(hdr[0]);

	unsigned frequency	= progress.frequency(nrecs, 20000);
	unsigned reportAfter	= frequency;

	name.assign(202, '\0');
	progress.start(nrecs);
	progress.message("preload-player");

	for (unsigned i = 0; i < nrecs; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		int32_t addr;
		strm.read(reinterpret_cast<char*>(&addr), 4);
		addr = mstl::bo::swapLE(addr);

		if (addr == ::Deleted)
		{
			strm.seekg(RecordSize - 4, mstl::ios_base::cur);
		}
		else
		{
			strm.seekg(5, mstl::ios_base::cur);
			strm.read(name.data(), 30);
			::convPlayerName(name);
			if (size_t n = ::strlen(name)) HandleData(name, n);

			strm.read(name.data(), 20);
			::convPlayerName(name);
			if (size_t n = ::strlen(name)) HandleData(name, n);

			strm.seekg(RecordSize - 59, mstl::ios_base::cur);
		}
	}

	strm.close();
}


void
Codec::preloadAnnotatorData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 62;

	mstl::string	name;
	mstl::fstream	strm;
	mstl::string	filename(rootname + ".cbc");

	checkPermissions(filename);
	openFile(strm, filename, Readonly);

	uint32_t hdr[7];
	strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr));
	strm.seekg((strm.size()%RecordSize) - sizeof(hdr), mstl::ios_base::cur);
	uint32_t nrecs	= mstl::bo::swapLE(hdr[0]);

	unsigned frequency	= progress.frequency(nrecs, 20000);
	unsigned reportAfter	= frequency;

	name.assign(200, '\0');
	progress.start(nrecs);
	progress.message("preload-annotator");

	for (unsigned i = 0; i < nrecs; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		int32_t addr;
		strm.read(reinterpret_cast<char*>(&addr), 4);
		addr = mstl::bo::swapLE(addr);

		if (addr == ::Deleted)
		{
			strm.seekg(RecordSize, mstl::ios_base::cur);
		}
		else
		{
			strm.seekg(5, mstl::ios_base::cur);
			strm.read(name.data(), 45);
			if (size_t n = ::strlen(name)) HandleData(name, n);

			strm.seekg(RecordSize - 54, mstl::ios_base::cur);
		}
	}

	strm.close();
}


void
Codec::reloadTournamentData(mstl::string const& rootname, util::Progress& progress)
{
	M_ASSERT(m_codec);

	static unsigned const RecordSize = 99;

	mstl::string	filename(rootname + ".cbt");
	mstl::string	name;
	mstl::string	city;
	mstl::fstream	strm;

	checkPermissions(filename);
	openFile(strm, filename, Readonly);
	name.assign(160, '\0');
	city.assign(160, '\0');

	uint32_t hdr[7];
	strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr));
	uint32_t nrecs = mstl::bo::swapLE(hdr[0]);
	strm.seekg((strm.size() % RecordSize) - sizeof(hdr), mstl::ios_base::cur);

	unsigned frequency	= progress.frequency(nrecs, 20000);
	unsigned reportAfter	= frequency;
	Namebase& eventBase	= namebase(Namebase::Event);
	Namebase& siteBase	= namebase(Namebase::Site);

	progress.start(nrecs);
	progress.message("load-tournament");

	for (unsigned i = 0; i < nrecs; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		int32_t addr;
		strm.read(reinterpret_cast<char*>(&addr), 4);
		addr = mstl::bo::swapLE(addr);

		if (addr == ::Deleted)
		{
			strm.seekg(RecordSize - 4, mstl::ios_base::cur);
		}
		else
		{
			strm.seekg(5, mstl::ios_base::cur);
			strm.read(name.data(), 40);

			name.set_size(::strippedLen(name));
			m_codec->toUtf8(name);

			if (!name.is_7bit())
			{
				if (!sys::utf8::validate(name))
					m_codec->forceValidUtf8(name);

				eventBase.rename(m_eventMap[i], name);
			}

			strm.read(city.data(), 30);
			city.set_size(::strippedLen(city));
			m_codec->toUtf8(city);

			if (!city.is_7bit())
			{
				if (!sys::utf8::validate(city))
					m_codec->forceValidUtf8(city);

				siteBase.rename(static_cast<NamebaseEvent*>(m_eventMap[i])->site(), city);
			}

			strm.seekg(RecordSize - 79, mstl::ios_base::cur);
		}
	}

	strm.close();
}


void
Codec::reloadPlayerData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 67;

	mstl::string	name;
	mstl::fstream	strm;
	mstl::string	filename(rootname + ".cbp");
	Namebase&		base(namebase(Namebase::Player));

	checkPermissions(filename);
	openFile(strm, filename, Readonly);

	uint32_t hdr[7];
	strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr));
	strm.seekg((strm.size() % RecordSize) - sizeof(hdr), mstl::ios_base::cur);
	uint32_t nrecs	= mstl::bo::swapLE(hdr[0]);

	unsigned frequency	= progress.frequency(nrecs, 20000);
	unsigned reportAfter	= frequency;

	name.assign(202, '\0');
	progress.start(nrecs);
	progress.message("read-player");

	for (unsigned i = 0; i < nrecs; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		int32_t addr;
		strm.read(reinterpret_cast<char*>(&addr), 4);
		addr = mstl::bo::swapLE(addr);

		if (addr == ::Deleted)
		{
			strm.seekg(RecordSize - 4, mstl::ios_base::cur);
		}
		else
		{
			strm.seekg(5, mstl::ios_base::cur);
			strm.read(name.data(), 30);
			name.set_size(::strippedLen(name));

			char* p = name.data() + name.size();

			name.append(", ", 2);
			strm.read(p + 2, 20);
			name.set_size(::strippedLen(p + 2) + name.size());

			if (p + 2 == name.end())
				name.resize(name.size() - 2);

			mapPlayerName(name);
			base.rename(m_playerMap[i], name);
			strm.seekg(RecordSize - 59, mstl::ios_base::cur);
		}
	}

	strm.close();
}


void
Codec::reloadAnnotatorData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 62;

	mstl::string	name;
	mstl::fstream	strm;
	mstl::string	filename(rootname + ".cbc");
	Namebase&		base(namebase(Namebase::Annotator));

	checkPermissions(filename);
	openFile(strm, filename, Readonly);

	uint32_t hdr[7];
	strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr));
	strm.seekg((strm.size()%RecordSize) - sizeof(hdr), mstl::ios_base::cur);
	uint32_t nrecs	= mstl::bo::swapLE(hdr[0]);

	unsigned frequency	= progress.frequency(nrecs, 20000);
	unsigned reportAfter	= frequency;

	name.assign(200, '\0');
	progress.start(nrecs);
	progress.message("read-annotator");

	for (unsigned i = 0; i < nrecs; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		int32_t addr;
		strm.read(reinterpret_cast<char*>(&addr), 4);
		addr = mstl::bo::swapLE(addr);

		if (addr == ::Deleted)
		{
			strm.seekg(RecordSize, mstl::ios_base::cur);
		}
		else
		{
			strm.seekg(5, mstl::ios_base::cur);
			strm.read(name.data(), 45);
			name.set_size(::strippedLen(name));
			m_codec->toUtf8(name);

			if (!name.is_7bit())
			{
				if (!sys::utf8::validate(name))
					m_codec->forceValidUtf8(name);

				base.rename(m_annotatorMap[i], name);
			}

			strm.seekg(RecordSize - 54, mstl::ios_base::cur);
		}
	}

	strm.close();
}


void
Codec::reloadSourceData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 68;

	mstl::string filename(rootname + ".cbs");

	if (!sys::file::access(filename, sys::file::Readable))
		return;

	mstl::string	name;
	mstl::fstream	strm;

	openFile(strm, filename, Readonly);

	uint32_t hdr[7];
	strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr));
	strm.seekg((strm.size()%RecordSize) - sizeof(hdr), mstl::ios_base::cur);
	uint32_t nrecs	= mstl::bo::swapLE(hdr[0]);

	unsigned frequency	= progress.frequency(nrecs, 20000);
	unsigned reportAfter	= frequency;

	name.assign(200, '\0');
	progress.start(nrecs);
	progress.message("read-source");

	for (unsigned i = 0; i < nrecs; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		int32_t addr;
		strm.read(reinterpret_cast<char*>(&addr), 4);
		addr = mstl::bo::swapLE(addr);

		if (addr == ::Deleted)
		{
			strm.seekg(RecordSize - 4, mstl::ios_base::cur);
		}
		else
		{
			strm.seekg(5, mstl::ios_base::cur);
			strm.read(name.data(), 25);
			name.set_size(::strippedLen(name));
			m_codec->toUtf8(name);

			if (!name.is_7bit())
			{
				mstl::string str;

				if (!sys::utf8::validate(name))
					m_codec->forceValidUtf8(name);

				m_sourceBase.rename(m_sourceMap2[i], name);
			}

			strm.seekg(RecordSize - 34, mstl::ios_base::cur);
		}
	}

	strm.close();
}


void
Codec::reloadTeamData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 72;

	if (m_teamRecords == 0)
		return;

	mstl::string	name;
	mstl::fstream	strm;

	openFile(strm, rootname + ".cbe", Readonly);

	uint32_t hdr[7];
	strm.read(reinterpret_cast<char*>(hdr), sizeof(hdr));
	strm.seekg((strm.size()%RecordSize) - sizeof(hdr), mstl::ios_base::cur);
	uint32_t nrecs	= mstl::bo::swapLE(hdr[0]);

	unsigned frequency	= progress.frequency(nrecs, 20000);
	unsigned reportAfter	= frequency;

	name.assign(250, '\0');
	progress.start(nrecs);
	progress.message("read-team");

	for (unsigned i = 0; i < nrecs; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		int32_t addr;
		strm.read(reinterpret_cast<char*>(&addr), 4);
		addr = mstl::bo::swapLE(addr);

		if (addr == ::Deleted)
		{
			strm.seekg(RecordSize - 4, mstl::ios_base::cur);
		}
		else
		{
			strm.seekg(5, mstl::ios_base::cur);
			strm.read(name.data(), 45);
			name.set_size(::strippedLen(name));
			m_codec->toUtf8(name);

			if (!name.is_7bit())
			{
				if (!sys::utf8::validate(name))
					m_codec->forceValidUtf8(name);

				char* p = m_sourceBase.alloc(name.size() + 1);
				::memcpy(p, name, name.size());
				p[name.size()] = '\0';
				m_teamBase[i]->title.hook(p, name.size());
			}

			strm.seekg(RecordSize - 54, mstl::ios_base::cur);
		}
	}

	strm.close();
}


unsigned
Codec::readHeader(mstl::string const& rootname)
{
	mstl::string	filename(rootname + ".cbh");
	mstl::fstream	strm;

	checkPermissions(filename);
	openFile(strm, filename, Readonly);

	Byte record[46];
	strm.read(record, sizeof(record));

	if (	record[0] != 0
		|| record[1] != 0
		|| (	record[2] != 0x2c	// CB 9/10/11
			&& record[2] != 0x24)// CB Light
		|| record[3] != 0
		|| record[4] != 0x2e
		|| record[5] > 0x0a)
	{
		IO_RAISE(Index, Open_Failed, "bad magic in '%s'", filename.c_str());
	}

	ByteStream bstrm(record, sizeof(record));

	bstrm.skip(6);
	return bstrm.uint32() - 1;
}


void
Codec::readIndexData(mstl::string const& rootname, util::Progress& progress)
{
	mstl::string	filename(rootname + ".cbh");
	mstl::fstream	strm;

	Byte record[46];
	ByteStream bstrm(record, sizeof(record));

	openFile(strm, filename, Readonly);
	strm.seekg(sizeof(record));

	ProgressWatcher watcher(progress, m_numGames);
	progress.message("read-index");

	unsigned frequency	= progress.frequency(m_numGames, 20000);
	unsigned reportAfter	= frequency;

	GameInfoList& infoList = gameInfoList();

	infoList.reserve(m_numGames);
	if (!m_sourceMap2.empty())
		m_sourceMap.reserve(m_numGames);
	if (m_teamRecords)
		m_gameIndexLookup.reserve(m_numGames);

	unsigned gameIndex = 0;

	for (unsigned i = 0; i < m_numGames; ++i)
	{
		if (reportAfter == i)
		{
			progress.update(i);
			reportAfter += frequency;
		}

		strm.read(record, sizeof(record));
		bstrm.resetg();

		Byte flags = bstrm.peek();

		if ((flags & 0x2) == 0)
		{
			M_ASSERT(gameIndex < m_numGames);

			GameInfo& info = infoList.push_back();

			decodeIndex(bstrm, info);

			if (m_teamRecords)
				m_gameIndexLookup.container().push_back(GameIndexLookup::value_type(&info, gameIndex));

			gameIndex += 1;
		}
		else
		{
			decodeGuidingText(bstrm);
		}
	}

	strm.close();
	infoList.resize(gameIndex);
	m_gameIndexLookup.qsort();
	m_annotationMap.qsort();
}


void
Codec::readIniData(mstl::string const& rootname)
{
	mstl::string	filename(rootname + ".ini");
	mstl::string	title;
	mstl::fstream	strm;
	db::type::ID	type;

	if (!sys::file::access(filename, sys::file::Readable))
		return;

	openFile(strm, filename, Readonly);
	strm.exceptions(mstl::ios_base::badbit);

	M_ASSERT(m_codec);
	readIniData(strm, *m_codec, type, title);
	setType(type);
	setDescription(title);
}


void
Codec::readIniData(mstl::fstream& strm, sys::utf8::Codec& codec, db::type::ID& type, mstl::string& title)
{
	enum Section { AnyOther, DescrCBG , Environ };

	M_REQUIRE(strm.is_open());

	mstl::string tournTitle;
	mstl::string tournPlace;
	mstl::string tournYear;

	Section section = AnyOther;

	type = Unspecific;

	while (true)
	{
		mstl::string line;

		if (!strm.getline(line))
		{
			strm.close();

			title.trim();
			tournTitle.trim();
			tournPlace.trim();
			tournYear.trim();

			if (!tournTitle.empty())
			{
				title = tournTitle;

				if (tournPlace != "Unknown" && tournPlace != "Unkown" && !tournPlace.empty())
				{
					title.append(", ", 2);
					title += tournPlace;
				}

				if (!tournYear.empty() && ::isdigit(tournYear[0]))
				{
					title.append(", ", 2);
					title += tournYear;
				}
			}

			codec.toUtf8(title);
			if (!::sys::utf8::validate(title))
				codec.forceValidUtf8(title);

			return;
		}

		if (!line.empty())
		{
			if (line[0] == '[')
			{
				if (::strncmp(line, "[DescrCBG]", 10) == 0)
					section = DescrCBG;
				else if (::strncmp(line, "[Environ]", 9) == 0)
					section = Environ;
				else
					section = AnyOther;
			}
			else
			{
				switch (section)
				{
					case DescrCBG:
						if (::strncmp(line, "Type=", 5) == 0)
						{
							unsigned t = ::strtoul(line.c_str() + 5, nullptr, 10);
							if (t < U_NUMBER_OF(::TypeMap))
								type = ::TypeMap[t];
						}
						else if (::strncmp(line, "Title=", 6) == 0)
						{
							title = line.substr(6);
						}
						break;

					case Environ:
						if (::strncmp(line, "TournTitle=", 11) == 0)
							tournTitle = line.substr(11);
						else if (::strncmp(line, "TournPlace=", 11) == 0)
							tournPlace = line.substr(11);
						else if (::strncmp(line, "TournYear=", 10) == 0)
							tournYear = line.substr(10);
						break;

					case AnyOther:
						break;
				}
			}
		}
	}
}


NamebasePlayer*
Codec::getPlayer(uint32_t ref)
{
	BaseMap::iterator p = m_playerMap.find(ref);

	if (p != m_playerMap.end())
	{
		static_cast<NamebasePlayer*>(p->second)->incrRef();
		return static_cast<NamebasePlayer*>(p->second);
	}

	if (m_illegalPlayer == 0)
	{
		m_illegalPlayer = namebase(Namebase::Player).insertPlayer(
									"? (illegal reference)", 0, m_playerMap.size() + 1);
	}

	m_illegalPlayer->incrRef();
	return m_illegalPlayer;
}


NamebaseEvent*
Codec::getEvent(uint32_t ref)
{
	BaseMap::iterator p = m_eventMap.find(ref);

	if (p != m_eventMap.end())
	{
		NamebaseEvent* event = static_cast<NamebaseEvent*>(p->second);

		if (event->frequency() == 0)
			event->site()->incrRef();

		event->incrRef();
		return event;
	}

	if (m_illegalEvent == 0)
	{
		m_illegalEvent = namebase(Namebase::Event).insertEvent(
								"? (illegal reference)",
								m_eventMap.size() + 1,
								namebase(Namebase::Site).insertSite(
									mstl::string::empty_string,
									country::Unknown,
									m_eventMap.size() + 1));
		m_illegalEvent->site()->incrRef();
	}

	m_illegalEvent->incrRef();

	return m_illegalEvent;
}


NamebaseEntry*
Codec::getAnnotator(uint32_t ref)
{
	BaseMap::iterator p = m_annotatorMap.find(ref);
	NamebaseEntry* entry = (p == m_annotatorMap.end()) ?
			namebase(Namebase::Annotator).emptyAnnotator() : p->second;

	entry->incrRef();
	return entry;
}


Codec::Source*
Codec::getSource(uint32_t ref)
{
	BaseMap::iterator p = m_sourceMap2.find(ref);

	if (p == m_sourceMap2.end())
		return 0;

	p->second->incrRef();

	return static_cast<Source*>(p->second);
}


void
Codec::decodeGuidingText(ByteStream& strm)
{
	M_ASSERT(m_gameStream.is_open());

if (::getenv("SCIDB_GUIDING_TEXT") == 0) return;

	Byte flags = strm.get();

	if (flags & (1 << 7))
		return; // is deleted

	unsigned offset			= strm.uint32();

//printf("skip(0): %02x %02x %02x\n", Byte(strm.data()[0]), Byte(strm.data()[1]), Byte(strm.data()[2]));
	strm.skip(3);

	__attribute__((unused)) unsigned tournamentId	= strm.uint24();
	__attribute__((unused)) unsigned sourceId			= strm.uint24();
	__attribute__((unused)) unsigned annotatorId		= strm.uint24();
	__attribute__((unused)) unsigned round				= strm.get();

//printf("offset:     %u\n", offset);
//printf("tournament: %u\n", tournamentId);
//printf("source:     %u\n", sourceId);
//printf("annotator:  %u\n", annotatorId);
//printf("round:      %u\n", round);

#if 0
	if (NamebaseEntry* annotator = getAnnotator(annotatorId))
		send(annotator);
	if (Source* source = getSource(sourceId))
		send(source);
	if (NamebaseEvent* event = getEvent(tournamentId))
		send(event);
	if (round)
		send(round);
#endif

	char header[8];

	if (m_gameStream.seekg(offset, mstl::ios_base::beg) && m_gameStream.read(header, sizeof(header)))
	{
		// Header (8 bytes) -----------------------------------------------------------------------
		// 80 00 20 cd			bit 0-29: Game size (including this, excluding trash bytes)
		// 						bit 30: ?
		// 						bit 31: If set, the data is not encoded
		//
		// 03						type of entries (after titles)?
		// 00						?
		// 01 00					Number of titles (can be 0) (little endian)
		//
		// For each title: ------------------------------------------------------------------------
		// 01 00					Language (0=english, 1=german, 2=france, 3=spain, 4=italian, 5=dutch)
		// 						(little endian) (unknown: italian, portuguese, polish)
		// 05 00					Length of title (little endian)
		// string				Title

		ByteStream bstrm(header, sizeof(header));

		int size = bstrm.uint32();

		if ((size & 0x80000000) == 0)
			return; // data is encoded

		size = (size & 0x3fffffff) - sizeof(header);
//printf("skip(1): %02x %02x\n", Byte(bstrm.data()[0]), Byte(bstrm.data()[1]));

		unsigned type = bstrm.get();

		bstrm.skip(1); // ??

		unsigned numTitles = bstrm.uint16LE();

		mstl::vector<char> buf(size);
		mstl::string str;

		if (m_gameStream.read(buf.data(), size))
		{
			bstrm.setup(reinterpret_cast<Byte*>(buf.data()), size);

			for (unsigned i = 0; i < numTitles; ++i)
			{
				if (bstrm.remaining() <= 4)
				{
					return;
				}

				__attribute__((unused)) unsigned lang		= bstrm.uint16LE();
				__attribute__((unused)) unsigned length	= bstrm.uint16LE();

				if (length > bstrm.remaining())
				{
					return;
				}

				str.clear();
				bstrm.get(str, length);
				::replaceNewlines(str);

//printf("lang=%u, length=%u: '%s'\n", lang, length, str.c_str());
			}
		}

		// PAN-EGC:
		// 01 | 01 00 00 00 | 67 34
		// language | id | length

		// Big2010:
		// 01 | 01 00 00 00 | 20 02
		// language | id | length

		// CB Light Database:
		// 01 | 08 00 00 00 | 6e 09 00 00
		// language | id | length

		// Test1:
		// 01 | 08 00 00 00 | 96 00 00 00
		// language | id | length

		if (type == 1)
		{
			if (bstrm.remaining() > 7)
			{
				__attribute__((unused)) unsigned lang		= bstrm.get();
				__attribute__((unused)) unsigned id			= bstrm.uint32LE();	// which?
				__attribute__((unused)) unsigned length	= bstrm.uint16LE();

				if (length > bstrm.remaining())
				{
					return;
				}

				str.clear();
				bstrm.get(str, length);
				::replaceNewlines(str);
//printf("id=%u, lang=%u: '%s'\n", id, lang, str.c_str());
				bstrm.get(); // nul byte?
			}
		}
		else
		{
			bstrm.get();			// language (unused)
			bstrm.uint32LE();	// title id (unused)

			while (bstrm.remaining() > 4)
			{
				unsigned length = bstrm.uint32LE();

				if (length >= bstrm.remaining())
				{
					return;
				}

				str.clear();
				bstrm.get(str, length);
				::replaceNewlines(str);
//printf("id=%u, lang=%u: '%s'\n", id, lang, str.c_str());
				bstrm.get(); // nul byte?

				if (bstrm.remaining() > 9)
				{
					bstrm.uint32();	// title id (unused)
					bstrm.get();		// language (unused)
				}
			}
		}
	}
}


void
Codec::decodeIndex(ByteStream& strm, GameInfo& info)
{
	M_ASSERT(strm.size() == 46);

	Byte flags = strm.get();

	if (flags & (1 << 7))
		info.m_gameFlags |= GameInfo::Flag_Deleted;

	info.m_gameOffset = strm.uint32();

	if (unsigned offset = strm.uint32())
		m_annotationMap.container().push_back(AnnotationMap::value_type(info.m_gameOffset, offset));

	NamebasePlayer* white = getPlayer(strm.uint24());
	NamebasePlayer* black = getPlayer(strm.uint24());

	info.m_player[color::White] = white;
	info.m_player[color::Black] = black;
	info.m_event = getEvent(strm.uint24());

	if (NamebaseEntry* annotator = getAnnotator(strm.uint24()))
		info.m_annotator = annotator;

	if (!m_sourceMap2.empty())
		m_sourceMap.push_back(getSource(strm.uint24()));

	Date date;
	::setDate(date, strm.uint24());

	info.m_dateYear = Date::encodeYearTo10Bits(date.year());
	info.m_dateMonth = date.month();
	info.m_dateDay = date.day();

	switch (strm.get())
	{
		case 0:	info.m_result = result::Black; break;
		case 1:	info.m_result = result::Draw; break;
		case 2:	info.m_result = result::White; break;
		case 7:	info.m_result = result::Lost; break;
		default:	info.m_result = result::Unknown; break;
	}

	strm.skip(1);	// skip line evaluation

	info.m_round = strm.get();
	info.m_subround = strm.get();

	unsigned whiteElo = strm.uint16();
	unsigned blackElo = strm.uint16();

	if (rating::isValid(whiteElo))
	{
		info.m_pd[color::White].elo = whiteElo;
		if (white != m_illegalPlayer)
			white->setElo(whiteElo);
	}

	if (rating::isValid(blackElo))
	{
		info.m_pd[color::Black].elo = blackElo;
		if (black != m_illegalPlayer)
			black->setElo(blackElo);
	}

	info.m_eco = ::convertEco(strm.uint16());

	unsigned medals = strm.uint16();

	if (medals & (1 <<  0)) info.m_gameFlags |= GameInfo::Flag_Best_Game;
	if (medals & (1 <<  1)) info.m_gameFlags |= GameInfo::Flag_Decided_Tournament;
	if (medals & (1 <<  2)) info.m_gameFlags |= GameInfo::Flag_Model_Game;
	if (medals & (1 <<  3)) info.m_gameFlags |= GameInfo::Flag_Novelty;
	if (medals & (1 <<  4)) info.m_gameFlags |= GameInfo::Flag_Pawn_Structure;
	if (medals & (1 <<  5)) info.m_gameFlags |= GameInfo::Flag_Strategy;
	if (medals & (1 <<  6)) info.m_gameFlags |= GameInfo::Flag_Tactics;
	if (medals & (1 <<  7)) info.m_gameFlags |= GameInfo::Flag_With_Attack;
	if (medals & (1 <<  8)) info.m_gameFlags |= GameInfo::Flag_Sacrifice;
	if (medals & (1 <<  9)) info.m_gameFlags |= GameInfo::Flag_Defense;
	if (medals & (1 << 10)) info.m_gameFlags |= GameInfo::Flag_Material;
	if (medals & (1 << 11)) info.m_gameFlags |= GameInfo::Flag_Piece_Play;
	if (medals & (1 << 12)) info.m_gameFlags |= GameInfo::Flag_End_Game;
	if (medals & (1 << 13)) info.m_gameFlags |= GameInfo::Flag_Blunder;	// Flag_Tactical_Blunder
	if (medals & (1 << 14)) info.m_gameFlags |= GameInfo::Flag_Blunder;	// Flag_Strategical_Blunder
	if (medals & (1 << 15)) info.m_gameFlags |= GameInfo::Flag_User;

	strm.skip(3);
	flags = strm.get();
	info.m_positionId = flags & (1 << 0) ? 0 : variant::Standard; // XXX possibly wrong
	info.m_setup = bool(flags & (1 << 0));

	if (flags & (1 << 1)) info.m_variationCount = 10;
	if (flags & (1 << 2)) info.m_commentCount = 10;
	if (flags & (7 << 3)) info.m_annotationCount = 10;

	strm.skip(1);

	flags = strm.get();
	if (flags & (2 << 0)) info.m_variationCount = 15;
	if (flags & (1 << 2)) info.m_commentCount = 15;
	if (flags & (7 << 3)) info.m_annotationCount = 15;

	info.m_plyCount = mstl::min(	GameInfo::MaxPlyCount,
											unsigned(mstl::max(0, mstl::mul2(int(strm.get())) - 1)));
}


void
Codec::startDecoding(ByteStream& gameStream,
							ByteStream* annotationStream,
							GameInfo const& info,
							bool& isChess960)
{
	sys::Lock lock(&m_mutex);

	try
	{
		if (!info.gameOffset())
			IO_RAISE(Index, Corrupted, "no game data");
		if (!m_gameStream.seekg(info.gameOffset(), mstl::ios_base::beg))
			IO_RAISE(Game, Corrupted, "unexpected end of file");
		if (!m_gameStream.read(gameStream.base(), 4))
			IO_RAISE(Game, Corrupted, "unexpected end of file");

		unsigned word = gameStream.uint32();

		if (word & 0x80000000)
		{
			throw DecodingFailedException(
				"unencoded game not supported (CBH bit 31 set, offset %llu)",
				(unsigned long long)info.gameOffset());

			// TODO: bit 31 = the game data is stored *unencoded* (plain format),
			// not the standard LUT encoding. ChessBase uses this for "guiding
			// texts" / embedded training files whose text must be directly
			// readable. It is NOT encryption (that is the separate .cbz DES
			// archive). scidb does not yet parse this plain format.
			// look at Big2010, #1964391, Giffard, Nicalas - Castlagliola, Marina
		}

		isChess960 = bool(word & 0x0a000000);
		unsigned size = word & 0x00ffffff;

		if (size <= 4)
			IO_RAISE(Game, Corrupted, "bad data");

		gameStream.resetg();
		gameStream.reserve(size);
		gameStream.provide(size);

		if (!m_gameStream.seekg(-4, mstl::ios_base::cur))
			IO_RAISE(Game, Unknown_Error_Type, "seek failed");

		// Sometimes CB is writing corrupted games, even CB cannot read such a game.
		if (!m_gameStream.read(gameStream.base(), size))
			IO_RAISE(Annotation, Corrupted, "bad data");

		AnnotationMap::const_iterator i = m_annotationMap.find(info.gameOffset());

		if (i != m_annotationMap.end())
		{
			uint32_t address = i->second;

			if (!m_annotationStream.seekg(address + 10, mstl::ios_base::beg))
				IO_RAISE(Annotation, Corrupted, "unexpected end of file");

			if (annotationStream)
			{
				if (!m_annotationStream.read(annotationStream->base(), 4))
					IO_RAISE(Annotation, Corrupted, "unexpected end of file");

				size = annotationStream->uint32() - 14;

				annotationStream->resetg();
				annotationStream->reserve(size);
				annotationStream->provide(size);

				if (!m_annotationStream.read(annotationStream->base(), size))
					IO_RAISE(Annotation, Corrupted, "unexpected end of file");
			}
		}
		else if (annotationStream)
		{
			annotationStream->provide(0);
		}
	}
	catch (mstl::ios_base::failure const& exc)
	{
		// This is an expected failure when reading CBH files.
		m_gameStream.clear();
		m_annotationStream.clear();
		throw exc;
	}
}


void
Codec::addSourceTags(TagSet& tags, unsigned index)
{
	if (!m_sourceMap.empty())
	{
		if (Source const* source = m_sourceMap[index])
		{
			tags.set(tag::Source, source->name());

			if (source->date)
				tags.set(tag::SourceDate, source->date.asString());
		}
	}
}


void
Codec::addEventTags(TagSet& tags, GameInfo const& info)
{
	TournamentMap::const_iterator t = m_tournamentMap.find(info.eventEntry());

	if (t != m_tournamentMap.end())
	{
		Tournament tournament = t->second;

		if (tournament.category)
			tags.set(tag::EventCategory, tournament.category);

		if (tournament.rounds)
			tags.set(tag::EventRounds, tournament.rounds);
	}
}


void
Codec::addTeamTags(TagSet& tags, GameInfo const& info)
{
	if (m_teamRecords == 0)
		return;

	M_ASSERT(m_gameIndexLookup.find(&info) != m_gameIndexLookup.end());

	unsigned gameIndex = m_gameIndexLookup.find(&info)->second;

	if (m_teamRecords <= gameIndex)
		return;

	uint32_t buf[2];
	unsigned offset = m_teamStream.size()%m_teamRecordSize + gameIndex*m_teamRecordSize;

	if (!m_teamStream.seekg(offset, mstl::ios_base::beg))
		IO_RAISE(Index, Read_Error, "seek failed");
	if (!m_teamStream.read(reinterpret_cast<Byte*>(buf), sizeof(buf)))
		IO_RAISE(Index, Read_Error, "unexpected end of file");

	unsigned whiteTeamRef = mstl::bo::swapLE(buf[0]);
	unsigned blackTeamRef = mstl::bo::swapLE(buf[1]);

	if (whiteTeamRef < m_teamBase.size())
	{
		if (Team const* team = m_teamBase[whiteTeamRef])
		{
			if (!team->title.empty())
			{
				tags.set(tag::WhiteTeam, team->title);

				if (team->nation != country::Unknown)
					tags.set(tag::WhiteTeamCountry, country::toString(team->nation));

			}
		}
	}

	if (blackTeamRef < m_teamBase.size())
	{
		if (Team const* team = m_teamBase[blackTeamRef])
		{
			if (!team->title.empty())
			{
				tags.set(tag::BlackTeam, team->title);

				if (team->nation != country::Unknown)
					tags.set(tag::BlackTeamCountry, country::toString(team->nation));

			}
		}
	}
}


unsigned
Codec::doDecoding(::util::BlockFileReader* reader, // not used
						GameInfo const& info,
						uint16_t* line,
						unsigned length,
						Board& startBoard,
						bool useStartBoard)
{
	Byte buf[32768];
	ByteStream gStrm(buf, sizeof(buf));
	bool isChess960;

	startDecoding(gStrm, nullptr, info, isChess960);
	return Decoder(gStrm, isChess960).doDecoding(line, length, startBoard, useStartBoard);
}


void
Codec::doDecoding(GameData& data, GameInfo& info, unsigned gameIndex, mstl::string*)
{
	Byte buf[2][32768];

	ByteStream gStrm(buf[0], sizeof(buf[0]));
	ByteStream aStrm(buf[1], sizeof(buf[1]));

	bool isChess960;

	startDecoding(gStrm, &aStrm, info, isChess960);

	addSourceTags(data.m_tags, gameIndex);
	addEventTags(data.m_tags, info);
	addTeamTags(data.m_tags, info);

	GameDecoder decoder(gStrm, aStrm, *m_codec, isChess960);
	info.m_plyCount = mstl::min(GameInfo::MaxPlyCount, decoder.doDecoding(data));
}


save::State
Codec::doDecoding(db::Consumer& consumer, TagSet& tags, GameInfo const& info, unsigned gameIndex)
{
	Byte buf[2][32768];

	ByteStream gStrm(buf[0], sizeof(buf[0]));
	ByteStream aStrm(buf[1], sizeof(buf[1]));

	bool isChess960;

	startDecoding(gStrm, &aStrm, info, isChess960);

	addSourceTags(tags, gameIndex);
	addEventTags(tags, info);
	addTeamTags(tags, info);

	GameDecoder decoder(gStrm, aStrm, *m_codec, isChess960);
	save::State state = decoder.doDecoding(consumer, tags, info, m_moveNodeAllocator);

	return state;
}


#if 0
Move
Codec::findExactPosition(	GameInfo const& info,
									Board const& position,
									bool skipVariations,
									BlockFileReader* reader)
{
	Byte buf[32768];

	ByteStream gStrm(buf, sizeof(buf));
	ByteStream aStrm(static_cast<Byte*>(0), static_cast<Byte*>(0));

	bool isChess960;

	startDecoding(gStrm, &aStrm, info, isChess960);

	Decoder decoder(gStrm, aStrm, *m_codec, isChess960);
	return decoder.findExactPosition(position, skipVariations);
}
#endif


bool
Codec::getAttributes(mstl::string const& filename,
							int& numGames,
							type::ID& type,
							mstl::string* description)
{
	M_REQUIRE(util::misc::file::suffix(filename) == "cbh");

	mstl::fstream strm(sys::file::internalName(filename), mstl::ios_base::in | mstl::ios_base::binary);
	mstl::string rootname(misc::file::rootname(filename));

	if (!strm)
		return false;

	Byte record[46];

	if (!strm.read(record, sizeof(record)))
		return false;

	if (	record[0] != 0
		|| record[1] != 0
		|| (	record[2] != 0x2c		// CB 9/10/11
			&& record[2] != 0x24)	// CB Light
		|| record[3] != 0
		|| record[4] != 0x2e
		|| record[5] > 0x0a)
	{
		return false;
	}

	ByteStream bstrm(record, sizeof(record));

	bstrm.skip(6);
	numGames = bstrm.uint32() - 1;

	if (description)
	{
		strm.close();
		strm.open(rootname + ".ini", mstl::ios_base::in);

		if (strm)
		{
			sys::utf8::Codec codec(sys::utf8::Codec::windows());
			readIniData(strm, codec, type, *description);
			strm.close();
		}
	}

	strm.close();
	return true;
}


void
Codec::getSuffixes(mstl::string const&, StringList& result)
{
	result.push_back("cba");
	result.push_back("cbb");
	result.push_back("cbc");
	result.push_back("cbe");
	result.push_back("cbg");
	result.push_back("cbgi");
	result.push_back("cbh");
	result.push_back("cbj");
	result.push_back("cbm");
	result.push_back("cbp");
	result.push_back("cbs");
	result.push_back("cbt");
	result.push_back("cbtt");
	result.push_back("cib");
	result.push_back("cit");
	result.push_back("ck1");
	result.push_back("ck2");
	result.push_back("ck3");
	result.push_back("ckn");
	result.push_back("cko");
	result.push_back("cp1");
	result.push_back("cp2");
	result.push_back("cp3");
	result.push_back("cpn");
	result.push_back("cpo");
	result.push_back("flags");
	result.push_back("html");
	result.push_back("ini");
	result.push_back("rb0");
	result.push_back("rb1");
	result.push_back("rb2");
}


save::State
Codec::addGame(ByteStream& gameData, ByteStream& annotationData, TagSet const& tags, db::Consumer& consumer)
{
	// Write annotation data to .cba file if present
	if (annotationData.size() > 0 && m_annotationStream.is_open())
	{
		unsigned annotOffset = m_nextAnnotationOffset;
		unsigned annotLength = annotationData.size();
		unsigned totalLength = annotLength + 14;
		Byte recordHeader[14] = { 0 };

		// The reader expects a 10-byte record prefix followed by a 4-byte
		// length field that includes the 14-byte wrapper.
		util::ByteStream::set(recordHeader + 10, uint32_t(totalLength));

		if (!m_annotationStream.write(reinterpret_cast<char const*>(recordHeader), sizeof(recordHeader)))
			IO_RAISE(Game, Write_Failed, "failed to write annotation header");

		if (!m_annotationStream.write(annotationData.data(), annotLength))
			IO_RAISE(Game, Write_Failed, "failed to write annotation data");

		// Store annotation offset for index entry
		// The offset will be linked to the game via m_annotationMap in writeIndexEntry
		unsigned gameOffset = m_nextGameOffset;
		m_annotationMap.container().push_back(AnnotationMap::value_type(gameOffset, annotOffset));

		m_nextAnnotationOffset += totalLength;
	}

	// Delegate to base class addGame for namebase/index handling
	return DatabaseCodec::addGame(gameData, tags, consumer);
}


void
Codec::doOpen(mstl::string const& encoding)
{
	// Used for creating new databases in memory
	M_ASSERT(m_codec == 0);

	m_codec = new sys::utf8::Codec(encoding);
	m_isWritable = true;
	m_nextGameOffset = 1;
	m_nextAnnotationOffset = 1;
}


void
Codec::doOpen(mstl::string const& rootname, mstl::string const& encoding)
{
	// Used for creating new databases on disk
	M_ASSERT(m_codec == 0);

	m_codec = new sys::utf8::Codec(encoding);
	m_rootname = rootname;
	m_isWritable = true;
	m_nextGameOffset = 1;
	m_nextAnnotationOffset = 1;

	setupForWriting(rootname);
}


void
Codec::setWritable()
{
	m_isWritable = true;
}


void
Codec::sync()
{
	if (m_gameStream.is_open())
		m_gameStream.flush();
	if (m_annotationStream.is_open())
		m_annotationStream.flush();
	if (m_indexStream.is_open())
		m_indexStream.flush();
	if (m_namebaseStream.is_open())
		m_namebaseStream.flush();
}


void
Codec::setupForWriting(mstl::string const& rootname)
{
	// Open game file for writing
	mstl::string gameFilename(rootname + ".cbg");
	m_gameStream.open(gameFilename, mstl::fstream::out | mstl::fstream::binary | mstl::fstream::trunc);
	if (!m_gameStream)
		IO_RAISE(Game, Open_Failed, "cannot create game file '%s'", gameFilename.c_str());

	// Open annotation file for writing
	mstl::string annotFilename(rootname + ".cba");
	m_annotationStream.open(annotFilename, mstl::fstream::out | mstl::fstream::binary | mstl::fstream::trunc);
	if (!m_annotationStream)
		IO_RAISE(Game, Open_Failed, "cannot create annotation file '%s'", annotFilename.c_str());

	// Offset 0 means "no record" in CBH indexes, so reserve byte 0.
	char const reserved = '\0';
	if (!m_gameStream.write(&reserved, 1))
		IO_RAISE(Game, Write_Failed, "cannot initialize game file '%s'", gameFilename.c_str());
	if (!m_annotationStream.write(&reserved, 1))
		IO_RAISE(Game, Write_Failed, "cannot initialize annotation file '%s'", annotFilename.c_str());

	// Open index file for writing
	mstl::string indexFilename(rootname + ".cbh");
	m_indexStream.open(indexFilename, mstl::fstream::out | mstl::fstream::binary | mstl::fstream::trunc);
	if (!m_indexStream)
		IO_RAISE(Index, Open_Failed, "cannot create index file '%s'", indexFilename.c_str());

	// Header will be written by writeIndexData() during save()

	m_nextGameOffset = 1;
	m_nextAnnotationOffset = 1;
}


unsigned
Codec::putGame(util::ByteStream const& strm)
{
	M_ASSERT(m_isWritable);
	M_ASSERT(m_gameStream.is_open());

	unsigned offset = m_nextGameOffset;
	unsigned length = strm.size();

	if (!m_gameStream.write(strm.data(), length))
		IO_RAISE(Game, Write_Failed, "failed to write game data");

	m_nextGameOffset += length;
	return offset;
}


unsigned
Codec::putGame(util::ByteStream const& strm, unsigned prevOffset, unsigned prevRecordLength)
{
	// For CBH, we don't reuse space - just append
	return putGame(strm);
}


util::ByteStream
Codec::getGame(GameInfo const& info)
{
	// Read game data from .cbg file
	M_ASSERT(m_gameStream.is_open());

	unsigned offset = info.gameOffset();
	unsigned length = info.gameRecordLength();

	mstl::string buffer;
	buffer.resize(length);

	if (!m_gameStream.seekg(offset, mstl::fstream::beg))
		IO_RAISE(Game, Read_Error, "cannot seek to game offset %u", offset);

	if (!m_gameStream.read(buffer.data(), length))
		IO_RAISE(Game, Read_Error, "cannot read game data");

	return util::ByteStream(reinterpret_cast<Byte*>(const_cast<char*>(buffer.data())), length);
}


util::ByteStream
Codec::getGame(GameInfo const& info, ::util::BlockFileReader* reader)
{
	if (!reader)
		return getGame(info);

	// CBH uses BlockFileReader for game data in the .cbg file
	util::ByteStream src;
	DatabaseCodec::getGameRecord(info, *reader, src);
	return src;
}


void
Codec::save(mstl::string const& rootname, unsigned start, util::Progress& progress)
{
	M_ASSERT(m_codec && m_codec->hasEncoding());

	if (m_gameStream.is_open() && !(m_gameStream.mode() & mstl::ios_base::out))
		IO_RAISE(Game, Read_Only, "game file '%s' is read-only", (rootname + ".cbg").c_str());

	// Sort annotation map so that find() works (entries may have been
	// appended via container().push_back() during addGame)
	m_annotationMap.qsort();

	// Write namebases
	writeNamebases(m_namebaseStream, progress);

	// Write index entries
	writeIndexData(rootname, progress);

	// Write .ini file
	writeIniData(rootname);

	// Sync all streams
	sync();
}


void
Codec::attach(mstl::string const& rootname, util::Progress& progress)
{
	M_ASSERT(m_codec && m_codec->hasEncoding());

	m_rootname = rootname;
	m_isWritable = true;
	setupForWriting(rootname);
	save(rootname, 0, progress);
}


void
Codec::update(mstl::string const& rootname, unsigned index, bool updateNamebase)
{
	util::Progress progress;
	save(rootname, index, progress);
}


void
Codec::updateHeader(mstl::string const& rootname)
{
	// Update the database header (.ini file)
	writeIniData(rootname);
}


void
Codec::writeNamebases(mstl::ostream& stream, util::Progress& progress)
{
	M_ASSERT(m_codec && m_codec->hasEncoding());

	progress.message("write-namebases");

	// Write player namebase
	writePlayerData(m_rootname, progress);

	// Write tournament/event namebase
	writeTournamentData(m_rootname, progress);

	// Write annotator namebase
	writeAnnotatorData(m_rootname, progress);

	// Write source namebase
	writeSourceData(m_rootname, progress);

	// Write team data
	writeTeamData(m_rootname, progress);
}


void
Codec::writePlayerData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 67;

	mstl::string filename(rootname + ".cbp");
	mstl::fstream strm;

	strm.open(filename, mstl::fstream::out | mstl::fstream::binary | mstl::fstream::trunc);
	if (!strm)
		IO_RAISE(Namebase, Open_Failed, "cannot create player file '%s'", filename.c_str());

	Namebase& base = namebase(Namebase::Player);
	uint32_t nrecs = base.size();

	// Write header (28 bytes)
	uint32_t hdr[7] = {0};
	hdr[0] = mstl::bo::swapLE(nrecs);
	strm.write(reinterpret_cast<char const*>(hdr), sizeof(hdr));

	// No padding needed: 28-byte header < any record size

	// Write player records
	unsigned char record[RecordSize];
	for (uint32_t i = 0; i < nrecs; ++i)
	{
		::memset(record, 0, RecordSize);
		ByteStream bstrm(record, RecordSize);

		// Offset to record data (not used in CBH)
		bstrm << uint32_t(0);

		NamebasePlayer* player = base.playerAt(i);
		if (player)
		{
			// FIDE ID / reserved area in the player record.
			bstrm.advance(5);

			// Last name (30 bytes, space-padded)
			mstl::string name = player->name();
			mstl::string::size_type commaPos = name.find(',');
			mstl::string lastName = (commaPos != mstl::string::npos) ? name.substr(0, commaPos) : name;
			lastName.trim();
			unsigned nameLen = mstl::min(lastName.size(), size_t(30));
			bstrm.put(reinterpret_cast<Byte const*>(lastName.data()), nameLen);
			for (unsigned j = nameLen; j < 30; ++j)
				bstrm.put(Byte(' '));

			// First name (20 bytes, space-padded)
			mstl::string firstName;
			if (commaPos != mstl::string::npos)
			{
				firstName = name.substr(commaPos + 1);
				firstName.trim();
			}
			nameLen = mstl::min(firstName.size(), size_t(20));
			bstrm.put(reinterpret_cast<Byte const*>(firstName.data()), nameLen);
			for (unsigned j = nameLen; j < 20; ++j)
				bstrm.put(Byte(' '));

			// Extra data (nation code, birthday, etc. - 8 bytes)
			bstrm.advance(8);
		}

		strm.write(reinterpret_cast<char const*>(record), RecordSize);
	}

	strm.close();
}


void
Codec::writeTournamentData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 99;

	mstl::string filename(rootname + ".cbt");
	mstl::fstream strm;

	strm.open(filename, mstl::fstream::out | mstl::fstream::binary | mstl::fstream::trunc);
	if (!strm)
		IO_RAISE(Namebase, Open_Failed, "cannot create tournament file '%s'", filename.c_str());

	Namebase& eventBase = namebase(Namebase::Event);
	uint32_t nrecs = eventBase.size();

	// Write header (28 bytes)
	uint32_t hdr[7] = {0};
	hdr[0] = mstl::bo::swapLE(nrecs);
	strm.write(reinterpret_cast<char const*>(hdr), sizeof(hdr));

	// No padding needed: 28-byte header < any record size

	// Write tournament records
	unsigned char record[RecordSize];
	for (uint32_t i = 0; i < nrecs; ++i)
	{
		::memset(record, 0, RecordSize);
		ByteStream bstrm(record, RecordSize);

		// Offset to record data
		bstrm << uint32_t(0);

		NamebaseEvent* event = eventBase.eventAt(i);
		if (event)
		{
			// Skip 5 bytes
			bstrm.advance(5);

			// Event name (40 bytes, space-padded)
			mstl::string name = event->name();
			unsigned nameLen = mstl::min(name.size(), size_t(40));
			bstrm.put(reinterpret_cast<Byte const*>(name.data()), nameLen);
			for (unsigned j = nameLen; j < 40; ++j)
				bstrm.put(Byte(' '));

			// Site/city (30 bytes, space-padded)
			mstl::string site;
			if (NamebaseSite const* s = event->site())
			{
				site = s->name();
				if (site == "?")
					site.clear();
			}
			unsigned siteLen = mstl::min(site.size(), size_t(30));
			bstrm.put(reinterpret_cast<Byte const*>(site.data()), siteLen);
			for (unsigned j = siteLen; j < 30; ++j)
				bstrm.put(Byte(' '));

			// Date (3 bytes)
			Date const& date = event->date();
			// Tournament dates are stored little-endian in CBH (see readTournamentData)
			unsigned dateValue = (date.year() << 9) | (date.month() << 5) | date.day();
			bstrm.put(Byte(dateValue));
			bstrm.put(Byte(dateValue >> 8));
			bstrm.put(Byte(dateValue >> 16));

			// Byte after date (position buf[3] in readTournamentData, unknown)
			bstrm.put(Byte(0));

			// Event type + time mode
			Byte eventType = 0; // Default event type
			switch (event->timeMode())
			{
				case time::Blitz: eventType |= (1 << 5); break;
				case time::Rapid: eventType |= (2 << 5); break;
				case time::Corr:  eventType |= (3 << 5); break;
				default: break;
			}
			bstrm.put(eventType);

			// Byte after eventType (position buf[5] in readTournamentData, unknown)
			bstrm.put(Byte(0));


			// Nation code (1 byte) - find from site country
			Byte nationCode = 0;
			if (NamebaseSite const* s = event->site())
			{
				// Find nation code from country
				for (unsigned n = 1; n < U_NUMBER_OF(::NationMap); ++n)
				{
					if (::NationMap[n] == s->country())
					{
						nationCode = n;
						break;
					}
				}
			}
			bstrm.put(nationCode);

			// Category (1 byte)
			TournamentMap::const_iterator t = m_tournamentMap.find(event);
			Byte category = (t != m_tournamentMap.end()) ? t->second.category : 0;
			bstrm.put(category);

			// Skip 1 byte
			bstrm.put(Byte(0));

			// Rounds (1 byte)
			Byte rounds = (t != m_tournamentMap.end()) ? t->second.rounds : 0;
			bstrm.put(rounds);
		}

		strm.write(reinterpret_cast<char const*>(record), RecordSize);
	}

	strm.close();
}


void
Codec::writeAnnotatorData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 62;

	mstl::string filename(rootname + ".cbc");
	mstl::fstream strm;

	strm.open(filename, mstl::fstream::out | mstl::fstream::binary | mstl::fstream::trunc);
	if (!strm)
		IO_RAISE(Namebase, Open_Failed, "cannot create annotator file '%s'", filename.c_str());

	Namebase& base = namebase(Namebase::Annotator);
	uint32_t nrecs = base.size();

	// Write header (28 bytes)
	uint32_t hdr[7] = {0};
	hdr[0] = mstl::bo::swapLE(nrecs);
	strm.write(reinterpret_cast<char const*>(hdr), sizeof(hdr));

	// No padding needed: 28-byte header < any record size

	// Write annotator records
	unsigned char record[RecordSize];
	for (uint32_t i = 0; i < nrecs; ++i)
	{
		::memset(record, 0, RecordSize);
		ByteStream bstrm(record, RecordSize);

		// Offset to record data
		bstrm << uint32_t(0);

		NamebaseEntry* annotator = base.entryAt(i);
		if (annotator)
		{
			// Skip 5 bytes
			bstrm.advance(5);

			// Annotator name (45 bytes, space-padded)
			mstl::string name = annotator->name();
			unsigned nameLen = mstl::min(name.size(), size_t(45));
			bstrm.put(reinterpret_cast<Byte const*>(name.data()), nameLen);
			for (unsigned j = nameLen; j < 45; ++j)
				bstrm.put(Byte(' '));
		}

		strm.write(reinterpret_cast<char const*>(record), RecordSize);
	}

	strm.close();
}


void
Codec::writeSourceData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 68;

	mstl::string filename(rootname + ".cbs");
	mstl::fstream strm;

	strm.open(filename, mstl::fstream::out | mstl::fstream::binary | mstl::fstream::trunc);
	if (!strm)
		IO_RAISE(Namebase, Open_Failed, "cannot create source file '%s'", filename.c_str());

	uint32_t nrecs = m_sourceBase.size();

	// Write header (28 bytes)
	uint32_t hdr[7] = {0};
	hdr[0] = mstl::bo::swapLE(nrecs);
	strm.write(reinterpret_cast<char const*>(hdr), sizeof(hdr));

	// No padding needed: 28-byte header < any record size

	// Write source records
	unsigned char record[RecordSize];
	for (uint32_t i = 0; i < nrecs; ++i)
	{
		::memset(record, 0, RecordSize);
		ByteStream bstrm(record, RecordSize);

		// Offset to record data
		bstrm << uint32_t(0);

		if (i < m_sourceMap2.size())
		{
			// Skip 5 bytes
			bstrm.advance(5);

			// Source title (25 bytes, space-padded)
			mstl::string title;
			if (Source const* src = getSource(i))
				title = src->name();
			unsigned titleLen = mstl::min(title.size(), size_t(25));
			bstrm.put(reinterpret_cast<Byte const*>(title.data()), titleLen);
			for (unsigned j = titleLen; j < 25; ++j)
				bstrm.put(Byte(' '));

			// Publisher (20 bytes, space-padded)
			for (unsigned j = 0; j < 20; ++j)
				bstrm.put(Byte(' '));

			// Date (3 bytes)
			bstrm << util::ByteStream::uint24_t(0);

			// Version (1 byte)
			bstrm.put(Byte(0));

			// Quality flag (1 byte)
			bstrm.put(m_highQuality ? Byte(1) : Byte(0));
		}

		strm.write(reinterpret_cast<char const*>(record), RecordSize);
	}

	strm.close();
}


void
Codec::writeTeamData(mstl::string const& rootname, util::Progress& progress)
{
	static unsigned const RecordSize = 72;

	if (m_teamBase.empty())
	{
		::remove((rootname + ".cbe").c_str());
		::remove((rootname + ".cbj").c_str());
		return;
	}

	// Write .cbe file (team data)
	mstl::string filename(rootname + ".cbe");
	mstl::fstream strm;

	strm.open(filename, mstl::fstream::out | mstl::fstream::binary | mstl::fstream::trunc);
	if (!strm)
		IO_RAISE(Namebase, Open_Failed, "cannot create team file '%s'", filename.c_str());

	uint32_t nrecs = m_teamBase.size();

	// Write header (28 bytes)
	uint32_t hdr[7] = {0};
	hdr[0] = mstl::bo::swapLE(nrecs);
	strm.write(reinterpret_cast<char const*>(hdr), sizeof(hdr));

	// No padding needed: 28-byte header < any record size

	// Write team records
	unsigned char record[RecordSize];
	for (uint32_t i = 0; i < nrecs; ++i)
	{
		::memset(record, 0, RecordSize);
		ByteStream bstrm(record, RecordSize);

		// Offset to record data
		bstrm << uint32_t(0);

		if (i < m_teamBase.size() && m_teamBase[i])
		{
			// Skip 5 bytes
			bstrm.advance(5);

			// Team title (45 bytes, space-padded)
			mstl::string title = m_teamBase[i]->title;
			unsigned titleLen = mstl::min(title.size(), size_t(45));
			bstrm.put(reinterpret_cast<Byte const*>(title.data()), titleLen);
			for (unsigned j = titleLen; j < 45; ++j)
				bstrm.put(Byte(' '));

			// Team number (4 bytes, little-endian in CBH format)
			unsigned teamNumber = 0;
			bstrm.put(Byte(teamNumber));
			bstrm.put(Byte(teamNumber >> 8));
			bstrm.put(Byte(teamNumber >> 16));
			bstrm.put(Byte(teamNumber >> 24));

			// Year type (1 byte)
			bstrm.put(Byte(0));

			// Year (2 bytes, little-endian in CBH format)
			unsigned teamYear = 0;
			bstrm.put(Byte(teamYear));
			bstrm.put(Byte(teamYear >> 8));

			// Skip 2 bytes
			bstrm.advance(2);

			// Nation code (1 byte)
			Byte nationCode = 0;
			for (unsigned n = 1; n < U_NUMBER_OF(::NationMap); ++n)
			{
				if (::NationMap[n] == m_teamBase[i]->nation)
				{
					nationCode = n;
					break;
				}
			}
			bstrm.put(nationCode);
		}

		strm.write(reinterpret_cast<char const*>(record), RecordSize);
	}

	strm.close();

	// Write .cbj file (team index/game linkage)
	mstl::string filenameJ(rootname + ".cbj");
	mstl::fstream strmJ;

	strmJ.open(filenameJ, mstl::fstream::out | mstl::fstream::binary | mstl::fstream::trunc);
	if (!strmJ)
		IO_RAISE(Namebase, Open_Failed, "cannot create team index file '%s'", filenameJ.c_str());

	// The reader treats the 12-byte header as 4 bytes of remainder plus
	// fixed-size 8-byte records, so the stored count includes that slot.
	unsigned numGames = gameInfoList().size();
	char hdrJ[12] = {0};
	hdrJ[4] = 8;  // record size
	*reinterpret_cast<uint32_t*>(hdrJ + 8) = mstl::bo::swapLE(uint32_t(numGames + 1));
	strmJ.write(hdrJ, sizeof(hdrJ));

	// Write team references for each game
	for (unsigned i = 0; i < numGames; ++i)
	{
		// Each entry is 8 bytes: team ID + unknown
		unsigned char entry[8] = {0};
		if (i < m_teamBase.size())
			entry[0] = static_cast<Byte>(i);
		strmJ.write(reinterpret_cast<char const*>(entry), sizeof(entry));
	}

	strmJ.close();
}


void
Codec::writeIndexData(mstl::string const& rootname, util::Progress& progress)
{
	mstl::string filename(rootname + ".cbh");
	mstl::fstream strm;

	strm.open(filename, mstl::fstream::out | mstl::fstream::binary | mstl::fstream::trunc);
	if (!strm)
		IO_RAISE(Index, Open_Failed, "cannot create index file '%s'", filename.c_str());

	progress.message("write-index");

	// Write header (46 bytes)
	unsigned char header[46];
	::memset(header, 0, sizeof(header));
	ByteStream hstrm(header, sizeof(header));

	// Magic bytes for CBH format
	header[2] = 0x2c;  // CB 9/10/11 format
	header[4] = 0x2e;
	header[5] = 0x01;

	// Number of games (stored at offset 6, 4 bytes)
	GameInfoList& infoList = gameInfoList();
	uint32_t numGames = infoList.size();
	hstrm.advance(6);
	hstrm << uint32_t(numGames + 1);  // CBH stores count + 1

	strm.write(reinterpret_cast<char const*>(header), sizeof(header));

	// Write index entries
	unsigned char record[46];
	for (unsigned i = 0; i < numGames; ++i)
	{
		::memset(record, 0, sizeof(record));
		ByteStream bstrm(record, sizeof(record));
		writeIndexEntry(infoList[i], i, bstrm);
		strm.write(reinterpret_cast<char const*>(record), sizeof(record));
	}

	strm.close();
}


void
Codec::writeIndexEntry(GameInfo const& info, unsigned index, util::ByteStream& strm)
{
	// CBH index entries are 46 bytes
	// Based on decodeIndex() - reverse the reading process

	// Byte 0: Flags
	Byte flags = 0;
	if (info.m_gameFlags & GameInfo::Flag_Deleted)
		flags |= (1 << 7);
	strm.put(flags);

	// Bytes 1-4: Game offset in .cbg file
	strm << uint32_t(info.m_gameOffset);

	// Bytes 5-8: Annotation offset in .cba file (0 if none)
	uint32_t annotOffset = 0;
	AnnotationMap::const_iterator it = m_annotationMap.find(info.m_gameOffset);
	if (it != m_annotationMap.end())
		annotOffset = it->second;
	strm << uint32_t(annotOffset);

	// Bytes 9-11: White player ID (24-bit)
	uint32_t whiteId =
		findPlayerRecordIndex(namebase(Namebase::Player), info.m_player[color::White]);
	strm << util::ByteStream::uint24_t(whiteId);

	// Bytes 12-14: Black player ID (24-bit)
	uint32_t blackId =
		findPlayerRecordIndex(namebase(Namebase::Player), info.m_player[color::Black]);
	strm << util::ByteStream::uint24_t(blackId);

	// Bytes 15-17: Event ID (24-bit)
	uint32_t eventId = findEventRecordIndex(namebase(Namebase::Event), info.m_event);
	strm << util::ByteStream::uint24_t(eventId);

	// Bytes 18-20: Annotator ID (24-bit)
	uint32_t annotatorId =
		findAnnotatorRecordIndex(namebase(Namebase::Annotator), info.m_annotator);
	strm << util::ByteStream::uint24_t(annotatorId);

	// Source ID (24-bit) - only present when source data exists
	bool hasSource = !m_sourceMap2.empty();
	if (hasSource)
	{
		uint32_t sourceId = 0;
		strm << util::ByteStream::uint24_t(sourceId);
	}

	// Date (year << 9 | month << 5 | day)
	unsigned dateValue = (Date::decodeYearFrom10Bits(info.m_dateYear) << 9)
						| (info.m_dateMonth << 5)
						| info.m_dateDay;
	strm << util::ByteStream::uint24_t(dateValue);

	// Byte 27: Result (0=Black, 1=Draw, 2=White, 7=Lost/default, else Unknown)
	Byte resultByte = 0xff;  // Unknown
	switch (info.m_result)
	{
		case result::White: resultByte = 2; break;
		case result::Draw:  resultByte = 1; break;
		case result::Black: resultByte = 0; break;
		case result::Lost:  resultByte = 7; break;
		default: break;
	}
	strm.put(resultByte);

	// Byte 28: Line evaluation (skip)
	strm.put(Byte(0));

	// Byte 29: Round
	strm.put(Byte(info.m_round));

	// Byte 30: Sub-round
	strm.put(Byte(info.m_subround));

	// Bytes 31-32: White ELO
	strm << uint16_t(info.m_pd[color::White].elo);

	// Bytes 33-34: Black ELO
	strm << uint16_t(info.m_pd[color::Black].elo);

	// Bytes 35-36: ECO code (CBH stores eco << 7, lower 7 bits are sub-code)
	strm << uint16_t(info.m_eco << 7);

	// Bytes 37-38: Medals/flags
	uint16_t medals = 0;
	if (info.m_gameFlags & GameInfo::Flag_Best_Game)      medals |= (1 << 0);
	if (info.m_gameFlags & GameInfo::Flag_Decided_Tournament) medals |= (1 << 1);
	if (info.m_gameFlags & GameInfo::Flag_Model_Game)     medals |= (1 << 2);
	if (info.m_gameFlags & GameInfo::Flag_Novelty)        medals |= (1 << 3);
	if (info.m_gameFlags & GameInfo::Flag_Pawn_Structure) medals |= (1 << 4);
	if (info.m_gameFlags & GameInfo::Flag_Strategy)       medals |= (1 << 5);
	if (info.m_gameFlags & GameInfo::Flag_Tactics)       medals |= (1 << 6);
	if (info.m_gameFlags & GameInfo::Flag_With_Attack)    medals |= (1 << 7);
	if (info.m_gameFlags & GameInfo::Flag_Sacrifice)     medals |= (1 << 8);
	if (info.m_gameFlags & GameInfo::Flag_Defense)       medals |= (1 << 9);
	if (info.m_gameFlags & GameInfo::Flag_Material)       medals |= (1 << 10);
	if (info.m_gameFlags & GameInfo::Flag_Piece_Play)    medals |= (1 << 11);
	if (info.m_gameFlags & GameInfo::Flag_End_Game)       medals |= (1 << 12);
	if (info.m_gameFlags & GameInfo::Flag_Blunder)        medals |= (1 << 13) | (1 << 14);
	if (info.m_gameFlags & GameInfo::Flag_User)           medals |= (1 << 15);
	strm << medals;

	// Bytes 39-41: Unknown/reserved.
	strm.advance(3);

	// Byte 42: Flags (position ID, setup, variation count, etc.)
	Byte flags2 = 0;
	if (info.m_setup)
		flags2 |= (1 << 0);
	if (info.m_variationCount >= 10)
		flags2 |= (1 << 1);
	if (info.m_commentCount >= 10)
		flags2 |= (1 << 2);
	if (info.m_annotationCount > 0)
		flags2 |= (1 << 3);
	strm.put(flags2);

	// Skip 1 byte (unknown)
	strm.put(Byte(0));

	// More flags
	Byte flags3 = 0;
	if (info.m_variationCount >= 15)
		flags3 |= (2 << 0);
	if (info.m_commentCount >= 15)
		flags3 |= (1 << 2);
	strm.put(flags3);

	// Ply count / 2 (rounded up)
	unsigned plyCount2 = (info.m_plyCount + 1) / 2;
	if (plyCount2 > 255) plyCount2 = 255;
	strm.put(Byte(plyCount2));

	// When source field is absent, record data is 43 bytes;
	// pad to 46-byte record size
	if (!hasSource)
		strm.advance(3);
}


db::Consumer*
Codec::getConsumer(format::Type srcFormat)
{
	return new Consumer(srcFormat, *this, encoding(), Consumer::TagBits(true), true);
}


void
Codec::writeIniData(mstl::string const& rootname)
{
	mstl::string filename(rootname + ".ini");
	mstl::fstream strm;

	strm.open(filename, mstl::fstream::out | mstl::fstream::trunc);
	if (!strm)
		IO_RAISE(Index, Open_Failed, "cannot create ini file '%s'", filename.c_str());

	// Write in CBH .ini format expected by readIniData()
	strm << "[DescrCBG]\n";

	// Find the inverse type mapping: internal type::ID -> CBH type number
	unsigned cbhType = 0;
	for (unsigned i = 0; i < U_NUMBER_OF(::TypeMap); ++i)
	{
		if (::TypeMap[i] == type())
		{
			cbhType = i;
			break;
		}
	}
	strm << "Type=" << cbhType << "\n";
	strm << "Title=" << description().c_str() << "\n";

	strm.close();
}

// vi:set ts=3 sw=3:
