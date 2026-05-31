#ifndef ScriptExecutor_hpp
#define ScriptExecutor_hpp

#include <functional>
#include <map>
#include <string>
#include <vector>

namespace VMCore {

struct ScriptContext {
  void *bridgeInstance; 
  std::function<void(const std::string &)> logFunc;
};

class ScriptExecutor {
public:
  virtual ~ScriptExecutor() = default;

  virtual bool execute(uint32_t cmdHash, const std::vector<std::string> &args,
                       ScriptContext &ctx) = 0;

  static constexpr uint32_t hash(const char *str, uint32_t h = 0x811c9dc5) {
    return !*str ? h : hash(str + 1, (h ^ (uint32_t)*str) * 0x01000193);
  }
};

} 

#endif
