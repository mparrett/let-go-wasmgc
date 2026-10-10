// host/wat-asm: wasm-tools' text parser (the `wat` crate) as a 500 KB wasm
// module a page can call, so the browser demo assembles the WAT the carried
// compiler emits without a server (D206's fallback, taken 2026-10-10: wabt.js
// cannot parse `rec` type groups). Four exports and no imports, no WASI, no
// bindgen: alloc_bytes(n) gives n bytes to write the text into; parse(ptr,
// len) answers 1 with the binary or -1 with the error text, either read back
// through out_ptr()/out_len() until the next parse; free_bytes returns the
// text's buffer. Built by host/build-wat-asm.sh.
static mut OUT: Vec<u8> = Vec::new();

fn set_out(v: Vec<u8>) {
    unsafe { *(&raw mut OUT) = v; }
}

#[no_mangle]
pub extern "C" fn alloc_bytes(n: usize) -> *mut u8 {
    let mut v: Vec<u8> = Vec::with_capacity(n.max(1));
    let p = v.as_mut_ptr();
    std::mem::forget(v);
    p
}

#[no_mangle]
pub extern "C" fn free_bytes(p: *mut u8, n: usize) {
    unsafe { drop(Vec::from_raw_parts(p, 0, n.max(1))); }
}

#[no_mangle]
pub extern "C" fn parse(ptr: *const u8, len: usize) -> i32 {
    let bytes = unsafe { std::slice::from_raw_parts(ptr, len) };
    let text = match std::str::from_utf8(bytes) {
        Ok(t) => t,
        Err(e) => { set_out(e.to_string().into_bytes()); return -1; }
    };
    match wat::parse_str(text) {
        Ok(b) => { set_out(b); 1 }
        // the message names the line and column and quotes the offending
        // text, as `wasm-tools parse` prints it (parse_str attaches the text)
        Err(e) => { set_out(e.to_string().into_bytes()); -1 }
    }
}

#[no_mangle]
pub extern "C" fn out_ptr() -> *const u8 { unsafe { (*(&raw const OUT)).as_ptr() } }

#[no_mangle]
pub extern "C" fn out_len() -> usize { unsafe { (*(&raw const OUT)).len() } }
