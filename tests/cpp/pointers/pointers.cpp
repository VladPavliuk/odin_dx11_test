// pointers.cpp - pointers, references and arrays
int main() {
    int value = 100;
    int* ptr = &value;
    *ptr = 250;
    int& ref = value;
    ref = 7;
    int arr[4] = {10, 20, 30, 40};
    int sum = 0;
    for (int i = 0; i < 4; i++) {
        sum += arr[i];
    }
    int viaPtr = *ptr;
    return sum + viaPtr;
}
