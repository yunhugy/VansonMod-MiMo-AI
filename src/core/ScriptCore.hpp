#ifndef ScriptCore_hpp
#define ScriptCore_hpp

#include "../memory/core/MemoryCore.hpp"
#include "ScriptExecutor.hpp"
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace VMCore {

class ScriptCore {
public:
  static ScriptCore &getInstance();

  bool dispatchCommand(const std::string &cmd,
                       const std::vector<std::string> &args,
                       ScriptContext &ctx);

  DataType typeFromStr(const std::string &typeStr);

  void getSearchRange(const std::string &argStart, const std::string &argEnd,
                      const std::string &defStart, const std::string &defEnd,
                      uint64_t &outStart, uint64_t &outEnd);

private:
  ScriptCore() = default;
};

} 

#endif /* ScriptCore_hpp */
