#include "NativeTypeEncoding.h"

#include <cstring>
#include <string_view>

static const char *unqualifiedType(const char *encoding)
{
    if (!encoding)
    {
        return "";
    }

    while (*encoding && std::strchr("rnNoORV", *encoding))
    {
        encoding++;
    }
    return encoding;
}

char normalizedType(const char *encoding)
{
    return *unqualifiedType(encoding);
}

std::string nativeFFITypeName(const char *encoding)
{
    const char *type = unqualifiedType(encoding);
    switch (*type)
    {
        case 'v': return "void";
        case '@': return "object";
        case '#': return "class";
        case ':': return "selector";
        case '^':
        case '*': return "pointer";
        case 'B': return "bool";
        case 'c': return "i8";
        case 'C': return "u8";
        case 's': return "i16";
        case 'S': return "u16";
        case 'i': return "i32";
        case 'I': return "u32";
        case 'l':
        case 'q': return "i64";
        case 'L':
        case 'Q': return "u64";
        case 'f': return "float";
        case 'd': return "double";
        case '{': break;
        default: return {};
    }

    const char *separator = std::strchr(type + 1, '=');
    if (!separator)
    {
        return {};
    }
    std::string_view name(type + 1, separator - type - 1);
    if (name == "_NSRange" || name == "NSRange") return "struct:NSRange";
    if (name == "CGRect" || name == "_CGRect") return "struct:CGRect";
    if (name == "CGPoint" || name == "_CGPoint") return "struct:CGPoint";
    if (name == "CGSize" || name == "_CGSize") return "struct:CGSize";
    if (name == "UIEdgeInsets" || name == "_UIEdgeInsets") return "struct:UIEdgeInsets";
    if (name == "CGAffineTransform" || name == "_CGAffineTransform") return "struct:CGAffineTransform";
    return {};
}
