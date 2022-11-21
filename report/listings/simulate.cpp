#include <iostream>
#include <vector>
#include <algorithm>
#include <numeric>
#include <bitset>
#include <cassert>
#include <tuple>

using namespace std;

typedef unsigned long long Addr;

enum Word { WORD=8, DWORD=16, QWORD=32 };

struct CacheLine {
    const int size;
    bool valid = 0; 
    bool dirty = 0; 
    Addr tag = -1;
    int last_call = 0;
    CacheLine& operator = (CacheLine oth) {
        assert(size == oth.size);
        tie(valid, dirty, tag, last_call) = tie(oth.valid, oth.dirty, oth.tag, oth.last_call);
        return *this;
    }
};

struct CacheSet {
private:
    vector<CacheLine> lines;
    const int line_size;
    int total_mem_pushes = 0;
public:
    CacheSet(int way, int line_size) : line_size(line_size) {
        lines = vector<CacheLine>(way, CacheLine{line_size});
    }

    bool read(Addr tag, int call) {
        auto it = find_by_tag(tag);
        if (it != lines.end()) {
            it->last_call = call;
        } else {
            total_mem_pushes += find_LRO()->dirty;
            *(find_LRO()) = CacheLine {line_size, 1, 0, tag, call};
        }
        return it != lines.end(); 
    }

    void write(Addr tag, int call) {
        auto it = find_by_tag(tag);
        if (it != lines.end()) {
            it->last_call = call;
            it->dirty = 1;
        } else {
            total_mem_pushes += find_LRO()->dirty;
            *(find_LRO()) = CacheLine {line_size, 1, 1, tag, call};
        }
    }

    int getMemPushes() const {
        return total_mem_pushes;
    }

private:
    vector<CacheLine>::iterator find_by_tag(Addr tag) {
        return find_if(lines.begin(), lines.end(), [&] (const CacheLine& line) {
                return line.valid && line.tag == tag;
            }
        );
    }

    vector<CacheLine>::iterator find_LRO() {
        return min_element(lines.begin(), lines.end(), [] (const CacheLine& a, const CacheLine& b) {
            return tie(a.valid, a.last_call) < tie(b.valid, b.last_call);
        });
    }
};


struct Cache { 
private:
    const int sets_cnt;
    const int way;
    const int line_size;        // byte
    const int data_bus_size;    // bits
    const int mem_size;         // byte

    int total_hits = 0;
    int total_misses = 0;
    int total_time = 0;
    int calls = 0;

    vector<CacheSet> sets;

    struct InnerAddr {
        Addr tag, set, offset;
    };
public:
    Cache(int sets_cnt, int way, int line_size, int data_bus_size, int mem_size) :
        sets_cnt(sets_cnt), way(way), line_size(line_size), data_bus_size(data_bus_size), mem_size(mem_size) {
        sets = vector<CacheSet>(sets_cnt, CacheSet(way, line_size));
    }

    void read(Word word, Addr addr) {
        calls++;
        auto [tag, set, offset] = split_addr(addr); 
        if (sets[set].read(tag, calls)) {
            total_hits++;
            total_time += 6; // Cache lag
            total_time += transfer_lag(word); // Cache -> Cpu
        } else {
            total_misses++;
            total_time += 4 + 100; // Cache + Mem lag
            total_time += transfer_lag(WORD * line_size); // Mem -> Cache
            total_time += transfer_lag(word); // Cache -> Cpu
        }
    };

    void write(Word word, Addr addr) {
        calls++;
        auto [tag, set, offset] = split_addr(addr); 
        if (sets[set].read(tag, calls)) {
            total_hits++;
            total_time += 6; // Cache lag 
            total_time += 1; // Cache->Cpu response
        } else {
            total_misses++;
            total_time += 4 + 100; // Cache + Mem lag
            total_time += transfer_lag(WORD * line_size); // Mem -> Cache
            total_time += 1;  // Cache -> Cpu response
        }
        sets[set].write(tag, calls);
    };

    int get_hits() const  {
        return total_hits;
    }

    int get_misses() const {
        return total_misses;
    }

    int get_time() const {
        int total_pushes = accumulate(sets.begin(), sets.end(), 0,
            [] (int acc, const CacheSet& el) {
                return acc + el.getMemPushes();
            }
        );
        return total_time + total_pushes * transfer_lag(WORD * line_size);
    }

private:
    InnerAddr split_addr(Addr addr) const {
        return {
            (addr & ((mem_size - 1) & ~(sets_cnt * line_size - 1))) / (sets_cnt * line_size),
            (addr & (sets_cnt - 1) * line_size) / line_size ,
            addr & (line_size - 1)
        };
    }

    int transfer_lag(int data) const {
        return (data + data_bus_size - 1) / data_bus_size;
    }

};

struct PseudoAllocator {
    Addr last_allocated_addr = 0;
    
    Addr allocate(int n, int m, int elem_sz) {
        int res = last_allocated_addr;
        last_allocated_addr += n * m * elem_sz;
        return res;
    }
};

int main() {
    // 512Kb == [0x00000...0x7ffff]
    Cache cache(32, 2, 16, 16, 512 * 1024);
    PseudoAllocator alloc;

    const int M = 64;
    const int N = 60;
    const int K = 32;

    int8_t*  a = (int8_t*) alloc.allocate(M, K, sizeof(int8_t));  // a[M][K];
    int16_t* b = (int16_t*)alloc.allocate(K, N, sizeof(int16_t)); // b[K][N];
    int32_t* c = (int32_t*)alloc.allocate(M, N, sizeof(int32_t)); // c[M][N];

    for (int y = 0; y < M; y++) {
        for (int x = 0; x < N; x++) {
            int16_t* pb = b;
            for (int k = 0; k < K; k++) {
                cache.read(WORD, (Addr) (a + k));
                cache.read(DWORD, (Addr) (pb + x));
                pb += N;
            }
            cache.write(QWORD, (Addr) (c + x));
        }
        a += K;
        c += N;
    }

    cout << "HITS: " << cache.get_hits() << "\nMISSES: " << cache.get_misses() << "\nTOTAL TIME: " << cache.get_time() << endl;
    cout << "RATE: " << 1.0 * (cache.get_hits()) / (cache.get_hits() + cache.get_misses()) << endl;

    return 0;
}
