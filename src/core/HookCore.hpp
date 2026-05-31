#ifndef HookCore_hpp
#define HookCore_hpp

#include <functional>
#include <string>
#include <vector>

namespace VMCore {

class HookCore {
public:
  static HookCore &shared();

  bool processMGDCommand(uint32_t cmdHash, const std::vector<uint8_t> &data);

  void onHookTriggered(uint32_t hookID, void *arg1, void *arg2, void *arg3);

private:
  HookCore() = default;
};

} 

#endif
