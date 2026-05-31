#ifndef UpdateCore_hpp
#define UpdateCore_hpp

#include <string>

namespace VMCore {

struct VersionInfo {
  std::string version;
  std::string releaseNotes;
  std::string downloadUrl;
  bool hasNewVersion;
};

class UpdateCore {
public:
  static UpdateCore &getInstance();

  int compareVersions(const std::string &v1, const std::string &v2);

  VersionInfo parseReleaseJson(const std::string &jsonStr,
                               const std::string &currentVersion,
                               const std::string &signature = "");

  void setPublicKey(const std::string &pemKey);

  bool verifyData(const std::string &data, const std::string &signature);

private:
  UpdateCore() = default;
};

} 

#endif /* UpdateCore_hpp */
