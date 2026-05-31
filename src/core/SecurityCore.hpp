#ifndef SecurityCore_hpp
#define SecurityCore_hpp

#include <string>
#include <vector>

namespace VMCore {

template <size_t N, char K> class XorStr {
public:
  constexpr XorStr(const char *str) : _data() {
    for (size_t i = 0; i < N; ++i) {
      _data[i] = str[i] ^ K;
    }
  }

  std::string decrypt() const {
    std::string result;
    result.reserve(N);
    for (size_t i = 0; i < N; ++i) {
      result += _data[i] ^ K;
    }
    return result;
  }

private:
  char _data[N];
};

#define SEC_STR(str)                                                           \
  []() {                                                                       \
    static constexpr VMCore::XorStr<sizeof(str), 0x42> s(str);                 \
    return s.decrypt();                                                        \
  }()

class SecurityCore {
public:
  static SecurityCore &getInstance();

  bool detectTampering();
  bool checkRuntimeIntegrity();
};

} 

#endif
