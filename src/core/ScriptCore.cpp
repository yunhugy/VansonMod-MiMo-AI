#include "ScriptCore.hpp"
#include <algorithm>

namespace VMCore {

ScriptCore &ScriptCore::getInstance() {
  static ScriptCore instance;
  return instance;
}

DataType ScriptCore::typeFromStr(const std::string &typeStr) {
  std::string str = typeStr;
  std::transform(str.begin(), str.end(), str.begin(), ::tolower);

  if (str == "i8")
    return DataType::Int8;
  if (str == "i16")
    return DataType::Int16;
  if (str == "i32")
    return DataType::Int32;
  if (str == "i64")
    return DataType::Int64;
  
  if (str == "u8")
    return DataType::UInt8;
  if (str == "u16")
    return DataType::UInt16;
  if (str == "u32")
    return DataType::UInt32;
  if (str == "u64")
    return DataType::UInt64;
  
  if (str == "f32" || str == "float")
    return DataType::Float;
  if (str == "f64" || str == "double")
    return DataType::Double;
  
  if (str == "str" || str == "string")
    return DataType::String;
  
  return DataType::Int32; 
}

bool ScriptCore::dispatchCommand(const std::string &cmd,
                                 const std::vector<std::string> &args,
                                 ScriptContext &ctx) {
  uint32_t h = ScriptExecutor::hash(cmd.c_str());

  switch (h) {
  case ScriptExecutor::hash("search"): 
    
    return true;
  case ScriptExecutor::hash("getValue"):
    return true;
  case ScriptExecutor::hash("setValue"):
    return true;
  default:
    if (ctx.logFunc)
      ctx.logFunc("[ScriptCore] Unknown command hash: " + std::to_string(h));
    return false;
  }
}

void ScriptCore::getSearchRange(const std::string &argStart,
                                const std::string &argEnd,
                                const std::string &defStart,
                                const std::string &defEnd, uint64_t &outStart,
                                uint64_t &outEnd) {
  auto parseAddr = [](const std::string &s,
                      const std::string &def) -> uint64_t {
    if (s.empty() || s == "0") {
      if (def.empty())
        return 0;
      return std::strtoull(def.c_str(), nullptr, 16);
    }
    return std::strtoull(s.c_str(), nullptr, 16);
  };

  outStart = parseAddr(argStart, defStart.empty() ? "0x100000000" : defStart);
  outEnd = parseAddr(argEnd, defEnd.empty() ? "0x300000000" : defEnd);
}

} 
