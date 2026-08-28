#include "CDirect2DInterop.h"

#include <bcrypt.h>
#include <dwrite_3.h>
#include <shlobj.h>

#include <array>
#include <cmath>
#include <cstddef>
#include <cstring>

namespace {

constexpr uint64_t kMaximumFileBytes = SWU_BITMAP_FONT_MAX_FILE_BYTES;
constexpr uint64_t kMaximumSessionBytes = SWU_BITMAP_FONT_MAX_SESSION_BYTES;
constexpr size_t kMaximumHeldObjects = 1 + SWU_BITMAP_FONT_MAX_PATH_UNITS / 2;
constexpr size_t kMaximumDeviceUnits = 64;
using PathBuffer = std::array<wchar_t, SWU_BITMAP_FONT_MAX_PATH_UNITS + 1>;
using DeviceBuffer = std::array<wchar_t, kMaximumDeviceUnits + 1>;
using FinalPathBuffer = std::array<wchar_t, SWU_BITMAP_FONT_MAX_PATH_UNITS + kMaximumDeviceUnits + 1>;

static_assert(sizeof(wchar_t) == sizeof(uint16_t), "The evidence ABI uses Windows UTF-16 units.");

template <typename T>
struct ComOwner {
    T *value = nullptr;
    ComOwner() = default;
    ComOwner(const ComOwner &) = delete;
    ComOwner &operator=(const ComOwner &) = delete;
    ~ComOwner() {
        if (value != nullptr) {
            value->Release();
        }
    }
};

struct ModuleOwner {
    HMODULE value = nullptr;
    ModuleOwner() = default;
    ModuleOwner(const ModuleOwner &) = delete;
    ModuleOwner &operator=(const ModuleOwner &) = delete;
    ~ModuleOwner() {
        if (value != nullptr) {
            FreeLibrary(value);
        }
    }
};

struct FindOwner {
    HANDLE value = INVALID_HANDLE_VALUE;
    FindOwner() = default;
    FindOwner(const FindOwner &) = delete;
    FindOwner &operator=(const FindOwner &) = delete;
    ~FindOwner() {
        if (value != INVALID_HANDLE_VALUE && value != nullptr) {
            FindClose(value);
        }
    }
};

void stopFile(
    SWU_BitmapFontFileEvidenceV2 &out,
    uint32_t status,
    uint32_t operation,
    uint32_t domain = SWU_BITMAP_FONT_CODE_NONE,
    int32_t code = 0
) {
    out.status = status;
    out.operation = operation;
    out.code_domain = domain;
    out.has_code = domain == SWU_BITMAP_FONT_CODE_NONE ? 0 : 1;
    out.code = domain == SWU_BITMAP_FONT_CODE_NONE ? 0 : code;
    out.has_sha256 = 0;
    std::memset(out.sha256, 0, sizeof(out.sha256));
    if (out.reference_status != SWU_BITMAP_FONT_STATUS_OBSERVED) {
        out.reference_status = status;
        out.scope = SWU_BITMAP_FONT_SCOPE_NONE;
        out.basename_length = 0;
        std::memset(out.basename, 0, sizeof(out.basename));
    }
}

void stopHRESULT(SWU_BitmapFontFileEvidenceV2 &out, uint32_t operation, HRESULT error) {
    stopFile(out, SWU_BITMAP_FONT_STATUS_FAILED, operation, SWU_BITMAP_FONT_CODE_HRESULT,
             static_cast<int32_t>(error));
}

void stopWin32(SWU_BitmapFontFileEvidenceV2 &out, uint32_t operation, DWORD error) {
    // Do not invent an API error code when a provider left LastError unset.
    stopFile(out, SWU_BITMAP_FONT_STATUS_FAILED, operation,
             error == ERROR_SUCCESS ? SWU_BITMAP_FONT_CODE_NONE : SWU_BITMAP_FONT_CODE_WIN32,
             static_cast<int32_t>(error));
}

bool sameText(const wchar_t *left, size_t leftLength, const wchar_t *right, size_t rightLength) {
    return leftLength == rightLength
        && CompareStringOrdinal(left, static_cast<int>(leftLength), right,
                                static_cast<int>(rightLength), TRUE) == CSTR_EQUAL;
}

bool asciiLetter(uint32_t value) {
    return (value >= 'A' && value <= 'Z') || (value >= 'a' && value <= 'z');
}

bool validAxisTag(uint32_t tag) {
    // DWRITE_MAKE_FONT_AXIS_TAG stores the first character in the low byte.
    // OpenType tags start with a letter; subsequent characters are letters,
    // digits, or trailing spaces. Private tags need not be registered here.
    if (!asciiLetter(tag & 0xff)) {
        return false;
    }
    bool trailingSpaces = false;
    for (unsigned shift = 8; shift < 32; shift += 8) {
        const uint32_t value = (tag >> shift) & 0xff;
        if (value == ' ') {
            trailingSpaces = true;
        } else if (trailingSpaces || (!asciiLetter(value) && (value < '0' || value > '9'))) {
            return false;
        }
    }
    return true;
}

bool forbiddenControl(uint32_t scalar) {
    // Keep metadata free of C0/C1 controls and Unicode format controls, including
    // bidi overrides and invisible tag characters. No path text is emitted.
    return scalar < 0x20 || (scalar >= 0x7f && scalar <= 0x9f)
        || scalar == 0xad || (scalar >= 0x600 && scalar <= 0x605)
        || scalar == 0x61c || scalar == 0x6dd || scalar == 0x70f
        || (scalar >= 0x890 && scalar <= 0x891) || scalar == 0x8e2
        || scalar == 0x180e || (scalar >= 0x200b && scalar <= 0x200f)
        || (scalar >= 0x2028 && scalar <= 0x202e)
        || (scalar >= 0x2060 && scalar <= 0x206f) || scalar == 0xfeff
        || (scalar >= 0xfff9 && scalar <= 0xfffb)
        || scalar == 0x110bd || scalar == 0x110cd
        || (scalar >= 0x13430 && scalar <= 0x1343f)
        || scalar == 0xe0001 || (scalar >= 0xe0020 && scalar <= 0xe007f);
}

bool validUTF16(const wchar_t *value, size_t length) {
    for (size_t index = 0; index < length; ++index) {
        uint32_t scalar = static_cast<uint16_t>(value[index]);
        if (scalar >= 0xd800 && scalar <= 0xdbff) {
            if (++index == length) {
                return false;
            }
            const uint32_t low = static_cast<uint16_t>(value[index]);
            if (low < 0xdc00 || low > 0xdfff) {
                return false;
            }
            scalar = 0x10000 + ((scalar - 0xd800) << 10) + low - 0xdc00;
        } else if (scalar >= 0xdc00 && scalar <= 0xdfff) {
            return false;
        }
        if (forbiddenControl(scalar) || (scalar >= 0xfdd0 && scalar <= 0xfdef)
            || (scalar & 0xffff) >= 0xfffe) {
            return false;
        }
    }
    return true;
}

bool reservedComponent(const wchar_t *value, size_t length) {
    size_t stemLength = 0;
    while (stemLength < length && value[stemLength] != L'.') {
        ++stemLength;
    }
    if (sameText(value, stemLength, L"CON", 3) || sameText(value, stemLength, L"PRN", 3)
        || sameText(value, stemLength, L"AUX", 3) || sameText(value, stemLength, L"NUL", 3)
        || sameText(value, stemLength, L"CLOCK$", 6) || sameText(value, stemLength, L"CONIN$", 6)
        || sameText(value, stemLength, L"CONOUT$", 7)) {
        return true;
    }
    if (stemLength != 4 || (!sameText(value, 3, L"COM", 3) && !sameText(value, 3, L"LPT", 3))) {
        return false;
    }
    const wchar_t digit = value[3];
    return (digit >= L'1' && digit <= L'9') || digit == 0xb9 || digit == 0xb2 || digit == 0xb3;
}

bool validComponent(const wchar_t *value, size_t length) {
    if (length == 0 || length > SWU_BITMAP_FONT_MAX_BASENAME_UNITS
        || value[length - 1] == L'.' || value[length - 1] == L' '
        || reservedComponent(value, length)) {
        return false;
    }
    size_t stemLength = 0;
    while (stemLength < length && value[stemLength] != L'.') {
        ++stemLength;
    }
    if (stemLength > 0 && value[stemLength - 1] == L' ') {
        return false;
    }
    for (size_t index = 0; index < length; ++index) {
        const wchar_t unit = value[index];
        if (unit == L':' || unit == L'/' || unit == L'\\' || unit == L'"'
            || unit == L'<' || unit == L'>' || unit == L'|' || unit == L'?'
            || unit == L'*' || unit == L'~'
            || (unit == L'.' && index + 1 < length && value[index + 1] == L'.')) {
            return false;
        }
    }
    return true;
}

bool validAbsolutePath(const wchar_t *path, size_t length, size_t *basenameOffset = nullptr) {
    if (length <= 3 || length > SWU_BITMAP_FONT_MAX_PATH_UNITS || !asciiLetter(path[0])
        || path[1] != L':' || path[2] != L'\\' || !validUTF16(path, length)) {
        return false;
    }
    size_t start = 3;
    for (size_t index = start; index <= length; ++index) {
        if (index == length || path[index] == L'\\') {
            if (!validComponent(path + start, index - start)) {
                return false;
            }
            if (basenameOffset != nullptr) {
                *basenameOffset = start;
            }
            start = index + 1;
        }
    }
    return true;
}

bool validFontBasename(const wchar_t *basename, size_t length) {
    if (!validComponent(basename, length) || length < 5 || basename[0] == L'.') {
        return false;
    }
    return sameText(basename + length - 4, 4, L".ttf", 4)
        || sameText(basename + length - 4, 4, L".otf", 4)
        || sameText(basename + length - 4, 4, L".ttc", 4);
}

bool appendPath(PathBuffer &buffer, size_t &length, const wchar_t *suffix, size_t suffixLength) {
    if (length + suffixLength > SWU_BITMAP_FONT_MAX_PATH_UNITS) {
        return false;
    }
    std::memcpy(buffer.data() + length, suffix, suffixLength * sizeof(wchar_t));
    length += suffixLength;
    buffer[length] = L'\0';
    return true;
}

bool approvedScope(
    const PathBuffer &path,
    size_t basenameOffset,
    uint32_t &scope,
    SWU_BitmapFontFileEvidenceV2 &out
) {
    // These roots come from the OS, never environment variables or report input.
    // Known-folder discovery is lazy, after the local-loader interface gate.
    PathBuffer systemPath{};
    const UINT systemLength = GetSystemWindowsDirectoryW(systemPath.data(), static_cast<UINT>(systemPath.size()));
    DWORD systemError = ERROR_SUCCESS;
    if (systemLength == 0) {
        systemError = GetLastError();
    }
    size_t systemRootLength = systemLength;
    const bool systemRootValid = systemLength > 0 && systemLength < systemPath.size()
        && validAbsolutePath(systemPath.data(), systemLength)
        && appendPath(systemPath, systemRootLength, L"\\Fonts", 6);
    if (systemRootValid && sameText(path.data(), basenameOffset - 1, systemPath.data(), systemRootLength)) {
        scope = SWU_BITMAP_FONT_SCOPE_SYSTEM_FONTS;
        return true;
    }

    ModuleOwner shell;
    shell.value = LoadLibraryExW(L"shell32.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (shell.value == nullptr) {
        stopWin32(out, SWU_BITMAP_FONT_OPERATION_VALIDATE_LOCAL_PATH, GetLastError());
        return false;
    }
    ModuleOwner ole;
    ole.value = LoadLibraryExW(L"ole32.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (ole.value == nullptr) {
        stopWin32(out, SWU_BITMAP_FONT_OPERATION_VALIDATE_LOCAL_PATH, GetLastError());
        return false;
    }
    const auto getKnownFolderPath = reinterpret_cast<decltype(&SHGetKnownFolderPath)>(
        GetProcAddress(shell.value, "SHGetKnownFolderPath"));
    if (getKnownFolderPath == nullptr) {
        stopWin32(out, SWU_BITMAP_FONT_OPERATION_VALIDATE_LOCAL_PATH, GetLastError());
        return false;
    }
    const auto freeTaskMemory = reinterpret_cast<decltype(&CoTaskMemFree)>(GetProcAddress(ole.value, "CoTaskMemFree"));
    if (freeTaskMemory == nullptr) {
        stopWin32(out, SWU_BITMAP_FONT_OPERATION_VALIDATE_LOCAL_PATH, GetLastError());
        return false;
    }
    // FOLDERID_LocalAppData from the SDK, expressed locally to avoid a GUID library dependency.
    const GUID localAppData = {0xf1b32785, 0x6fba, 0x4fcf, {0x9d, 0x55, 0x7b, 0x8e, 0x7f, 0x15, 0x70, 0x91}};
    PWSTR allocatedPath = nullptr;
    const HRESULT result = getKnownFolderPath(localAppData, KF_FLAG_DONT_VERIFY, nullptr, &allocatedPath);
    PathBuffer userPath{};
    size_t userLength = 0;
    if (SUCCEEDED(result) && allocatedPath != nullptr) {
        while (userLength <= SWU_BITMAP_FONT_MAX_PATH_UNITS && allocatedPath[userLength] != L'\0') {
            ++userLength;
        }
        if (userLength <= SWU_BITMAP_FONT_MAX_PATH_UNITS) {
            std::memcpy(userPath.data(), allocatedPath, (userLength + 1) * sizeof(wchar_t));
        }
    }
    // SHGetKnownFolderPath requires freeing nonnull output even after failure.
    if (allocatedPath != nullptr) {
        freeTaskMemory(allocatedPath);
    }
    if (FAILED(result)) {
        stopHRESULT(out, SWU_BITMAP_FONT_OPERATION_VALIDATE_LOCAL_PATH, result);
        return false;
    }
    if (userLength == 0 || userLength > SWU_BITMAP_FONT_MAX_PATH_UNITS
        || !validAbsolutePath(userPath.data(), userLength)) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_INVALID_VALUE, SWU_BITMAP_FONT_OPERATION_VALIDATE_LOCAL_PATH);
        return false;
    }
    if (!appendPath(userPath, userLength, L"\\Microsoft\\Windows\\Fonts", 24)) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_LIMIT_EXCEEDED, SWU_BITMAP_FONT_OPERATION_VALIDATE_LOCAL_PATH);
        return false;
    }
    if (sameText(path.data(), basenameOffset - 1, userPath.data(), userLength)) {
        scope = SWU_BITMAP_FONT_SCOPE_USER_FONTS;
        return true;
    }
    if (!systemRootValid) {
        if (systemError != ERROR_SUCCESS) {
            stopWin32(out, SWU_BITMAP_FONT_OPERATION_VALIDATE_LOCAL_PATH, systemError);
        } else {
            stopFile(out, SWU_BITMAP_FONT_STATUS_UNAVAILABLE, SWU_BITMAP_FONT_OPERATION_VALIDATE_LOCAL_PATH);
        }
    } else {
        stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, SWU_BITMAP_FONT_OPERATION_VALIDATE_LOCAL_PATH);
    }
    return false;
}

bool currentFixedDevice(
    const PathBuffer &path,
    DeviceBuffer &device,
    size_t &deviceLength,
    SWU_BitmapFontFileEvidenceV2 &out,
    uint32_t operation
) {
    const wchar_t root[] = {path[0], L':', L'\\', L'\0'};
    const wchar_t drive[] = {path[0], L':', L'\0'};
    if (GetDriveTypeW(root) != DRIVE_FIXED) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, operation);
        return false;
    }
    PathBuffer mappings{};
    const DWORD count = QueryDosDeviceW(drive, mappings.data(), static_cast<DWORD>(mappings.size()));
    if (count == 0) {
        stopWin32(out, operation, GetLastError());
        return false;
    }
    size_t length = 0;
    while (length < count && length < mappings.size() && mappings[length] != L'\0') {
        ++length;
    }
    // Only the FIRST MULTI_SZ entry is the current mapping. This deliberately
    // narrower policy rejects SUBST, UNC, and other device aliases, even when
    // GetDriveType reports fixed storage. Old undeleted mappings are not used.
    constexpr wchar_t prefix[] = L"\\Device\\HarddiskVolume";
    constexpr size_t prefixLength = sizeof(prefix) / sizeof(wchar_t) - 1;
    bool allowed = length > prefixLength && length <= kMaximumDeviceUnits
        && length < count && length < mappings.size()
        && sameText(mappings.data(), prefixLength, prefix, prefixLength);
    for (size_t index = prefixLength; allowed && index < length; ++index) {
        allowed = mappings[index] >= L'0' && mappings[index] <= L'9';
    }
    if (!allowed) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, operation);
        return false;
    }
    std::memcpy(device.data(), mappings.data(), length * sizeof(wchar_t));
    device[length] = L'\0';
    deviceLength = length;
    return true;
}

struct FileSnapshot {
    FILE_BASIC_INFO basic{};
    FILE_STANDARD_INFO standard{};
    FILE_ID_INFO identity{};
    FILE_ATTRIBUTE_TAG_INFO tag{};
    FILE_CASE_SENSITIVE_INFO caseSensitivity{};
};

struct HeldObject {
    HANDLE handle = INVALID_HANDLE_VALUE;
    size_t prefixLength = 0;
    bool directory = false;
    FileSnapshot before{};
    HeldObject() = default;
    HeldObject(const HeldObject &) = delete;
    HeldObject &operator=(const HeldObject &) = delete;
    ~HeldObject() {
        if (handle != INVALID_HANDLE_VALUE && handle != nullptr) {
            CloseHandle(handle);
        }
    }
};

bool inspectHandle(
    HANDLE handle,
    bool directory,
    FileSnapshot &snapshot,
    SWU_BitmapFontFileEvidenceV2 &out,
    uint32_t operation
) {
    SetLastError(ERROR_SUCCESS);
    const DWORD type = GetFileType(handle);
    if (type != FILE_TYPE_DISK) {
        const DWORD error = GetLastError();
        if (type == FILE_TYPE_UNKNOWN && error != ERROR_SUCCESS) {
            stopWin32(out, operation, error);
        } else {
            stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, operation);
        }
        return false;
    }
    if (!GetFileInformationByHandleEx(handle, FileBasicInfo, &snapshot.basic, sizeof(snapshot.basic))
        || !GetFileInformationByHandleEx(handle, FileStandardInfo, &snapshot.standard, sizeof(snapshot.standard))
        || !GetFileInformationByHandleEx(handle, FileIdInfo, &snapshot.identity, sizeof(snapshot.identity))
        || !GetFileInformationByHandleEx(handle, FileAttributeTagInfo, &snapshot.tag, sizeof(snapshot.tag))) {
        stopWin32(out, operation, GetLastError());
        return false;
    }
    // In these information classes 0x40000 means FILE_ATTRIBUTE_EA, not
    // RECALL_ON_OPEN (which is defined only for directory enumeration).
    constexpr DWORD deniedAttributes = FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_OFFLINE
        | FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS | FILE_ATTRIBUTE_DEVICE;
    if ((snapshot.basic.FileAttributes & deniedAttributes) != 0
        || (snapshot.tag.FileAttributes & deniedAttributes) != 0
        || snapshot.standard.DeletePending || (snapshot.standard.Directory != FALSE) != directory
        || ((snapshot.basic.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) != directory
        || snapshot.standard.EndOfFile.QuadPart < 0 || snapshot.standard.NumberOfLinks == 0) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, operation);
        return false;
    }
    if (directory) {
        // A case-only sibling can differ on case-sensitive NTFS. Reject that
        // mode (and an unsupported query) rather than treating ordinal text
        // comparison as proof that the OS-known directory is the same object.
        if (!GetFileInformationByHandleEx(handle, FileCaseSensitiveInfo, &snapshot.caseSensitivity,
                                         sizeof(snapshot.caseSensitivity))) {
            stopWin32(out, operation, GetLastError());
            return false;
        }
        if (snapshot.caseSensitivity.Flags != 0) {
            stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, operation);
            return false;
        }
    }
    return true;
}

bool sameSnapshot(const FileSnapshot &left, const FileSnapshot &right) {
    // LastAccessTime can change because of this observation. Compare fields,
    // not structure padding. Hard links are allowed; their count must stay
    // stable, and the held file denies ordinary data writes/delete sharing.
    // ReparseTag is unused for the nonreparse objects accepted above; MS-FSCC
    // 2.4.6 requires ignoring it when FILE_ATTRIBUTE_REPARSE_POINT is absent.
    return left.identity.VolumeSerialNumber == right.identity.VolumeSerialNumber
        && std::memcmp(left.identity.FileId.Identifier, right.identity.FileId.Identifier,
                       sizeof(left.identity.FileId.Identifier)) == 0
        && left.basic.CreationTime.QuadPart == right.basic.CreationTime.QuadPart
        && left.basic.LastWriteTime.QuadPart == right.basic.LastWriteTime.QuadPart
        && left.basic.ChangeTime.QuadPart == right.basic.ChangeTime.QuadPart
        && left.basic.FileAttributes == right.basic.FileAttributes
        && left.standard.AllocationSize.QuadPart == right.standard.AllocationSize.QuadPart
        && left.standard.EndOfFile.QuadPart == right.standard.EndOfFile.QuadPart
        && left.standard.NumberOfLinks == right.standard.NumberOfLinks
        && left.standard.DeletePending == right.standard.DeletePending
        && left.standard.Directory == right.standard.Directory
        && left.tag.FileAttributes == right.tag.FileAttributes
        && left.caseSensitivity.Flags == right.caseSensitivity.Flags;
}

bool inspectDirectoryEntry(
    const PathBuffer &prefix,
    size_t prefixLength,
    bool directory,
    SWU_BitmapFontFileEvidenceV2 &out,
    uint32_t operation
) {
    if (prefixLength == 3) {
        // The drive root is the already-approved physical volume root, not a
        // child placeholder. FindFirstFileEx does not accept a root directory.
        return true;
    }
#if defined(FIND_FIRST_EX_ON_DISK_ENTRIES_ONLY)
    WIN32_FIND_DATAW data{};
    FindOwner search;
    // One exact entry, no wildcard or FindNextFile traversal. The caller has
    // retained and checked its parent. Unlike BasicInfo/TagInfo, enumeration
    // attributes give RECALL_ON_OPEN its documented meaning (not EA).
    search.value = FindFirstFileExW(prefix.data(), FindExInfoBasic, &data,
        FindExSearchNameMatch, nullptr, FIND_FIRST_EX_ON_DISK_ENTRIES_ONLY);
    if (search.value == INVALID_HANDLE_VALUE || search.value == nullptr) {
        stopWin32(out, operation, GetLastError());
        return false;
    }
    size_t nameLength = 0;
    while (nameLength < MAX_PATH && data.cFileName[nameLength] != L'\0') {
        ++nameLength;
    }
    size_t componentOffset = prefixLength;
    while (componentOffset > 3 && prefix[componentOffset - 1] != L'\\') {
        --componentOffset;
    }
    constexpr DWORD deniedAttributes = FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_OFFLINE
        | FILE_ATTRIBUTE_RECALL_ON_OPEN | FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS | FILE_ATTRIBUTE_DEVICE;
    if (nameLength == MAX_PATH || !validUTF16(data.cFileName, nameLength)
        || !sameText(data.cFileName, nameLength, prefix.data() + componentOffset, prefixLength - componentOffset)
        || (data.dwFileAttributes & deniedAttributes) != 0
        || ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) != directory) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, operation);
        return false;
    }
    // Enumeration can lag metadata updates; it is only a preflight. Handle
    // attributes, identity, and times are checked after opening and after use.
    return true;
#else
    stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_IMPLEMENTED, operation);
    return false;
#endif
}

struct LocalFileGuard {
    PathBuffer path{};
    DeviceBuffer device{};
    size_t deviceLength = 0;
    std::array<HeldObject, kMaximumHeldObjects> held{};
    size_t count = 0;

    bool checkFinalPath(const HeldObject &object, SWU_BitmapFontFileEvidenceV2 &out, uint32_t operation) const {
        FinalPathBuffer finalPath{};
        const DWORD length = GetFinalPathNameByHandleW(object.handle, finalPath.data(),
            static_cast<DWORD>(finalPath.size()), FILE_NAME_NORMALIZED | VOLUME_NAME_NT);
        if (length == 0) {
            stopWin32(out, operation, GetLastError());
            return false;
        }
        const size_t suffixLength = object.prefixLength - 2;
        FinalPathBuffer expected{};
        std::memcpy(expected.data(), device.data(), deviceLength * sizeof(wchar_t));
        std::memcpy(expected.data() + deviceLength, path.data() + 2, suffixLength * sizeof(wchar_t));
        const size_t expectedLength = deviceLength + suffixLength;
        if (length >= finalPath.size() || finalPath[length] != L'\0'
            || !sameText(finalPath.data(), length, expected.data(), expectedLength)) {
            stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, operation);
            return false;
        }
        return true;
    }

    bool open(const PathBuffer &source, size_t length, SWU_BitmapFontFileEvidenceV2 &out) {
        path = source;
        if (!currentFixedDevice(path, device, deviceLength, out, SWU_BITMAP_FONT_OPERATION_VALIDATE_LOCAL_PATH)) {
            return false;
        }
        size_t prefixLength = 3;
        while (true) {
            if (count == held.size()) {
                stopFile(out, SWU_BITMAP_FONT_STATUS_LIMIT_EXCEEDED, SWU_BITMAP_FONT_OPERATION_OPEN_LOCAL_FILE);
                return false;
            }
            PathBuffer prefix = path;
            prefix[prefixLength] = L'\0';
            HeldObject &object = held[count++];
            object.prefixLength = prefixLength;
            object.directory = prefixLength != length;
            if (!inspectDirectoryEntry(prefix, prefixLength, object.directory, out,
                                       SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE)) {
                return false;
            }
            constexpr DWORD flags = FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT
                | FILE_FLAG_OPEN_NO_RECALL;
            HeldObject probe;
            probe.prefixLength = object.prefixLength;
            probe.directory = object.directory;
            probe.handle = CreateFileW(prefix.data(), FILE_READ_ATTRIBUTES, FILE_SHARE_READ, nullptr,
                                      OPEN_EXISTING, flags, nullptr);
            if (probe.handle == INVALID_HANDLE_VALUE || probe.handle == nullptr) {
                stopWin32(out, SWU_BITMAP_FONT_OPERATION_OPEN_LOCAL_FILE, GetLastError());
                return false;
            }
            if (!inspectHandle(probe.handle, probe.directory, probe.before, out,
                               SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE)
                || !checkFinalPath(probe, out, SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE)) {
                return false;
            }
            // Attribute-only opens do NOT enforce read/write/delete sharing
            // conflicts (MS-FSA 2.1.5.1.2.2). Reopen the same inspected object
            // with actual read/list access, denying ordinary writers/deleters.
            // No ReadFile or directory-content read is performed on this handle.
            // The probe remains alive until identity/metadata have been checked
            // again; never broaden sharing or fall back after an open failure.
            const DWORD readAccess = object.directory ? FILE_LIST_DIRECTORY : FILE_READ_DATA;
            object.handle = ReOpenFile(probe.handle, FILE_READ_ATTRIBUTES | readAccess, FILE_SHARE_READ, flags);
            if (object.handle == INVALID_HANDLE_VALUE || object.handle == nullptr) {
                stopWin32(out, SWU_BITMAP_FONT_OPERATION_OPEN_LOCAL_FILE, GetLastError());
                return false;
            }
            if (!inspectHandle(object.handle, object.directory, object.before, out,
                               SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE)
                || !checkFinalPath(object, out, SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE)) {
                return false;
            }
            if (!sameSnapshot(probe.before, object.before)) {
                stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE);
                return false;
            }
            if (prefixLength == length) {
                break;
            }
            size_t next = prefixLength == 3 ? 3 : prefixLength + 1;
            while (next < length && path[next] != L'\\') {
                ++next;
            }
            prefixLength = next;
        }
        return checkMapping(out, SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE);
    }

    bool checkMapping(SWU_BitmapFontFileEvidenceV2 &out, uint32_t operation) const {
        DeviceBuffer current{};
        size_t currentLength = 0;
        if (!currentFixedDevice(path, current, currentLength, out, operation)) {
            return false;
        }
        if (!sameText(device.data(), deviceLength, current.data(), currentLength)) {
            stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, operation);
            return false;
        }
        return true;
    }

    bool verifyAfter(SWU_BitmapFontFileEvidenceV2 &out) const {
        constexpr uint32_t operation = SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE_AFTER;
        for (size_t index = 0; index < count; ++index) {
            const HeldObject &object = held[index];
            PathBuffer prefix = path;
            prefix[object.prefixLength] = L'\0';
            if (!inspectDirectoryEntry(prefix, object.prefixLength, object.directory, out, operation)) {
                return false;
            }
            FileSnapshot after{};
            if (!inspectHandle(object.handle, object.directory, after, out, operation)
                || !checkFinalPath(object, out, operation)) {
                return false;
            }
            if (!sameSnapshot(object.before, after)) {
                stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, operation);
                return false;
            }
        }
        return checkMapping(out, operation);
    }

    const FileSnapshot &fileSnapshot() const {
        return held[count - 1].before;
    }
};

struct Sha256 {
    ModuleOwner module;
    decltype(&BCryptOpenAlgorithmProvider) openAlgorithm = nullptr;
    decltype(&BCryptCloseAlgorithmProvider) closeAlgorithm = nullptr;
    decltype(&BCryptGetProperty) getProperty = nullptr;
    decltype(&BCryptCreateHash) createHash = nullptr;
    decltype(&BCryptDestroyHash) destroyHash = nullptr;
    decltype(&BCryptHashData) hashData = nullptr;
    decltype(&BCryptFinishHash) finishHash = nullptr;
    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;

    ~Sha256() {
        // Includes nonnull outputs from failed initialization calls. Function
        // pointers and their module remain alive through both cleanup calls.
        if (hash != nullptr && destroyHash != nullptr) {
            destroyHash(hash);
        }
        if (algorithm != nullptr && closeAlgorithm != nullptr) {
            closeAlgorithm(algorithm, 0);
        }
    }

    bool initialize(SWU_BitmapFontFileEvidenceV2 &out) {
        constexpr uint32_t operation = SWU_BITMAP_FONT_OPERATION_INITIALIZE_SHA256;
        module.value = LoadLibraryExW(L"bcrypt.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
        if (module.value == nullptr) {
            stopWin32(out, operation, GetLastError());
            return false;
        }
#define SWU_LOAD_BCRYPT(member, symbol) \
        member = reinterpret_cast<decltype(member)>(GetProcAddress(module.value, #symbol)); \
        if (member == nullptr) { stopWin32(out, operation, GetLastError()); return false; }
        SWU_LOAD_BCRYPT(openAlgorithm, BCryptOpenAlgorithmProvider)
        SWU_LOAD_BCRYPT(closeAlgorithm, BCryptCloseAlgorithmProvider)
        SWU_LOAD_BCRYPT(getProperty, BCryptGetProperty)
        SWU_LOAD_BCRYPT(createHash, BCryptCreateHash)
        SWU_LOAD_BCRYPT(destroyHash, BCryptDestroyHash)
        SWU_LOAD_BCRYPT(hashData, BCryptHashData)
        SWU_LOAD_BCRYPT(finishHash, BCryptFinishHash)
#undef SWU_LOAD_BCRYPT
        NTSTATUS result = openAlgorithm(&algorithm, BCRYPT_SHA256_ALGORITHM, MS_PRIMITIVE_PROVIDER, 0);
        if (result < 0) {
            stopFile(out, SWU_BITMAP_FONT_STATUS_FAILED, operation, SWU_BITMAP_FONT_CODE_NTSTATUS,
                     static_cast<int32_t>(result));
            return false;
        }
        if (algorithm == nullptr) {
            stopFile(out, SWU_BITMAP_FONT_STATUS_INVALID_VALUE, operation);
            return false;
        }
        ULONG digestLength = 0;
        ULONG propertyLength = 0;
        result = getProperty(algorithm, BCRYPT_HASH_LENGTH, reinterpret_cast<PUCHAR>(&digestLength),
                             sizeof(digestLength), &propertyLength, 0);
        if (result < 0) {
            stopFile(out, SWU_BITMAP_FONT_STATUS_FAILED, operation, SWU_BITMAP_FONT_CODE_NTSTATUS,
                     static_cast<int32_t>(result));
            return false;
        }
        if (propertyLength != sizeof(digestLength) || digestLength != 32) {
            stopFile(out, SWU_BITMAP_FONT_STATUS_INVALID_VALUE, operation);
            return false;
        }
        // Windows 7+ CNG owns this bounded provider's hash object allocation;
        // BCryptDestroyHash releases it. No full font buffer is allocated.
        result = createHash(algorithm, &hash, nullptr, 0, nullptr, 0, 0);
        if (result < 0) {
            stopFile(out, SWU_BITMAP_FONT_STATUS_FAILED, operation, SWU_BITMAP_FONT_CODE_NTSTATUS,
                     static_cast<int32_t>(result));
            return false;
        }
        if (hash == nullptr) {
            stopFile(out, SWU_BITMAP_FONT_STATUS_INVALID_VALUE, operation);
            return false;
        }
        return true;
    }
};

struct FragmentLease {
    IDWriteFontFileStream *stream;
    void *context;
    bool acquired;
    ~FragmentLease() {
        if (acquired) {
            // A successful call may legitimately return a null context.
            stream->ReleaseFileFragment(context);
        }
    }
};

uint64_t fileTimeValue(const FILETIME &value) {
    return (static_cast<uint64_t>(value.dwHighDateTime) << 32) | value.dwLowDateTime;
}

void observeFile(IDWriteFontFile *file, uint64_t remainingBytes, SWU_BitmapFontFileEvidenceV2 &out) {
    // The outer GetFiles owner retains every file until this function returns;
    // the key is borrowed from that retained file and is never copied/output.
    const void *key = nullptr;
    UINT32 keyLength = 0;
    HRESULT result = file->GetReferenceKey(&key, &keyLength);
    if (FAILED(result)) {
        stopHRESULT(out, SWU_BITMAP_FONT_OPERATION_GET_REFERENCE_KEY, result);
        return;
    }
    if (keyLength > SWU_BITMAP_FONT_MAX_REFERENCE_KEY_BYTES) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_LIMIT_EXCEEDED, SWU_BITMAP_FONT_OPERATION_GET_REFERENCE_KEY);
        return;
    }
    if (key == nullptr || keyLength == 0) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_INVALID_VALUE, SWU_BITMAP_FONT_OPERATION_GET_REFERENCE_KEY);
        return;
    }
    ComOwner<IDWriteFontFileLoader> loader;
    result = file->GetLoader(&loader.value);
    if (FAILED(result)) {
        stopHRESULT(out, SWU_BITMAP_FONT_OPERATION_GET_LOADER, result);
        return;
    }
    if (loader.value == nullptr) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_INVALID_VALUE, SWU_BITMAP_FONT_OPERATION_GET_LOADER);
        return;
    }
    // Reject a remote interface even if an object also claims the local one.
    // No directory discovery, stream creation, or GetFileSize precedes this gate.
    ComOwner<IDWriteRemoteFontFileLoader> remote;
    result = loader.value->QueryInterface(__uuidof(IDWriteRemoteFontFileLoader),
                                         reinterpret_cast<void **>(&remote.value));
    if (SUCCEEDED(result)) {
        stopFile(out, remote.value == nullptr ? SWU_BITMAP_FONT_STATUS_INVALID_VALUE
                                            : SWU_BITMAP_FONT_STATUS_NONLOCAL_OR_CUSTOM,
                 SWU_BITMAP_FONT_OPERATION_QUERY_LOCAL_LOADER);
        return;
    }
    if (result != E_NOINTERFACE) {
        stopHRESULT(out, SWU_BITMAP_FONT_OPERATION_QUERY_LOCAL_LOADER, result);
        return;
    }
    if (remote.value != nullptr) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_INVALID_VALUE, SWU_BITMAP_FONT_OPERATION_QUERY_LOCAL_LOADER,
                 SWU_BITMAP_FONT_CODE_HRESULT, static_cast<int32_t>(result));
        return;
    }
    ComOwner<IDWriteLocalFontFileLoader> local;
    result = loader.value->QueryInterface(__uuidof(IDWriteLocalFontFileLoader),
                                         reinterpret_cast<void **>(&local.value));
    if (FAILED(result)) {
        stopFile(out, result == E_NOINTERFACE ? SWU_BITMAP_FONT_STATUS_NONLOCAL_OR_CUSTOM
                                            : SWU_BITMAP_FONT_STATUS_FAILED,
                 SWU_BITMAP_FONT_OPERATION_QUERY_LOCAL_LOADER, SWU_BITMAP_FONT_CODE_HRESULT,
                 static_cast<int32_t>(result));
        return;
    }
    if (local.value == nullptr) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_INVALID_VALUE, SWU_BITMAP_FONT_OPERATION_QUERY_LOCAL_LOADER);
        return;
    }
    // The SDK documents IDWriteLocalFontFileLoader as DirectWrite's built-in
    // local-file loader. This classifies that supported interface, not hostile
    // in-process COM code impersonating an IID. In particular, arbitrary custom
    // and remote loaders are not probed with CreateStreamFromKey/GetFileSize.
    UINT32 pathLength = 0;
    result = local.value->GetFilePathLengthFromKey(key, keyLength, &pathLength);
    if (FAILED(result)) {
        stopHRESULT(out, SWU_BITMAP_FONT_OPERATION_GET_LOCAL_PATH, result);
        return;
    }
    if (pathLength > SWU_BITMAP_FONT_MAX_PATH_UNITS) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_LIMIT_EXCEEDED, SWU_BITMAP_FONT_OPERATION_GET_LOCAL_PATH);
        return;
    }
    if (pathLength == 0) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_INVALID_VALUE, SWU_BITMAP_FONT_OPERATION_GET_LOCAL_PATH);
        return;
    }
    PathBuffer path;
    path.fill(static_cast<wchar_t>(0xffff));
    result = local.value->GetFilePathFromKey(key, keyLength, path.data(), pathLength + 1);
    if (FAILED(result)) {
        stopHRESULT(out, SWU_BITMAP_FONT_OPERATION_GET_LOCAL_PATH, result);
        return;
    }
    size_t basenameOffset = 0;
    if (path[pathLength] != L'\0' || !validAbsolutePath(path.data(), pathLength, &basenameOffset)
        || !validFontBasename(path.data() + basenameOffset, pathLength - basenameOffset)) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, SWU_BITMAP_FONT_OPERATION_VALIDATE_LOCAL_PATH);
        return;
    }
    uint32_t scope = SWU_BITMAP_FONT_SCOPE_NONE;
    if (!approvedScope(path, basenameOffset, scope, out)) {
        return;
    }
    LocalFileGuard guard;
    if (!guard.open(path, pathLength, out)) {
        return;
    }
    out.reference_status = SWU_BITMAP_FONT_STATUS_OBSERVED;
    out.scope = scope;
    out.basename_length = static_cast<uint32_t>(pathLength - basenameOffset);
    for (uint32_t index = 0; index < out.basename_length; ++index) {
        out.basename[index] = static_cast<uint16_t>(path[basenameOffset + index]);
    }
    const FileSnapshot &before = guard.fileSnapshot();
    FILETIME keyWriteTime{};
    result = local.value->GetLastWriteTimeFromKey(key, keyLength, &keyWriteTime);
    if (FAILED(result)) {
        stopHRESULT(out, SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE, result);
        return;
    }
    if (fileTimeValue(keyWriteTime) != static_cast<uint64_t>(before.basic.LastWriteTime.QuadPart)) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE);
        return;
    }
    if (static_cast<uint64_t>(before.standard.EndOfFile.QuadPart) > kMaximumFileBytes
        || static_cast<uint64_t>(before.standard.EndOfFile.QuadPart) > remainingBytes) {
        // This is held-file metadata, not an observed COM stream length.
        stopFile(out, SWU_BITMAP_FONT_STATUS_LIMIT_EXCEEDED, SWU_BITMAP_FONT_OPERATION_CHECK_BYTE_BUDGET);
        return;
    }

    ComOwner<IDWriteFontFileStream> stream;
    result = loader.value->CreateStreamFromKey(key, keyLength, &stream.value);
    if (FAILED(result)) {
        stopHRESULT(out, SWU_BITMAP_FONT_OPERATION_CREATE_STREAM, result);
        return;
    }
    if (stream.value == nullptr) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_INVALID_VALUE, SWU_BITMAP_FONT_OPERATION_CREATE_STREAM);
        return;
    }
    UINT64 streamLength = 0;
    result = stream.value->GetFileSize(&streamLength);
    if (FAILED(result)) {
        stopHRESULT(out, SWU_BITMAP_FONT_OPERATION_GET_STREAM_SIZE, result);
        return;
    }
    out.has_stream_length = 1;
    out.stream_length = streamLength;
    if (streamLength == 0) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_INVALID_VALUE, SWU_BITMAP_FONT_OPERATION_GET_STREAM_SIZE);
        return;
    }
    if (streamLength > kMaximumFileBytes || streamLength > remainingBytes) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_LIMIT_EXCEEDED, SWU_BITMAP_FONT_OPERATION_CHECK_BYTE_BUDGET);
        return;
    }
    if (streamLength != static_cast<uint64_t>(before.standard.EndOfFile.QuadPart)) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_INVALID_VALUE, SWU_BITMAP_FONT_OPERATION_GET_STREAM_SIZE);
        return;
    }
    Sha256 sha;
    if (!sha.initialize(out)) {
        return;
    }
    uint64_t offset = 0;
    while (offset < streamLength) {
        const uint64_t available = streamLength - offset;
        const uint64_t amount = available < SWU_BITMAP_FONT_FRAGMENT_BYTES ? available : SWU_BITMAP_FONT_FRAGMENT_BYTES;
        if (amount > remainingBytes - out.requested_bytes) {
            stopFile(out, SWU_BITMAP_FONT_STATUS_LIMIT_EXCEEDED, SWU_BITMAP_FONT_OPERATION_CHECK_BYTE_BUDGET);
            return;
        }
        const void *fragment = nullptr;
        void *context = nullptr;
        // Failed attempts consume request budget; no retry refunds or loops.
        out.requested_bytes += amount;
        result = stream.value->ReadFileFragment(&fragment, offset, amount, &context);
        FragmentLease lease{stream.value, context, SUCCEEDED(result) || fragment != nullptr || context != nullptr};
        if (FAILED(result)) {
            stopHRESULT(out, SWU_BITMAP_FONT_OPERATION_READ_STREAM_FRAGMENT, result);
            return;
        }
        if (fragment == nullptr) {
            stopFile(out, SWU_BITMAP_FONT_STATUS_INVALID_VALUE, SWU_BITMAP_FONT_OPERATION_READ_STREAM_FRAGMENT);
            return;
        }
        out.read_bytes += amount;
        // BCryptHashData takes PUCHAR but promises not to modify its input.
        // Hash the borrowed fragment directly, then release it this iteration.
        const NTSTATUS hashResult = sha.hashData(sha.hash,
            const_cast<PUCHAR>(static_cast<const UCHAR *>(fragment)), static_cast<ULONG>(amount), 0);
        if (hashResult < 0) {
            stopFile(out, SWU_BITMAP_FONT_STATUS_FAILED, SWU_BITMAP_FONT_OPERATION_HASH_STREAM_FRAGMENT,
                     SWU_BITMAP_FONT_CODE_NTSTATUS, static_cast<int32_t>(hashResult));
            return;
        }
        offset += amount;
    }
    std::array<UCHAR, 32> digest{};
    const NTSTATUS finishResult = sha.finishHash(sha.hash, digest.data(), static_cast<ULONG>(digest.size()), 0);
    if (finishResult < 0) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_FAILED, SWU_BITMAP_FONT_OPERATION_FINISH_SHA256,
                 SWU_BITMAP_FONT_CODE_NTSTATUS, static_cast<int32_t>(finishResult));
        return;
    }
    UINT64 afterLength = 0;
    result = stream.value->GetFileSize(&afterLength);
    if (FAILED(result)) {
        stopHRESULT(out, SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE_AFTER, result);
        return;
    }
    UINT64 streamWriteTime = 0;
    result = stream.value->GetLastWriteTime(&streamWriteTime);
    if (FAILED(result)) {
        stopHRESULT(out, SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE_AFTER, result);
        return;
    }
    if (afterLength != streamLength || streamWriteTime != fileTimeValue(keyWriteTime)) {
        stopFile(out, SWU_BITMAP_FONT_STATUS_NOT_APPROVED, SWU_BITMAP_FONT_OPERATION_VERIFY_LOCAL_FILE_AFTER);
        return;
    }
    if (!guard.verifyAfter(out)) {
        return;
    }
    // Held handles and metadata checks do not lock DOS-device mappings against
    // temporary/ABA remapping, nor prove a snapshot of earlier rasterization.
    // This SHA describes the associated face-file stream at observation time.
    out.status = SWU_BITMAP_FONT_STATUS_OBSERVED;
    out.operation = SWU_BITMAP_FONT_OPERATION_COMPLETE;
    out.code_domain = SWU_BITMAP_FONT_CODE_NONE;
    out.has_code = 0;
    out.code = 0;
    std::memcpy(out.sha256, digest.data(), digest.size());
    out.has_sha256 = 1;
}

void observeAxes(IDWriteFontFace *face, SWU_BitmapFontFaceEvidenceV2 &out, SWU_BitmapFontAxisValueV2 *axes) {
    ComOwner<IDWriteFontFace5> face5;
    const HRESULT query = face->QueryInterface(__uuidof(IDWriteFontFace5), reinterpret_cast<void **>(&face5.value));
    if (FAILED(query)) {
        out.axes_status = query == E_NOINTERFACE ? SWU_BITMAP_FONT_STATUS_UNAVAILABLE : SWU_BITMAP_FONT_STATUS_FAILED;
        return;
    }
    if (face5.value == nullptr) {
        out.axes_status = SWU_BITMAP_FONT_STATUS_INVALID_VALUE;
        return;
    }
    out.has_variations_value = 1;
    out.has_variations = face5.value->HasVariations() != FALSE ? 1 : 0;
    const UINT32 count = face5.value->GetFontAxisValueCount();
    if (count > SWU_BITMAP_FONT_MAX_AXES) {
        out.axes_status = SWU_BITMAP_FONT_STATUS_LIMIT_EXCEEDED;
        return;
    }
    std::array<DWRITE_FONT_AXIS_VALUE, SWU_BITMAP_FONT_MAX_AXES> values{};
    // Exact count is required by Face5, including the supported-empty case.
    const HRESULT result = face5.value->GetFontAxisValues(values.data(), count);
    if (FAILED(result)) {
        out.axes_status = SWU_BITMAP_FONT_STATUS_FAILED;
        return;
    }
    if (face5.value->GetFontAxisValueCount() != count) {
        out.axes_status = SWU_BITMAP_FONT_STATUS_INVALID_VALUE;
        return;
    }
    for (UINT32 index = 0; index < count; ++index) {
        const uint32_t tag = static_cast<uint32_t>(values[index].axisTag);
        if (!validAxisTag(tag) || !std::isfinite(values[index].value)) {
            out.axes_status = SWU_BITMAP_FONT_STATUS_INVALID_VALUE;
            return;
        }
        for (UINT32 previous = 0; previous < index; ++previous) {
            if (values[previous].axisTag == values[index].axisTag) {
                out.axes_status = SWU_BITMAP_FONT_STATUS_INVALID_VALUE;
                return;
            }
        }
    }
    for (UINT32 index = 0; index < count; ++index) {
        axes[index].tag = static_cast<uint32_t>(values[index].axisTag);
        axes[index].value = values[index].value;
    }
    out.axis_count = count;
    out.axes_status = SWU_BITMAP_FONT_STATUS_OBSERVED;
}

struct FontFilesOwner {
    std::array<IDWriteFontFile *, SWU_BITMAP_FONT_MAX_FILES> values{};
    ~FontFilesOwner() {
        // Release the original slots, even if GetFiles failed or changed its
        // output count. Duplicate pointers each represent an owned output ref.
        for (IDWriteFontFile *file : values) {
            if (file != nullptr) {
                file->Release();
            }
        }
    }
};

} // namespace

extern "C" void SWU_BitmapObserveFontFaceV2(
    void *borrowed_font_face,
    uint64_t remaining_requested_bytes,
    SWU_BitmapFontFaceEvidenceV2 *face_out,
    SWU_BitmapFontAxisValueV2 *axes_out,
    uint32_t axes_capacity,
    SWU_BitmapFontFileEvidenceV2 *files_out,
    uint32_t files_capacity
) {
    if (face_out == nullptr) {
        return;
    }
    *face_out = {};
    face_out->axes_status = SWU_BITMAP_FONT_STATUS_UNAVAILABLE;
    face_out->files_status = SWU_BITMAP_FONT_STATUS_UNAVAILABLE;
    if (axes_out != nullptr && axes_capacity == SWU_BITMAP_FONT_MAX_AXES) {
        std::memset(axes_out, 0, sizeof(*axes_out) * SWU_BITMAP_FONT_MAX_AXES);
    }
    if (files_out != nullptr && files_capacity == SWU_BITMAP_FONT_MAX_FILES) {
        std::memset(files_out, 0, sizeof(*files_out) * SWU_BITMAP_FONT_MAX_FILES);
        for (uint32_t index = 0; index < SWU_BITMAP_FONT_MAX_FILES; ++index) {
            files_out[index].index = index;
            files_out[index].status = SWU_BITMAP_FONT_STATUS_UNAVAILABLE;
            files_out[index].reference_status = SWU_BITMAP_FONT_STATUS_UNAVAILABLE;
        }
    }
    if (borrowed_font_face == nullptr || axes_out == nullptr || files_out == nullptr
        || axes_capacity != SWU_BITMAP_FONT_MAX_AXES || files_capacity != SWU_BITMAP_FONT_MAX_FILES) {
        face_out->axes_status = SWU_BITMAP_FONT_STATUS_INVALID_VALUE;
        face_out->files_status = SWU_BITMAP_FONT_STATUS_INVALID_VALUE;
        return;
    }
    ComOwner<IDWriteFontFace> face;
    face.value = static_cast<IDWriteFontFace *>(borrowed_font_face);
    face.value->AddRef();
    const uint32_t faceType = static_cast<uint32_t>(face.value->GetType());
    if (faceType <= static_cast<uint32_t>(DWRITE_FONT_FACE_TYPE_RAW_CFF)) {
        face_out->face_type = faceType;
        face_out->has_face_type = 1;
    }
    observeAxes(face.value, *face_out, axes_out);
    UINT32 count = 0;
    HRESULT result = face.value->GetFiles(&count, nullptr);
    if (FAILED(result)) {
        face_out->files_status = SWU_BITMAP_FONT_STATUS_FAILED;
        return;
    }
    if (count == 0) {
        face_out->files_status = SWU_BITMAP_FONT_STATUS_INVALID_VALUE;
        return;
    }
    if (count > SWU_BITMAP_FONT_MAX_FILES) {
        face_out->files_status = SWU_BITMAP_FONT_STATUS_LIMIT_EXCEEDED;
        return;
    }
    const UINT32 originalCount = count;
    FontFilesOwner files;
    result = face.value->GetFiles(&count, files.values.data());
    if (FAILED(result)) {
        face_out->files_status = SWU_BITMAP_FONT_STATUS_FAILED;
        return;
    }
    if (count != originalCount) {
        face_out->files_status = SWU_BITMAP_FONT_STATUS_INVALID_VALUE;
        return;
    }
    for (UINT32 index = 0; index < originalCount; ++index) {
        if (files.values[index] == nullptr) {
            face_out->files_status = SWU_BITMAP_FONT_STATUS_INVALID_VALUE;
            return;
        }
    }
    face_out->file_count = originalCount;
    face_out->files_status = SWU_BITMAP_FONT_STATUS_OBSERVED;
    const uint64_t allowance = remaining_requested_bytes < kMaximumSessionBytes
        ? remaining_requested_bytes : kMaximumSessionBytes;
    for (UINT32 index = 0; index < originalCount; ++index) {
        observeFile(files.values[index], allowance - face_out->requested_bytes, files_out[index]);
        face_out->requested_bytes += files_out[index].requested_bytes;
        face_out->read_bytes += files_out[index].read_bytes;
        if (files_out[index].status != SWU_BITMAP_FONT_STATUS_OBSERVED) {
            face_out->files_status = SWU_BITMAP_FONT_STATUS_PARTIAL;
        }
    }
}
