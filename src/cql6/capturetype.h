#pragma once
#include<string>
/*this enum class represents whether a DashCon or a Focus
  represents a capture*/

enum class CaptureType{None,Capture,NonCapture};
std::string captureTypeToString(CaptureType);
bool captureTypeIsCapture(CaptureType);
bool captureTypeIsNonCapture(CaptureType);
bool captureTypeValid(CaptureType c);

