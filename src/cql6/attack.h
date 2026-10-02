#pragma once
#include "node.h"
class Attack{
 public:
  static void initialize();
  static SquareMask attacksquares(SquareMask squares,
				  const pieceT* board,
				  SquareMask occupied,
				  SquareMask target);
  static SquareMask attacksquare(squareT square,
				 pieceT piece,
				 SquareMask occupied,
				 SquareMask target);
  static SquareMask orthogonalShift(squareT square);
  static SquareMask diagonalShift(squareT square);
  static SquareMask betweenmask(squareT source,squareT target);
  static SquareMask kingAttacks(squareT square);
  static SquareMask pawnAttacks(squareT square, colorT color);
  static SquareMask knightAttacks(squareT square);
  static squareT shift(squareT square, int fileoffset, int rankoffset);
  static SquareMask pawnNormalMove(squareT square, SquareMask occupied, colorT color);
  static bool enpassantAttack(QPos*qpos,
			      squareT square,
			      const pieceT*board,
			      squareT*epsquarep,
			      squareT*eptop,
			      bool allowPseudo);
  static bool incheck(const pieceT*board, colorT tomove);
  static void masks_from_board(const pieceT*board,
			       SquareMask*masks, //array of length 2, for BLACK and WHITE
			       squareT*kingsquares // array of length 2 for BLACK, WHITE
			       );
  static SquareMask castle(QPos*qpos,
			   SquareMask* masks,
			   const squareT* kingsquares);
  static SquareMask moveTos(QPos*qpos);

};
