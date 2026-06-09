package tests

// Tests for the "basic feature" additions to the debugger: registers, memory read/write, set-variable,
// run-to-line, and single-instruction stepping. All driven headlessly (see debug_driver.odin) against
// the arithmetic fixture. Run with ODIN_TEST_THREADS=1 (shared global debugger state).

import "core:testing"

import main "../"

// Registers are captured at a stop and update after execution advances.
@(test)
registers_captured_and_change_on_step :: proc(t: ^testing.T) {
    defer dbgStop()
    exe, src := fixturePaths("arithmetic")

    dbgSetBreakpoint(src, 3) // int sum = x + y;  (inside add)
    dbgStart(exe)
    testing.expect(t, dbgWaitStop(), "should stop in add()")

    r0 := dbgRegisters()
    testing.expect(t, r0.rip != 0, "rip should be captured")
    testing.expect(t, r0.rsp != 0, "rsp should be captured")

    testing.expect(t, dbgResume(.STEP_OVER), "step over to the next line")
    r1 := dbgRegisters()
    testing.expect(t, r1.rip != r0.rip, "rip should change after stepping")
}

// Read a local's memory, write it, read it back, and confirm the new value drives execution.
@(test)
memory_read_write_and_set_variable :: proc(t: ^testing.T) {
    defer dbgStop()
    exe, src := fixturePaths("arithmetic")

    dbgSetBreakpoint(src, 3) // int sum = x + y;  (x == 10 here)
    dbgStart(exe)
    testing.expect(t, dbgWaitStop(), "should stop in add()")

    addr, size, ok := dbgLocalAddress("x")
    testing.expect(t, ok, "x should have a frame-relative address")
    testing.expect_value(t, size, u32(4)) // int

    buf: [4]u8
    n, rok := main.readDebuggerMemory(addr, buf[:])
    testing.expect(t, rok && n == 4, "should read 4 bytes of x")
    testing.expect_value(t, transmute(i32)buf, i32(10))

    testing.expect(t, main.writeDebuggerInt(addr, 99, 4), "should write x")
    _, rok2 := main.readDebuggerMemory(addr, buf[:])
    testing.expect(t, rok2, "should re-read x")
    testing.expect_value(t, transmute(i32)buf, i32(99))

    // The write must actually affect execution: sum = x + y = 99 + 32.
    testing.expect(t, dbgResume(.STEP_OVER), "step over the addition")
    testing.expect_value(t, dbgLine(), i32(4))
    sum, sok := dbgLocalInt("sum"); testing.expect(t, sok, "sum readable"); testing.expect_value(t, sum, i64(131))
}

// Single-instruction stepping advances rip one machine instruction at a time.
@(test)
step_one_instruction :: proc(t: ^testing.T) {
    defer dbgStop()
    exe, src := fixturePaths("arithmetic")

    dbgSetBreakpoint(src, 3)
    dbgStart(exe)
    testing.expect(t, dbgWaitStop(), "should stop in add()")

    rip0 := dbgRegisters().rip
    testing.expect(t, dbgResume(.STEP_INSTRUCTION), "step one instruction")
    rip1 := dbgRegisters().rip
    testing.expect(t, rip1 != rip0, "rip should advance after one instruction")

    testing.expect(t, dbgResume(.STEP_INSTRUCTION), "step another instruction")
    rip2 := dbgRegisters().rip
    testing.expect(t, rip2 != rip1, "rip should advance again")
}

// Run-to-line plants a one-shot breakpoint and runs there (over the intervening call).
@(test)
run_to_line :: proc(t: ^testing.T) {
    defer dbgStop()
    exe, src := fixturePaths("arithmetic")

    dbgSetBreakpoint(src, 13) // int a = 10;  (in main)
    dbgStart(exe)
    testing.expect(t, dbgWaitStop(), "should stop at main:13")
    testing.expect_value(t, dbgLine(), i32(13))

    testing.expect(t, dbgRunTo(src, 16), "run to main:16")
    testing.expect_value(t, dbgLine(), i32(16)) // int sq = square(total);
    total, ok := dbgLocalInt("total"); testing.expect(t, ok, "total readable"); testing.expect_value(t, total, i64(42)) // add(10, 32)
}
