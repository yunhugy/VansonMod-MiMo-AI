#ifndef AuditCore_hpp
#define AuditCore_hpp

#include <mach/mach.h>
#include <string>
#include <vector>
#include <cstdint>

namespace VMCore {

struct AuditModuleInfo {
  std::string name;
  std::string path;
  uint64_t loadAddress;
  uint32_t size;
  bool isSystem;       
  bool isEncrypted;    
};

struct TextDiffEntry {
  std::string moduleName;
  uint64_t offset;         
  uint64_t runtimeAddress; 
  std::vector<uint8_t> originalBytes;
  std::vector<uint8_t> currentBytes;
};

struct TextSnapshot {
  std::string moduleName;
  uint64_t textAddr;
  uint64_t textSize;
  std::vector<uint8_t> data;
};

class AuditCore {
public:
  static AuditCore &getInstance();

  std::vector<AuditModuleInfo> classifyModules(mach_port_t task);

  std::vector<TextDiffEntry> diffTextSegmentWithDisk(mach_port_t task,
                                                      const AuditModuleInfo &module);

  bool takeTextSnapshot(mach_port_t task,
                        const std::vector<AuditModuleInfo> &modules);

  std::vector<TextDiffEntry> diffTextSegmentWithSnapshot(mach_port_t task);

  bool hasSnapshot() const;

  void clearSnapshot();

  bool restoreBytes(mach_port_t task, uint64_t address,
                    const std::vector<uint8_t> &originalBytes);

  bool isMachOEncrypted(mach_port_t task, uint64_t loadAddress);

private:
  AuditCore() = default;
  ~AuditCore() = default;
  AuditCore(const AuditCore &) = delete;
  AuditCore &operator=(const AuditCore &) = delete;

  bool getTextSegmentInfo(mach_port_t task, uint64_t loadAddress,
                          uint64_t &segAddr, uint64_t &segSize,
                          uint64_t &segFileOffset);

  std::vector<uint8_t> readTextSegmentFromDisk(const std::string &path,
                                         uint64_t &fileOffset,
                                         uint64_t &size);

  std::vector<uint8_t> readRemoteMemory(mach_port_t task, uint64_t addr,
                                         uint64_t size);

  bool isSystemPath(const std::string &path);

  std::vector<TextSnapshot> _snapshots;
};

} 

#endif /* AuditCore_hpp */
