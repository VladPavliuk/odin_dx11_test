// stl.cpp - STL containers (vector, string)
#include <vector>
#include <string>

int main() {
    std::vector<int> nums;
    nums.push_back(5);
    nums.push_back(15);
    nums.push_back(25);
    int total = 0;
    for (int n : nums) {
        total += n;
    }
    int count = (int)nums.size();
    std::string greeting = "hello";
    int len = (int)greeting.size();
    return total + count + len;
}
