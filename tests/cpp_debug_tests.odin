package tests

// Debug-operation tests against the C++ fixtures in tests/cpp (built by tests/cpp/compile.bat).
// Each test drives the real debugger core headlessly (see debug_driver.odin) - set breakpoints, run,
// inspect locals / call stack, step - so it exercises the same paths the editor uses, without a window.

import "core:testing"
import "core:strings"

import main "../"

// arithmetic.cpp: breakpoint inside a callee, read parameters/locals, step over, step out.
@(test)
arithmetic_step_and_locals :: proc(t: ^testing.T) {
    defer dbgStop()
    exe, src := fixturePaths("arithmetic")

    dbgSetBreakpoint(src, 3) // int sum = x + y;  (inside add)
    dbgStart(exe)
    testing.expect(t, dbgWaitStop(), "should stop at the breakpoint in add()")

    testing.expect_value(t, dbgLine(), i32(3))
    testing.expect(t, strings.contains(dbgTopFrame(), "add"), "top frame should be add")

    x, xok := dbgLocalInt("x"); testing.expect(t, xok, "x readable"); testing.expect_value(t, x, i64(10))
    y, yok := dbgLocalInt("y"); testing.expect(t, yok, "y readable"); testing.expect_value(t, y, i64(32))

    testing.expect(t, dbgResume(.STEP_OVER), "step over to next line")
    testing.expect_value(t, dbgLine(), i32(4)) // return sum;
    sum, sok := dbgLocalInt("sum"); testing.expect(t, sok, "sum readable"); testing.expect_value(t, sum, i64(42))

    testing.expect(t, dbgResume(.STEP_OUT), "step out back to main")
    testing.expect(t, strings.contains(dbgTopFrame(), "main"), "back in main after step out")
}

// control_flow.cpp: branch result and a loop accumulator across two functions.
@(test)
control_flow_branches_and_loops :: proc(t: ^testing.T) {
    defer dbgStop()
    exe, src := fixturePaths("control_flow")

    dbgSetBreakpoint(src, 11) // return category;  (classify)
    dbgSetBreakpoint(src, 19) // return sum;        (sumTo)
    dbgStart(exe)

    testing.expect(t, dbgWaitStop(), "stop in classify")
    testing.expect_value(t, dbgLine(), i32(11))
    testing.expect(t, strings.contains(dbgTopFrame(), "classify"), "top frame classify")
    cat, cok := dbgLocalInt("category"); testing.expect(t, cok, "category readable"); testing.expect_value(t, cat, i64(1))

    testing.expect(t, dbgResume(.CONTINUE), "continue to sumTo")
    testing.expect_value(t, dbgLine(), i32(19))
    testing.expect(t, strings.contains(dbgTopFrame(), "sumTo"), "top frame sumTo")
    sum, sok := dbgLocalInt("sum"); testing.expect(t, sok, "sum readable"); testing.expect_value(t, sum, i64(15)) // 1+2+3+4+5
}

// recursion.cpp: the base case is reached with the recursive frames stacked up.
@(test)
recursion_call_stack_depth :: proc(t: ^testing.T) {
    defer dbgStop()
    exe, src := fixturePaths("recursion")

    dbgSetBreakpoint(src, 4) // return 1;  (factorial base case, n == 1)
    dbgStart(exe)
    testing.expect(t, dbgWaitStop(), "stop at factorial base case")

    testing.expect_value(t, dbgLine(), i32(4))
    n, nok := dbgLocalInt("n"); testing.expect(t, nok, "n readable"); testing.expect_value(t, n, i64(1))
    // factorial(5)->(4)->(3)->(2)->(1) are all on the stack at the base case.
    testing.expect_value(t, dbgFramesNamed("factorial"), 5)
}

// structs.cpp: a value computed from struct members, plus a member function call.
@(test)
structs_members_and_method :: proc(t: ^testing.T) {
    defer dbgStop()
    exe, src := fixturePaths("structs")

    dbgSetBreakpoint(src, 25) // int area = r.area();  (in main, after dist2)
    dbgSetBreakpoint(src, 12) // int a = width * height;  (in Rect::area)
    dbgStart(exe)

    testing.expect(t, dbgWaitStop(), "stop in main before the area() call")
    testing.expect_value(t, dbgLine(), i32(25))
    d, dok := dbgLocalInt("dist2"); testing.expect(t, dok, "dist2 readable"); testing.expect_value(t, d, i64(25)) // 3*3+4*4

    testing.expect(t, dbgResume(.CONTINUE), "continue into Rect::area")
    testing.expect_value(t, dbgLine(), i32(12))
    testing.expect(t, strings.contains(dbgTopFrame(), "area"), "top frame is Rect::area")

    testing.expect(t, dbgResume(.STEP_OVER), "step over the member computation")
    testing.expect_value(t, dbgLine(), i32(13))
    a, aok := dbgLocalInt("a"); testing.expect(t, aok, "a readable"); testing.expect_value(t, a, i64(30)) // 5*6
}

// pointers.cpp: a value mutated through a pointer and a reference, plus an array-sum loop.
@(test)
pointers_refs_and_arrays :: proc(t: ^testing.T) {
    defer dbgStop()
    exe, src := fixturePaths("pointers")

    dbgSetBreakpoint(src, 13) // int viaPtr = *ptr;  (after the loop)
    dbgStart(exe)
    testing.expect(t, dbgWaitStop(), "stop after the array loop")

    testing.expect_value(t, dbgLine(), i32(13))
    sum, sok := dbgLocalInt("sum"); testing.expect(t, sok, "sum readable"); testing.expect_value(t, sum, i64(100)) // 10+20+30+40
    val, vok := dbgLocalInt("value"); testing.expect(t, vok, "value readable"); testing.expect_value(t, val, i64(7)) // set via reference

    testing.expect(t, dbgResume(.STEP_OVER), "step over viaPtr assignment")
    testing.expect_value(t, dbgLine(), i32(14))
    viaPtr, pok := dbgLocalInt("viaPtr"); testing.expect(t, pok, "viaPtr readable"); testing.expect_value(t, viaPtr, i64(7))
}

// templates.cpp: a function template instantiated for int.
@(test)
templates_function_instantiation :: proc(t: ^testing.T) {
    defer dbgStop()
    exe, src := fixturePaths("templates")

    dbgSetBreakpoint(src, 4) // T result = (a > b) ? a : b;  (maxOf<int>)
    dbgStart(exe)
    testing.expect(t, dbgWaitStop(), "stop inside maxOf<int>")

    testing.expect_value(t, dbgLine(), i32(4))
    testing.expect(t, strings.contains(dbgTopFrame(), "maxOf"), "top frame is maxOf")
    a, aok := dbgLocalInt("a"); testing.expect(t, aok, "a readable"); testing.expect_value(t, a, i64(3))
    b, bok := dbgLocalInt("b"); testing.expect(t, bok, "b readable"); testing.expect_value(t, b, i64(9))

    testing.expect(t, dbgResume(.STEP_OVER), "step over the comparison")
    testing.expect_value(t, dbgLine(), i32(5))
    result, rok := dbgLocalInt("result"); testing.expect(t, rok, "result readable"); testing.expect_value(t, result, i64(9))
}

// stl.cpp: stop after summing a std::vector (run over the STL calls at full speed to get there).
@(test)
stl_vector_sum :: proc(t: ^testing.T) {
    defer dbgStop()
    exe, src := fixturePaths("stl")

    dbgSetBreakpoint(src, 14) // int count = (int)nums.size();  (after the range-for sum)
    dbgStart(exe)
    testing.expect(t, dbgWaitStop(), "stop after the vector sum loop")

    testing.expect_value(t, dbgLine(), i32(14))
    testing.expect(t, strings.contains(dbgTopFrame(), "main"), "top frame main")
    total, tok := dbgLocalInt("total"); testing.expect(t, tok, "total readable"); testing.expect_value(t, total, i64(45)) // 5+15+25
}

// inheritance.cpp: stepping into a virtual call lands in the derived override, and the result proves it.
@(test)
inheritance_virtual_dispatch :: proc(t: ^testing.T) {
    defer dbgStop()
    exe, src := fixturePaths("inheritance")

    dbgSetBreakpoint(src, 15) // int a = s->area();  (in compute, before the virtual call)
    dbgSetBreakpoint(src, 16) // return a;           (in compute, after it)
    dbgStart(exe)

    testing.expect(t, dbgWaitStop(), "stop in compute()")
    testing.expect_value(t, dbgLine(), i32(15))
    testing.expect(t, strings.contains(dbgTopFrame(), "compute"), "top frame compute")

    testing.expect(t, dbgResume(.STEP_INTO), "step into the virtual call")
    testing.expect(t, strings.contains(dbgTopFrame(), "area"), "virtual dispatch lands in Square::area")

    testing.expect(t, dbgResume(.STEP_OUT), "step back out to compute")
    testing.expect(t, dbgResume(.CONTINUE), "continue to 'return a'")
    testing.expect_value(t, dbgLine(), i32(16))
    a, aok := dbgLocalInt("a"); testing.expect(t, aok, "a readable"); testing.expect_value(t, a, i64(81)) // 9*9 -> Square::area, not Shape::area (0)
}
