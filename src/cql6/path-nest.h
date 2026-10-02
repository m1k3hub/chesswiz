/* include in pathnode.h
    methods and members relating to nesting
*/

 public:
  bool nestBan{false}; //whether this bans nesting
  void nestRegisterPosition(QPos*qpos); //register current position as having matched
  void nestRegisterPositions(QPos*start,QPos*finish);
  bool nestSeenPosition(QPos*qpos); // query if this filter has seen current position
  void nestClearPositions(); //clear all positions that have been seen by this
  std::set<QPos*> nestIds; // the positions with a child matched by part of the current filter

