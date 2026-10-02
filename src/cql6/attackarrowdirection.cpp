#include "attackarrowdirection.h"
bool AttackArrowDirectionIsValid(AttackArrowDirection d){return d!=AttackArrowDirection::None;}
bool AttackArrowDirectionIsInvalid(AttackArrowDirection d){return d==AttackArrowDirection::None;}
bool AttackArrowDirectionIsLeft(AttackArrowDirection d){return d==AttackArrowDirection::Left;}
bool AttackArrowDirectionIsRight(AttackArrowDirection d){return d==AttackArrowDirection::Right;}
