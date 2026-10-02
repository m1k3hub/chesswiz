#pragma once
#include <stdio.h>
#include "cqlassert.h"
#include "cqlexit.h"
#include "abbreviations.h"
#include <array>

class PgnSource{
 public:
  int gameNumber{0};
  size_t nRequests{0};
  PgnSource(string filename);
  bool nextGame(char*buffer,
		int maxlength,
		int*gamenumberp,
		int*charsreadp,
		int*linestartp);
  void print();
  string toString();
 private:
  //////Location information
  size_t lineNumber{1}; //1-based (relied on in mainloop)
  size_t filePosition{0}; //position of next character in file
  int charInLine{0};
  int bufferPosition{0}; //next position to write in buffer;
  /////Buffer information
  char* theBuffer{0};
  int bufferCapacity{0};
  ////File information
  FILE* theFile{NULL};
  string fileName;
  //////////////
  bool Eof{false}; //whether the actual file is at EOF, not the current pointer
  void pgnAssert(bool test,const char* message);
  bool isReading{false};
  bool mainLoop();
  int getChar(); //read next char, set Eof, return -1 if EOF
  void skipLine();
  void skipComment(bool fixnested);
  bool seen_result();
  void writeBuffer(int c);
  void skipTagLine();
  int getPreviousCharacter();
  bool seen_result_string(const char* res);
  int peek();
  void skipNonAsciiBuffer();
};
