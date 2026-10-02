#pragma once
#include<string>
//this enum class represents the direction of an attack arrow"

enum class AttackArrowDirection{None,Left,Right};
bool AttackArrowDirectionIsValid(AttackArrowDirection d);
bool AttackArrowDirectionIsInvalid(AttackArrowDirection d);
bool AttackArrowDirectionIsLeft(AttackArrowDirection d);
bool AttackArrowDirectionIsRight(AttackArrowDirection d);
