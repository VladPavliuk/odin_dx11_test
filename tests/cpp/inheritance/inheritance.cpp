// inheritance.cpp - inheritance and virtual dispatch
class Shape {
public:
    virtual int area() { return 0; }
    virtual ~Shape() {}
};

class Square : public Shape {
public:
    int side;
    int area() override { return side * side; }
};

int compute(Shape* s) {
    int a = s->area();
    return a;
}

int main() {
    Square sq;
    sq.side = 9;
    Shape* shape = &sq;
    int result = compute(shape);
    return result;
}
