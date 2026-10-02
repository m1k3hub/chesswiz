#pragma once
#include "abbreviations.h"
#include <map>
enum class UnicodePieces{None=0,Start=0x2654, K=0x2654,Q,R,B,N,P,
			   k,q,r,b,n,p,Last=p};

/*codepoints*/
const int UnicodeTimes=0xD7;
const int UnicodeWhitePiece=0x25b3;
const int UnicodeBlackPiece=0x25b2;
const int UnicodePiece=0x25ed;
const int UnicodeEmptySquare=0x25A1;
const int UnicodeWhiteRightPointingPointer=0x25BB;
const int UnicodeBlackRightPointingPointer=0x25BA;
const int UnicodeDash=UnicodeBlackRightPointingPointer;
const int UnicodeGrid=0x25A6;
const int UnicodeIntersection=0x2229; 
const int UnicodeUnion=0x222A;        
const int UnicodeDoubleVertical=0x2560;
const int UnicodeVerticalSingleAndRight=0x255E;
const int UnicodeVerticalSingleAndLeft=0x2561;
const int UnicodeLightVertical=0x2502;
const int UnicodeDoubleHorizontal=0x2550;
const int UnicodeHorizontalBar=0x2015;
const int UnicodeTurnstile=0x22A2;
const vector<int>UnicodeDashCodes={UnicodeHorizontalBar,UnicodeHorizontalBar};
const int UnicodeApproximatelyEqual=0x2245;
const int UnicodeEightPointedStar=0x2735;
const int UnicodeHalfBlackSquare=0x2B13;
const int UnicodeBOM=0xFEFF;
const int UnicodeElement=0x220A;
const int UnicodeForAll=0x2200;
const int UnicodeLE=0x2264;
const int UnicodeGE=0x2265;
const int UnicodeNE=0x2260;
const int UnicodeDottedArrow=0x2911;
const int UnicodeDottedCircle=0x29BF;
const int UnicodeConcentricCircles=0x25CE; //changed 9.455
const int UnicodeBullet=0x2219;
const int UnicodeLeftArrow=0x2190;
const int UnicodeRightArrow=0x2192;
const int UnicodePrecedes=0x227A;
const int UnicodeSucceeds=0x227B;
const int UnicodePrecedesOrEqualTo=0x227C;
const int UnicodeSucceedsOrEqualTo=0x227D;



/*ascii equivalents*/
const string CaptureAscii="[x]";
const string DashAscii="--";
const string ForAllAscii="[forall]";
const string ElementAscii="[element]";

/*string forms of selected symbols*/
const string UnicodeDashString="\xE2\x80\x95\xE2\x80\x95";
const string UnicodeBOMString="\xEF\xBB\xBF";
const string UnicodeUnionString="\xE2\x88\xAA";
const string UnicodeIntersectionString="\xE2\x88\xA9";

/*names of unicode symbols*/
const std::map<int,string>UnicodeNames=
  {
   {(int)UnicodePieces::K,"WHITE CHESS KING"},
   {(int)UnicodePieces::Q,"WHITE CHESS QUEEN"},
   {(int)UnicodePieces::R,"WHITE CHESS ROOK"},
   {(int)UnicodePieces::B,"WHITE CHESS BISHOP"},
   {(int)UnicodePieces::N,"WHITE CHESS KNIGHT"},
   {(int)UnicodePieces::P,"WHITE CHESS PAWN"},
   {(int)UnicodePieces::k,"BLACK CHESS KING"},
   {(int)UnicodePieces::q,"BLACK CHESS QUEEN"},
   {(int)UnicodePieces::r,"BLACK CHESS ROOK"},
   {(int)UnicodePieces::b,"BLACK CHESS BISHOP"},
   {(int)UnicodePieces::n,"BLACK CHESS KNIGHT"},
   {(int)UnicodePieces::p,"BLACK CHESS PAWN"},
   {UnicodeWhitePiece,"WHITE UP-POINTING TRIANGLE"},
   {UnicodeBlackPiece,"BLACK UP-POINTING TRIANGLE"},
   {UnicodePiece,"UP-POINTING TRIANGLE WITH LEFT HALF BLACK"},
   {UnicodeBlackRightPointingPointer,"Black RIGHT-POINTING POINTER"},
   {UnicodeEmptySquare,"WHITE SQUARE"},
   {UnicodeTimes,"MULTIPLICATION SIGN"},
   {UnicodeGrid,"SQUARE WITH ORTHOGONAL CROSSHATCH FILL"},
   {UnicodeDoubleVertical,"BOX DRAWINGS DOUBLE VERTICAL AND RIGHT"},
   {UnicodeDoubleHorizontal,"BOX DRAWINGS DOUBLE HORIZONTAL"},
   {UnicodeVerticalSingleAndRight,"BOX DRAWINGS VERTICAL SINGLE AND RIGHT DOUBLE"},
   {UnicodeVerticalSingleAndLeft,"BOX DRAWINGS VERTICAL SINGLE AND LEFT DOUBLE"},
   {UnicodeLightVertical,"BOX DRAWINGS LIGHT VERTICAL"}  ,
   {UnicodeHorizontalBar,"HORIZONTAL BAR"},
   {UnicodeDottedArrow,"RIGHTWARDS ARROW WITH DOTTED STEM"},
   {UnicodeTurnstile,"RIGHT TACK"},
   {UnicodeDottedCircle,"CIRCLED BULLET"},
   {UnicodeConcentricCircles,"BULLSEYE"},
   {UnicodeBullet,"BULLET OPERATOR"},
   {UnicodeNE,"NOT EQUAL TO"},
   {UnicodeApproximatelyEqual,"APPROXIMATELY EQUAL TO"},
   {UnicodeBOM,"BYTE ORDER MARK"},
   {UnicodeLeftArrow,"LEFTWARDS ARROW"},
   {UnicodeRightArrow,"RIGHTWARDS ARROW"},
   {UnicodeEightPointedStar,"EIGHT POINTED PINWHEEL STAR"},
   {UnicodeHalfBlackSquare,"SQUARE WITH BOTTOM HALF BLACK"},
   {UnicodeUnion,"UNION"},
   {UnicodeIntersection,"INTERSECTION"},
   {UnicodeForAll,"FOR ALL"},
   {UnicodeElement,"ELEMENT OF"},
   {UnicodePrecedes,"PRECEDES"},
   {UnicodeSucceeds,"SUCCEEDS"},
   {UnicodePrecedesOrEqualTo,"PRECEDESOREQUALTO"},
   {UnicodeSucceedsOrEqualTo,"SUCCEEDSOREQUALTO"}
  };

const vector<std::pair<string,int>> test1=
  {
   {"hi1"s,3},
   {"hi2"s,4}};

const vector<std::pair<string,int>> test2=
  {
   {"hi1",3},
   {"hi2",4}};

const vector<std::pair<string,int>> AsciiToUnicode=
  {
   {"<=",UnicodeLE},
   {">=",UnicodeGE},
   {"!=",UnicodeNE},
   {"->",UnicodeRightArrow},
   {"<-",UnicodeLeftArrow},
   {"path",UnicodeTurnstile},
   {"focus",UnicodeConcentricCircles},
   {"currentposition",UnicodeBullet},
   {"curpos",UnicodeBullet},
   {"flip",UnicodeEightPointedStar},
   {"flipcolor",UnicodeHalfBlackSquare},
   {"[x]",UnicodeTimes},
   {"[forall]",UnicodeForAll},
   {"[element]",UnicodeElement},
   {".",UnicodeGrid},
   {"_",UnicodeEmptySquare},
   {"A",UnicodeWhitePiece},
   {"a",UnicodeBlackPiece},
   {"[Aa]",UnicodePiece},
   {"&",UnicodeIntersection},
   {"|",UnicodeUnion},
   {"[<]",UnicodePrecedes},
   {"[>]",UnicodeSucceeds},
   {"[<=]",UnicodePrecedesOrEqualTo},
   {"[>=]",UnicodeSucceedsOrEqualTo},
   {"N",(int)UnicodePieces::N},
   {"n",(int)UnicodePieces::n},
   {"R",(int)UnicodePieces::R},
   {"r",(int)UnicodePieces::r},
   {"B",(int)UnicodePieces::B},
   {"b",(int)UnicodePieces::b},
   {"Q",(int)UnicodePieces::Q},
   {"q",(int)UnicodePieces::q},
   {"K",(int)UnicodePieces::K},
   {"k",(int)UnicodePieces::k},
   {"P",(int)UnicodePieces::P},
   {"p",(int)UnicodePieces::p}
  };




