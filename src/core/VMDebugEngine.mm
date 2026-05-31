 
#import "VMDebugEngine.h"
#import "VMDebugCore.hpp"
#import "SystemCore.hpp"
#include <mach/mach.h>

@interface VMMemoryEngine : NSObject
+ (instancetype)shared;
@property (nonatomic, assign) mach_port_t targetTask;
- (BOOL)isDeviceJailbroken;
- (uint64_t)findModuleBaseAddress:(NSString *)moduleName;
@end

extern "C" {
kern_return_t mach_vm_read_overwrite(vm_map_t, mach_vm_address_t,
                                     mach_vm_size_t, mach_vm_address_t,
                                     mach_vm_size_t *);
}

using namespace VMDebug;

#pragma mark - Model Classes

@implementation VMStackFrame
@end

@implementation VMWatchHit
@end

#pragma mark - Lightweight ARM64 Disassembler

static const char *xreg(uint32_t r, bool is64) {
    static const char *x[] = {
        "X0","X1","X2","X3","X4","X5","X6","X7",
        "X8","X9","X10","X11","X12","X13","X14","X15",
        "X16","X17","X18","X19","X20","X21","X22","X23",
        "X24","X25","X26","X27","X28","X29","X30","XZR"
    };
    static const char *w[] = {
        "W0","W1","W2","W3","W4","W5","W6","W7",
        "W8","W9","W10","W11","W12","W13","W14","W15",
        "W16","W17","W18","W19","W20","W21","W22","W23",
        "W24","W25","W26","W27","W28","W29","W30","WZR"
    };
    if (r > 31) r = 31;
    return is64 ? x[r] : w[r];
}

static const char *spreg(uint32_t r, bool is64) {
    if (r == 31) return is64 ? "SP" : "WSP";
    return xreg(r, is64);
}

static int64_t signExtend(uint64_t val, uint32_t bits) {
    uint64_t mask = 1ULL << (bits - 1);
    return (int64_t)((val ^ mask) - mask);
}

static NSString *disasmOne(uint32_t insn, uint64_t pc) {
    char buf[128];

    if (insn == 0xD503201F) return @"NOP";

    if ((insn & 0xFFFFFC1F) == 0xD65F0000) {
        uint32_t rn = (insn >> 5) & 0x1F;
        if (rn == 30) return @"RET";
        snprintf(buf, sizeof(buf), "RET %s", xreg(rn, true));
        return [NSString stringWithUTF8String:buf];
    }

    if ((insn & 0xFFFFFC1F) == 0xD61F0000) {
        snprintf(buf, sizeof(buf), "BR %s", xreg((insn >> 5) & 0x1F, true));
        return [NSString stringWithUTF8String:buf];
    }
    if ((insn & 0xFFFFFC1F) == 0xD63F0000) {
        snprintf(buf, sizeof(buf), "BLR %s", xreg((insn >> 5) & 0x1F, true));
        return [NSString stringWithUTF8String:buf];
    }

    if ((insn & 0xFC000000) == 0x14000000) {
        int64_t off = signExtend(insn & 0x3FFFFFF, 26) * 4;
        snprintf(buf, sizeof(buf), "B 0x%llX", (unsigned long long)(pc + off));
        return [NSString stringWithUTF8String:buf];
    }

    if ((insn & 0xFC000000) == 0x94000000) {
        int64_t off = signExtend(insn & 0x3FFFFFF, 26) * 4;
        snprintf(buf, sizeof(buf), "BL 0x%llX", (unsigned long long)(pc + off));
        return [NSString stringWithUTF8String:buf];
    }

    if ((insn & 0xFF000010) == 0x54000000) {
        static const char *conds[] = {
            "EQ","NE","CS","CC","MI","PL","VS","VC",
            "HI","LS","GE","LT","GT","LE","AL","NV"
        };
        int64_t off = signExtend((insn >> 5) & 0x7FFFF, 19) * 4;
        snprintf(buf, sizeof(buf), "B.%s 0x%llX", conds[insn & 0xF],
                 (unsigned long long)(pc + off));
        return [NSString stringWithUTF8String:buf];
    }

    if ((insn & 0x7E000000) == 0x34000000) {
        bool is64 = (insn >> 31) & 1;
        bool isNZ = (insn >> 24) & 1;
        int64_t off = signExtend((insn >> 5) & 0x7FFFF, 19) * 4;
        snprintf(buf, sizeof(buf), "%s %s, 0x%llX",
                 isNZ ? "CBNZ" : "CBZ", xreg(insn & 0x1F, is64),
                 (unsigned long long)(pc + off));
        return [NSString stringWithUTF8String:buf];
    }

    if ((insn & 0x1F800000) == 0x12800000) {
        bool is64 = (insn >> 31) & 1;
        uint32_t opc = (insn >> 29) & 0x3;
        uint32_t hw = (insn >> 21) & 0x3;
        uint32_t imm16 = (insn >> 5) & 0xFFFF;
        uint32_t rd = insn & 0x1F;
        const char *op = (opc == 0) ? "MOVN" : (opc == 2) ? "MOVZ" : "MOVK";
        if (hw == 0 && opc == 2) {
            snprintf(buf, sizeof(buf), "MOV %s, #0x%X", xreg(rd, is64), imm16);
        } else {
            snprintf(buf, sizeof(buf), "%s %s, #0x%X, LSL #%u",
                     op, xreg(rd, is64), imm16, hw * 16);
        }
        return [NSString stringWithUTF8String:buf];
    }

    if ((insn & 0x1F000000) == 0x11000000) {
        bool is64 = (insn >> 31) & 1;
        bool isSub = (insn >> 30) & 1;
        bool setFlags = (insn >> 29) & 1;
        uint32_t sh = (insn >> 22) & 1;
        uint32_t imm12 = (insn >> 10) & 0xFFF;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t rd = insn & 0x1F;
        const char *op;
        if (setFlags && isSub && rd == 31) op = "CMP";
        else if (setFlags && !isSub && rd == 31) op = "CMN";
        else op = isSub ? (setFlags ? "SUBS" : "SUB") : (setFlags ? "ADDS" : "ADD");

        if (rd == 31 && setFlags) {
            snprintf(buf, sizeof(buf), "%s %s, #0x%X%s", op,
                     spreg(rn, is64), imm12, sh ? ", LSL #12" : "");
        } else {
            snprintf(buf, sizeof(buf), "%s %s, %s, #0x%X%s", op,
                     xreg(rd, is64), spreg(rn, is64), imm12,
                     sh ? ", LSL #12" : "");
        }
        return [NSString stringWithUTF8String:buf];
    }

    if ((insn & 0x3B200C00) == 0x39000000) {
        uint32_t size = (insn >> 30) & 0x3;
        bool isLoad = (insn >> 22) & 1;
        uint32_t imm12 = (insn >> 10) & 0xFFF;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t rt = insn & 0x1F;
        uint64_t offset = (uint64_t)imm12 << size;
        const char *op;
        if (isLoad) {
            switch (size) { case 0: op="LDRB"; break; case 1: op="LDRH"; break; default: op="LDR"; break; }
        } else {
            switch (size) { case 0: op="STRB"; break; case 1: op="STRH"; break; default: op="STR"; break; }
        }
        bool regIs64 = (size == 3);
        if (offset == 0) {
            snprintf(buf, sizeof(buf), "%s %s, [%s]", op, xreg(rt, regIs64), spreg(rn, true));
        } else {
            snprintf(buf, sizeof(buf), "%s %s, [%s, #0x%llX]", op,
                     xreg(rt, regIs64), spreg(rn, true), (unsigned long long)offset);
        }
        return [NSString stringWithUTF8String:buf];
    }

    // LDP/STP (all variants: signed offset, pre-index, post-index)
    if ((insn & 0x3E000000) == 0x28000000 || (insn & 0x3E000000) == 0x2C000000) {
        uint32_t indexMode = (insn >> 23) & 0x3; // 01=post, 10=signed-offset, 11=pre
        bool is64 = (insn >> 31) & 1;
        bool isLoad = (insn >> 22) & 1;
        int32_t imm7 = (int32_t)signExtend((insn >> 15) & 0x7F, 7);
        uint32_t rt2 = (insn >> 10) & 0x1F;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t rt = insn & 0x1F;
        int32_t off = imm7 * (is64 ? 8 : 4);
        const char *op = isLoad ? "LDP" : "STP";
        if (indexMode == 1) { // post-index
            snprintf(buf, sizeof(buf), "%s %s, %s, [%s], #%d", op,
                     xreg(rt, is64), xreg(rt2, is64), spreg(rn, true), off);
        } else if (indexMode == 3) { // pre-index
            snprintf(buf, sizeof(buf), "%s %s, %s, [%s, #%d]!", op,
                     xreg(rt, is64), xreg(rt2, is64), spreg(rn, true), off);
        } else { // signed offset
            if (off == 0) {
                snprintf(buf, sizeof(buf), "%s %s, %s, [%s]", op,
                         xreg(rt, is64), xreg(rt2, is64), spreg(rn, true));
            } else {
                snprintf(buf, sizeof(buf), "%s %s, %s, [%s, #%d]", op,
                         xreg(rt, is64), xreg(rt2, is64), spreg(rn, true), off);
            }
        }
        return [NSString stringWithUTF8String:buf];
    }

    if ((insn & 0x1F000000) == 0x0A000000) {
        bool is64 = (insn >> 31) & 1;
        uint32_t opc = (insn >> 29) & 0x3;
        bool N = (insn >> 21) & 1;
        uint32_t rm = (insn >> 16) & 0x1F;
        uint32_t imm6 = (insn >> 10) & 0x3F;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t rd = insn & 0x1F;
        if (opc == 1 && !N && rn == 31 && imm6 == 0) {
            snprintf(buf, sizeof(buf), "MOV %s, %s", xreg(rd, is64), xreg(rm, is64));
            return [NSString stringWithUTF8String:buf];
        }
        const char *op;
        if (opc == 0 && !N) op = "AND";
        else if (opc == 1 && !N) op = "ORR";
        else if (opc == 2 && !N) op = "EOR";
        else if (opc == 3 && !N) op = "ANDS";
        else op = "LOGIC";
        snprintf(buf, sizeof(buf), "%s %s, %s, %s", op,
                 xreg(rd, is64), xreg(rn, is64), xreg(rm, is64));
        return [NSString stringWithUTF8String:buf];
    }

    if ((insn & 0x1F200000) == 0x0B000000) {
        bool is64 = (insn >> 31) & 1;
        bool isSub = (insn >> 30) & 1;
        bool setFlags = (insn >> 29) & 1;
        uint32_t rm = (insn >> 16) & 0x1F;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t rd = insn & 0x1F;
        const char *op;
        if (setFlags && isSub && rd == 31) op = "CMP";
        else op = isSub ? (setFlags ? "SUBS" : "SUB") : (setFlags ? "ADDS" : "ADD");
        if (rd == 31 && setFlags) {
            snprintf(buf, sizeof(buf), "%s %s, %s", op, xreg(rn, is64), xreg(rm, is64));
        } else {
            snprintf(buf, sizeof(buf), "%s %s, %s, %s", op,
                     xreg(rd, is64), xreg(rn, is64), xreg(rm, is64));
        }
        return [NSString stringWithUTF8String:buf];
    }

    if ((insn & 0x9F000000) == 0x90000000) {
        uint32_t rd = insn & 0x1F;
        uint32_t immlo = (insn >> 29) & 0x3;
        uint32_t immhi = (insn >> 5) & 0x7FFFF;
        int64_t imm = signExtend(((uint64_t)immhi << 2) | immlo, 21) << 12;
        uint64_t target = (pc & ~0xFFFULL) + imm;
        snprintf(buf, sizeof(buf), "ADRP %s, 0x%llX", xreg(rd, true), (unsigned long long)target);
        return [NSString stringWithUTF8String:buf];
    }

    // ADR
    if ((insn & 0x9F000000) == 0x10000000) {
        uint32_t rd = insn & 0x1F;
        uint32_t immlo = (insn >> 29) & 0x3;
        uint32_t immhi = (insn >> 5) & 0x7FFFF;
        int64_t imm = signExtend(((uint64_t)immhi << 2) | immlo, 21);
        snprintf(buf, sizeof(buf), "ADR %s, 0x%llX", xreg(rd, true), (unsigned long long)(pc + imm));
        return [NSString stringWithUTF8String:buf];
    }

    // LDUR / STUR (unscaled immediate)
    if ((insn & 0x3B200C00) == 0x38000000) {
        uint32_t size = (insn >> 30) & 0x3;
        uint32_t opc = (insn >> 22) & 0x3;
        uint32_t kind = (insn >> 10) & 0x3; // 00=unscaled, 01=post, 11=pre
        int32_t imm9 = (int32_t)signExtend((insn >> 12) & 0x1FF, 9);
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t rt = insn & 0x1F;
        bool isLoad = (opc & 1);
        bool regIs64 = (size == 3);
        const char *op;
        if (kind == 0) { // unscaled
            if (isLoad) {
                if (opc == 1) { switch(size) { case 0: op="LDURB"; break; case 1: op="LDURH"; break; default: op="LDUR"; break; } }
                else if (opc == 3) { op = (size == 0) ? "LDURSB" : (size == 1) ? "LDURSH" : "LDURSW"; regIs64 = true; }
                else { op = "LDUR"; }
            } else {
                switch(size) { case 0: op="STURB"; break; case 1: op="STURH"; break; default: op="STUR"; break; }
            }
            if (imm9 == 0)
                snprintf(buf, sizeof(buf), "%s %s, [%s]", op, xreg(rt, regIs64), spreg(rn, true));
            else
                snprintf(buf, sizeof(buf), "%s %s, [%s, #%d]", op, xreg(rt, regIs64), spreg(rn, true), imm9);
        } else if (kind == 1) { // post-index
            if (isLoad) { switch(size) { case 0: op="LDRB"; break; case 1: op="LDRH"; break; default: op="LDR"; break; } }
            else { switch(size) { case 0: op="STRB"; break; case 1: op="STRH"; break; default: op="STR"; break; } }
            snprintf(buf, sizeof(buf), "%s %s, [%s], #%d", op, xreg(rt, regIs64), spreg(rn, true), imm9);
        } else { // pre-index (kind == 3)
            if (isLoad) { switch(size) { case 0: op="LDRB"; break; case 1: op="LDRH"; break; default: op="LDR"; break; } }
            else { switch(size) { case 0: op="STRB"; break; case 1: op="STRH"; break; default: op="STR"; break; } }
            snprintf(buf, sizeof(buf), "%s %s, [%s, #%d]!", op, xreg(rt, regIs64), spreg(rn, true), imm9);
        }
        return [NSString stringWithUTF8String:buf];
    }

    // LDR/STR (register offset)
    if ((insn & 0x3B200C00) == 0x38200800) {
        uint32_t size = (insn >> 30) & 0x3;
        bool isLoad = (insn >> 22) & 1;
        uint32_t rm = (insn >> 16) & 0x1F;
        uint32_t option = (insn >> 13) & 0x7;
        uint32_t S = (insn >> 12) & 1;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t rt = insn & 0x1F;
        bool regIs64 = (size == 3);
        const char *op;
        if (isLoad) { switch(size) { case 0: op="LDRB"; break; case 1: op="LDRH"; break; default: op="LDR"; break; } }
        else { switch(size) { case 0: op="STRB"; break; case 1: op="STRH"; break; default: op="STR"; break; } }
        bool rmIs64 = (option & 1);
        const char *ext = "";
        switch(option) {
            case 2: ext = "UXTW"; break; case 3: ext = "LSL"; break;
            case 6: ext = "SXTW"; break; case 7: ext = "SXTX"; break;
            default: ext = "LSL"; break;
        }
        if (S && size > 0)
            snprintf(buf, sizeof(buf), "%s %s, [%s, %s, %s #%u]", op, xreg(rt, regIs64), spreg(rn, true), xreg(rm, rmIs64), ext, size);
        else if (option == 3 && S == 0)
            snprintf(buf, sizeof(buf), "%s %s, [%s, %s]", op, xreg(rt, regIs64), spreg(rn, true), xreg(rm, rmIs64));
        else
            snprintf(buf, sizeof(buf), "%s %s, [%s, %s, %s]", op, xreg(rt, regIs64), spreg(rn, true), xreg(rm, rmIs64), ext);
        return [NSString stringWithUTF8String:buf];
    }

    // LDR (literal) - PC-relative
    if ((insn & 0x3B000000) == 0x18000000) {
        bool is64 = (insn >> 30) & 1;
        int64_t imm19 = signExtend((insn >> 5) & 0x7FFFF, 19) * 4;
        uint32_t rt = insn & 0x1F;
        uint64_t target = pc + imm19;
        snprintf(buf, sizeof(buf), "LDR %s, 0x%llX", xreg(rt, is64), (unsigned long long)target);
        return [NSString stringWithUTF8String:buf];
    }

    // CCMP / CCMN (immediate)
    if ((insn & 0x7FE00C10) == 0x7A400800) {
        bool is64 = (insn >> 31) & 1;
        bool isCCMN = !((insn >> 30) & 1);
        uint32_t imm5 = (insn >> 16) & 0x1F;
        uint32_t cond = (insn >> 12) & 0xF;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t nzcv = insn & 0xF;
        static const char *conds[] = {"EQ","NE","CS","CC","MI","PL","VS","VC","HI","LS","GE","LT","GT","LE","AL","NV"};
        snprintf(buf, sizeof(buf), "%s %s, #%u, #%u, %s", isCCMN ? "CCMN" : "CCMP",
                 xreg(rn, is64), imm5, nzcv, conds[cond]);
        return [NSString stringWithUTF8String:buf];
    }

    // CCMP / CCMN (register)
    if ((insn & 0x7FE00C10) == 0x7A400000) {
        bool is64 = (insn >> 31) & 1;
        bool isCCMN = !((insn >> 30) & 1);
        uint32_t rm = (insn >> 16) & 0x1F;
        uint32_t cond = (insn >> 12) & 0xF;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t nzcv = insn & 0xF;
        static const char *conds[] = {"EQ","NE","CS","CC","MI","PL","VS","VC","HI","LS","GE","LT","GT","LE","AL","NV"};
        snprintf(buf, sizeof(buf), "%s %s, %s, #%u, %s", isCCMN ? "CCMN" : "CCMP",
                 xreg(rn, is64), xreg(rm, is64), nzcv, conds[cond]);
        return [NSString stringWithUTF8String:buf];
    }

    // CSEL / CSINC / CSINV / CSNEG
    if ((insn & 0x1FE00000) == 0x1A800000) {
        bool is64 = (insn >> 31) & 1;
        uint32_t op2 = (insn >> 10) & 0x3;
        bool S = (insn >> 29) & 1;
        uint32_t rm = (insn >> 16) & 0x1F;
        uint32_t cond = (insn >> 12) & 0xF;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t rd = insn & 0x1F;
        static const char *conds[] = {"EQ","NE","CS","CC","MI","PL","VS","VC","HI","LS","GE","LT","GT","LE","AL","NV"};
        const char *op;
        if (!S && op2 == 0) op = "CSEL";
        else if (!S && op2 == 1) op = "CSINC";
        else if (S && op2 == 0) op = "CSINV";
        else op = "CSNEG";
        // Aliases
        if (!S && op2 == 1 && rn == 31 && rm == 31) {
            snprintf(buf, sizeof(buf), "CSET %s, %s", xreg(rd, is64), conds[cond ^ 1]);
        } else if (S && op2 == 0 && rn == 31 && rm == 31) {
            snprintf(buf, sizeof(buf), "CSETM %s, %s", xreg(rd, is64), conds[cond ^ 1]);
        } else if (!S && op2 == 1 && rn == rm && rn != 31) {
            snprintf(buf, sizeof(buf), "CINC %s, %s, %s", xreg(rd, is64), xreg(rn, is64), conds[cond ^ 1]);
        } else {
            snprintf(buf, sizeof(buf), "%s %s, %s, %s, %s", op, xreg(rd, is64), xreg(rn, is64), xreg(rm, is64), conds[cond]);
        }
        return [NSString stringWithUTF8String:buf];
    }

    // MADD / MSUB (MUL / MNEG aliases)
    if ((insn & 0x1F800000) == 0x1B000000) {
        bool is64 = (insn >> 31) & 1;
        uint32_t rm = (insn >> 16) & 0x1F;
        uint32_t o0 = (insn >> 15) & 1;
        uint32_t ra = (insn >> 10) & 0x1F;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t rd = insn & 0x1F;
        if (!o0 && ra == 31) {
            snprintf(buf, sizeof(buf), "MUL %s, %s, %s", xreg(rd, is64), xreg(rn, is64), xreg(rm, is64));
        } else if (o0 && ra == 31) {
            snprintf(buf, sizeof(buf), "MNEG %s, %s, %s", xreg(rd, is64), xreg(rn, is64), xreg(rm, is64));
        } else {
            snprintf(buf, sizeof(buf), "%s %s, %s, %s, %s", o0 ? "MSUB" : "MADD",
                     xreg(rd, is64), xreg(rn, is64), xreg(rm, is64), xreg(ra, is64));
        }
        return [NSString stringWithUTF8String:buf];
    }

    // UDIV / SDIV
    if ((insn & 0x1FE0FC00) == 0x1AC00800) {
        bool is64 = (insn >> 31) & 1;
        bool isSigned = (insn >> 10) & 1;
        uint32_t rm = (insn >> 16) & 0x1F;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t rd = insn & 0x1F;
        snprintf(buf, sizeof(buf), "%s %s, %s, %s", isSigned ? "SDIV" : "UDIV",
                 xreg(rd, is64), xreg(rn, is64), xreg(rm, is64));
        return [NSString stringWithUTF8String:buf];
    }

    // LSL / LSR / ASR / ROR (register)
    if ((insn & 0x1FE0F000) == 0x1AC02000) {
        bool is64 = (insn >> 31) & 1;
        uint32_t op2 = (insn >> 10) & 0x3;
        uint32_t rm = (insn >> 16) & 0x1F;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t rd = insn & 0x1F;
        const char *ops[] = {"LSL", "LSR", "ASR", "ROR"};
        snprintf(buf, sizeof(buf), "%s %s, %s, %s", ops[op2],
                 xreg(rd, is64), xreg(rn, is64), xreg(rm, is64));
        return [NSString stringWithUTF8String:buf];
    }

    // SBFM / BFM / UBFM (and aliases: SXTB, SXTH, SXTW, UXTB, UXTH, LSL#imm, LSR#imm, ASR#imm)
    if ((insn & 0x1F800000) == 0x13000000) {
        bool is64 = (insn >> 31) & 1;
        uint32_t opc = (insn >> 29) & 0x3;
        uint32_t immr = (insn >> 16) & 0x3F;
        uint32_t imms = (insn >> 10) & 0x3F;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t rd = insn & 0x1F;
        uint32_t regWidth = is64 ? 64 : 32;
        // SBFM aliases
        if (opc == 0) {
            if (imms == 7) { snprintf(buf, sizeof(buf), "SXTB %s, %s", xreg(rd, is64), xreg(rn, false)); return [NSString stringWithUTF8String:buf]; }
            if (imms == 15) { snprintf(buf, sizeof(buf), "SXTH %s, %s", xreg(rd, is64), xreg(rn, false)); return [NSString stringWithUTF8String:buf]; }
            if (imms == 31 && is64) { snprintf(buf, sizeof(buf), "SXTW %s, %s", xreg(rd, true), xreg(rn, false)); return [NSString stringWithUTF8String:buf]; }
            if (imms == regWidth - 1) { snprintf(buf, sizeof(buf), "ASR %s, %s, #%u", xreg(rd, is64), xreg(rn, is64), immr); return [NSString stringWithUTF8String:buf]; }
            snprintf(buf, sizeof(buf), "SBFX %s, %s, #%u, #%u", xreg(rd, is64), xreg(rn, is64), immr, imms - immr + 1);
        }
        // BFM
        else if (opc == 1) {
            snprintf(buf, sizeof(buf), "BFM %s, %s, #%u, #%u", xreg(rd, is64), xreg(rn, is64), immr, imms);
        }
        // UBFM aliases
        else {
            if (imms == 7 && immr == 0) { snprintf(buf, sizeof(buf), "UXTB %s, %s", xreg(rd, false), xreg(rn, false)); return [NSString stringWithUTF8String:buf]; }
            if (imms == 15 && immr == 0) { snprintf(buf, sizeof(buf), "UXTH %s, %s", xreg(rd, false), xreg(rn, false)); return [NSString stringWithUTF8String:buf]; }
            if (imms == regWidth - 1) { snprintf(buf, sizeof(buf), "LSR %s, %s, #%u", xreg(rd, is64), xreg(rn, is64), immr); return [NSString stringWithUTF8String:buf]; }
            if (imms + 1 == immr) { snprintf(buf, sizeof(buf), "LSL %s, %s, #%u", xreg(rd, is64), xreg(rn, is64), regWidth - immr); return [NSString stringWithUTF8String:buf]; }
            snprintf(buf, sizeof(buf), "UBFX %s, %s, #%u, #%u", xreg(rd, is64), xreg(rn, is64), immr, imms - immr + 1);
        }
        return [NSString stringWithUTF8String:buf];
    }

    // TBNZ / TBZ
    if ((insn & 0x7E000000) == 0x36000000) {
        bool isNZ = (insn >> 24) & 1;
        uint32_t b5 = (insn >> 31) & 1;
        uint32_t b40 = (insn >> 19) & 0x1F;
        uint32_t bit = (b5 << 5) | b40;
        int64_t off = signExtend((insn >> 5) & 0x3FFF, 14) * 4;
        uint32_t rt = insn & 0x1F;
        snprintf(buf, sizeof(buf), "%s %s, #%u, 0x%llX", isNZ ? "TBNZ" : "TBZ",
                 xreg(rt, bit >= 32), bit, (unsigned long long)(pc + off));
        return [NSString stringWithUTF8String:buf];
    }

    // MRS / MSR
    if ((insn & 0xFFF00000) == 0xD5300000) {
        uint32_t rt = insn & 0x1F;
        uint32_t sysreg = (insn >> 5) & 0x7FFF;
        snprintf(buf, sizeof(buf), "MRS %s, S%u_%u_C%u_C%u_%u", xreg(rt, true),
                 (sysreg >> 14) & 1, (sysreg >> 11) & 0x7,
                 (sysreg >> 7) & 0xF, (sysreg >> 3) & 0xF, sysreg & 0x7);
        return [NSString stringWithUTF8String:buf];
    }
    if ((insn & 0xFFF00000) == 0xD5100000) {
        uint32_t rt = insn & 0x1F;
        uint32_t sysreg = (insn >> 5) & 0x7FFF;
        snprintf(buf, sizeof(buf), "MSR S%u_%u_C%u_C%u_%u, %s",
                 (sysreg >> 14) & 1, (sysreg >> 11) & 0x7,
                 (sysreg >> 7) & 0xF, (sysreg >> 3) & 0xF, sysreg & 0x7, xreg(rt, true));
        return [NSString stringWithUTF8String:buf];
    }

    // SVC / BRK / HLT
    if ((insn & 0xFFE0001F) == 0xD4000001) {
        snprintf(buf, sizeof(buf), "SVC #0x%X", (insn >> 5) & 0xFFFF);
        return [NSString stringWithUTF8String:buf];
    }
    if ((insn & 0xFFE0001F) == 0xD4200000) {
        snprintf(buf, sizeof(buf), "BRK #0x%X", (insn >> 5) & 0xFFFF);
        return [NSString stringWithUTF8String:buf];
    }

    // EXTR (and ROR immediate alias)
    if ((insn & 0x1F800000) == 0x13800000) {
        bool is64 = (insn >> 31) & 1;
        uint32_t rm = (insn >> 16) & 0x1F;
        uint32_t imms = (insn >> 10) & 0x3F;
        uint32_t rn = (insn >> 5) & 0x1F;
        uint32_t rd = insn & 0x1F;
        if (rn == rm) {
            snprintf(buf, sizeof(buf), "ROR %s, %s, #%u", xreg(rd, is64), xreg(rn, is64), imms);
        } else {
            snprintf(buf, sizeof(buf), "EXTR %s, %s, %s, #%u", xreg(rd, is64), xreg(rn, is64), xreg(rm, is64), imms);
        }
        return [NSString stringWithUTF8String:buf];
    }

    // CLZ / CLS / RBIT / REV
    if ((insn & 0x7FE0FC00) == 0x5AC00000) {
        uint32_t opcode2 = (insn >> 10) & 0x3F;
        if (opcode2 <= 5) {
            bool is64 = (insn >> 31) & 1;
            uint32_t rn = (insn >> 5) & 0x1F;
            uint32_t rd = insn & 0x1F;
            const char *op;
            switch(opcode2) { case 0: op="RBIT"; break; case 1: op="REV16"; break; case 2: op=is64?"REV32":"REV"; break; case 3: op="REV"; break; case 4: op="CLZ"; break; case 5: op="CLS"; break; default: op="???"; break; }
            snprintf(buf, sizeof(buf), "%s %s, %s", op, xreg(rd, is64), xreg(rn, is64));
            return [NSString stringWithUTF8String:buf];
        }
    }

    // DMB / DSB / ISB
    if (insn == 0xD5033BBF) return @"DMB ISH";
    if (insn == 0xD5033B9F) return @"DSB ISH";
    if (insn == 0xD5033FDF) return @"ISB";

    snprintf(buf, sizeof(buf), ".inst 0x%08X", insn);
    return [NSString stringWithUTF8String:buf];
}

#pragma mark - VMDebugEngine

@implementation VMDebugEngine

+ (instancetype)shared {
    static VMDebugEngine *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VMDebugEngine alloc] init];
    });
    return instance;
}

+ (BOOL)isAvailable {
    return [[VMMemoryEngine shared] isDeviceJailbroken];
}

- (BOOL)attach {
    mach_port_t task = [VMMemoryEngine shared].targetTask;
    if (task == MACH_PORT_NULL) return NO;
    return DebugCore::inst().attach(task);
}

- (void)detach {
    DebugCore::inst().detach();
}

- (BOOL)isAttached {
    return DebugCore::inst().isAttached();
}

- (mach_port_t)currentTask {
    return DebugCore::inst().currentTask();
}

- (int)addWatchpoint:(uint64_t)address type:(VMWatchType)type size:(VMWatchSize)size {
    return DebugCore::inst().addWatch(address, (WatchType)type, (WatchSize)size);
}

- (BOOL)removeWatchpoint:(uint32_t)index {
    return DebugCore::inst().removeWatch(index);
}

- (void)removeAllWatchpoints {
    DebugCore::inst().removeAll();
}

- (uint32_t)activeCount {
    return DebugCore::inst().activeCount();
}

- (uint32_t)maxSlots {
    return DebugCore::MAX_SLOTS;
}

- (BOOL)isSlotActive:(uint32_t)index {
    auto &slots = DebugCore::inst().getSlots();
    if (index >= slots.size()) return NO;
    return slots[index].active;
}

- (uint64_t)slotAddress:(uint32_t)index {
    auto &slots = DebugCore::inst().getSlots();
    if (index >= slots.size()) return 0;
    return slots[index].address;
}

- (NSArray<VMWatchHit *> *)hitsForSlot:(uint32_t)index {
    auto &cppHits = DebugCore::inst().getHits(index);
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:cppHits.size()];
    for (auto &h : cppHits) {
        VMWatchHit *hit = [[VMWatchHit alloc] init];
        hit.slotIndex = h.wpIndex;
        hit.pc = h.pc;
        hit.address = h.address;
        hit.newValue = h.newValue;
        hit.imageName = [NSString stringWithUTF8String:h.imageName.c_str()];
        hit.offset = h.offset;
        hit.timestamp = h.timestamp;
        hit.stackTrace = @[];
        [result addObject:hit];
    }
    return result;
}

- (void)clearHitsForSlot:(uint32_t)index {
    DebugCore::inst().clearHits(index);
}

- (void)clearAllHits {
    DebugCore::inst().clearAllHits();
}

- (void)setHitCallback:(VMWatchHitBlock)hitCallback {
    _hitCallback = hitCallback;
    if (hitCallback) {
        __weak VMDebugEngine *ws = self;
        DebugCore::inst().setHitCallback([ws](const WatchHit &h) {
            VMDebugEngine *ss = ws;
            if (!ss || !ss.hitCallback) return;
            VMWatchHit *hit = [[VMWatchHit alloc] init];
            hit.slotIndex = h.wpIndex;
            hit.pc = h.pc;
            hit.address = h.address;
            hit.newValue = h.newValue;
            hit.imageName = [NSString stringWithUTF8String:h.imageName.c_str()];
            hit.offset = h.offset;
            hit.timestamp = h.timestamp;
            hit.stackTrace = @[];
            dispatch_async(dispatch_get_main_queue(), ^{
                ss.hitCallback(hit);
            });
        });
    } else {
        DebugCore::inst().setHitCallback(nullptr);
    }
}

#pragma mark - Cross-Process Disassembly

- (NSArray<NSDictionary *> *)disassembleAt:(uint64_t)address
                               countBefore:(uint32_t)before
                                countAfter:(uint32_t)after
                                moduleName:(NSString *)moduleName {
    mach_port_t task = [VMMemoryEngine shared].targetTask;
    if (task == MACH_PORT_NULL) return @[];

    uint64_t imageBase = 0;
    if (moduleName) {
        imageBase = [[VMMemoryEngine shared] findModuleBaseAddress:moduleName];
    }

    uint64_t startAddr = address - (uint64_t)before * 4;
    uint32_t totalCount = before + 1 + after;
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:totalCount];

    for (uint32_t i = 0; i < totalCount; i++) {
        uint64_t curAddr = startAddr + (uint64_t)i * 4;
        uint64_t offset = (imageBase != 0) ? (curAddr - imageBase) : curAddr;
        BOOL isPC = (curAddr == address);

        uint32_t opcode = 0;
        mach_vm_size_t readSize = 4;
        kern_return_t kr = mach_vm_read_overwrite(task, curAddr, 4,
                                                   (mach_vm_address_t)&opcode, &readSize);

        NSString *hex, *mnemonic;
        if (kr == KERN_SUCCESS && readSize == 4) {
            hex = [NSString stringWithFormat:@"%02X%02X%02X%02X",
                   opcode & 0xFF, (opcode >> 8) & 0xFF,
                   (opcode >> 16) & 0xFF, (opcode >> 24) & 0xFF];
            mnemonic = disasmOne(opcode, curAddr);
        } else {
            hex = @"????????";
            mnemonic = @"???";
        }

        [result addObject:@{
            @"address": @(curAddr),
            @"offset": @(offset),
            @"opcode": @(opcode),
            @"hex": hex,
            @"mnemonic": mnemonic,
            @"isPC": @(isPC)
        }];
    }
    return result;
}

#pragma mark - Function-Level Disassembly

static bool isARM64Prologue(uint32_t insn) {
    
    if ((insn & 0xFFE07FFF) == 0xA9807BFD) return true;
    if ((insn & 0xFFC07FFF) == 0xA9007BFD) return true;
    
    if ((insn & 0xFF0003FF) == 0xD10003FF) return true;
    
    if (insn == 0xD503237F) return true;
    return false;
}

static bool isARM64Epilogue(uint32_t insn) {
    
    if ((insn & 0xFFFFFC1F) == 0xD65F0000) return true;
    
    if (insn == 0xD65F0FFF || insn == 0xD65F0BFF) return true;
    return false;
}

- (NSArray<NSDictionary *> *)disassembleFunctionAt:(uint64_t)pc
                                        moduleName:(NSString *)moduleName {
    mach_port_t task = [VMMemoryEngine shared].targetTask;
    if (task == MACH_PORT_NULL) return @[];

    static const uint32_t MAX_SCAN = 256;
    static const uint32_t BULK_READ = 256;

    uint64_t imageBase = 0;
    if (moduleName) {
        imageBase = [[VMMemoryEngine shared] findModuleBaseAddress:moduleName];
    }

    uint64_t funcStart = pc;
    {
        uint32_t scanned = 0;
        uint64_t scanAddr = pc;
        while (scanned < MAX_SCAN) {
            uint32_t chunk = MIN(BULK_READ, MAX_SCAN - scanned);
            uint64_t readStart = scanAddr - (uint64_t)chunk * 4;

            uint32_t buf[BULK_READ];
            mach_vm_size_t readSize = chunk * 4;
            kern_return_t kr = mach_vm_read_overwrite(task, readStart, readSize,
                                                       (mach_vm_address_t)buf, &readSize);
            if (kr != KERN_SUCCESS || readSize < 4) break;

            uint32_t validCount = (uint32_t)(readSize / 4);
            for (int32_t i = validCount - 1; i >= 0; i--) {
                if (isARM64Prologue(buf[i])) {
                    funcStart = readStart + (uint64_t)i * 4;
                    goto foundStart;
                }
            }
            scanned += validCount;
            scanAddr = readStart;
        }
        funcStart = pc - MIN((uint64_t)64 * 4, pc);
    }
foundStart:;

    uint64_t funcEnd = pc;
    {
        uint32_t scanned = 0;
        uint64_t scanAddr = pc;
        while (scanned < MAX_SCAN) {
            uint32_t chunk = MIN(BULK_READ, MAX_SCAN - scanned);

            uint32_t buf[BULK_READ];
            mach_vm_size_t readSize = chunk * 4;
            kern_return_t kr = mach_vm_read_overwrite(task, scanAddr, readSize,
                                                       (mach_vm_address_t)buf, &readSize);
            if (kr != KERN_SUCCESS || readSize < 4) break;

            uint32_t validCount = (uint32_t)(readSize / 4);
            for (uint32_t i = 0; i < validCount; i++) {
                if (isARM64Epilogue(buf[i])) {
                    funcEnd = scanAddr + (uint64_t)i * 4;
                    goto foundEnd;
                }
            }
            scanned += validCount;
            scanAddr += (uint64_t)validCount * 4;
        }
        funcEnd = pc + 64 * 4;
    }
foundEnd:;

    uint32_t totalInsns = (uint32_t)((funcEnd - funcStart) / 4) + 1;
    if (totalInsns > 1024) totalInsns = 1024;

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:totalInsns];
    uint32_t *codeBuf = (uint32_t *)malloc(totalInsns * 4);
    if (!codeBuf) return @[];

    mach_vm_size_t totalReadSize = totalInsns * 4;
    kern_return_t kr = mach_vm_read_overwrite(task, funcStart, totalReadSize,
                                               (mach_vm_address_t)codeBuf, &totalReadSize);
    uint32_t readInsns = (kr == KERN_SUCCESS) ? (uint32_t)(totalReadSize / 4) : 0;

    for (uint32_t i = 0; i < totalInsns; i++) {
        uint64_t curAddr = funcStart + (uint64_t)i * 4;
        uint64_t offset = (imageBase != 0) ? (curAddr - imageBase) : curAddr;
        BOOL isPC = (curAddr == pc);

        NSString *hex, *mnemonic;
        if (i < readInsns) {
            uint32_t opcode = codeBuf[i];
            hex = [NSString stringWithFormat:@"%02X%02X%02X%02X",
                   opcode & 0xFF, (opcode >> 8) & 0xFF,
                   (opcode >> 16) & 0xFF, (opcode >> 24) & 0xFF];
            mnemonic = disasmOne(opcode, curAddr);
        } else {
            hex = @"????????";
            mnemonic = @"???";
        }

        [result addObject:@{
            @"address": @(curAddr),
            @"offset": @(offset),
            @"opcode": @(i < readInsns ? codeBuf[i] : 0),
            @"hex": hex,
            @"mnemonic": mnemonic,
            @"isPC": @(isPC)
        }];
    }

    free(codeBuf);
    return result;
}

@end
