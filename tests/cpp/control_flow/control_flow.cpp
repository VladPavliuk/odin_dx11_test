// control_flow.cpp - if/else branches and loops
int classify(int n) {
    int category = 0;
    if (n < 0) {
        category = -1;
    } else if (n == 0) {
        category = 0;
    } else {
        category = 1;
    }
    return category;
}

int sumTo(int n) {
    int sum = 0;
    for (int i = 1; i <= n; i++) {
        sum += i;
    }
    return sum;
}

int main() {
    int c = classify(7);
    int s = sumTo(5);
    int total = c + s;
    return total;
}
