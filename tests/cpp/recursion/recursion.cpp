// recursion.cpp - recursion, exercises a deep call stack
int factorial(int n) {
    if (n <= 1) {
        return 1;
    }
    int sub = factorial(n - 1);
    return n * sub;
}

int main() {
    int f = factorial(5);
    return f & 0xFF;
}
