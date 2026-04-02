extern fn imprt() void;

export const exprt = &imprt;

export const hello_world: [*:0]const u8 = "Hello, World!";

export fn add(a: i32, b: i32) i32 {
    return a +% b;
}
