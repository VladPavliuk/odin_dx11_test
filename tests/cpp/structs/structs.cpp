// structs.cpp - structs, classes and member functions
struct Point {
    int x;
    int y;
};

class Rect {
public:
    int width;
    int height;
    int area() {
        int a = width * height;
        return a;
    }
};

int main() {
    Point p;
    p.x = 3;
    p.y = 4;
    int dist2 = p.x * p.x + p.y * p.y;
    Rect r;
    r.width = 5;
    r.height = 6;
    int area = r.area();
    return dist2 + area;
}
