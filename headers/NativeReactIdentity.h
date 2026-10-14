#pragma once

#include <atomic>
#include <cstdint>

class NativeReactIdentity
{
public:
    NativeReactIdentity(int64_t tag, uint64_t generation)
        : tag_(tag), generation_(generation) {}

    int64_t tag(void) const { return tag_; }
    uint64_t generation(void) const { return generation_; }
    bool active(void) const { return active_.load(); }
    bool valid(int64_t tag, uint64_t generation) const
    {
        return active() && tag_ > 0 && tag_ == tag && generation_ == generation;
    }
    void invalidate(void) { active_.store(false); }

private:
    int64_t tag_ = 0;
    uint64_t generation_ = 0;
    std::atomic_bool active_{true};
};
