#pragma once

#include <cstdint>
#include <string>
#include <vector>

class PointerCore {
public:
  static PointerCore &getInstance();

  PointerCore(const PointerCore &) = delete;
  PointerCore &operator=(const PointerCore &) = delete;

  std::string getVerifierFolder();

  std::vector<std::string> getSavedApps();

  std::string generateUniquePath(const std::string &folder,
                                 const std::string &baseName,
                                 const std::string &ext);

  std::string saveChains(const std::string &bundleID, const uint8_t *data,
                         size_t dataSize, size_t chainCount);

  std::vector<uint8_t> loadChainsData(const std::string &filePath);

private:
  PointerCore() = default;
  ~PointerCore() = default;
};
