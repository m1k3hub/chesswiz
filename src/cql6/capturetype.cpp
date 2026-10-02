#include "cqlassert.h"
#include "capturetype.h"
string captureTypeToString(CaptureType c){
  switch(c){
  case CaptureType::None: return "None";
  case CaptureType::Capture: return "Capture";
  case CaptureType::NonCapture: return "NonCapture";
  };
  uassert(false,"bad  type");
  return "";
}
bool captureTypeIsCapture(CaptureType c){
  return c==CaptureType::Capture;
}
bool captureTypeIsNonCapture(CaptureType c){
  return c==CaptureType::NonCapture;
}
bool captureTypeValid(CaptureType c){
  return c!=CaptureType::None;
}
