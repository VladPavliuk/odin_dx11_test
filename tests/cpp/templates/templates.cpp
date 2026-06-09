// templates.cpp - function and class templates
template <typename T>
T maxOf(T a, T b) {
    T result = (a > b) ? a : b;
    return result;
}

template <typename T>
class Box {
public:
    T value;
    T get() { return value; }
};

int main() {
    int m = maxOf(3, 9);
    Box<int> box;
    box.value = 77;
    int v = box.get();
    return m + v;
}
