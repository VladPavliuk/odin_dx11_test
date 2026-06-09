// arithmetic.cpp - integer arithmetic and plain function calls
int add(int x, int y) {
    int sum = x + y;
    return sum;
}

int square(int n) {
    int result = n * n;
    return result;
}

int main() {
    int a = 10;
    int b = 32;
    int total = add(a, b);
    int sq = square(total);
    return sq & 0xFF;
}
