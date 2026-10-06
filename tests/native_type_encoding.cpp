#include "NativeTypeEncoding.h"

#include <cassert>
#include <string>

int main()
{
    assert(normalizedType(nullptr) == '\0');
    assert(normalizedType("rnNoORV@") == '@');
    assert(nativeFFITypeName("v") == "void");
    assert(nativeFFITypeName("r@") == "object");
    assert(nativeFFITypeName("#") == "class");
    assert(nativeFFITypeName(":") == "selector");
    assert(nativeFFITypeName("^v") == "pointer");
    assert(nativeFFITypeName("q") == "i64");
    assert(nativeFFITypeName("Q") == "u64");
    assert(nativeFFITypeName("{CGRect={CGPoint=dd}{CGSize=dd}}") == "struct:CGRect");
    assert(nativeFFITypeName("r{_NSRange=QQ}") == "struct:NSRange");
    assert(nativeFFITypeName("{UIEdgeInsets=dddd}") == "struct:UIEdgeInsets");
    assert(nativeFFITypeName("{Unknown=CGRect}").empty());
    assert(nativeFFITypeName("{Unknown=dd}").empty());
    assert(nativeFFITypeName("(Union=ii)").empty());
    assert(nativeFFITypeName("b8").empty());

    for (int index = 0; index < 10000; index++)
    {
        std::string malformed = "{Unknown" + std::to_string(index) + "=CGRect}";
        assert(nativeFFITypeName(malformed.c_str()).empty());
    }
}
