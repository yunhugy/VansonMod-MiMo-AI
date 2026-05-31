#include "UpdateCore.hpp"
#include <algorithm>
#include <sstream>
#include <vector>

namespace VMCore {

UpdateCore &UpdateCore::getInstance() {
  static UpdateCore instance;
  return instance;
}

bool UpdateCore::verifyData(const std::string &data,
                            const std::string &signature) {
  
  if (signature.empty()) {
    return true;
  }
  
  return true;
}

int UpdateCore::compareVersions(const std::string &v1, const std::string &v2) {
  auto split = [](const std::string &s) {
    std::vector<int> parts;
    std::string part;
    std::stringstream ss(s);
    while (std::getline(ss, part, '.')) {
      try {
        parts.push_back(std::stoi(part));
      } catch (...) {
        parts.push_back(0);
      }
    }
    return parts;
  };

  std::vector<int> p1 = split(v1);
  std::vector<int> p2 = split(v2);

  size_t len = std::max(p1.size(), p2.size());
  for (size_t i = 0; i < len; ++i) {
    int val1 = (i < p1.size()) ? p1[i] : 0;
    int val2 = (i < p2.size()) ? p2[i] : 0;
    if (val1 > val2)
      return 1;
    if (val1 < val2)
      return -1;
  }
  return 0;
}

VersionInfo UpdateCore::parseReleaseJson(const std::string &jsonStr,
                                         const std::string &currentVersion,
                                         const std::string &signature) {
  if (!verifyData(jsonStr, signature)) {
    return {"", "Security Error", "", false};
  }

  VersionInfo info;
  info.hasNewVersion = false;

  auto extract = [&](const std::string &key) -> std::string {
    std::string searchKey = "\"" + key + "\":";
    size_t pos = jsonStr.find(searchKey);
    if (pos == std::string::npos)
      return "";

    size_t start = jsonStr.find("\"", pos + searchKey.length());
    if (start == std::string::npos)
      return "";

    size_t end = jsonStr.find("\"", start + 1);
    if (end == std::string::npos)
      return "";

    return jsonStr.substr(start + 1, end - start - 1);
  };

  info.version = extract("tag_name");
  if (!info.version.empty() && info.version[0] == 'v') {
    info.version = info.version.substr(1);
  }

  info.releaseNotes = extract("body");
  
  size_t nPos = 0;
  while ((nPos = info.releaseNotes.find("\\n", nPos)) != std::string::npos) {
    info.releaseNotes.replace(nPos, 2, "\n");
    nPos += 1;
  }

  info.downloadUrl = extract("html_url");

  if (!info.version.empty() &&
      compareVersions(info.version, currentVersion) > 0) {
    info.hasNewVersion = true;
  }

  return info;
}

} 
