#include "HookCore.hpp"
#include "SecurityCore.hpp"
#include <iostream>

namespace VMCore {

HookCore &HookCore::shared() {
  static HookCore instance;
  return instance;
}

bool HookCore::processMGDCommand(uint32_t cmdHash,
                                 const std::vector<uint8_t> &data) {
  
  switch (cmdHash) {
  case 0xAABBCCDD: 
    return true;
  default:
    return false;
  }
}

void HookCore::onHookTriggered(uint32_t hookID, void *arg1, void *arg2,
                               void *arg3) {
  
}

} 
