extern fn imprt() void;

export const exprt = &imprt;

export const hello_world: [*:0]const u8 = "Hello, World!";

export fn add(a: i32, b: i32) i32 {
    return a +% b;
}

export fn dumb_is_prime(n: u32) bool {
    return n == 2 or n == 3 or n == 5 or n == 7;
}

export fn is_prime(n: u32) bool {
    if (n <= 1) return false;

    var i: u32 = 2;
    while (i < n) : (i += 1) {
        if (n % i == 0) {
            return false;
        }
    }

    return true;
}
