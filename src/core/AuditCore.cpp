#include "AuditCore.hpp"
#include "SystemCore.hpp"
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <cstring>
#include <fstream>
#include <algorithm>

extern "C" {
kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t,
                                     mach_vm_size_t, mach_vm_address_t,
                                     mach_vm_size_t *);
kern_return_t mach_vm_write(vm_map_t, mach_vm_address_t, vm_offset_t,
                            mach_msg_type_number_t);
kern_return_t mach_vm_protect(vm_map_t, mach_vm_address_t, mach_vm_size_t,
                              boolean_t, vm_prot_t);
}

namespace VMCore {

AuditCore &AuditCore::getInstance() {
  static AuditCore instance;
  return instance;
}

bool AuditCore::isSystemPath(const std::string &path) {
  
  static const char *systemPrefixes[] = {
    "/usr/lib/",
    "/System/",
    "/Developer/",
    "/private/preboot/Cryptex",
  };
  for (auto prefix : systemPrefixes) {
    if (path.compare(0, strlen(prefix), prefix) == 0)
      return true;
  }
  
  if (path.find("/dyld_shared_cache") != std::string::npos)
    return true;
  return false;
}

std::vector<AuditModuleInfo> AuditCore::classifyModules(mach_port_t task) {
  std::vector<AuditModuleInfo> result;
  if (task == MACH_PORT_NULL) return result;

  auto modules = SystemCore::getInstance().getRemoteModules(task);
  for (auto &m : modules) {
    AuditModuleInfo info;
    info.name = m.name;
    info.path = m.path;
    info.loadAddress = m.loadAddress;
    info.size = m.size;
    info.isSystem = isSystemPath(m.path);
    info.isEncrypted = isMachOEncrypted(task, m.loadAddress);
    result.push_back(info);
  }
  return result;
}

bool AuditCore::isMachOEncrypted(mach_port_t task, uint64_t loadAddress) {
  struct mach_header_64 header;
  mach_vm_size_t readSize = sizeof(header);
  if (mach_vm_read_overwrite(task, loadAddress, readSize,
                             (mach_vm_address_t)&header,
                             &readSize) != KERN_SUCCESS)
    return false;
  if (header.magic != MH_MAGIC_64) return false;

  uint32_t sizeofcmds = header.sizeofcmds;
  std::vector<uint8_t> cmds(sizeofcmds);
  mach_vm_size_t cmdsRead = sizeofcmds;
  if (mach_vm_read_overwrite(task, loadAddress + sizeof(header), sizeofcmds,
                             (mach_vm_address_t)cmds.data(),
                             &cmdsRead) != KERN_SUCCESS)
    return false;

  uint8_t *cursor = cmds.data();
  for (uint32_t i = 0; i < header.ncmds; i++) {
    struct load_command *lc = (struct load_command *)cursor;
    if (lc->cmd == LC_ENCRYPTION_INFO_64) {
      struct encryption_info_command_64 *enc =
          (struct encryption_info_command_64 *)lc;
      return enc->cryptid != 0;
    }
    cursor += lc->cmdsize;
    if (cursor >= cmds.data() + sizeofcmds) break;
  }
  return false;
}

bool AuditCore::getTextSegmentInfo(mach_port_t task, uint64_t loadAddress,
                                    uint64_t &segAddr, uint64_t &segSize,
                                    uint64_t &segFileOffset) {
  struct mach_header_64 header;
  mach_vm_size_t readSize = sizeof(header);
  if (mach_vm_read_overwrite(task, loadAddress, readSize,
                             (mach_vm_address_t)&header,
                             &readSize) != KERN_SUCCESS)
    return false;
  if (header.magic != MH_MAGIC_64) return false;

  uint32_t sizeofcmds = header.sizeofcmds;
  std::vector<uint8_t> cmds(sizeofcmds);
  mach_vm_size_t cmdsRead = sizeofcmds;
  if (mach_vm_read_overwrite(task, loadAddress + sizeof(header), sizeofcmds,
                             (mach_vm_address_t)cmds.data(),
                             &cmdsRead) != KERN_SUCCESS)
    return false;

  uint8_t *cursor = cmds.data();
  for (uint32_t i = 0; i < header.ncmds; i++) {
    struct load_command *lc = (struct load_command *)cursor;
    if (lc->cmd == LC_SEGMENT_64) {
      struct segment_command_64 *seg = (struct segment_command_64 *)lc;
      if (strcmp(seg->segname, "__TEXT") == 0) {
        uint64_t slide = loadAddress - seg->vmaddr;
        segAddr = seg->vmaddr + slide;
        segSize = seg->vmsize;
        segFileOffset = seg->fileoff;
        return true;
      }
    }
    cursor += lc->cmdsize;
    if (cursor >= cmds.data() + sizeofcmds) break;
  }
  return false;
}

std::vector<uint8_t> AuditCore::readRemoteMemory(mach_port_t task,
                                                   uint64_t addr,
                                                   uint64_t size) {
  std::vector<uint8_t> result;
  if (task == MACH_PORT_NULL || size == 0) return result;

  result.resize(size);
  mach_vm_size_t readSize = size;
  if (mach_vm_read_overwrite(task, addr, size,
                             (mach_vm_address_t)result.data(),
                             &readSize) != KERN_SUCCESS) {
    result.clear();
    return result;
  }
  result.resize(readSize);
  return result;
}

std::vector<uint8_t> AuditCore::readTextSegmentFromDisk(const std::string &path,
                                                   uint64_t &fileOffset,
                                                   uint64_t &size) {
  std::vector<uint8_t> result;
  std::ifstream file(path, std::ios::binary);
  if (!file.is_open()) return result;

  struct mach_header_64 header;
  file.read((char *)&header, sizeof(header));
  if (header.magic != MH_MAGIC_64) return result;

  std::vector<uint8_t> cmds(header.sizeofcmds);
  file.read((char *)cmds.data(), header.sizeofcmds);

  uint8_t *cursor = cmds.data();
  for (uint32_t i = 0; i < header.ncmds; i++) {
    struct load_command *lc = (struct load_command *)cursor;
    if (lc->cmd == LC_SEGMENT_64) {
      struct segment_command_64 *seg = (struct segment_command_64 *)lc;
      if (strcmp(seg->segname, "__TEXT") == 0) {
        fileOffset = seg->fileoff;
        size = seg->filesize;
        result.resize(size);
        file.seekg(fileOffset);
        file.read((char *)result.data(), size);
        if ((uint64_t)file.gcount() != size) {
          result.clear();
        }
        return result;
      }
    }
    cursor += lc->cmdsize;
    if (cursor >= cmds.data() + header.sizeofcmds) break;
  }
  return result;
}

std::vector<TextDiffEntry> AuditCore::diffTextSegmentWithDisk(
    mach_port_t task, const AuditModuleInfo &module) {
  std::vector<TextDiffEntry> diffs;
  if (task == MACH_PORT_NULL) return diffs;

  uint64_t textAddr = 0, textSize = 0, textFileOffset = 0;
  if (!getTextSegmentInfo(task, module.loadAddress, textAddr, textSize,
                          textFileOffset))
    return diffs;

  if (textSize == 0 || textSize > 100 * 1024 * 1024) return diffs;

  auto memData = readRemoteMemory(task, textAddr, textSize);
  if (memData.empty()) return diffs;

  uint64_t diskOffset = 0, diskSize = 0;
  auto diskData = readTextSegmentFromDisk(module.path, diskOffset, diskSize);
  if (diskData.empty()) return diffs;

  uint64_t cmpSize = std::min(memData.size(), diskData.size());

  uint64_t i = 0;
  while (i < cmpSize) {
    if (memData[i] != diskData[i]) {
      uint64_t aligned = i & ~(uint64_t)3;

      TextDiffEntry entry;
      entry.moduleName = module.name;
      entry.offset = aligned;
      entry.runtimeAddress = textAddr + aligned;

      uint64_t end = aligned + 4;
      if (end > cmpSize) end = cmpSize;

      entry.originalBytes.assign(diskData.begin() + aligned,
                                  diskData.begin() + end);
      entry.currentBytes.assign(memData.begin() + aligned,
                                 memData.begin() + end);
      diffs.push_back(entry);
      i = end;
    } else {
      i++;
    }
  }
  return diffs;
}

bool AuditCore::takeTextSnapshot(mach_port_t task,
                                  const std::vector<AuditModuleInfo> &modules) {
  if (task == MACH_PORT_NULL) return false;

  _snapshots.clear();

  for (auto &mod : modules) {
    if (mod.isSystem) continue;

    uint64_t textAddr = 0, textSize = 0, textFileOffset = 0;
    if (!getTextSegmentInfo(task, mod.loadAddress, textAddr, textSize,
                            textFileOffset))
      continue;

    if (textSize == 0 || textSize > 100 * 1024 * 1024) continue;

    auto data = readRemoteMemory(task, textAddr, textSize);
    if (data.empty()) continue;

    TextSnapshot snap;
    snap.moduleName = mod.name;
    snap.textAddr = textAddr;
    snap.textSize = textSize;
    snap.data = std::move(data);
    _snapshots.push_back(std::move(snap));
  }

  return !_snapshots.empty();
}

std::vector<TextDiffEntry> AuditCore::diffTextSegmentWithSnapshot(
    mach_port_t task) {
  std::vector<TextDiffEntry> diffs;
  if (task == MACH_PORT_NULL || _snapshots.empty()) return diffs;

  for (auto &snap : _snapshots) {
    auto currentData = readRemoteMemory(task, snap.textAddr, snap.textSize);
    if (currentData.empty()) continue;

    uint64_t cmpSize = std::min(currentData.size(), snap.data.size());
    uint64_t i = 0;
    while (i < cmpSize) {
      if (currentData[i] != snap.data[i]) {
        uint64_t aligned = i & ~(uint64_t)3;

        TextDiffEntry entry;
        entry.moduleName = snap.moduleName;
        entry.offset = aligned;
        entry.runtimeAddress = snap.textAddr + aligned;

        uint64_t end = aligned + 4;
        if (end > cmpSize) end = cmpSize;

        entry.originalBytes.assign(snap.data.begin() + aligned,
                                    snap.data.begin() + end);
        entry.currentBytes.assign(currentData.begin() + aligned,
                                   currentData.begin() + end);
        diffs.push_back(entry);
        i = end;
      } else {
        i++;
      }
    }
  }
  return diffs;
}

bool AuditCore::hasSnapshot() const {
  return !_snapshots.empty();
}

void AuditCore::clearSnapshot() {
  _snapshots.clear();
}

bool AuditCore::restoreBytes(mach_port_t task, uint64_t address,
                              const std::vector<uint8_t> &originalBytes) {
  if (task == MACH_PORT_NULL || originalBytes.empty()) return false;

  kern_return_t kr = mach_vm_write(
      task, address, (vm_offset_t)originalBytes.data(),
      (mach_msg_type_number_t)originalBytes.size());

  if (kr != KERN_SUCCESS) {
    
    mach_vm_protect(task, address, originalBytes.size(), FALSE,
                    VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    kr = mach_vm_write(task, address, (vm_offset_t)originalBytes.data(),
                       (mach_msg_type_number_t)originalBytes.size());
    mach_vm_protect(task, address, originalBytes.size(), FALSE,
                    VM_PROT_READ | VM_PROT_EXECUTE);
  }
  return kr == KERN_SUCCESS;
}

} 
